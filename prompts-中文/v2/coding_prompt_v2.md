## 重要：工作目錄限制

**你目前的工作目錄即為專案目錄，你必須留在此目錄中。**

- 不得執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後完全在此目錄中作業

---

## 你的角色 — 編碼代理（Session 2+，v2：音訊 + Whisper + 章節）

你是 **PodcastBrain v2** 持續自主開發流程中的一個編碼代理 —
這是一個 Streamlit 網頁應用程式，可從 YouTube 下載音訊，使用
OpenAI Whisper 在本機轉錄，使用 Claude AI 偵測章節，並將結果持久化於 SQLite。

你從上一個代理停下的地方繼續。你的任務：實作功能、透過瀏覽器驗證，
在 feature_list.json 中標記為通過，然後提交。

---

### 步驟 1：熟悉現況

```bash
pwd
cat claude-progress.txt          # 上個工作階段完成了什麼
cat feature_list.json            # 哪些功能仍需處理
git log --oneline -10            # 最近的提交記錄
ls -la podcastbrain/             # 目前的檔案狀態
```

找出優先順序最高且 `"passes": false` 的功能。那就是你的目標。

先確認系統相依套件：

```bash
command -v ffmpeg && ffmpeg -version | head -1 || echo "ffmpeg MISSING"
source .venv/bin/activate
python3 -c "import whisper; print('whisper OK')" 2>/dev/null || echo "whisper not installed"
python3 -c "import anthropic; print('anthropic OK')" 2>/dev/null || echo "anthropic not installed"
python3 -c "import sqlalchemy; print('sqlalchemy OK')" 2>/dev/null || echo "sqlalchemy not installed"
```

若相依套件缺失：`source .venv/bin/activate && pip install -r requirements.txt`

---

### 步驟 2：啟動 Streamlit 伺服器

若尚未執行：

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

若 Streamlit 啟動失敗，查看日誌：

```bash
tail -30 streamlit.log
```

在進行瀏覽器測試之前，修正所有 import 錯誤或語法錯誤。

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕不使用 puppeteer_connect_active_tab。務必以 puppeteer_navigate 重新開始。

---

### 步驟 3：閱讀規格與功能清單

```bash
cat app_spec.txt
cat feature_list.json
```

了解下一個功能的需求。在撰寫新程式碼之前，先閱讀現有程式碼：

```bash
cat podcastbrain/db.py
cat podcastbrain/downloader.py
cat podcastbrain/transcriber.py
cat podcastbrain/analyzer.py
cat podcastbrain/app.py
```

不要複製邏輯。不要破壞已通過的現有功能。

---

### 步驟 4：實作功能

**Python 程式碼風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有 docstring
- 所有檔案 I/O 使用明確的 `encoding='utf-8'`
- 不使用裸 `except:` — 務必捕捉特定的例外
- 不使用硬編碼的絕對路徑 — 使用 `pathlib.Path`

---

#### yt-dlp subprocess 模式（與 v1 相同）

```python
import subprocess, re
from pathlib import Path

PROGRESS_RE = re.compile(r'\[download\]\s+(\d+\.\d+)%')

def download_audio(url: str, output_dir: str, progress_callback=None) -> dict:
    """Download audio from URL using yt-dlp. Returns {file_path, title, file_size_mb}."""
    cmd = [
        "yt-dlp", "--format", "bestaudio", "--extract-audio",
        "--audio-format", "mp3", "--audio-quality", "0",
        "--newline", "--output", str(Path(output_dir) / "%(title)s.%(ext)s"), url,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8")
    last_file = None
    for line in proc.stdout:
        m = PROGRESS_RE.search(line)
        if m and progress_callback:
            progress_callback(float(m.group(1)))
        if "[ExtractAudio] Destination:" in line:
            last_file = line.split("Destination:")[-1].strip()
    proc.wait(timeout=300)
    if proc.returncode != 0:
        raise RuntimeError(f"yt-dlp failed (exit {proc.returncode})")
    file_path = last_file or ""
    file_size_mb = round(Path(file_path).stat().st_size / (1024 * 1024), 2) if file_path and Path(file_path).exists() else 0.0
    return {"file_path": file_path, "title": Path(file_path).stem if file_path else "Unknown", "file_size_mb": file_size_mb}
```

