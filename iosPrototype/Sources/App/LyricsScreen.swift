import AVFoundation
import SwiftUI

struct SleepTimerMenu: View {
  @EnvironmentObject var model: MusicModel
  var body: some View {
    Menu {
      ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
        Button("\(minutes) minuti") { model.setSleepTimer(.minutes(minutes)) }
      }
      Button("Alla fine del brano") { model.setSleepTimer(.endOfTrack) }
      if model.sleepTimer != nil { Button("Disattiva timer") { model.setSleepTimer(nil) } }
    } label: {
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        Label(
          model.sleepTimer.map { "Timer: " + $0.title } ?? "Timer di spegnimento",
          systemImage: "moon.zzz")
      }
    }.accessibilityIdentifier("sleep-timer")
  }
}
struct SyncedLyricsScreen: View {
  @EnvironmentObject var model: MusicModel
  @ObservedObject var player: PlaybackPlayer
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var direction
  @State private var followsPlayback = true
  private var text: String { model.manualLyrics.isEmpty ? model.lyrics : model.manualLyrics }

  var body: some View {
    // Only the visible lyrics refresh at display cadence. Reading AVPlayer's media clock
    // also stops the animation during buffering, narration and pauses, and follows seeks.
    TimelineView(
      .animation(minimumInterval: 1.0 / 30, paused: !player.playing || model.timeline.lines.isEmpty)
    ) { _ in
      let mediaTime = player.currentTime().seconds
      let position = mediaTime.isFinite ? mediaTime : player.elapsed
      let active = model.timeline.current(at: position, delay: model.lyricsDelay)
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            NavigationLink("Strumenti testo", destination: LyricsTools()).accessibilityIdentifier(
              "lyrics-tools")
            if model.loadingLyrics && text.isEmpty { ProgressView(model.lyricsProgress) }
            if !model.timeline.lines.isEmpty {
              HStack {
                Text(
                  model.timeline.hasWords
                    ? "Sincronizzato parola per parola" : "Testo sincronizzato")
                Spacer()
                Button("−0,5 s") { model.lyricsDelay -= 0.5 }
                Text(model.lyricsDelay, format: .number.precision(.fractionLength(1)))
                Button("+0,5 s") { model.lyricsDelay += 0.5 }
              }.font(.caption)
              if let source = model.timelineSource {
                Text("Tempi: " + source.rawValue).font(.caption).foregroundStyle(.secondary)
              }
              ForEach(model.timeline.lines) { line in
                Button {
                  followsPlayback = true
                  player.seek(
                    to: CMTime(
                      seconds: max(0, line.time + model.lyricsDelay), preferredTimescale: 600))
                } label: {
                  lineText(line, active: active, position: position)
                    .font(.title2.bold()).lineSpacing(10)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).id(line.id)
                  .accessibilityLabel(line.text.isEmpty ? "Pausa musicale" : line.text)
                  .accessibilityValue(active?.id == line.id ? "Riga in riproduzione" : "")
                  .accessibilityHint("Riproduce la canzone da questa riga")
                  .accessibilityIdentifier("lyric-line-\(line.id)")
              }
            } else if !text.isEmpty {
              Text(text).font(.title2.bold()).lineSpacing(12).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(
                  "song-lyrics")
              Text("Testo non sincronizzato. Puoi incollare un testo LRC dal menu del player.")
                .font(.caption).foregroundStyle(.secondary)
            } else if let error = model.lyricsError {
              Text(error).foregroundStyle(.secondary)
              Button("Riprova") {
                model.loadLyrics(force: true)
                model.loadTimedLyrics()
              }
            }
            if let source = model.lyricsSource, model.manualLyrics.isEmpty {
              if let url = model.lyricsSourceURL {
                Link("Testo: \(source.rawValue)", destination: url)
              } else {
                Text("Testo: \(source.rawValue)")
              }
            }
            if !text.isEmpty {
              HStack {
                Button("Copia testo", systemImage: "doc.on.doc") { PlatformClipboard.copy(text) }
                Spacer()
                ShareLink(item: text) {
                  Label("Condividi testo", systemImage: "square.and.arrow.up")
                }
              }.labelStyle(.iconOnly)
            }
          }.padding(18).padding(.bottom, 52)
        }.accessibilityIdentifier("synchronized-lyrics-scroll")
          .modifier(
            LyricsScrollInteraction {
              if !model.timeline.lines.isEmpty { followsPlayback = false }
            }
          )
          .overlay(alignment: .bottom) {
            if !followsPlayback && !model.timeline.lines.isEmpty {
              Button {
                followsPlayback = true
                follow(active?.id, proxy: proxy)
              } label: {
                Label("Segui il testo", systemImage: "arrow.down.to.line")
                  .font(.callout.bold()).padding(.horizontal, 18).padding(.vertical, 12)
              }.buttonStyle(.plain).background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8).accessibilityIdentifier("lyrics-resume-follow")
            }
          }
          .onChange(of: active?.id, initial: true) { _, id in
            if followsPlayback { follow(id, proxy: proxy) }
          }
          .onChange(of: model.current?.id) { _, _ in followsPlayback = true }
      }
    }.task(id: model.current?.id) {
      model.loadLyrics()
      model.loadTimedLyrics()
    }
  }

  private func follow(_ id: Int?, proxy: ScrollViewProxy) {
    guard let id else { return }
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
      proxy.scrollTo(id, anchor: .center)
    }
  }

  @ViewBuilder
  private func lineText(_ line: LyricLine, active: LyricLine?, position: Double) -> some View {
    if !line.words.isEmpty,
      line.words.map(\.text).joined().trimmingCharacters(in: .whitespaces) == line.text
    {
      // Keep the same layout for active and inactive lines, so wrapping cannot move the
      // scroll target when the sung line changes. Untimed fragments are never fabricated.
      LyricWordFlow(direction: direction) {
        ForEach(line.words.filter { !$0.text.isEmpty }) { word in
          let progress = model.timeline.progress(
            of: word, in: line, at: position, delay: model.lyricsDelay)
          KaraokeWord(
            text: word.text, progress: progress, active: active?.id == line.id,
            reduceMotion: reduceMotion)
        }
      }
    } else {
      Text(line.text.isEmpty ? "♪" : line.text)
        .foregroundStyle(active?.id == line.id ? Color.cyan : Color.primary.opacity(0.55))
    }
  }
}

