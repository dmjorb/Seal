enum ImportWorkflowState: Equatable, Sendable {
    case idle
    case preparing
    case awaitingConfirmation(ImportDraft)
    case committing(ImportDraft)
    case completed(AppRecord)
    case failed(ImportFailure)
}
