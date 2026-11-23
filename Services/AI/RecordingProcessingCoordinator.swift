import Foundation
import FlashNoteCore

enum ProcessingStage: String {
    case transcribing = "正在转写"
    case minutes = "正在生成会议纪要"
    case mindMap = "正在生成思维导图"
    case insight = "正在生成洞察"
    case needsConfiguration = "等待配置 AI 服务"
    case completed = "全部内容已生成"
    case minutesCompleted = "会议纪要已更新"
    case failed = "处理未全部完成"
}

struct ProcessingProgress: Equatable {
    var stage: ProcessingStage
    var finishedSteps: Int
    var detail: String?
    var totalSteps: Int = 3
    var fraction: Double { Double(finishedSteps) / Double(max(1, totalSteps)) }
    var isActive: Bool { [.transcribing, .minutes, .insight].contains(stage) }
}

enum WorkflowNoticeKind: Equatable {
    case downloadStarted, downloadCompleted, downloadFailed
    case transcriptionStarted, transcriptionCompleted, transcriptionFailed
    case minutesStarted, minutesCompleted, minutesFailed
}

struct WorkflowNotice {
    let kind: WorkflowNoticeKind
    let title: String
    let detail: String?
}

/// 导入、设备下载和手动重试共用的内容生成任务。百分比仅表示四个阶段的完成数；
/// AI 单次请求没有可靠字节进度，界面在当前阶段使用不确定进度指示。
@Observable
final class RecordingProcessingCoordinator {
    private let store: RecordingStore
    @ObservationIgnored private let settingsFactory: () -> AppSettings
    @ObservationIgnored private let clientFactory: (URL, String, String) -> any LLMClient
    @ObservationIgnored private let notify: (WorkflowNotice) -> Void
    private(set) var progress: [UUID: ProcessingProgress] = [:]
    private(set) var revision = 0
    private var running: Set<UUID> = []
    @ObservationIgnored private var minutesTasks: [UUID: Task<Void, Never>] = [:]

