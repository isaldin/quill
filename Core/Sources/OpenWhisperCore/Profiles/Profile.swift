import Foundation

public struct Profile: Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var transcriptionModel: String?
    public var llmModel: String?
    public var postprocess: Bool
    public var language: String?
    public var vocabulary: [String]
    public var instructions: String

    public init(
        id: String,
        name: String,
        transcriptionModel: String? = nil,
        llmModel: String? = nil,
        postprocess: Bool = true,
        language: String? = nil,
        vocabulary: [String] = [],
        instructions: String = ""
    ) {
        self.id = id
        self.name = name
        self.transcriptionModel = transcriptionModel
        self.llmModel = llmModel
        self.postprocess = postprocess
        self.language = language
        self.vocabulary = vocabulary
        self.instructions = instructions
    }

    /// Используется, когда нет ни одного валидного профиля.
    public static let fallbackRaw = Profile(id: "raw", name: "Без обработки", postprocess: false)
}
