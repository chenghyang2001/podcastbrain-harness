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
