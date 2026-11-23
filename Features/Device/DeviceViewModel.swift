import Foundation
import FlashNoteCore
import CoreBluetooth

/// 设备面板状态机：扫描/连接/设备信息/文件列表/下载+转写/录音控制。
@Observable
final class DeviceViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var battery: Int?
    private(set) var firmware: String?
    private(set) var recordState: UInt8?
    private(set) var files: [CB08FileEntry] = []
    private(set) var statusText = "扫描以连接 CB08 录音笔"
    private(set) var progress: Double = 0
    private(set) var activeDownloadFile: CB08FileEntry?
    private(set) var activeDownloadIndex: Int?
    private(set) var discovered: [CBPeripheral] = []
    private(set) var deletingFileName: String?
    var isDeletingFiles: Bool { deletingFileName != nil }
    private(set) var downloadedDeviceNames: Set<String> = []
    private(set) var realtimeStatus = "未开始推流"
    private(set) var realtimeSeconds: TimeInterval = 0
    private(set) var realtimePackets = 0
    private(set) var realtimeSegments: [TranscriptSegment] = []
    private(set) var realtimePartialText: String?
    private(set) var realtimeRecognitionIssue: String?
    private(set) var isRealtimeStarting = false
    private(set) var streamStartedRecording = false
    private var isRealtimePaused = false
    var isRealtimeActive: Bool { realtimeCapture != nil }

    static func displayedRecordState(reported: UInt8, streamPaused: Bool, streamActive: Bool) -> UInt8 {
        streamActive && streamPaused && reported == 1 ? 3 : reported
    }

    private let central: CB08Central
    private let store: RecordingStore
    private let processing: RecordingProcessingCoordinator
    private var device: CB08Device?
    private var transcription: DeviceTranscriptionService?
    private var seq: UInt8 = 0
    private var scanGeneration = 0
    private var currentRecordingID: UUID?
    private var realtimeCapture: DeviceRealtimeCapture?
    private var realtimeTitle = ""
    private var recordCommandGeneration = 0
    private var recordStateTimer: Timer?
    private var lastRecordStateResponseAt = Date()
    private var queuedFileDeletions: [CB08FileEntry] = []
    private var deletionBatchTotal = 0
    private var deletionBatchCompleted = 0
    private var deletionAcknowledged = false

    init(store: RecordingStore, processing: RecordingProcessingCoordinator) {
        self.central = CB08Central.shared
        self.store = store
        self.processing = processing
        wireCentral()
    }

    func scan() {
        scanGeneration += 1
        let generation = scanGeneration
        discovered = []
        guard central.scan() else {
            phase = .error("蓝牙不可用")
            statusText = "蓝牙不可用，请开启后重试"
            return
        }
        phase = .scanning
        statusText = "正在扫描…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.scanGeneration == generation, self.phase == .scanning else { return }
            self.central.stopScan()
            self.phase = .idle
            self.statusText = self.discovered.isEmpty
                ? "未发现录音笔，请确认设备处于可发现状态后重试"
                : "扫描结束，发现 \(self.discovered.count) 台设备"
        }
    }

    func connect(to peripheral: CBPeripheral) {
        scanGeneration += 1
        phase = .connecting
        statusText = "正在连接 \(peripheral.name ?? "CB08")…"
        central.connect(peripheral)
    }

    func disconnect() {
        recordStateTimer?.invalidate()
        recordStateTimer = nil
        finishRealtime(sendStop: true)
        scanGeneration += 1
        central.stopScan()
        central.disconnect()
        device = nil
        transcription = nil
        phase = .idle
        files = []
        battery = nil
        firmware = nil
        statusText = "已断开，可重新扫描连接"
    }

    /// 视图出现时重新绑定单例中央的回调并恢复连接态。
    func onAppear() {
        wireCentral()
        refreshDownloadedNames()
        if central.isConnected {
            phase = .connected
            statusText = "已连接"
        } else {
            statusText = "蓝牙可用，请扫描并连接设备"
        }
    }

    func refreshInfo() {
        device?.requestBattery()
        device?.requestVersion()
        device?.recordState()
        device?.requestFileList()
    }

    func downloadAndTranscribe(file: CB08FileEntry, index: Int) {
        guard let transcription else {
            statusText = "设备未连接"
            return
        }
        guard activeDownloadFile == nil else { return }
        activeDownloadFile = file
        activeDownloadIndex = index
        progress = 0
        statusText = "下载并转写中…"
        processing.downloadStarted(title: file.displayName)
        Task {
            defer {
                activeDownloadFile = nil
                activeDownloadIndex = nil
                progress = 0
                refreshDownloadedNames()
            }
            statusText = "下载并转写中…"
            do {
                let transcript = try await transcription.downloadAndTranscribe(file: file, title: "")
                processing.transcriptionCompleted(transcript.recordingID)
                refreshDownloadedNames()
                statusText = "已转写：\(transcript.fullText.count) 字；AI 内容正在后台生成，可在文件页查看进度"
                let id = transcript.recordingID
                Task { await processing.generateAll(recordingID: id) }
            } catch DeviceError.incompleteDownload {
                statusText = "下载中断，已保留进度；重新点击即可从断点继续"
                processing.downloadFailed(title: file.displayName, error: DeviceError.incompleteDownload)
            } catch TranscriptionError.engineUnavailable {
                statusText = "录音已保存到本地；当前转写引擎不可用，可在录音详情中重试"
                if let currentRecordingID { processing.transcriptionFailed(currentRecordingID, error: TranscriptionError.engineUnavailable) }
            } catch {
                statusText = "失败：\(error.localizedDescription)"
                if let currentRecordingID { processing.transcriptionFailed(currentRecordingID, error: error) }
                else { processing.downloadFailed(title: file.displayName, error: error) }
            }
            currentRecordingID = nil
        }
    }

    func deleteFile(_ file: CB08FileEntry) {
        deleteFiles([file])
    }

    func deleteFiles(_ selected: [CB08FileEntry]) {
        guard phase == .connected, let device else {
            statusText = "设备未连接"
            return
        }
        guard deletingFileName == nil, activeDownloadFile == nil else { return }
        let names = Set(selected.map(\.displayName))
        queuedFileDeletions = files.filter { names.contains($0.displayName) }
        guard !queuedFileDeletions.isEmpty else { return }
        deletionBatchTotal = queuedFileDeletions.count
        deletionBatchCompleted = 0
        startNextFileDeletion(using: device)
    }

    private func startNextFileDeletion(using device: CB08Device) {
        guard let file = queuedFileDeletions.first else {
            deletingFileName = nil
            statusText = "已删除 \(deletionBatchCompleted) 个设备文件"
            return
        }
        deletingFileName = file.displayName
        deletionAcknowledged = false
        statusText = "正在删除设备文件（\(deletionBatchCompleted + 1)/\(deletionBatchTotal)）…"
        device.deleteFile(file)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.deletingFileName == file.displayName else { return }
            self.device?.requestFileList()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.deletingFileName == file.displayName else { return }
                self.queuedFileDeletions = []
                self.deletingFileName = nil
                self.statusText = "设备未响应删除请求，已停止批量删除并恢复连接"
                self.central.recoverUnresponsiveConnection()
            }
        }
    }

    func isDownloaded(_ file: CB08FileEntry) -> Bool { downloadedDeviceNames.contains(file.displayName) }

    private func refreshDownloadedNames() {
        downloadedDeviceNames = Set(((try? store.fetchRecordings()) ?? []).flatMap { recording in
            [recording.sourceDeviceName, recording.title.hasPrefix("note") ? recording.title : nil].compactMap { $0 }
        })
    }

    func recordStart() {
        guard phase == .connected else { statusText = "设备未连接"; return }
        statusText = "正在通过推流接口开始设备录音…"
        realtimeStart()
    }
    func recordPause(paused: Bool) {
        guard phase == .connected, let device else { statusText = "设备未连接"; return }
        statusText = paused ? "正在暂停设备录音…" : "正在继续设备录音…"
        if isRealtimeActive {
            device.realtimePause(paused: paused)
        } else {
            device.recordPause(paused: paused)
            device.recordState()
        }
    }
    func recordSave() {
        guard phase == .connected, let device else { statusText = "设备未连接"; return }
        statusText = "正在通过推流接口停止并保存设备录音…"
        if realtimeCapture != nil { finishRealtime(sendStop: true) }
        else { device.stopRealtime() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.phase == .connected else { return }
            self.device?.recordState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.phase == .connected, self.recordState == 1 || self.recordState == 3 else { return }
                self.statusText = "设备仍在录音；请用录音笔按键结束并保存"
            }
        }
    }
    func realtimeStart() {
        guard phase == .connected, let device, realtimeCapture == nil, !isRealtimeStarting else {
            realtimeStatus = "设备未连接或推流已开始"
            return
        }
        isRealtimeStarting = true
        realtimeStatus = "正在准备实时推流…"
        Task {
            let authorization = await SpeechAuthorization.requestPermissions()
            let locale = UserDefaults.standard.string(forKey: "liveTranscriptionLocale") ?? "zh-CN"
            let speech = authorization == nil
                ? (SpeechEngine(locale: Locale(identifier: locale)) ?? SpeechEngine())
                : nil
            let id = UUID()
            do {
                let capture = try DeviceRealtimeCapture(recordingID: id,
                    storeDirectory: AppEnvironment.defaultStoreDirectory(), speech: speech,
                    onPartial: { [weak self] text in self?.realtimePartialText = text },
                    onSegment: { [weak self] segment in self?.realtimeSegments.append(segment) },
                    onRecognitionError: { [weak self] error in
                        self?.realtimeRecognitionIssue = "实时识别失败：\(error.localizedDescription)"
                    })
                guard self.phase == .connected else {
                    _ = try? capture.finish()
                    isRealtimeStarting = false
                    return
                }
                realtimeCapture = capture
                isRealtimePaused = false
                streamStartedRecording = recordState != 1 && recordState != 3
                realtimeTitle = RecorderViewModel.hardwareStyleTitle(at: Date())
                realtimeSeconds = 0
                realtimePackets = 0
                realtimeSegments = []
                realtimePartialText = nil
                realtimeRecognitionIssue = authorization == nil
                    ? (speech == nil ? "当前语言的系统实时识别不可用；停止后仍会转写音频" : nil)
                    : "语音识别权限不可用；停止后仍会转写音频"
                realtimeStatus = speech == nil ? "正在接收设备音频；停止后会进行文件转写" : "正在等待设备音频…"
                isRealtimeStarting = false
                device.startRealtime()
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    guard let self, self.realtimeCapture === capture, capture.packetCount == 0 else { return }
                    self.realtimeStatus = "设备未返回音频，请检查录音笔状态后重试"
                }
            } catch {
                isRealtimeStarting = false
                realtimeStatus = "推流启动失败：\(error.localizedDescription)"
            }
        }
    }

    func realtimeStop() { finishRealtime(sendStop: true) }

    private func handleRealtimeAudio(_ data: Data) {
        guard let capture = realtimeCapture else { return }
        do {
            try capture.append(data)
            realtimePackets = capture.packetCount
            realtimeSeconds = capture.duration
            if !isRealtimePaused { realtimeStatus = "正在接收录音笔音频 · \(realtimePackets) 包" }
        } catch {
            realtimeStatus = "实时音频解码失败：\(error.localizedDescription)"
            finishRealtime(sendStop: true)
        }
    }

    private func finishRealtime(sendStop: Bool) {
        guard let capture = realtimeCapture else { return }
        if sendStop { device?.stopRealtime() }
        realtimeCapture = nil
        isRealtimePaused = false
        streamStartedRecording = false
        do {
            let liveTranscript = try capture.finish()
            guard capture.packetCount > 0 else {
                realtimeStatus = "未收到设备音频；未创建空录音"
                return
            }
            let id = capture.recordingID
            var recording = Recording(id: id, title: realtimeTitle)
            recording.audioFilename = capture.audioURL.lastPathComponent
            recording.duration = capture.duration
            try store.upsertRecording(recording)
            if let liveTranscript, !liveTranscript.fullText.isEmpty {
                try store.upsertTranscript(liveTranscript)
                recording.markTranscribed()
                try store.upsertRecording(recording)
            }
            realtimeStatus = "已保存设备音频，正在后台转写；可在文件页查看"
            processing.beginTranscription(id)
            Task {
                do {
                    let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
                    let service = RecordingTranscriptionService(store: store,
                        engine: FileTranscriptionEngineFactory.make(settings: settings))
                    _ = try await service.transcribe(recording)
                    processing.transcriptionCompleted(id)
                    await processing.generateAll(recordingID: id)
                    realtimeStatus = "设备推流已保存并完成处理"
                } catch {
                    if liveTranscript?.fullText.isEmpty == false {
                        processing.transcriptionCompleted(id)
                        await processing.generateAll(recordingID: id)
                        realtimeStatus = "设备推流已保存，已使用实时转写结果"
                    } else {
                        processing.transcriptionFailed(id, error: error)
                        realtimeStatus = "音频已保存；转写失败：\(error.localizedDescription)"
                    }
                }
            }
        } catch {
            realtimeStatus = "停止推流失败：\(error.localizedDescription)"
        }
    }

    private func wireCentral() {
        central.onDiscovered = { [weak self] peripheral in
            guard let self else { return }
            if !self.discovered.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discovered.append(peripheral)
            }
            self.statusText = "发现 \(self.discovered.count) 台设备，点击连接"
        }
        central.onPoweredOn = { [weak self] powered in
            self?.statusText = powered ? "蓝牙可用，请扫描并连接设备" : "蓝牙不可用"
        }
        central.onAutoReconnect = { [weak self] in
            self?.phase = .connecting
            self?.statusText = "自动重连上次设备…"
        }
        central.onPeripheralConnected = { [weak self] in
            guard let self else { return }
            let device = CB08Device(transport: self.central, seqGenerator: { self.nextSeq() })
            self.device = device
            device.onBattery = { self.battery = $0 }
            device.onFileList = { list in
                self.files = list.sorted {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending
                }
                if let deletingFileName = self.deletingFileName {
                    if !list.contains(where: { $0.displayName == deletingFileName }) {
                        self.deletionBatchCompleted += 1
                        self.queuedFileDeletions.removeFirst()
                        self.deletingFileName = nil
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.phase == .connected, let device = self.device else { return }
                            self.startNextFileDeletion(using: device)
                        }
                    } else if self.deletionAcknowledged {
                        self.queuedFileDeletions = []
                        self.deletingFileName = nil
                        self.statusText = "设备仍保留 \(deletingFileName)，已停止批量删除"
                    }
                }
            }
            device.onFirmware = { self.firmware = $0 }
            device.onRecordState = { state in
                self.lastRecordStateResponseAt = Date()
                let wasRecording = self.recordState == 1 || self.recordState == 3
                let effectiveState = Self.displayedRecordState(reported: state,
                    streamPaused: self.isRealtimePaused, streamActive: self.realtimeCapture != nil)
                self.recordState = effectiveState
                if effectiveState == 1 && !wasRecording {
                    self.recordCommandGeneration += 1
                    self.statusText = "设备正在录音"
                }
                if wasRecording && state == 2 {
                    self.recordCommandGeneration += 1
                    self.statusText = "设备已停止并保存录音"
                    if self.realtimeCapture != nil { self.finishRealtime(sendStop: false) }
                    self.device?.requestFileList()
                }
            }
            device.onRecordCommandResult = { [weak self] command, result in
                guard let self else { return }
                let action = switch command {
                case 2: "开始录音"
                case 4: "停止并保存"
                case 6: "暂停录音"
                default: "继续录音"
                }
                self.statusText = result == 1 ? "设备已执行：\(action)" : "设备拒绝\(action)（返回 \(result)）"
                self.device?.recordState()
                if command == 4, result == 1 { self.device?.requestFileList() }
            }
            device.onRealtimeAudio = { [weak self] data in self?.handleRealtimeAudio(data) }
            device.onRealtimeState = { [weak self] state in
                guard let self else { return }
                if self.realtimeCapture != nil {
                    switch state {
                    case 0:
                        self.isRealtimePaused = false
                        self.recordState = 1
                        self.statusText = "设备已继续录音"
                        self.realtimeStatus = "正在接收设备音频"
                    case 1:
                        self.isRealtimePaused = true
                        self.recordState = 3
                        self.statusText = "设备已暂停录音"
                        self.realtimeStatus = "设备录音已暂停"
                    case 2:
                        self.isRealtimePaused = false
                        self.recordState = 2
                        self.finishRealtime(sendStop: false)
                    default: break
                    }
                }
            }
            device.onFileDeleteResult = { [weak self] code in
                guard let self else { return }
                if code == 0 {
                    self.deletionAcknowledged = true
                    self.statusText = "设备确认删除，正在核对文件列表…"
                    self.device?.requestFileList()
                } else if code == 0xFF {
                    self.queuedFileDeletions = []
                    self.deletingFileName = nil
                    self.statusText = "设备文件名无效，无法安全删除"
                } else {
                    self.queuedFileDeletions = []
                    self.deletingFileName = nil
                    self.statusText = "设备拒绝删除（返回 \(code)）；文件仍在设备上"
                    self.device?.requestFileList()
                }
            }
            let settings = AppSettings(storeDirectory: AppEnvironment.defaultStoreDirectory())
            self.transcription = DeviceTranscriptionService(
                device: device,
                engine: FileTranscriptionEngineFactory.make(settings: settings),
                store: self.store
            )
            self.transcription?.onProgress = { [weak self] p, status in
                self?.progress = p
                self?.statusText = status
            }
            self.transcription?.onRecordingCreated = { [weak self] id in
                self?.currentRecordingID = id
                if let title = self?.activeDownloadFile?.displayName { self?.processing.downloadCompleted(title: title) }
                self?.processing.beginTranscription(id)
            }
            self.phase = .connected
            self.statusText = "已连接，读取设备信息…"
            self.lastRecordStateResponseAt = Date()
            self.refreshInfo()
            self.recordStateTimer?.invalidate()
            self.recordStateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self, self.phase == .connected, self.activeDownloadFile == nil,
                      self.device != nil else { return }
                if self.realtimeCapture == nil, Date().timeIntervalSince(self.lastRecordStateResponseAt) > 18 {
                    self.statusText = "设备无响应，正在恢复蓝牙连接"
                    self.recordStateTimer?.invalidate()
                    self.recordStateTimer = nil
                    self.central.recoverUnresponsiveConnection()
                    return
                }
                self.device?.recordState()
            }
        }
        central.onPeripheralDisconnected = { [weak self] in
            self?.queuedFileDeletions = []
            self?.deletingFileName = nil
            self?.recordStateTimer?.invalidate()
            self?.recordStateTimer = nil
            self?.finishRealtime(sendStop: false)
            self?.phase = .idle
            self?.statusText = "设备已断开"
        }
        central.onError = { [weak self] msg in
            self?.central.stopScan()
            self?.phase = .error(msg)
        }
    }

    private func nextSeq() -> UInt8 {
        defer { seq &+= 1 }
        return seq
    }
}
