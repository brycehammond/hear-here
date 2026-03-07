import Foundation
import Observation

@Observable
@MainActor
final class AudioEditSession {
    let fileURL: URL
    let originalDuration: TimeInterval

    private(set) var operations: [EditOperation] = []

    private var undoStack: [[EditOperation]] = []
    private var redoStack: [[EditOperation]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var effectiveDuration: TimeInterval {
        var duration = originalDuration
        for operation in operations {
            switch operation {
            case .trim(let start, let end):
                duration = end - start
            case .cut(let start, let end):
                duration -= (end - start)
            case .fadeIn, .fadeOut, .normalize:
                break
            }
        }
        return max(0, duration)
    }

    init(fileURL: URL, originalDuration: TimeInterval) {
        self.fileURL = fileURL
        self.originalDuration = originalDuration
    }

    func apply(_ operation: EditOperation) {
        undoStack.append(operations)
        redoStack.removeAll()
        operations.append(operation)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(operations)
        operations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(operations)
        operations = next
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        operations.removeAll()
    }
}
