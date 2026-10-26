import SwiftUI

struct AlbumView: View {
  let album: LibraryAlbum
  let identity: String?
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var detail: AlbumDetail?
  @State private var loading = true
  @State private var error: String?
  @State private var retry = 0
  @State private var optionsSong: Song?
  private var shown: LibraryAlbum { detail?.album ?? album }
  private var songs: [Song] { detail?.songs ?? [] }
  private var liked: Bool { model.favoriteAlbums.contains { $0.id == album.id } }
  private var playingAlbum: Bool {
    model.current?.albumBrowseID == album.id && model.player.playing
  }

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width >= 700 && !typeSize.isAccessibilitySize
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if wide {
            HStack(alignment: .center, spacing: 28) {
              Artwork(url: shown.artwork, fit: true)
                .frame(
                  width: min(geometry.size.width * 0.4, 380),
                  height: min(geometry.size.width * 0.4, 380)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
              VStack(alignment: .leading, spacing: 24) {
                identityHeader
                albumControls
              }
            }.padding(.horizontal, 24).padding(.top, 12)
          } else {
            ZStack(alignment: .bottom) {
              Artwork(url: shown.artwork).frame(height: min(geometry.size.width * 1.08, 520))
              LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
              identityHeader.padding(24)
            }
            albumControls.padding(.horizontal, 24)
          }
          if loading {
            ProgressView("Carico l’album…").frame(maxWidth: .infinity).padding()
          } else if let error {
            ContentUnavailableView {
              Label("Album non disponibile", systemImage: "exclamationmark.triangle")
            } description: {
              Text(error)
            } actions: {
              Button("Riprova") { retry += 1 }
            }
          } else {
            Text(detail?.description.isEmpty == false ? detail!.description : "Nessuna descrizione")
              .foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 24)
              .accessibilityIdentifier("album-description")
            Text(summary).font(.subheadline).padding(.horizontal, 24)
              .accessibilityIdentifier("album-track-summary")
            LazyVStack(spacing: 0) {
              ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                HStack(spacing: 12) {
                  Button {
                    model.play(song, queue: songs, selectedIndex: index)
                  } label: {
                    HStack(spacing: 18) {
                      Group {
                        if model.current?.id == song.id {
                          Image(systemName: "waveform").foregroundStyle(.cyan)
                        } else {
                          Text("\(index + 1)").foregroundStyle(.secondary)
                        }
                      }.font(.headline).frame(width: 30)
                      VStack(alignment: .leading, spacing: 5) {
                        Text(song.title).font(.headline).foregroundStyle(.primary)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                      }.frame(maxWidth: .infinity, alignment: .leading)
                      if let duration = song.durationSeconds {
                        Text(Self.time(duration)).font(.caption).monospacedDigit().foregroundStyle(
                          .secondary)
                      }
                    }.padding(.vertical, 18).contentShape(Rectangle())
                  }.buttonStyle(.plain).accessibilityIdentifier("album-track-\(index)")
                  Button {
                    optionsSong = song
                  } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(
                      width: 44, height: 48)
                  }.buttonStyle(.plain).accessibilityLabel("Opzioni di \(song.title)")
                    .accessibilityIdentifier("album-track-options-\(index)")
                }.padding(.horizontal, 20)
                Divider().padding(.leading, 68)
              }
            }
          }
        }.padding(.bottom, 32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
      }.background(.black).accessibilityIdentifier("album-scroll")
    }.navigationTitle(shown.title).inlineNavigationTitle()
      .toolbar {
        ToolbarItem(placement: .platformTrailing) {
          Button {
            model.toggleFavoriteAlbum(shown)
          } label: {
            Image(systemName: liked ? "heart.fill" : "heart").foregroundStyle(
              liked ? .red : .primary)
          }.accessibilityLabel(liked ? "Rimuovi album dai preferiti" : "Salva album nei preferiti")
            .accessibilityIdentifier("album-favorite").accessibilityValue(
              liked ? "Attivo" : "Non attivo")
        }
        ToolbarItem(placement: .platformTrailing) {
          Menu {
            Button {
              for song in songs { model.enqueue(song) }
            } label: {
              Label("Aggiungi album alla coda", systemImage: "text.append")
            }
            .disabled(songs.isEmpty).accessibilityIdentifier("album-add-queue")
            ShareLink(item: URL(string: "https://music.youtube.com/browse/\(album.id)")!) {
              Label("Condividi album", systemImage: "square.and.arrow.up")
            }
            Button {
              retry += 1
            } label: {
              Label("Aggiorna", systemImage: "arrow.clockwise")
            }
          } label: {
            Label("Opzioni album", systemImage: "ellipsis")
          }
          .accessibilityIdentifier("album-options")
        }
      }
      .task(id: "\(album.id):\(identity ?? ""):\(retry)") { await load() }
      .onChange(of: library.session?.identity) { _, new in if new != identity { dismiss() } }
      .sheet(item: $optionsSong) { song in
        SongOptionsSheet(song: song, onClose: { optionsSong = nil })
      }
  }

  private var identityHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(shown.title).font(.largeTitle.bold()).accessibilityIdentifier("album-title")
      Text(shown.artist).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
      Text([detail?.year, "Album"].compactMap { $0 }.joined(separator: " · "))
        .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("album-year")
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var albumControls: some View {
    HStack(spacing: 18) {
      Button {
        guard let index = songs.indices.randomElement() else { return }
        model.setShuffle(true)
        model.play(songs[index], queue: songs, selectedIndex: index)
      } label: {
        Image(systemName: "shuffle").font(.title2).frame(width: 58, height: 58)
      }
      .background(.white.opacity(0.12), in: Circle()).accessibilityLabel(
        "Riproduzione casuale dell’album"
      )
      .accessibilityIdentifier("album-shuffle").disabled(songs.isEmpty)
      Button {
        if playingAlbum {
          model.player.pause()
        } else if model.current?.albumBrowseID == album.id {
          model.player.play()
          model.showPlayer = true
        } else if let first = songs.first {
          model.setShuffle(false)
          model.play(first, queue: songs)
        }
      } label: {
        Label(
          playingAlbum ? "Pausa" : "Play", systemImage: playingAlbum ? "pause.fill" : "play.fill"
        )
        .font(.title3.bold()).frame(maxWidth: .infinity).frame(height: 60)
      }.buttonStyle(.plain).foregroundStyle(.black).background(.white, in: Capsule())
        .disabled(songs.isEmpty).accessibilityIdentifier("album-play")
      AlbumDownloadControl(songs: songs, downloads: model.downloads)
    }.tint(.white)
  }
  private var summary: String {
    var text = "\(songs.count) tracce"
    if let seconds = detail?.durationSeconds { text += ", \(Int((seconds / 60).rounded())) minuti" }
    return text
  }
  private static func time(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):" + String(format: "%02d", total % 60)
  }
  private func load() async {
    loading = true
    error = nil
    let account = library.session
    do {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-album-player") {
          let songs = (1...3).map { index in
            Song(
              id: "local-\(index)-30", title: "Brano locale \(index)", artist: "Prova offline",
              artwork: nil, durationSeconds: 30, artistBrowseID: "UCfixture")
          }
          detail = AlbumDetail(
            album: album, year: "1988", description: "Storie e viaggi nell’album di prova.",
            songs: songs)
          loading = false
          return
        }
      #endif
      let result = try await AlbumDetail.load(album: album, session: account)
      try Task.checkCancellation()
      guard library.session == account else { return }
      detail = result
      loading = false
    } catch is CancellationError {} catch {
      self.error = "Impossibile caricare tutte le tracce. Riprova."
      loading = false
    }
  }
}

