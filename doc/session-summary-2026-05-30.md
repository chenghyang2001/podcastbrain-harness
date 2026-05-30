# Session Summary — 2026-05-30

**主題**：Dynamic Workflow 演化版的定位、保存、視覺化，並建立 `wf-evolve` skill 把「演化化」能力產品化

---

## 完成事項

### 1. 定位並說明「dynamic workflow 演化版 JS」
- 找出使用者自建的演化版 workflow 腳本實體位置：`~/.claude/projects/C--Users-user-workspace-podcastbrain-harness/2c29bdf8-.../workflows/scripts/evolving-builder-demo-wf_5393fc77-fb5.js`（04:08 最終版，三支同名 run 中最新）
- 對照「一般 dynamic workflow」（`skills-consolidation-audit`）逐點說明差異：演化版多了 Append/Persist 兩段、外部 state 檔、APPEND diff、鎖 stable、index 對應、演化指標回傳；一般版則是無狀態、一次性 Scan→Synthesize

### 2. 演化版 JS 永久保存進 repo
- 從 session 暫存目錄複製到 `doc/dynamic-workflow-演化版-evolving-builder.js`（8633 bytes），檔頭加中文註解總結「一般 vs 演化」差異，每段演化邏輯標 `【演化新增】`
- 三重驗證：async-function-wrap 語法 parse + strip 註解 diff（程式碼與原檔逐行一致）+ 來源確認
- commit `2606f78`

### 3. mmd-gen-20：演化版 JS 的 20 種圖表合輯
- 以演化版 JS 為素材，4 個平行 subagent 各畫 5 張，產 20 mmd + 20 png + 1 pptx 到 `doc/dynamic-workflow-演化版-mmd20/`
- 桑基圖走 Pillow 降級（sankey-beta CJK parse error）；甘特/時間軸修全形冒號 parse 後成功；四象限 mmdc 直出未降級
- 抽驗 01 流程圖、17 桑基圖中文無亂碼、數據正確（v1 497k=80+380+37、v2 362k=120+210+32）
- commit `9060753`（42 檔）

### 4. 建立 `wf-evolve` user-level skill（skill-creator）
- 路徑：`~/.claude/skills/wf-evolve/`（SKILL.md 134 行 + references/evolving-builder-reference.js + references/transformation-rules.md + evals/evals.json 3 案例）
- 定位：source-to-source 轉換器，把任意一般 workflow JS 植入三不變量產出 `-演化版.js`
- 三決策：全自動分析 / 走三 agent 鐵律 / 輸出原檔同層 + `-演化版` 後綴
- 可攜性：reference JS 複製進 skill 自己的 references（不指向專案 repo）

### 5. wf-evolve smoke test（完整三 agent 鐵律實跑）
- 拿 `skills-consolidation-audit` 轉演化版，跑 code-writer → code-qa(PASS) → code-reviewer(CHANGES_REQUESTED) → 修 → code-qa Round2(PASS)
- **reviewer 抓到 2 個 QA 沒測到的真 bug**：(a) `.filter(Boolean)` 破壞 index 對應致 passes 錯位；(b) `passes:false` 群被永久跳過無法重試
- 修復後 Round2 QA 逐條確認（rawScans 不過濾 + fail-fast 斷言、lockedNames 只收 passes:true、newByName 去重、VERSION 必填檢查）
- 證明三 agent 鐵律的 adversarial review 確實攔下 happy-path 之外的缺陷

### 6. skill 自我強化
- 把 smoke test 暴露的 2 個陷阱補進 `transformation-rules.md` 踩坑表（+3 條：filter 破壞 index、passes:false 永久跳過、重試 name 重複）

---

## 關鍵技術筆記
- **workflow JS 語法驗證**：頂層 `return`/`await` 是 runtime 特性，裸 `node --check` 誤報 Illegal return。正確做法：`new Function("args","agent","parallel","pipeline","phase","log","return (async()=>{"+s+"})")` 包起來 parse
- **演化三不變量**：狀態外部化（state 檔）/ 冪等+APPEND-aware / 鎖 stable 只攻 new
- **index 對應鐵律**：merge 用 `rawScans[i]` 對 `toAdd[i]`，絕不在 fan-out 後接 `.filter(Boolean)`（會壓縮陣列致錯位）
- **dedup 只鎖 passes:true**：失敗項要能重試，dedup 鍵不可收全部 feats

## 產出檔案

| 檔案 | 說明 | 狀態 |
|---|---|---|
| `doc/dynamic-workflow-演化版-evolving-builder.js` | 演化版 JS 永久保存 + 差異註解 | commit 2606f78 |
| `doc/dynamic-workflow-演化版-mmd20/`（42 檔） | 20 mmd + 20 png + pptx | commit 9060753 |
| `~/.claude/skills/wf-evolve/`（4 檔） | 新 user-level skill | 待 ~/.claude commit |
| `…/scripts/skills-consolidation-audit-wf_cbc3ca28-0be-演化版.js` | smoke test 產物（265 行） | session 暫存目錄，不進 repo |

---

## HANDOFF（下次 session 優先處理）

### 立即行動
- [ ] 確認 wf-evolve skill 已隨本 session Phase 4 commit 進 ~/.claude repo（4 檔）
- [ ] （可選）把 smoke test 產出的演化版 JS 複製進 `wf-evolve/references/` 當真實 before/after 範例
- [ ] （可選）對 wf-evolve 跑 skill-creator 的正式 eval（generate_review.py），目前只做了結構驗證 + 1 次 smoke test

（註：本專案 MEMORY.md 已於本 session Phase 2 由 Memory Keeper 首建，72 行）

### 進行中（需接續）
- wf-evolve skill 已可用並通過 smoke test，但 evals.json 的 case 2/3（已是演化版偵測、無 fan-out 降級）尚未實跑驗證

### 注意事項
- 本專案無 `summary-02-sessions/` 與專案 MEMORY.md，summary 沿用既有慣例 `doc/session-summary-YYYY-MM-DD.md`
- wf-evolve 在 `~/.claude/skills/`（全域），不在本專案 repo；要保存需 commit ~/.claude repo
- 本週 usage 已超標（170MB+），smoke test 三 agent 鐵律耗用較多 token
