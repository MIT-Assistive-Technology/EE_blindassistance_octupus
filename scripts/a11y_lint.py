#!/usr/bin/env python3
"""Static accessibility lint for the Octopi SwiftUI sources.

Catches the mistakes that Apple's runtime audit cannot see from the outside:
fixed font sizes that ignore Dynamic Type, image-only buttons without labels,
tap gestures on non-controls, single-line truncation, and controls with empty labels.

Usage:  python3 scripts/a11y_lint.py [Octopi/App]
Exit status 1 when any finding is reported.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "Octopi/App")

RULES = [
    (r"\.font\(\.system\(size:", "Fixed font size ignores Dynamic Type; use a text style (.title, .largeTitle) or @ScaledMetric."),
    (r"\.onTapGesture", "Tap gesture on a non-control is invisible to VoiceOver; use a Button."),
    (r"DragGesture|LongPressGesture|MagnificationGesture|RotationGesture", "Custom gesture needs an accessibility action alternative."),
    (r"\.lineLimit\(1\)", "Single-line truncation hides text at large Dynamic Type sizes."),
    (r"\.truncationMode", "Truncation hides text; let it wrap."),
    (r'Toggle\(""', "Toggle with an empty label."),
    (r'TextField\(""', "TextField with an empty placeholder/label."),
    (r'Button\(""', "Button with an empty title."),
    (r"\.accessibilityHidden\(true\)[^\n]*Text\(", "Hiding text from VoiceOver."),
    (r"\.frame\((?:width: \d+, )?height: (?:[0-9]|[1-3][0-9]|4[0-3])\)", "Control shorter than 44 points."),
    (r"\.disabled\(true\)", "Permanently disabled control is confusing; hide it or explain why."),
    (r"^(?![^\n]*(accessibilityLabel|strokeBorder|overlay))[^\n]*Color\.(red|green|yellow)\b", "Colour used as the only signal? Make sure text or haptics carry the meaning too."),
]

IMAGE_BUTTON = re.compile(r"Button\s*\{[^}]*\}\s*label:\s*\{\s*Image\(systemName:[^}]*\}\s*(?!\s*\.accessibilityLabel)", re.S)
LABEL_LESS_IMAGE = re.compile(r"^\s*Image\(systemName:[^\n]*\)\s*$")

findings = []
for path in sorted(ROOT.rglob("*.swift")):
    text = path.read_text()
    for pattern, message in RULES:
        for match in re.finditer(pattern, text, re.M):
            line = text.count("\n", 0, match.start()) + 1
            findings.append((path, line, message))
    for match in IMAGE_BUTTON.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        findings.append((path, line, "Image-only button without .accessibilityLabel."))
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if LABEL_LESS_IMAGE.match(line):
            window = "\n".join(lines[index:index + 3])
            if ".accessibilityLabel" not in window and ".accessibilityHidden" not in window and "decorative" not in window:
                findings.append((path, index + 1, "Standalone Image(systemName:) needs .accessibilityLabel or .accessibilityHidden(true)."))

if findings:
    for path, line, message in findings:
        print(f"{path}:{line}: {message}")
    print(f"\n{len(findings)} accessibility finding(s).")
    sys.exit(1)
print("No accessibility findings.")