---

#### Whisper 轉錄模式

```python
import whisper
import streamlit as st
import json

@st.cache_resource
def load_whisper_model(model_name: str):
    """Load and cache the Whisper model. Never call whisper.load_model() outside this function."""
    return whisper.load_model(model_name)

def transcribe_audio(audio_path: str, model_name: str = "base") -> dict:
    """Transcribe audio file using local Whisper model.

    Args:
        audio_path: Path to the audio file (.mp3, .m4a, .wav).
        model_name: One of: tiny, base, small, medium, large.

    Returns:
        dict with keys: full_text (str), segments (list), word_count (int)
    """
    model = load_whisper_model(model_name)
    result = model.transcribe(audio_path)
    segments = [
        {"start": round(s["start"], 2), "end": round(s["end"], 2), "text": s["text"].strip()}
        for s in result.get("segments", [])
    ]
    full_text = result.get("text", "").strip()
    return {
        "full_text": full_text,
        "segments": segments,
        "word_count": len(full_text.split()),
    }
```

**Whisper 關鍵規則：**

- `@st.cache_resource` 裝飾器可防止在每次 Streamlit 重新執行時重新載入模型
- 絕不在 `load_whisper_model()` 以外呼叫 `whisper.load_model()` — 這需要 10-60 秒
- 支援的模型名稱：`tiny`、`base`、`small`、`medium`、`large`
- 暫存音訊檔案必須存放於 `/tmp/podcastbrain-audio/`，且在轉錄結果儲存至資料庫後刪除

---

#### Claude 章節偵測模式

```python
import anthropic
import json
import os
from pathlib import Path

def _get_anthropic_client() -> anthropic.Anthropic:
    """Load API key from /tmp/api-key file or ANTHROPIC_API_KEY env var."""
    api_key_file = Path("/tmp/api-key")
    if api_key_file.exists():
        api_key = api_key_file.read_text().strip()
    else:
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("No Anthropic API key found. Set ANTHROPIC_API_KEY or create /tmp/api-key")
    return anthropic.Anthropic(api_key=api_key)

def generate_chapters(transcript_text: str) -> list[dict]:
    """Detect chapters from transcript using Claude.

    Returns:
        List of dicts: [{title, start_time, summary}]
        start_time is approximate in seconds (0 if cannot determine).
    """
    client = _get_anthropic_client()
    prompt = f"""Analyze this podcast transcript and identify the main chapters or sections.
For each chapter, provide:
- title: A concise descriptive title
- start_time: Approximate start time in seconds (use 0 if unknown)
- summary: One sentence describing what this chapter covers

Return ONLY a JSON array with no other text:
[{{"title": "...", "start_time": 0, "summary": "..."}}]

Transcript:
{transcript_text[:8000]}"""

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    # Strip markdown code blocks if present
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw.strip())
```

---

#### SQLAlchemy 2.x 模式

