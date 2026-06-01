# PodcastBrain Harness — Session 摘要 2026-05-29

## 本 Session 完成事項

### 1. 建立 `prompts/v1-演化版/`：harness 從「生成器」升級為「演化器」

依據三份分析素材（`AI_Framework_Evolution.pdf` 14 頁簡報 + `AI_程式編寫代理：從生成到演化.mp4` + `AI寫程式為何一改就崩潰.m4a`），把 v1 三個 prompt 升級為支援「替換 app_spec 後仍能增量演化」的版本。

**核心問題（PDF 診斷 #2）**：目前 `feature_list.json` 是一次性產物——「Harness 發現 JSON 已存在 → 直接跳過 Initializer」→ 換上 v2 spec 後新功能永遠不會被實作。

**使用者收斂後的需求**：只要 harness 在換上修改過的 `app_spec.txt`（例如 `app_spec_v2.txt`）後仍能運作，其餘維持原樣，純 additive 不重寫。

### 2. 三檔升級內容（對應 PDF 4 支柱）

| 檔案 | 新增內容 | 支柱 |
|------|---------|------|
| `app_spec_v1.txt` | feature 加 `status` + `version_added` 欄位、新增 `<evolution_note>`（演化模型 + 黃金守則） | 支柱 1 |
| `initializer_prompt_v1.md` | **Step 1A Mode Detection**：CREATE/APPEND 雙模式、增量 append 鐵律、時空錯亂防護、schema 升級、結尾驗證更新 | 支柱 1 + 3 |
| `coding_prompt_v1.md` | **STEP 1.5 紅綠燈護欄**（鎖 stable、攻 new）、**STEP 7.5 輕量迴歸檢查** | 支柱 2 + 4（輕量） |

### 3. 關鍵設計決策

- **迴歸保護用「輕量檢查」而非完整自動 revert**：跑舊測試 → 壞了用 `git checkout` 局部還原（保留新功能進度），而非 PDF 的全自動 `revert_last_commit()`。使用者明確選輕量版（符合「不要過度」）。
- **APPEND 模式設計成冪等**：沒有新功能就不動檔案，可安全反覆重跑 initializer。
- **防作弊條款**：明文禁止「把壞掉的 stable 功能 passes 翻回 false 騙綠燈」（PDF 的「拆東牆補西牆」）。
- **遵循專案既有慣例**：session summary 放 `doc/session-summary-YYYY-MM-DD.md`（非 skill 預設的 `summary-02-sessions/`）。

### 4. Git 與素材處理

- 大型素材檔（mp4 53MB + m4a 48MB + pdf 8.4MB）加進 `.gitignore`，只提交 3 個 prompt 檔，維持 repo 輕量。
- `git check-ignore` 驗證忽略規則生效。

## 關鍵技術筆記

- **Evolution Mode 的兩個狀態欄位**：`status`（`new`/`modified`/`stable`）+ `version_added`（`v1`/`v2`…）。stable+passes=true = 紅燈鎖死；passes=false = 綠燈施工。
- **冪等增量是關鍵**：Initializer 偵測 `feature_list.json` 存在 → 進 APPEND 模式（讀舊+讀新 spec→只附加），而非跳過或覆寫。
- **時空錯亂防護**：明文禁止在早期版本測試尚未存在的高階模組（PDF 診斷 #3），避免 coding agent 陷入死循環。

## 產出檔案

| 檔案 | 動作 | 說明 |
|------|------|------|
| `prompts/v1-演化版/app_spec_v1.txt` | 修改 | 加 schema 欄位 + evolution_note |
| `prompts/v1-演化版/coding_prompt_v1.md` | 修改 | 紅綠燈護欄 + 輕量迴歸 |
| `prompts/v1-演化版/initializer_prompt_v1.md` | 修改 | CREATE/APPEND 雙模式 |
| `.gitignore` | 修改 | 排除 3 個大型素材檔 |

**Commit**：`b291592`（4 files changed, 1024 insertions）已 push 到 `master`。

---

## HANDOFF（下次 session 優先處理）

### 立即行動

- [ ] 端對端實測演化流程：用 v1 spec 跑出 8 個 stable 功能 → 把 `app_spec.txt` 換成含新功能的 v2 內容 → 重跑 initializer，確認進 APPEND 模式只附加不重置
- [ ] 視測試結果決定是否準備 `app_spec_v2.txt` 範例（如加 Whisper 轉錄 + SQLite）
- [ ] 若演化版驗證 OK，考慮把同樣的 Evolution Mode 改動回填到原始 `prompts/v1/`（目前只有演化版有）

### 進行中（需接續）

- 演化版 3 個 prompt 已完成並 push，但**尚未實際跑過 CI/CD 驗證**——目前只有靜態 schema 語法檢查（JSON schema OK）通過。

### 注意事項

- 此專案 session summary 慣例是 `doc/session-summary-YYYY-MM-DD.md`，**不是** skill 預設的 `summary-02-sessions/`。
- `.claude/session-state.md` 是 harness 自動維護檔，每次互動會變動，刻意不納入功能 commit。
- 演化版的迴歸保護是「輕量檢查」設計（非自動 revert），若未來要升級成完整 Regression Protection 需另外改 `coding_prompt`。
- 素材檔（mp4/m4a/pdf）只在本機 `prompts/v1-演化版/`，已被 gitignore，不在 repo。

---

# Session 2（同日下午）— VPS Demo + v1→v2 演化實戰

> 上午設計了演化版 prompt（尚未實跑驗證）；本 session 把它**部署到 VPS 實際跑**，端對端驗證了「v1 生成 → v2 演化」整條鏈，並補了一套進度監看/瀏覽工具。

## 完成事項

