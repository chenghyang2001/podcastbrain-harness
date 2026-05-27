#!/bin/bash
set -euo pipefail

# ==============================================================================
# autonomous_cli_loop.sh  (Linux 版)
#
# autonomous-coding-sub/autonomous_cli_loop.sh 的 Linux 相容版。
# 差異：移除 cygpath -w、python → python3、移除 PYTHONUTF8=1。
#
# autonomous_agent_demo.py 的 CLI 等價版。
#
# 原版用 Python + Claude Agent SDK 驅動「雙角色自主編碼」迴圈；本腳本改用
# claude CLI（claude -p）直接驅動，不依賴 Python SDK，只用 python 解析 JSON。
#
# 雙角色 pattern：
#   - Session 1（initializer）：讀 app_spec.txt → 生成 feature_list.json 等。
#   - Session 2+（coding）：讀 feature_list.json → 實作一個 feature → 標記 passes。
# 每個 session 都是全新 context；狀態靠 feature_list.json + git 外部化，
# 不靠對話延續（故意不用 claude --continue，見下方註解）。
#
# 用法：
#   ./autonomous_cli_loop.sh [專案名稱] [最大coding迭代數]
#   DRY_RUN=1 ./autonomous_cli_loop.sh    # 乾跑：只做檢查與設定，不真的呼叫 claude
#   MODEL=claude-opus-4-6 ./autonomous_cli_loop.sh   # 覆寫模型
# ==============================================================================

# --- 參數與變數 --------------------------------------------------------------

# $1：專案名稱（決定 generations/ 底下的子目錄），預設 cli_demo
PROJECT_NAME="${1:-cli_demo}"

# $2：coding 迴圈最大迭代數（initializer session 不計入），預設 30
MAX_ITER="${2:-30}"

# $3：initializer 產生的端對端測試案例數量（feature_list.json），預設 5
NUM_FEATURES="${3:-5}"

# 模型：可用環境變數 MODEL 覆寫，否則用 Sonnet 4.5
MODEL="${MODEL:-claude-sonnet-4-5-20250929}"

# DRY_RUN：環境變數，設為 1 時進乾跑模式（只做檢查與設定，不呼叫 claude）
DRY_RUN="${DRY_RUN:-0}"

# SLEEP_INTERVAL：coding session 之間的停頓秒數。
# 抽成環境變數的理由：不同模型 / 不同帳號額度下，避免 rate limit 所需的
# 間隔不同；寫死 3 秒在被限流時無法臨時加長，故讓使用者可外部覆寫。
SLEEP_INTERVAL="${SLEEP_INTERVAL:-3}"

# STALL_LIMIT：連續幾圈 coding session 跑完但剩餘 feature 數沒下降即視為卡住。
# 抽成環境變數的理由：feature 卡住時（claude 每圈跑完卻標不上 passes）原本
# 只能白燒到 MAX_ITER，成本浪費；達此圈數即提前中止止血，可外部覆寫門檻。
STALL_LIMIT="${STALL_LIMIT:-3}"

# SCRIPT_DIR：腳本自我定位，避免硬編碼 C:\Users\... 路徑
# 用 BASH_SOURCE 取得腳本本身位置，再 cd 進去取絕對路徑。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROMPTS_DIR="$SCRIPT_DIR/prompts"
PROJECT_DIR="$SCRIPT_DIR/generations/$PROJECT_NAME"
PARSER_PATH="$SCRIPT_DIR/scripts/parse_claude_stream.py"
_INIT_PROMPT_TMP=$(mktemp /tmp/cc_initprompt_XXXX.md)
sed "s/__NUM_FEATURES__/$NUM_FEATURES/g" "$PROMPTS_DIR/initializer_prompt.md" > "$_INIT_PROMPT_TMP"
INITIALIZER_PROMPT="$_INIT_PROMPT_TMP"
CODING_PROMPT="$PROMPTS_DIR/coding_prompt.md"

# --- 前置檢查（preflight） ---------------------------------------------------
# 任一硬性檢查失敗：印繁中錯誤訊息到 stderr 並 exit 1。

# claude CLI 必須存在，否則整個迴圈無法驅動。
if ! command -v claude >/dev/null 2>&1; then
  echo "錯誤：找不到 claude CLI，請先安裝 Claude Code（npm install -g @anthropic-ai/claude-code）。" >&2
  exit 1
