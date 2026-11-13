"""Pinned carousel geometry and category grid from the YouTube Music app."""
from pathlib import Path
import subprocess,hashlib,sys
root=Path(__file__).resolve().parents[2]
source='iosPrototype/Sources/App/HomeView.swift'
original=subprocess.check_output(['git','show','5a277798:'+source],cwd=root).decode()
s=original[original.index('struct DiscoveryShelves:'):original.index('\nstruct DiscoveryItemLink<')]
a=s.index('            if let target = shelf.more {')
b=s.index('\n          }.padding(.horizontal, 20)',a)
s=s[:a]+'''            NavigationLink("Altro") { AppleShelfScreen(shelf:shelf) }
              .font(.subheadline).accessibilityLabel("Altro: \\(shelf.title)")'''+s[b:]
s=s.replace('HomeShelf','AppleShelf').replace('DiscoveryShelves','AppleDiscoveryShelves').replace('DiscoveryItemLink','AppleDiscoveryItemLink').replace('DiscoveryCard','AppleDiscoveryCard').replace('let item: DiscoveryItem','let item: MusicBrowseItem')
s=s.replace('Artwork(url: avatar)','YTPlayerArtwork(url: avatar)').replace('Artwork(url: item.artwork)','Cover(artwork: item.artwork)')
c=original[original.index('private struct DiscoveryCategories:'):original.index('\nprivate struct DiscoveryContinuation:')]
c=c.replace('private struct DiscoveryCategories','struct AppleDiscoveryCategories').replace('HomeCategorySection','AppleCategorySection').replace('HomeBrowseView(title: item.title, target: item.target)','AppleExploreDestinationScreen(destination:item.target)')
header='// Adapted from '+source+' at 5a277798. SHA256 '+hashlib.sha256(original.encode()).hexdigest()+'\n// Reproduce with Scripts/import_youtube_discovery.py.\nimport SwiftUI\n\n'
path=root/'iosAppleMusic/Sources/YouTubeDiscoveryPresentation.swift'
expected=(header+s+'\n'+c).rstrip()+'\n'
if '--check' in sys.argv:
 assert path.read_text()==expected,'Pinned discovery presentation differs'
 print('Pinned discovery presentation: verified')
else:path.write_text(expected)
