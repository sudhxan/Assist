import SwiftUI

// MARK: - One buddy, many seats

/// A place the buddy can sit. It only reserves space; the single buddy hops into it.
struct BuddySlot: View {
    let spot: BuddySpot
    var size: CGFloat
    /// Soft shadow "cushion" so an empty seat still looks intentional.
    var seat = false

    var body: some View {
        Color.clear
            .frame(width: size * BuddyView.footprintRatio, height: size * BuddyView.footprintRatio)
            .background(alignment: .bottom) {
                if seat {
                    Ellipse()
                        .fill(.white.opacity(0.07))
                        .frame(width: size * 0.95, height: size * 0.16)
                }
            }
            .anchorPreference(key: BuddySpotKey.self, value: .bounds) { [spot: $0] }
    }
}

struct BuddySpotKey: PreferenceKey {
    static var defaultValue: [BuddySpot: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [BuddySpot: Anchor<CGRect>], nextValue: () -> [BuddySpot: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Draws the one and only buddy at whichever seat it belongs in, hopping between seats.
struct BuddyLayer: View {
    @Environment(AppModel.self) private var model
    let spots: [BuddySpot: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let target {
                let rect = proxy[target.anchor]
                TravelingBuddy(spot: target.spot, scale: rect.width / (BuddyView.baseSize * BuddyView.footprintRatio))
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.spring(response: 0.6, dampingFraction: 0.62), value: target.spot)
            }
        }
    }

    private var target: (spot: BuddySpot, anchor: Anchor<CGRect>)? {
        for spot in [model.buddySpot, .header, .ear] {
            if let anchor = spots[spot] { return (spot, anchor) }
        }
        return nil
    }
}

private struct TravelingBuddy: View {
    @Environment(AppModel.self) private var model
    let spot: BuddySpot
    let scale: CGFloat

    var body: some View {
        BuddyView(mood: model.mood, level: model.combinedLevel)
            .scaleEffect(scale)
            .animation(.spring(response: 0.55, dampingFraction: 0.65), value: scale)
            // A jump arc, with squash on take-off and landing, whenever it changes seats.
            .keyframeAnimator(initialValue: BuddyView.Squash(), trigger: spot) { content, value in
                content
                    .scaleEffect(x: value.sx, y: value.sy, anchor: .bottom)
                    .offset(y: value.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    CubicKeyframe(2, duration: 0.07)
                    CubicKeyframe(-28, duration: 0.26)
                    CubicKeyframe(0, duration: 0.24)
                    SpringKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.sy) {
                    CubicKeyframe(0.78, duration: 0.07)
                    CubicKeyframe(1.18, duration: 0.2)
                    CubicKeyframe(1.0, duration: 0.3)
                    CubicKeyframe(0.8, duration: 0.07)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy(extraBounce: 0.3))
                }
                KeyframeTrack(\.sx) {
                    CubicKeyframe(1.2, duration: 0.07)
                    CubicKeyframe(0.86, duration: 0.2)
                    CubicKeyframe(1.0, duration: 0.3)
                    CubicKeyframe(1.2, duration: 0.07)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy(extraBounce: 0.3))
                }
            }
    }
}

// MARK: - The buddy

/// A squishy aurora blob that hops, squashes and stretches, and pulls faces to match
/// what Assist is doing. Click it for a twirl and a heart.
struct BuddyView: View {
    static let baseSize: CGFloat = 32
    static let footprintRatio: CGFloat = 1.35

