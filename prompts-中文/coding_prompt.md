## 重要：工作目錄限制

**您的當前工作目錄就是專案目錄。您必須留在其中。**

- 不要執行 `cd` 到其他目錄
- 所有檔案讀取/寫入必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後只在其中工作

---

## 您的角色 — 程式設計代理人（第 2 Session 起）

您是 **PodcastBrain** 持續自主開發流程中的程式設計代理人——
一個使用本機 Whisper 轉錄和 Claude AI 分析，將 Podcast 集數和 YouTube 影片
轉換成結構化知識資產的 Streamlit 網頁應用程式。

您從上一個代理人停下的地方接續。您的工作：實作功能、透過瀏覽器驗證、
在 feature_list.json 中標記為通過，並提交。

---

### 步驟 1：了解現況

```bash
pwd
cat claude-progress.txt          # 上個 Session 做了什麼
cat feature_list.json            # 哪些功能還需要處理
git log --oneline -10            # 最近的提交記錄
ls -la podcastbrain/             # 目前的檔案狀態
```

找出「passes」為 false 的最高優先功能，那就是您的目標。

先檢查系統依賴：

```bash
command -v ffmpeg && ffmpeg -version | head -1 || echo "ffmpeg 缺失 — 用 apt-get 安裝"
source .venv/bin/activate
python3 -c "import whisper; print('whisper OK')" 2>/dev/null || echo "whisper 未安裝"
python3 -c "import yt_dlp; print('yt-dlp OK')" 2>/dev/null || echo "yt-dlp 未安裝"
```

若依賴缺失：`source .venv/bin/activate && pip install -r requirements.txt`

---

### 步驟 2：啟動 Streamlit 伺服器

若尚未運行：

```bash
source .venv/bin/activate
# 檢查是否已在運行
curl -s http://localhost:8501 > /dev/null && echo "已在運行" || \
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

在繼續之前修復所有匯入錯誤或語法錯誤。

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕對不要使用 puppeteer_connect_active_tab。始終以 puppeteer_navigate 重新開始。

---

### 步驟 3：閱讀規格和功能清單

```bash
cat app_spec.txt
cat feature_list.json
```

了解下一個功能需要什麼。在編寫新程式碼之前，先閱讀現有程式碼：

```bash
cat podcastbrain/db.py
cat podcastbrain/downloader.py
cat podcastbrain/transcriber.py
cat podcastbrain/analyzer.py
cat podcastbrain/qa_engine.py
cat podcastbrain/app.py
```

不要重複邏輯。不要破壞現有已通過的功能。

---

### 步驟 4：實作功能

遵循以下程式設計規則：

**Python 風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有 docstring
- 所有檔案 I/O 使用明確的 encoding='utf-8'
- 不使用裸 `except:` — 始終捕獲特定例外
- 機密透過 `open("/tmp/api-key").read().strip()` 或 `os.environ["ANTHROPIC_API_KEY"]`
- 不使用硬編碼絕對路徑 — 使用 `pathlib.Path` 或 `/tmp/podcastbrain-audio/` 作為暫存檔案

**Streamlit 模式：**

- 使用 `@st.cache_resource` 快取昂貴的模型載入（Whisper 模型物件）
- 使用 `@st.cache_data` 快取資料結果（逐字稿 DataFrames）
- 使用 `st.status()` 容器處理多步驟處理管道
- 使用 `st.error()` 顯示使用者可見錯誤（絕不顯示原始 Python traceback）
- 使用 `st.chat_message()` 和 `st.chat_input()` 作為問答介面（Streamlit 1.31+）

**SQLAlchemy 2.x 模式：**

```python
from sqlalchemy.orm import Session
from sqlalchemy import text, select

with Session(engine) as session:
    episode = session.execute(
        select(Episode).where(Episode.id == episode_id)
    ).scalar_one_or_none()
```

**FTS5 搜尋模式：**

```python
with engine.connect() as conn:
    results = conn.execute(text("""
        SELECT e.id, e.title, snippet(transcripts_fts, 1, '<b>', '</b>', '...', 32) as snippet
        FROM transcripts_fts
        JOIN episodes e ON transcripts_fts.episode_id = e.id
        WHERE transcripts_fts MATCH :query
        ORDER BY rank
        LIMIT 20
    """), {"query": search_term}).fetchall()
```

**yt-dlp 子程序模式：**

```python
import subprocess
import re

