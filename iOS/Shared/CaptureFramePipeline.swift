#if canImport(UIKit)
import CoreGraphics
import CoreImage
import ImageIO
import ScrollCaptureCore

struct PendingCaptureStrip {
    let image: CGImage
    let sourceTopPixel: Int
    let placement: StitchDecision.Placement
    /// Automatic matching insets never authorize losing outer screen pixels.
    /// The repository preserves these edges once and replaces the advancing end
    /// in the same atomic manifest commit as its adjoining content.
    let fullImage: CGImage?
    let topInset: Int
    let bottomInset: Int
    let isInitial: Bool

    init(image: CGImage, sourceTopPixel: Int, placement: StitchDecision.Placement = .append,
         fullImage: CGImage? = nil, topInset: Int = 0, bottomInset: Int = 0, isInitial: Bool = false) {
        self.image = image; self.sourceTopPixel = sourceTopPixel; self.placement = placement
        self.fullImage = fullImage; self.topInset = topInset; self.bottomInset = bottomInset
        self.isInitial = isInitial
    }
}

struct CaptureFrameResult {
    let status: StitchDecision.Status
    let strips: [PendingCaptureStrip]
    let isArming: Bool
    let replacedProvisionalStart: Bool
    let regionWarning: String?
    init(status: StitchDecision.Status, strips: [PendingCaptureStrip], isArming: Bool,
         replacedProvisionalStart: Bool = false, regionWarning: String? = nil) {
        self.status = status; self.strips = strips; self.isArming = isArming
        self.replacedProvisionalStart = replacedProvisionalStart; self.regionWarning = regionWarning
    }
}

/// One provisional lossless still file, bounded grayscale evidence, and no
/// untrusted bridge. A rejected frame never becomes a reference after stitching starts.
final class CaptureFramePipeline {
    let configuration: AlignmentConfiguration
    private(set) var effectiveConfiguration: AlignmentConfiguration
    private var stitcher: StreamStitcher
    private var candidateURL: URL?
    private let candidateRepository: CaptureSessionRepository?
    private let candidateSessionID: UUID?
    private var firstCommitConfirmed = false
    private(set) var provisionalFrame: CaptureStrip?
    private var candidateAnalysis: GrayFrame?
    private var armingRejections = 0
    private var rejectedSceneAnalysis: GrayFrame?
    private var rejectedSceneURL: URL?
    private var wasRejected = false
    private var measuredOtherSeconds = 0.0
    private(set) var hasStarted = false
    private(set) var diagnostics = CaptureDiagnostics()
    var hasReference: Bool { hasStarted || candidateAnalysis != nil }
    private var automaticallyFindRegion: Bool { configuration.topInset == 0 && configuration.bottomInset == 0 }

    init(configuration: AlignmentConfiguration, repository: CaptureSessionRepository? = nil, sessionID: UUID? = nil) {
        self.configuration = configuration; self.effectiveConfiguration = configuration
        self.stitcher = StreamStitcher(configuration: configuration)
        self.candidateRepository = repository; self.candidateSessionID = sessionID
    }

    deinit { clearCandidate(); clearRejectedScene() }

    func ingest(_ analysis: GrayFrame, allowProvisionalReplacement: Bool = true,
                makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        do { return try ingestFrame(analysis, allowProvisionalReplacement: allowProvisionalReplacement, makeImage: makeImage) }
        catch { clearRejectedScene(); throw error }
    }

