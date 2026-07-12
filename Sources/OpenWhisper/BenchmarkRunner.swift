import AVFoundation
import Foundation

enum BenchmarkError: LocalizedError {
    case missingAudioFiles
    case unreadableAudioFile(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioFiles:
            return "Set OPENWHISPER_BENCHMARK_AUDIO_FILES to one or more local audio file paths."
        case .unreadableAudioFile(let path):
            return "Could not read benchmark audio file: \(path)"
        }
    }
}

private struct BenchmarkRunResult: Sendable {
    let fileLabel: String
    let mode: String
    let authMs: Int
    let transcribeMs: Int
    let normalizationMs: Int
    let totalMs: Int
    let error: String?
}

struct BenchmarkRunner {
    let config: AppConfig
    let authManager: any ChatGPTAuthProviding
    let environment: [String: String]
    let fileManager: FileManager

    init(
        config: AppConfig,
        authManager: any ChatGPTAuthProviding,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.config = config
        self.authManager = authManager
        self.environment = environment
        self.fileManager = fileManager
    }

    func run() async throws {
        let files = benchmarkAudioFiles()
        guard !files.isEmpty else {
            throw BenchmarkError.missingAudioFiles
        }

        let runs = Int(environment["OPENWHISPER_BENCHMARK_RUNS"] ?? "") ?? 5
        var results: [BenchmarkRunResult] = []

        for fileURL in files {
            let audio = try recordedAudio(from: fileURL)

            for _ in 0..<runs {
                let coldAuthManager = ChatGPTAuthManager(store: InMemoryChatGPTSessionStore())
                let coldPipeline = DictationPipeline(
                    transcriber: ChatGPTTranscriber(
                        authManager: coldAuthManager,
                        config: config.transcription
                    ),
                    normalizer: TerminologyNormalizer(
                        languagePreference: config.transcription.languagePreference,
                        punctuationPreference: config.transcription.punctuationPreference
                    ),
                    importedEntries: config.transcription.activeDictionaryEntries,
                    hintTerms: config.transcription.hintTerms
                )
                let coldStarted = DispatchTime.now().uptimeNanoseconds
                do {
                    let coldPrepared = try await coldPipeline.prepare(audio: audio)
                    results.append(
                        BenchmarkRunResult(
                            fileLabel: fileURL.lastPathComponent,
                            mode: "cold",
                            authMs: coldPrepared.metrics.transcription.authMs,
                            transcribeMs: coldPrepared.metrics.transcription.transcribeMs,
                            normalizationMs: coldPrepared.metrics.normalizationMs,
                            totalMs: elapsedMilliseconds(since: coldStarted),
                            error: nil
                        )
                    )
                } catch {
                    results.append(
                        BenchmarkRunResult(
                            fileLabel: fileURL.lastPathComponent,
                            mode: "cold",
                            authMs: 0,
                            transcribeMs: 0,
                            normalizationMs: 0,
                            totalMs: elapsedMilliseconds(since: coldStarted),
                            error: error.localizedDescription
                        )
                    )
                }
            }

            await authManager.prewarmSession()
            for _ in 0..<runs {
                let warmPipeline = DictationPipeline(
                    transcriber: ChatGPTTranscriber(
                        authManager: authManager,
                        config: config.transcription
                    ),
                    normalizer: TerminologyNormalizer(
                        languagePreference: config.transcription.languagePreference,
                        punctuationPreference: config.transcription.punctuationPreference
                    ),
                    importedEntries: config.transcription.activeDictionaryEntries,
                    hintTerms: config.transcription.hintTerms
                )
                let warmStarted = DispatchTime.now().uptimeNanoseconds
                do {
                    let warmPrepared = try await warmPipeline.prepare(audio: audio)
                    results.append(
                        BenchmarkRunResult(
                            fileLabel: fileURL.lastPathComponent,
                            mode: "warm",
                            authMs: warmPrepared.metrics.transcription.authMs,
                            transcribeMs: warmPrepared.metrics.transcription.transcribeMs,
                            normalizationMs: warmPrepared.metrics.normalizationMs,
                            totalMs: elapsedMilliseconds(since: warmStarted),
                            error: nil
                        )
                    )
                } catch {
                    results.append(
                        BenchmarkRunResult(
                            fileLabel: fileURL.lastPathComponent,
                            mode: "warm",
                            authMs: 0,
                            transcribeMs: 0,
                            normalizationMs: 0,
                            totalMs: elapsedMilliseconds(since: warmStarted),
                            error: error.localizedDescription
                        )
                    )
                }
            }
        }

        print(renderSummary(results: results))
    }

    private func benchmarkAudioFiles() -> [URL] {
        let rawValue = environment["OPENWHISPER_BENCHMARK_AUDIO_FILES"] ?? ""
        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    private func recordedAudio(from fileURL: URL) throws -> RecordedAudio {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw BenchmarkError.unreadableAudioFile(fileURL.path)
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let durationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        return RecordedAudio(
            fileURL: fileURL,
            durationMs: Int((durationSeconds * 1000).rounded())
        )
    }

    private func renderSummary(results: [BenchmarkRunResult]) -> String {
        let grouped = Dictionary(grouping: results) { "\($0.fileLabel) [\($0.mode)]" }
        let lines = grouped.keys.sorted().flatMap { key -> [String] in
            let runs = grouped[key] ?? []
            let successes = runs.filter { $0.error == nil }
            let authValues = successes.map(\.authMs)
            let transcribeValues = successes.map(\.transcribeMs)
            let totalValues = successes.map(\.totalMs)
            var section = [
                key,
                "  successes=\(successes.count)/\(runs.count)",
                "  auth_ms p50=\(percentile(authValues, 0.5)) p95=\(percentile(authValues, 0.95))",
                "  transcribe_ms p50=\(percentile(transcribeValues, 0.5)) p95=\(percentile(transcribeValues, 0.95))",
                "  total_ms p50=\(percentile(totalValues, 0.5)) p95=\(percentile(totalValues, 0.95))",
            ]
            let uniqueErrors = Array(Set(runs.compactMap(\.error))).sorted()
            section.append(contentsOf: uniqueErrors.map { "  error=\($0)" })
            return section
        }
        return lines.joined(separator: "\n")
    }

    private func percentile(_ values: [Int], _ fraction: Double) -> Int {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))
        return sorted[index]
    }

    private func elapsedMilliseconds(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
