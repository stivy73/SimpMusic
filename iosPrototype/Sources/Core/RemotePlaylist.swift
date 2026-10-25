import Combine
import Foundation
import YouTubeSDK

public enum PlaylistAction: Sendable, Equatable {
  case rename(String)
  case add(String)
  case remove(videoID: String, setID: String)
  case move(setID: String, before: String?)
  var fields: [String: Any] {
    switch self {
    case .rename(let title): ["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title]
    case .add(let id): ["action": "ACTION_ADD_VIDEO", "addedVideoId": id]
    case .remove(let video, let set):
      ["action": "ACTION_REMOVE_VIDEO", "removedVideoId": video, "setVideoId": set]
    case .move(let set, let before):
      [
        "action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": set,
        "movedSetVideoIdSuccessor": before as Any? ?? NSNull(),
      ]
    }
  }
}

public struct RemotePlaylistEntry: Identifiable, Sendable, Equatable {
  public let id: String
  public let item: DiscoveryItem
  public let setVideoID: String?
}

public struct RemotePlaylist: Sendable {
  public let editable: Bool
  public let entries: [RemotePlaylistEntry]

  public static func completed(fetch: @Sendable (String?) async throws -> Data) async throws -> Self
  {
    let parser = YouTubeMusicClient()
    var entries: [RemotePlaylistEntry] = []
    var seenIDs = Set<String>()
    var seenTokens = Set<String>()
    var token: String?
    var editable = false
    repeat {
      try Task.checkCancellation()
      let data = try await fetch(token)
      let page = try await parser.decodeEditablePlaylistPage(from: data)
      if token == nil { editable = page.editable }
      for entry in page.entries {
        let id = entry.setVideoID ?? "uneditable-\(entries.count)-\(entry.song.videoId)"
        if seenIDs.insert(id).inserted {
          entries.append(
            .init(id: id, item: DiscoveryItem(.song(entry.song)), setVideoID: entry.setVideoID))
        }
      }
      token = page.continuation
      if let token, !seenTokens.insert(token).inserted { throw LibraryError.repeatedContinuation }
    } while token != nil
    return Self(editable: editable, entries: entries)
  }

  public static func moveAction(entries: [RemotePlaylistEntry], from: Int, to: Int) throws
    -> PlaylistAction
  {
    guard entries.indices.contains(from), (0...entries.count).contains(to),
      let set = entries[from].setVideoID
    else { throw LibraryError.malformed }
    var reordered = entries
    let entry = reordered.remove(at: from)
    let destination = to > from ? to - 1 : to
    reordered.insert(entry, at: destination)
    let next = destination + 1 < reordered.count ? reordered[destination + 1] : nil
    if let next, next.setVideoID == nil { throw LibraryError.malformed }
    return .move(setID: set, before: next?.setVideoID)
  }
}

@MainActor
public final class RemotePlaylistModel: ObservableObject {
  @Published public private(set) var detail: RemotePlaylist?
  @Published public private(set) var loading = false
  @Published public private(set) var saving = false
  @Published public var error: String?
  private var session: YouTubeSession?
  private var revision = UUID()
  private let id: String
  public typealias Fetch = @Sendable (YouTubeSession, String) async throws -> RemotePlaylist
  public typealias Edit = @Sendable (YouTubeSession, String, PlaylistAction) async throws -> Void
  private let fetch: Fetch
  private let edit: Edit

  public init(
    id: String,
    fetch: @escaping Fetch = { session, id in
      try await YouTubeBrowse(session: session).playlist(id: id)
    },
    edit: @escaping Edit = { session, id, action in
      try await YouTubeBrowse(session: session).editPlaylist(id: id, action: action)
    }
  ) {
    self.id = id
    self.fetch = fetch
    self.edit = edit
  }

  public func configure(session: YouTubeSession?) async {
    if self.session != session {
      revision = UUID()
      self.session = session
      detail = nil
      loading = false
      saving = false
    }
    await reload()
  }

  public func reload() async {
    guard let session, !saving else { return }
    let token = UUID()
    revision = token
    loading = true
    error = nil
    do {
      let detail = try await fetch(session, id)
      guard revision == token else { return }
      self.detail = detail
    } catch {
      guard revision == token else { return }
      self.error = "Impossibile aggiornare la playlist. Riprova."
    }
    guard revision == token else { return }
    loading = false
  }

  @discardableResult
  public func apply(_ action: PlaylistAction) async -> Bool {
    guard let session, detail?.editable == true, !loading, !saving else { return false }
    let token = revision
    saving = true
    error = nil
    do {
      try await edit(session, id, action)
      guard revision == token else { return false }
      saving = false
      await reload()
      return true
    } catch {
      guard revision == token else { return false }
      saving = false
      self.error =
        "Modifica non confermata da YouTube Music. La playlist non è stata aggiornata nell’app. Riprova."
      return false
    }
  }
}
