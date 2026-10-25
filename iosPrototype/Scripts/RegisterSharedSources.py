"""Register new shared Swift sources in the explicit iOS and optional local Mac projects."""
import hashlib, json, re, subprocess, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for project, target, prefix in [(root/'StivySimpMusic.xcodeproj/project.pbxproj', 'StivySimpMusic', ''), (root.parent/'macPrototype/NoteNarrateMac.xcodeproj/project.pbxproj', 'NoteNarrateMac', '../iosPrototype/')]:
    if not project.exists(): continue
    text = project.read_text()
    data = json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(project)]))
    objects = data['objects']; main = objects[data['rootObject']]['mainGroup']
    app = next(value for value in objects.values() if value.get('isa')=='PBXNativeTarget' and value.get('name')==target)
    phase = next(key for key in app['buildPhases'] if objects[key]['isa']=='PBXSourcesBuildPhase')
    refs, builds, entries = [], [], []
    for path in sys.argv[1:]:
        path = path.removeprefix('iosPrototype/')
        actual = prefix + path
        if actual in text: continue
        ref = hashlib.sha1(actual.encode()).hexdigest()[:24].upper()
        build = hashlib.sha1((actual+'-build').encode()).hexdigest()[:24].upper()
        refs.append(ref); builds.append(build)
        entries += [f'{ref} = {{ isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{actual}"; sourceTree = "<group>"; }};', f'{build} = {{ isa = PBXBuildFile; fileRef = {ref}; }};']
    if not refs: continue
    for key, field, values in [(main,'children',refs),(phase,'files',builds)]:
        pattern = r'("?'+key+r'"?\s*=\s*\{[^{}]*?"?'+field+r'"?\s*=\s*\()'
        text, count = re.subn(pattern,lambda m:m.group(1)+','.join(values)+',',text,count=1)
        assert count==1, (project,key,field)
    text = re.sub(r'("?objects"?\s*=\s*\{)',lambda m:m.group(1)+'\n'+'\n'.join(entries)+'\n',text,count=1)
    project.write_text(text)
    print(project.parent.name, 'registered',len(refs),'files')