    var mood: BuddyMood
    var level: Float = 0
    var size: CGFloat = BuddyView.baseSize
    @State private var pokes = 0
    @State private var boings = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .sleeping ? 1.0 / 24 : 1.0 / 60)) { context in
            buddy(at: context.date.timeIntervalSinceReferenceDate)
        }
        // "Boing" when it perks up: crouch, spring up, wobble back.
        .keyframeAnimator(initialValue: Squash(), trigger: boings) { content, value in
            content
                .scaleEffect(x: value.sx, y: value.sy, anchor: .bottom)
                .offset(y: value.y)
        } keyframes: { _ in
            KeyframeTrack(\.sy) {
                CubicKeyframe(0.72, duration: 0.09)
                CubicKeyframe(1.22, duration: 0.13)
                SpringKeyframe(0.92, duration: 0.14, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy(extraBounce: 0.25))
            }
            KeyframeTrack(\.sx) {
                CubicKeyframe(1.25, duration: 0.09)
                CubicKeyframe(0.85, duration: 0.13)
                SpringKeyframe(1.06, duration: 0.14, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy(extraBounce: 0.25))
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0, duration: 0.09)
                CubicKeyframe(-size * 0.3, duration: 0.15)
                SpringKeyframe(0, duration: 0.4, spring: .bouncy(extraBounce: 0.3))
            }
        }
        // Poke: hop, twirl, and a little heart.
        .keyframeAnimator(initialValue: Twirl(), trigger: pokes) { content, value in
            content
                .rotationEffect(.degrees(value.angle))
                .offset(y: value.y)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(Palette.pink)
                        .scaleEffect(0.5 + value.heart * 0.6)
                        .offset(x: size * 0.5, y: -size * 0.45 - value.heartRise)
                        .opacity(value.heart)
                }
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                CubicKeyframe(-20, duration: 0.1)
                CubicKeyframe(360, duration: 0.42)
                MoveKeyframe(0)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(2, duration: 0.1)
                CubicKeyframe(-size * 0.45, duration: 0.2)
                SpringKeyframe(0, duration: 0.45, spring: .bouncy(extraBounce: 0.35))
            }
            KeyframeTrack(\.heart) {
                CubicKeyframe(1, duration: 0.18)
                LinearKeyframe(1, duration: 0.5)
                CubicKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.heartRise) {
                CubicKeyframe(size * 0.55, duration: 1.0)
            }
        }
        .frame(width: size * Self.footprintRatio, height: size * Self.footprintRatio)
        .contentShape(Rectangle())
        .onTapGesture { pokes += 1 }
        .onChange(of: mood) { _, new in
            // Dozing off is quiet; perking up gets a boing.
            if new != .sleeping && new != .drowsy { boings += 1 }
        }
    }

    private func buddy(at t: Double) -> some View {
        let lvl = CGFloat(min(level, 1))
        let motion = Self.motion(for: mood, level: lvl, size: size, t: t)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .fill(AngularGradient(colors: Palette.aurora, center: .center, angle: .degrees(t * 45)))
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(.white.opacity(0.45))
                        .frame(width: size * 0.32, height: size * 0.16)
                        .rotationEffect(.degrees(-20))
                        .offset(x: size * 0.14, y: size * 0.12)
                        .blur(radius: size * 0.03)
                }
                .frame(width: size, height: size)
                .shadow(color: Palette.sky.opacity(mood == .sleeping ? 0.4 : 0.55), radius: size * 0.3)
            FaceView(spec: FaceSpec.make(mood: mood, level: lvl, t: t), size: size)
            Extras(mood: mood, t: t, size: size)
        }
        .scaleEffect(x: motion.sx, y: motion.sy, anchor: .bottom)
        .rotationEffect(.degrees(motion.tilt))
        .offset(x: motion.x, y: motion.y)
    }

    // MARK: Motion

    struct Squash {
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var y: CGFloat = 0
    }

    struct Twirl {
        var angle: Double = 0
        var y: CGFloat = 0
        var heart: Double = 0
        var heartRise: CGFloat = 0
    }

    struct Motion {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var tilt: Double = 0
    }

    private static func motion(for mood: BuddyMood, level: CGFloat, size: CGFloat, t: Double) -> Motion {
        switch mood {
        case .sleeping:
            // Slow, deep breaths with a sleepy sway. No bouncing: let it nap.
            let b = CGFloat(sin(t * 1.6))
            return Motion(sx: 1 - 0.04 * b, sy: 1 + 0.06 * b, tilt: sin(t * 0.8) * 5)
        case .drowsy:
            // Nodding off: slowly droops, then jerks back up.
            let p = (t / 3.2).truncatingRemainder(dividingBy: 1)
            let droop = CGFloat(p < 0.8 ? pow(p / 0.8, 2) : 1 - (p - 0.8) / 0.2)
            return Motion(y: droop * size * 0.08, sx: 1 + droop * 0.04, sy: 1 - droop * 0.06, tilt: Double(droop) * 10)
        case .waking:
            // Shivers and stretches, trying to get up.
            let stretch = CGFloat(max(0, sin(t * 4)))
            return Motion(x: CGFloat(sin(t * 45)) * size * 0.02, sx: 1 - 0.06 * stretch, sy: 1 + 0.1 * stretch)
        case .idle:
            // A little hop now and then.
            return hop(t: t, period: 3.2, height: size * 0.18, squash: 1)
        case .listening:
            // Bounces along with whoever is talking; still when it's quiet.
            var m = hop(t: t, period: 0.62, height: size * 0.28 * level, squash: level)
            m.tilt = sin(t * 3.1) * 6 * Double(level)
            return m
        case .alert:
            // Excited quick hops: a question is coming.
            var m = hop(t: t, period: 0.46, height: size * 0.22, squash: 1)
            m.tilt = sin(t * 13) * 4
            return m
        case .thinking:
            // Wobbly jelly while the answer is being written.
            let w = CGFloat(sin(t * 7))
            return Motion(y: CGFloat(sin(t * 3.5)) * size * 0.05, sx: 1 + 0.08 * w, sy: 1 - 0.08 * w, tilt: sin(t * 5) * 9)
        case .happy:
            // Big celebratory bounces with a flip at the top.
            let period = 0.95
            var m = hop(t: t, period: period, height: size * 0.3, squash: 1.2)
            let phase = (t / period).truncatingRemainder(dividingBy: 1)
            if phase > 0.12 && phase < 0.52 { m.tilt = (phase - 0.12) / 0.4 * 360 }
            return m
        }
    }

    /// Cartoon hop: anticipation squash → stretched jump → landing squash → rest.
    private static func hop(t: Double, period: Double, height: CGFloat, squash: CGFloat) -> Motion {
        let p = (t / period).truncatingRemainder(dividingBy: 1)
        switch p {
        case ..<0.12:
            let k = CGFloat(sin(p / 0.12 * .pi))
            return Motion(sx: 1 + 0.12 * k * squash, sy: 1 - 0.14 * k * squash)
        case ..<0.52:
            let a = (p - 0.12) / 0.4
            let air = CGFloat(sin(a * .pi))
            let stretch = CGFloat(abs(cos(a * .pi))) * squash
            return Motion(y: -height * air, sx: 1 - 0.07 * stretch, sy: 1 + 0.1 * stretch)
        case ..<0.68:
            let k = CGFloat(sin((p - 0.52) / 0.16 * .pi))
            return Motion(sx: 1 + 0.16 * k * squash, sy: 1 - 0.18 * k * squash)
        default:
            return Motion()
        }
    }
}

