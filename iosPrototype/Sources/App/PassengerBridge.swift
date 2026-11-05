#if os(iOS)
  import Combine
  import Foundation
  #if DEBUG
    import Network
  #endif

  /// The host resolves received catalog IDs with its own playback/account, exactly as local selections.
  @MainActor final class PassengerBridge: ObservableObject {
    let link = PassengerLink()
    @Published var showing = false
    @Published var incomingInvitation: String?
    private let music: MusicModel
    private var subscriptions = Set<AnyCancellable>()
    init(music: MusicModel) {
      self.music = music
      music.passengerSelection = { [weak self] songs, action in
        guard let self, self.link.isPassenger else { return false }
        self.send(songs, action: action)
        return true
      }
      link.onSelection = { [weak self] request in
        guard let self else {
          return PassengerReceipt(
            requestID: request.id, success: false, message: "Player non disponibile.")
        }
        guard request.action == .playNow || self.music.queue.count + request.tracks.count <= 5000
        else {
          return PassengerReceipt(
            requestID: request.id, success: false,
            message: "Coda piena. Rimuovi alcuni brani dal telefono principale.")
        }
        let songs = request.tracks.map {
          Song(
            id: $0.id, title: $0.title, artist: $0.artist,
            artwork: URL(string: "https://i.ytimg.com/vi/\($0.id)/hqdefault.jpg"))
        }
        self.music.applySelection(songs, action: request.action)
        self.publish()
        return PassengerReceipt(
          requestID: request.id, success: true,
          message: request.action == .playNow
            ? "Selezione inviata al player dell’auto: \(songs.count) brani."
            : "Aggiunti alla coda dell’auto: \(songs.count) brani.")
      }
      link.$mode.receive(on: RunLoop.main).sink { [weak self] mode in
        guard let self else { return }
        let passenger = mode == .connecting || mode == .awaitingApproval || mode == .connected
        if passenger != self.music.isPassenger { self.music.setPassenger(passenger) }
        if mode == .hosting { self.publish() }
      }.store(in: &subscriptions)
      link.$peers.receive(on: RunLoop.main).sink { [weak self] peers in
        if peers.contains(where: { !$0.approved }) { self?.showing = true }
      }.store(in: &subscriptions)
      music.objectWillChange.merge(with: music.player.objectWillChange)
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
    }
    func send(_ songs: [Song], action: PassengerSelection.Action) {
      link.submit(
        action: action,
        tracks: songs.map { PassengerTrack(id: $0.id, title: $0.title, artist: $0.artist) })
    }
    private func publish() {
      guard link.mode == .hosting else { return }
      link.publish(
        PassengerPlayback(
          title: music.current?.title ?? "", artist: music.current?.artist ?? "",
          playing: music.player.playing, queueCount: music.queue.count))
    }
    #if DEBUG
      /// Exercises the production bridge/queue/selection routing over actual TLS sockets, offline.
      func verifyLoopback() async -> String {
        let guest = PassengerLink()
        let remoteHost = PassengerLink()
        let originalProvider = music.player.localFileProvider
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent(
          UUID().uuidString + ".m4a")
        defer {
          link.stop()
          guest.stop()
          remoteHost.stop()
          music.player.pause()
          music.player.localFileProvider = originalProvider
          showing = false
          try? FileManager.default.removeItem(at: audio)
        }
        func wait(_ condition: () -> Bool) async -> Bool {
          let end = Date().addingTimeInterval(12)
          while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(40))
          }
          return condition()
        }
        do {
          guard await wait({ music.current != nil }) else { return "FAIL local fixture" }
          try LocalPlaybackFixture.audio(audio, seconds: 20)
          music.player.localFileProvider = { id in
            ["abcdefghijk", "lmnopqrstuv"].contains(id) ? audio : originalProvider(id)
          }
          let tracks = [
            PassengerTrack(id: "abcdefghijk", title: "Dal passeggero 1", artist: "Prova"),
            PassengerTrack(id: "lmnopqrstuv", title: "Dal passeggero 2", artist: "Prova"),
          ]
          let count = music.queue.count
          let current = music.current?.id
          link.startHosting()
          guard await wait({ link.listeningPort != nil }), let port = link.listeningPort,
            let invitation = link.invitation
          else { return "FAIL host listen" }
          guest.connect(
            invitation: invitation, endpoint: .hostPort(host: .ipv4(.loopback), port: port))
          guard await wait({ !link.peers.isEmpty }), let peer = link.peers.first else {
            return "FAIL join"
          }
          guest.submit(action: .playNow, tracks: tracks)
          guard music.queue.count == count, music.current?.id == current else {
            return "FAIL approval gate"
          }
          link.approve(peer.id)
          guard await wait({ guest.canSend }) else { return "FAIL approval" }
          guest.submit(action: .enqueue, tracks: tracks)
          guard await wait({ guest.receipt?.success == true }), music.queue.count == count + 2,
            music.current?.id == current
          else { return "FAIL atomic enqueue" }
          try await Task.sleep(for: .milliseconds(1100))
          guest.submit(action: .playNow, tracks: tracks)
          guard await wait({ guest.receipt?.success == true }),
            music.queue.map(\.id) == tracks.map(\.id),
            music.current?.id == tracks[0].id
          else { return "FAIL play now" }
          let occurrences = music.queueRows.map(\.id)
          if let receipt = guest.receipt, let connection = guest.connectionID {
            var repeated = PassengerSelection(
              sessionID: invitation.sessionID, action: .playNow, tracks: tracks)
            repeated.id = receipt.requestID
            guest.send(.selection(repeated), to: connection)
            try await Task.sleep(for: .milliseconds(200))
            guard music.queueRows.map(\.id) == occurrences else { return "FAIL duplicate" }
          }
          link.stop()
          guest.stop()
          // Turn the production phone into the passenger. Normal Play/Add must route remotely.
          var requests: [PassengerSelection] = []
          remoteHost.onSelection = { request in
            requests.append(request)
            return PassengerReceipt(requestID: request.id, success: true, message: "OK")
          }
          remoteHost.startHosting()
          guard await wait({ remoteHost.listeningPort != nil }),
            let port = remoteHost.listeningPort,
            let invitation = remoteHost.invitation
          else { return "FAIL remote listen" }
          link.connect(
            invitation: invitation, endpoint: .hostPort(host: .ipv4(.loopback), port: port))
          guard await wait({ !remoteHost.peers.isEmpty }), let peer = remoteHost.peers.first else {
            return "FAIL remote join"
          }
          remoteHost.approve(peer.id)
          guard await wait({ link.canSend && music.isPassenger }) else {
            return "FAIL passenger mode"
          }
          let songs = tracks.map {
            Song(id: $0.id, title: $0.title, artist: $0.artist, artwork: nil)
          }
          music.enqueue(contentsOf: songs)
          guard await wait({ link.receipt?.success == true }), requests.count == 1,
            requests[0].tracks.count == 2, music.queueRows.map(\.id) == occurrences,
            !music.player.wantsPlayback
          else { return "FAIL passenger enqueue/local silence" }
          try await Task.sleep(for: .milliseconds(1100))
          music.play(songs[0], queue: songs)
          guard await wait({ requests.count == 2 }), requests[1].action == .playNow,
            music.queueRows.map(\.id) == occurrences, !music.player.wantsPlayback
          else { return "FAIL passenger play routing" }
          return
            "PASS TLS approval, atomic queue, play now, idempotency, passenger routing, local silence"
        } catch { return "FAIL fixture " + error.localizedDescription }
      }
    #endif
  }
#endif
