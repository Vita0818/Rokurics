#!/usr/bin/env swift

import AppKit
import Foundation

private struct FolderBadge {
    let name: String
    let symbolName: String
    let tint: NSColor
}

private struct FolderTint {
    let name: String
    let color: NSColor
}

private let assetSizes: [(scale: String, points: CGFloat, pixels: Int)] = [
    ("1x", 64, 64),
    ("2x", 64, 128),
    ("3x", 64, 192)
]

private let backupSize: CGFloat = 512
private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
private let assetCatalogURL = rootURL.appendingPathComponent("Rokurics/Assets.xcassets", isDirectory: true)
private let backupURL = rootURL.appendingPathComponent("Scripts/GeneratedFinderFolderIcons", isDirectory: true)
private let baseIcon = NSWorkspace.shared.icon(forFileType: "public.folder")

private let colorVariants: [FolderTint] = [
    FolderTint(name: "red", color: NSColor(red: 0.95, green: 0.24, blue: 0.28, alpha: 1)),
    FolderTint(name: "orange", color: NSColor(red: 0.96, green: 0.50, blue: 0.18, alpha: 1)),
    FolderTint(name: "yellow", color: NSColor(red: 0.96, green: 0.73, blue: 0.20, alpha: 1)),
    FolderTint(name: "green", color: NSColor(red: 0.35, green: 0.73, blue: 0.38, alpha: 1)),
    FolderTint(name: "mint", color: NSColor(red: 0.25, green: 0.78, blue: 0.62, alpha: 1)),
    FolderTint(name: "teal", color: NSColor(red: 0.18, green: 0.67, blue: 0.64, alpha: 1)),
    FolderTint(name: "cyan", color: NSColor(red: 0.20, green: 0.68, blue: 0.94, alpha: 1)),
    FolderTint(name: "blue", color: NSColor(red: 0.25, green: 0.56, blue: 0.96, alpha: 1)),
    FolderTint(name: "indigo", color: NSColor(red: 0.36, green: 0.43, blue: 0.88, alpha: 1)),
    FolderTint(name: "purple", color: NSColor(red: 0.58, green: 0.38, blue: 0.92, alpha: 1)),
    FolderTint(name: "gray", color: NSColor(red: 0.58, green: 0.62, blue: 0.67, alpha: 1))
]

private let badgeVariants: [FolderBadge] = [
    FolderBadge(name: "plus", symbolName: "plus", tint: NSColor(red: 0.15, green: 0.62, blue: 0.96, alpha: 1)),
    FolderBadge(name: "checkmark", symbolName: "checkmark", tint: NSColor(red: 0.18, green: 0.68, blue: 0.36, alpha: 1)),
    FolderBadge(name: "star", symbolName: "star.fill", tint: NSColor(red: 0.96, green: 0.64, blue: 0.14, alpha: 1)),
    FolderBadge(name: "trash", symbolName: "trash.fill", tint: NSColor(red: 0.92, green: 0.22, blue: 0.28, alpha: 1)),
    FolderBadge(name: "lock", symbolName: "lock.fill", tint: NSColor(red: 0.40, green: 0.45, blue: 0.55, alpha: 1)),
    FolderBadge(name: "upload", symbolName: "arrow.up", tint: NSColor(red: 0.16, green: 0.58, blue: 0.92, alpha: 1)),
    FolderBadge(name: "transcript", symbolName: "text.alignleft", tint: NSColor(red: 0.28, green: 0.56, blue: 0.86, alpha: 1)),
    FolderBadge(name: "note", symbolName: "note.text", tint: NSColor(red: 0.50, green: 0.42, blue: 0.88, alpha: 1)),
    FolderBadge(name: "ai", symbolName: "sparkles", tint: NSColor(red: 0.60, green: 0.36, blue: 0.92, alpha: 1))
]

