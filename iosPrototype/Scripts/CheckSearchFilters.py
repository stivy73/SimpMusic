"""Compare phone search filters to the checked-out Android SearchFilter constants."""
import re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
android = (root.parent / "core/service/kotlinYtmusicScraper/src/commonMain/kotlin/com/maxrave/kotlinytmusicscraper/YouTube.kt").read_text()
swift = (root / "Sources/Core/HomeDiscovery.swift").read_text()
names = {"SONG": "songs", "ARTIST": "artists", "ALBUM": "albums", "VIDEO": "videos",
         "FEATURED_PLAYLIST": "playlists", "COMMUNITY_PLAYLIST": "communityPlaylists", "PODCAST": "podcasts"}
for key, identifier in names.items():
    expected = re.search(r'FILTER_' + key + r': SearchFilter = SearchFilter\("([^"]+)"\)', android).group(1)
    actual = re.search(r'case \.' + identifier + r': "([^"]+)"', swift).group(1)
    assert actual == expected, f"Search filter differs: {key}"
print("iOS/Android search filters: all 7 params identical")
