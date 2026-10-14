import Foundation

public struct BuiltinProfile: Sendable {
    public let id: String
    public let contents: String
}

public enum BuiltinProfiles {
    public static let all: [BuiltinProfile] = [
        BuiltinProfile(id: "raw", contents: """
        ---
        name: Без обработки
        postprocess: false
        ---

        """),
        BuiltinProfile(id: "clean", contents: """
        ---
        name: Чистка
        postprocess: true
        ---
        Расставь пунктуацию и заглавные буквы.
        Убери слова-паразиты (ну, вот, типа, как бы, э-э) и случайные повторы.
        Не меняй смысл, порядок мыслей и стиль. Ничего не добавляй от себя.

        """),
    ]
}
