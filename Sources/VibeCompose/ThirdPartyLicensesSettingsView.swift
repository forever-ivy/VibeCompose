import AppKit
import SwiftUI

struct ThirdPartyLicensesView: View {
    let documents: [ThirdPartyLicenseDocument]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIdentity: String?

    init(documents: [ThirdPartyLicenseDocument]) {
        self.documents = documents
        _selectedIdentity = State(
            initialValue: documents.first?.entry.identity
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedIdentity) {
                ForEach(documents) { document in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.entry.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(document.entry.pinnedDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .tag(document.entry.identity)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 190,
                ideal: 220,
                max: 260
            )
        } detail: {
            if let selectedDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedDocument.entry.name)
                                .font(.system(size: 24, weight: .semibold))
                                .tracking(-0.3)
                            Text(selectedDocument.entry.pinnedDescription)
                                .font(VibeComposeTypography.callout())
                                .foregroundStyle(.secondary)
                            VibeComposeStatusChip(
                                text: selectedDocument.entry.licenseName,
                                kind: .neutral
                            )
                        }

                        Divider().opacity(0.5)

                        Text(selectedDocument.licenseText)
                            .font(
                                .system(
                                    size: 11,
                                    design: .monospaced
                                )
                            )
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                            .padding(14)
                            .background(
                                Color(nsColor: VibeComposePalette.insetSurface),
                                in: RoundedRectangle(
                                    cornerRadius: VibeComposeMetrics.radiusM,
                                    style: .continuous
                                )
                            )
                    }
                    .padding(24)
                }
            } else {
                VibeComposeEmptyState(
                    systemImage: "doc.text",
                    title: L10n.text("No license selected")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle(L10n.text("Third-Party Licenses"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("Close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var selectedDocument: ThirdPartyLicenseDocument? {
        guard let selectedIdentity else {
            return documents.first
        }
        return documents.first {
            $0.entry.identity == selectedIdentity
        }
    }
}

