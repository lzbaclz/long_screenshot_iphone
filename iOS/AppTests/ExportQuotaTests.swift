import XCTest
@testable import ScrollCapture

@MainActor
final class ExportQuotaTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "ExportQuotaTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testFreeReleaseStartsWithFiftyFiniteExports() {
        let store = ExportQuotaStore(defaults: defaults)
        XCTAssertEqual(store.quotaPolicy, .weekly(limit: 50))
        XCTAssertEqual(store.exportLimit, 50)
        XCTAssertEqual(store.remainingExports, 50)
        XCTAssertTrue(store.canExport(sessionID: UUID()))
    }

    func testReleaseBundleHasNoInAppPurchaseProduct() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "ProProductIdentifier"))
    }

    func testFortyNinthFiftiethAndFiftyFirstNewExports() {
        let store = ExportQuotaStore(defaults: defaults)
        let sessions = (0..<51).map { _ in UUID() }
        for session in sessions.prefix(49) {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 1)
        XCTAssertTrue(store.canExport(sessionID: sessions[49]))
        store.recordSuccessfulExport(sessionID: sessions[49])
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: sessions[50]))
        // Editing, saving again, or sharing any already-counted work stays available.
        for session in sessions.prefix(50) {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1")?.count, 50)
        let relaunched = ExportQuotaStore(defaults: defaults)
        XCTAssertEqual(relaunched.remainingExports, 0)
        XCTAssertFalse(relaunched.canExport(sessionID: sessions[50]))
        XCTAssertTrue(relaunched.canExport(sessionID: sessions[0]))
    }

    func testFailedOrCancelledShareDoesNotConsumeAndSuccessfulRepeatCountsOnce() {
        let store = ExportQuotaStore(defaults: defaults)
        let session = UUID()
        // Both cancellation and a failed activity report completed == false.
        store.recordShareCompletion(sessionID: session, completed: false)
        store.recordShareCompletion(sessionID: session, completed: false)
        XCTAssertEqual(store.remainingExports, 50)
        XCTAssertNil(defaults.dictionary(forKey: "successfulCaptureExports.v1"))
        store.recordShareCompletion(sessionID: session, completed: true)
        XCTAssertEqual(store.remainingExports, 49)
        store.recordSuccessfulExport(sessionID: session)
        store.recordShareCompletion(sessionID: session, completed: true)
        XCTAssertEqual(store.remainingExports, 49)
        XCTAssertEqual(ExportQuotaStore(defaults: defaults).remainingExports, 49)
    }

    func testPreviousThreeExportLedgerSurvivesUpgradeAndOnlyCurrentWeekCounts() {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // 2026-09-14, Monday.
        let oldSession = UUID()
        let currentSessions = (0..<3).map { _ in UUID() }
        var ledger = Dictionary(uniqueKeysWithValues: currentSessions.map { ($0.uuidString, now) })
        ledger[oldSession.uuidString] = now.addingTimeInterval(-604_800)
        defaults.set(ledger, forKey: "successfulCaptureExports.v1")
        let store = ExportQuotaStore(defaults: defaults, currentDate: { now })
        XCTAssertEqual(store.remainingExports, 47)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date], ledger)
        for session in currentSessions + [oldSession] {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 47)
        let newSession = UUID()
        store.recordSuccessfulExport(sessionID: newSession)
        let upgraded = ExportQuotaStore(defaults: defaults, quotaPolicy: .weekly(limit: 50), currentDate: { now })
        XCTAssertEqual(upgraded.remainingExports, 46)
        let persisted = defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date]
        for (id, date) in ledger { XCTAssertEqual(persisted?[id], date) }
        XCTAssertTrue(upgraded.canExport(sessionID: newSession))
    }

    func testISOWeekBoundaryReplenishesAllowanceWithoutCountingRepeatedWorksAgain() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 59))!
        let store = ExportQuotaStore(defaults: defaults, calendar: calendar, currentDate: { now })
        let oldSession = UUID()
        store.recordSuccessfulExport(sessionID: oldSession)
        for _ in 0..<49 { store.recordSuccessfulExport(sessionID: UUID()) }
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: UUID()))
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        XCTAssertEqual(store.remainingExports, 50)
        store.recordSuccessfulExport(sessionID: oldSession)
        XCTAssertEqual(store.remainingExports, 50, "Repeating last week's work must not consume this week's allowance")
        store.recordSuccessfulExport(sessionID: UUID())
        XCTAssertEqual(store.remainingExports, 49)
        XCTAssertEqual(ExportQuotaStore(defaults: defaults, calendar: calendar, currentDate: { now }).remainingExports, 49)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1")?.count, 51)
    }

    func testExistingLedgerAboveFiftyIsPreservedWithoutNegativeAllowance() {
        let ledger = Dictionary(uniqueKeysWithValues: (0..<51).map { _ in (UUID().uuidString, Date()) })
        defaults.set(ledger, forKey: "successfulCaptureExports.v1")
        let store = ExportQuotaStore(defaults: defaults)
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: UUID()))
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date], ledger)
        XCTAssertTrue(store.canExport(sessionID: UUID(uuidString: ledger.keys.first!)!))
    }

    func testWeeklyAllowanceUsesLocalMondayInsteadOfUTCMidnight() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 59))!
        let store = ExportQuotaStore(defaults: defaults, calendar: calendar, currentDate: { now })
        store.recordSuccessfulExport(sessionID: UUID())
        XCTAssertEqual(store.remainingExports, 49)
        now = now.addingTimeInterval(60)
        XCTAssertEqual(store.remainingExports, 50, "Local Monday starts while it is still Sunday in UTC")
    }

}

