import SwiftUI
import UIKit

enum SealScreenLevel {
    case primary
    case secondary
    case tertiary

    var backgroundColor: Color {
        switch self {
        case .primary: .sealBackground
        case .secondary: .sealSecondaryBackground
        case .tertiary: .sealTertiaryBackground
        }
    }

    var topHighlightOpacity: Double { 0.44 }
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
                    .fill(Color.sealHairline.opacity(level.topHighlightOpacity))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }
}

extension Color {
    static let sealAccent = adaptive(
        light: UIColor(red: 0.08, green: 0.42, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1)
    )
    static let sealBackground = adaptive(
        light: UIColor(red: 0.955, green: 0.968, blue: 0.988, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.047, blue: 0.075, alpha: 1)
    )
    static let sealSecondaryBackground = adaptive(
        light: UIColor(red: 0.940, green: 0.956, blue: 0.982, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.058, blue: 0.090, alpha: 1)
    )
    static let sealTertiaryBackground = adaptive(
        light: UIColor(red: 0.925, green: 0.944, blue: 0.974, alpha: 1),
        dark: UIColor(red: 0.055, green: 0.069, blue: 0.104, alpha: 1)
    )
    static let sealSurface = adaptive(
        light: UIColor(white: 1.0, alpha: 0.94),
        dark: UIColor(red: 0.090, green: 0.105, blue: 0.145, alpha: 0.96)
    )
    static let sealSurfaceElevated = adaptive(
        light: UIColor(white: 1.0, alpha: 0.99),
        dark: UIColor(red: 0.120, green: 0.138, blue: 0.185, alpha: 0.98)
    )
    static let sealTextSecondary = adaptive(
        light: UIColor(red: 0.34, green: 0.38, blue: 0.46, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.72, blue: 0.80, alpha: 1)
    )
    static let sealHairline = adaptive(
        light: UIColor(white: 0.0, alpha: 0.10),
        dark: UIColor(white: 1.0, alpha: 0.14)
    )
    static let sealWarning = adaptive(
        light: UIColor(red: 0.84, green: 0.40, blue: 0.04, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.60, blue: 0.24, alpha: 1)
    )
    static let sealDanger = adaptive(
        light: UIColor(red: 0.82, green: 0.14, blue: 0.20, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)
    )
    static let sealSuccess = adaptive(
        light: UIColor(red: 0.08, green: 0.54, blue: 0.24, alpha: 1),
        dark: UIColor(red: 0.38, green: 0.86, blue: 0.52, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension View {
    func sealScreenBackground(_ level: SealScreenLevel = .primary) -> some View {
        background(SealBackdrop(level: level))
    }
}
