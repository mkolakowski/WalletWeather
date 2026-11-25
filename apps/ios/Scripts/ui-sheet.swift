// Draws contact sheets for the UI review (Plans/ios-ui-review.md, #345):
// several of a run's pictures side by side, each with a caption, so a screen
// can be compared across looks, text sizes and devices in one image.
//
//   swift Scripts/ui-sheet.swift <manifest.json>
//
// The manifest is a list of sheets, each {"out": path, "height": points per
// picture, "rows": [[{"path": …, "label": …}]]}. Scripts/ui-report.py --sheets
// writes one and calls this. It can also cut one piece out of a picture, for
// a review page: a cell may carry "crop": [x, y, width, height] as fractions
// of the picture. System frameworks only.
import AppKit
import Foundation

struct Cell: Decodable {
    let path: String
    let label: String
    var crop: [Double]?
}

struct Sheet: Decodable {
    let out: String
    var height: Double?
    let rows: [[Cell]]
}

guard CommandLine.arguments.count == 2, let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let sheets = try? JSONDecoder().decode([Sheet].self, from: data) else {
    FileHandle.standardError.write(Data("usage: swift ui-sheet.swift <manifest.json>\n".utf8))
    exit(64)
}

let gap = 14.0
let caption = 30.0
var written = 0
for sheet in sheets {
    let height = sheet.height ?? 800
    // Each cell: its picture (cropped if asked) and the size it's drawn at.
    var rows: [[(CGImage, CGSize, String)]] = []
    for row in sheet.rows {
        var cells: [(CGImage, CGSize, String)] = []
        for cell in row {
            guard let image = NSImage(contentsOfFile: cell.path), var picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            if let crop = cell.crop, crop.count == 4 {
                let box = CGRect(x: crop[0] * Double(picture.width), y: crop[1] * Double(picture.height),
                                 width: crop[2] * Double(picture.width), height: crop[3] * Double(picture.height))
                    .intersection(CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
                if let cut = picture.cropping(to: box) { picture = cut }
            }
            let scale = height / Double(picture.height)
            cells.append((picture, CGSize(width: Double(picture.width) * scale, height: height), cell.label))
        }
        if !cells.isEmpty { rows.append(cells) }
    }
    guard !rows.isEmpty else { continue }
    let width = rows.map { $0.reduce(gap) { $0 + $1.1.width + gap } }.max() ?? 0
    let total = rows.reduce(gap) { $0 + caption + $1[0].1.height + gap }
    guard let context = CGContext(data: nil, width: Int(width), height: Int(total), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    context.setFillColor(CGColor(gray: 0.93, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: total))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    var top = gap
    for row in rows {
        var left = gap
        for (picture, size, label) in row {
            // Core Graphics counts from the bottom.
            let y = total - top - caption - size.height
            (label as NSString).draw(at: CGPoint(x: left, y: total - top - caption + 7),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.black])
            context.draw(picture, in: CGRect(x: left, y: y, width: size.width, height: size.height))
            left += size.width + gap
        }
        top += caption + row[0].1.height + gap
    }
    guard let made = context.makeImage() else { continue }
    let representation = NSBitmapImageRep(cgImage: made)
    let type: NSBitmapImageRep.FileType = sheet.out.hasSuffix(".png") ? .png : .jpeg
    guard let bytes = representation.representation(using: type, properties: [.compressionFactor: 0.8]) else { continue }
    try? FileManager.default.createDirectory(atPath: (sheet.out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    if FileManager.default.createFile(atPath: sheet.out, contents: bytes) { written += 1 }
}
print("ui-sheet: \(written) of \(sheets.count) written")