final class CaptureNoticeTests: XCTestCase {
    func testOriginWarningSurvivesInterruptedRecoveryReason() {
        var session = manifestWithImage()
        session.status = .interrupted
        session.stopReason = "捕捉意外中断，已保留画面。"
        session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
        XCTAssertTrue(session.noticeText?.contains("捕捉意外中断") == true)
        XCTAssertTrue(session.noticeText?.contains("请检查图片开头是否完整") == true)
    }

    func testCompletedOriginWarningIsVisibleAndNotRepeated() {
        var session = manifestWithImage()
        session.status = .completed
        session.startWarning = "请检查图片开头是否完整。"
        XCTAssertEqual(session.stateLabel, "请检查开头")
        XCTAssertEqual(session.noticeText, session.startWarning)
        session.stopReason = "已停止。请检查图片开头是否完整。"
        XCTAssertEqual(session.noticeText, session.stopReason)
    }

    func testEmptyTerminalCaptureIsFailureAndNeverRecoverable() {
        for status in [CaptureSessionStatus.partial, .interrupted, .completed] {
            var session = CaptureSessionManifest()
            session.status = status
            session.stopReason = "捕捉意外中断，已保留最后一次成功写入的画面。"
            XCTAssertTrue(session.isFailedCapture)
            XCTAssertFalse(session.isSavedPartialCapture)
            XCTAssertEqual(session.stateLabel, "未捕捉到可用画面")
            XCTAssertEqual(session.noticeText, "捕捉意外中断，未保存可用画面。请重新开始捕捉。")
            XCTAssertEqual(session.stopReason, "捕捉意外中断，已保留最后一次成功写入的画面。",
                           "Presenting a legacy failure must not rewrite its original record")
        }
    }

    func testEmptyCaptureKeepsActualActionableFailureReason() {
        var session = CaptureSessionManifest()
        session.status = .partial
        session.stopReason = "无法安全识别固定栏或页面留白。请手动设置顶部和底部忽略区域后重试。"
        XCTAssertEqual(session.noticeText, session.stopReason)
        XCTAssertEqual(session.stateLabel, "未捕捉到可用画面")
    }

    func testEmptyActiveCaptureIsStillPreparing() {
        let session = CaptureSessionManifest()
        XCTAssertFalse(session.isFailedCapture)
        XCTAssertFalse(session.isSavedPartialCapture)
        XCTAssertEqual(session.stateLabel, "等待目标内容")
    }

    func testSingleFrameFallbackIsSavedButNeverLabelledCompletedLongImage() {
        var session = manifestWithImage()
        session.status = .partial
        session.outputKind = .singleFrame
        XCTAssertTrue(session.hasImage)
        XCTAssertTrue(session.isSavedPartialCapture)
        XCTAssertFalse(session.isFailedCapture)
        XCTAssertEqual(session.stateLabel, "仅保留单屏")
    }

