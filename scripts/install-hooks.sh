#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
APP_DIR="$PROJECT_DIR/outputs/Claude Pulse.app"
INSTALLED_APP="/Applications/Claude Pulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HOOK_BIN="$HOME/.local/bin/cc-light"
SETTINGS_FILE="$HOME/.claude/settings.json"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HOME/.local/bin" "$HOME/.claude"
cp ".build/release/cc-light" "$MACOS_DIR/cc-light"
cp -R ".build/release/CCLight_CCLight.bundle" "$RESOURCES_DIR/CCLight_CCLight.bundle"
cp "Sources/CCLight/Resources/ClaudePulse.icns" "$RESOURCES_DIR/ClaudePulse.icns"
cp ".build/release/cc-light" "$HOOK_BIN"
chmod +x "$MACOS_DIR/cc-light" "$HOOK_BIN"

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Claude Pulse" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Claude Pulse" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.cclight.pulse" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string cc-light" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ClaudePulse" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSAppleEventsUsageDescription string 用于在你点击会话时切回对应的终端窗口。" "$CONTENTS_DIR/Info.plist"

HOOK_BIN_ESCAPED="${HOOK_BIN//\//\\/}"
/usr/bin/python3 - "$SETTINGS_FILE" "$HOOK_BIN" <<'PY'
import json
import os
import sys

path, binary = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hooks = settings.setdefault("hooks", {})
events = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PostToolBatch", "PermissionRequest",
    "Notification", "Stop", "StopFailure", "SessionEnd"
]
command = f'\"{binary}\" emit'
for event in events:
    groups = hooks.setdefault(event, [])
    already_installed = any(
        command == hook.get("command")
        for group in groups
        for hook in group.get("hooks", [])
        if isinstance(hook, dict)
    )
    if not already_installed:
        groups.append({"hooks": [{"type": "command", "command": command, "timeout": 5}]})

temp = path + ".cc-light.tmp"
with open(temp, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(temp, path)
PY

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
pkill -f '/Claude Pulse.app/Contents/MacOS/cc-light' 2>/dev/null || true
ditto "$APP_DIR" "$INSTALLED_APP"
codesign --force --deep --sign - "$INSTALLED_APP" >/dev/null 2>&1 || true
open "$INSTALLED_APP"

print "Claude Pulse 已安装并启动。"
print "Hooks: $SETTINGS_FILE"
print "App:   $INSTALLED_APP"
