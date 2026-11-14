"""Pinned carousels, categories and Home filter presentation from YouTube Music."""
from pathlib import Path
import subprocess,hashlib,sys,re,textwrap
root=Path(__file__).resolve().parents[2]
source='iosPrototype/Sources/App/HomeView.swift'
original=subprocess.check_output(['git','show','5a277798:'+source],cwd=root).decode()
s=original[original.index('struct DiscoveryShelves:'):original.index('\nstruct DiscoveryItemLink<')]
a=s.index('            if let target = shelf.more {')
b=s.index('\n          }.padding(.horizontal, 20)',a)
s=s[:a]+'''            NavigationLink("Altro") { AppleShelfScreen(shelf:shelf) }
              .font(.subheadline).accessibilityLabel("Altro: \\(shelf.title)")'''+s[b:]
s=s.replace('HomeShelf','AppleShelf').replace('DiscoveryShelves','AppleDiscoveryShelves').replace('DiscoveryItemLink','AppleDiscoveryItemLink').replace('DiscoveryCard','AppleDiscoveryCard').replace('let item: DiscoveryItem','let item: MusicBrowseItem')
s=s.replace('Artwork(url: avatar)','YTPlayerArtwork(url: avatar)').replace('Artwork(url: item.artwork)','BrowseCover(item: item)')
c=original[original.index('private struct DiscoveryCategories:'):original.index('\nprivate struct DiscoveryContinuation:')]
c=c.replace('private struct DiscoveryCategories','struct AppleDiscoveryCategories').replace('HomeCategorySection','AppleCategorySection').replace('HomeBrowseView(title: item.title, target: item.target)','AppleExploreDestinationScreen(destination:item.target)')
header='// Adapted from '+source+' at 5a277798. SHA256 '+hashlib.sha256(original.encode()).hexdigest()+'\n// Reproduce with Scripts/import_youtube_discovery.py.\nimport SwiftUI\n\n'
path=root/'iosAppleMusic/Sources/YouTubeDiscoveryPresentation.swift'
expected=(header+s+'\n'+c).rstrip()+'\n'
if '--check' in sys.argv:
 assert path.read_text()==expected,'Pinned discovery presentation differs'
 print('Pinned discovery presentation: verified')
else:path.write_text(expected)

# Keep the same IDs, order, labels and chip code, without importing YouTube's
# opaque browse parameters or SDK into the Apple Music target.
filter_source='iosPrototype/Sources/Core/HomeDiscovery.swift'
filter_original=subprocess.check_output(['git','show','5a277798:'+filter_source],cwd=root).decode()
definition=filter_original[filter_original.index('public struct HomeFilter:'):filter_original.index('\npublic struct DiscoveryItem:')]
labels=[('all','Tutto')]+re.findall(r'id: "([a-z_]+)", title: "([^"]+)"',definition)[1:]
assert len(labels)==11 and len({key for key,_ in labels})==11
metadata='// Adapted from '+filter_source+' at 5a277798. SHA256 '+hashlib.sha256(filter_original.encode()).hexdigest()+'\n// Reproduce with Scripts/import_youtube_discovery.py. No YouTube browse parameters.\nimport Foundation\n\n'
metadata+='struct AppleHomeFilter:Identifiable,Hashable,Sendable {\n  let id:String\n  let title:String\n  static let all=AppleHomeFilter(id:"all",title:"Tutto")\n  static let values:[Self]=[\n    all,\n'
metadata+=''.join('    .init(id:"'+key+'",title:"'+title+'"),\n' for key,title in labels[1:])
metadata+='  ]\n}\n'
start=original.index('        ScrollView(.horizontal, showsIndicators: false) {')
end=original.index('        if library.session == nil {',start)
bar=textwrap.dedent(original[start:end]).rstrip().replace('HomeFilter.values','AppleHomeFilter.values')
presentation=header+'struct AppleHomeQuickFilters:View {\n  @ObservedObject var home:HomeQuickFilterStore<MusicBrowseItem>\n  var body:some View {\n'+textwrap.indent(bar,'    ')+'\n  }\n}\n'
for name,contents in [('HomeFilter.swift',metadata),('YouTubeHomeFiltersPresentation.swift',presentation)]:
 target=root/'iosAppleMusic/Sources'/name
 if '--check' in sys.argv:
  assert target.read_text()==contents,'Pinned Home filters differ: '+name
  print('Pinned Home filters: verified '+name)
 else:target.write_text(contents)