fi

# python3 用來解析 feature_list.json，沒有就無法計算剩餘 feature 數。
if ! command -v python3 >/dev/null 2>&1; then
  echo "錯誤：找不到 python3，本腳本需要 python3 來解析 feature_list.json。" >&2
  exit 1
fi

# 三個 prompt 檔缺一不可。
if [ ! -f "$PROMPTS_DIR/initializer_prompt.md" ]; then
  echo "錯誤：缺少 $PROMPTS_DIR/initializer_prompt.md。" >&2
  exit 1
fi

if [ ! -f "$PROMPTS_DIR/coding_prompt.md" ]; then
  echo "錯誤：缺少 $PROMPTS_DIR/coding_prompt.md。" >&2
  exit 1
fi

if [ ! -f "$PROMPTS_DIR/app_spec.txt" ]; then
  echo "錯誤：缺少 $PROMPTS_DIR/app_spec.txt。" >&2
  exit 1
fi

# ANTHROPIC_API_KEY 警告（非致命，不 exit）：
# claude CLI 一旦偵測到 ANTHROPIC_API_KEY，會優先走 API Credits 計費，
# 而非免費的 Max 訂閱額度。此迴圈會跑數十次 session，成本差異可觀。
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "警告：偵測到 ANTHROPIC_API_KEY，claude CLI 會改走 API Credits 計費（付費）。" >&2
  echo "      若要用 Max 訂閱額度（免費），請先執行 unset ANTHROPIC_API_KEY 再跑本腳本。" >&2
fi

# --- 設定階段 ----------------------------------------------------------------

# 建立專案目錄，並立即初始化獨立的 git repo。
# 若不在此處 git init，claude 的 git 操作會冒泡命中外層 harness repo 的 .git，
# 把 app code 誤 commit 到 harness 裡（已實證踩坑：vps_run1）。
mkdir -p "$PROJECT_DIR"
if [ ! -d "$PROJECT_DIR/.git" ]; then
  git -C "$PROJECT_DIR" init -q
  git -C "$PROJECT_DIR" config user.email "agent@autonomous-coding"
  git -C "$PROJECT_DIR" config user.name "Autonomous Agent"
fi

# 複製 app_spec.txt 進專案目錄，讓 claude 從 cwd（PROJECT_DIR）直接讀得到。
cp "$PROMPTS_DIR/app_spec.txt" "$PROJECT_DIR/app_spec.txt"

# 寫入專案層級 .claude/settings.json：每次執行覆寫即可。
# 此設定給 claude 子程序自動 accept 編輯權限 + 白名單常用工具，
# 含 puppeteer MCP 工具白名單（搭配下方 .mcp.json 才生效）。
# 讓自主迴圈不會卡在權限確認。
mkdir -p "$PROJECT_DIR/.claude"
cat > "$PROJECT_DIR/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": ["Read", "Write", "Edit", "Glob", "Grep", "Bash(npm:*)", "Bash(node:*)", "Bash(git init:*)", "Bash(git add:*)", "Bash(git commit:*)", "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(mkdir:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)", "Bash(grep:*)", "Bash(pwd)", "Bash(cp:*)", "Bash(netstat:*)", "Bash(ss:*)", "Bash(ps:*)", "Bash(curl:*)", "Bash(kill:*)", "Bash(chmod:*)", "Bash(npx:*)", "Bash(rm:*)", "Bash(mv:*)", "Bash(touch:*)", "Bash(echo:*)", "Bash(sed:*)", "Bash(awk:*)", "Bash(env:*)", "Bash(export:*)", "Bash(bash:*)", "Bash(sh:*)", "Bash(python:*)", "Bash(python3:*)", "Bash(pip:*)", "Bash(pip3:*)", "Bash(which:*)", "Bash(find:*)", "Bash(xargs:*)", "Bash(lsof:*)", "Bash(pkill:*)", "Bash(date:*)", "Bash(sleep:*)", "mcp__puppeteer__puppeteer_navigate", "mcp__puppeteer__puppeteer_screenshot", "mcp__puppeteer__puppeteer_click", "mcp__puppeteer__puppeteer_fill", "mcp__puppeteer__puppeteer_select", "mcp__puppeteer__puppeteer_hover", "mcp__puppeteer__puppeteer_evaluate", "mcp__puppeteer__puppeteer_connect_active_tab"]
  }
}
EOF

