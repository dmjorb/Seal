import SwiftUI

struct SealSheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.sealHairline.opacity(0.95))
            .frame(width: 40, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }
}

struct SealDrawer<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    private let content: Content
    private let footer: Footer

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            SealSheetGrabber()

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.sealTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            Divider().overlay(Color.sealHairline.opacity(0.65))

            ScrollView(showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(Color.sealHairline.opacity(0.65))

                footer
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
            }
            .background(Color.sealSurfaceElevated.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
        .sealSheetBackground()
    }
}

extension SealDrawer where Footer == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, content: content) {
            EmptyView()
        }
    }
}
