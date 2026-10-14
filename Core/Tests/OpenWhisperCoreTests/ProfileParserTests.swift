import XCTest
@testable import OpenWhisperCore

final class ProfileParserTests: XCTestCase {
    func testParsesFullProfile() throws {
        let text = """
        ---
        name: Frontend / Claude Code
        transcription_model: openai/gpt-4o-transcribe
        llm_model: openai/gpt-4.1-mini
        postprocess: true
        language: ru
        vocabulary:
          - useState
          - frontend-config
        ---
        Пиши термины латиницей.
        Убери паразиты.
        """
        let profile = try ProfileParser.parse(id: "frontend", contents: text)
        XCTAssertEqual(profile, Profile(
            id: "frontend",
            name: "Frontend / Claude Code",
            transcriptionModel: "openai/gpt-4o-transcribe",
            llmModel: "openai/gpt-4.1-mini",
            postprocess: true,
            language: "ru",
            vocabulary: ["useState", "frontend-config"],
            instructions: "Пиши термины латиницей.\nУбери паразиты."
        ))
    }

    func testDefaultsWhenOnlyNameGiven() throws {
        let profile = try ProfileParser.parse(id: "x", contents: "---\nname: X\n---\n")
        XCTAssertEqual(profile, Profile(id: "x", name: "X"))
        XCTAssertTrue(profile.postprocess)
        XCTAssertNil(profile.transcriptionModel)
        XCTAssertNil(profile.llmModel)
        XCTAssertNil(profile.language)
        XCTAssertEqual(profile.vocabulary, [])
        XCTAssertEqual(profile.instructions, "")
    }

    func testRejectsMissingFrontmatter() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "просто текст")) {
            XCTAssertEqual($0 as? ProfileParseError, .missingFrontmatter)
        }
    }

    func testRejectsUnclosedFrontmatter() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "---\nname: X\n")) {
            XCTAssertEqual($0 as? ProfileParseError, .missingFrontmatter)
        }
    }

    func testRejectsMissingName() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "---\npostprocess: false\n---\n")) {
            XCTAssertEqual($0 as? ProfileParseError, .missingName)
        }
    }

    func testRejectsEmptyFrontmatter() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "---\n---\nтело")) {
            XCTAssertEqual($0 as? ProfileParseError, .missingName)
        }
    }

    func testRejectsInvalidYAML() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "---\nname: [unclosed\n---\n")) {
            guard case .invalidYAML = $0 as? ProfileParseError else { return XCTFail("\($0)") }
        }
    }

    func testRejectsWrongFieldType() {
        XCTAssertThrowsError(try ProfileParser.parse(id: "x", contents: "---\nname: X\npostprocess: maybe\n---\n")) {
            guard case .invalidYAML = $0 as? ProfileParseError else { return XCTFail("\($0)") }
        }
    }

    func testAcceptsCRLFBOMAndTrailingSpaces() throws {
        let text = "\u{FEFF}---\r\nname: X\r\nvocabulary:\r\n  - A\r\n---  \r\nТело\r\n"
        let profile = try ProfileParser.parse(id: "x", contents: text)
        XCTAssertEqual(profile.name, "X")
        XCTAssertEqual(profile.vocabulary, ["A"])
        XCTAssertEqual(profile.instructions, "Тело")
    }

    func testTrimsAndDropsBlankValues() throws {
        let text = """
        ---
        name: "  X  "
        language: ""
        llm_model: " "
        vocabulary:
          - "  a "
          - ""
        ---
        """
        let profile = try ProfileParser.parse(id: "x", contents: text)
        XCTAssertEqual(profile.name, "X")
        XCTAssertNil(profile.language)
        XCTAssertNil(profile.llmModel)
        XCTAssertEqual(profile.vocabulary, ["a"])
    }
}
