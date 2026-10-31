import SwiftUI

enum DuckPose {
    case idle, walking, sleeping, cheering, held
}

@MainActor
final class DuckModel: ObservableObject {
    @Published var pose: DuckPose = .idle
    @Published var facingRight = true
    @Published var message: String?

    // Wired up by DuckController.
    var onTap: () -> Void = {}
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
}

/// Path data copied from the Figma exports in `art/`.
/// Positions are in the 86×78 coordinate space of `art/duck.png`.
enum DuckParts {
    static let size = CGSize(width: 86, height: 78)

    static let body = "M69.3203 25.2995C69.3203 37.7259 54.0979 47.7995 35.3203 47.7995C16.5426 47.7995 1.32026 37.7259 1.32026 25.2995C-5.67975 -11.7005 16.5426 2.79946 35.3203 2.79946C54.0979 2.79946 69.3203 12.8731 69.3203 25.2995Z"
    static let bodyShade = "M78.8636 -2.85436C78.8636 8.74362 94.8419 22.1841 58.0919 23.7995C46.6201 23.7995 37.3203 14.3975 37.3203 2.79948C37.3203 -8.7985 46.6201 -18.2005 58.0919 -18.2005C69.5638 -18.2005 78.8636 -14.4523 78.8636 -2.85436Z"
    static let head = "M41.5434 15.3462C41.5434 26.9441 57.5216 40.3846 20.7717 42C9.2998 42 0 32.598 0 21C0 9.40202 9.2998 0 20.7717 0C32.2436 0 41.5434 3.74817 41.5434 15.3462Z"
    static let beak = "M21.1766 8.38877L5.81368 0.339468C4.65899 -0.265525 3.21637 -0.0718008 2.47518 1.00056C-1.4094 6.62075 -1.20655 16.0057 6.59515 16.3077C12.6537 16.5421 17.57 14.2279 21.1532 12.3421C22.6606 11.5487 22.6854 9.17933 21.1766 8.38877Z"
    static let eye = "M8 4C8 6.20914 6.20914 6.5 4 6.5C1.79086 6.5 0 6.20914 0 4C0 1.79086 1.79086 0 4 0C6.20914 0 8 1.79086 8 4Z"

    static let yellow = Color(red: 1.0, green: 0.922, blue: 0.580)       // #FFEB94
    static let shade = Color(red: 0.925, green: 0.804, blue: 0.529)      // #ECCD87
    static let orange = Color(red: 0.933, green: 0.553, blue: 0.373)     // #EE8D5F
    static let darkOrange = Color(red: 0.827, green: 0.471, blue: 0.302) // #D3784D
    static let brown = Color(red: 0.333, green: 0.263, blue: 0.224)      // #554339
}

/// The duck drawn from its parts, posed procedurally for time `t`.
/// This is the piece a Rive view replaces later.
struct DuckArt: View {
    let pose: DuckPose
    let t: Double

    var body: some View {
        let a = Animation(pose: pose, t: t)
        ZStack(alignment: .topLeading) {
            Ellipse().fill(DuckParts.darkOrange)
                .part(x: 12 + a.backFootX, y: 69 + a.backFootY, w: 20, h: 8)

            ZStack(alignment: .topLeading) {
                SVGPath(d: DuckParts.body).fill(DuckParts.yellow)
                    .part(x: 0, y: 24, w: 70, h: 48)
                SVGPath(d: DuckParts.bodyShade).fill(DuckParts.shade)
                    .frame(width: 70, height: 48)
                    .mask(SVGPath(d: DuckParts.body))
                    .offset(x: 0, y: 24)

                ZStack(alignment: .topLeading) {
                    SVGPath(d: DuckParts.head).fill(DuckParts.yellow)
                        .part(x: 37, y: 0, w: 45, h: 42)
                    SVGPath(d: DuckParts.beak).fill(DuckParts.orange)
                        .part(x: 63, y: 21, w: 23, h: 17)
                    eye(closed: a.eyesClosed)
                }
                .canvas()
                .rotationEffect(.degrees(a.headTilt), anchor: UnitPoint(x: 0.55, y: 0.45))
                .offset(y: a.headY)
            }
            .canvas()
            .scaleEffect(x: 1, y: a.squash, anchor: .bottom)
            .rotationEffect(.degrees(a.bodyTilt), anchor: UnitPoint(x: 0.4, y: 0.92))
            .offset(y: a.bob)

            Ellipse().fill(DuckParts.orange)
                .part(x: 28 + a.frontFootX, y: 70 + a.frontFootY, w: 18, h: 8)

            if pose == .sleeping {
                zzz
            }
        }
        .canvas()
        .offset(y: a.hop)
    }

