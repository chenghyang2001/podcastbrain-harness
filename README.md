# PodcastBrain — Autonomous Coding Harness

把 Podcast / YouTube 影片轉成結構化知識資產。由 Claude 自主編碼 harness 全自動建構。

## 技術棧

- Python 3.11+ / Streamlit (port 8501)
- yt-dlp（音頻下載）
- OpenAI Whisper（本地轉錄）
- Anthropic Claude `claude-sonnet-4-6`（章節分析 / 摘要 / Q&A）
- SQLite + FTS5（全文搜尋）

## 快速啟動（VPS / Linux）

```bash
# 前提：已安裝 claude CLI（npm install -g @anthropic-ai/claude-code）

DISABLE_WRITER_QA_HOOK=1 nohup bash autonomous_cli_loop.sh podcastbrain_run1 30 5 \
  > /tmp/podcastbrain_run1.log 2>&1 &

echo "PID: $!"
tail -f /tmp/podcastbrain_run1.log
```

## 參數說明

| 參數 | 預設 | 說明 |
|------|------|------|
| `$1` | `cli_demo` | 專案名稱（outputs 到 `generations/$1/`）|
| `$2` | `30` | coding 迴圈最大迭代數 |
| `$3` | `5` | 端對端測試案例數 |

## 注意事項

- 使用 OAuth 訂閱模式（不需要 `ANTHROPIC_API_KEY`，走 Max 訂閱額度）
- `DISABLE_WRITER_QA_HOOK=1` 必設（防止全域三 agent 鐵律 hook 攔截巢狀寫檔）
- 生成的 App 位於 `generations/podcastbrain_run1/`
- App 啟動後可在 VPS `http://<VPS_IP>:8501` 瀏覽
