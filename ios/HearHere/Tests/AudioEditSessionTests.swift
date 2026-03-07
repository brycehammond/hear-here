import XCTest
@testable import HearHere

@MainActor
final class AudioEditSessionTests: XCTestCase {
    private let fileURL = URL(fileURLWithPath: "/tmp/test-audio.m4a")

    func testApplyAddsOperationToList() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 1.0, end: 5.0))

        XCTAssertEqual(session.operations.count, 1)
        XCTAssertEqual(session.operations.first, .trim(start: 1.0, end: 5.0))
    }

    func testApplyMultipleOperations() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 1.0, end: 8.0))
        session.apply(.fadeIn(duration: 0.5))

        XCTAssertEqual(session.operations.count, 2)
        XCTAssertEqual(session.operations[0], .trim(start: 1.0, end: 8.0))
        XCTAssertEqual(session.operations[1], .fadeIn(duration: 0.5))
    }

    func testUndoRemovesLastOperationAndEnablesRedo() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 1.0, end: 5.0))
        session.apply(.fadeIn(duration: 0.5))

        session.undo()

        XCTAssertEqual(session.operations.count, 1)
        XCTAssertEqual(session.operations.first, .trim(start: 1.0, end: 5.0))
        XCTAssertTrue(session.canRedo)
    }

    func testRedoRestoresUndoneOperation() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 1.0, end: 5.0))
        session.apply(.fadeIn(duration: 0.5))

        session.undo()
        session.redo()

        XCTAssertEqual(session.operations.count, 2)
        XCTAssertEqual(session.operations[1], .fadeIn(duration: 0.5))
        XCTAssertFalse(session.canRedo)
    }

    func testCanUndoIsFalseWhenNoOperations() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        XCTAssertFalse(session.canUndo)
    }

    func testCanUndoIsTrueAfterApply() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.fadeOut(duration: 1.0))
        XCTAssertTrue(session.canUndo)
    }

    func testCanRedoIsFalseInitially() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        XCTAssertFalse(session.canRedo)
    }

    func testCanRedoIsFalseAfterNewApply() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.fadeIn(duration: 0.5))
        session.undo()
        XCTAssertTrue(session.canRedo)

        session.apply(.fadeOut(duration: 1.0))
        XCTAssertFalse(session.canRedo)
    }

    func testResetClearsAllOperations() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 0.0, end: 5.0))
        session.apply(.fadeIn(duration: 0.3))

        session.reset()

        XCTAssertTrue(session.operations.isEmpty)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    func testUndoAfterResetDoesNothing() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 0.0, end: 5.0))
        session.reset()
        session.undo()

        XCTAssertTrue(session.operations.isEmpty)
        XCTAssertFalse(session.canUndo)
    }

    func testEffectiveDurationWithTrim() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 2.0, end: 7.0))

        XCTAssertEqual(session.effectiveDuration, 5.0)
    }

    func testEffectiveDurationWithCut() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.cut(start: 3.0, end: 6.0))

        XCTAssertEqual(session.effectiveDuration, 7.0)
    }

    func testEffectiveDurationWithNonDurationOperations() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.fadeIn(duration: 0.5))
        session.apply(.fadeOut(duration: 0.5))
        session.apply(.normalize(targetPeakDb: -1.0))

        XCTAssertEqual(session.effectiveDuration, 10.0)
    }

    func testEffectiveDurationWithMultipleOperations() {
        let session = AudioEditSession(fileURL: fileURL, originalDuration: 10.0)
        session.apply(.trim(start: 1.0, end: 9.0)) // 8s
        session.apply(.cut(start: 2.0, end: 4.0))   // remove 2s -> 6s

        XCTAssertEqual(session.effectiveDuration, 6.0)
    }
}