// MARK: - Face

private struct FaceSpec {
    enum Eye {
        case open(CGFloat)
        /// Heavy eyelid: flat on top, only the bottom showing.
        case lid(CGFloat)
        /// Sleeping ‿
        case closed
        /// Happy ^
        case happy
    }

    enum Mouth {
        case none, smile(CGFloat), grin, o(CGFloat), yawn(CGFloat), wavy
    }

    var left: Eye
    var right: Eye
    /// Gaze offset, in units of the buddy's size.
    var look = CGSize.zero
    var mouth = Mouth.none
    var blush = 0.25

    static func make(mood: BuddyMood, level: CGFloat, t: Double) -> FaceSpec {
        let blinking = t.truncatingRemainder(dividingBy: 3.7) < 0.13
        func open(_ h: CGFloat) -> Eye { blinking ? .open(0.04) : .open(h) }

        switch mood {
        case .sleeping:
            return FaceSpec(left: .closed, right: .closed, blush: 0.4)
        case .drowsy:
            let p = (t / 3.2).truncatingRemainder(dividingBy: 1)
            let yawnPhase = (t / 5.5).truncatingRemainder(dividingBy: 1)
            let yawn = yawnPhase < 0.32 ? CGFloat(sin(yawnPhase / 0.32 * .pi)) * 0.2 : 0
            let eyesShut = (p > 0.55 && p < 0.82) || yawn > 0.08
            let eye: Eye = eyesShut ? .closed : .lid(0.11)
            return FaceSpec(left: eye, right: eye, look: CGSize(width: 0, height: 0.03),
                            mouth: yawn > 0.02 ? .yawn(yawn) : .none, blush: 0.35)
        case .waking:
            let flutter = CGFloat(max(0, sin(t * 9)))
            let eye = Eye.lid(0.07 + 0.16 * flutter)
            return FaceSpec(left: eye, right: eye, mouth: .o(0.07), blush: 0.35)
        case .idle:
            let winking = (t + 2).truncatingRemainder(dividingBy: 7.3) < 0.35
            let glance: CGFloat = sin(t * 0.6) > 0.75 ? 0.06 : 0
            return FaceSpec(left: winking ? .happy : open(0.27), right: open(0.27),
                            look: CGSize(width: glance, height: 0), mouth: .smile(0.18), blush: 0.28)
        case .listening:
            return FaceSpec(left: open(0.27), right: open(0.27), look: CGSize(width: sin(t * 0.9) * 0.07, height: 0),
                            mouth: level > 0.35 ? .o(0.07 + level * 0.06) : .smile(0.16), blush: 0.22)
        case .alert:
            return FaceSpec(left: .open(0.36), right: .open(0.36), mouth: .o(0.1), blush: 0.2)
        case .thinking:
            return FaceSpec(left: open(0.22), right: open(0.22),
                            look: CGSize(width: cos(t * 3) * 0.05 + 0.04, height: -0.06), mouth: .wavy, blush: 0.2)
        case .happy:
            return FaceSpec(left: .happy, right: .happy, mouth: .grin, blush: 0.6)
        }
    }
}