private struct AlbumDownloadControl: View {
  let songs: [Song]
  @ObservedObject var downloads: MusicDownloads
  @EnvironmentObject private var model: MusicModel
  private var records: [OfflineRecord] {
    downloads.library.records.filter { record in songs.contains { $0.id == record.id } }
  }
  private var complete: Bool {
    !songs.isEmpty && songs.allSatisfy { downloads.library.url(for: $0.id) != nil }
  }
  private var pending: Bool {
    records.contains { [.preparing, .downloading, .verifying].contains($0.state) }
  }
  var body: some View {
    Button {
      for song in songs { model.download(song) }
    } label: {
      Group {
        if pending {
          ProgressView()
        } else {
          Image(systemName: complete ? "checkmark.circle.fill" : "arrow.down.circle.fill").font(
            .title2)
        }
      }.frame(width: 58, height: 58)
    }.buttonStyle(.plain).background(.white.opacity(0.12), in: Circle())
      .disabled(songs.isEmpty || complete || pending)
      .accessibilityLabel(
        complete
          ? "Album disponibile offline" : pending ? "Download album in corso" : "Scarica album"
      )
      .accessibilityIdentifier("album-download")
      .accessibilityValue("\(records.filter { $0.state == .ready }.count) di \(songs.count)")
  }
}
