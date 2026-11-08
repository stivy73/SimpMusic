import Foundation
import XCTest

@testable import PrototypeCore

private final class SessionLifetime: NSObject, URLSessionDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var ended = false
  var invalidated: Bool { lock.withLock { ended } }
  func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    lock.withLock { ended = true }
  }
}

final class AudioRangeLifecycleTests: XCTestCase {
  func testCloseDrainsFetchBeforeSessionInvalidation() async throws {
    actor Gate {
      var entered = false
      var release: CheckedContinuation<Void, Never>?
      func wait() async {
        entered = true
        await withCheckedContinuation { release = $0 }
      }
      func finish() {
        release?.resume()
        release = nil
      }
    }
    actor Completion {
      var closed = false
      func finish() { closed = true }
    }
    let gate = Gate()
    let completion = Completion()
    let lifetime = SessionLifetime()
    let session = URLSession(configuration: .ephemeral, delegate: lifetime, delegateQueue: nil)
    let url = URL(string: "https://fixture.googlevideo.com/audio")!
    let source = YouTubeAudio.Source(
      url: url, duration: 30, userAgent: "Test", byteCount: 131072, isHLS: false)
    let buffer = AudioRangeBuffer(
      source: source, session: session,
      fetchRange: { _ in
        // Simulate cancellation between a fetch's check and task creation.
        // Intentionally ignore cancellation until the gate is released.
        await gate.wait()
        return (
          Data(repeating: 0, count: 131072),
          HTTPURLResponse(
            url: url, statusCode: 206,
            httpVersion: nil, headerFields: ["Content-Range": "bytes 0-131071/131072"])!
        )
      })
    let read = Task { try await buffer.block(at: 0) }
    while !(await gate.entered) { await Task.yield() }
    let close = Task {
      await buffer.close()
      await completion.finish()
    }
    try await Task.sleep(for: .milliseconds(40))
    let closedTooEarly = await completion.closed
    XCTAssertFalse(closedTooEarly)
    XCTAssertFalse(lifetime.invalidated)
    do {
      _ = try await buffer.block(at: 0)
      XCTFail("Read after close allowed")
    } catch {}
    await gate.finish()
    await close.value
    do {
      _ = try await read.value
      XCTFail("Closed read succeeded")
    } catch {}
    for _ in 0..<100 where !lifetime.invalidated { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(lifetime.invalidated)
    await buffer.close()
  }
}
