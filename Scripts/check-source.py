#!/usr/bin/env python3
"""Portable source/package checks. Swift syntax checks are NOT Apple SDK compilation.

Optional syntax parser: python3 -m pip install tree-sitter==0.26.0 tree-sitter-swift==0.7.3
"""
from pathlib import Path
import json, plistlib, re, sys, struct, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
failures = []
swift_files = sorted(ROOT.rglob('*.swift'))
swift_files = [p for p in swift_files if '.build' not in p.parts]
for path in ROOT.rglob('*.json'):
    if '.build' not in path.parts:
        try: json.loads(path.read_text(encoding='utf-8-sig'))
        except Exception as error: failures.append(f'{path.relative_to(ROOT)}: {error}')
for path in list(ROOT.rglob('*.plist')) + list(ROOT.rglob('*.xcprivacy')):
    try: plistlib.loads(path.read_bytes())
    except Exception as error: failures.append(f'{path.relative_to(ROOT)}: {error}')
for path in swift_files:
    text = path.read_text(encoding='utf-8-sig')
    if re.search(r'\b(WKWebView|UIWebView)\b', text): failures.append(f'Web wrapper found: {path}')
    if re.search(r'sb_secret_|service_role\s*[=:]\s*["\']', text): failures.append(f'Privileged key pattern found: {path}')

icon = ROOT / 'App/Assets.xcassets/AppIcon.appiconset/Watchdog-1024.png'
if icon.exists():
    data = icon.read_bytes()
    width, height = struct.unpack('>II', data[16:24])
    if (width, height) != (1024, 1024) or data[25] in (4,6): failures.append('App icon must be opaque 1024x1024.')
else: failures.append('App icon is missing.')

parsed = False
try:
    import tree_sitter, tree_sitter_swift
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    for path in swift_files:
        tree = parser.parse(path.read_bytes())
        if tree.root_node.has_error:
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == 'ERROR' or node.is_missing:
                    failures.append(f'{path.relative_to(ROOT)}:{node.start_point.row+1}: Swift syntax {node.type}')
                else: stack.extend(reversed(node.children))
    parsed = True
except ImportError:
    print('Swift parser not installed; syntax scan skipped. Install the pinned parser packages noted above.')

project = ROOT / 'Watchdog.xcodeproj/project.pbxproj'
project_parsed = False
if project.exists():
    content = project.read_text()
    for path in (ROOT / 'App').rglob('*.swift'):
        relative = path.relative_to(ROOT).as_posix()
        if f'path = "{relative}";' not in content: failures.append(f'App source missing from Xcode project: {relative}')
    try:
        from openstep_parser import OpenStepDecoder
        parsed_project = OpenStepDecoder.ParseFromString(content)
        objects = parsed_project['objects']
        assert objects[parsed_project['rootObject']]['isa'] == 'PBXProject'
        for identifier, value in objects.items():
            if value.get('isa') == 'PBXFileReference' and value.get('sourceTree') == 'SOURCE_ROOT':
                if not (ROOT / value['path']).exists(): failures.append('Missing project file: ' + value['path'])
            for key in ('fileRef','productRef','package','mainGroup','productRefGroup','target','targetProxy','containerPortal','buildConfigurationList','productReference'):
                if key in value and value[key] not in objects: failures.append(f'Unresolved Xcode reference {identifier}.{key}')
            for key in ('children','targets','buildPhases','buildConfigurations','dependencies','files','packageReferences','packageProductDependencies'):
                for target in value.get(key,[]):
                    if target not in objects: failures.append(f'Unresolved Xcode list reference {identifier}.{key}: {target}')
        for path in (ROOT / 'Watchdog.xcodeproj').rglob('*.xcscheme'):
            tree = ET.parse(path)
            for item in tree.iter('BuildableReference'):
                if item.attrib['BlueprintIdentifier'] not in objects: failures.append(f'Scheme target is missing: {path.name}')
        project_parsed = True
    except ImportError:
        print('OpenStep parser not installed; project structure parsing skipped (optional: openstep-parser==2.0.3).')
    except Exception as error:
        failures.append('Xcode project parse: ' + str(error))
else: failures.append('Xcode project is missing. Run Scripts/generate-project.py.')

report = {'swiftFiles':len(swift_files), 'swiftSyntaxParsed':parsed, 'xcodeProjectParsed':project_parsed, 'failures':failures,
          'appleSDKCompiled':False, 'simulatorTested':False}
print(json.dumps(report,indent=2))
sys.exit(1 if failures else 0)