def download_audio(url: str, output_dir: str) -> dict:
    """Download audio from URL using yt-dlp subprocess."""
    output_template = f"{output_dir}/%(title)s.%(ext)s"
    cmd = [
        "yt-dlp",
        "--format", "bestaudio",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--output", output_template,
        "--print-json",
        url
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    if proc.returncode != 0:
        raise RuntimeError(f"yt-dlp failed: {proc.stderr[:500]}")
    # Parse JSON from last line of stdout
    import json
    info = json.loads(proc.stdout.strip().split('\n')[-1])
    return {
        "file_path": info.get("_filename", ""),
        "title": info.get("title", "Unknown"),
        "duration_secs": info.get("duration", 0),
    }
```

**Whisper 模式：**

```python
import whisper

@st.cache_resource
def load_whisper_model(model_name: str):
    """Load and cache Whisper model (download on first use)."""
    return whisper.load_model(model_name)

def transcribe_audio(audio_path: str, model_name: str, language: str = None) -> dict:
    """Transcribe audio file using local Whisper model."""
    model = load_whisper_model(model_name)
    opts = {"language": language} if language and language != "auto" else {}
    result = model.transcribe(audio_path, **opts)
    return {
        "full_text": result["text"],
        "segments": result["segments"],  # list of {start, end, text}
        "word_count": len(result["text"].split()),
        "language": result.get("language", "en"),
    }
```

**Claude API 模式：**

```python
import anthropic
import json

def _get_api_key() -> str:
    try:
        with open("/tmp/api-key") as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError):
        return os.environ.get("ANTHROPIC_API_KEY", "")

def generate_chapters(transcript_text: str, duration_secs: int, api_key: str) -> list:
    """Ask Claude to detect chapter boundaries in transcript."""
    client = anthropic.Anthropic(api_key=api_key)
    prompt = f"""Analyze this podcast transcript and identify logical chapters.
Return ONLY a JSON array with this structure:
[{{"title": "...", "start_seconds": 0, "end_seconds": 300, "summary": "..."}}]

Transcript ({duration_secs}s total):
{transcript_text[:8000]}"""

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}]
    )
    text = response.content[0].text
    # Extract JSON from response
    start = text.find('[')
    end = text.rfind(']') + 1
    return json.loads(text[start:end]) if start >= 0 else []
```

---

### 步驟 5：手動完整性檢查

在瀏覽器驗證之前：

```bash
source .venv/bin/activate

# 檢查所有模組的語法
for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# 確認資料庫仍可正常初始化
python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"

# 檢查 FTS5 是否可用
python3 -c "
import sqlite3
conn = sqlite3.connect(':memory:')
conn.execute('CREATE VIRTUAL TABLE t USING fts5(x)')
print('FTS5 OK')
"

# 檢查 Streamlit 日誌
tail -20 streamlit.log
```

在瀏覽器測試之前修復所有錯誤。

---

### 步驟 6：透過瀏覽器自動化驗證

**重要：** 您必須透過實際的 Streamlit 瀏覽器介面驗證 UI 功能。
在 Python shell 中有效但在 Streamlit 中失敗的程式碼不算通過。

按以下順序使用瀏覽器自動化工具：

1. **導航至儀表板：**

   ```
   puppeteer_navigate: http://localhost:8501
   ```

2. **截圖查看當前狀態：**

   ```
   puppeteer_screenshot
   ```

3. **像真實使用者一樣互動：**
   - 使用 `puppeteer_fill` 在 URL 輸入框中輸入
   - 使用 `puppeteer_click` 點擊「處理集數」按鈕
   - 每次互動後使用 `puppeteer_screenshot`
   - 在進行下一步之前等待轉圈完成（Whisper 可能需要 30-120 秒）

4. **檢查錯誤：**
   - 紅色 Streamlit 例外框 = 應用程式中的 Python 錯誤
   - 空白頁面或無限轉圈 = 崩潰或匯入錯誤
   - "ModuleNotFoundError" = 缺少依賴

5. **端對端測試處理管道：**
   首先建立一個短測試音頻檔案，避免長時間等待 Whisper：

   ```bash
   # 用 ffmpeg 建立 10 秒測試音頻
   ffmpeg -f lavfi -i "sine=frequency=440:duration=10" /tmp/test_podcast.mp3 -y 2>/dev/null
   ```

   然後透過 Streamlit 中的檔案上傳小工具上傳（使用「tiny」Whisper 模型以提升速度）。

6. **用真實問題測試問答：**
   處理集數後，導航至問答分頁，輸入關於集數內容的問題，
   點擊「提問」，確認回應包含來源引用。

7. **測試媒體庫搜尋：**
   導航至媒體庫頁面，輸入已處理集數中的關鍵字，確認結果出現。

**應該做：**

- 導航至 <http://localhost:8501> 測試所有功能
- 測試時使用「tiny」Whisper 模型（最快，約 10 倍實時速度）
- 使用短音頻檔案（< 30 秒）以最小化等待時間
- 在每個步驟截圖以確認進度指示器出現
- 確認問答回應包含「來源：」或引用文字
- 確認處理後集數卡片出現在媒體庫中

**不應該做：**

- 只透過 Python 直接測試 — 需要瀏覽器 UI 驗證
- 使用 `puppeteer_connect_active_tab` — 始終以 `puppeteer_navigate` 重新開始
- 未透過瀏覽器驗證就標記測試通過
- 在檢查逐字稿分頁之前跳過等待 Whisper 完成
- 使用大型音頻檔案測試（使用短檔案保持測試快速）

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕對不要使用 puppeteer_connect_active_tab。始終以 puppeteer_navigate 重新開始。

---

### 步驟 7：標記功能為通過

只有在瀏覽器驗證確認功能正常後：

編輯 `feature_list.json` — 將已驗證功能的 `"passes": false` 改為 `"passes": true`。

**以下情況絕對不要標記功能為通過：**

- 只透過 Python 測試（而非瀏覽器）
- 功能部分有效（例如：下載執行但進度列不可見）
- 看到 Streamlit 錯誤框
- feature_list.json 中的測試步驟未全部執行

**重要：** 絕對不要移除或編輯功能描述或測試步驟。只改變「passes」。

---

### 步驟 8：提交進度

每個驗證通過的功能（或相關功能的邏輯群組）後：

```bash
git add -A
git commit -m "Implement [feature name]: [brief description of what was done]"
```

好的提交訊息：「Implement Whisper transcription with model selection and progress display」
不好的提交訊息：「fix」、「update」、「wip」

---

### 步驟 9：更新進度檔案

用以下內容更新 `claude-progress.txt`：

- 本 Session 完成的功能（feature_list.json 中的 ID）
- 每個源文件的當前狀態（stub/partial/complete）
- 任何已知問題或限制
- 下個 Session 的建議優先順序

```
SESSION N 摘要
=================
已完成功能：#1（載入）、#2（URL 輸入）、#5（處理按鈕）、#7（轉錄）
已修改檔案：podcastbrain/app.py（處理頁面完成）、podcastbrain/transcriber.py（完成）
已知問題：CPU 上 45 分鐘集數，Whisper「medium」模型需要 3+ 分鐘
下個優先順序：功能 #8（章節）、#10（摘要分頁）、#13（問答）
```

---

### 步驟 10：確認沒有東西壞掉

完成前，執行最終端對端完整性檢查：

```bash
# 重新確認 Streamlit 仍在運行
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"

