import SwiftUI
import Testing
@testable import Seal

struct SealAppearanceTests {
    @Test(arguments: [
        (SealAppearance.system, "system", "跟随系统"),
        (SealAppearance.light, "light", "浅色"),
        (SealAppearance.dark, "dark", "深色")
    ])
    func persistenceValuesAndTitlesRemainStable(
        appearance: SealAppearance,
        rawValue: String,
        title: String
    ) {
        #expect(appearance.rawValue == rawValue)
        #expect(SealAppearance(rawValue: rawValue) == appearance)
        #expect(appearance.title == title)
    }

    @Test
    func systemDoesNotForceColorScheme() {
        #expect(SealAppearance.system.colorScheme == nil)
        #expect(SealAppearance.light.colorScheme == .light)
        #expect(SealAppearance.dark.colorScheme == .dark)
    }
}
