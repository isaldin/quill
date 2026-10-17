import Foundation

/// Какую картинку показывать в строке меню.
public enum StatusIcon: Equatable, Sendable {
    case idle
    case recording
    case processing

    public static func make(isRecording: Bool, activeJobs: Int) -> StatusIcon {
        if isRecording { return .recording }
        return activeJobs > 0 ? .processing : .idle
    }
}

public enum StatusMenuAction: Equatable, Sendable {
    case history
    case settings
    case openProfilesFolder
    case quit
}

public enum StatusMenuItem: Equatable, Sendable {
    case status(String)
    case profile(id: String, name: String, isActive: Bool)
    case invalidProfile(String)
    case separator
    case action(StatusMenuAction)
}

/// Содержимое меню в строке меню, без привязки к AppKit.
public enum StatusMenuModel {
    public static func statusLine(isRecording: Bool, activeJobs: Int, activeProfileName: String) -> String {
        if isRecording { return "● Запись… (Esc — отмена)" }
        if activeJobs > 0 { return "Обработка…" }
        return "Профиль: \(activeProfileName)"
    }

    /// `activeProfile` — фактически используемый профиль (с учётом отката на raw), галочка ставится на нём.
    public static func items(
        isRecording: Bool, activeJobs: Int, entries: [ProfileEntry], activeProfile: Profile
    ) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = [
            .status(statusLine(isRecording: isRecording, activeJobs: activeJobs, activeProfileName: activeProfile.name)),
            .separator,
        ]
        for case .valid(let profile) in entries {
            items.append(.profile(id: profile.id, name: profile.name, isActive: profile.id == activeProfile.id))
        }
        for case .invalid(let id, let message) in entries {
            items.append(.invalidProfile("⚠︎ \(id).md: \(message)"))
        }
        items += [
            .separator,
            .action(.history),
            .action(.settings),
            .action(.openProfilesFolder),
            .separator,
            .action(.quit),
        ]
        return items
    }
}
