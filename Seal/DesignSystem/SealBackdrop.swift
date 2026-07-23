import SwiftUI
import UIKit

enum SealScreenLevel {
    case primary
    case secondary
    case tertiary

    var backgroundColor: Color { Color.sealBackground }
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

private extension UIColor {
    static func sealDynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension Color {
    static let sealAccent = Color(uiColor: .sealDynamic(
        light: UIColor(red: 0.08, green: 0.42, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1)
    ))
    static let sealBackground = Color(uiColor: .sealDynamic(
        light: UIColor(red: 0.965, green: 0.972, blue: 0.985, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.047, blue: 0.075, alpha: 1)
    ))
    static let sealSecondaryBackground = sealBackground
    static let sealTertiaryBackground = sealBackground
    static let sealSurface = Color(uiColor: .sealDynamic(
        light: UIColor(white: 1.0, alpha: 0.96),
        dark: UIColor(red: 0.090, green: 0.105, blue: 0.145, alpha: 0.96)
    ))
    static let sealSurfaceElevated = Color(uiColor: .sealDynamic(
        light: UIColor(red: 0.93, green: 0.945, blue: 0.97, alpha: 0.98),
        dark: UIColor(red: 0.120, green: 0.138, blue: 0.185, alpha: 0.98)
    ))
    static let sealTextSecondary = Color(uiColor: .secondaryLabel)
    static let sealHairline = Color(uiColor: .sealDynamic(
        light: UIColor(white: 0.0, alpha: 0.12),
        dark: UIColor(white: 1.0, alpha: 0.14)
    ))
    static let sealWarning = Color(uiColor: .systemOrange)
    static let sealDanger = Color(uiColor: .systemRed)
    static let sealSuccess = Color(uiColor: .systemGreen)
}

extension View {
    func sealScreenBackground(_ level: SealScreenLevel = .primary) -> some View {
        background(SealBackdrop(level: level))
    }
}
