import SwiftUI
import UniformTypeIdentifiers
import FlashNoteCore

struct RecordingTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, UTType(filenameExtension: "md") ?? .plainText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct TodoCalendarSheet: View {
    let initialTitle: String
    let recordingTitle: String
    let onComplete: (Result<Void, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var startDate: Date
    @State private var durationMinutes = 30
    @State private var isSaving = false

    init(title: String, recordingTitle: String, onComplete: @escaping (Result<Void, Error>) -> Void) {
        self.initialTitle = title
        self.recordingTitle = recordingTitle
        self.onComplete = onComplete
        _title = State(initialValue: title)
        _startDate = State(initialValue: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0,
            of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("加入本机日历").font(.title2.bold())
            TextField("待办事项", text: $title)
            DatePicker("开始时间", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
            Picker("预计时长", selection: $durationMinutes) {
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
                Text("1 小时").tag(60)
            }
            Text("将保存到系统默认日历；首次使用时系统会请求日历写入权限。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(isSaving ? "保存中…" : "加入日历") {
                    isSaving = true
                    Task {
                        do {
                            try await CalendarTodoService().add(title: title, start: startDate,
                                duration: TimeInterval(durationMinutes * 60), notes: "来自 FlashNote 纪要：\(recordingTitle)")
                            onComplete(.success(()))
                            dismiss()
                        } catch {
                            onComplete(.failure(error))
                            isSaving = false
                        }
                    }
                }.buttonStyle(.borderedProminent).disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
    }
}
