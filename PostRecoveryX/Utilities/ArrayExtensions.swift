import Foundation

extension Array {
    /// Splits the array into chunks of the specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension TaskGroup {
    /// Wait for all tasks to complete
    mutating func waitForAll() async throws {
        while let _ = try await next() {
            // Continue until all tasks complete
        }
    }
}

extension ThrowingTaskGroup {
    /// Wait for all tasks to complete
    mutating func waitForAll() async throws {
        while let _ = try await next() {
            // Continue until all tasks complete
        }
    }
}