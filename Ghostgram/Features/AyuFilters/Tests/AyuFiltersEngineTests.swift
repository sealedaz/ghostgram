import Foundation
import XCTest

final class AyuFiltersEngineTests: XCTestCase {
    func testJsonV2DecodingAndEncoding() throws {
        let json = """
        {
            "version": 2,
            "isEnabled": true,
            "autoClickButtonsEnabled": true,
            "filters": [
                {
                    "id": 101,
                    "dialogId": 0,
                    "text": "crypto",
                    "reversed": false,
                    "caseInsensitive": true,
                    "enabled": true
                },
                {
                    "id": "102",
                    "dialogId": -100123456789,
                    "text": "<type>contains</type>spam",
                    "reversed": true,
                    "caseInsensitive": false,
                    "enabled": true
                }
            ],
            "exclusions": [
                -100987654321
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let config = try decoder.decode(AyuFiltersConfig.self, from: data)

        XCTAssertEqual(config.version, 2)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.autoClickButtonsEnabled)
        XCTAssertEqual(config.filters.count, 2)
        XCTAssertEqual(config.exclusions, [-100987654321])

        XCTAssertEqual(config.filters[0].id, 101)
        XCTAssertNil(config.filters[0].dialogId) // 0 mapped to nil
        XCTAssertEqual(config.filters[0].text, "crypto")

        XCTAssertEqual(config.filters[1].id, 102) // string "102" decoded as 102
        XCTAssertEqual(config.filters[1].dialogId, -100123456789)
        XCTAssertTrue(config.filters[1].reversed)

        // Test re-encoding
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(config)
        let reDecoded = try decoder.decode(AyuFiltersConfig.self, from: encodedData)
        XCTAssertEqual(reDecoded.version, 2)
        XCTAssertEqual(reDecoded.filters.count, 2)
    }

    func testRegexMatchingAndInvalidRegexProtection() {
        // Valid regex
        let validRule = AyuFilterRule(id: 1, text: "h[0-9]+llo", caseInsensitive: true, enabled: true)
        let validCompiled = AyuCompiledFilter(rule: validRule)
        XCTAssertNotNil(validCompiled.regex)
        XCTAssertTrue(validCompiled.matches(text: "h123llo world", buttonTitles: []))
        XCTAssertFalse(validCompiled.matches(text: "hallo world", buttonTitles: []))

        // Invalid regex must not crash and fail safely (even if reversed)
        let invalidRule = AyuFilterRule(id: 2, text: "[unclosed-bracket(", caseInsensitive: true, enabled: true)
        let invalidCompiled = AyuCompiledFilter(rule: invalidRule)
        XCTAssertNil(invalidCompiled.regex)
        XCTAssertFalse(invalidCompiled.matches(text: "any text", buttonTitles: []))

        let invalidReversedRule = AyuFilterRule(id: 3, text: "[unclosed-bracket(", reversed: true, caseInsensitive: true, enabled: true)
        let invalidReversedCompiled = AyuCompiledFilter(rule: invalidReversedRule)
        XCTAssertNil(invalidReversedCompiled.regex)
        XCTAssertFalse(invalidReversedCompiled.matches(text: "any text", buttonTitles: []))
    }

    func testTypeTagsParsing() {
        // Contains
        let containsRule = AyuFilterRule(id: 1, text: "<type>contains</type>secret", caseInsensitive: true, enabled: true)
        let containsCompiled = AyuCompiledFilter(rule: containsRule)
        XCTAssertEqual(containsCompiled.matchMode, .contains)
        XCTAssertEqual(containsCompiled.cleanPattern, "secret")
        XCTAssertTrue(containsCompiled.matches(text: "this is Top Secret info", buttonTitles: []))
        XCTAssertFalse(containsCompiled.matches(text: "public info", buttonTitles: []))

        // Exact
        let exactRule = AyuFilterRule(id: 2, text: "<type>exact</type>STOP", caseInsensitive: true, enabled: true)
        let exactCompiled = AyuCompiledFilter(rule: exactRule)
        XCTAssertEqual(exactCompiled.matchMode, .exact)
        XCTAssertTrue(exactCompiled.matches(text: "stop", buttonTitles: []))
        XCTAssertFalse(exactCompiled.matches(text: "stop please", buttonTitles: []))

        // StartsWith
        let startRule = AyuFilterRule(id: 3, text: "<type>startswith</type>#ad", caseInsensitive: true, enabled: true)
        let startCompiled = AyuCompiledFilter(rule: startRule)
        XCTAssertEqual(startCompiled.matchMode, .startsWith)
        XCTAssertTrue(startCompiled.matches(text: "#AD Check this out", buttonTitles: []))
        XCTAssertFalse(startCompiled.matches(text: "Great #ad here", buttonTitles: []))

        // EndsWith
        let endRule = AyuFilterRule(id: 4, text: "<type>endswith</type>.xyz", caseInsensitive: true, enabled: true)
        let endCompiled = AyuCompiledFilter(rule: endRule)
        XCTAssertEqual(endCompiled.matchMode, .endsWith)
        XCTAssertTrue(endCompiled.matches(text: "Visit scam.xyz", buttonTitles: []))
        XCTAssertFalse(endCompiled.matches(text: "Visit scam.xyz/info", buttonTitles: []))
    }

    func testButtonTagParsingAndMatching() {
        // standalone <button>
        let btnRule = AyuFilterRule(id: 1, text: "<button>", enabled: true)
        let btnCompiled = AyuCompiledFilter(rule: btnRule)
        XCTAssertEqual(btnCompiled.buttonPattern, "")
        XCTAssertTrue(btnCompiled.matches(text: "any message", buttonTitles: ["Claim"]))
        XCTAssertFalse(btnCompiled.matches(text: "any message", buttonTitles: []))

        // <button>Claim</button>
        let specificBtnRule = AyuFilterRule(id: 2, text: "<button>Claim</button>", caseInsensitive: true, enabled: true)
        let specificCompiled = AyuCompiledFilter(rule: specificBtnRule)
        XCTAssertEqual(specificCompiled.buttonPattern, "Claim")
        XCTAssertTrue(specificCompiled.matches(text: "", buttonTitles: ["Claim Reward"]))
        XCTAssertFalse(specificCompiled.matches(text: "", buttonTitles: ["Other"]))
    }

    func testReversedLogic() {
        let rule = AyuFilterRule(id: 1, text: "<type>contains</type>approved", reversed: true, enabled: true)
        let compiled = AyuCompiledFilter(rule: rule)
        // Reversed: matches if "approved" is NOT present
        XCTAssertTrue(compiled.matches(text: "spam message", buttonTitles: []))
        XCTAssertFalse(compiled.matches(text: "this is approved message", buttonTitles: []))
    }

    func testEngineExclusionsAndPerChatFiltering() {
        let engine = AyuFiltersEngine()
        let config = AyuFiltersConfig(
            version: 2,
            isEnabled: true,
            autoClickButtonsEnabled: false,
            filters: [
                AyuFilterRule(id: 1, dialogId: 0, text: "<type>contains</type>global_spam", enabled: true),
                AyuFilterRule(id: 2, dialogId: -100555, text: "<type>contains</type>chat_only", enabled: true)
            ],
            exclusions: [-100999]
        )
        engine.compile(config: config)

        // 1. Shared filter matches in regular chat
        XCTAssertNotNil(engine.shouldFilter(dialogId: -100111, text: "some global_spam text", buttonTitles: []))

        // 2. Chat in exclusions is never filtered even with matching text
        XCTAssertNil(engine.shouldFilter(dialogId: -100999, text: "some global_spam text", buttonTitles: []))

        // 3. Per-chat filter only matches in that chat (tested with direct dialogId and altDialogId)
        XCTAssertNotNil(engine.shouldFilter(dialogId: -100555, text: "some chat_only text", buttonTitles: []))
        XCTAssertNotNil(engine.shouldFilter(dialogId: 999999, altDialogId: -100555, text: "some chat_only text", buttonTitles: []))
        XCTAssertNil(engine.shouldFilter(dialogId: -100111, text: "some chat_only text", buttonTitles: []))
    }

    func testFlexibleExclusionsDecoding() throws {
        let json = """
        {
            "version": 2,
            "filters": [],
            "exclusions": [
                {"id": -100111222},
                {"dialogId": -100333444}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AyuFiltersConfig.self, from: data)
        XCTAssertEqual(config.exclusions.sorted(), [-100333444, -100111222].sorted())
    }
}
