import XCTest
@testable import OpenWhisperCore

final class SharedSettingsTests: XCTestCase {
    func testDecodesFullFile() throws {
        let json = """
        {"version":1,"default_transcription_model":"a/stt","default_llm_model":"b/llm",
         "audio_limit_gb":2.5,"sounds_enabled":false,"show_indicator":false}
        """
        XCTAssertEqual(try SharedSettings.decode(Data(json.utf8)), SharedSettings(
            defaultTranscriptionModel: "a/stt", defaultLLMModel: "b/llm",
            audioLimitGB: 2.5, soundsEnabled: false, showIndicator: false
        ))
    }

    func testMissingFieldsUseDefaults() throws {
        XCTAssertEqual(try SharedSettings.decode(Data("{}".utf8)), .defaults)
        XCTAssertEqual(SharedSettings.defaults.defaultTranscriptionModel, "openai/gpt-4o-transcribe")
        XCTAssertEqual(SharedSettings.defaults.defaultLLMModel, "openai/gpt-4.1-mini")
        XCTAssertEqual(SharedSettings.defaults.audioLimitGB, 1.0)
        XCTAssertTrue(SharedSettings.defaults.soundsEnabled)
        XCTAssertTrue(SharedSettings.defaults.showIndicator)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = #"{"sounds_enabled":false,"future_option":42,"nested":{"x":1}}"#
        XCTAssertFalse(try SharedSettings.decode(Data(json.utf8)).soundsEnabled)
    }

    func testBlankModelsAndTinyLimitAreNormalized() throws {
        let json = #"{"default_transcription_model":"  ","default_llm_model":"","audio_limit_gb":0.01}"#
        let settings = try SharedSettings.decode(Data(json.utf8))
        XCTAssertEqual(settings.defaultTranscriptionModel, SharedSettings.defaultTranscriptionModelID)
        XCTAssertEqual(settings.defaultLLMModel, SharedSettings.defaultLLMModelID)
        XCTAssertEqual(settings.audioLimitGB, 0.1)
    }

    func testModelsAreTrimmed() throws {
        let json = #"{"default_llm_model":"  x/y \n"}"#
        XCTAssertEqual(try SharedSettings.decode(Data(json.utf8)).defaultLLMModel, "x/y")
    }

    func testWrongTypeIsInvalid() {
        let json = #"{"audio_limit_gb":"много"}"#
        XCTAssertThrowsError(try SharedSettings.decode(Data(json.utf8))) {
            guard case .invalidJSON(let message) = $0 as? SharedSettingsError else { return XCTFail("\($0)") }
            XCTAssertTrue(message.contains("audio_limit_gb"), message)
        }
    }

    func testBrokenJSONIsInvalid() {
        for text in ["", "{", "[1,2]", #"{"sounds_enabled":tru}"#] {
            XCTAssertThrowsError(try SharedSettings.decode(Data(text.utf8)), text) {
                guard case .invalidJSON = $0 as? SharedSettingsError else { return XCTFail("\($0)") }
            }
        }
    }

    func testDecodesUTF8BOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"sounds_enabled":false}"#.utf8)
        XCTAssertFalse(try SharedSettings.decode(data).soundsEnabled)
    }

    func testEncodeRoundTripWithSnakeCaseAndVersion() throws {
        let settings = SharedSettings(defaultLLMModel: "x/y", audioLimitGB: 3, soundsEnabled: false)
        let data = try settings.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["default_llm_model"] as? String, "x/y")
        XCTAssertEqual(object["sounds_enabled"] as? Bool, false)
        XCTAssertEqual(try SharedSettings.decode(data), settings)
    }

    func testLegacyDefaultsMigration() {
        let defaults = UserDefaults(suiteName: "ow-legacy-\(UUID().uuidString)")!
        XCTAssertEqual(SharedSettings(legacyDefaults: defaults), .defaults)
        defaults.set("old/stt", forKey: "defaultTranscriptionModel")
        defaults.set("old/llm", forKey: "defaultLLMModel")
        defaults.set(4.0, forKey: "audioLimitGB")
        defaults.set(false, forKey: "soundsEnabled")
        defaults.set(false, forKey: "showIndicator")
        XCTAssertEqual(SharedSettings(legacyDefaults: defaults), SharedSettings(
            defaultTranscriptionModel: "old/stt", defaultLLMModel: "old/llm",
            audioLimitGB: 4, soundsEnabled: false, showIndicator: false
        ))
    }
}
