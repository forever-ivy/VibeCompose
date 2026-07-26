import Foundation
import Testing
@testable import VibeCompose

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
            "VibeComposeProductMetrics-\(UUID().uuidString)",
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
        "VibeCompose",
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

@Test
func productMetricsReportAggregatesOnlyApprovedDimensions() throws {
    let eventTimestamp = Date(timeIntervalSince1970: 100)
    let generatedAt = Date(timeIntervalSince1970: 200)
    let samples = [
        ProductMetricSample(
            timestamp: eventTimestamp,
            environment: ProductMetricsEnvironment(
                productVersion: "PRIVATE /Users/alice",
                productBuild: "42"
            ),
            event: .dictationSucceeded,
            provider: .chatGPTManagedAuth,
            audioDurationMs: 7_000,
            totalProcessingMs: 3_000,
            deliveryStatus: .insertedVerified
        ),
        ProductMetricSample(
            timestamp: eventTimestamp.addingTimeInterval(1),
            environment: ProductMetricsEnvironment(
                productVersion: "0.1.0",
                productBuild: "42"
            ),
            event: .dictationFailed,
            provider: .chatGPTManagedAuth,
            audioDurationMs: 7_000,
            totalProcessingMs: 3_000,
            failureCategory: .transcription
        ),
    ]
    let report = ProductMetricsReport(
        samples: samples,
        generatedAt: generatedAt
    )

    #expect(report.sampleCount == 2)
    #expect(report.eventCounts["dictation_succeeded"] == 1)
    #expect(report.eventCounts["dictation_failed"] == 1)
    #expect(report.providerCounts["chatGPTManagedAuth"] == 2)
    #expect(report.audioDurationBucketCounts["5_to_15s"] == 2)
    #expect(report.latencyBucketCounts["2_to_5s"] == 2)
    #expect(report.deliveryStatusCounts["inserted_verified"] == 1)
    #expect(report.failureCategoryCounts["transcription"] == 1)
    #expect(report.productVersionCounts["other"] == 1)
    #expect(report.productVersionCounts["0.1.0"] == 1)
    #expect(report.productBuildCounts["42"] == 2)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let text = String(
        data: try encoder.encode(report),
        encoding: .utf8
    ) ?? ""
    #expect(!text.contains("PRIVATE"))
    #expect(!text.contains("1970-01-01T00:01:40Z"))
    #expect(!text.contains("timestamp"))
    #expect(!text.contains("identifier"))
    #expect(!text.contains("path"))
    #expect(!text.contains("account"))
}

@Test
func productMetricsExporterWritesOwnerOnlyAggregateJSON() throws {
    let fileManager = FileManager.default
    let parent = fileManager.temporaryDirectory
        .appendingPathComponent(
            "VibeComposeProductMetricsExport-\(UUID().uuidString)",
            isDirectory: true
        )
    let applicationSupportURL = parent.appendingPathComponent(
        "VibeCompose",
        isDirectory: true
    )
    let outputURL = parent.appendingPathComponent("metrics")
    try fileManager.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
    )
    defer { try? fileManager.removeItem(at: parent) }

    let now = Date(timeIntervalSince1970: 2_000_000)
    try ProductMetricsRecorder(
        directoryURL: applicationSupportURL
    ).record(
        ProductMetricSample(
            timestamp: now,
            environment: ProductMetricsEnvironment(
                productVersion: "0.1.0",
                productBuild: "1"
            ),
            event: .appLaunch
        ),
        retention: DiagnosticsRetentionPolicy(
            maxRecords: 10,
            retentionDays: 30,
            now: now
        )
    )

    let exportedURL = try ProductMetricsExporter(
        applicationSupportURL: applicationSupportURL
    ).export(
        to: outputURL,
        generatedAt: now
    )

    #expect(exportedURL.pathExtension == "json")
    let data = try Data(contentsOf: exportedURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let report = try decoder.decode(
        ProductMetricsReport.self,
        from: data
    )
    #expect(report.sampleCount == 1)
    #expect(report.eventCounts == ["app_launch": 1])
    let attributes = try fileManager.attributesOfItem(
        atPath: exportedURL.path
    )
    #expect(
        (attributes[.posixPermissions] as? NSNumber)?.intValue
            == 0o600
    )
}

@Test
func productMetricsExporterRefusesToReplaceDirectory() throws {
    let fileManager = FileManager.default
    let parent = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destination = parent.appendingPathComponent(
        "metrics.json",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: destination,
        withIntermediateDirectories: true
    )
    defer { try? fileManager.removeItem(at: parent) }

    let exporter = ProductMetricsExporter(
        applicationSupportURL: parent.appendingPathComponent(
            "VibeCompose",
            isDirectory: true
        )
    )
    #expect(throws: ProductMetricsExportError.self) {
        try exporter.export(to: destination)
    }
}
