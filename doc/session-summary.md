# PodcastBrain Harness — Session Summary（2026-05-28）

## 完成項目

### Phase 1：autonomous_cli_loop.sh 版本化

- 新增 `VERSION="${4:-v1}"` 第 4 個位置參數
- 加入 regex 驗證防止 path traversal（`^[a-zA-Z0-9_-]+$`）
- `PROMPTS_DIR` 改用 `$SCRIPT_DIR/prompts/$VERSION`
- 所有 3 個 prompt 檔名改用版本化命名：`initializer_prompt_${VERSION}.md` 等
- 修復 sed 執行順序 bug（preflight check 前不能引用 prompt 變數）
- 修復 tmpfile leak（加 `trap 'rm -f "$_INIT_PROMPT_TMP"' EXIT`）

### Phase 2：build-podcastbrain.yml 更新

- 新增 `version` input（default: `v1`）
- model default 從 `claude-sonnet-4-5` 改為 `claude-sonnet-4-6`
- 新增 Seed step：預置 `feature_list.json` / `requirements.txt` / `init.sh` 到 `generations/$PROJECT_NAME/`，跳過 initializer session
- 傳 `VERSION` 為第 4 引數給 harness

### Phase 3：CLAUDE_CREDENTIALS secret 修復

- CI run #26550041266 失敗：secret 有 trailing content（`Extra data: line 1 column 472`）
- 以 `json.dumps(data, separators=(',', ':'))` 輸出 compact JSON 重設 secret

### Phase 4：CI 成功驗證

- Run ID: `26550073708`
- 執行時間：46 分鐘（02:01 → 02:47 UTC）
- 結果：**PASSED: 8/8**（所有 PodcastBrain v1 features 通過）
- Artifact：`podcastbrain-app-6`（27.2 MB，16 files）
- Streamlit 在 CI 中正常啟動並由 Puppeteer 驗證

## 最終檔案狀態

| 檔案 | 狀態 | SHA256（部分）|
|------|------|--------------|
| `autonomous_cli_loop.sh` | complete | `2a244f94...` |
| `.github/workflows/build-podcastbrain.yml` | complete | `d7fb99f6...` |
| `feature_list.json` | pre-generated (8 features) | — |
| `requirements.txt` | pre-generated | — |
| `init.sh` | pre-generated | — |
| `prompts/v1/initializer_prompt_v1.md` | pre-existing | — |
| `prompts/v1/app_spec_v1.txt` | pre-existing | — |

## 已通過的 Features（8/8）

1. Streamlit app loads at port 8501 ✅
2. URL input field accepts YouTube watch URLs ✅
3. 'Download Audio' button is visible and clickable ✅
4. Progress bar increments from 0% to 100% during yt-dlp download ✅
5. Downloaded file appears in ./downloads/ with success message ✅
6. Invalid URL shows user-friendly error (not Python traceback) ✅
7. Cancel button stops download and removes partial file ✅
8. Style: single-page layout has no overflow at 1280px ✅

## 關鍵架構決策

- **Seed step pattern**：比 initializer session 快約 10–20 分鐘，適合已知 feature list 的固定版本
- **Versioned prompts**：未來 v2 只需新增 `prompts/v2/` 子目錄，harness 不需改動
- **Model slug**：`claude-sonnet-4-6`（無日期後綴），錯誤的 `claude-sonnet-4-6-20241022` 會讓 CI 失敗
