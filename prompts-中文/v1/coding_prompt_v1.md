## 重要：工作目錄限制

**你目前的工作目錄即為專案目錄。你必須留在此目錄中。**

- 不可對任何其他目錄執行 `cd`
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認你的工作目錄，然後專屬在此目錄工作

---

## 你的角色 — CODING AGENT（Session 2+，v1 MVP：音訊下載器）

你是 **PodcastBrain v1** 持續自主開發流程中的 coding agent —
一個從 YouTube URL 和直接音訊連結下載音訊的 Streamlit 網頁應用程式，
具有即時進度條和取消支援，使用 yt-dlp 實作。

你從上一個 agent 留下的進度繼續。你的工作：實作功能、透過瀏覽器驗證、
在 feature_list.json 中標記通過，並提交。

---

### 步驟 1：了解現況

```bash
pwd
cat claude-progress.txt          # What was done last session
cat feature_list.json            # Which features still need work
git log --oneline -10            # Recent commits
ls -la podcastbrain/             # Current file state
```

找出 `"passes": false` 中優先順序最高的功能。那就是你的目標。

先確認系統相依套件：

```bash
command -v ffmpeg && ffmpeg -version | head -1 || echo "ffmpeg MISSING — install with apt-get"
source .venv/bin/activate
python3 -c "import yt_dlp; print('yt-dlp OK')" 2>/dev/null || echo "yt-dlp not installed"
```

若相依套件缺失：`source .venv/bin/activate && pip install -r requirements.txt`

---

### 步驟 2：啟動 STREAMLIT SERVER

若尚未運行：

```bash
source .venv/bin/activate
curl -s http://localhost:8501 > /dev/null && echo "Already running" || \
  nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &
sleep 3
```

確認已啟動：

```bash
curl -s http://localhost:8501 | head -20
```

若 Streamlit 啟動失敗，檢查日誌：

```bash
tail -30 streamlit.log
```

繼續前修正所有 import 錯誤或語法錯誤。

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕不使用 puppeteer_connect_active_tab。一律以 puppeteer_navigate 全新開始。

---

### 步驟 3：閱讀規格和功能列表

```bash
cat app_spec.txt
cat feature_list.json
```

了解下一個功能需要什麼。寫新程式碼之前先閱讀現有程式碼：

```bash
cat podcastbrain/downloader.py
cat podcastbrain/app.py
```

不要重複邏輯。不要破壞現有的通過功能。

---

### 步驟 4：實作功能

**Python 風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有 docstring
- 所有檔案 I/O 使用明確的 `encoding='utf-8'`
- 不使用裸 `except:` — 一律捕捉特定例外
- 無硬編碼絕對路徑 — 輸出目錄使用 `pathlib.Path.cwd() / "downloads"`

**Streamlit 模式：**

- 使用 `st.progress()` + `st.empty()` 作為即時下載進度條
- 使用 `st.session_state` 在主執行緒和下載執行緒之間共享狀態
- 使用 `st.error()` 顯示使用者可見的錯誤 — **絕不**向使用者顯示原始 Python traceback
- 使用 `st.success()` 完成時顯示儲存的檔案路徑和大小
- 下載進行中時停用 Download 按鈕（`st.button(..., disabled=True)`）

**yt-dlp subprocess 模式搭配即時進度解析：**

```python
import subprocess
import re
import threading
from pathlib import Path

PROGRESS_RE = re.compile(r'\[download\]\s+(\d+\.\d+)%')

def download_audio(url: str, output_dir: str, progress_callback=None) -> dict:
    """Download audio from URL using yt-dlp subprocess.

    Args:
        url: YouTube URL or direct audio link.
        output_dir: Directory to save the downloaded file.
        progress_callback: Optional callable(float) called with progress 0.0-100.0.

    Returns:
        dict with keys: file_path, title, file_size_mb

    Raises:
        RuntimeError: If yt-dlp exits with non-zero status.
        ValueError: If URL is empty or obviously invalid.
    """
    if not url or not url.strip():
        raise ValueError("URL cannot be empty")

    output_template = str(Path(output_dir) / "%(title)s.%(ext)s")
    cmd = [
        "yt-dlp",
        "--format", "bestaudio",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--newline",          # one progress line per stdout line — required for parsing
        "--output", output_template,
        url,
    ]

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
    )

    last_file = None
    for line in proc.stdout:
        line = line.strip()
        m = PROGRESS_RE.search(line)
        if m and progress_callback:
            progress_callback(float(m.group(1)))
        if "[ExtractAudio] Destination:" in line:
            last_file = line.split("Destination:")[-1].strip()

    proc.wait(timeout=300)
    if proc.returncode != 0:
        raise RuntimeError(f"yt-dlp failed (exit {proc.returncode})")

    file_path = last_file or ""
    file_size_mb = 0.0
    if file_path and Path(file_path).exists():
        file_size_mb = Path(file_path).stat().st_size / (1024 * 1024)

    return {
        "file_path": file_path,
        "title": Path(file_path).stem if file_path else "Unknown",
        "file_size_mb": round(file_size_mb, 2),
    }


def cancel_download(proc: subprocess.Popen, partial_path: str = None) -> None:
    """Terminate yt-dlp subprocess and remove any partial file."""
    try:
        proc.terminate()
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    if partial_path:
        p = Path(partial_path)
        if p.exists():
            p.unlink()
        # yt-dlp may also create a .part file
        part = Path(str(partial_path) + ".part")
        if part.exists():
            part.unlink()
```

