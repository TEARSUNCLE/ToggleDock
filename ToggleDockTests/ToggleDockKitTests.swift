import XCTest
@testable import ToggleDockKit

/// Kit 层纯逻辑单测（不涉及真实窗口操作，可在 CI 直接跑）。
final class ToggleDockKitTests: XCTestCase {

    // MARK: - 语言解析

    func testSystemLanguageChinese() {
        XCTAssertEqual(L10n.systemLanguageCode(preferredLanguages: ["zh-Hans-CN", "en"]), "zh-Hans")
        XCTAssertEqual(L10n.systemLanguageCode(preferredLanguages: ["zh-Hant"]), "zh-Hans") // 暂只内置简体，繁体回退到简体文案
    }

    func testSystemLanguageFallbackToEnglish() {
        XCTAssertEqual(L10n.systemLanguageCode(preferredLanguages: ["en-US"]), "en")
        XCTAssertEqual(L10n.systemLanguageCode(preferredLanguages: ["ko-KR"]), "en")
        XCTAssertEqual(L10n.systemLanguageCode(preferredLanguages: []), "en")
    }

    func testUnknownKeyFallsBackToKeyItself() {
        XCTAssertEqual(L10n.string("this.key.does.not.exist"), "this.key.does.not.exist")
    }

    func testFollowSystemDoesNotRecurse() {
        // 回归：语言为「跟随系统」时，私有无参 systemLanguageCode() 曾无限调用自身导致栈溢出崩溃
        Preferences.language = .system
        L10n.reload()
        let code = L10n.currentLanguageCode()
        XCTAssertTrue(L10n.supportedLanguages.contains(code))
    }

    func testKnownKeyResolves() {
        // 两份语言文件都应包含该键；解析链 zh-Hans → en 至少命中一个
        XCTAssertNotEqual(L10n.string("menu.quit"), "menu.quit")
    }

    // MARK: - 聚焦判定

    func testSameAppNeverCollapses() {
        XCTAssertFalse(SingleAppFocusLogic.shouldCollapsePrevious(
            previousPID: 100, currentPID: 100,
            previousOnScreen: nil, currentOnScreen: nil, screenCount: 1
        ))
    }

    func testSingleScreenAlwaysCollapses() {
        XCTAssertTrue(SingleAppFocusLogic.shouldCollapsePrevious(
            previousPID: 100, currentPID: 200,
            previousOnScreen: nil, currentOnScreen: nil, screenCount: 1
        ))
    }

    func testMultiScreenSkipsWhenPositionUnknown() {
        XCTAssertFalse(SingleAppFocusLogic.shouldCollapsePrevious(
            previousPID: 100, currentPID: 200,
            previousOnScreen: nil, currentOnScreen: nil, screenCount: 2
        ))
    }

    // MARK: - 偏好枚举解码

    func testCollapseModeDefaultsToMinimize() {
        XCTAssertEqual(Preferences.CollapseMode(rawValue: "minimize"), .minimize)
        XCTAssertNil(Preferences.CollapseMode(rawValue: "garbage"))
    }

    // MARK: - 版本解析

    func testVersionTripleParsesCommonForms() {
        XCTAssertEqual(Version.triple(from: "1.0.0")?.0, 1)
        XCTAssertEqual(Version.triple(from: "1.0.0")?.1, 0)
        XCTAssertEqual(Version.triple(from: "v2.1.0")?.0, 2)
        XCTAssertEqual(Version.triple(from: "v2.1.0")?.2, 0)
        XCTAssertEqual(Version.triple(from: "1.2.3.4")?.2, 3) // 多余段忽略
        XCTAssertEqual(Version.triple(from: " 1.10 ")?.1, 10) // 容忍空白
    }

    func testVersionTripleMissingSegmentsPadZero() {
        XCTAssertEqual(Version.triple(from: "1.0")?.2, 0)
        XCTAssertEqual(Version.triple(from: "2")?.0, 2)
    }

    func testVersionTripleRejectsGarbage() {
        XCTAssertNil(Version.triple(from: ""))
        XCTAssertNil(Version.triple(from: "abc"))
        XCTAssertNil(Version.triple(from: "1..2"))
    }

    func testVersionComparisonFollowsSemver() {
        let v100 = Version.triple(from: "v1.0.0")!
        let v101 = Version.triple(from: "1.0.1")!
        let v110 = Version.triple(from: "1.1.0")!
        let v2 = Version.triple(from: "v2")!
        XCTAssertTrue(v101 > v100)
        XCTAssertTrue(v110 > v101)
        XCTAssertTrue(v2 > v110)
        XCTAssertFalse(v100 > v101)
    }
}
