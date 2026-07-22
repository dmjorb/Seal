import SwiftUI

struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.sealSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.secondary.opacity(0.18), lineWidth: 0.5)
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.7)
                }
        } else {
            content
                .background(
                    Color.sealSurface,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.sealHairline.opacity(0.72), lineWidth: 0.7)
                }
        }
    }
}


struct SealSheetBackground: ViewModifier {
    let level: SealScreenLevel

    func body(content: Content) -> some View {
        content
            .background(SealBackdrop(level: level).ignoresSafeArea())
            .presentationDragIndicator(.hidden)
            .compatibleSealPresentationBackground(level)
            .compatiblePresentationCornerRadius(30)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func compatibleClearPresentationBackground() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }


    @ViewBuilder
    func compatibleSealPresentationBackground(_ level: SealScreenLevel) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(level == .primary ? Color.sealBackground : Color.sealSurface)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatiblePresentationCornerRadius(_ radius: CGFloat) -> some View {
        if #available(iOS 16.4, *) {
            presentationCornerRadius(radius)
        } else {
            self
        }
    }

    func sealSheetBackground(_ level: SealScreenLevel = .tertiary) -> some View {
        modifier(SealSheetBackground(level: level))
    }

    func sealPrimaryAction() -> some View {
        buttonStyle(SealPrimaryActionStyle(cornerRadius: 8))
    }

    func sealPrimaryAction(cornerRadius: CGFloat) -> some View {
        buttonStyle(SealPrimaryActionStyle(cornerRadius: cornerRadius))
    }

    func sealOutlineAction(cornerRadius: CGFloat) -> some View {
        buttonStyle(SealOutlineActionStyle(cornerRadius: cornerRadius))
    }

    func sealSecondaryDisabledAction(cornerRadius: CGFloat) -> some View {
        buttonStyle(SealSecondaryDisabledActionStyle(cornerRadius: cornerRadius))
    }
}

struct SealPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(
                Color.sealAccent.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.5)
            }
            .shadow(color: Color.sealAccent.opacity(isEnabled ? (configuration.isPressed ? 0.14 : 0.28) : 0.0), radius: 14, y: 7)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SealOutlineActionStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color.sealAccent)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.sealAccent, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SealSecondaryDisabledActionStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color.sealTextSecondary.opacity(0.75))
            .background(
                Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
