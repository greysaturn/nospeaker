import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
func touch(_ id: Int32, _ x: Double, _ y: Double = 0.5) -> InstrumentContact {
    InstrumentContact(id: id, x: x, y: y)
}
func frame(_ time: Double, _ contacts: [InstrumentContact]) -> InstrumentFrame {
    InstrumentFrame(time: time, contacts: contacts)
}

var engine = InstrumentEngine()
engine.accept(frame(0, [touch(17, 0.3)]))
check(engine.held[17]?.kind == .string, "First finger must be string")
let initialHz = engine.held[17]!.frequency
engine.accept(frame(0.01, [touch(4, 0.8), touch(17, 0.3)]))
check(engine.held[4]?.kind == .drum, "Second finger must be drum")
check(engine.drumHits == 1, "Touch-down produces one hit")
let mixed = engine.mix(at: 0.01)
check(mixed.tones.count >= 5, "String harmonics and drum partials must coexist")
check(mixed.level > 0 && mixed.level <= 1, "Mixed level must be bounded")
engine.accept(frame(0.04, [touch(17, 0.33), touch(4, 0.2)]))
check(engine.held[17]?.kind == .string && engine.held[4]?.kind == .drum, "Crossing fingers cannot swap roles")
check(engine.held[17]!.frequency > initialHz, "Rock right raises pitch")
engine.accept(frame(0.08, [touch(4, 0.2), touch(17, 0.27)]))
check(engine.held[17]!.frequency < initialHz, "Rock left lowers pitch")
check(abs(engine.held[17]!.bendCents) <= 75, "Vibrato must remain bounded")
check(engine.drumHits == 1, "Moving or holding drum must not retrigger")
engine.accept(frame(0.1, [touch(4, 0.2)]))
check(engine.held[4]?.kind == .drum, "Lifting string must not promote drum")
check(engine.tails.contains { $0.kind == .string }, "String should release smoothly")
engine.accept(frame(0.11, [touch(4, 0.2), touch(8, 0.6)]))
check(engine.held[8]?.kind == .string, "New contact fills vacant string role")
engine.accept(frame(0.12, [touch(8, 0.6)]))
engine.accept(frame(0.13, [touch(4, 0.7), touch(8, 0.6)]))
check(engine.drumHits == 2, "Lift/re-tap must retrigger even when driver reuses ID")
engine.accept(frame(0.14, []))
engine.prune(at: 1)
check(engine.mix(at: 1).tones.isEmpty, "All voices must finish after release")

var quickTap = InstrumentEngine()
quickTap.accept(frame(0, [touch(1, 0.5)]))
quickTap.accept(frame(0.002, [touch(1, 0.5), touch(2, 0.6)]))
quickTap.accept(frame(0.004, [touch(1, 0.5)]))
check(quickTap.drumHits == 1 && quickTap.tails.count == 1, "A tap between synthesis ticks must survive")
check(quickTap.mix(at: 0.01).tones.count >= 5, "A released quick drum tap must still sound")

var simultaneous = InstrumentEngine()
simultaneous.accept(frame(0, [touch(100, 0.8), touch(99, 0.2)]))
check(simultaneous.held[99]?.kind == .string, "Same-frame touches use deterministic leftmost assignment")
simultaneous.accept(frame(0.01, (0..<11).map { touch(Int32($0), Double($0) / 11) }))
check(simultaneous.touchCount == 11 && simultaneous.peakTouches == 11, "Track eleven distinct contacts")
let many = simultaneous.mix(at: 0.02)
check(many.level <= 1 && many.tones.allSatisfy { $0.hz.isFinite && (100...4000).contains($0.hz) && $0.amp > 0 }, "Polyphony must stay finite and bounded")
simultaneous.accept(frame(0.03, [touch(9, .nan), touch(10, .infinity), touch(11, -1)]))
check(simultaneous.touchCount == 0, "Malformed driver coordinates must be rejected")
simultaneous.reset()
check(simultaneous.held.isEmpty && simultaneous.tails.isEmpty, "Reset clears all sounding voices")
check(simultaneous.peakTouches == 11, "Reset retains observed diagnostic peak")