private struct KaraokeWord: View {
  let text: String
  let progress: Double
  let active: Bool
  let reduceMotion: Bool
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    Text(text).foregroundStyle(Color.primary.opacity(active ? 0.4 : 0.55))
      .overlay(alignment: .leading) {
        if active {
          Text(text).foregroundStyle(.cyan)
            .mask {
              GeometryReader { geometry in
                let fill = reduceMotion && progress > 0 ? 1 : progress
                Path { path in
                  path.addRect(
                    CGRect(
                      x: direction == .rightToLeft ? geometry.size.width * (1 - fill) : 0,
                      y: 0, width: geometry.size.width * fill, height: geometry.size.height))
                }.fill(.white)
              }
            }
        }
      }.accessibilityHidden(true)
  }
}

/// Words wrap as one lyric line while retaining the provider's spaces and punctuation.
private struct LyricWordFlow: Layout {
  var direction: LayoutDirection
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = positions(subviews, width: proposal.width ?? .infinity)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = positions(subviews, width: bounds.width)
    for (index, position) in result.origins.enumerated() {
      subviews[index].place(
        at: CGPoint(
          x: direction == .rightToLeft
            ? bounds.maxX - position.x - result.sizes[index].width : bounds.minX + position.x,
          y: bounds.minY + position.y),
        proposal: ProposedViewSize(
          width: result.sizes[index].width, height: result.sizes[index].height))
    }
  }

  private func positions(_ subviews: Subviews, width: CGFloat) -> (
    size: CGSize, origins: [CGPoint], sizes: [CGSize]
  ) {
    let limit = max(1, width)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var usedWidth: CGFloat = 0
    var origins: [CGPoint] = []
    var sizes: [CGSize] = []
    for view in subviews {
      let size = view.sizeThatFits(
        ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil))
      if x > 0 && x + size.width > limit {
        usedWidth = max(usedWidth, x)
        x = 0
        y += rowHeight + 8
        rowHeight = 0
      }
      origins.append(CGPoint(x: x, y: y))
      sizes.append(size)
      x += size.width
      rowHeight = max(rowHeight, size.height)
    }
    return (CGSize(width: max(usedWidth, x), height: y + rowHeight), origins, sizes)
  }
}

private struct LyricsScrollInteraction: ViewModifier {
  let onManualScroll: () -> Void
  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 18.0, macOS 15.0, *) {
      content.onScrollPhaseChange { _, phase in
        if phase == .interacting { onManualScroll() }
      }
    } else {
      content.simultaneousGesture(
        DragGesture(minimumDistance: 8).onChanged { _ in onManualScroll() })
    }
  }
}
