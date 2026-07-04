import SwiftUI

/// Primary CTA. Clean and modern: a solid fill (white by default) with a dark
/// label — the colour lives in the gradient card borders, not the buttons.
/// Pass `fill:` for a tinted action (e.g. the positive confirm).
struct KenniPrimaryButtonStyle: ButtonStyle {
    var isEnabled = true
    var fill: Color = .white
    var foreground: Color = .kenniInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(isEnabled ? foreground : foreground.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                (isEnabled ? fill : fill.opacity(0.28)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Secondary action: translucent fill with a hairline border. Reads quiet next
/// to the primary button but stays tappable on the dark background.
struct KenniSecondaryButtonStyle: ButtonStyle {
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// A card with a subtle gradient border — used for the identity card and phrase box.
struct GradientBorderCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(KenniGradient.primary.opacity(0.6), lineWidth: 1.5))
    }
}

/// Step header used across onboarding screens.
struct OnboardingHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var gradient: LinearGradient = KenniGradient.primary

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(gradient)
                .padding(.bottom, 4)
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

/// Monospaced fingerprint chip, e.g. "R7KQ-2MXA-9F4T".
struct FingerprintBadge: View {
    let fingerprint: String

    var body: some View {
        Text(fingerprint)
            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.kenniCard, in: Capsule())
            .overlay(Capsule().strokeBorder(KenniGradient.cool.opacity(0.7), lineWidth: 1))
    }
}