    func testLegacyDiagnosticsDecodeWithoutPretendingNewCountersWereRecorded() throws {
        let legacy = Data(#"{"observedFrames":12,"acceptedFrames":0,"rejectedFrames":11,"regionAttempts":4,"recoveredGaps":0,"provisionalReplacements":1,"skippedSamples":3,"maximumProcessingMilliseconds":24,"lastStage":"alignment","terminationCause":"systemStop"}"#.utf8)
        let diagnostics = try JSONDecoder().decode(CaptureDiagnostics.self, from: legacy)
        XCTAssertNil(diagnostics.receivedVideoSamples)
        XCTAssertNil(diagnostics.startupRecoveryMethod)
        XCTAssertNil(diagnostics.startupWaitingState)
        XCTAssertNil(diagnostics.startupWaitingSeconds)
        XCTAssertNil(diagnostics.stableCandidateFrameCount)
        XCTAssertEqual(diagnostics.startupWaitingLabel, "未记录")
        XCTAssertEqual(diagnostics.observedFrames, 12)
        XCTAssertEqual(diagnostics.provisionalReplacements, 1)
        XCTAssertEqual(diagnostics.terminationLabel, "系统入口结束（也可能由你手动停止）")
        XCTAssertEqual(try JSONDecoder().decode(CaptureDiagnostics.self, from: JSONEncoder().encode(diagnostics)), diagnostics)
    }

    func testStartupWaitingUsesConfirmedImageAndActiveWaitingTime() {
        var session = CaptureSessionManifest()
        session.diagnostics = .init()
        session.diagnostics?.startupWaitingSeconds = 0.5
        session.provisionalFrame = .init(fileName: "candidate.png", pixelWidth: 100, pixelHeight: 200)
        XCTAssertTrue(session.isWaitingForTarget)
        XCTAssertEqual(session.activeCaptureTitle, "等待目标内容")
        XCTAssertFalse(session.activeCaptureMessage.contains("还没有确认"), "Brief startup is normal, not a failure")
        session.diagnostics?.startupWaitingSeconds = 8
        XCTAssertTrue(session.activeCaptureMessage.contains("当前尚未形成长图"))
        session.diagnostics?.lifecycleState = "paused"
        XCTAssertEqual(session.activeCaptureTitle, "等待系统恢复捕捉")
        XCTAssertFalse(session.activeCaptureMessage.contains("缓慢"))
        session.diagnostics?.lifecycleState = "awaitingOverlap"
        XCTAssertEqual(session.activeCaptureTitle, "恢复后重新确认画面衔接")
        session = manifestWithImage()
        session.diagnostics = .init(); session.diagnostics?.startupWaitingSeconds = 12
        XCTAssertFalse(session.isWaitingForTarget)
        XCTAssertEqual(session.activeCaptureTitle, "正在为你保留内容")
        XCTAssertFalse(session.activeCaptureMessage.contains("尚未形成长图"))
    }

    func testSystemEntryStopAndLegacyReasonsLocalizeWithoutImplyingSystemFailure() throws {
        for language in ["en", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let ended = language == "en" ? "Broadcast ended." : "广播已结束。"
            for key in ["广播已结束。", "捕捉已由系统结束。"] {
                XCTAssertEqual(CaptureMessageLocalization.text(key, bundle: bundle), ended)
            }
            let composite = CaptureMessageLocalization.text("未写入可用画面。 捕捉已由系统结束。", bundle: bundle)
            XCTAssertTrue(composite.hasSuffix(ended))
            for cause in ["systemStop", "systemEnded", "systemEntryStop"] {
                var diagnostics = CaptureDiagnostics(); diagnostics.terminationCause = cause
                let label = bundle.localizedString(forKey: diagnostics.terminationLabel, value: nil, table: nil)
                XCTAssertTrue(label.contains(language == "en" ? "manual stop" : "手动停止"))
            }
        }
    }

    private func manifestWithImage() -> CaptureSessionManifest {
        var manifest = CaptureSessionManifest()
        manifest.pixelWidth = 100
        manifest.strips = [CaptureStrip(fileName: "fixture.png", pixelWidth: 100, pixelHeight: 200)]
        return manifest
    }
}
