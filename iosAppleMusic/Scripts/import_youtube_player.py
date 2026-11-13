"""Pin and port the real YouTube player presentation. Does not import its engine."""
from pathlib import Path
import subprocess, hashlib, re, sys
root=Path(__file__).resolve().parents[2]
revision='5a277798'
path='iosPrototype/Sources/App/StivyApp.swift'
source=subprocess.check_output(['git','show',f'{revision}:{path}'],cwd=root).decode()
def between(a,b):return source[source.index(a):source.index(b)]
art=between('struct Artwork: View {','struct RootView: View {')
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
# Remove the old app's debug harness; it is not the MusicKit test harness.
player=re.sub(r'                #if DEBUG.*?                #endif\n','',player,flags=re.S)
a=player.index('    Button {\n      #if DEBUG')
b=player.index('    } label: {',a)
player=player[:a]+'    Button { model.explain() } label: {'+player[b+len('    } label: {'):]
mini=mini.replace('private struct DuoNavigationBars','struct DuoNavigationBars').replace('private struct SystemMiniPlayerAccessory','struct SystemMiniPlayerAccessory').replace('private struct LegacyMiniPlayerInset','struct LegacyMiniPlayerInset')
controls=re.sub(r'      #if DEBUG && os\(iOS\).*?      #endif\n','',controls,flags=re.S)
controls=controls.replace('Label("YouTube",','Label("Apple Music",')
controls=controls.replace('Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...100)\n          .accessibilityLabel("Volume del player")','NativeMusicVolume().frame(height: 28).accessibilityLabel("Volume")')
a=controls.index('      #if os(iOS)\n        if player.cast.connected')
b=controls.index('      #endif',a)+len('      #endif')
controls=controls[:a]+controls[b:]
alltext='import AVKit\nimport Combine\nimport SwiftUI\n\n'+art+mini+player+controls
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
