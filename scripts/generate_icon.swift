import AppKit
import Foundation

// Directly generates a valid Apple .icns file containing Retina PNG chunks without requiring iconservicesd XPC
let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift generate_icon.swift <output.icns>\n", stderr)
    exit(1)
}

let outputICNSPath = args[1]

func renderPNG(pointSize: Int, pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pointSize, height: pointSize)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    let s = CGFloat(pointSize)
    let pad = s * 0.095
    let box = NSRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let radius = box.width * 0.225

    let squircle = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.30, blue: 0.74, alpha: 1.0)
    ])
    gradient?.draw(in: squircle, angle: -90)

    NSColor.white.withAlphaComponent(0.18).setStroke()
    squircle.lineWidth = max(0.5, s * 0.012)
    squircle.stroke()

    if let sym = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.44, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let colored = sym.withSymbolConfiguration(cfg) {
            let imgSize = colored.size
            let drawRect = NSRect(
                x: (s - imgSize.width) * 0.5,
                y: (s - imgSize.height) * 0.5,
                width: imgSize.width,
                height: imgSize.height
            )
            colored.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    return rep.representation(using: .png, properties: [:])
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var be = value.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

let chunkSpecs: [(String, Int, Int)] = [
    ("icp4", 16, 16),
    ("ic11", 16, 32),
    ("icp5", 32, 32),
    ("ic12", 32, 64),
    ("ic07", 128, 128),
    ("ic13", 128, 256),
    ("ic08", 256, 256),
    ("ic14", 256, 512),
    ("ic09", 512, 512),
    ("ic10", 512, 1024)
]

var chunksData = Data()
for (osType, pt, px) in chunkSpecs {
    guard let png = renderPNG(pointSize: pt, pixelSize: px) else { continue }
    chunksData.append(contentsOf: osType.utf8)
    appendUInt32BE(UInt32(8 + png.count), to: &chunksData)
    chunksData.append(png)
}

var icnsData = Data()
icnsData.append(contentsOf: "icns".utf8)
appendUInt32BE(UInt32(8 + chunksData.count), to: &icnsData)
icnsData.append(chunksData)

let outURL = URL(fileURLWithPath: outputICNSPath)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try icnsData.write(to: outURL, options: .atomic)
