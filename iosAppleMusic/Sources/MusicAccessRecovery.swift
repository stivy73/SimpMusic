import Foundation

/// One retry, only for a developer-token failure. Never retries consent failures.
struct MusicAccessRecovery: Sendable {
  let isDeveloperTokenFailure: @Sendable (any Error) -> Bool
  let renewDeveloperToken: @Sendable () async throws -> Void
  func perform<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    do { return try await operation() }
    catch {
      guard isDeveloperTokenFailure(error) else { throw error }
      try Task.checkCancellation()
      try await renewDeveloperToken()
      try Task.checkCancellation()
      return try await operation()
    }
  }
}
