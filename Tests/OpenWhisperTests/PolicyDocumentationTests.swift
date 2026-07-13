import Foundation
import Testing
@testable import OpenWhisper

@Test
func privacyPoliciesMatchCurrentLocalRetentionAndDiagnosticsBoundary() throws {
    let root = policyRepositoryRoot()
    let english = try policyText(
        root,
        "docs/legal/privacy-policy.md"
    )
    let chinese = try policyText(
        root,
        "docs/legal/privacy-policy.zh-CN.md"
    )
    let config = AppConfig().privacy

    for text in [english, chinese] {
        #expect(text.contains("\(config.historyRetentionDays)"))
        #expect(text.contains("\(config.historyRecordLimit)"))
        #expect(text.contains("\(config.failedAudioRetentionHours)"))
        #expect(text.contains("\(config.failedAudioRecordLimit)"))
        #expect(text.contains("\(config.diagnosticsRetentionDays)"))
        #expect(
            text.contains(
                NumberFormatter.localizedString(
                    from: NSNumber(value: config.diagnosticsRecordLimit),
                    number: .decimal
                )
            )
                || text.contains("\(config.diagnosticsRecordLimit)")
        )
        #expect(text.contains("\(config.productMetricsRetentionDays)"))
        #expect(
            text.contains(
                NumberFormatter.localizedString(
                    from: NSNumber(
                        value: config.productMetricsRecordLimit
                    ),
                    number: .decimal
                )
            )
                || text.contains("\(config.productMetricsRecordLimit)")
        )
        #expect(text.contains("app.openwhisper.mac.ChatGPTSession"))
        #expect(text.contains("app.openwhisper.mac.LicenseReceipt"))
        #expect(text.contains("app.openwhisper.mac.LicenseDevice"))
        #expect(text.contains("Export Diagnostics") || text.contains("导出诊断"))
        #expect(text.contains("not uploaded automatically") || text.contains("不会自动上传"))
        #expect(text.contains("Off by default") || text.contains("默认关闭"))
        #expect(
            (
                text.contains("persistent")
                    && text.contains("user/install identifier")
            )
                || text.contains("持久用户/安装标识")
        )
        #expect(text.contains("audio") || text.contains("音频"))
        #expect(text.contains("transcript") || text.contains("转写"))
        #expect(text.contains("token") || text.contains("令牌"))
    }
}

@Test
func commercialPolicySetIsBilingualAndKeepsPreReleaseGatesExplicit() throws {
    let root = policyRepositoryRoot()
    let pairs = [
        (
            "docs/legal/terms-of-use.md",
            "docs/legal/terms-of-use.zh-CN.md"
        ),
        (
            "docs/legal/refund-policy.md",
            "docs/legal/refund-policy.zh-CN.md"
        ),
        (
            "docs/support/support-policy.md",
            "docs/support/support-policy.zh-CN.md"
        ),
        (
            "docs/support/upstream-incident-playbook.md",
            "docs/support/upstream-incident-playbook.zh-CN.md"
        ),
    ]

    for (englishPath, chinesePath) in pairs {
        let english = try policyText(root, englishPath)
        let chinese = try policyText(root, chinesePath)
        #expect(english.count > 600)
        #expect(chinese.count > 300)
    }

    let terms = try policyText(root, "docs/legal/terms-of-use.md")
    #expect(terms.contains("MIT License"))
    #expect(terms.contains("View Third-Party Licenses"))
    #expect(terms.contains("not affiliated with, sponsored by, or endorsed by OpenAI"))
    #expect(terms.contains("public paid release must identify the commercial operator"))

    let refund = try policyText(root, "docs/legal/refund-policy.md")
    #expect(refund.contains("14 calendar days"))
    #expect(refund.contains("does not currently sell a subscription"))

    let support = try policyText(root, "docs/support/support-policy.md")
    #expect(support.contains("Settings → Advanced → Export Diagnostics"))
    #expect(support.contains("not a paid SLA"))

    let incident = try policyText(
        root,
        "docs/support/upstream-incident-playbook.md"
    )
    #expect(
        incident.contains(
            "implements a remotely signed capability kill-switch foundation"
        )
    )
    #expect(incident.contains("monotonic revision"))
    #expect(incident.contains("production signing key"))

    let security = try policyText(root, "SECURITY.md")
    #expect(security.contains("private GitHub Security Advisory"))
    #expect(security.contains("Do not open a public issue"))
}

private func policyRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func policyText(_ root: URL, _ path: String) throws -> String {
    try String(
        contentsOf: root.appendingPathComponent(path),
        encoding: .utf8
    )
}
