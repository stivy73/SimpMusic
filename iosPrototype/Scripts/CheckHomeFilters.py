"""Verify Home mood params against the checked-out SimpMusic Android source."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
android = (root.parent / "composeApp/src/commonMain/kotlin/com/maxrave/simpmusic/viewModel/HomeViewModel.kt").read_text()
swift = (root / "Sources/Core/HomeDiscovery.swift").read_text()
names = {"RELAX": "relax", "SLEEP": "sleep", "ENERGIZE": "energize", "SAD": "sad",
         "ROMANCE": "romance", "FEEL_GOOD": "feel_good", "WORKOUT": "workout",
         "PARTY": "party", "COMMUTE": "commute", "FOCUS": "focus"}
for key, identifier in names.items():
    expected = re.search(r'HOME_PARAMS_' + key + r'\s*=\s*"([^"]+)"', android).group(1)
    actual = re.search(r'id: "' + identifier + r'".*?params: "([^"]+)"', swift, re.S).group(1)
    assert actual == expected, f"Home filter differs: {key}"
print("iOS/Android Home filters: all 10 params identical")