private func drawBitmapImage(size: CGFloat, draw: (NSRect, CGContext?) -> Void) -> NSImage {
    let pixelSize = Int(size.rounded())
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return NSImage(size: NSSize(width: size, height: size))
    }

    rep.size = NSSize(width: size, height: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    context.cgContext.clear(rect)
    draw(rect, context.cgContext)
    NSGraphicsContext.current = previousContext

    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

private func renderSystemFolderIcon(size: CGFloat) -> NSImage {
    drawBitmapImage(size: size) { _, _ in
        let inset = size * 0.04
        let drawRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        baseIcon.size = drawRect.size
        baseIcon.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}

private func tintedImage(_ image: NSImage, tint: NSColor) -> NSImage {
    drawBitmapImage(size: image.size.width) { rect, context in
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        if let context,
       let tintColor = tint.usingColorSpace(.deviceRGB)?.cgColor {
            context.saveGState()
            context.setBlendMode(.sourceAtop)
            context.setAlpha(0.72)
            context.setFillColor(tintColor)
            context.fill(rect)
            context.restoreGState()
        }
        image.draw(in: rect, from: .zero, operation: .overlay, fraction: 0.36)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.18)
    }
}

private func badgedImage(_ image: NSImage, badge: FolderBadge) -> NSImage {
    drawBitmapImage(size: image.size.width) { rect, _ in
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

        let diameter = image.size.width * 0.34
        let badgeRect = NSRect(
            x: image.size.width - diameter * 1.10,
            y: image.size.height * 0.08,
            width: diameter,
            height: diameter
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = image.size.width * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -image.size.height * 0.012)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.set()

        badge.tint.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        NSShadow().set()

        NSColor.white.withAlphaComponent(0.82).setStroke()
        NSBezierPath(ovalIn: badgeRect.insetBy(dx: diameter * 0.035, dy: diameter * 0.035)).stroke()

        if let symbol = NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: nil) {
            symbol.isTemplate = true
            NSColor.white.set()
            let symbolSide = diameter * 0.54
            let symbolRect = NSRect(
                x: badgeRect.midX - symbolSide / 2,
                y: badgeRect.midY - symbolSide / 2,
                width: symbolSide,
                height: symbolSide
            )
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}

private func pngData(from image: NSImage) throws -> Data {
    if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
       let data = rep.representation(using: .png, properties: [:]) {
        return data
    }

    var rect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "FinderFolderIconExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage"])
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = image.size
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FinderFolderIconExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return data
}

private func writeImageSet(name: String, builder: (CGFloat) -> NSImage) throws {
    let imageSetURL = assetCatalogURL.appendingPathComponent("\(name).imageset", isDirectory: true)
    try fileManager.createDirectory(at: imageSetURL, withIntermediateDirectories: true)

    for size in assetSizes {
        let image = builder(CGFloat(size.pixels))
        let imageURL = imageSetURL.appendingPathComponent("\(name)@\(size.scale).png")
        try pngData(from: image).write(to: imageURL, options: .atomic)
    }

    let contents = """
    {
      "images" : [
        {
          "filename" : "\(name)@1x.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "\(name)@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "\(name)@3x.png",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "template-rendering-intent" : "original"
      }
    }
    """
    try contents.data(using: .utf8)?.write(to: imageSetURL.appendingPathComponent("Contents.json"), options: .atomic)

    try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
    let backupImage = builder(backupSize)
    try pngData(from: backupImage).write(to: backupURL.appendingPathComponent("\(name)-512.png"), options: .atomic)
}

do {
    try fileManager.createDirectory(at: assetCatalogURL, withIntermediateDirectories: true)
    try writeImageSet(name: "finder-folder-default") { size in
        renderSystemFolderIcon(size: size)
    }

    for variant in colorVariants {
        try writeImageSet(name: "finder-folder-\(variant.name)") { size in
            tintedImage(renderSystemFolderIcon(size: size), tint: variant.color)
        }
    }

    for badge in badgeVariants {
        try writeImageSet(name: "finder-folder-default-\(badge.name)") { size in
            badgedImage(renderSystemFolderIcon(size: size), badge: badge)
        }
    }

    print("Exported Finder folder icons to \(assetCatalogURL.path)")
    print("Wrote 512px backups to \(backupURL.path)")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
