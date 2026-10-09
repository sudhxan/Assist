import SwiftUI

struct NotchContainer: View {
    let model: AppModel

    var body: some View {
        NotchRootView()
            .environment(model)
            .environment(\.colorScheme, .dark)
    }
}

/// The black notch shape that morphs between collapsed, peek and expanded.
struct NotchRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(topRadius: AppModel.flare, bottomRadius: model.bottomRadius)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                content
            }
            .frame(width: size.width, height: size.height)
            // The one buddy, drawn above everything and hopping between the seats the content offers.
            .overlayPreferenceValue(BuddySpotKey.self) { spots in
                BuddyLayer(spots: spots)
            }
            .clipShape(shape)
            .overlay {
                if model.isGenerating { GlowRim(shape: shape) }
            }
            .shadow(color: .black.opacity(model.state == .collapsed ? 0 : 0.45), radius: 18, y: 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.46, dampingFraction: 0.66), value: model.state)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.notchSize)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .collapsed:
            CollapsedView()
                .transition(.opacity)
        case .peek:
            PeekView()
                .transition(.opacity)
        case .expanded:
            ExpandedView()
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }
}

/// Flares into the menu bar at the top corners, rounded at the bottom — like the hardware notch.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4, rect.height / 2)
        let b = max(0, min(bottomRadius, rect.height - t, (rect.width - 2 * t) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + t, y: rect.minY + t), radius: t)
        path.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - t, y: rect.maxY), radius: b)
        path.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - t, y: rect.minY), radius: b)
        path.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: t)
        path.closeSubpath()
        return path
    }
}

/// Animated aurora outline shown while an answer is being written.
struct GlowRim: View {
    let shape: NotchShape

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            shape
                .stroke(AngularGradient(colors: Palette.aurora, center: .center, angle: .degrees(t * 90)), lineWidth: 1.6)
                .blur(radius: 1.2)
                .mask(LinearGradient(colors: [.clear, .white, .white], startPoint: .top, endPoint: .bottom))
        }
        .allowsHitTesting(false)
    }
}

/// Buddy on the left of the notch, status on the right.
struct CollapsedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            // Pushed toward the outer edge so it's clear of the camera housing.
            BuddySlot(spot: .ear, size: model.notchSize.height * 0.58)
                .padding(.leading, 6)
                .frame(width: AppModel.earWidth, alignment: .leading)
            Color.clear.frame(width: model.notchSize.width)
            RightEar()
                .padding(.trailing, 10)
                .frame(width: AppModel.earWidth, alignment: .trailing)
        }
        .frame(width: model.notchSize.width + 2 * AppModel.earWidth, height: model.notchSize.height)
    }
}

private struct RightEar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isGenerating || model.isCapturingScreen {
            SparkleSpinner(size: model.notchSize.height * 0.38)
        } else if model.hasUnseenAnswer {
            PulseDot()
        } else if model.isListening || model.isDictating {
            WaveformView(level: model.combinedLevel, height: model.notchSize.height * 0.42)
        } else if model.isStarting {
            ProgressView().controlSize(.mini)
        } else {
            // Keep a real view here: an empty ear would collapse and shove the buddy under the notch.
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// A one-line glance at the newest answer, without opening the panel.
struct PeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            CollapsedView()
            HStack(spacing: 10) {
                if let card = model.selectedCard {
                    Image(systemName: card.kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.auroraLinear)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                        Group {
                            if card.text.isEmpty, card.phase == .streaming {
                                Text("Thinking…")
                            } else if case .failed(let message) = card.phase {
                                Text(message).foregroundStyle(.orange)
                            } else {
                                Text(MarkdownLite.inline(MarkdownLite.firstLine(card.text)))
                            }
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("hover to open")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, AppModel.flare + 14)
            .frame(height: AppModel.peekSize.height)
        }
        .frame(width: max(model.collapsedSize.width, AppModel.peekSize.width))
    }
}
