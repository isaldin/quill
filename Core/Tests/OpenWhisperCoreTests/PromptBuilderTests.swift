import XCTest
@testable import OpenWhisperCore

final class PromptBuilderTests: XCTestCase {
    func testOnlyBaseInstructionWhenProfileIsEmpty() {
        let messages = PromptBuilder.messages(rawText: "привет", profile: Profile(id: "p", name: "P"))
        XCTAssertEqual(messages, [
            ChatMessage(role: "system", content: PromptBuilder.baseInstruction),
            ChatMessage(role: "user", content: "<transcript>\nпривет\n</transcript>"),
        ])
    }

    func testAppendsInstructionsAndVocabulary() {
        let profile = Profile(id: "p", name: "P", vocabulary: ["useState", "MR"], instructions: "Пиши кратко.")
        let system = PromptBuilder.messages(rawText: "x", profile: profile)[0].content
        XCTAssertEqual(system, PromptBuilder.baseInstruction
            + "\n\nПиши кратко."
            + "\n\nПиши эти термины именно так: useState, MR")
    }

    func testWhitespaceOnlyInstructionsAreIgnored() {
        let profile = Profile(id: "p", name: "P", instructions: "  \n ")
        let system = PromptBuilder.messages(rawText: "x", profile: profile)[0].content
        XCTAssertEqual(system, PromptBuilder.baseInstruction)
    }

    func testBaseInstructionForbidsAnsweringTheTranscript() {
        XCTAssertTrue(PromptBuilder.baseInstruction.contains("<transcript>"))
        XCTAssertTrue(PromptBuilder.baseInstruction.contains("Не отвечай"))
    }
}