    private func ingestFrame(_ analysis: GrayFrame, allowProvisionalReplacement: Bool,
                             makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        let began = ProcessInfo.processInfo.systemUptime
        let excludedBefore = measuredOtherSeconds
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            recordTiming(.alignment, seconds: max(0, elapsed - (measuredOtherSeconds - excludedBefore)))
        }
        diagnostics.observedFrames += 1
        if candidateAnalysis == nil && !hasStarted {
            return try arm(analysis, replaced: false, makeImage: makeImage)
        }
        var updated = stitcher
        var decision: StitchDecision
        var selectedStart: VerifiedStart?
        var replacedStart = false
        if !hasStarted, let reference = candidateAnalysis {
            let attempt = evaluateStart(reference: reference, current: analysis)
            if let verified = attempt.verified {
                selectedStart = verified
            } else if attempt.status == .rejected {
                if allowProvisionalReplacement {
                    let recovery = rejectedSceneAnalysis.map { evaluateStart(reference: $0, current: analysis) }
                    if let previous = rejectedSceneAnalysis, let recovered = recovery?.verified {
                        // Promote only after the SAME strict verification used for
                        // the original start. Publishing the still is transactional.
                        guard let image = loadImage(at: rejectedSceneURL) else {
                            throw CaptureStorageError.imageEncodingFailed
                        }
                        _ = try arm(previous, replaced: true) { image }
                        selectedStart = recovered; replacedStart = true
                        diagnostics.startupRecoveryMethod = "adjacentSceneOverlap"
                    } else if recovery?.status == .unchanged,
                              let previous = rejectedSceneAnalysis, !locallyStable(previous, analysis) {
                        // Strictly unchanged body can coexist with changing system
                        // chrome. Retain the earliest target screen without treating
                        // changing outer pixels as evidence for stable promotion.
                        armingRejections = 1; diagnostics.stableCandidateFrameCount = 1
                    } else if let replacement = try stableSceneReplacement(analysis, makeImage: makeImage) {
                        return replacement
                    }
                } else { clearRejectedScene() }
                if selectedStart == nil {
                    let result = reject(arming: true, region: attempt.regionRejected)
                    if attempt.foregroundRejected { diagnostics.lastStage = "foreground" }
                    return result
                }
            } else {
                // The original candidate remains first priority, including when
                // it becomes visible again after a transient unrelated screen.
                clearRejectedScene()
                return .init(status: .unchanged, strips: [], isArming: true)
            }
            guard let verified = selectedStart else { return reject(arming: true, region: false) }
            updated = verified.stitcher; decision = verified.decision
            effectiveConfiguration = verified.configuration
        } else {
            decision = updated.ingest(analysis)
            recordForeground(updated.lastForegroundRegistration, status: decision.status)
            if decision.status == .rejected { return reject(arming: false, region: false) }
        }
        clearRejectedScene()
        if decision.status == .unchanged {
            if hasStarted { stitcher = updated }
            recoveredIfNeeded()
            return .init(status: .unchanged, strips: [], isArming: !hasStarted)
        }
        guard let rows = decision.sourceRows, !rows.isEmpty else {
            stitcher = updated; recoveredIfNeeded()
            return .init(status: decision.status, strips: [], isArming: !hasStarted)
        }
        let region = effectiveConfiguration
        var strips: [PendingCaptureStrip] = []
        if !hasStarted {
            guard let candidateImage = loadCandidate(),
                  let first = candidateImage.cropping(to: CGRect(x: 0, y: region.topInset,
                      width: candidateImage.width, height: candidateImage.height - region.topInset - region.bottomInset))
            else { throw CaptureStorageError.imageEncodingFailed }
            strips.append(.init(image: first, sourceTopPixel: region.topInset,
                                fullImage: automaticallyFindRegion ? candidateImage : nil,
                                topInset: region.topInset, bottomInset: region.bottomInset, isInitial: true))
        }
        let image = try measure(.frameRendering, makeImage)
        guard image.height == analysis.height,
              let added = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count))
        else { throw CaptureStorageError.imageEncodingFailed }
        strips.append(.init(image: added, sourceTopPixel: rows.lowerBound, placement: decision.placement,
                            fullImage: automaticallyFindRegion ? image : nil,
                            topInset: region.topInset, bottomInset: region.bottomInset))
        if !hasStarted {
            // Record only the region whose replay won and whose strips were
            // rendered. Failed/conflicting candidates must leave no values.
            diagnostics.matchingTopInset = region.topInset
            diagnostics.matchingBottomInset = region.bottomInset
            diagnostics.matchingFrameHeight = analysis.height
            diagnostics.matchingRegionSource = selectedStart?.source ?? "manual"
            diagnostics.fixedBandTop = selectedStart?.fixedBand?.top
            diagnostics.fixedBandBottom = selectedStart?.fixedBand?.bottom
        }
        if !hasStarted {
            diagnostics.startupRecoveryMethod = diagnostics.startupRecoveryMethod ?? "initialOverlap"
            diagnostics.startupWaitingState = "confirmed"
        }
        hasStarted = true; candidateAnalysis = nil
        stitcher = updated; diagnostics.acceptedFrames += 1; diagnostics.lastStage = "stitching"
        recoveredIfNeeded()
        return .init(status: decision.status, strips: strips, isArming: false, replacedProvisionalStart: replacedStart)
    }

    /// This is explicitly a single screen fallback, never evidence of a long image.
    func takeSingleFrameFallback() -> CGImage? {
        guard !firstCommitConfirmed else { return nil }
        defer { clearCandidate(); clearRejectedScene(); candidateAnalysis = nil }
        return loadCandidate()
    }

    private func arm(_ analysis: GrayFrame, replaced: Bool,
                     makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        // Stage the new still before releasing the old one. A rendering or
        // write failure during an app switch leaves the last usable candidate.
        let oldURL = candidateURL
        let url: URL
        if let repository = candidateRepository, let sessionID = candidateSessionID {
            let candidate = try autoreleasepool {
                let image = try measure(.frameRendering, makeImage)
                return try measure(.provisionalWrite) {
                    try repository.stageProvisionalFrame(image: image, sessionID: sessionID)
                }
            }
            provisionalFrame = candidate
            url = try repository.stripURL(candidate, sessionID: sessionID)
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("Longlet-Candidate-\(UUID().uuidString).png")
            try autoreleasepool {
                let image = try measure(.frameRendering, makeImage)
                try measure(.provisionalWrite) { try CaptureSessionRepository.writeImage(image, to: url, format: .png) }
            }
        }
        candidateURL = url
        if candidateRepository == nil, let oldURL { try? FileManager.default.removeItem(at: oldURL) }
        candidateAnalysis = analysis; clearRejectedScene()
        stitcher = StreamStitcher(configuration: configuration); _ = stitcher.ingest(analysis)
        diagnostics.startupWaitingState = "waitingForTarget"
        diagnostics.lastStage = "arming"
        if replaced { diagnostics.provisionalReplacements += 1 }
        return .init(status: .started, strips: [], isArming: true, replacedProvisionalStart: replaced)
    }

    /// The additional scene is untrusted and never appears in the manifest.
    /// Compare every stable sample against this fixed anchor, not the previous
    /// sample, so small changes cannot accumulate into a drifting scene.
    private func stableSceneReplacement(_ analysis: GrayFrame,
                                        makeImage: () throws -> CGImage) throws -> CaptureFrameResult? {
        if let previous = rejectedSceneAnalysis, locallyStable(previous, analysis) {
            armingRejections = min(3, armingRejections + 1)
            diagnostics.stableCandidateFrameCount = armingRejections
            if armingRejections >= 3 {
                let result = try arm(analysis, replaced: true, makeImage: makeImage)
                diagnostics.startupRecoveryMethod = "stableSceneReplacement"
                return result
            }
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Longlet-Recovery-\(UUID().uuidString).png")
        do {
            try autoreleasepool {
                let image = try measure(.frameRendering, makeImage)
                try measure(.provisionalWrite) { try CaptureSessionRepository.writeImage(image, to: url, format: .png) }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        clearRejectedScene()
        rejectedSceneAnalysis = analysis; rejectedSceneURL = url; armingRejections = 1
        diagnostics.stableCandidateFrameCount = 1
        return nil
    }

    private func locallyStable(_ reference: GrayFrame, _ current: GrayFrame) -> Bool {
        guard reference.width == current.width, reference.height == current.height else { return false }
        if reference.pixels.elementsEqual(current.pixels) { return true }
        // At most 0.25% changed pixels, mean absolute error <= 0.25 gray levels,
        // all changes inside one <= 10%-wide by <= 10%-high patch. A status
        // corner may blink; distributed noise, scrolling and full-page fades
        // cannot establish a replacement. This never authorizes a long join.
        let limit = max(1, reference.pixels.count / 400)
        var count = 0, total = 0
        var minX = reference.width, minY = reference.height, maxX = 0, maxY = 0
        for index in reference.pixels.indices {
            let difference = abs(Int(reference.pixels[index]) - Int(current.pixels[index]))
            guard difference != 0 else { continue }
            count += 1; total += difference
            if count > limit || total > reference.pixels.count / 4 { return false }
            let x = index % reference.width, y = index / reference.width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        return maxX - minX + 1 <= max(1, reference.width / 10)
            && maxY - minY + 1 <= max(1, reference.height / 10)
    }

    private func clearRejectedScene() {
        if let rejectedSceneURL { try? FileManager.default.removeItem(at: rejectedSceneURL) }
        rejectedSceneURL = nil; rejectedSceneAnalysis = nil; armingRejections = 0
        diagnostics.stableCandidateFrameCount = 0
    }

    private struct StartAttempt {
        var verified: VerifiedStart? = nil
        var status: StitchDecision.Status = .rejected
        var regionRejected = false
        var foregroundRejected = false
    }

    /// One validation gate for BOTH provisional references. Failed region and
    /// foreground checks return evidence, never bypass the startup recovery path.
    private func evaluateStart(reference: GrayFrame, current: GrayFrame) -> StartAttempt {
        guard automaticallyFindRegion else {
            var replay = StreamStitcher(configuration: configuration)
            guard replay.ingest(reference).status == .started else { return .init() }
            let decision = replay.ingest(current)
            recordForeground(replay.lastForegroundRegistration, status: decision.status)
            return .init(verified: decision.status == .advanced
                ? .init(stitcher: replay, decision: decision, configuration: configuration,
                        source: "manual", fixedBand: nil) : nil, status: decision.status)
        }
        let foreground = measure(.foregroundRegistration) {
            ForegroundMotionRegistration.analyze(reference: reference, current: current, configuration: configuration)
        }
        recordForeground(foreground, status: .rejected)
        switch foreground.status {
        case .matched:
            diagnostics.regionAttempts += 1
            guard let displacement = foreground.displacement, let insets = foreground.matchingInsets,
                  let verified = verifyStart(reference: reference, current, displacement: displacement,
                                             preferredInsets: insets) else { return .init(regionRejected: true) }
            return .init(verified: verified, status: .advanced)
        case .rejected: return .init(foregroundRejected: true)
        case .unchanged: return .init(status: .unchanged)
        case .notLayered: break
        }
        let windows = [(reference.height / 5, reference.height / 5),
                       (reference.height / 8, reference.height / 8),
                       (reference.height / 10, reference.height * 2 / 5),
                       (reference.height / 10, reference.height / 2),
                       (reference.height / 3, reference.height / 3)]
        var hypotheses: [StitchDecision] = []
        var checkedOffsets: Set<Int> = []
        var verifiedOffsets: [Int: VerifiedStart] = [:]
        var accepted: [VerifiedStart] = []
        for (top, bottom) in windows {
            var region = configuration; region.topInset = top; region.bottomInset = bottom
            var probe = StreamStitcher(configuration: region); _ = probe.ingest(reference)
            let hypothesis = probe.ingest(current); hypotheses.append(hypothesis)
            guard hypothesis.status == .advanced else { continue }
            if checkedOffsets.insert(hypothesis.contentOffset).inserted {
                if checkedOffsets.count == 1 { diagnostics.regionAttempts += 1 }
                if let verified = verifyStart(reference: reference, current, displacement: hypothesis.contentOffset) {
                    verifiedOffsets[hypothesis.contentOffset] = verified
                }
            }
            if let verified = verifiedOffsets[hypothesis.contentOffset] { accepted.append(verified) }
            if Set(accepted.map { $0.decision.contentOffset }).count > 1 { return .init(regionRejected: true) }
            if accepted.count >= 2 { break }
        }
        if let verified = accepted.first { return .init(verified: verified, status: .advanced) }
        if !hypotheses.isEmpty, hypotheses.allSatisfy({ $0.status == .unchanged }) { return .init(status: .unchanged) }
        return .init(regionRejected: !checkedOffsets.isEmpty)
    }

    private func recordForeground(_ foreground: ForegroundMotionRegistration.Result?, status: StitchDecision.Status) {
        diagnostics.foregroundStatus = foreground?.status.rawValue ?? (status == .unchanged ? "unchanged" : nil)
        diagnostics.foregroundCandidateCount = foreground?.candidateCount ?? 0
        diagnostics.foregroundSupportCount = foreground?.supportCount ?? 0
    }

    private struct VerifiedStart {
        let stitcher: StreamStitcher
        let decision: StitchDecision
        let configuration: AlignmentConfiguration
        let source: String
        let fixedBand: (top: Int, bottom: Int)?
    }

    private func verifyStart(reference candidateAnalysis: GrayFrame, _ analysis: GrayFrame, displacement: Int,
                             preferredInsets: FixedRegionDetector.Insets? = nil) -> VerifiedStart? {
        let candidates: [FixedRegionDetector.Insets]
        let source: String
        let band: (top: Int, bottom: Int)?
        if let preferredInsets {
            candidates = [preferredInsets]; source = "foreground"; band = nil
        } else {
            // candidates can discover foreground AFTER swapping an upward
            // pair. A missing preferred region alone does not imply whole-page
            // translation; preserve the detector's explicit candidate source.
            let result = FixedRegionDetector.candidateSet(reference: candidateAnalysis,
                current: analysis, displacement: displacement)
            candidates = result.insets
            source = result.source == .foreground ? "foreground" : "wholePage"
            band = result.source == .wholePage
                ? FixedRegionDetector.fixedStructureBand(reference: candidateAnalysis, current: analysis) : nil
        }
        for insets in candidates {
            // This second gate precedes replay: its trimmed score may otherwise
            // hide a narrow fixed header inside a mostly correct moving region.
            if let band, insets.top < band.top || insets.bottom < band.bottom { continue }
            var region = configuration
            region.topInset = insets.top; region.bottomInset = insets.bottom
            // Automatic foreground has already established a fixed layer in
            // this frame pair's original allowed analysis range. Recheck that
            // texture context on every replay/continuation pair while keeping
            // ALL motion features and overlap scoring inside the chosen body.
            // Manual regions and whole-page candidates retain ROI isolation.
            let stationaryRows = automaticallyFindRegion && source == "foreground"
                ? configuration.topInset..<(analysis.height - configuration.bottomInset) : nil
            var replay = StreamStitcher(configuration: region, stationaryEvidenceRows: stationaryRows)
            guard replay.ingest(candidateAnalysis).status == .started else { continue }
            let result = replay.ingest(analysis)
            if result.status == .advanced, result.contentOffset == displacement {
                return VerifiedStart(stitcher: replay, decision: result, configuration: region, source: source, fixedBand: band)
            }
        }
        return nil
    }

    private func loadCandidate() -> CGImage? { loadImage(at: candidateURL) }

    private func loadImage(at url: URL?) -> CGImage? {
        measure(.provisionalRead) {
            guard let url,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                diagnostics.lastStage = "provisionalRead"; return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
    }

    private func measure<T>(_ stage: CaptureProcessingStage, _ operation: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            measuredOtherSeconds += elapsed
            recordTiming(stage, seconds: elapsed)
        }
        do { return try operation() }
        catch { diagnostics.lastStage = stage.rawValue; throw error }
    }

    private func recordTiming(_ stage: CaptureProcessingStage, seconds: Double) {
        var timings = diagnostics.stageTimings ?? .init()
        timings.record(stage, seconds: seconds); diagnostics.stageTimings = timings
    }

    /// Call only after the corresponding repository transaction has succeeded.
    /// Until then, even a detected first scroll can fall back to its durable still.
    func confirmCommit() {
        guard hasStarted else { return }
        firstCommitConfirmed = true; clearCandidate(); provisionalFrame = nil
    }

    private func clearCandidate() {
        // App Group candidates are owned by the atomic manifest transaction;
        // destroying this pipeline or a failed fallback must not delete them.
        if candidateRepository == nil, let candidateURL { try? FileManager.default.removeItem(at: candidateURL) }
        candidateURL = nil
    }

    private func reject(arming: Bool, region: Bool) -> CaptureFrameResult {
        wasRejected = true; diagnostics.rejectedFrames += 1
        diagnostics.lastStage = region ? "region" : "alignment"
        return .init(status: .rejected, strips: [], isArming: arming,
                     regionWarning: region ? "正在确认滚动区域，请缓慢滚动并等待画面稳定。" : nil)
    }

    private func recoveredIfNeeded() {
        if wasRejected { diagnostics.recoveredGaps += 1; wasRejected = false }
    }
}

/// Shared by the real capture adapters and host tests. CGImage crop rows and
/// GrayFrame pixels both use the CGImage's top-to-bottom provider row order.
/// Core Image's bottom-left coordinate system is confined to createCGImage.
enum CaptureFrameConversion {
    static func grayFrame(_ source: CIImage, context imageContext: CIContext,
                          width: Int, height: Int) throws -> GrayFrame {
        let normalized = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX,
                                                                  y: -source.extent.minY))
        let resized = normalized.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / normalized.extent.width,
                                                                   y: CGFloat(height) / normalized.extent.height))
        guard width > 0, height > 0,
              let image = imageContext.createCGImage(resized, from: CGRect(x: 0, y: 0, width: width, height: height)),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let bytes = context.data else { throw CaptureStorageError.imageEncodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try GrayFrame(width: width, height: height,
                             pixels: Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self),
                                                               count: width * height)))
    }
}
#endif