    init(store: RecordingStore,
         settingsFactory: @escaping () -> AppSettings = { AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory()) },
         clientFactory: @escaping (URL, String, String) -> any LLMClient = { url, key, model in
             OpenAICompatibleClient(configuration: .init(baseURL: url, apiKey: key, model: model))
         }, notify: @escaping (WorkflowNotice) -> Void = { _ in }) {
        self.store = store
        self.settingsFactory = settingsFactory
        self.clientFactory = clientFactory
        self.notify = notify
    }

    func beginTranscription(_ id: UUID, title: String? = nil) {
        progress[id] = ProcessingProgress(stage: .transcribing, finishedSteps: 0)
        revision += 1
        emit(.transcriptionStarted, recordingID: id, titleOverride: title)
    }

    func transcriptionCompleted(_ id: UUID) {
        emit(.transcriptionCompleted, recordingID: id)
    }

    func transcriptionFailed(_ id: UUID, error: Error) {
        progress[id] = ProcessingProgress(stage: .failed, finishedSteps: 0, detail: "转写失败：\(error.localizedDescription)")
        revision += 1
        emit(.transcriptionFailed, recordingID: id, detail: error.localizedDescription)
    }

    func downloadStarted(title: String) { notify(WorkflowNotice(kind: .downloadStarted, title: title, detail: nil)) }
    func downloadCompleted(title: String) { notify(WorkflowNotice(kind: .downloadCompleted, title: title, detail: nil)) }
    func downloadFailed(title: String, error: Error) {
        notify(WorkflowNotice(kind: .downloadFailed, title: title, detail: error.localizedDescription))
    }

    /// 应用级任务持有重新生成操作，离开详情页后仍会继续并更新持久化结果。
    func regenerateMinutes(recordingID id: UUID, template: MinutesTemplate) {
        guard !running.contains(id) else { return }
        running.insert(id)
        progress[id] = ProcessingProgress(stage: .minutes, finishedSteps: 0, totalSteps: 1)
        revision += 1
        emit(.minutesStarted, recordingID: id)
        minutesTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.running.remove(id)
                self.minutesTasks[id] = nil
            }
            await self.performMinutesRegeneration(recordingID: id, template: template)
        }
    }

    func waitForMinutesGeneration(recordingID id: UUID) async {
        await minutesTasks[id]?.value
    }

    private func performMinutesRegeneration(recordingID id: UUID, template: MinutesTemplate) async {
        let startedAt = Date()
        do {
            guard let transcript = try store.fetchTranscript(recordingID: id),
                  !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionError.engineFailed("缺少有效的全文转写")
            }
            let settings = settingsFactory()
            guard !settings.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let baseURL = URL(string: settings.llmBaseURL) else {
                progress[id] = ProcessingProgress(stage: .needsConfiguration, finishedSteps: 0,
                                                  detail: "请先在设置中填写 AI 服务的地址、模型和 API Key。", totalSteps: 1)
                revision += 1
                emit(.minutesFailed, recordingID: id, detail: "AI 服务尚未配置")
                return
            }
            let client = clientFactory(baseURL, settings.llmAPIKey, settings.llmModel)
            let result = try await MinutesGenerator(client: client).generate(
                transcript: transcript.fullText, template: template, recordingID: id
            )
            guard var recording = try store.fetchRecording(id: id) else {
                progress[id] = ProcessingProgress(stage: .failed, finishedSteps: 0,
                                                  detail: "录音已删除，纪要未保存", totalSteps: 1)
                revision += 1
                return
            }
            try store.upsertMinutes(result)
            if let title = RecordingTitle.shortTitle(from: result) { recording.title = title }
            recording.markSummarized()
            try store.upsertRecording(recording)
            progress[id] = ProcessingProgress(stage: .minutesCompleted, finishedSteps: 1, totalSteps: 1)
            revision += 1
            emit(.minutesCompleted, recordingID: id,
                 detail: "用时 \(Int(Date().timeIntervalSince(startedAt).rounded())) 秒")
        } catch {
            progress[id] = ProcessingProgress(stage: .failed, finishedSteps: 0,
                                              detail: "纪要生成失败：\(error.localizedDescription)", totalSteps: 1)
            revision += 1
            emit(.minutesFailed, recordingID: id, detail: error.localizedDescription)
        }
    }

    private func emit(_ kind: WorkflowNoticeKind, recordingID id: UUID, detail: String? = nil,
                      titleOverride: String? = nil) {
        let recording = try? store.fetchRecording(id: id)
        let title = titleOverride ?? recording?.title ?? "录音"
        notify(WorkflowNotice(kind: kind, title: title, detail: detail))
    }

    func generateAll(recordingID id: UUID) async {
        guard !running.contains(id) else { return }
        running.insert(id)
        defer { running.remove(id) }

        guard let transcript = try? store.fetchTranscript(recordingID: id),
              !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            progress[id] = ProcessingProgress(stage: .failed, finishedSteps: 0, detail: "缺少有效的全文转写")
            revision += 1
            return
        }

        let settings = settingsFactory()
        guard !settings.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let baseURL = URL(string: settings.llmBaseURL) else {
            progress[id] = ProcessingProgress(stage: .needsConfiguration, finishedSteps: 1,
                                              detail: "转写已保存。请在设置中填写 AI Key，然后在详情页继续生成。")
            revision += 1
            return
        }

        let client = clientFactory(baseURL, settings.llmAPIKey, settings.llmModel)
        let generator = MinutesGenerator(client: client)
        var failures: [String] = []
        let jobs: [(ProcessingStage, MinutesTemplate)] = [(.minutes, .defaultTemplate), (.insight, .insight)]
        for (index, job) in jobs.enumerated() {
            progress[id] = ProcessingProgress(stage: job.0, finishedSteps: index + 1)
            revision += 1
            if job.0 == .minutes { emit(.minutesStarted, recordingID: id) }
            let startedAt = Date()
            do {
                let result = try await generator.generate(transcript: transcript.fullText, template: job.1, recordingID: id)
                guard try store.fetchRecording(id: id) != nil else { return }
                try store.upsertMinutes(result)
                if job.0 == .minutes, var recording = try store.fetchRecording(id: id) {
                    if let title = RecordingTitle.shortTitle(from: result) { recording.title = title }
                    recording.markSummarized()
                    try store.upsertRecording(recording)
                }
                if job.0 == .minutes {
                    emit(.minutesCompleted, recordingID: id,
                         detail: "用时 \(Int(Date().timeIntervalSince(startedAt).rounded())) 秒")
                }
            } catch {
                failures.append("\(job.0.rawValue)：\(error.localizedDescription)")
                if job.0 == .minutes { emit(.minutesFailed, recordingID: id, detail: error.localizedDescription) }
            }
        }
        progress[id] = ProcessingProgress(stage: failures.isEmpty ? .completed : .failed,
                                          finishedSteps: 3, detail: failures.isEmpty ? nil : failures.joined(separator: "；"))
        revision += 1
    }
}
