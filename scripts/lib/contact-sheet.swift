// Keeps the screenshots a UI test named, out of an exported .xcresult's attachments,
// and lays them out on contact sheets. Usage: contact-sheet.swift <attachments> <out>
import AppKit
import Foundation

struct Manifest: Decodable {
    struct Attachment: Decodable {
        let exportedFileName: String
        let suggestedHumanReadableName: String?
    }

    let attachments: [Attachment]
}

let columns = 4
let rows = 3
let thumbnailWidth: CGFloat = 330
let gap: CGFloat = 8
/// What Xcode records by itself, as against what a test chose to keep.
let automatic = ["App Screenshot", "Element Screenshot", "Synthesized Event", "Screen Recording", "Complete Issue"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else { fail("usage: contact-sheet.swift <attachments> <out>") }
let source = URL(filePath: CommandLine.arguments[1])
let destination = URL(filePath: CommandLine.arguments[2])
let manager = FileManager.default

let data: Data
let tests: [Manifest]
do {
    data = try Data(contentsOf: source.appending(path: "manifest.json"))
    tests = try JSONDecoder().decode([Manifest].self, from: data)
} catch {
    fail("no attachment manifest in \(source.path): \(error)")
}

/// "01-home_0_6E594E27-….png" was named "01-home" by the test.
func keptName(_ attachment: Manifest.Attachment) -> String? {
    guard let name = attachment.suggestedHumanReadableName,
          !automatic.contains(where: name.hasPrefix),
          ["png", "jpg", "jpeg"].contains(URL(filePath: attachment.exportedFileName).pathExtension.lowercased())
    else { return nil }
    return name.replacing(#/_\d+_[0-9A-Fa-f-]{36}(\.\w+)?$/#, with: "")
}

var kept: [(name: String, file: URL)] = []
for attachment in tests.flatMap(\.attachments) {
    guard let name = keptName(attachment) else { continue }
    let file = destination.appending(path: "\(name).png")
    try? manager.removeItem(at: file)
    do {
        try manager.copyItem(at: source.appending(path: attachment.exportedFileName), to: file)
        kept.append((name, file))
    } catch {
        fail("could not copy \(name): \(error)")
    }
}
kept.sort { $0.name < $1.name }
guard !kept.isEmpty else { fail("the tests kept no named screenshots") }

func drawSheet(_ images: ArraySlice<(name: String, file: URL)>, to file: URL) {
    guard let first = images.first.flatMap({ NSImage(contentsOf: $0.file) }), first.size.width > 0 else {
        fail("could not read \(images.first?.name ?? "a screenshot")")
    }
    let thumbnailHeight = thumbnailWidth * first.size.height / first.size.width
    let labelHeight: CGFloat = 24
    let cell = NSSize(width: thumbnailWidth + gap, height: thumbnailHeight + labelHeight + gap)
    let rowCount = (images.count + columns - 1) / columns
    let size = NSSize(width: CGFloat(columns) * cell.width, height: CGFloat(rowCount) * cell.height)
    let sheet = NSImage(size: size)
    sheet.lockFocus()
    NSColor.darkGray.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    for (index, item) in images.enumerated() {
        let x = CGFloat(index % columns) * cell.width + gap / 2
        let y = size.height - CGFloat(index / columns + 1) * cell.height + gap / 2
        NSImage(contentsOf: item.file)?.draw(in: NSRect(x: x, y: y, width: thumbnailWidth, height: thumbnailHeight))
        NSString(string: item.name).draw(at: NSPoint(x: x + 4, y: y + thumbnailHeight + 2), withAttributes: attributes)
    }
    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation,
          let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    else { fail("could not encode \(file.lastPathComponent)") }
    do {
        try jpeg.write(to: file)
    } catch {
        fail("could not write \(file.path): \(error)")
    }
}

let perSheet = columns * rows
for (page, start) in stride(from: 0, to: kept.count, by: perSheet).enumerated() {
    let file = destination.appending(path: "sheet-\(page + 1).jpg")
    drawSheet(kept[start ..< min(start + perSheet, kept.count)], to: file)
    print("  \(file.path)")
}
print("  \(kept.count) screenshots")
