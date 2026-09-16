import XCTest
import CoreGraphics
import CoreImage
import UIKit
import ScrollCaptureCore
@testable import ScrollCapture

final class CaptureFramePipelineTests: XCTestCase {
    func testAutomaticFixedBarsKeepEveryBodyRowWithoutRepeatingChrome() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let document = scene(seed: 311)
        var output: [UInt8] = []
        for offset in [0, 23, 47, 31, 68] {
            let gray = try chromeFrame(document, offset: offset, top: 17, bottom: 23)
            let result = try pipeline.ingest(gray) { self.image(gray) }
            XCTAssertNil(result.regionWarning)
            output += result.strips.flatMap { pixels($0.image) }
        }
        XCTAssertEqual(pipeline.effectiveConfiguration.topInset, 17)
        XCTAssertEqual(pipeline.effectiveConfiguration.bottomInset, 23)
        XCTAssertEqual(output, Array(document.prefix((120 + 68) * 48)))
    }

    func testAutomaticWhitePaddingRemainsVisibleInPreservedOuterEdges() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        var document = scene(seed: 801)
        document.replaceSubrange(0..<(60 * 48), with: repeatElement(UInt8(248), count: 60 * 48))
        _ = try feed(pipeline, source: document, offset: 0)
        let result = try feed(pipeline, source: document, offset: 25)
        XCTAssertEqual(result.status, .advanced)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CaptureSessionRepository(rootURL: directory)
        var session = try repository.createSession(configuration: .init())
        try repository.commit(result, maximumBodyHeight: 1_000, to: &session)
        session.status = .completed; try repository.saveManifest(session)
        let exported = try CaptureImageRenderer(repository: repository).export(sessionID: session.id)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: exported.path)?.cgImage)
        XCTAssertEqual(pixels(actual), Array(document.prefix(145 * 48)))
    }

    func testManualBarsBypassAutomaticAmbiguityAndKeepBodyPixels() throws {
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 17, bottomInset: 23))
        var document = scene(seed: 901)
        document.replaceSubrange(0..<(60 * 48), with: repeatElement(UInt8(248), count: 60 * 48))
        let first = try chromeFrame(document, offset: 0, top: 17, bottom: 23)
        _ = try pipeline.ingest(first) { self.image(first) }
        let current = try chromeFrame(document, offset: 25, top: 17, bottom: 23)
        let result = try pipeline.ingest(current) { self.image(current) }
        XCTAssertNil(result.regionWarning)
        XCTAssertEqual(result.strips.flatMap { pixels($0.image) }, Array(document.prefix(145 * 48)))
    }

    func testAppSwitchBeforeFirstScrollReplacesCandidateAndPreservesTargetBeginning() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let host = scene(seed: 4), target = scene(seed: 91)
        let first = try feed(pipeline, source: host, offset: 0)
        XCTAssertTrue(first.isArming)
        XCTAssertTrue(first.strips.isEmpty)
        _ = try feed(pipeline, source: target, offset: 0)
        _ = try feed(pipeline, source: target, offset: 0)
        let switched = try feed(pipeline, source: target, offset: 0)
        XCTAssertTrue(switched.isArming)
        XCTAssertTrue(switched.replacedProvisionalStart)
        XCTAssertTrue(switched.strips.isEmpty)
        let scrolled = try feed(pipeline, source: target, offset: 37)
        XCTAssertFalse(scrolled.isArming)
        XCTAssertEqual(scrolled.strips.map { $0.image.height }, [120, 37])
        let assembled = scrolled.strips.flatMap { pixels($0.image) }
        XCTAssertEqual(assembled, Array(target.prefix(157 * 48)))
    }

    func testStationaryArmingDoesNotRenderAgainAndUntrustedGapNeverAddsContent() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let target = scene(seed: 67)
        _ = try feed(pipeline, source: target, offset: 0)
        let gray = try frame(target, offset: 0)
        let stationary = try pipeline.ingest(gray) {
            XCTFail("Stationary frame must retain the provisional candidate without rendering again")
            return self.image(gray)
        }
        XCTAssertTrue(stationary.isArming)
        XCTAssertFalse(stationary.replacedProvisionalStart)
        XCTAssertFalse(pipeline.hasStarted)
        _ = try feed(pipeline, source: target, offset: 30)
        let gap = try feed(pipeline, source: scene(seed: 999), offset: 0)
        XCTAssertEqual(gap.status, .rejected)
        XCTAssertFalse(gap.isArming)
        XCTAssertTrue(gap.strips.isEmpty)
        let recovered = try feed(pipeline, source: target, offset: 60)
        XCTAssertEqual(recovered.strips.map { $0.image.height }, [30])
        XCTAssertEqual(recovered.strips.flatMap { pixels($0.image) }, Array(target[(150 * 48)..<(180 * 48)]))
    }

    func testFirstUpwardMovementPrependsAndNeverResetsTheStart() throws {
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 4, bottomInset: 6))
        let target = scene(seed: 403)
        _ = try feed(pipeline, source: target, offset: 35)
        let movement = try feed(pipeline, source: target, offset: 0)
        XCTAssertFalse(movement.isArming)
        XCTAssertFalse(movement.replacedProvisionalStart)
        XCTAssertEqual(movement.strips.map(\.placement), [.append, .prepend])
        var assembled = pixels(movement.strips[0].image)
        assembled.insert(contentsOf: pixels(movement.strips[1].image), at: 0)
        XCTAssertEqual(assembled, Array(target[(4 * 48)..<(149 * 48)]))
        let backtrack = try feed(pipeline, source: target, offset: 24)
        XCTAssertTrue(backtrack.strips.isEmpty)
    }

    func testSingleScreenFallbackKeepsFullImageAndCannotBeTakenTwice() throws {
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 4, bottomInset: 6))
        let source = scene(seed: 114)
        _ = try feed(pipeline, source: source, offset: 0)
        XCTAssertEqual(try XCTUnwrap(pipeline.takeSingleFrameFallback()).height, 120)
        XCTAssertNil(pipeline.takeSingleFrameFallback())
        XCTAssertFalse(pipeline.hasStarted)
    }

    func testProductionConversionUsesSameTopRowAsCGImageCropping() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let original = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 20, width: 40, height: 60))
        }.cgImage!
        let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: original), context: CIContext(), width: 40, height: 80)
        XCTAssertEqual(gray.pixels[10 * 40 + 20], 0)
        XCTAssertEqual(gray.pixels[60 * 40 + 20], 255)
        let cropped = try XCTUnwrap(original.cropping(to: CGRect(x: 0, y: 0, width: 40, height: 20)))
        XCTAssertTrue(pixels(cropped).allSatisfy { $0 == 0 })
    }

    func testContinuityAllowsLoadingToRecoverAfterThreeAndFiveSeconds() {
        var policy = CaptureContinuityPolicy()
        for index in 0..<20 { XCTAssertFalse(policy.reject(at: Double(index), hasStarted: false)) }
        for elapsed in [3.5, 5.0] {
            for index in 0..<20 {
                XCTAssertFalse(policy.reject(at: Double(index) * elapsed / 19, hasStarted: true))
            }
            XCTAssertTrue(policy.isAwaitingBridge)
            policy.accept()
            XCTAssertFalse(policy.isAwaitingBridge)
            XCTAssertEqual(policy.consecutiveRejections, 0)
        }
        for index in 0..<20 { XCTAssertFalse(policy.reject(at: 20 + Double(index) * 0.4, hasStarted: true)) }
        XCTAssertTrue(policy.reject(at: 28.1, hasStarted: true))
    }

    func testFirstCommitFailureStillHasARealSingleScreenFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CaptureSessionRepository(rootURL: directory)
        var session = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 4, bottomInset: 6),
                                             repository: repository, sessionID: session.id)
        let source = scene(seed: 1_024)
        _ = try feed(pipeline, source: source, offset: 0)
        let first = try feed(pipeline, source: source, offset: 30)
        XCTAssertTrue(pipeline.hasStarted)
        let wrongWidth = try GrayFrame(width: 49, height: 2, pixels: [UInt8](repeating: 0, count: 98))
        let faulty = CaptureFrameResult(status: .advanced,
            strips: first.strips + [.init(image: image(wrongWidth), sourceTopPixel: 0)], isArming: false)
        XCTAssertThrowsError(try repository.commit(faulty, maximumBodyHeight: 1_000, to: &session))
        session = try repository.loadSession(id: session.id)
        XCTAssertTrue(session.strips.isEmpty)
        XCTAssertNotNil(session.provisionalFrame)
        let fallback = try XCTUnwrap(pipeline.takeSingleFrameFallback())
        XCTAssertTrue(try repository.preserveProvisionalFrame(to: &session))
        session.finalizeCapture(reason: "图片写入失败，请检查剩余空间。", partial: true)
        try repository.saveManifest(session)
        XCTAssertTrue(session.hasImage)
        XCTAssertTrue(session.isSingleFrameFallback)
        XCTAssertEqual(session.strips.count, 1)
        XCTAssertNil(session.provisionalFrame)
        XCTAssertEqual(pixels(fallback), Array(source.prefix(120 * 48)))
    }

    func testDurableCandidateSurvivesWriterLossAndRecoversWithFreshRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CaptureSessionRepository(rootURL: directory)
        var session = try repository.createSession(configuration: .init())
        var lease: CaptureSessionLease? = try repository.acquireSessionLease(id: session.id)
        var pipeline: CaptureFramePipeline? = CaptureFramePipeline(configuration: .init(), repository: repository,
                                                                   sessionID: session.id)
        let original = scene(seed: 814)
        _ = try feed(try XCTUnwrap(pipeline), source: original, offset: 0)
        session = try repository.loadSession(id: session.id)
        let candidate = try XCTUnwrap(session.provisionalFrame)
        let candidateURL = try repository.stripURL(candidate, sessionID: session.id)
        let originalPNG = try Data(contentsOf: candidateURL)
        // A failing replacement must leave the already-published still intact.
        let other = scene(seed: 4_449)
        _ = try feed(try XCTUnwrap(pipeline), source: other, offset: 0)
        _ = try feed(try XCTUnwrap(pipeline), source: other, offset: 0)
        let otherGray = try frame(other, offset: 0)
        XCTAssertThrowsError(try pipeline?.ingest(otherGray) { throw CaptureStorageError.imageEncodingFailed })
        XCTAssertEqual(try repository.loadSession(id: session.id).provisionalFrame, candidate)
        XCTAssertEqual(try Data(contentsOf: candidateURL), originalPNG)
        session.updatedAt = Date(timeIntervalSinceNow: -60)
        try repository.saveManifest(session)
        let reopened = try CaptureSessionRepository(rootURL: directory)
        XCTAssertEqual(try reopened.recoverInterruptedSessions(), 0)
        withExtendedLifetime(lease) {}
        lease = nil; pipeline = nil
        XCTAssertEqual(try reopened.recoverInterruptedSessions(), 1)
        let recovered = try reopened.loadSession(id: session.id)
        XCTAssertTrue(recovered.hasImage)
        XCTAssertTrue(recovered.isSingleFrameFallback)
        XCTAssertEqual(recovered.status, .interrupted)
        XCTAssertEqual(recovered.strips, [candidate])
        XCTAssertNil(recovered.provisionalFrame)
        XCTAssertEqual(try Data(contentsOf: candidateURL), originalPNG)
        XCTAssertEqual(try reopened.recoverInterruptedSessions(), 0)
    }

    func testSuccessfulFirstCommitAcknowledgesAndRemovesDurableCandidate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try CaptureSessionRepository(rootURL: directory)
        var session = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 4, bottomInset: 6),
                                             repository: repository, sessionID: session.id)
        let source = scene(seed: 2_433)
        _ = try feed(pipeline, source: source, offset: 0)
        let candidate = try XCTUnwrap(pipeline.provisionalFrame)
        let candidateURL = try repository.stripURL(candidate, sessionID: session.id)
        let result = try feed(pipeline, source: source, offset: 30)
        try repository.commit(result, maximumBodyHeight: 1_000, to: &session)
        pipeline.confirmCommit()
        XCTAssertNil(session.provisionalFrame)
        XCTAssertNil(pipeline.takeSingleFrameFallback())
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidateURL.path))
    }

    func testChangingRejectedFramesNeverReplaceTheProvisionalStartingImage() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let original = scene(seed: 17_123)
        _ = try feed(pipeline, source: original, offset: 0)
        for seed in UInt64(20_000)..<20_008 {
            let gray = try frame(scene(seed: seed), offset: 0)
            let result = try pipeline.ingest(gray) {
                // One temporary recovery image is allowed; it must not replace
                // the published fallback or authorize a join without overlap.
                return self.image(gray)
            }
            XCTAssertTrue(result.strips.isEmpty)
            XCTAssertFalse(result.replacedProvisionalStart)
        }
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 0)
        XCTAssertEqual(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())), Array(original.prefix(120 * 48)))
    }

    private func feed(_ pipeline: CaptureFramePipeline, source: [UInt8], offset: Int) throws -> CaptureFrameResult {
        let gray = try frame(source, offset: offset)
        return try pipeline.ingest(gray) { self.image(gray) }
    }

    private func frame(_ source: [UInt8], offset: Int) throws -> GrayFrame {
        try GrayFrame(width: 48, height: 120, pixels: Array(source[(offset * 48)..<((offset + 120) * 48)]))
    }

    private func chromeFrame(_ document: [UInt8], offset: Int, top: Int, bottom: Int) throws -> GrayFrame {
        let chrome = scene(seed: 11_091)
        let pixels = Array(chrome.prefix(top * 48)) + Array(document[(offset * 48)..<((offset + 120) * 48)])
            + Array(chrome[(200 * 48)..<((200 + bottom) * 48)])
        return try GrayFrame(width: 48, height: top + 120 + bottom, pixels: pixels)
    }

    private func scene(seed: UInt64) -> [UInt8] {
        var state = seed
        return (0..<(48 * 400)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 32)
        }
    }

    private func image(_ frame: GrayFrame) -> CGImage {
        let data = Data(frame.pixels)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: frame.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

extension CaptureFramePipelineTests {
    func testImmediateTargetScrollRecoversBothDirectionsWithExactExportAndNoHostPixels() throws {
        for offsets in [[0, 12, 24, 36, 48, 60], [60, 48, 36, 24, 12, 0]] {
            for stillCount in [1, 2] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: root) }
                let repository = try CaptureSessionRepository(rootURL: root)
                var session = try repository.createSession(configuration: .init())
                let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: session.id)
                let target = scene(seed: 91)
                _ = try feed(pipeline, source: scene(seed: 4), offset: 0)
                for _ in 0..<stillCount { _ = try feed(pipeline, source: target, offset: offsets[0]) }
                for offset in offsets.dropFirst() {
                    let result = try feed(pipeline, source: target, offset: offset)
                    XCTAssertEqual(result.status, .advanced)
                    XCTAssertEqual(result.replacedProvisionalStart, offset == offsets[1])
                    session.provisionalFrame = pipeline.provisionalFrame
                    try repository.commit(result, maximumBodyHeight: 1_000, to: &session)
                    pipeline.confirmCommit()
                }
                XCTAssertEqual(pipeline.diagnostics.acceptedFrames, 5)
                XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 1)
                XCTAssertEqual(pipeline.diagnostics.startupRecoveryMethod, "adjacentSceneOverlap")
                session.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
                try repository.saveManifest(session)
                let exported = try CaptureImageRenderer(repository: repository).export(sessionID: session.id)
                let actual = try XCTUnwrap(UIImage(contentsOfFile: exported.path)?.cgImage)
                XCTAssertEqual(pixels(actual), Array(target.prefix(180 * 48)))
            }
        }
    }

    func testLocalCornerChangesPermitStableReplacementWithoutCreatingALongImage() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        _ = try feed(pipeline, source: scene(seed: 4), offset: 0)
        let target = scene(seed: 91)
        for index in 1...3 {
            var bytes = Array(target.prefix(120 * 48)); bytes[0] = UInt8(index)
            let gray = try GrayFrame(width: 48, height: 120, pixels: bytes)
            _ = try pipeline.ingest(gray) { self.image(gray) }
        }
        XCTAssertFalse(pipeline.hasStarted)
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 1)
        XCTAssertEqual(pipeline.diagnostics.startupRecoveryMethod, "stableSceneReplacement")
        let result = try feed(pipeline, source: target, offset: 12)
        XCTAssertEqual(result.status, .advanced)
        XCTAssertEqual(result.strips.last?.image.height, 12)
    }

    func testDistributedMinorChangesCannotEstablishStableScene() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let host = scene(seed: 4), target = scene(seed: 91)
        _ = try feed(pipeline, source: host, offset: 0)
        for index in 1...8 {
            var bytes = Array(target.prefix(120 * 48))
            bytes[0] = UInt8(index); bytes[119 * 48 + 47] = UInt8(index)
            let gray = try GrayFrame(width: 48, height: 120, pixels: bytes)
            _ = try pipeline.ingest(gray) { self.image(gray) }
        }
        XCTAssertFalse(pipeline.hasStarted)
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 0)
        XCTAssertEqual(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())), Array(host.prefix(120 * 48)))
    }

    func testOriginalCandidateWinsWhenItReturnsBeforeNewSceneIsConfirmed() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let original = scene(seed: 4)
        _ = try feed(pipeline, source: original, offset: 0)
        _ = try feed(pipeline, source: scene(seed: 91), offset: 0)
        let result = try feed(pipeline, source: original, offset: 12)
        XCTAssertEqual(result.status, .advanced)
        XCTAssertFalse(result.replacedProvisionalStart)
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 0)
        XCTAssertEqual(result.strips.flatMap { pixels($0.image) }, Array(original.prefix(132 * 48)))
    }

    func testProvisionalOnlyPauseResumesImmediateScrollingWithNewOrigin() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        var lifecycle = CaptureLifecyclePolicy()
        _ = try feed(pipeline, source: scene(seed: 4), offset: 0)
        XCTAssertTrue(pipeline.hasReference); XCTAssertFalse(pipeline.hasStarted)
        lifecycle.pause(at: 1, requiresOverlap: pipeline.hasStarted)
        lifecycle.resume(at: 2)
        XCTAssertFalse(lifecycle.needsOverlapAfterResume)
        for offset in [0, 12] {
            let gray = try frame(scene(seed: 91), offset: offset)
            _ = try pipeline.ingest(gray, allowProvisionalReplacement: !lifecycle.needsOverlapAfterResume) { self.image(gray) }
        }
        XCTAssertTrue(pipeline.hasStarted)
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 1)
    }

    func testAfterFirstJoinUnrelatedAdjacentFramesCannotReplaceTrustedOrigin() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let original = scene(seed: 4), other = scene(seed: 91)
        for offset in [0, 12] { _ = try feed(pipeline, source: original, offset: offset) }
        for offset in [0, 12, 24, 36] {
            let rejected = try feed(pipeline, source: other, offset: offset)
            XCTAssertEqual(rejected.status, .rejected)
            XCTAssertTrue(rejected.strips.isEmpty)
        }
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 0)
        let recovered = try feed(pipeline, source: original, offset: 24)
        XCTAssertEqual(pixels(try XCTUnwrap(recovered.strips.last).image), Array(original[(132 * 48)..<(144 * 48)]))
    }

    func testRecoveryCandidateRenderingFailurePreservesPublishedFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        let session = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: session.id)
        let host = scene(seed: 4)
        _ = try feed(pipeline, source: host, offset: 0)
        let published = pipeline.provisionalFrame
        let other = try frame(scene(seed: 91), offset: 0)
        XCTAssertThrowsError(try pipeline.ingest(other) { throw CaptureStorageError.imageEncodingFailed })
        XCTAssertEqual(try repository.loadSession(id: session.id).provisionalFrame, published)
        XCTAssertEqual(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())), Array(host.prefix(120 * 48)))
    }

    func testRecoveredFirstCommitFailureKeepsCompleteTargetFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var session = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: session.id)
        let target = scene(seed: 91)
        _ = try feed(pipeline, source: scene(seed: 4), offset: 0)
        _ = try feed(pipeline, source: target, offset: 0)
        let result = try feed(pipeline, source: target, offset: 12)
        XCTAssertTrue(result.replacedProvisionalStart)
        let wrong = try GrayFrame(width: 49, height: 2, pixels: [UInt8](repeating: 0, count: 98))
        let faulty = CaptureFrameResult(status: .advanced,
            strips: result.strips + [.init(image: image(wrong), sourceTopPixel: 0)], isArming: false)
        XCTAssertThrowsError(try repository.commit(faulty, maximumBodyHeight: 1_000, to: &session))
        session = try repository.loadSession(id: session.id)
        XCTAssertTrue(session.strips.isEmpty)
        XCTAssertEqual(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())), Array(target.prefix(120 * 48)))
        XCTAssertTrue(try repository.preserveProvisionalFrame(to: &session))
    }

    func testManualRegionAndAutomaticCapsRecoverUpwardStartAndReversal() throws {
        for manual in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let repository = try CaptureSessionRepository(rootURL: root)
            var session = try repository.createSession(configuration: .init())
            let config = AlignmentConfiguration(topInset: manual ? 17 : 0, bottomInset: manual ? 23 : 0)
            let pipeline = CaptureFramePipeline(configuration: config, repository: repository, sessionID: session.id)
            let host = try chromeFrame(scene(seed: 4), offset: 0, top: 17, bottom: 23)
            _ = try pipeline.ingest(host) { self.image(host) }
            let target = scene(seed: 91)
            for offset in [60, 48, 24, 0, 36, 72] {
                let gray = try chromeFrame(target, offset: offset, top: 17, bottom: 23)
                let result = try pipeline.ingest(gray) { self.image(gray) }
                if !result.strips.isEmpty {
                    try repository.commit(result, maximumBodyHeight: 1_000, to: &session)
                    pipeline.confirmCommit()
                }
            }
            session.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
            try repository.saveManifest(session)
            let url = try CaptureImageRenderer(repository: repository).export(sessionID: session.id)
            let actual = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
            let chrome = scene(seed: 11_091)
            let expected = manual ? Array(target.prefix(192 * 48))
                : Array(chrome.prefix(17 * 48)) + Array(target.prefix(192 * 48)) + Array(chrome[(200 * 48)..<(223 * 48)])
            XCTAssertEqual(pixels(actual), expected)
            XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 1)
        }
    }

    func testUnchangedTargetBodyKeepsEarliestFullScreenDespiteChromeChanges() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let target = scene(seed: 91)
        let host = try chromeFrame(scene(seed: 4), offset: 0, top: 17, bottom: 23)
        _ = try pipeline.ingest(host) { self.image(host) }
        let first = try chromeFrame(target, offset: 0, top: 17, bottom: 23)
        _ = try pipeline.ingest(first) { self.image(first) }
        for offset in [0, 12] {
            let original = try chromeFrame(target, offset: offset, top: 17, bottom: 23)
            var bytes = original.pixels
            for x in 0..<12 { bytes[x] = 9 }
            let gray = try GrayFrame(width: original.width, height: original.height, pixels: bytes)
            let result = try pipeline.ingest(gray) { self.image(gray) }
            if offset == 0 { XCTAssertTrue(result.strips.isEmpty) }
            else {
                XCTAssertEqual(result.status, .advanced)
                XCTAssertEqual(pixels(try XCTUnwrap(result.strips.first?.fullImage)), first.pixels)
            }
        }
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 1)
    }

    func testPromotionFailurePreservesOldStillAndRenderFailureAfterPromotionPreservesTarget() throws {
        for failPromotion in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let repository = try CaptureSessionRepository(rootURL: root)
            var session = try repository.createSession(configuration: .init())
            let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: session.id)
            let host = scene(seed: 4), target = scene(seed: 91)
            _ = try feed(pipeline, source: host, offset: 0)
            _ = try feed(pipeline, source: target, offset: 0)
            if failPromotion {
                // A concurrent terminal manifest makes promotion fail its
                // transactional publication precondition, before replacing PNG.
                session = try repository.loadSession(id: session.id)
                session.status = .completed; try repository.saveManifest(session)
            }
            let current = try frame(target, offset: 12)
            XCTAssertThrowsError(try pipeline.ingest(current) { throw CaptureStorageError.imageEncodingFailed })
            XCTAssertFalse(pipeline.hasStarted)
            let expected = failPromotion ? host : target
            XCTAssertEqual(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())), Array(expected.prefix(120 * 48)))
            let published = try repository.loadSession(id: session.id)
            let candidate = try XCTUnwrap(published.provisionalFrame)
            let url = try repository.stripURL(candidate, sessionID: session.id)
            XCTAssertEqual(pixels(try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)), Array(expected.prefix(120 * 48)))
        }
    }

    func testFadeAndScalingSceneTransitionsDoNotInventScrolling() throws {
        let target = scene(seed: 91)
        for transition in ["fade", "scale", "localMove"] {
            let pipeline = CaptureFramePipeline(configuration: .init())
            _ = try feed(pipeline, source: scene(seed: 4), offset: 0)
            for index in 0..<5 {
                var bytes = Array(target.prefix(120 * 48))
                for y in 0..<120 {
                    for x in 0..<48 {
                        let position = y * 48 + x
                        switch transition {
                        case "fade": bytes[position] = UInt8(Int(bytes[position]) * (index + 2) / 8)
                        case "scale":
                            let sourceX = min(47, x * (6 + index) / 10)
                            let sourceY = min(119, y * (6 + index) / 10)
                            bytes[position] = target[sourceY * 48 + sourceX]
                        default:
                            if (20..<35).contains(y), (4..<10).contains(x) {
                                bytes[position] = target[(y + index * 3) * 48 + x]
                            }
                        }
                    }
                }
                bytes[0] = UInt8(index)
                let gray = try GrayFrame(width: 48, height: 120, pixels: bytes)
                let result = try pipeline.ingest(gray) { self.image(gray) }
                XCTAssertTrue(result.strips.isEmpty, transition)
            }
            XCTAssertFalse(pipeline.hasStarted, transition)
        }
    }

    func testRecoveryTemporaryPNGIsBoundedAndRemovedOnStopAndDeinit() throws {
        func files() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
                .filter { $0.hasPrefix("Longlet-Recovery-") })
        }
        let before = try files()
        var pipeline: CaptureFramePipeline? = CaptureFramePipeline(configuration: .init())
        _ = try feed(try XCTUnwrap(pipeline), source: scene(seed: 4), offset: 0)
        for seed in UInt64(90)...94 {
            _ = try feed(try XCTUnwrap(pipeline), source: scene(seed: seed), offset: 0)
            XCTAssertEqual(try files().subtracting(before).count, 1)
        }
        _ = pipeline?.takeSingleFrameFallback()
        XCTAssertEqual(try files(), before)
        pipeline = CaptureFramePipeline(configuration: .init())
        _ = try feed(try XCTUnwrap(pipeline), source: scene(seed: 4), offset: 0)
        _ = try feed(try XCTUnwrap(pipeline), source: scene(seed: 91), offset: 0)
        XCTAssertEqual(try files().subtracting(before).count, 1)
        pipeline = nil
        XCTAssertEqual(try files(), before)
    }
}