### 1. 把 harness 部署到 VPS 並跑出 v1（8/8）
- VPS 新資料夾 `/home/claude/podcastbrain-demo/`，放 driver（`autonomous_cli_loop.sh`）、parser（`scripts/parse_claude_stream.py`）、3 個 v1-演化版 prompt（置於 `prompts/v1/`，因 VERSION 參數只允許英數，中文「v1-演化版」會被擋）。
- **port 隔離**：正式版 podcastbrain 佔用 8501，demo 全程 patch 成 **8502**，互不干擾。
- 跑 `autonomous_cli_loop.sh podcastbrain_demo 6 8 v1` → initializer（CREATE MODE）scaffold + 2 個 coding session 建完 → **v1 8/8 全通過**（streamlit 8502 UP）。

### 2. v1 → v2 演化（APPEND MODE，16/16 全通過）
完整「如何基於 v1 foundation 建 v2」步驟（已實證）：
1. 複製 `app_spec_v2.txt` → VPS（port patch 8502）
2. swap 專案 `app_spec.txt` 成 v2 內容（`feature_list.json` 保留）
3. **手動跑 APPEND initializer**（關鍵：loop 偵測 `feature_list.json` 已存在會「跳過」initializer，演化必須手動觸發這步）→ feature_list 8→16（v1 鎖 stable、v2 #9-16 append 為 new）
4. API key 放專案 `.env`（不 export → 驅動 harness 的 claude CLI 仍走免費 Max）
5. coding prompt append v2 指引（dotenv 讀 key / whisper tiny + 19 秒短片 / 裝依賴 / port 8502）
6. 讓 loop 來源 spec = v2（`cp app_spec_v2.txt app_spec_v1.txt`，避免重跑覆蓋回 v1），跑 coding 迴圈
→ **1 個 coding session 建完 8 個 v2 功能，16/16 全通過**；紅綠燈護欄守住 v1 #1-8 未被破壞。
- v2 app 實裝：SQLite 持久化、本地 Whisper 轉錄、Claude 章節偵測、sidebar nav（Process New/My Episodes）、檔案上傳、Transcript/Chapters 雙 tab、My Episodes 列表。
- 截圖驗證 v2 UI 全到位（透過 SSH local forward 8502 在本機瀏覽器確認）。

### 3. 產出的 helper 工具（已入庫 podcastbrain-harness）
- `watch-demo.bat` — 串流監看（`ssh + tail -f loop.log`，append 不清屏 + 斷線重連）
- `progress.sh` — VPS 端一次性快照儀表板（feature 通過數/git/log/進程/streamlit 狀態）
- `tunnel-8502.bat` — SSH local forward（本機 8502→VPS 8502）讓瀏覽器看 demo app

## 踩坑與修復（3 個跨平台 + 2 個 QA 盲點）
- **CRLF/LF 行尾方向相反**：Windows repo 的 `.sh` 帶 CRLF 在 Linux bash 炸（`set: pipefail: invalid option`）→ VPS 端轉 LF；`.bat` 帶 LF 在 Windows goto 可能失效 → 轉 CRLF。同一 repo 跨 Win↔Linux 同步，行尾需求相反。
- **VERSION 含中文被正規表達式擋** → demo 用 `v1` 標籤夾、內容是 v1-演化版。
- **progress.sh 計數 bug**：parser 漏判真實 key `"passes"`（只猜了 passed/pass/status）→ 全通過時誤印 0/8。QA 盲點：首次 QA 在「0 通過」狀態驗，一個「永遠回傳 0」的壞 parser 剛好吻合預期值假性 PASS（**測試 oracle 巧合**）。修法是在真實 8/8 狀態回歸驗證。
- **tunnel-8502.bat 用 `>/dev/null`（Unix）而非 `>nul`（Windows cmd）**。QA 盲點：動態測試在 git bash/Linux 跑，沒在 cmd.exe 實際執行那行 → **測試環境≠目標執行環境**。
- **pgrep/pkill `-f` pattern 自我匹配**：SSH 遠端 shell 的 cmdline 含 pattern 字串 → 匹配到自己 → kill 殺掉 SSH（exit 255）。「仍有殘留」是假陽性。

## 關鍵事實（給接續 session）
- VPS demo：`/home/claude/podcastbrain-demo/`；專案 `generations/podcastbrain_demo/`（獨立 git repo）
- port：8501=正式版（勿動）、8502=demo
- API key：在 `generations/podcastbrain_demo/.env`（已 gitignore，權限 600），app 用 `load_dotenv` 讀，claude CLI 環境無此 key（維持 Max）
- 監看：`bash /home/claude/podcastbrain-demo/progress.sh` 或本機 `watch-demo.bat`
- 成本：claude CLI 全程走 Max（$0），唯一 API credits 是 v2 章節偵測幾次呼叫（約幾分錢）

## 下一步（明天接續）— 演化到 v3
`app_spec_v3.txt` 已在 VPS（`prompts/v1/app_spec_v3.txt`，需先 port patch 8502）。依今日 v2 同一手法：
1. `cp prompts/v1/app_spec_v3.txt → app_spec_v3.txt` 並 `sed 8501→8502`
2. swap 專案 `app_spec.txt` 成 v3
3. 手動跑 APPEND initializer → feature_list 16→更多（v1+v2 鎖 stable、v3 append）
4. 視 v3 spec 補 coding prompt 指引（新依賴/新 env）
5. `cp app_spec_v3.txt app_spec_v1.txt`（loop 來源=v3），跑 coding 迴圈
6. watch-demo.bat 看進度，跑完截圖驗證
（先讀 `app_spec_v3.txt` 確認 v3 新增什麼功能、需不需要額外 API/依賴/env。）
