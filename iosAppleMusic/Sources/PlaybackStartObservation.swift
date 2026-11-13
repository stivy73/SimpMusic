import Foundation
/// A completed play command is not a playback acknowledgement.
enum PlaybackStartObservation {
  enum Outcome:Equatable {case playing,cancelled,unconfirmed}
  @MainActor static func wait(
    attempts:Int=30,current:()->Bool,playing:()->Bool,
    tick:() async throws -> Void = {try await Task.sleep(for:.milliseconds(100))}
  ) async throws -> Outcome {
    for _ in 0..<attempts {
      try Task.checkCancellation()
      guard current() else {return .cancelled}
      if playing() {return .playing}
      try await tick()
    }
    return current() ? .unconfirmed:.cancelled
  }
}
