# Shared-surface instruments

This local extension is based on `os6/nospeaker` commit
`e02a121243f3dbddb288fa6520134b0c4a8727c6`. It adds an opt-in terminal instrument
mode; the original show, speech, and sweep remain available.

## Run

```sh
./build.sh
./nospeaker --instruments
```

Use a terminal at least 80 columns by 24 rows. `--dark` selects a dark background.
`--plain` prints contact counts without shapes. Exit with `q`, Escape, or Ctrl-C
(in plain mode, use Ctrl-C).

Instrument mode applies a 2× output gain to bring up sustained notes and drum
tails for recording, with the final actuator level still capped at 1.0. Peaks
already at the cap cannot get louder. This is an increase in the commanded drive
level, not a measured doubling of acoustic loudness. Restart a running instance
after rebuilding to use the updated level.

1. Place one finger anywhere: a triangle appears at its trackpad position and
   plays a string-like synthesized voice. Horizontal position chooses a note
   from the same G3–D5 layout, now shown as a labeled fretboard. Slide left or
   right while holding to move between notes without lifting.
2. Keep that finger down and rock it gently left and right. Its pitch follows
   your motion, up to 75 cents either way. Repeated rocking produces manual
   vibrato; a stationary finger has no automatic vibrato. Wider slides change
   frets, with a short pitch glide between notes. A boundary buffer preserves
   small rocking movements even when the finger starts near a fret edge.
   The note labels highlight the selected fret; adjacent-note glides settle
   over roughly 60 ms. Sliding preserves the sustained string envelope.
3. Tap another finger anywhere: a circle appears and a drum hit sounds alongside
   the string. Lift and re-tap for another hit. Holding or moving this finger
   does not retrigger it. The kick has the same tuning everywhere on the pad: a
   fast drop from 280 Hz toward a 100 Hz body, with a longer, rounded decay and
   a quiet octave attack. Moving the drum finger does not change its tuning.
4. Each contact keeps its instrument until lifted, even when fingers cross.
   Lifting the string finger does not turn an existing drum into a string; the
   next new contact takes the vacant string role. Additional contacts are drums.

The screen is a map of the whole trackpad. There are no reserved string/drum
zones. If multiple fingers arrive in the same hardware frame, the leftmost
contact becomes the string (contact ID breaks ties). The software cannot know
which physical finger you intend to use after it leaves the surface.

The voice is a harmonic approximation of a plucked string with a quiet sustain,
not a sampled violin or guitar. Strings and drums are mixed into the existing
haptic actuator. They share one vibrating surface, so feedback is not localized
under individual fingers. Real-world timbre, loudness, and multi-tone clarity
still need a hands-on test on the target trackpad.

## How many touches?

**Use 10 simultaneous fingers as the practical design target; raw multitouch
implementations report up to 11 contacts.** That is evidence of capability,
not an Apple guarantee for every MacBook model and macOS release.

- The authors of [Fingerpinger](https://www.anyma.ch/2009/research/multitouch-external-for-maxmsp/)
  report tracking ten or more fingers on MacBook trackpads and expose individual
  identifiers and positions. This is historical hardware evidence, not a test
  of the current Mac.
- IRCAM's [phonos.trackpad](https://github.com/Ircam-RnD/phonos-tilde#phonostrackpad)
  reports support for up to eleven fingers in raw multi-finger mode.
- [Magic Utilities' driver documentation](https://www.magicutilities.net/magic-trackpad/help/scrolling-and-swipes)
  describes a maximum of eleven contacts for Magic Trackpad. This corroborates
  external-trackpad capability, not a specification for every built-in model.
- Apple's [NSTouch documentation](https://developer.apple.com/documentation/appkit/nstouch)
  exposes per-touch identity, phase, and normalized coordinates, without declaring
  a universal maximum number of simultaneous trackpad contacts. Gesture counts
  such as three- and four-finger swipes are not the sensor's maximum contact count.
- Apple's [touch identity documentation](https://developer.apple.com/documentation/appkit/nstouch/identity)
  says an identity is unique during a touch's life but may be reused afterward.

Measure the **observed** count on your Mac with:

```sh
./nospeaker --touch-test
```

This diagnostic does not open or actuate the motor. Spread ten fingertips across
the trackpad and watch the contact IDs and peak count. A peak of ten confirms
that this session observed ten contacts; it does not prove that ten is the maximum.
No hands-on ten-finger measurement was performed during development.

## Architecture and project findings

The original project is a native Swift command-line application. It dynamically
loads the private `MultitouchSupport` framework. `play()` supplies sine-tone
frequencies and normalized strengths to the haptic motor. AVFoundation is used
for speech analysis, while visuals use an 80-by-24 terminal canvas.

The upstream contact callback loops over records but repeatedly overwrites one
`Contact`; consequently, the original instrument only sees the last active
contact. Its pitch follows horizontal position and its automatic 6 Hz vibrato
gets deeper with vertical position.

The original groove uses a kick that drops from 1,000 Hz toward 150 Hz with a
50 ms exponential decay, and a separate bass pattern at 110, 87.31, 130.81, and
98 Hz. The new kick adapts that pitch-dive approach: 280 Hz toward 100 Hz, an
85 ms exponential decay, and a tapered cutoff at 450 ms. Its body stays within
the existing instrument mixer's 100 Hz lower bound. These are synthesis settings;
the perceived bass response still depends on the physical trackpad.

The new implementation adds:

- A bounded queue of complete contact frames, preserving short taps between
  synthesis updates. Queue overflow resets sounding state before consuming the
  newest frames.
- Per-contact ownership using the driver's path identifier at byte 16 in the
  existing 96-byte record layout, rather than array order. State 5 (break-touch)
  releases the new instrument voice immediately.
- A hardware-independent `InstrumentEngine.swift` with role assignment, filtered
  fret transitions with hysteresis, filtered manual pitch bend, short legato
  glides, string harmonics, bass-drum envelopes, and release tails.
- A 10 ms synthesis tick mixing all voices through one call to the existing
  `play()` function. Total output level remains clamped to 1.0; partials remain
  in the project's 100–4,000 Hz working range.
- A triangle/circle terminal canvas and a silent touch-count diagnostic.

The original 96-byte private record format remains a compatibility assumption.
Reference layouts are documented in this [raw multitouch example](https://gist.github.com/rmhsilva/61cc45587ed34707da34818a76476e11).
Finite coordinate checks and a defensive 32-record frame bound reject obvious
bad input; neither proves ABI compatibility. The 32-record bound is not a claim
about hardware capacity. System trackpad gestures also remain enabled, as in the
upstream project, and may interrupt play.

## Validation

```sh
./test.sh
```

Tests cover contact order changes, crossing fingers, retained roles, lift/re-tap,
short drum taps between synthesis ticks, manual vibrato direction and limits,
stationary-finger behavior, traversing every fret in both directions, vibrato
near note boundaries and after slides, glide settling, bass-drum tuning and decay,
release completion, eleven simulated contacts,
malformed coordinates, amplitude/frequency bounds, raw record decoding, callback
queue overflow, and terminal shape rendering. They never actuate the motor.

`build/instruments-preview.txt` contains the generated two-finger canvas fixture.
The build produces a universal Apple Silicon/Intel binary. Compilation and
simulated input validate software behavior; physical sound and actual maximum
contact count require playing the instrument on the intended Mac.

The silent diagnostic was also smoke-tested on the connected `MacBookPro18,3`:
it started tracking and exited cleanly when terminated. No fingers were placed
on the trackpad during that check (observed peak: zero), so this is a startup and
cleanup check only, not a capacity measurement.
