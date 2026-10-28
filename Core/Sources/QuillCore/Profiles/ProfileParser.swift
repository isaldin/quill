import Foundation
import Yams

public enum ProfileParseError: Error, Equatable, LocalizedError {
    case missingFrontmatter
    case invalidYAML(String)
    case missingName

    public var errorDescription: String? {
        switch self {
        case .missingFrontmatter: "Файл должен начинаться с блока --- … ---"
        case .invalidYAML(let message): "Ошибка YAML: \(message)"
        case .missingName: "Не задано поле name"
        }
    }
}

public enum ProfileParser {
    private struct Frontmatter: Decodable {
        let name: String?
        let transcriptionModel: String?
        let llmModel: String?
        let postprocess: Bool?
        let language: String?
        let vocabulary: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case transcriptionModel = "transcription_model"
            case llmModel = "llm_model"
            case postprocess, language, vocabulary
        }
    }

    public static func parse(id: String, contents: String) throws -> Profile {
        var text = contents.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let lines = text.components(separatedBy: "\n")
        let isFence: (String) -> Bool = { $0.trimmingCharacters(in: .whitespaces) == "---" }
        guard let first = lines.first, isFence(first),
              let closeIndex = lines.indices.dropFirst().first(where: { isFence(lines[$0]) })
        else { throw ProfileParseError.missingFrontmatter }

        let yaml = lines[1..<closeIndex].joined(separator: "\n")
        let body = lines[(closeIndex + 1)...].joined(separator: "\n")

        guard !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileParseError.missingName
        }

        let frontmatter: Frontmatter
        do {
            frontmatter = try YAMLDecoder().decode(Frontmatter.self, from: yaml)
        } catch {
            throw ProfileParseError.invalidYAML(String(describing: error))
        }

        guard let name = nonBlank(frontmatter.name) else { throw ProfileParseError.missingName }

        return Profile(
            id: id,
            name: name,
            transcriptionModel: nonBlank(frontmatter.transcriptionModel),
            llmModel: nonBlank(frontmatter.llmModel),
            postprocess: frontmatter.postprocess ?? true,
            language: nonBlank(frontmatter.language),
            vocabulary: (frontmatter.vocabulary ?? []).compactMap(nonBlank),
            instructions: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
