import SwiftUI
import AppKit

// MARK: - SwiftUI bird (24×24 viewport, same paths as govorun-lite)

struct BirdLogoView: View {
    var color: Color = .white
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24.0

            // Body outline
            var body = Path()
            body.move(to:    pt(21.5, 10.5, s))
            body.addLine(to: pt(17.5,  9.0, s))
            body.addCurve(to: pt( 6.0,  9.5, s),
                          control1: pt(14.5, 5.5, s),
                          control2: pt( 9.0, 5.5, s))
            body.addLine(to: pt( 3.0,  8.5, s))
            body.addLine(to: pt( 4.0, 12.5, s))
            body.addCurve(to: pt(13.0, 17.5, s),
                          control1: pt( 5.5, 15.5, s),
                          control2: pt( 9.0, 17.5, s))
            body.addCurve(to: pt(18.0, 13.0, s),
                          control1: pt(16.0, 17.5, s),
                          control2: pt(18.0, 15.5, s))
            body.addLine(to: pt(21.5, 11.5, s))
            body.closeSubpath()
            ctx.stroke(body, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.9 * s, lineCap: .round, lineJoin: .round))

            // Belly line
            var belly = Path()
            belly.move(to:    pt( 7.5, 11.5, s))
            belly.addCurve(to: pt(15.0, 14.0, s),
                           control1: pt( 9.5, 13.5, s),
                           control2: pt(12.0, 14.5, s))
            ctx.stroke(belly, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))

            // Eye (filled circle, r=0.85 at (15.2, 9))
            let eye = Path(ellipseIn: CGRect(x: (15.2 - 0.85) * s, y: (9.0 - 0.85) * s,
                                             width: 1.7 * s, height: 1.7 * s))
            ctx.fill(eye, with: .color(color))
        }
        .frame(width: size, height: size)
    }

    private func pt(_ x: Double, _ y: Double, _ s: Double) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - NSImage for status bar (template so it follows system dark/light)

extension NSImage {
    static func birdTemplate(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            let s = Double(bounds.width) / 24.0
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Body outline
            ctx.setLineWidth(1.9 * s)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 21.5 * s, y: 13.5 * s))  // flipped Y: 24 - y
            ctx.addLine(to: CGPoint(x: 17.5 * s, y: 15.0 * s))
            ctx.addCurve(to:     CGPoint(x:  6.0 * s, y: 14.5 * s),
                         control1: CGPoint(x: 14.5 * s, y: 18.5 * s),
                         control2: CGPoint(x:  9.0 * s, y: 18.5 * s))
            ctx.addLine(to: CGPoint(x:  3.0 * s, y: 15.5 * s))
            ctx.addLine(to: CGPoint(x:  4.0 * s, y: 11.5 * s))
            ctx.addCurve(to:     CGPoint(x: 13.0 * s, y:  6.5 * s),
                         control1: CGPoint(x:  5.5 * s, y:  8.5 * s),
                         control2: CGPoint(x:  9.0 * s, y:  6.5 * s))
            ctx.addCurve(to:     CGPoint(x: 18.0 * s, y: 11.0 * s),
                         control1: CGPoint(x: 16.0 * s, y:  6.5 * s),
                         control2: CGPoint(x: 18.0 * s, y:  8.5 * s))
            ctx.addLine(to: CGPoint(x: 21.5 * s, y: 12.5 * s))
            ctx.closePath()
            ctx.strokePath()

            // Belly
            ctx.setLineWidth(1.5 * s)
            ctx.beginPath()
            ctx.move(to: CGPoint(x:  7.5 * s, y: 12.5 * s))
            ctx.addCurve(to:     CGPoint(x: 15.0 * s, y: 10.0 * s),
                         control1: CGPoint(x:  9.5 * s, y: 10.5 * s),
                         control2: CGPoint(x: 12.0 * s, y:  9.5 * s))
            ctx.strokePath()

            // Eye
            ctx.fillEllipse(in: CGRect(x: (15.2 - 0.85) * s, y: (24 - 9.0 - 0.85) * s,
                                       width: 1.7 * s, height: 1.7 * s))
            return true
        }
        img.isTemplate = true
        return img
    }
}
