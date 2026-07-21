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

extension Color {
    static let sealAccent = Color(uiColor: UIColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1))
    static let sealBackground = Color(uiColor: UIColor(red: 0.035, green: 0.047, blue: 0.075, alpha: 1))
    static let sealSecondaryBackground = Color.sealBackground
    static let sealTertiaryBackground = Color.sealBackground
    static let sealSurface = Color(uiColor: UIColor(red: 0.090, green: 0.105, blue: 0.145, alpha: 0.96))
    static let sealSurfaceElevated = Color(uiColor: UIColor(red: 0.120, green: 0.138, blue: 0.185, alpha: 0.98))
    static let sealTextSecondary = Color(uiColor: UIColor(red: 0.68, green: 0.72, blue: 0.80, alpha: 1))
    static let sealHairline = Color(uiColor: UIColor(white: 1.0, alpha: 0.14))
    static let sealWarning = Color(uiColor: UIColor(red: 1.0, green: 0.60, blue: 0.24, alpha: 1))
    static let sealDanger = Color(uiColor: UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1))
    static let sealSuccess = Color(uiColor: UIColor(red: 0.38, green: 0.86, blue: 0.52, alpha: 1))
}

extension View {
    func sealScreenBackground(_ level: SealScreenLevel = .primary) -> some View {
        background(SealBackdrop(level: level))
    }
}
