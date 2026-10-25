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
  private var text: String { model.manualLyrics.isEmpty ? model.lyrics : model.manualLyrics }
  private var active: LyricLine? {
    model.timeline.current(at: player.elapsed, delay: model.lyricsDelay)
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          NavigationLink("Strumenti testo", destination: LyricsTools()).accessibilityIdentifier(
            "lyrics-tools")
          if model.loadingLyrics && text.isEmpty { ProgressView(model.lyricsProgress) }
          if !model.timeline.lines.isEmpty {
            HStack {
              Text(
                model.timeline.hasWords ? "Sincronizzato parola per parola" : "Testo sincronizzato")
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
                player.seek(
                  to: CMTime(
                    seconds: max(0, line.time + model.lyricsDelay), preferredTimescale: 600))
              } label: {
                lineText(line).font(.title2.bold()).lineSpacing(10)
                  .foregroundStyle(line.id == active?.id ? Color.cyan : Color.primary.opacity(0.55))
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
              }.buttonStyle(.plain).id(line.id).accessibilityIdentifier("lyric-line-\(line.id)")
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
              ShareLink(item: text) { Label("Condividi testo", systemImage: "square.and.arrow.up") }
            }.labelStyle(.iconOnly)
          }
        }.padding(18)
      }.onChange(of: active?.id) { _, id in
        if let id {
          withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }.task(id: model.current?.id) {
      model.loadLyrics()
      model.loadTimedLyrics()
    }
  }
  private func lineText(_ line: LyricLine) -> Text {
    guard active?.id == line.id, !line.words.isEmpty else {
      return Text(line.text.isEmpty ? "♪" : line.text)
    }
    let word = model.timeline.activeWord(in: line, at: player.elapsed, delay: model.lyricsDelay)
    return line.words.reduce(Text("")) { result, token in
      result + Text(token.text).foregroundColor(token.id == word ? .white : .cyan.opacity(0.6))
    }
  }
}
