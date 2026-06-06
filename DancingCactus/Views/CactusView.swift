import SwiftUI

struct CactusView: View {
    let isPlaying: Bool
    let beatPhase: Double
    let isWiggling: Bool

    private var swayAngle: Double {
        if isWiggling { return sin(beatPhase * .pi * 4) * 18.0 }
        if isPlaying  { return sin(beatPhase * .pi * 2) * 12.0 }
        return 0
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = sin(t * 0.8) * 0.015 + 1.0
            let pulse = (sin(t * 1.2) + 1.0) / 2.0

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let cx = geo.size.width / 2
                let cy = geo.size.height / 2

                ZStack {
                    RadialGradient(
                        colors: bgColors(pulse: pulse),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                    .ignoresSafeArea()

                    Canvas { ctx, sz in
                        drawCactus(&ctx, size: sz, breathe: breathe)
                    }
                    .frame(width: size * 0.55, height: size * 0.65)
                    .rotationEffect(.degrees(swayAngle), anchor: .bottom)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: swayAngle)
                    .position(x: cx, y: cy * 0.9)
                    .scaleEffect(breathe)
                }
            }
        }
    }

    private func bgColors(pulse: Double) -> [Color] {
        let green = Color(red: 0.176, green: 0.416, blue: 0.176)
        let teal  = Color(red: 0.102, green: 0.478, blue: 0.431)
        let lime  = Color(red: 0.478, green: 0.788, blue: 0.290)
        let mid: Color = pulse < 0.5
            ? green.lerp(to: teal, t: pulse * 2)
            : teal.lerp(to: lime, t: (pulse - 0.5) * 2)
        return [mid, green.opacity(0.7)]
    }

    private func drawCactus(_ ctx: inout GraphicsContext, size: CGSize, breathe: Double) {
        let w = size.width, h = size.height
        let cGreen = Color(red: 0.18, green: 0.55, blue: 0.18)
        let dGreen = Color(red: 0.10, green: 0.38, blue: 0.10)

        let tW = w * 0.28, tH = h * 0.60
        let tX = (w - tW) / 2, tY = h - tH
        let trunkRect = CGRect(x: tX, y: tY, width: tW, height: tH)

        // trunk
        let trunk = Path(roundedRect: trunkRect,
                         cornerSize: CGSize(width: tW * 0.4, height: tW * 0.4))
        ctx.fill(trunk, with: .color(cGreen))
        ctx.stroke(trunk, with: .color(dGreen), lineWidth: 1.5)

        // arms
        for dir: CGFloat in [-1, 1] {
            let ox = dir < 0 ? tX + tW * 0.15 : tX + tW * 0.85
            let oy = dir < 0 ? tY + tH * 0.28  : tY + tH * 0.32
            let arm = armPath(ox: ox, oy: oy, dir: dir, w: w)
            ctx.fill(arm, with: .color(cGreen))
            ctx.stroke(arm, with: .color(dGreen), lineWidth: 1.5)
        }

        // spines
        let spines: [(CGFloat, CGFloat, CGFloat)] = [
            (0.15, 0.20, -30), (0.85, 0.20, 30),
            (0.10, 0.42, -20), (0.90, 0.42, 20),
            (0.15, 0.62, -25), (0.85, 0.62, 25)
        ]
        for (xf, yf, deg) in spines {
            let ox = tX + tW * xf, oy = tY + tH * yf
            let rad = deg * .pi / 180
            let len = tW * 0.25
            var spine = Path()
            spine.move(to: CGPoint(x: ox, y: oy))
            spine.addLine(to: CGPoint(x: ox + cos(rad) * len, y: oy + sin(rad) * len))
            ctx.stroke(spine, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        }

        // eyes
        let eyeR = w * 0.035
        let eyeY = tY + tH * 0.12
        for xf: CGFloat in [0.2, 0.65] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: tX + tW * xf - eyeR, y: eyeY - eyeR,
                                       width: eyeR * 2, height: eyeR * 2)),
                with: .color(.black)
            )
        }

        // smile
        var smile = Path()
        smile.addArc(center: CGPoint(x: tX + tW / 2, y: tY + tH * 0.22),
                     radius: w * 0.055,
                     startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
        ctx.stroke(smile, with: .color(.black), lineWidth: 2)

        // flower
        let fr = w * 0.07
        let fcx = w / 2, fcy = tY - h * 0.04
        for i in 0..<6 {
            let a = Double(i) / 6.0 * .pi * 2
            ctx.fill(
                Path(ellipseIn: CGRect(x: fcx + cos(a) * fr * 0.9 - fr * 0.35,
                                       y: fcy + sin(a) * fr * 0.9 - fr * 0.5,
                                       width: fr * 0.7, height: fr)),
                with: .color(Color(red: 1.0, green: 0.8, blue: 0.2))
            )
        }
        ctx.fill(
            Path(ellipseIn: CGRect(x: fcx - fr * 0.38, y: fcy - fr * 0.38,
                                   width: fr * 0.76, height: fr * 0.76)),
            with: .color(Color(red: 1.0, green: 0.4, blue: 0.1))
        )
    }

    private func armPath(ox: CGFloat, oy: CGFloat, dir: CGFloat, w: CGFloat) -> Path {
        let wave = isPlaying ? CGFloat(sin(beatPhase * .pi * 2)) * 0.3 * dir * w * 0.15 : 0
        let elbowX = ox + dir * w * 0.28
        let elbowY = oy - w * 0.22 * 0.4 + wave
        let tipX = elbowX + dir * w * 0.04
        let tipY = elbowY - w * 0.22 * 0.35
        let aW = w * 0.14

        var p = Path()
        p.move(to: CGPoint(x: ox, y: oy))
        p.addCurve(to: CGPoint(x: elbowX, y: elbowY),
                   control1: CGPoint(x: ox + dir * w * 0.1,     y: oy - w * 0.022),
                   control2: CGPoint(x: elbowX - dir * w * 0.05, y: elbowY + w * 0.044))
        p.addCurve(to: CGPoint(x: tipX, y: tipY),
                   control1: CGPoint(x: elbowX + dir * w * 0.06, y: elbowY - w * 0.022),
                   control2: CGPoint(x: tipX - dir * w * 0.02,   y: tipY + w * 0.022))
        p.addCurve(to: CGPoint(x: elbowX - dir * aW * 0.4, y: elbowY + aW * 0.2),
                   control1: CGPoint(x: tipX + dir * aW * 0.3, y: tipY),
                   control2: CGPoint(x: elbowX + dir * aW * 0.1, y: elbowY - aW * 0.1))
        p.addCurve(to: CGPoint(x: ox - dir * aW * 0.1, y: oy + aW * 0.3),
                   control1: CGPoint(x: elbowX - dir * aW * 0.5, y: elbowY + w * 0.066),
                   control2: CGPoint(x: ox - dir * aW * 0.3, y: oy + aW * 0.1))
        p.closeSubpath()
        return p
    }
}

private extension Color {
    func lerp(to other: Color, t: Double) -> Color {
        let f = max(0, min(1, t))
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * f,
                     green: g1 + (g2 - g1) * f,
                     blue: b1 + (b2 - b1) * f,
                     opacity: a1 + (a2 - a1) * f)
    }
}

#Preview {
    CactusView(isPlaying: false, beatPhase: 0.0, isWiggling: false)
        .frame(width: 400, height: 600)
}
