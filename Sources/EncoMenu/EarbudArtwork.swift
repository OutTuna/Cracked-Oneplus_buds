import AppKit
import SwiftUI

enum EarbudArtwork {
    private static var resources: Bundle {
        Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("EncoAir5Pro_EncoMenu.bundle")) } ?? Bundle.module
    }

    static func image(_ finish: EarbudFinish) -> NSImage {
        if finish == .pearlWhite {
            return NSImage(size: NSSize(width: 800, height: 800), flipped: false) { _ in
                half(finish, right: false).draw(in: NSRect(x: 140, y: 130, width: 230, height: 420))
                half(finish, right: true).draw(in: NSRect(x: 430, y: 130, width: 230, height: 420))
                return true
            }
        }
        let name = "matte-black"
        guard let url = resources.url(forResource: name, withExtension: "webp"),
              let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return image
    }

    static func half(_ finish: EarbudFinish, right: Bool) -> NSImage {
        if finish == .pearlWhite,
           let url = resources.url(forResource: right ? "white-right" : "white-left", withExtension: "png"),
           let source = NSImage(contentsOf: url),
           let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let cropped = cg.cropping(to: CGRect(x: right ? 20 : 39, y: right ? 120 : 118,
                                               width: right ? 262 : 258, height: right ? 412 : 405)) {
            return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        }
        let image = image(finish)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: CGRect(x: right ? cgImage.width / 2 : 0, y: 0,
                                                       width: cgImage.width / 2, height: cgImage.height)) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}

struct EarbudArtworkView: View {
    var finish: EarbudFinish
    var opened: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: -8) {
                bud(right: false)
                bud(right: true)
            }
            .frame(width: geometry.size.height * 1.12, height: geometry.size.height * 1.12)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityLabel("OPPO Enco Air5 Pro, \(finish.title)")
        .accessibilityElement(children: .ignore)
    }

    private func bud(right: Bool) -> some View {
        Image(nsImage: EarbudArtwork.half(finish, right: right))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(finish == .pearlWhite ? 0.78 : 1)
            .rotationEffect(.degrees(reduceMotion ? 0 : opened ? (right ? 7 : -7) : (right ? -12 : 12)))
            .offset(x: reduceMotion ? 0 : opened ? (right ? 7 : -7) : (right ? -14 : 14),
                    y: reduceMotion ? 0 : opened ? 0 : 18)
            .scaleEffect(opened || reduceMotion ? 1 : 0.92)
            .opacity(opened ? 1 : 0)
            .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 9)
            .animation(reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.48, dampingFraction: 0.84), value: opened)
            .id(finish)
    }
}