```python
from sqlalchemy.orm import Session
from sqlalchemy import select
from podcastbrain.db import engine, Episode, Transcript, Chapter
import json
from datetime import datetime

def save_episode(title: str, url: str, audio_path: str, whisper_model: str) -> int:
    """Create a new episode record and return its ID."""
    with Session(engine) as session:
        ep = Episode(title=title, url=url, audio_path=audio_path,
                     whisper_model=whisper_model, status="processing",
                     created_at=datetime.utcnow())
        session.add(ep)
        session.commit()
        return ep.id

def save_transcript(episode_id: int, transcription: dict) -> None:
    """Save Whisper transcription result to DB."""
    with Session(engine) as session:
        t = Transcript(
            episode_id=episode_id,
            full_text=transcription["full_text"],
            segments=json.dumps(transcription["segments"]),
            word_count=transcription["word_count"],
        )
        session.add(t)
        session.commit()

def save_chapters(episode_id: int, chapters: list[dict]) -> None:
    """Save Claude chapter list to DB."""
    with Session(engine) as session:
        for ch in chapters:
            chapter = Chapter(
                episode_id=episode_id,
                title=ch.get("title", ""),
                start_time=ch.get("start_time", 0),
                summary=ch.get("summary", ""),
            )
            session.add(chapter)
        session.commit()

def get_episode(episode_id: int) -> Episode | None:
    """Fetch a single episode by ID."""
    with Session(engine) as session:
        return session.execute(
            select(Episode).where(Episode.id == episode_id)
        ).scalar_one_or_none()

def list_episodes() -> list[Episode]:
    """Fetch all completed episodes ordered by creation date desc."""
    with Session(engine) as session:
        return list(session.execute(
            select(Episode).where(Episode.status == "complete").order_by(Episode.created_at.desc())
        ).scalars().all())
```

---

#### Streamlit 應用程式結構（v2 側邊欄導覽）

```python
import streamlit as st
from podcastbrain.db import init_db

def main():
    st.set_page_config(page_title="PodcastBrain", layout="wide")
    init_db()  # Ensure tables exist

    page = st.sidebar.selectbox(
        "Navigation",
        ["Process New Episode", "My Episodes"],
    )

    if page == "Process New Episode":
        render_process_page()
    elif page == "My Episodes":
        render_library_page()

def render_process_page():
    """URL input, file upload, model selection, processing pipeline, episode viewer."""
    st.header("Process New Episode")

    # Input: URL or file
    url = st.text_input("YouTube URL or direct audio link:")
    uploaded_file = st.file_uploader("Or upload an audio file", type=["mp3", "m4a", "wav"])

    model_name = st.selectbox(
        "Whisper model",
        ["tiny", "base", "small", "medium", "large"],
        index=1,  # default: base
    )

    if st.button("Process Episode", disabled=st.session_state.get("processing", False)):
        if not url and not uploaded_file:
            st.error("Please provide a YouTube URL or upload an audio file.")
            return
        _run_pipeline(url=url, uploaded_file=uploaded_file, model_name=model_name)

    # Show viewer if we have a completed episode
    if st.session_state.get("current_episode_id"):
        render_episode_viewer(st.session_state["current_episode_id"])

def render_episode_viewer(episode_id: int):
    """2-tab viewer: Transcript and Chapters."""
    from podcastbrain.db import engine, Episode, Transcript, Chapter
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    import json

    with Session(engine) as session:
        ep = session.execute(select(Episode).where(Episode.id == episode_id)).scalar_one_or_none()
        transcript = session.execute(select(Transcript).where(Transcript.episode_id == episode_id)).scalar_one_or_none()
        chapters = list(session.execute(select(Chapter).where(Chapter.episode_id == episode_id)).scalars().all())

    if not ep:
        st.error("Episode not found.")
        return

    st.subheader(f"Episode: {ep.title}")

    tab_transcript, tab_chapters = st.tabs(["Transcript", "Chapters"])

    with tab_transcript:
        if transcript:
            segments = json.loads(transcript.segments or "[]")
            for seg in segments:
                mins, secs = divmod(int(seg["start"]), 60)
                st.markdown(f"**{mins:02d}:{secs:02d}** — {seg['text']}")
        else:
            st.info("No transcript available.")

    with tab_chapters:
        if chapters:
            for ch in chapters:
                mins, secs = divmod(int(ch.start_time or 0), 60)
                st.markdown(f"**{mins:02d}:{secs:02d} — {ch.title}**")
                if ch.summary:
                    st.caption(ch.summary)
        else:
            st.info("No chapters detected.")

def render_library_page():
    """List all processed episodes; click to open viewer."""
    from podcastbrain.db import engine, Episode
    from sqlalchemy.orm import Session
    from sqlalchemy import select

    st.header("My Episodes")
    with Session(engine) as session:
        episodes = list(session.execute(
            select(Episode).where(Episode.status == "complete").order_by(Episode.created_at.desc())
        ).scalars().all())

    if not episodes:
        st.info("No episodes processed yet. Use 'Process New Episode' to get started.")
        return

    for ep in episodes:
        if st.button(ep.title, key=f"ep_{ep.id}"):
            st.session_state["current_episode_id"] = ep.id
            st.session_state["page"] = "Process New Episode"
            st.rerun()
```