private struct FaceView: View {
    let spec: FaceSpec
    let size: CGFloat
    private let ink = Color.black.opacity(0.82)

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.42) {
                cheek
                cheek
            }
            .offset(y: size * 0.13)
            VStack(spacing: size * 0.03) {
                HStack(spacing: size * 0.12) {
                    eye(spec.left)
                    eye(spec.right)
                }
                mouth(spec.mouth)
                    .frame(width: size * 0.3, height: size * 0.16, alignment: .top)
            }
            .offset(x: spec.look.width * size, y: spec.look.height * size + size * 0.06)
        }
    }

    private var cheek: some View {
        Ellipse()
            .fill(Palette.pink.opacity(spec.blush))
            .frame(width: size * 0.17, height: size * 0.09)
            .blur(radius: size * 0.02)
    }

    private func eye(_ eye: FaceSpec.Eye) -> some View {
        Group {
            switch eye {
            case .open(let h):
                Capsule()
                    .fill(ink)
                    .frame(width: size * 0.15, height: max(size * 0.035, size * h))
            case .lid(let h):
                UnevenRoundedRectangle(topLeadingRadius: size * 0.015, bottomLeadingRadius: size * 0.075,
                                       bottomTrailingRadius: size * 0.075, topTrailingRadius: size * 0.015)
                    .fill(ink)
                    .frame(width: size * 0.17, height: max(size * 0.035, size * h))
                    .offset(y: (size * 0.27 - size * h) / 2) // eyelid comes down from the top
            case .closed:
                Smile()
                    .stroke(ink, style: StrokeStyle(lineWidth: max(1, size * 0.06), lineCap: .round))
                    .frame(width: size * 0.18, height: size * 0.07)
            case .happy:
                HappyEye()
                    .stroke(ink, style: StrokeStyle(lineWidth: max(1, size * 0.07), lineCap: .round))
                    .frame(width: size * 0.19, height: size * 0.11)
            }
        }
        .frame(width: size * 0.22, height: size * 0.36)
    }

    @ViewBuilder
    private func mouth(_ mouth: FaceSpec.Mouth) -> some View {
        switch mouth {
        case .none:
            Color.clear
        case .smile(let width):
            Smile()
                .stroke(ink, style: StrokeStyle(lineWidth: max(1, size * 0.055), lineCap: .round))
                .frame(width: size * width, height: size * 0.07)
        case .grin:
            Grin()
                .fill(ink)
                .overlay(alignment: .bottom) {
                    Ellipse().fill(Palette.pink).frame(width: size * 0.13, height: size * 0.08).offset(y: size * 0.02)
                }
                .clipShape(Grin())
                .frame(width: size * 0.26, height: size * 0.13)
        case .o(let d):
            Ellipse()
                .fill(ink)
                .frame(width: size * d, height: size * d * 1.2)
        case .yawn(let open):
            Ellipse()
                .fill(ink)
                .frame(width: size * 0.15, height: max(size * 0.03, size * open))
        case .wavy:
            Wavy()
                .stroke(ink, style: StrokeStyle(lineWidth: max(1, size * 0.045), lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.05)
        }
    }
}

