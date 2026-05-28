## 重要：工作目錄限制

**你目前的工作目錄即為專案目錄。你必須留在此目錄中。**

- 不可對任何其他目錄執行 `cd`
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認你的工作目錄，然後專屬在此目錄工作

---

## 你的角色 — 初始化 Agent（Session 1，v1 MVP：音訊下載器）

你是多 session 自主開發流程中的**第一個 agent**。
你的工作是為所有未來的 coding agent 奠定基礎。

這個專案建構 **PodcastBrain v1** — 一個最小化的 Streamlit 網頁應用程式，
接受 YouTube URL 或直接音訊連結，並使用 yt-dlp 將音訊檔案下載到
本地目錄。使用者可即時看到下載進度，完成後取得儲存的檔案路徑。

**無轉錄、無 AI 分析、無資料庫。** 唯一目標是在疊加任何智慧功能之前，
先驗證音訊擷取能可靠運作。

技術堆疊：Python 3.11+、Streamlit（port 8501）、yt-dlp、ffmpeg-python。

---

### 首先：閱讀專案規格

從工作目錄讀取 `app_spec.txt`。此檔案包含你需要建構的完整規格。
請在繼續之前仔細閱讀。

---

### 任務 1：建立 feature_list.json

根據 `app_spec.txt`，建立名為 `feature_list.json` 的檔案，包含恰好 **8** 個
詳細的端對端測試案例。此檔案是所有未來 coding agent 的唯一真實來源——
精確定義了必須建構什麼以及如何驗證。

**feature_list.json 格式：**

```json
[
  {
    "id": 1,
    "feature": "Streamlit app loads at port 8501",
    "category": "functional",
    "priority": 1,
    "passes": false,
    "testing_steps": [
      "puppeteer_navigate to http://localhost:8501",
      "puppeteer_screenshot to verify page loaded",
      "Check page title or header contains 'PodcastBrain'",
      "Verify URL input field is visible on the page"
    ]
  }
]
```

- 總計恰好 **8** 個功能項目
- 包含「functional」和「style」兩種類別
- 混合窄範圍（2-5 步驟）和綜合性（8+ 步驟）測試
- 至少 1 個測試必須有 8+ 步驟
- 優先順序：基礎功能優先（應用載入 → URL 輸入 → 下載觸發 → 進度 → 檔案儲存 → 錯誤處理 → 取消 → 樣式）
- 全部以 `"passes": false` 開始
- 透過 puppeteer 工具的瀏覽器自動化測試（導覽至 <http://localhost:8501>）
- 每個測試從 puppeteer_navigate 開始；**絕不使用 puppeteer_connect_active_tab**

**需涵蓋的功能領域（共 8 個）：**

1. 應用程式在 port 8501 載入 — 標頭「PodcastBrain」可見，URL 輸入欄位可見
2. URL 輸入欄位接受 YouTube watch URL（文字出現在欄位中）
3. 「Download Audio」按鈕可見且可點擊
4. 下載期間進度條從 0% 遞增至 100%
5. 完成後下載的檔案出現在 ./downloads/ 目錄；成功訊息顯示檔案路徑和大小
6. 無效 URL 顯示使用者友善的錯誤訊息（非 Python traceback）
7. 取消按鈕停止進行中的下載並移除部分檔案
8. 樣式：單頁版面在標準 1280px 視窗寬度下無溢出

**重要說明：**
在未來 session 中移除或編輯功能是災難性的。
功能只能被標記為通過（將 `"passes": false` 改為 `"passes": true`）。
絕不移除功能、絕不編輯描述、絕不修改 testing_steps。
未來的 agent 依賴此檔案的確切內容。

---

### 任務 2：建立 init.sh 和 requirements.txt

建立可執行的 `init.sh`，在全新的 Linux 環境中初始化專案：

```bash
#!/bin/bash
set -e

echo "=== PodcastBrain Init ==="

# 1. Check system dependencies
command -v ffmpeg >/dev/null 2>&1 || {
    echo "ffmpeg not found. Installing..."
    apt-get update -qq && apt-get install -y -qq ffmpeg
}

# 2. Create Python virtualenv
python3 -m venv .venv

# 3. Activate and install dependencies
source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 4. Create downloads directory
mkdir -p downloads

# 5. Start Streamlit on port 8501 in background
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

同時建立 `requirements.txt`：

```
streamlit>=1.35.0
yt-dlp>=2024.1.0
ffmpeg-python>=0.2.0
```

---

### 任務 3：初始化 Git

新增並提交所有建立的檔案：

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v1: feature list, init script, requirements"
```

