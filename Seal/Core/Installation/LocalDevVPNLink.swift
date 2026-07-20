import Foundation

enum LocalDevVPNLink {
    static let enableAndReturn = URL(
        string: "localdevvpn://enable?scheme=seal"
    )!
    static let disableAndReturn = URL(
        string: "localdevvpn://disable?scheme=seal"
    )!
    static let appStore = URL(
        string: "itms-apps://itunes.apple.com/app/id6755608044"
    )!

    static func isCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "seal"
    }
}