/// Little props around the buddy: z's and a snot bubble, "!?", thought dots, sparkles.
private struct Extras: View {
    let mood: BuddyMood
    let t: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            switch mood {
            case .sleeping:
                bubble
                floatingZ(delay: 0)
                floatingZ(delay: 1.1)
            case .drowsy:
                floatingZ(delay: 0).opacity(0.5)
            case .waking:
                mark("!?", wiggle: true)
            case .alert:
                mark("!", wiggle: false)
            case .thinking:
                thoughtDots
            case .happy:
                sparkles
            default:
                EmptyView()
            }
        }
    }

    /// Grows and shrinks with each breath, then pops.
    private var bubble: some View {
        let cycle = (t / 8.8).truncatingRemainder(dividingBy: 1)
        let breath = CGFloat(0.5 + 0.5 * sin(t * 1.6))
        let radius = size * (0.035 + 0.08 * breath * min(1, CGFloat(cycle) / 0.25))
        let popped = cycle > 0.9
        return Circle()
            .fill(Palette.sky.opacity(0.25))
            .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: max(0.6, size * 0.025)))
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: size * 0.16 + radius * 0.6, y: size * 0.2)
            .opacity(popped ? 0 : 1)
            .scaleEffect(popped ? 1.6 : 1)
    }

    private func floatingZ(delay: Double) -> some View {
        let phase = ((t + delay) / 2.2).truncatingRemainder(dividingBy: 1)
        return Text("z")
            .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .scaleEffect(0.6 + 0.5 * phase)
            .offset(x: size * 0.5 + CGFloat(phase) * size * 0.18 + CGFloat(sin(phase * 6)) * size * 0.04,
                    y: -size * 0.32 - CGFloat(phase) * size * 0.32)
            .opacity(1 - phase)
    }

    private func mark(_ text: String, wiggle: Bool) -> some View {
        let pop = CGFloat(0.85 + 0.15 * abs(sin(t * 6)))
        return Text(text)
            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
            .foregroundStyle(Palette.mint)
            .shadow(color: .black.opacity(0.6), radius: 1)
            .scaleEffect(pop)
            .rotationEffect(.degrees(wiggle ? sin(t * 10) * 12 : 0))
            .offset(x: size * 0.56, y: -size * 0.5)
    }

    private var thoughtDots: some View {
        let step = Int(t * 2.5) % 4
        return HStack(alignment: .bottom, spacing: size * 0.05) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: size * (0.07 + CGFloat(i) * 0.025), height: size * (0.07 + CGFloat(i) * 0.025))
                    .opacity(i < step ? 1 : 0.15)
            }
        }
        .offset(x: size * 0.62, y: -size * 0.5)
    }

    private var sparkles: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (t * 1.6 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let angle = Double(i) * 2.1 + 0.6
                Image(systemName: "sparkle")
                    .font(.system(size: size * (0.18 + 0.1 * CGFloat(i % 2)), weight: .bold))
                    .foregroundStyle(Palette.aurora[i + 1])
                    .scaleEffect(CGFloat(sin(phase * .pi)))
                    .offset(x: cos(angle) * size * 0.68, y: sin(angle) * size * 0.6 - size * 0.12)
            }
        }
    }
}

private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.8))
        return path
    }
}

private struct Grin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.9))
        path.closeSubpath()
        return path
    }
}

private struct Wavy: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        for i in 1...12 {
            let x = rect.minX + rect.width * CGFloat(i) / 12
            let y = rect.midY + sin(CGFloat(i) / 12 * .pi * 3) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - Small indicators

struct WaveformView: View {
    var level: Float
    var bars = 4
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    let wobble = 0.5 + 0.5 * sin(t * 8 + Double(i) * 1.7)
                    let lvl = CGFloat(level)
                    let fraction = min(1, 0.2 + lvl * (0.5 + 0.5 * wobble) + 0.07 * wobble)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.mint, Palette.sky], startPoint: .bottom, endPoint: .top))
                        .frame(width: 3, height: max(3, height * fraction))
                }
            }
            .frame(height: height)
        }
    }
}

struct SparkleSpinner: View {
    var size: CGFloat = 13

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Image(systemName: "sparkle")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(AngularGradient(colors: Palette.aurora, center: .center, angle: .degrees(t * 180)))
                .rotationEffect(.degrees(t * 120))
                .scaleEffect(1 + 0.12 * sin(t * 6))
        }
    }
}

struct PulseDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = (context.date.timeIntervalSinceReferenceDate / 1.4).truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle().stroke(Palette.mint.opacity(1 - phase), lineWidth: 1.5)
                    .frame(width: 8 + phase * 12, height: 8 + phase * 12)
                Circle().fill(Palette.mint).frame(width: 8, height: 8)
                    .shadow(color: Palette.mint, radius: 4)
                    .offset(y: -abs(sin(phase * .pi * 2)) * 3)
            }
        }
    }
}

struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Palette.aurora[i + 1])
                        .frame(width: 7, height: 7)
                        .offset(y: -abs(sin(t * 4 + Double(i) * 0.6)) * 5)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
