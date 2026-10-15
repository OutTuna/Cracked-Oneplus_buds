import AppKit

enum Artwork {
    static func icon(_ style: MenuBarIcon, side: Int? = nil) -> NSImage {
        if style == .earbuds, side == nil,
           let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: "Enco earbuds") {
            let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) ?? symbol
            image.size = NSSize(width: 23, height: 18)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if style == .chargingCase {
                let outline = NSBezierPath(roundedRect: NSRect(x: 2, y: 3.5, width: 18, height: 13), xRadius: 4.8, yRadius: 4.8)
                outline.lineWidth = 1.55
                outline.stroke()
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: 2.5, y: 11.4))
                seam.line(to: NSPoint(x: 19.5, y: 11.4))
                seam.lineWidth = 1.15
                seam.stroke()
                NSBezierPath(ovalIn: NSRect(x: 10.3, y: 7, width: 1.4, height: 1.4)).fill()
            } else {
                let positions: [(CGFloat, CGFloat)] = side == nil ? [(6.1, -0.12), (15.9, 0.12)] : [(11, side == 1 ? -0.12 : 0.12)]
                for (x, angle) in positions {
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform()
                    transform.translateX(by: x, yBy: 11)
                    transform.rotate(byRadians: angle)
                    transform.concat()
                    NSBezierPath(roundedRect: NSRect(x: -1.25, y: -7.8, width: 2.5, height: 9.6), xRadius: 1.25, yRadius: 1.25).fill()
                    NSBezierPath(ovalIn: NSRect(x: -3.1, y: -1, width: 6.2, height: 6.4)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func exportIcon(to url: URL, finish: EarbudFinish = .pearlWhite) throws {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        let buds = EarbudArtwork.image(finish)
        image.lockFocus()
        let outline = NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 212, yRadius: 212)
        NSGradient(colors: [NSColor(red: 0.23, green: 0.28, blue: 0.29, alpha: 1), NSColor(red: 0.065, green: 0.085, blue: 0.095, alpha: 1)])?.draw(in: outline, angle: -70)
        NSColor(white: 1, alpha: 0.09).setStroke()
        outline.lineWidth = 3
        outline.stroke()
        buds.draw(in: NSRect(x: 42, y: 45, width: 940, height: 940))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
