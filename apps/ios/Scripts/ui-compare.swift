// Compares pictures of the same screen from two sets (#352) and says which
// changed and where, for the before-and-after page.
//
//   swift Scripts/ui-compare.swift <pairs.json> <out.json>
//
// pairs.json is a list of {"name": …, "before": path, "after": path}. For
// each it writes {"name", "changed", "share" (of the picture that differs),
// "boxes": [[x, y, width, height] as fractions of the picture]}.
//
// Two renderings of the same screen are never identical to the pixel: glass
// shimmers and JPEG rounds. So a pixel counts only when a channel is off by
// more than `pixelGap`, a 12-pixel cell only when a fifth of it counts, and a
// picture only when more than `cellsNeeded` cells do. Scripts/ui-snapshot.sh
// --check takes two sets from one build to show these let nothing through.
// System frameworks only.
import AppKit
import Foundation

struct Pair: Decodable { let name: String; let before: String; let after: String }
struct Verdict: Encodable { let name: String; let changed: Bool; let share: Double; let boxes: [[Double]]; let note: String }

let pixelGap = 48
let cell = 12
let cellShare = 0.2
let cellsNeeded = 4

func pixels(_ path: String) -> (data: [UInt8], width: Int, height: Int)? {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    guard let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (data, image.width, image.height)
}

guard CommandLine.arguments.count == 3, let input = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let pairs = try? JSONDecoder().decode([Pair].self, from: input) else {
    FileHandle.standardError.write(Data("usage: swift ui-compare.swift <pairs.json> <out.json>\n".utf8))
    exit(64)
}

var verdicts: [Verdict] = []
for pair in pairs {
    guard let before = pixels(pair.before), let after = pixels(pair.after) else {
        verdicts.append(Verdict(name: pair.name, changed: true, share: 1, boxes: [], note: "a picture couldn't be read"))
        continue
    }
    guard before.width == after.width, before.height == after.height else {
        verdicts.append(Verdict(name: pair.name, changed: true, share: 1, boxes: [], note: "the screen's size changed"))
        continue
    }
    let width = before.width, height = before.height
    let columns = (width + cell - 1) / cell, rows = (height + cell - 1) / cell
    var counts = [Int](repeating: 0, count: columns * rows)
    for y in 0..<height {
        for x in 0..<width {
            let at = (y * width + x) * 4
            if abs(Int(before.data[at]) - Int(after.data[at])) > pixelGap || abs(Int(before.data[at + 1]) - Int(after.data[at + 1])) > pixelGap
                || abs(Int(before.data[at + 2]) - Int(after.data[at + 2])) > pixelGap {
                counts[(y / cell) * columns + x / cell] += 1
            }
        }
    }
    var marked = counts.map { Double($0) >= Double(cell * cell) * cellShare }
    let markedCount = marked.filter { $0 }.count
    guard markedCount > cellsNeeded else {
        verdicts.append(Verdict(name: pair.name, changed: false, share: Double(markedCount) / Double(marked.count), boxes: [], note: ""))
        continue
    }
    // Groups of marked cells that touch (or nearly: two cells apart) become one box each.
    var boxes: [CGRect] = []
    for start in 0..<marked.count where marked[start] {
        var stack = [start]
        marked[start] = false
        var minX = start % columns, maxX = minX, minY = start / columns, maxY = minY
        while let at = stack.popLast() {
            let x = at % columns, y = at / columns
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            for dy in -2...2 {
                for dx in -2...2 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < columns, ny < rows, marked[ny * columns + nx] else { continue }
                    marked[ny * columns + nx] = false
                    stack.append(ny * columns + nx)
                }
            }
        }
        boxes.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
    // Boxes that overlap are one change; at most eight are drawn, the largest first.
    var merged = true
    while merged {
        merged = false
        outer: for first in 0..<boxes.count {
            for second in (first + 1)..<boxes.count where boxes[first].insetBy(dx: -1, dy: -1).intersects(boxes[second]) {
                boxes[first] = boxes[first].union(boxes[second])
                boxes.remove(at: second)
                merged = true
                break outer
            }
        }
    }
    boxes.sort { $0.width * $0.height > $1.width * $1.height }
    let round4 = { (value: Double) in (value * 10000).rounded() / 10000 }
    let drawn = boxes.prefix(8).map { box in
        [round4(Double(box.minX * CGFloat(cell)) / Double(width)), round4(Double(box.minY * CGFloat(cell)) / Double(height)),
         round4(min(1, Double(box.width * CGFloat(cell)) / Double(width))), round4(min(1, Double(box.height * CGFloat(cell)) / Double(height)))]
    }
    verdicts.append(Verdict(name: pair.name, changed: true, share: round4(Double(markedCount) / Double(columns * rows)), boxes: drawn, note: ""))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(verdicts).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("ui-compare: \(verdicts.filter(\.changed).count) of \(verdicts.count) changed")
