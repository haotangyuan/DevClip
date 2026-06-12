import Foundation

/// Actor boundary for stateless transform actions.
public actor TransformEngine {
    private let actionsByID: [String: any TransformAction]

    public init(actions: [any TransformAction]? = nil) {
        let registeredActions = actions ?? BuiltInTransformActions.all
        self.actionsByID = Dictionary(uniqueKeysWithValues: registeredActions.map { ($0.id, $0) })
    }

    public func smartActions(for input: TransformInput) async throws -> [TransformDefinition] {
        actionsByID.values
            .filter { $0.canHandle(input) }
            .sorted {
                if $0.category == $1.category {
                    return $0.displayName < $1.displayName
                }

                return $0.category.rawValue < $1.category.rawValue
            }
            .map { action in
                TransformDefinition(
                    id: action.id,
                    displayName: action.displayName,
                    category: action.category,
                    acceptedInputKinds: action.acceptedInputKinds,
                    outputKind: action.outputKind,
                    isDestructive: action.isDestructive
                )
            }
    }

    public func execute(
        actionID: String,
        input: TransformInput,
        options: TransformOptions = TransformOptions()
    ) async throws -> TransformResult {
        guard let action = actionsByID[actionID] else {
            throw DevClipError.invalidInput(reason: "未知转换动作：\(actionID)。")
        }

        guard action.canHandle(input) else {
            throw DevClipError.invalidInput(reason: "当前内容类型不支持此转换。")
        }

        return try await withTimeout(seconds: options.timeoutSeconds) {
            try Task.checkCancellation()
            return try await action.execute(input, options: options)
        }
    }

    public func execute(
        pipeline: TransformPipeline,
        input: TransformInput,
        options: TransformOptions = TransformOptions()
    ) async throws -> TransformResult {
        var currentInput = input
        var lastResult: TransformResult?

        for step in pipeline.steps.sorted(by: { $0.order < $1.order }) {
            try Task.checkCancellation()
            var mergedOptions = options
            for (key, value) in step.options.values {
                mergedOptions.values[key] = value
            }

            let result = try await execute(
                actionID: step.actionID,
                input: currentInput,
                options: mergedOptions
            )
            lastResult = result
            currentInput = TransformInput(
                kind: result.outputKind,
                data: result.data,
                text: String(data: result.data, encoding: .utf8),
                metadata: result.metadata
            )
        }

        guard let lastResult else {
            throw DevClipError.invalidInput(reason: "转换流水线没有步骤。")
        }

        return lastResult
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(seconds, 0.001) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw DevClipError.timedOut(seconds: seconds)
            }

            guard let result = try await group.next() else {
                throw DevClipError.cancelled
            }

            group.cancelAll()
            return result
        }
    }
}
