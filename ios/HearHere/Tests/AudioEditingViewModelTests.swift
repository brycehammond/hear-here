import Foundation
import XCTest
@testable import HearHere

// MARK: - Mocks

final class MockWaveformDataProvider: WaveformDataProviding, @unchecked Sendable {
    var stubbedResult: WaveformData?
    var stubbedError: Error?
    private(set) var extractCallCount = 0

    func extractWaveform(from url: URL, targetBinCount: Int) async throws -> WaveformData {
        extractCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedResult ?? WaveformData(
            peaks: Array(repeating: Float(0.5), count: targetBinCount),
            sampleRate: 44100
        )
    }
}

final class MockAudioEngine: AudioEngineProtocol, @unchecked Sendable {
    var stubbedOutputURL: URL?
    var stubbedError: Error?
    private(set) var processCallCount = 0
    private(set) var lastOperations: [EditOperation]?

    func process(inputURL: URL, operations: [EditOperation]) async throws -> URL {
        processCallCount += 1
        lastOperations = operations
        if let error = stubbedError { throw error }
        return stubbedOutputURL ?? URL(fileURLWithPath: "/tmp/edited-output.m4a")
    }
}

// MARK: - Tests

@MainActor
final class AudioEditingViewModelTests: XCTestCase {
    private let testURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

    private func makeSUT(
        waveformProvider: MockWaveformDataProvider = MockWaveformDataProvider(),
        audioEngine: MockAudioEngine = MockAudioEngine()
    ) -> (AudioEditingViewModel, MockWaveformDataProvider, MockAudioEngine) {
        let vm = AudioEditingViewModel(
            fileURL: testURL,
            originalDuration: 10.0,
            waveformProvider: waveformProvider,
            audioEngine: audioEngine
        )
        return (vm, waveformProvider, audioEngine)
    }

    func testInitialStateIsIdle() {
        let (vm, _, _) = makeSUT()
        XCTAssertEqual(vm.state, .idle)
    }

    func testLoadWaveformPopulatesData() async {
        let provider = MockWaveformDataProvider()
        provider.stubbedResult = WaveformData(
            peaks: [0.1, 0.5, 0.9],
            sampleRate: 44100
        )
        let (vm, _, _) = makeSUT(waveformProvider: provider)

        await vm.loadWaveform()

        XCTAssertNotNil(vm.waveformData)
        XCTAssertEqual(vm.waveformData?.peaks.count, 3)
        XCTAssertEqual(provider.extractCallCount, 1)
    }

    func testPlayTransitionsToPreviewing() {
        let (vm, _, _) = makeSUT()
        vm.play()
        XCTAssertEqual(vm.state, .previewing)
    }

    func testPauseTransitionsToIdle() {
        let (vm, _, _) = makeSUT()
        vm.play()
        vm.pause()
        XCTAssertEqual(vm.state, .idle)
    }

    func testApplyTrimAddsOperationToSession() {
        let (vm, _, _) = makeSUT()
        vm.selectionRange = 1.0...5.0
        vm.applyTrim()
        XCTAssertEqual(vm.editSession.operations.count, 1)
        XCTAssertEqual(vm.editSession.operations.first, EditOperation.trim(start: 1.0, end: 5.0))
    }

    func testApplyCutAddsOperationToSession() {
        let (vm, _, _) = makeSUT()
        vm.selectionRange = 2.0...4.0
        vm.applyCut()
        XCTAssertEqual(vm.editSession.operations.count, 1)
        XCTAssertEqual(vm.editSession.operations.first, EditOperation.cut(start: 2.0, end: 4.0))
    }

    func testApplyFadeInAddsOperation() {
        let (vm, _, _) = makeSUT()
        vm.applyFadeIn()
        XCTAssertEqual(vm.editSession.operations.count, 1)
        if case .fadeIn = vm.editSession.operations.first {} else {
            XCTFail("Expected fadeIn operation")
        }
    }

    func testApplyFadeOutAddsOperation() {
        let (vm, _, _) = makeSUT()
        vm.applyFadeOut()
        XCTAssertEqual(vm.editSession.operations.count, 1)
        if case .fadeOut = vm.editSession.operations.first {} else {
            XCTFail("Expected fadeOut operation")
        }
    }

    func testApplyNormalizeAddsOperation() {
        let (vm, _, _) = makeSUT()
        vm.applyNormalize()
        XCTAssertEqual(vm.editSession.operations.count, 1)
        XCTAssertEqual(vm.editSession.operations.first, EditOperation.normalize(targetPeakDb: -1.0))
    }

    func testUndoPropagatesToSession() {
        let (vm, _, _) = makeSUT()
        vm.applyFadeIn()
        XCTAssertTrue(vm.editSession.canUndo)
        vm.undo()
        XCTAssertTrue(vm.editSession.operations.isEmpty)
        XCTAssertFalse(vm.editSession.canUndo)
    }

    func testRedoPropagatesToSession() {
        let (vm, _, _) = makeSUT()
        vm.applyFadeIn()
        vm.undo()
        XCTAssertTrue(vm.editSession.canRedo)
        vm.redo()
        XCTAssertEqual(vm.editSession.operations.count, 1)
    }

    func testExportEditedTransitionsThroughProcessingToCompleted() async {
        let engine = MockAudioEngine()
        let outputURL = URL(fileURLWithPath: "/tmp/final-output.m4a")
        engine.stubbedOutputURL = outputURL
        let (vm, _, _) = makeSUT(audioEngine: engine)

        vm.applyFadeIn()

        let result = await vm.exportEdited()

        XCTAssertEqual(result, outputURL)
        XCTAssertEqual(vm.state, .completed(outputURL))
        XCTAssertEqual(engine.processCallCount, 1)
    }

    func testSkipReturnsOriginalURL() {
        let (vm, _, _) = makeSUT()
        let result = vm.skip()
        XCTAssertEqual(result, testURL)
    }

    func testTrimAndCutDisabledWithoutSelection() {
        let (vm, _, _) = makeSUT()
        XCTAssertNil(vm.selectionRange)
        XCTAssertFalse(vm.canTrimOrCut)
    }

    func testTrimAndCutEnabledWithSelection() {
        let (vm, _, _) = makeSUT()
        vm.selectionRange = 1.0...3.0
        XCTAssertTrue(vm.canTrimOrCut)
    }
}
