#!/usr/bin/env python3
"""解析 claude -p --output-format stream-json 的 JSONL 輸出，印出可讀的 tool 呼叫流。

用法（直接餵檔案，無 tail deadlock 問題）：
  python parse_claude_stream.py /path/to/output.jsonl

用法（legacy stdin 模式，僅在明確需要 pipe 時使用）：
  claude -p --output-format stream-json --verbose < prompt.md | python parse_claude_stream.py

輸出範例：
  [Tool: Read] {"file_path":"app_spec.txt"}
     [OK] # Application Spec ...
  [Tool: Write] {"file_path":"feature_list.json"}
     [OK] (no output)
    > 我已經建立 feature_list.json 含 5 個 features...
  === DONE (cost: $0.0234, turns: 12) ===
"""
import json
import sys
import time
from typing import Any

# 預覽長度上限，避免長字串塞爆 terminal
INPUT_PREVIEW = 100
RESULT_PREVIEW = 80
TEXT_PREVIEW = 150

# poll_file 模式：idle 超過此秒數後印診斷並 exit(1)
IDLE_TIMEOUT_SEC = 120
# poll_file 模式：每次 readline 無資料時的等待間隔（秒）
POLL_INTERVAL = 0.2


def truncate(text: str, max_len: int) -> str:
    """截斷字串並加省略符號；同時把換行壓成空白避免破壞單行排版。"""
    text = text.replace("\n", " ").strip()
    return text if len(text) <= max_len else text[:max_len] + "..."


def extract_tool_result_content(content: Any) -> str:
    """tool_result.content 可能是 str 或 list[block]；統一轉成單一字串。

    list 形式來自 Anthropic API 規格：每個 block 可能是 {"type":"text","text":...}
    或單純字串。為了相容，逐個解開後用空白串起來。
    """
    if isinstance(content, list):
        return " ".join(
            c.get("text", "") if isinstance(c, dict) else str(c)
            for c in content
        )
    return str(content)


def handle_assistant(msg: dict) -> None:
    """處理 assistant 訊息：印出 tool_use 與 text block。"""
    for block in msg.get("message", {}).get("content", []) or []:
        btype = block.get("type")
        if btype == "tool_use":
            name = block.get("name", "?")
            # ensure_ascii=False 讓中文輸入直接顯示，不被 escape 成 \uXXXX
            inp = truncate(
                json.dumps(block.get("input", {}), ensure_ascii=False),
                INPUT_PREVIEW,
            )
            print(f"[Tool: {name}] {inp}", flush=True)
        elif btype == "text":
            text = truncate(block.get("text", ""), TEXT_PREVIEW)
            if text:
                print(f"  > {text}", flush=True)


def handle_user(msg: dict) -> None:
    """處理 user 訊息：印出 tool_result（可能含錯誤）。"""
    for block in msg.get("message", {}).get("content", []) or []:
        if block.get("type") == "tool_result":
            preview = truncate(
                extract_tool_result_content(block.get("content", "")),
                RESULT_PREVIEW,
            )
            tag = "[ERR]" if block.get("is_error") else "[OK]"
            print(f"   {tag} {preview}", flush=True)


def handle_result(msg: dict) -> None:
    """處理 result 訊息：印出收尾總結（成本/輪數/subtype）。"""
    cost = msg.get("total_cost_usd", 0)
    turns = msg.get("num_turns", "?")
    sub = msg.get("subtype", "?")
    print(f"=== DONE [{sub}] (cost: ${cost}, turns: {turns}) ===", flush=True)


def process_line(line: str) -> bool:
    """解析並印出單行 JSONL；若此行為 result event 則回傳 True（session 完成）。

    回傳 True 表示呼叫端應停止讀取（session 已完結）。
    單行解析失敗時原樣印出，不中斷整個 stream。
    """
    line = line.strip()
    if not line:
        return False
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        # 非 JSON 行（例如 SDK 啟動時的 banner / system 訊息）原樣印
        print(line, flush=True)
        return False

    msg_type = msg.get("type")
    if msg_type == "assistant":
        handle_assistant(msg)
    elif msg_type == "user":
        handle_user(msg)
    elif msg_type == "result":
        handle_result(msg)
        return True  # 通知呼叫端 session 完成，可以停止讀取
    # system / 其他類型忽略（system 含 init/session info，太雜不印）
    return False


def poll_file(filepath: str) -> None:
    """直接對檔案做 polling 讀取，消除 tail -f | python 的 SIGPIPE deadlock。

    tail -f 只在嘗試寫新資料時才收到 SIGPIPE；若 claude session 結束後檔案
    再無新資料，tail 永遠不發 SIGPIPE、永遠不退出，pipeline 因此掛死。
    改用此函式直接讀檔，完全繞過 tail，根本消除 deadlock。

    idle_sec 超過 IDLE_TIMEOUT_SEC（120 秒）即視為 claude 異常中止，
    印診斷訊息後 sys.exit(1) 讓 shell 偵測到非零退出，觸發錯誤處理。
    """
    idle_increments = 0  # 每次 readline 空回傳累計次數
    max_idle_increments = int(IDLE_TIMEOUT_SEC / POLL_INTERVAL)

    try:
        with open(filepath, encoding="utf-8", errors="replace") as fh:
            while True:
                line = fh.readline()
                if not line:
                    # 沒有新資料：等一小段再試
                    idle_increments += 1
                    if idle_increments >= max_idle_increments:
                        print(
                            f"診斷：poll_file 已等待 {IDLE_TIMEOUT_SEC} 秒無新資料，"
                            "疑似 claude 子程序異常中斷，結束 parser。",
                            file=sys.stderr,
                            flush=True,
                        )
                        sys.exit(1)
                    time.sleep(POLL_INTERVAL)
                    continue
                # 有新資料：重置 idle 計數，避免短暫停頓被誤判為超時
                idle_increments = 0
                if process_line(line):
                    return  # result event 收到，正常完成，exit 0
    except OSError as exc:
        print(f"錯誤：無法開啟 {filepath}：{exc}", file=sys.stderr, flush=True)
        sys.exit(1)

    # 迴圈正常結束（EOF 但未收到 result event）= claude 崩潰或被 kill
    sys.exit(1)


def read_stdin() -> None:
    """讀 stdin JSONL 逐行解析（legacy 模式，供需要 pipe 的場景使用）。

    stdin 關閉但未收到 result event = claude 崩潰或被 kill，sys.exit(1)。
    """
    for line in sys.stdin:
        if process_line(line):
            return  # result event 收到，正常完成，exit 0

    # stdin 關閉但未收到 result event = claude 崩潰或被 kill
    sys.exit(1)


def main() -> None:
    """入口：若提供 sys.argv[1] 則走 poll_file 模式，否則走 stdin 模式。

    poll_file 模式（推薦）：
      python parse_claude_stream.py /path/to/output.jsonl
      消除 tail -f | python pipeline deadlock，claude session 結束後可立即退出。

    stdin 模式（legacy，僅在明確需要 pipe 時使用）：
      ... | python parse_claude_stream.py
    """
    if len(sys.argv) >= 2:
        poll_file(sys.argv[1])
    else:
        read_stdin()


if __name__ == "__main__":
    main()