var still = InstrumentEngine()
still.accept(frame(0, [touch(1, 0.5)]))
still.accept(frame(2, [touch(1, 0.5)]))
check(still.held[1]?.bendCents == 0, "Stationary finger must not generate automatic vibrato")
check(!still.mix(at: 2).tones.isEmpty, "Held string sustains for manual vibrato")
// A held finger can play the full fretboard in either direction.
var fretboard = InstrumentEngine()
fretboard.accept(frame(0, [touch(1, 0.02)]))
fretboard.accept(frame(0.01, [touch(1, 0.02), touch(2, 0.8)]))
var time = 0.1
for index in Array(InstrumentFretboard.notes.indices) + Array(InstrumentFretboard.notes.indices.reversed()) {
    let x = (Double(index) + 0.5) / Double(InstrumentFretboard.notes.count)
    fretboard.accept(frame(time, [touch(2, 0.8), touch(1, x)]))
    check(fretboard.held[1]?.fretIndex == index, "A held finger must select every fret in both directions")
    check(abs(fretboard.held[1]!.baseHz - InstrumentFretboard.frequency(at: index)) < 0.001, "Keep the existing note distribution")
    time += 0.1
}
check(fretboard.drumHits == 1 && fretboard.held[2]?.kind == .drum, "Playing a melody cannot retrigger or reassign the other finger")
check(fretboard.held[1]?.began == 0, "Fret transitions preserve the sustained envelope")
fretboard.accept(frame(time, [touch(1, 1), touch(2, 0.8)]))
check(fretboard.held[1]?.fretIndex == 10, "Right edge selects the highest note")
fretboard.accept(frame(time + 0.1, [touch(1, 0), touch(2, 0.8)]))
check(fretboard.held[1]?.fretIndex == 0, "Left edge selects the lowest note")

// Crossing a nearby zone edge during small vibrato must not select another note.
var boundary = InstrumentEngine()
let boundaryStart = 4.0 / 11 - 0.002
boundary.accept(frame(0, [touch(1, boundaryStart)]))
for (i, delta) in [0.02, -0.02, 0.02, -0.02].enumerated() {
    boundary.accept(frame(Double(i + 1) * 0.04, [touch(1, boundaryStart + delta)]))
    check(boundary.held[1]?.fretIndex == 3, "Rocking across a fret edge must keep the selected note")
    check(delta * boundary.held[1]!.bendCents > 0, "Rocking must bend in the finger's direction")
}
let beforeSlide = boundary.held[1]!.soundingFrequency(at: 0.2)
boundary.accept(frame(0.2, [touch(1, 0.41)]))
let transitioned = boundary.held[1]!
check(transitioned.fretIndex == 4 && transitioned.bendCents == 0, "A wider slide changes fret and recenters vibrato")
check(abs(transitioned.soundingFrequency(at: 0.2) - beforeSlide) < 0.001, "Glide starts at the previous sounding pitch")
check(abs(1200 * log2(transitioned.soundingFrequency(at: 0.35) / transitioned.baseHz)) < 1, "Glide settles without needing another touch frame")
boundary.accept(frame(0.36, [touch(1, 0.43)]))
check(boundary.held[1]!.bendCents > 0 && boundary.held[1]?.fretIndex == 4, "Vibrato works on the newly selected note")
boundary.accept(frame(0.4, [touch(1, 0.39)]))
check(boundary.held[1]!.bendCents < 0 && boundary.held[1]?.fretIndex == 4, "Reverse rocking after sliding keeps the new note")

var kick = InstrumentEngine()
kick.accept(frame(0, [touch(1, 0.5)]))
kick.accept(frame(0, [touch(1, 0.5), touch(2, 0.8, 0.1)]))
let kickVoice = kick.held[2]!
check(kick.mix(at: 0).tones.contains { abs($0.hz - 280) < 0.001 && $0.amp > 0.8 }, "Kick starts with a dominant low attack")
let body = kick.mix(at: 0.1).tones.filter { $0.hz < 150 }
check(body.count == 1 && (100...105).contains(body[0].hz), "Kick quickly settles near its 100 Hz body")
check(kickVoice.amplitude(at: 0.2) > 0.07, "Kick has a longer bass decay")
check(kickVoice.amplitude(at: 0.45) == 0, "Bass tail finishes cleanly")
let beforeMove = kick.mix(at: 0.12)
kick.accept(frame(0.12, [touch(1, 0.5), touch(2, 0.2, 0.9)]))
let afterMove = kick.mix(at: 0.12)
check(beforeMove.tones.map(\.hz) == afterMove.tones.map(\.hz), "Drum movement cannot change its bass tuning")
check(kick.drumHits == 1, "Drum movement cannot retrigger its envelope")

print("Passed \(checks) instrument behavior checks.")
