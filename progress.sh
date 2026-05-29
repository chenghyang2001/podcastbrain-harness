#!/bin/bash
set -uo pipefail
# ============================================================
# progress.sh
# 用途：PodcastBrain demo 自主編碼迴圈的 VPS 端儀表板腳本。
#       由本機 watch-demo.bat 每 3 秒透過 SSH 呼叫，印出當前進度。
# 注意：刻意不使用 set -e，因為儀表板要容忍個別指令失敗仍繼續印完。
# 部署：scp 到 VPS 後需轉成 LF 行尾再執行。
# ============================================================

DEMO_DIR="/home/claude/podcastbrain-demo"
PROJ_DIR="$DEMO_DIR/generations/podcastbrain_demo"

# 1. 標題與當前時間
echo "===== PodcastBrain Demo Progress ====="
date '+%Y-%m-%d %H:%M:%S'
echo ""

# 2. Features 區塊：解析 feature_list.json
echo "--- Features ---"
FEATURE_JSON="$PROJ_DIR/feature_list.json"
if [ -f "$FEATURE_JSON" ]; then
    # 用 python3 解析 JSON：個別 feature 讀取失敗不可讓整個儀表板 crash
    FEATURE_JSON="$FEATURE_JSON" python3 <<'PY'
import json
import os
import sys

path = os.environ.get("FEATURE_JSON", "")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError) as exc:
    # 檔案讀取或 JSON 解析失敗：印繁中訊息但不中斷
    print(f"feature_list.json 讀取失敗：{exc}")
    sys.exit(0)

# feature 清單可能直接是 list，或包在 dict 的某個 key 底下
if isinstance(data, dict):
    features = data.get("features", data.get("feature_list", []))
elif isinstance(data, list):
    features = data
else:
    features = []

if not isinstance(features, list):
    features = []

total = len(features)
passed = 0
lines = []
for feat in features:
    if not isinstance(feat, dict):
        continue
    # 容忍多種 schema：passed / status / pass 欄位
    is_passed = bool(
        feat.get("passed")
        or feat.get("pass")
        or str(feat.get("status", "")).lower() in ("passed", "pass", "done")
    )
    if is_passed:
        passed += 1
    mark = "[v]" if is_passed else "[ ]"
    fid = feat.get("id", feat.get("feature_id", "?"))
    name = str(feat.get("name", feat.get("feature", feat.get("title", "")))).strip()
    lines.append(f"{mark} #{fid} {name[:55]}")

print(f"{passed} / {total} passed")
for line in lines:
    print(line)
PY
else
    echo "feature_list.json 尚未生成（initializer 進行中）"
fi
echo ""

# 3. 最近 git commits
echo "--- 最近 git commits ---"
if ! git -C "$PROJ_DIR" log --oneline -5 2>/dev/null; then
    echo "(尚無 commit)"
fi
echo ""

# 4. loop.log 末 8 行
echo "--- loop.log（末 8 行）---"
if ! tail -n 8 "$DEMO_DIR/loop.log" 2>/dev/null; then
    echo "(無 log)"
fi
echo ""

# 5. loop 進程狀態
if pgrep -f autonomous_cli_loop >/dev/null 2>&1; then
    echo "loop 進程：RUNNING"
else
    echo "loop 進程：STOPPED"
fi

# 6. streamlit 8502 狀態
if curl -s -o /dev/null http://localhost:8502 2>/dev/null; then
    echo "streamlit 8502：UP"
else
    echo "streamlit 8502：down"
fi
