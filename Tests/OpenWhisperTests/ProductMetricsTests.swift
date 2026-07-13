import Foundation
import Testing
@testable import OpenWhisper

@Test
func productMetricsDefaultToLocalOptInOffAndBoundedRetention() throws {
    let config = AppConfig()

    #expect(config.privacy.productMetricsEnabled == false)
    #expect(config.privacy.productMetricsRetentionDays == 30)
    #expect(config.privacy.productMetricsRecordLimit == 5_000)

    let decoded = try JSONDecoder().decode(
        AppConfig.self,
        from: Data(
            """
            {
              "privacy": {
                "productMetricsEnabled": true,
                "productMetricsRetentionDays": 0,
                "productMetricsRecordLimit": 999999
              }
            }
            """.utf8
        )
    )

    #expect(decoded.privacy.productMetricsEnabled)
    #expect(decoded.privacy.productMetricsRetentionDays == 1)
    #expect(decoded.privacy.productMetricsRecordLimit == 50_000)
    #expect(config.privacy.productMetricsRetentionPolicy().maxRecords == 0)
    #expect(
        decoded.privacy.productMetricsRetentionPolicy().maxRecords
            == 50_000
    )
}

@Test
func productMetricSamplesContainOnlyEnumsBucketsAndVersionMetadata() throws {
    let sample = ProductMetricSample(
        timestamp: Date(timeIntervalSince1970: 100),
        environment: ProductMetricsEnvironment(
            productVersion: "0.1.0",
            productBuild: "42"
        ),
        event: .dictationSucceeded,
        provider: .chatGPTManagedAuth,
        audioDurationMs: 12_000,
        totalProcessingMs: 4_500,
        deliveryStatus: .pasteDispatched
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let text = String(
        data: try encoder.encode(sample),
        encoding: .utf8
    ) ?? ""

    #expect(sample.schemaVersion == 1)
    #expect(sample.audioDurationBucket == .seconds5To15)
    #expect(sample.latencyBucket == .seconds2To5)
    #expect(text.contains("\"event\":\"dictation_succeeded\""))
    #expect(text.contains("\"provider\":\"chatGPTManagedAuth\""))
    #expect(text.contains("\"deliveryStatus\":\"paste_dispatched\""))
    #expect(!text.contains("transcript"))
    #expect(!text.contains("bundleIdentifier"))
    #expect(!text.contains("account"))
    #expect(!text.contains("path"))
    #expect(!text.contains("identifier"))
}

@Test
func productMetricBucketsUseStableBoundaries() {
    #expect(
        ProductMetricAudioDurationBucket(milliseconds: 4_999)
            == .under5Seconds
    )
    #expect(
        ProductMetricAudioDurationBucket(milliseconds: 5_000)
            == .seconds5To15
    )
    #expect(
        ProductMetricAudioDurationBucket(milliseconds: 60_000)
            == .over60Seconds
    )
    #expect(
        ProductMetricLatencyBucket(milliseconds: 1_999)
            == .under2Seconds
    )
    #expect(
        ProductMetricLatencyBucket(milliseconds: 2_000)
            == .seconds2To5
    )
    #expect(
        ProductMetricLatencyBucket(milliseconds: 30_000)
            == .over30Seconds
    )
}

@Test
func productMetricsRecorderAppliesRetentionPermissionsAndDisableDelete()
    throws
{
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "OpenWhisperProductMetrics-\(UUID().uuidString)",
            isDirectory: true
        )
    defer { try? fileManager.removeItem(at: root) }

    let recorder = ProductMetricsRecorder(directoryURL: root)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let retention = DiagnosticsRetentionPolicy(
        maxRecords: 2,
        retentionDays: 7,
        now: now
    )
    let environment = ProductMetricsEnvironment(
        productVersion: "0.1.0",
        productBuild: "1"
    )

    for (offset, event) in [
        (-8 * 24 * 60 * 60, ProductMetricEvent.appLaunch),
        (-2, .dictationStarted),
        (-1, .dictationSucceeded),
        (0, .retryStarted),
    ] {
        try recorder.record(
            ProductMetricSample(
                timestamp: now.addingTimeInterval(
                    TimeInterval(offset)
                ),
                environment: environment,
                event: event
            ),
            retention: retention
        )
    }

    #expect(
        try recorder.loadRecent(limit: 10).map(\.event)
            == [.dictationSucceeded, .retryStarted]
    )
    let dataURL = root.appendingPathComponent(
        "product-metrics.jsonl"
    )
    let attributes = try fileManager.attributesOfItem(
        atPath: dataURL.path
    )
    #expect(
        (attributes[.posixPermissions] as? NSNumber)?.intValue
            == 0o600
    )

    try recorder.prune(
        retention: DiagnosticsRetentionPolicy(
            maxRecords: 0,
            retentionDays: 1,
            now: now
        )
    )
    #expect(!fileManager.fileExists(atPath: dataURL.path))
}

@Test
func productMetricsRecorderRejectsSymbolicLinkStorage() throws {
    let fileManager = FileManager.default
    let parent = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = parent.appendingPathComponent(
        "OpenWhisper",
        isDirectory: true
    )
    let outside = parent.appendingPathComponent("outside.jsonl")
    try fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    try Data("keep".utf8).write(to: outside)
    try fileManager.createSymbolicLink(
        at: root.appendingPathComponent("product-metrics.jsonl"),
        withDestinationURL: outside
    )
    defer { try? fileManager.removeItem(at: parent) }

    let recorder = ProductMetricsRecorder(directoryURL: root)
    #expect(throws: ProductMetricsStorageError.self) {
        try recorder.record(
            ProductMetricSample(
                environment: ProductMetricsEnvironment(
                    productVersion: "0.1.0",
                    productBuild: "1"
                ),
                event: .appLaunch
            ),
            retention: DiagnosticsRetentionPolicy(
                maxRecords: 10,
                retentionDays: 30
            )
        )
    }
    #expect(try String(contentsOf: outside) == "keep")
}
