import AVFoundation
import QuillCore
import SwiftUI

struct HistoryView: View {
    let controller: AppController
    @State private var query = ""
    @State private var records: [DictationRecord] = []
    @State private var selection: DictationRecord.ID?
    @State private var monthCost: Double = 0
    @State private var loadError: String?

    private var reloadKey: String { "\(query)|\(controller.pipeline.historyRevision)" }

    var body: some View {
        NavigationSplitView {
            List(records, selection: $selection) { record in
                HistoryRow(record: record, profileName: profileName(record.profileID))
            }
            .searchable(text: $query, prompt: "Поиск по тексту")
            .safeAreaInset(edge: .bottom) {
                Text("Расход за месяц: $\(monthCost, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if let record = records.first(where: { $0.id == selection }) {
                HistoryDetail(controller: controller, record: record)
            } else if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                Text("Выберите запись").foregroundStyle(.secondary)
            }
        }
        .task(id: reloadKey) { reload() }
    }

    private func reload() {
        do {
            records = try controller.history.search(query)
            let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
            monthCost = try controller.history.totalCost(since: startOfMonth)
            loadError = nil
        } catch {
            loadError = "Не удалось прочитать историю: \(error.localizedDescription)"
        }
    }

    private func profileName(_ id: String) -> String {
        controller.profiles.profile(id: id)?.name ?? id
    }
}

private struct HistoryRow: View {
    let record: DictationRecord
    let profileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.createdAt, format: .dateTime.day().month().hour().minute())
                Text(profileName).foregroundStyle(.secondary)
                Spacer()
                if record.status == .failed {
                    Text("ошибка").foregroundStyle(.red)
                } else if record.postprocessFailed {
                    Text("без обработки").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            Text(record.displayText.split(separator: "\n").first.map(String.init) ?? "—")
                .lineLimit(1)
            Text("\(record.durationSec, specifier: "%.1f") с · $\(record.costUSD, specifier: "%.4f")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryDetail: View {
    let controller: AppController
    let record: DictationRecord
    @State private var player: AVAudioPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = record.error {
                    Text(error).foregroundStyle(.red)
                }
                section("Итоговый текст", record.finalText)
                section("Сырой текст", record.rawText)

                HStack {
                    Button("Копировать") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.displayText, forType: .string)
                    }
                    .disabled(record.displayText.isEmpty)

                    Menu("Обработать заново профилем…") {
                        ForEach(controller.profiles.validProfiles) { profile in
                            Button(profile.name) {
                                Task { await controller.pipeline.reprocess(id: record.id, profile: profile) }
                            }
                        }
                    }
                    .disabled(record.rawText == nil)

                    Button("Распознать заново") {
                        Task { await controller.pipeline.retranscribe(id: record.id) }
                    }
                    .disabled(record.audioFileName == nil)

                    Button(player?.isPlaying == true ? "Стоп" : "Прослушать") { togglePlayback() }
                        .disabled(record.audioFileName == nil)

                    Spacer()

                    Button("Удалить", role: .destructive) {
                        player?.stop()
                        controller.pipeline.delete(id: record.id)
                    }
                }

                Text("Модели: \(record.transcriptionModel ?? "—") / \(record.llmModel ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: record.id) { _, _ in
            player?.stop()
            player = nil
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text ?? "—").textSelection(.enabled)
        }
    }

    private func togglePlayback() {
        if let player, player.isPlaying {
            player.stop()
            self.player = nil
            return
        }
        guard let fileName = record.audioFileName else { return }
        player = try? AVAudioPlayer(contentsOf: controller.audio.url(for: fileName))
        player?.play()
    }
}
