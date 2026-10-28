import AppKit
import Observation
import QuillCore
import SwiftUI

/// Плавающая «капсула» по центру сверху: запись, распознавание, итог.
/// Панель неактивируемая и пропускает клики, поэтому не мешает вставке текста.
@MainActor
@Observable
final class RecordingIndicator {
    private static let panelSize = NSSize(width: 380, height: 64)

    private(set) var model = RecordingIndicatorModel()
    private(set) var level: Double = 0

    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(isEnabled: @escaping @MainActor () -> Bool) {
        self.isEnabled = isEnabled
    }

    func recordingStarted(id: String, profileName: String) {
        model.recordingStarted(id: id, profileName: profileName, at: Date())
        update()
    }

    func recordingStopped() {
        level = 0
        model.recordingStopped()
        update()
    }

    func recordingCancelled() {
        level = 0
        model.recordingCancelled()
        update()
    }

    func apply(_ event: PipelineEvent) {
        model.apply(event)
        update()
    }

    func hide() {
        model.hide()
        update()
    }

    func setLevel(decibels: Float) {
        level = LevelMeter.normalized(decibels: decibels)
    }

    private func update() {
        hideTask?.cancel()
        guard model.phase != .hidden, isEnabled() else {
            panel?.orderOut(nil)
            return
        }
        showPanel()
        if let delay = model.autoHideDelay {
            let shownPhase = model.phase
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.model.phase == shownPhase else { return }
                self.model.hide()
                self.panel?.orderOut(nil)
            }
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let size = Self.panelSize
            panel.setFrame(NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height - 6,
                width: size.width, height: size.height
            ), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IndicatorView(indicator: self))
        return panel
    }
}

private struct IndicatorView: View {
    let indicator: RecordingIndicator

    var body: some View {
        content
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch indicator.model.phase {
        case .hidden:
            EmptyView()
        case .recording(let profileName, let startedAt):
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                LevelBars(level: indicator.level)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(Duration.seconds(max(0, context.date.timeIntervalSince(startedAt))),
                         format: .time(pattern: .minuteSecond))
                        .monospacedDigit()
                }
                Text(profileName).foregroundStyle(.secondary).lineLimit(1)
                Text("Esc — отмена").font(.caption).foregroundStyle(.tertiary)
            }
        case .transcribing:
            working("Распознаю…")
        case .postprocessing:
            working("Обрабатываю…")
        case .finished(.inserted):
            Label("Вставлено", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .finished(.copiedToClipboard):
            Label("В буфере обмена — нажмите ⌘V", systemImage: "doc.on.clipboard")
        case .finished(.cancelled):
            Label("Отменено", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .finished(.failed(let message)):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func working(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(title)
        }
    }
}

private struct LevelBars: View {
    let level: Double
    private let heights: [CGFloat] = [6, 10, 14, 10, 6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(level > Double(index) / Double(heights.count) ? Color.red : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: heights[index])
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