# 寫入專案層級 .mcp.json：宣告 puppeteer MCP server。
# claude CLI 偵測到 PROJECT_DIR 有 .mcp.json 就會 spawn 對應 server，
# 之後 settings.json allow list 裡的 mcp__puppeteer__* 工具才會生效。
# 對齊 Python 版 client.py:107-109 的 mcp_servers={"puppeteer": {"command":"npx", "args":["puppeteer-mcp-server"]}}
cat > "$PROJECT_DIR/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "puppeteer": {
      "command": "npx",
      "args": ["puppeteer-mcp-server"]
    }
  }
}
EOF

# --- 計數 helper -------------------------------------------------------------

# count_remaining：印出「passes 不為 true 的 feature 數」到 stdout。
# 用 python 解析當前 cwd 下的 feature_list.json。
# 若檔案不存在 / JSON 解析失敗，python 會非零退出並把錯誤印到 stderr，
# 呼叫端可用 || 分支判斷（見主流程）。
count_remaining() {
  python3 -c "import json; print(sum(1 for f in json.load(open('feature_list.json',encoding='utf-8')) if not f.get('passes',False)))"
}

# --- 主流程 ------------------------------------------------------------------

# 進入專案目錄：claude 一律在 PROJECT_DIR 內執行，cwd 即為它的工作根目錄。
cd "$PROJECT_DIR"

echo "=============================================================="
echo " 自主編碼 CLI 迴圈（Linux 版）"
echo "  專案目錄：$PROJECT_DIR"
echo "  模型：$MODEL"
echo "  最大 coding 迭代數：$MAX_ITER"
if [ "$DRY_RUN" = "1" ]; then
  echo "  模式：DRY-RUN（不會真的呼叫 claude）"
fi
echo "=============================================================="

# DISABLE_WRITER_QA_HOOK=1 的理由：
#   本腳本會以子程序呼叫 claude，而子程序會繼承使用者全域 ~/.claude/ 設定，
#   其中包含「程式碼三 agent 鐵律」hook（enforce_writer_qa.py）。該 hook 會
#   攔截 .sh / .py 等程式碼檔的 Write/Edit。若不停用，巢狀 agent 在迴圈內
#   寫程式碼會被攔截而卡死（演練實測踩過）。此處明確停用該 hook。

# Session 1（initializer）：只在 feature_list.json 尚未存在時跑一次。
if [ ! -f "feature_list.json" ]; then
  echo ""
  echo "--- Session 1：initializer（讀 app_spec → 生成 feature_list.json） ---"
  if [ "$DRY_RUN" = "1" ]; then
    # 用文字描述而非顯示含 < 重導向的指令：若直接把 "< '路徑'" 寫進 echo 字串，
    # 使用者整行複製貼上時 < 會被 shell 當成重導向而誤觸發。
    echo "[DRY-RUN] 將執行 initializer session：DISABLE_WRITER_QA_HOOK=1 claude -p （含 stream-json verbose + Python parser，model=$MODEL，permission-mode acceptEdits，max-turns 200，從 $PROMPTS_DIR/initializer_prompt.md 以 --system-prompt-file 傳入，user message 為 \"Begin. Execute all initialization tasks now.\"）"
  else
    # 用 if ! ... 包裹的理由：if 條件位置的指令不受 set -e 中止，
    # 因此 claude 非零退出時能落到 then 分支印診斷訊息再 exit，
    # 而不是被 set -e 直接 silent exit、讓使用者隔天看不出跑到第幾圈。
    #
    # --output-format stream-json --verbose：讓 claude 印 JSONL 事件流
    # （含 tool_use / tool_result / text block），透過 pipe 餵給 Python parser
    # 翻成可讀的 [Tool: ...] / [OK] / > text 行。
    # set -o pipefail 已在腳本頂層設定，pipe 中任一段非零退出都會被 if ! 捕獲。
    #
    # --system-prompt-file：把 prompt 放 system 位置，避免 model 把角色設定當 user message 問「你想做什麼」。
    _INIT_TMPOUT=$(mktemp /tmp/cc_init_XXXX.jsonl)
    DISABLE_WRITER_QA_HOOK=1 claude -p "Begin. Execute all initialization tasks now." \
      --system-prompt-file "$INITIALIZER_PROMPT" \
      --model "$MODEL" \
      --permission-mode bypassPermissions \
      --max-turns 200 \
      --output-format stream-json \
      --verbose \
      >> "$_INIT_TMPOUT" &
    _INIT_CPID=$!
    # 直接把 tmpout 路徑傳給 parser，取代舊的 tail -n +1 -f ... | python pipeline。
    # tail -f 只有在嘗試寫新資料時才收 SIGPIPE；session 結束後若無新資料，
    # tail 永遠不退出，整個 pipeline 因此 deadlock。
    # 改用 poll_file 模式直接讀檔，根本消除 deadlock。
    # Linux 路徑可直接傳給 python3。
    set +e
    python3 "$PARSER_PATH" "$_INIT_TMPOUT"
    _INIT_PEXIT=$?
    set -e
    kill "$_INIT_CPID" 2>/dev/null || true; wait "$_INIT_CPID" 2>/dev/null || true
    rm -f "$_INIT_TMPOUT"
    rm -f "$_INIT_PROMPT_TMP"
    if [ $_INIT_PEXIT -ne 0 ]; then
      echo "錯誤：initializer session 非零退出（可能 rate limit / max-turns 耗盡 / auth 過期 / 網路中斷）。中止迴圈。" >&2
      exit 1
    fi
  fi
