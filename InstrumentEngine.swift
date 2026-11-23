import Foundation

/// A contact ID lasts until lift-off; array order is not finger identity.
struct InstrumentContact {
    var id: Int32
    var x: Double
    var y: Double
}

struct InstrumentFrame {
    var time: Double
    var contacts: [InstrumentContact]
}

enum InstrumentKind { case string, drum }

enum InstrumentFretboard {
    static let notes = [55, 57, 59, 60, 62, 64, 67, 69, 71, 72, 74] // G3–D5
    static func index(at x: Double) -> Int { min(notes.count - 1, max(0, Int(x * Double(notes.count)))) }
    static func frequency(at index: Int) -> Double { 440 * pow(2, Double(notes[index] - 69) / 12) }
}

struct InstrumentVoice {
    var contact: InstrumentContact
    var kind: InstrumentKind
    var began: Double
    var released: Double?
    var anchorX: Double
    var baseHz: Double
    var fretIndex: Int
    var bendCents = 0.0
    var glideCents = 0.0
    var glideBegan = 0.0

    var frequency: Double { baseHz * pow(2, bendCents / 1200) }
    func soundingFrequency(at time: Double) -> Double {
        // Settle a fret change in time, even if no further touch frames arrive.
        let glide = glideCents * exp(-max(0, time - glideBegan) / 0.015)
        return frequency * pow(2, glide / 1200)
    }
    func amplitude(at time: Double) -> Double {
        let age = max(0, time - began)
        if kind == .drum {
            let release = max(0, min(1, (0.45 - age) / 0.05))
            return 0.95 * exp(-age / 0.085) * release
        }
        let release = released.map { max(0, 1 - (time - $0) / 0.09) } ?? 1
        // A bright pluck settles into a quiet sustained string, leaving time for vibrato.
        return (0.27 + 0.43 * exp(-age / 0.35)) * release
    }
}

struct InstrumentMix {
    var tones: [(hz: Double, amp: Double)]
    var level: Float
}

/// Pure state/synthesis layer: no hardware, terminal, or wall-clock dependencies.
struct InstrumentEngine {
    // Boost quieter notes and drum tails for recording; the final limiter still
    // caps the actuator at its existing maximum. Tone ratios stay unchanged.
    private let outputGain = 2.0
    private(set) var held: [Int32: InstrumentVoice] = [:]
    private(set) var tails: [InstrumentVoice] = []
    private(set) var peakTouches = 0
    private(set) var touchCount = 0
    private(set) var drumHits = 0
    private var lastFrameTime: Double?

    mutating func reset() {
        held.removeAll(); tails.removeAll(); touchCount = 0; lastFrameTime = nil
    }

    mutating func accept(_ frame: InstrumentFrame) {
        // Reject malformed coordinates from the undocumented driver layout.
        let contacts = frame.contacts.filter {
            $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
        }
        let ids = Set(contacts.map(\.id))
        touchCount = ids.count
        peakTouches = max(peakTouches, touchCount)
        let dt = min(0.1, max(0, frame.time - (lastFrameTime ?? frame.time)))
        lastFrameTime = frame.time
        for id in Array(held.keys) where !ids.contains(id) {
            if var voice = held.removeValue(forKey: id) {
                voice.released = frame.time
                tails.append(voice)
            }
        }
        // When fingers arrive in one hardware frame, leftmost wins the string role.
        // Later frames always retain the assignment, even if fingers cross.
        for contact in contacts.sorted(by: { $0.x == $1.x ? $0.id < $1.id : $0.x < $1.x }) {
            if var voice = held[contact.id] {
                voice.contact = contact
                if voice.kind == .string {
                    let count = Double(InstrumentFretboard.notes.count)
                    // Keep a small rocking gesture on its current fret, including
                    // when touch-down happens close to a boundary. A wider slide
                    // crosses frets; reverse movement has its own threshold.
                    let left = min(Double(voice.fretIndex) / count - 0.012, voice.anchorX - 0.035)
                    let right = max(Double(voice.fretIndex + 1) / count + 0.012, voice.anchorX + 0.035)
                    let nextFret = InstrumentFretboard.index(at: contact.x)
                    if (contact.x < left || contact.x > right) && nextFret != voice.fretIndex {
                        let previousHz = voice.soundingFrequency(at: frame.time)
                        voice.fretIndex = nextFret
                        voice.baseHz = InstrumentFretboard.frequency(at: nextFret)
                        voice.anchorX = contact.x
                        voice.bendCents = 0
                        voice.glideCents = 1200 * log2(previousHz / voice.baseHz)
                        voice.glideBegan = frame.time
                    } else {
                        let target = max(-75, min(75, (contact.x - voice.anchorX) * 2500))
                        voice.bendCents += (target - voice.bendCents) * (1 - exp(-dt / 0.012))
                    }
                }
                held[contact.id] = voice
            } else {
                let kind: InstrumentKind = held.values.contains { $0.kind == .string } ? .drum : .string
                let index = InstrumentFretboard.index(at: contact.x)
                let pitch = InstrumentFretboard.frequency(at: index)
                held[contact.id] = InstrumentVoice(contact: contact, kind: kind, began: frame.time,
                    anchorX: contact.x, baseHz: pitch, fretIndex: index)
                if kind == .drum { drumHits += 1 }
            }
        }
        prune(at: frame.time)
    }

    mutating func prune(at time: Double) {
        tails.removeAll { $0.amplitude(at: time) < 0.001 }
        // Keep overload/retrigger bursts bounded without changing held identities.
        if tails.count > 32 { tails.removeFirst(tails.count - 32) }
    }

    func mix(at time: Double) -> InstrumentMix {
        var tones: [(hz: Double, amp: Double)] = []
        let voices = held.values.sorted { $0.contact.id < $1.contact.id } + tails
        for voice in voices {
            let amp = voice.amplitude(at: time)
            guard amp > 0.001 else { continue }
            let age = max(0, time - voice.began)
            if voice.kind == .string {
                // Harmonics decay faster than the fundamental: a string-like pluck.
                let bright = exp(-age / 0.22)
                let pitch = voice.soundingFrequency(at: time)
                tones.append((pitch, amp * 0.65))
                tones.append((pitch * 2, amp * (0.15 + 0.15 * bright)))
                tones.append((pitch * 3, amp * 0.2 * bright))
            } else {
                // Like the upstream kick's pitch dive, with a deeper 100 Hz body,
                // longer decay, and a quiet octave attack instead of a metallic partial.
                let pitch = 100 + 180 * exp(-age / 0.018)
                tones.append((pitch, amp * 0.92))
                tones.append((pitch * 2, amp * 0.08 * exp(-age / 0.035)))
            }
        }
        tones = tones.filter { $0.amp > 0.0001 && (100...4000).contains($0.hz) }
        let sum = tones.reduce(0) { $0 + $1.amp }
        // play() normalizes tone weights; carry the envelope in overall level.
        return InstrumentMix(tones: tones, level: Float(min(1, sum * outputGain)))
    }
}