# 快速瀏覽器檢查
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

如果任何之前通過的功能現在壞掉，在結束 Session 之前修復它。
不要引入回退問題。

---

### 重要提醒

**PodcastBrain 的品質標準：**

- Whisper 模型必須以 `@st.cache_resource` 快取 — 絕不在每次互動時重新載入
- Claude 只能接收文字 — 絕不接收音頻二進位資料或檔案路徑
- 問答系統提示必須包含「Answer only from the provided transcript excerpts」
- FTS5 搜尋必須使用參數化查詢 — 絕不使用字串插值（SQL 注入風險）
- yt-dlp 子程序必須有超時（300 秒）以防止掛起
- `/tmp/podcastbrain-audio/` 中的暫存音頻檔案在轉錄儲存至資料庫後必須清理
- 所有三個 Claude 分析呼叫（章節、摘要+引述+行動項目、說話者識別）必須是獨立函式
- 集數狀態必須在每個管道步驟更新至資料庫（queued → downloading → transcribing → analyzing → complete/failed）

**API 金鑰處理：**

```python
def _get_api_key() -> str:
    """Load API key from /tmp/api-key or environment variable."""
    try:
        with open("/tmp/api-key") as f:
            return f.read().strip()
    except (FileNotFoundError, PermissionError):
        return os.environ.get("ANTHROPIC_API_KEY", "")

# 在 Streamlit 頁面中：
api_key = _get_api_key()
if not api_key:
    st.error("找不到 API 金鑰。請設定 ANTHROPIC_API_KEY 環境變數或建立 /tmp/api-key")
    st.stop()
```

**Whisper 模型計時（用於測試規劃）：**

- tiny：約 5 倍實時（10 秒音頻 → 2 秒轉錄）— 用於測試
- base：約 10 倍實時 — 良好平衡
- small：約 20 倍實時
- medium：約 40 倍實時 — 高精確度
- large：約 60 倍實時 — 最高精確度，CPU 速度慢

**FTS5 搜尋必須使用參數化查詢：**

```python
# 正確 — 參數化查詢
results = conn.execute(text("SELECT * FROM transcripts_fts WHERE transcripts_fts MATCH :q"),
                       {"q": user_query}).fetchall()

# 錯誤 — 字串插值（SQL 注入風險）
results = conn.execute(text(f"SELECT * FROM transcripts_fts WHERE transcripts_fts MATCH '{user_query}'"))
```

**不要破壞現有已通過的功能。** 開始之前先閱讀 feature_list.json。
如果某個功能已通過，除非修復 bug，否則不要碰其相關程式碼。
