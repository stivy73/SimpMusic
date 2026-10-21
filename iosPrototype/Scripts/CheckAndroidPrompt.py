"""Verify parity with the checked-out Android prompt, without accessing credentials."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
android = root.parent / 'core/service/aiService/src/commonMain/kotlin/org/simpmusic/aiservice/AiService.kt'
source = android.read_text().split('suspend fun explainSong(')[1].split('system {')[1].split('user {')[0]
quoted = r'"(?:[^"\\]|\\.)*"'
expected = ''.join(json.loads(part) for part in re.findall(quoted, source))
swift = (root / 'Sources/Core/Interpretation.swift').read_text()
actual = json.loads(re.search(quoted, swift.split('public static let systemPrompt =')[1]).group())
assert actual == expected, 'iOS and Android interpretation prompts differ'
print('iOS/Android system prompt: identical')
