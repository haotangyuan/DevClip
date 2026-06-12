import Foundation

public enum DiffLineKind: String, Codable, Equatable, Sendable {
    case unchanged
    case added
    case removed
}

public struct DiffLine: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: DiffLineKind
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var text: String

    public init(
        id: UUID = UUID(),
        kind: DiffLineKind,
        oldLineNumber: Int? = nil,
        newLineNumber: Int? = nil,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
    }
}

public struct DiffResult: Equatable, Sendable {
    public var lines: [DiffLine]
    public var addedCount: Int
    public var removedCount: Int

    public init(lines: [DiffLine]) {
        self.lines = lines
        self.addedCount = lines.filter { $0.kind == .added }.count
        self.removedCount = lines.filter { $0.kind == .removed }.count
    }
}

public protocol DiffService: Sendable {
    func diff(oldText: String, newText: String) async throws -> DiffResult
}

public struct LineDiffService: DiffService {
    public init() {}

    public func diff(oldText: String, newText: String) async throws -> DiffResult {
        let oldLines = oldText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let table = lcsTable(oldLines: oldLines, newLines: newLines)
        var lines: [DiffLine] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count,
               newIndex < newLines.count,
               oldLines[oldIndex] == newLines[newIndex]
            {
                lines.append(
                    DiffLine(
                        kind: .unchanged,
                        oldLineNumber: oldIndex + 1,
                        newLineNumber: newIndex + 1,
                        text: oldLines[oldIndex]
                    )
                )
                oldIndex += 1
                newIndex += 1
            } else if newIndex < newLines.count,
                      (oldIndex == oldLines.count || table[oldIndex][newIndex + 1] >= table[oldIndex + 1][newIndex])
            {
                lines.append(
                    DiffLine(
                        kind: .added,
                        newLineNumber: newIndex + 1,
                        text: newLines[newIndex]
                    )
                )
                newIndex += 1
            } else if oldIndex < oldLines.count {
                lines.append(
                    DiffLine(
                        kind: .removed,
                        oldLineNumber: oldIndex + 1,
                        text: oldLines[oldIndex]
                    )
                )
                oldIndex += 1
            }
        }

        return DiffResult(lines: lines)
    }

    private func lcsTable(oldLines: [String], newLines: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: newLines.count + 1),
            count: oldLines.count + 1
        )

        guard !oldLines.isEmpty, !newLines.isEmpty else {
            return table
        }

        for oldIndex in stride(from: oldLines.count - 1, through: 0, by: -1) {
            for newIndex in stride(from: newLines.count - 1, through: 0, by: -1) {
                if oldLines[oldIndex] == newLines[newIndex] {
                    table[oldIndex][newIndex] = table[oldIndex + 1][newIndex + 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(
                        table[oldIndex + 1][newIndex],
                        table[oldIndex][newIndex + 1]
                    )
                }
            }
        }

        return table
    }
}
