# PodcastBrain Harness — Session 摘要 2026-05-28

## 本 Session 完成事項

### 1. CI/CD End-to-End 驗證成功
- **CI Run #8** (`26554469815`)：build PASS (25m32s) + deploy PASS (31s)
- Health check：`VPS HTTP status: 200` ✅
- VPS：`http://187.127.109.145:8501` 正常服務

### 2. 本 Session 修復的 Bug

| Bug | 根本原因 | 修復 commit |
|-----|---------|------------|
| SSH key 無法載入（libcrypto 錯誤） | `printf '%s'` 沒有尾端 `\n`，OpenSSH PEM 格式需要 `\n` | `b2d486b` |
| yt-dlp 找不到（Errno 2） | systemd subprocess 的 PATH 不含 venv，需要 system binary | `cd75504` |

**正確的 SSH key 寫法：**
```bash
printf '%s\n' "$VPS_SSH_KEY" | tr -d '\r' > ~/.ssh/vps_key
# 加 \n（PEM 格式需要）、去 \r（Windows CRLF）
```

**yt-dlp 正確安裝方式：**
```bash
sudo curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp && sudo chmod a+rx /usr/local/bin/yt-dlp
# 安裝到 /usr/local/bin 讓 systemd subprocess 可以找到
```

---

## 架構討論：V1 → V2 → V5 升級策略

### 問題一：能用 v5 prompts + v1 app_spec 嗎？

**答：不行。** 三個原因：
1. v5 initializer 硬寫產 **30 個測試**，v1 只有 1 個 feature → 測試案例無效
2. `feature_list.json` 只產生一次，之後切換 app_spec 也不會重新產生
3. v5 coding prompt 假設 `plotly`、`db.py`、`analyzer.py` 等模組已存在

### 問題二：正確的增量升級方式

每個版本獨立 `project_name`，透過 `init.sh` 把前一版程式碼作為種子：

```
pb_v1（8 tests）   → seed init.sh 複製 v1 code →
pb_v2（14 tests）  → seed init.sh 複製 v2 code →
pb_v3（N tests）   → ...
```

**關鍵：每個版本的 feature_list 包含所有前版本測試 + 新測試（向後相容性保證）**

---

## 架構討論：Harness 在真實專案開發的限制

### 目前 Harness 的三個根本限制

1. **feature_list.json 不可變** — initializer 跑完後鎖死，無法 append 新功能
2. **無 stable feature 保護** — coding agent 可能破壞已通過的功能
3. **無 regression 機制** — 沒有自動回滾破壞既有功能的變更

### Harness 元件 vs 真實開發等效物

| Harness | 真實開發 |
|---------|---------|
| `feature_list.json` | GitHub Issues / Jira / 驗收條件 |
| initializer agent | PM + 技術 lead 寫規格 |
| coding agent | 開發者 + PR review |
| `passes: true/false` | CI 測試通過/失敗 |
| seed（init.sh 複製程式碼） | git branch 從 main checkout |

### 讓 Harness 支援真實增量開發需要的修改

**修改 1：feature_list 支援 append + status 欄位**
```json
{ "id": 1, "feature": "...", "passes": true,  "status": "stable", "version_added": "v1" }
{ "id": 9, "feature": "...", "passes": false, "status": "new",    "version_added": "v2" }
```

**修改 2：coding agent 加 stable feature 保護規則**
- `status=stable` 且 `passes=true` → 不得修改相關程式碼
- `status=new` 且 `passes=false` → 這才是目標

**修改 3：evolution initializer（讀現有 feature_list → append 新 feature）**

**修改 4：harness loop 加 regression check**
```bash
run_regression_tests()
if any_stable_feature_broken: revert_last_commit()
```

### 一句話結論

> 目前 Harness 是「生成工具」，不是「維護工具」。
> 真實專案需要 evolution mode：append feature_list + regression 保護 + stable feature 鎖定。

---

## 關鍵數字

| 項目 | 值 |
|------|---|
| VPS | 187.127.109.145:8501 |
| 最新通過 CI Run | 26554469815 |
| V1 features | 8/8 PASS |
| 最新 commit | `cd75504` |