    @ViewBuilder
    private func eye(closed: Bool) -> some View {
        if closed {
            Capsule().fill(DuckParts.brown).part(x: 45, y: 17, w: 8, h: 1.8)
        } else {
            SVGPath(d: DuckParts.eye).fill(DuckParts.brown).part(x: 45, y: 14, w: 8, h: 7)
        }
    }

    private var zzz: some View {
        ForEach(0..<3) { i in
            let phase = (t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            Text("z")
                .font(.system(size: 8 + CGFloat(i) * 2, weight: .bold, design: .rounded))
                .foregroundStyle(DuckParts.brown.opacity(1 - phase))
                .offset(x: 70 + CGFloat(phase) * 10, y: -CGFloat(phase) * 22)
        }
    }

    /// All the per-frame numbers for a pose. Units are art pixels / degrees.
    private struct Animation {
        var bodyTilt = 0.0, headTilt = 0.0
        var bob: CGFloat = 0, hop: CGFloat = 0, headY: CGFloat = 0, squash: CGFloat = 1
        var frontFootX: CGFloat = 0, frontFootY: CGFloat = 0
        var backFootX: CGFloat = 0, backFootY: CGFloat = 0
        var eyesClosed = false

        init(pose: DuckPose, t: Double) {
            let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.13
            switch pose {
            case .idle:
                headY = CGFloat(sin(t * 2)) * 0.8
                squash = 1 + CGFloat(sin(t * 2)) * 0.012
                eyesClosed = blink
            case .walking:
                let s = sin(t * 9)
                bodyTilt = s * 5
                bob = -CGFloat(abs(s)) * 2.5
                frontFootX = CGFloat(s) * 4
                backFootX = -CGFloat(s) * 4
                frontFootY = -CGFloat(max(0, s)) * 2.5
                backFootY = -CGFloat(max(0, -s)) * 2.5
                eyesClosed = blink
            case .sleeping:
                headY = 4
                headTilt = 8
                squash = 0.96 + CGFloat(sin(t * 1.4)) * 0.02
                eyesClosed = true
            case .cheering:
                let s = sin(t * 11)
                hop = -CGFloat(abs(s)) * 10
                bodyTilt = s * 4
                headTilt = -6
                squash = 1 + CGFloat(abs(s)) * 0.04
            case .held:
                bodyTilt = sin(t * 6) * 6
                frontFootY = 3 + CGFloat(sin(t * 12)) * 1.5
                backFootY = 3 - CGFloat(sin(t * 12)) * 1.5
            }
        }
    }
}

private extension View {
    func part(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        frame(width: w, height: h).offset(x: x, y: y)
    }

    /// Pins a layer group to the full art size so rotation/scale anchors are in art space.
    func canvas() -> some View {
        frame(width: DuckParts.size.width, height: DuckParts.size.height, alignment: .topLeading)
    }
}

/// Window contents: speech bubble on top, duck at the bottom.
struct DuckRootView: View {
    @ObservedObject var model: DuckModel
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            if let message = model.message {
                SpeechBubble(text: message)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
            TimelineView(.animation) { context in
                DuckArt(pose: model.pose, t: context.date.timeIntervalSinceReferenceDate)
                    .scaleEffect(x: model.facingRight ? 1 : -1)
            }
            .frame(width: DuckParts.size.width, height: DuckParts.size.height)
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: DuckParts.size.width * scale, height: DuckParts.size.height * scale)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if hypot(value.translation.width, value.translation.height) > 4 {
                            model.onDragChanged()
                        }
                    }
                    .onEnded { value in
                        if hypot(value.translation.width, value.translation.height) > 4 {
                            model.onDragEnded()
                        } else {
                            model.onTap()
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.3), value: model.message)
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DuckParts.brown)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                )
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 7)
        }
        .frame(maxWidth: 200)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
