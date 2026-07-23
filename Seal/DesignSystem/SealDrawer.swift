import SwiftUI

struct SealSheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.sealHairline.opacity(0.95))
            .frame(width: 40, height: 5)
            .accessibilityHidden(true)
    }
}

/// Unified bottom-sheet container used throughout Seal.
/// The header and footer stay fixed while the body scrolls independently.
struct SealDrawer<Content: View, Footer: View>: View {
    let title: String?
    let level: SealScreenLevel
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    init(
        title: String? = nil,
        level: SealScreenLevel = .tertiary,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.level = level
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                SealSheetGrabber()
                    .padding(.top, 10)
                if let title {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, title == nil ? 10 : 14)

            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                Divider()
                    .overlay(Color.sealHairline.opacity(0.65))
                footer()
                    .padding(.horizontal, 22)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }
            .background(SealBackdrop(level: level))
        }
        .background(SealBackdrop(level: level).ignoresSafeArea())
        .presentationDragIndicator(.hidden)
        .compatibleClearPresentationBackground()
        .compatiblePresentationCornerRadius(29)
    }
}

extension SealDrawer where Footer == EmptyView {
    init(
        title: String? = nil,
        level: SealScreenLevel = .tertiary,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, level: level, content: content) { EmptyView() }
    }
}
