#!/bin/zsh
set -euo pipefail

HOOK_BIN="$HOME/.local/bin/cc-light"
SETTINGS_FILE="$HOME/.claude/settings.json"

/usr/bin/python3 - "$SETTINGS_FILE" "$HOOK_BIN" <<'PY'
import json
import os
import sys

path, binary = sys.argv[1:]
if not os.path.exists(path):
    raise SystemExit(0)
with open(path, encoding="utf-8") as f:
    settings = json.load(f)
command = f'\"{binary}\" emit'
hooks = settings.get("hooks", {})
for event in list(hooks):
    cleaned = []
    for group in hooks[event]:
        entries = [h for h in group.get("hooks", []) if h.get("command") != command]
        if entries:
            group["hooks"] = entries
            cleaned.append(group)
    if cleaned:
        hooks[event] = cleaned
    else:
        del hooks[event]
temp = path + ".cc-light.tmp"
with open(temp, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(temp, path)
PY

rm -f "$HOOK_BIN"
print "Claude Pulse Hooks 已移除。"