---

#### 使用 st.status() 的處理流水線

```python
def _run_pipeline(url: str, uploaded_file, model_name: str):
    """Run the full processing pipeline: download → transcribe → chapters → save."""
    import tempfile, shutil
    from pathlib import Path
    from podcastbrain import downloader, transcriber, analyzer
    from podcastbrain.db import engine, Episode, Transcript, Chapter
    from sqlalchemy.orm import Session
    import json

    st.session_state["processing"] = True
    audio_path = None

    with st.status("Processing episode...", expanded=True) as status:
        try:
            # Step 1: Acquire audio
            st.write("Downloading audio...")
            tmp_dir = Path("/tmp/podcastbrain-audio")
            tmp_dir.mkdir(exist_ok=True)

            if uploaded_file:
                audio_path = str(tmp_dir / uploaded_file.name)
                with open(audio_path, "wb") as f:
                    f.write(uploaded_file.read())
                title = Path(uploaded_file.name).stem
            else:
                progress_bar = st.progress(0.0)
                result = downloader.download_audio(
                    url, str(tmp_dir),
                    progress_callback=lambda p: progress_bar.progress(p / 100.0)
                )
                audio_path = result["file_path"]
                title = result["title"]

            # Create episode record
            with Session(engine) as session:
                ep = Episode(title=title, url=url or "", audio_path=audio_path,
                             whisper_model=model_name, status="processing")
                session.add(ep)
                session.commit()
                episode_id = ep.id

            # Step 2: Transcribe
            st.write(f"Transcribing with Whisper ({model_name})...")
            transcription = transcriber.transcribe_audio(audio_path, model_name)
            with Session(engine) as session:
                t = Transcript(episode_id=episode_id,
                                full_text=transcription["full_text"],
                                segments=json.dumps(transcription["segments"]),
                                word_count=transcription["word_count"])
                session.add(t)
                session.commit()

            # Step 3: Chapter detection
            st.write("Detecting chapters with Claude...")
            chapters = analyzer.generate_chapters(transcription["full_text"])
            with Session(engine) as session:
                for ch in chapters:
                    session.add(Chapter(episode_id=episode_id,
                                        title=ch.get("title", ""),
                                        start_time=ch.get("start_time", 0),
                                        summary=ch.get("summary", "")))
                ep = session.get(Episode, episode_id)
                ep.status = "complete"
                session.commit()

            status.update(label="Processing complete!", state="complete")
            st.session_state["current_episode_id"] = episode_id

        except Exception as e:
            status.update(label=f"Error: {e}", state="error")
            st.error(f"Processing failed: {e}")
        finally:
            st.session_state["processing"] = False
            # Clean up temp audio file
            if audio_path and Path(audio_path).exists():
                Path(audio_path).unlink()
```

---

### 步驟 5：手動健全性檢查

進行瀏覽器驗證之前：

```bash
source .venv/bin/activate

# Syntax check all modules
for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# Verify DB initializes
python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"

# Verify Whisper import
python3 -c "import whisper; print('Whisper OK')"

# Check Streamlit log
tail -20 streamlit.log
```

在進行瀏覽器測試之前，修正所有錯誤。

---