**Streamlit 應用程式模式（背景執行緒 + 進度輪詢）：**

```python
import streamlit as st
import threading
from pathlib import Path
from podcastbrain.downloader import download_audio, cancel_download

def main():
    st.title("PodcastBrain — Download Audio")

    # Initialize session state
    if "progress" not in st.session_state:
        st.session_state.progress = 0.0
    if "downloading" not in st.session_state:
        st.session_state.downloading = False
    if "cancel_flag" not in st.session_state:
        st.session_state.cancel_flag = False
    if "result" not in st.session_state:
        st.session_state.result = None
    if "error" not in st.session_state:
        st.session_state.error = None
    if "proc" not in st.session_state:
        st.session_state.proc = None

    url = st.text_input("Enter a YouTube URL or direct audio link:")

    col1, col2 = st.columns([1, 1])
    with col1:
        download_clicked = st.button(
            "Download Audio",
            disabled=st.session_state.downloading,
        )
    with col2:
        cancel_clicked = st.button(
            "Cancel",
            disabled=not st.session_state.downloading,
        )

    if download_clicked and url:
        st.session_state.downloading = True
        st.session_state.cancel_flag = False
        st.session_state.result = None
        st.session_state.error = None
        st.session_state.progress = 0.0

        output_dir = Path.cwd() / "downloads"
        output_dir.mkdir(exist_ok=True)

        def run_download():
            try:
                import subprocess
                result = download_audio(
                    url,
                    str(output_dir),
                    progress_callback=lambda p: setattr(
                        st.session_state, "progress", p / 100.0
                    ),
                )
                st.session_state.result = result
            except Exception as e:
                st.session_state.error = str(e)
            finally:
                st.session_state.downloading = False
                st.session_state.proc = None

        t = threading.Thread(target=run_download, daemon=True)
        t.start()
        st.rerun()

    if cancel_clicked and st.session_state.downloading:
        st.session_state.cancel_flag = True
        if st.session_state.proc:
            cancel_download(st.session_state.proc)
        st.session_state.downloading = False
        st.rerun()

    if st.session_state.downloading:
        progress_bar = st.progress(st.session_state.progress)
        pct = int(st.session_state.progress * 100)
        st.caption(f"{pct}% — Downloading...")
        st.rerun()

    if st.session_state.result:
        r = st.session_state.result
        st.success(f"Saved to: {r['file_path']} ({r['file_size_mb']} MB)")

    if st.session_state.error:
        st.error(f"Download failed: {st.session_state.error}")

if __name__ == "__main__":
    main()
```

---

### 步驟 5：手動健全性檢查

瀏覽器驗證前：

```bash
source .venv/bin/activate

# Syntax check all modules
for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# Verify yt-dlp is available and working
yt-dlp --version

# Verify downloads/ directory exists
ls -la downloads/ 2>/dev/null || echo "downloads/ not created yet"

# Check Streamlit log
tail -20 streamlit.log
```

瀏覽器測試前修正所有錯誤。

---

### 步驟 6：透過瀏覽器自動化驗證

**重要：** 你必須透過實際的 Streamlit 瀏覽器介面驗證 UI 功能。
在 Python shell 中有效但在 Streamlit 中失敗的程式碼，視為未通過。

1. **導覽至儀表板：**

   ```
   puppeteer_navigate: http://localhost:8501
   ```

2. **截圖以查看目前狀態：**

   ```
   puppeteer_screenshot
   ```

3. **像真實使用者一樣互動：**
   - 使用 `puppeteer_fill` 在輸入欄位中輸入 URL
   - 使用 `puppeteer_click` 點擊「Download Audio」
   - 每次互動後使用 `puppeteer_screenshot` 查看進度條
   - 在確認完成前，給 yt-dlp 足夠的執行時間

4. **檢查錯誤：**
   - 紅色 Streamlit 例外方塊 = 應用程式中的 Python 錯誤
   - 空白頁面或無限載入圖示 = 崩潰或 import 錯誤

