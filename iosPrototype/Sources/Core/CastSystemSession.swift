import Foundation

public enum CastSystemSessionError: Error { case differentAttributes }

@MainActor
public protocol CastSystemSessionHandle: AnyObject {
  var id: String { get }
  var isPrimary: Bool { get }
  func update(_ state: CastRemoteState) async throws
  func promote() async throws
  func end() async throws
}

@MainActor
public protocol CastSystemSessionDriver {
  func sessions() async throws -> [any CastSystemSessionHandle]
  func start(_ state: CastRemoteState) async throws -> any CastSystemSessionHandle
}

/// Serial callers can recover an existing OS session after an app update.
/// Registration alone must never suppress the working local Now Playing card.
@MainActor
public final class CastSystemSessionController {
  private let driver: any CastSystemSessionDriver
  private let beginHandoff: () -> Void
  private let finishHandoff: (Bool) -> Void
  private var session: (any CastSystemSessionHandle)?
  private var attributesID: String?
  private var nextPromotion = -Double.infinity
  public private(set) var registered = false
  public private(set) var promoting = false
  public private(set) var lastError: Error?
  public var isPrimary: Bool { registered && session?.isPrimary == true }
  public var suppressesLegacy: Bool { isPrimary || promoting }
  public var sessionID: String? { registered ? session?.id : nil }

  public init(driver: any CastSystemSessionDriver,
    beginHandoff: @escaping () -> Void = {}, finishHandoff: @escaping (Bool) -> Void = { _ in }) {
    self.driver = driver; self.beginHandoff = beginHandoff; self.finishHandoff = finishHandoff
  }

  public func publish(_ state: CastRemoteState, foreground: Bool, forcePromotion: Bool = false,
    now: TimeInterval) async throws {
    if let session, attributesID != state.id {
      try? await session.end()
      self.session = nil; registered = false
    }
    let newlyAttached = session == nil
    do {
      if let session {
        try await session.update(state)
      } else {
        // update validates Attributes.id in the OS. A foreign session rejects
        // it without mutation, even when the framework's handle ID is opaque.
        for candidate in (try? await driver.sessions()) ?? [] {
          do {
            try await candidate.update(state)
            session = candidate
            break
          } catch CastSystemSessionError.differentAttributes { continue }
          catch { continue }
        }
        if session == nil { session = try await driver.start(state) }
      }
      attributesID = state.id; registered = true
    } catch {
      let failedSession = session
      session = nil; attributesID = nil; registered = false; lastError = error
      try? await failedSession?.end()
      throw error
    }
    guard foreground, forcePromotion || newlyAttached || (!isPrimary && now >= nextPromotion) else { return }
    nextPromotion = now + 2
    promoting = true
    beginHandoff()
    defer { finishHandoff(isPrimary); promoting = false }
    do {
      try await session?.promote()
      lastError = nil
    } catch { lastError = error }
  }

  public func end() async {
    if let session { try? await session.end() }
    session = nil; attributesID = nil; registered = false; promoting = false
    nextPromotion = -.infinity; lastError = nil
  }
}
