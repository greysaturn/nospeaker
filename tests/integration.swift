// Appended to the application declarations by test.sh; no motor is opened.
func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let records = UnsafeMutableRawPointer.allocate(byteCount: 96 * 2, alignment: 8)
records.initializeMemory(as: UInt8.self, repeating: 0, count: 96 * 2)
func record(_ index: Int, id: Int32, state: Int32, x: Float, y: Float) {
    let ptr = records.advanced(by: index * 96)
    ptr.storeBytes(of: id, toByteOffset: 16, as: Int32.self)
    ptr.storeBytes(of: state, toByteOffset: 20, as: Int32.self)
    ptr.storeBytes(of: x, toByteOffset: 32, as: Float.self)
    ptr.storeBytes(of: y, toByteOffset: 36, as: Float.self)
}
collectInstrumentFrames = true
record(0, id: 41, state: 4, x: 0.25, y: 0.6)
record(1, id: 7, state: 3, x: 0.75, y: 0.4)
_ = touchCallback(nil, records, 2, 0, 0)
let first = drainInstrumentFrames()
verify(first.frames.count == 1 && first.frames[0].contacts.map(\.id) == [41, 7], "Decode all stable contact IDs")
verify(first.frames[0].contacts[1].x == 0.75, "Decode second 96-byte record")
record(0, id: 41, state: 4, x: 0.25, y: 0.6)
record(1, id: 7, state: 5, x: 0.75, y: 0.4)
_ = touchCallback(nil, records, 2, 0, 0)
verify(drainInstrumentFrames().frames[0].contacts.map(\.id) == [41], "Break-touch must release instrument")
_ = touchCallback(nil, nil, 0, 0, 0)
verify(drainInstrumentFrames().frames[0].contacts.isEmpty, "Empty frame releases all contacts")
for _ in 0..<300 { _ = touchCallback(nil, nil, 0, 0, 0) }
let overflow = drainInstrumentFrames()
verify(overflow.overflowed && overflow.frames.count <= 256, "Queue overload is bounded and signals reset")
verify(!drainInstrumentFrames().overflowed, "Overflow reset flag is consumed once")
records.deallocate()

var previewEngine = InstrumentEngine()
previewEngine.accept(InstrumentFrame(time: 0, contacts: [InstrumentContact(id: 41, x: 0.25, y: 0.6)]))
previewEngine.accept(InstrumentFrame(time: 0.01, contacts: [InstrumentContact(id: 41, x: 0.25, y: 0.6), InstrumentContact(id: 7, x: 0.75, y: 0.4)]))
var previewState = LiveState()
previewState.scene = .instruments
previewState.instrumentVoices = Array(previewEngine.held.values)
previewState.instrumentTouchCount = 2
previewState.instrumentPeakTouches = 2
let preview = Canvas()
draw(preview, previewState, 0.02)
var rows: [String] = []
for row in 0..<24 { rows.append(String(preview.cells[(row * 80)..<((row + 1) * 80)].map(\.ch))) }
let textPreview = rows.joined(separator: "\n")
verify(textPreview.contains("/__\\") && textPreview.contains("(  )"), "Both shapes appear on the shared canvas")
verify(textPreview.contains("#41") && textPreview.contains("#7"), "Visuals identify both contacts")
verify(textPreview.contains("G3") && textPreview.contains("D5"), "Fretboard labels span the existing note range")
try textPreview.write(toFile: "build/instruments-preview.txt", atomically: true, encoding: .utf8)
print("Passed raw callback, queue, release, and terminal rendering checks (no motor actuations).")
