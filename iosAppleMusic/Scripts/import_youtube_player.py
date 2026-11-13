"""Pin and port the real YouTube player presentation. Does not import its engine."""
from pathlib import Path
import subprocess, hashlib, re, sys
root=Path(__file__).resolve().parents[2]
revision='5a277798'
path='iosPrototype/Sources/App/StivyApp.swift'
source=subprocess.check_output(['git','show',f'{revision}:{path}'],cwd=root).decode()
def between(a,b):return source[source.index(a):source.index(b)]
art=between('struct Artwork: View {','struct RootView: View {')
# Keep the original placeholder and sizing, but observe real image success/failure.
art='''struct Artwork: View {
  let url: URL?
  var fit = false
  var onLoaded: ((URL) -> Void)?
  var onFailure: ((URL, Error) async -> Void)?
  @State private var image: UIImage?
  @State private var renderedURL: URL?
  private var placeholder: some View {
    ZStack {
      LinearGradient(colors: [.cyan.opacity(0.5), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white)
    }
  }
  var body: some View {
    Group {
      if renderedURL == url, let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
      } else { placeholder }
    }.clipped().task(id: url) {
      guard let url else { return }
      do {
        let data = try await ArtworkImageData.shared.load(url)
        try Task.checkCancellation()
        guard let decoded = UIImage(data: data) else { throw ArtworkImageData.Failure(code: -4) }
        renderedURL = url; image = decoded; onLoaded?(url)
      } catch {
        guard !Task.isCancelled else { return }
        await onFailure?(url, error)
      }
    }
  }
}

'''
mini=between('private struct DuoNavigationBars: ViewModifier {','struct SongList: View {')
player=between('struct PlayerScreen: View {','struct LyricsContent: View {')
controls=between('struct PlayerControls: View {','struct MeaningView: View {')
# Keep layout, geometry, bars, scrubbing and actions. Replace service-specific panes.
player=player.replace('  @State private var editLyrics = false\n','').replace('  @State private var pendingOption: PlayerOption?\n','')
a=player.index('      .sheet(\n        item: $optionsSong,')
b=player.index('      .sheet(isPresented: $showQueue)',a)
player=player[:a]+'''      .sheet(item: $optionsSong) { song in
        ApplePlayerOptions(song: song, onClose: { optionsSong = nil })
      }
'''+player[b:]
a=player.index('      .sheet(isPresented: $editLyrics)')
b=player.index('\n    }\n  }\n\n  private func playerContent',a)
player=player[:a]+player[b:]
# Google Search interpretation replaces unlicensed lyrics; geometry stays intact.
a=player.index('                if showLyrics && !expanded {\n                  HStack {')
b=player.index('\n              }.frame(width: column)',a)
player=player[:a]+player[b:]
player=player.replace('"Testo della canzone"','"Significato"').replace('navigationTitle("Testo")','navigationTitle("Significato")')
# ArrangementView can collapse its secondary pane on a landscape iPhone.
# Keep the original control and use its existing full-pane sheet in that layout.
inline_action='                      toggleLyrics()\n                    }.accessibilityIdentifier("toggle-lyrics")'
assert player.count(inline_action)==1
player=player.replace(inline_action,'                      if expanded { expandedLyrics = true } else { toggleLyrics() }\n                    }.accessibilityIdentifier("toggle-lyrics")')
# The lightbulb already opens and reads Meaning; remove the duplicate bubble action.
a=player.index('            Button {\n              model.loadLyrics()\n              expandedLyrics = true')
b=player.index('            meaningButton',a)
player=player[:a]+player[b:]
a=player.index('                    playerAction("Significato", icon: "quote.bubble"')
b=player.index('                    Spacer()',a)
player=player[:a]+player[b:]
# Remove the old app's debug harness; it is not the MusicKit test harness.
player=re.sub(r'                #if DEBUG.*?                #endif\n','',player,flags=re.S)
a=player.index('    Button {\n      #if DEBUG')
b=player.index('    } label: {',a)
player=player[:a]+'    Button { model.explain() } label: {'+player[b+len('    } label: {'):]
mini=mini.replace('private struct DuoNavigationBars','struct DuoNavigationBars').replace('private struct SystemMiniPlayerAccessory','struct SystemMiniPlayerAccessory').replace('private struct LegacyMiniPlayerInset','struct LegacyMiniPlayerInset')
for layout in ['player','mini']:
 value=locals()[layout]
 for suffix in ['', ', fit: true']:
  old='Artwork(url: song.artwork'+suffix+')'
  new='Artwork(url: song.artwork'+suffix+', onLoaded: { model.artworkLoaded(song, url: $0) }, onFailure: { url, error in await model.artworkFailed(song, url: url, error: error) })'
  value=value.replace(old,new)
 if layout=='player':player=value
 else:mini=value
# MusicKit queue items can be lightweight; hydrate artwork independently of audio.
player=player.replace('.accessibilityIdentifier("player-artwork")','.accessibilityIdentifier("player-artwork")\n                      .task(id: song.id) { await model.loadCurrentArtwork() }')
controls=re.sub(r'      #if DEBUG && os\(iOS\).*?      #endif\n','',controls,flags=re.S)
controls=controls.replace('Label("YouTube",','Label("Apple Music",')
controls=controls.replace('Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...100)\n          .accessibilityLabel("Volume del player")','NativeMusicVolume().frame(height: 28).accessibilityLabel("Volume")')
a=controls.index('      #if os(iOS)\n        if player.cast.connected')
b=controls.index('      #endif',a)+len('      #endif')
controls=controls[:a]+controls[b:]
alltext='import AVKit\nimport Combine\nimport SwiftUI\nimport UIKit\n\n'+art+mini+player+controls
for old,new in [('MusicModel','ApplePlayerAdapter'),('PlaybackPlayer','ApplePlayerAdapter'),('MiniPlayer','AppleMiniPlayer'),('PlayerScreen','AdaptedYTPlayerScreen'),('PlayerControls','AdaptedYTPlayerControls'),('LyricsContent','PlayerInfoContent'),('MeaningView','MeaningScreen'),('QueueScreen','ApplePlayerQueueScreen'),('AudioOutputButtons','AppleAudioOutputButtons')]:
 alltext=re.sub(r'\b'+old+r'\b',new,alltext)
alltext=re.sub(r'\bSong\b','PlayerSong',alltext)
alltext=re.sub(r'\bArtwork\b','YTPlayerArtwork',alltext).rstrip()+'\n'
header=f'// Player presentation ported from {path} at {revision}.\n// Original SHA256: {hashlib.sha256(source.encode()).hexdigest()}\n// Reproduce with Scripts/import_youtube_player.py. Service adaptations are explicit there.\n'
output=root/'iosAppleMusic/Sources/YouTubePlayerPresentation.swift'
if '--check' in sys.argv:
 assert output.read_text()==header+alltext, 'Player presentation differs from pinned port'
 print('Pinned YouTube player presentation: verified')
else:output.write_text(header+alltext)
