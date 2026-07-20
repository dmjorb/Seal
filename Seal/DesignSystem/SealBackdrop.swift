import SwiftUI

enum SealScreenLevel {
    case primary
    case secondary
    case tertiary

    var backgroundColor: Color {
        switch self {
        case .primary:
            return Color.sealBackground
        case .secondary:
            return Color.sealSecondaryBackground
        case .tertiary:
            return Color.sealTertiaryBackground
        }
    }

    var topHighlightOpacity: Double {
        switch self {
        case .primary: return 0.72
        case .secondary: return 0.58
        case .tertiary: return 0.46
        }
    }
}

struct SealBackdrop: View {
    let level: SealScreenLevel

    init(level: SealScreenLevel = .primary) {
        self.level = level
    }

    var body: some View {
        level.backgroundColor
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(level.topHighlightOpacity))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }
}

extension Color {
    static let sealAccent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let sealBackground = Color(red: 0.965, green: 0.965, blue: 0.984)
    static let sealSecondaryBackground = Color(red: 0.954, green: 0.965, blue: 0.992)
    static let sealTertiaryBackground = Color(red: 0.942, green: 0.950, blue: 0.970)
    static let sealSurface = Color.white.opacity(0.74)
    static let sealSurfaceElevated = Color.white.opacity(0.86)
    static let sealTextSecondary = Color(red: 0.39, green: 0.40, blue: 0.53)
    static let sealHairline = Color(red: 0.78, green: 0.79, blue: 0.84)
    static let sealWarning = Color(red: 1.0, green: 0.49, blue: 0.0)
    static let sealDanger = Color(red: 1.0, green: 0.18, blue: 0.18)
    static let sealSuccess = Color(red: 0.20, green: 0.78, blue: 0.35)
}

extension View {
    func sealScreenBackground(_ level: SealScreenLevel = .primary) -> some View {
        background(SealBackdrop(level: level))
    }
}