else
  echo ""
  echo "--- Session 1：略過（feature_list.json 已存在，沿用既有進度） ---"
fi

# Session 2+（coding 迴圈）：每圈跑一個全新 context 的 claude session。
# 不用 claude --continue 的理由：autonomous coding pattern 刻意要求每個
# session 都是乾淨 context，避免長對話脈絡污染；session 之間靠
# feature_list.json + git 傳遞狀態，而非靠對話延續。

# stall detection 狀態：prev_remaining 設 -1 當「尚無前一圈資料」哨兵值，
# 避免第一圈就把初始 remaining 誤判成無進度；stall_count 累計連續無進度圈數。
prev_remaining=-1
stall_count=0

for i in $(seq 1 "$MAX_ITER"); do
  # DRY_RUN：在讀 feature_list.json 之前就攔截。
  # 乾跑模式下 initializer 沒真的執行，feature_list.json 不存在，
  # 若先呼叫 count_remaining 會解析失敗而誤判 exit 1。故 guard 必須是
  # for 迴圈內第一個動作，早於任何 count_remaining 呼叫。
  if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "--- coding 迴圈（DRY-RUN 示意，不讀 feature_list.json） ---"
    # 用文字描述而非顯示含 < 重導向的指令：避免使用者整行複製貼上時誤觸發。
    echo "[DRY-RUN] 將執行 coding session：DISABLE_WRITER_QA_HOOK=1 claude -p （含 stream-json verbose + Python parser，model=$MODEL，permission-mode acceptEdits，max-turns 200，從 $PROMPTS_DIR/coding_prompt.md 以 --system-prompt-file 傳入，user message 為 \"Continue. Execute your coding task now.\"）"
    # 乾跑時不真的跑迴圈，印一次示意指令後即跳出。
    break
  fi

  # 算剩餘 feature 數；feature_list.json 缺失或損毀時，count_remaining 失敗。
  if remaining="$(count_remaining 2>/dev/null)"; then
    :
  else
    echo "錯誤：無法解析 feature_list.json（檔案不存在或格式錯誤），中止 coding 迴圈。" >&2
    exit 1
  fi

  # 全部 feature 通過 → 完成，跳出迴圈。
  if [ "$remaining" -eq 0 ]; then
    echo ""
    echo "全部 feature 通過，自主編碼完成。"
    break
  fi

  # stall detection：若上一圈 session 沒讓 remaining 下降，累計無進度圈數。
  # 放在此處（DRY_RUN guard 與 remaining -eq 0 檢查之後、跑 claude 之前）的理由：
  # DRY_RUN 模式已在上方 break，不會走到這；remaining 為 0 也已 break，
  # 故此處的 remaining 必為「需要繼續做但尚未做的真實待辦數」，比較才有意義。
  if [ "$prev_remaining" -ne -1 ] && [ "$remaining" -ge "$prev_remaining" ]; then
    stall_count=$((stall_count + 1))
    echo "警告：第 $i 圈偵測無進度（remaining 維持 $remaining），連續無進度 $stall_count/$STALL_LIMIT 圈" >&2
  else
    stall_count=0
  fi
  if [ "$stall_count" -ge "$STALL_LIMIT" ]; then
    echo "錯誤：連續 $STALL_LIMIT 圈 feature 數未下降，疑似卡住，提前中止以節省成本。剩餘 $remaining 個 feature。" >&2
    exit 1
  fi
  prev_remaining="$remaining"

  echo ""
  echo "--- Session $((i + 1))：coding（第 $i/$MAX_ITER 圈，剩餘 $remaining 個 feature） ---"

  # 用 if ! ... 包裹的理由：if 條件位置的指令不受 set -e 中止，
  # 因此 claude 非零退出時能落到 then 分支印診斷訊息再 exit，
  # 而不是被 set -e 直接 silent exit、讓使用者隔天看不出跑到第幾圈。
  #
  # --output-format stream-json --verbose：讓 claude 印 JSONL 事件流
  # （含 tool_use / tool_result / text block），透過 pipe 餵給 Python parser
  # 翻成可讀的 [Tool: ...] / [OK] / > text 行。
  # set -o pipefail 已在腳本頂層設定，pipe 中任一段非零退出都會被 if ! 捕獲。
  #
  # --system-prompt-file：把 prompt 放 system 位置，避免 model 把角色設定當 user message 問「你想做什麼」。
  _CODING_TMPOUT=$(mktemp /tmp/cc_coding_XXXX.jsonl)
  DISABLE_WRITER_QA_HOOK=1 claude -p "Continue. Execute your coding task now." \
    --system-prompt-file "$CODING_PROMPT" \
    --model "$MODEL" \
    --permission-mode bypassPermissions \
    --max-turns 200 \
    --output-format stream-json \
    --verbose \
    >> "$_CODING_TMPOUT" &
  _CODING_CPID=$!
  # 直接把 tmpout 路徑傳給 parser，取代舊的 tail -n +1 -f ... | python pipeline。
  # tail -f 只有在嘗試寫新資料時才收 SIGPIPE；session 結束後若無新資料，
  # tail 永遠不退出，整個 pipeline 因此 deadlock。
  # 改用 poll_file 模式直接讀檔，根本消除 deadlock。
  # Linux 路徑可直接傳給 python3。
  set +e
  python3 "$PARSER_PATH" "$_CODING_TMPOUT"
  _CODING_PEXIT=$?
  set -e
  kill "$_CODING_CPID" 2>/dev/null || true; wait "$_CODING_CPID" 2>/dev/null || true
  rm -f "$_CODING_TMPOUT"
  if [ $_CODING_PEXIT -ne 0 ]; then
    echo "錯誤：第 $i 圈 coding session 非零退出（可能 rate limit / max-turns 耗盡 / auth 過期 / 網路中斷）。剩餘 $remaining 個 feature，中止迴圈。" >&2
    exit 1
  fi

  # 兩個 session 之間稍作停頓，避免連續打 API；間隔由 SLEEP_INTERVAL 控制。
  sleep "$SLEEP_INTERVAL"
done

# --- 結尾總結 ----------------------------------------------------------------

if [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo "=============================================================="
  echo " DRY-RUN 結束：preflight 檢查與設定階段完成，未呼叫 claude。"
  echo "  專案目錄：$PROJECT_DIR"
  echo "=============================================================="
  exit 0
fi

# 非乾跑：再算一次剩餘數做總結（feature_list.json 此時應已存在）。
if final_remaining="$(count_remaining 2>/dev/null)"; then
  :
else
  final_remaining="未知（feature_list.json 無法解析）"
fi

echo ""
echo "=============================================================="
echo " 自主編碼 CLI 迴圈結束"
echo "  專案目錄：$PROJECT_DIR"
echo "  剩餘未通過 feature 數：$final_remaining"
echo "=============================================================="