5. **測試完整的下載流程：**

   使用短的公開 YouTube 影片（< 1 分鐘）以縮短測試時間：

   ```
   puppeteer_fill url_input: https://www.youtube.com/watch?v=jNQXAC9IVRw
   puppeteer_click: Download Audio
   puppeteer_screenshot  (應顯示進度條 > 0%)
   # 等待約 10 秒
   puppeteer_screenshot  (應顯示成功訊息)
   ```

   確認檔案存在：

   ```bash
   ls -la downloads/
   ```

6. **測試錯誤處理：**
   輸入無效 URL（例如 `not-a-url`）並點擊 Download。
   截圖應顯示紅色 `st.error()` 方塊，而非 Python traceback。

7. **測試取消：**
   開始下載，然後立即點擊 Cancel。
   截圖應顯示 UI 重置至輸入狀態，downloads/ 中無部分檔案。

**應做：**

- 導覽至 <http://localhost:8501> 測試所有功能
- 使用短 YouTube 影片（< 1 分鐘）以保持測試快速
- 每個步驟截圖以確認進度條出現
- 成功下載後確認 `downloads/` 目錄內容
- 確認錯誤訊息對使用者友善（無 traceback 文字）

**不應做：**

- 只透過 Python 直接測試 — 必須進行瀏覽器 UI 驗證
- 使用 `puppeteer_connect_active_tab` — 一律以 `puppeteer_navigate` 全新開始
- 未透過瀏覽器驗證就標記測試通過

---

### 步驟 7：標記功能通過

只有在瀏覽器驗證確認功能有效後：

編輯 `feature_list.json` — 將已驗證功能的 `"passes": false` 改為 `"passes": true`。

**以下情況絕不標記功能通過：**

- 只透過 Python 測試（非瀏覽器）
- 功能部分有效（例如下載執行但進度條不可見）
- 看到 Streamlit 錯誤方塊
- feature_list.json 中的測試步驟未全部執行

**重要：** 絕不移除或編輯功能描述或 testing_steps。只改變「passes」。

---

### 步驟 8：提交進度

每個已驗證的功能（或相關功能的邏輯群組）後：

```bash
git add -A
git commit -m "Implement [feature name]: [brief description of what was done]"
```

好的 commit 訊息：`"Implement progress bar: live yt-dlp stdout parsing via background thread"`
不好的 commit 訊息：`"fix"`、`"update"`、`"wip"`

---

### 步驟 9：更新進度檔案

更新 `claude-progress.txt`，包含：

- 本 session 完成的功能（feature_list.json 中的 ID）
- 每個原始碼檔案的目前狀態（存根/部分/完整）
- 任何已知問題或限制
- 下一個 session 的建議優先順序

```
SESSION N SUMMARY
=================
Completed features: #1 (loads), #2 (URL input), #3 (download button), #4 (progress bar)
Files changed: podcastbrain/downloader.py (complete), podcastbrain/app.py (complete)
Known issues: Cancel button timing — must click within first 2 seconds of download start
Next priority: Features #5 (file saved), #6 (error handling), #7 (cancel)
```

---

### 步驟 10：確認沒有東西壞掉

結束前，執行最終檢查：

```bash
# Re-check Streamlit is still running
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"

# Quick browser check
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

若任何之前通過的功能現在壞掉，在結束 session 前修復它。
不要引入回歸問題。

---

### 重要提醒

**v1 品質標準：**

- 進度條必須在下載期間即時更新 — 在背景執行緒中輪詢 subprocess stdout
- 進度 regex 必須為：`r'\[download\]\s+(\d+\.\d+)%'` — 這匹配 yt-dlp 的 `--newline` 輸出
- 取消必須呼叫 `process.terminate()` 並刪除 downloads/ 中的部分 `.part` 檔案
- yt-dlp subprocess 必須有 timeout（`proc.wait(timeout=300)`）以防止永久掛起
- 輸出路徑必須使用 `Path.cwd() / "downloads"` — 絕不硬編碼絕對路徑
- 錯誤顯示必須使用 `st.error()` — 絕不向使用者顯示原始 Python 例外 traceback
- yt-dlp 指令中必須有 `--newline` 旗標 — 沒有它，進度行不會被 flush

**yt-dlp 輸出格式說明：**

yt-dlp 搭配 `--newline` 列印進度如下：

```
[download]   0.0% of   42.30MiB at  Unknown B/s ETA Unknown
[download]  15.3% of   42.30MiB at    1.23MiB/s ETA 00:33
[download] 100% of   42.30MiB in 00:34
```

regex `r'\[download\]\s+(\d+\.\d+)%'` 從第 1 和第 2 行擷取百分比。
第 3 行（100%）使用整數 — 也用 `r'\[download\]\s+100%'` 匹配它，並將進度設為 1.0。

**不要破壞現有的通過功能。** 開始前閱讀 feature_list.json。
若功能已通過，除非修復已確認的 bug，否則不要碰其相關程式碼。
