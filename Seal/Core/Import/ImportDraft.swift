import Foundation

struct ImportDraft: Equatable, Identifiable, Sendable {
    let appID: UUID
    let parsedIPA: ParsedIPA
    let stagedIPA: StagedIPA

    var id: UUID { appID }
}
