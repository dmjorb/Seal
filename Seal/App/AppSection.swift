import Foundation

enum AppSection: String, CaseIterable, Hashable {
    case apps
    case settings

    var title: String {
        switch self {
        case .apps: "应用"
        case .settings: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .settings: "person.crop.circle"
        }
    }
}