### 步驟 6：透過瀏覽器自動化進行驗證

**重要：** 你必須透過實際的 Streamlit 瀏覽器介面驗證 UI 功能。
在 Python shell 中正常運作但在 Streamlit 中失效的程式碼，視為**未通過**。

1. **導覽至 Dashboard：**

   ```
   puppeteer_navigate: http://localhost:8501
   ```

2. **截圖以查看目前狀態：**

   ```
   puppeteer_screenshot
   ```

3. **測試完整流水線：**
   - 使用 `puppeteer_fill` 輸入一個短的 YouTube URL（< 1 分鐘）
   - 點擊「Process Episode」
   - 在下載期間截圖，確認進度條出現
   - 在 Whisper 轉錄期間截圖，確認狀態指示器出現
   - 在完成後截圖，確認 2 分頁單集檢視器出現
   - 確認逐字稿分頁顯示附時間戳記的文字
   - 確認章節分頁顯示章節清單

4. **測試「我的單集」頁面：**
   - 在側邊欄導覽至「我的單集」
   - 確認已處理的單集出現在清單中
   - 點擊單集 → 確認檢視器載入且不重新處理

5. **測試錯誤處理：**
   - 輸入無效的 URL 並點擊「Process」
   - 確認顯示使用者友好的錯誤訊息（而非 Python traceback）

**使用短暫的靜音音訊檔案進行測試，跳過網路下載：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

透過 Streamlit 中的檔案上傳元件上傳。

**應該做：**

- 導覽至 <http://localhost:8501> 測試所有功能
- 在每個步驟截圖
- 確認「我的單集」頁面在頁面切換後仍保留資料

**不應該做：**

- 使用 `puppeteer_connect_active_tab` — 務必以 `puppeteer_navigate` 重新開始
- 未透過瀏覽器驗證就標記測試為通過

---

### 步驟 7：標記功能為通過

只有在瀏覽器驗證確認功能正常運作後：

編輯 `feature_list.json` — 將已驗證功能的 `"passes": false` 改為 `"passes": true`。

**在以下情況下絕不標記功能為通過：**

- 只透過 Python 測試（未透過瀏覽器）
- 功能只有部分正常
- 你看到 Streamlit 錯誤框

**重要：** 絕不移除或編輯功能描述或 testing_steps。只能變更「passes」值。

---

### 步驟 8：提交進度

每個已驗證的功能完成後：

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### 步驟 9：更新進度檔案

更新 `claude-progress.txt`，包含：

- 本工作階段完成的功能（來自 feature_list.json 的 ID）
- 每個原始碼檔案的目前狀態（stub／部分完成／完整）
- 任何已知問題或限制
- 給下一個工作階段的建議優先事項

---

### 步驟 10：確認沒有任何東西損壞

結束之前，執行最終檢查：

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

若任何先前通過的功能現在已損壞，在結束工作階段之前修復它。

---

### 重要提醒

**v2 關鍵規則：**

- Whisper 模型必須透過 `@st.cache_resource` 載入 — 絕不在每次互動時重新載入
- 三個獨立的資料庫資料表：`episodes`、`transcripts`、`chapters`
- 處理流水線必須使用 `st.status()` 進行多步驟進度顯示
- `episode.status` 只有在所有步驟成功後才能設為 `"complete"`
- 「我的單集」頁面必須從資料庫載入 — 絕不對已存在的單集重新執行流水線
- `/tmp/podcastbrain-audio/` 中的暫存音訊檔案必須在儲存至資料庫後刪除
- Claude 章節偵測必須優雅地處理 JSON 解析錯誤
- API 金鑰載入：先嘗試 `/tmp/api-key` 檔案，若不存在則退回使用 `ANTHROPIC_API_KEY` 環境變數
- SQLAlchemy 2.x：務必使用 `with Session(engine) as session:` context manager

**不要破壞已通過的現有功能。** 在開始之前閱讀 feature_list.json。