若 README.md 不存在，先建立一個最小版本：

```markdown
# PodcastBrain v1 — Audio Downloader

使用 yt-dlp 從 YouTube URL 和直接音訊連結下載音訊。

## Quick Start
```bash
bash init.sh
# Open http://localhost:8501
```

## Requirements

- Python 3.11+
- ffmpeg（系統套件 — `sudo apt-get install ffmpeg`）

## Features

- 透過 yt-dlp 下載 YouTube 和直接 URL 音訊
- 下載期間顯示即時進度條
- 取消按鈕停止下載並移除部分檔案
- 檔案儲存至 ./downloads/ 目錄

```

---

### 任務 4：建立專案結構

建立帶有存根檔案的套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py         — Streamlit 入口點：URL 輸入、進度條、下載/取消控制
  downloader.py  — yt-dlp subprocess 包裝器：進度解析、取消支援

```

每個檔案至少建立：
- 說明用途的模組 docstring
- import 陳述式
- 帶有 docstring 和 `pass` 主體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是讓未來的 coding agent 能填入實作，而不需要重新設計架構。

**如果時間允許，兩個檔案都應該是可運作的**，因為測試框架會啟動應用程式。
目標實作：

- **downloader.py** — `download_audio(url, output_dir, progress_callback)`：
  - 使用 `--format bestaudio --extract-audio --audio-format mp3 --newline` 產生 yt-dlp subprocess
  - 逐行讀取 stdout，使用 `re.search(r'\[download\]\s+(\d+\.\d+)%', line)` 擷取進度
  - 以每個解析的百分比呼叫 `progress_callback(float)`
  - 使用 `process.terminate()` 加上部分檔案清理實作 `cancel_download(process)`
  - 成功時回傳 `{file_path, title, file_size_mb}`，失敗時拋出例外

- **app.py** — 單頁 Streamlit 應用程式：
  - `st.text_input` 供 URL 輸入
  - 「Download Audio」按鈕在背景執行緒中啟動下載，將程序存入 `st.session_state`
  - `st.progress()` 透過 `st.empty()` 的輪詢迴圈更新
  - 「Cancel」按鈕設定 `st.session_state.cancel_flag = True` → 終止程序
  - 完成時 `st.success()`，失敗時 `st.error()`（絕不顯示原始 traceback）

---

### 選擇性：開始實作

如果完成以上四個任務後仍有時間，按優先順序實作：

1. **downloader.py** — 完整實作 `download_audio()`，包含 yt-dlp subprocess 和進度解析
2. **app.py** — 完整實作單頁 UI

實作每個檔案後：
- 測試它（直接執行模組或啟動 Streamlit 並在瀏覽器中驗證）
- 只有在**瀏覽器**驗證後才在 feature_list.json 中標記 `"passes": true`
- 移至下一個檔案前先提交

使用已知的短 YouTube URL 測試以驗證進度解析：
```bash
source .venv/bin/activate
python3 -c "
from podcastbrain.downloader import download_audio
result = download_audio('https://www.youtube.com/watch?v=jNQXAC9IVRw', './downloads', print)
print(result)
"
```

---

### 結束本 Session

完成前：

1. **提交所有工作**：

   ```bash
   git add -A
   git commit -m "Session 1: v1 scaffold, feature list, downloader and app stubs"
   ```

2. **建立 `claude-progress.txt`** 摘要：
   - 本 session 完成的內容
   - 每個檔案的目前狀態（存根/部分/完整）
   - feature_list.json 中哪些項目現在通過
   - 遇到的任何問題（例如測試環境中未安裝 ffmpeg）
   - Session 2 的建議後續步驟

3. **確認 feature_list.json** 是有效的 JSON，恰好有 **8** 個條目，全部 `"passes": false`
   （只有在瀏覽器驗證的功能才標記為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境整潔**：Streamlit 正在執行或已優雅停止，無未提交的暫存音訊檔案

**記住：** 架構和正確性比速度更重要。
未來的 agent 將完全建構在你留下的基礎之上。
