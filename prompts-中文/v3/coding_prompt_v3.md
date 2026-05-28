## 重要：工作目錄限制

**你目前的工作目錄就是專案目錄。你必須留在其中。**

- 禁止執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，之後只在該目錄中工作

---

## 你的角色 — 程式碼代理（第 2+ 次 Session，v3：完整分析 + 問答）

你是 **PodcastBrain v3** 持續自主開發流程中的程式碼代理——
一個可下載音訊、以 Whisper 轉錄、執行三種 Claude AI 分析
（章節、完整摘要+引言+行動項目、發言人識別），
並提供以逐字稿為基礎附來源引用的互動式問答的 Streamlit 網頁應用程式。

你從上一個代理結束的地方繼續。你的任務是：實作功能、透過瀏覽器驗證、
在 feature_list.json 中標記通過，並提交。

---

### 步驟 1：定向

```bash
pwd
cat claude-progress.txt
cat feature_list.json
git log --oneline -10
ls -la podcastbrain/
```

找出優先順序最高且 `"passes": false` 的功能。那就是你的目標。

先檢查系統相依套件：

```bash
source .venv/bin/activate
python3 -c "import whisper; print('whisper OK')"
python3 -c "import anthropic; print('anthropic OK')"
python3 -c "import sqlalchemy; print('sqlalchemy OK')"
python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"
```

---

### 步驟 2：啟動 Streamlit 伺服器

```bash
source .venv/bin/activate
curl -s http://localhost:8501 > /dev/null && echo "Already running" || \
  nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &
sleep 3
tail -20 streamlit.log
```

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕不使用 puppeteer_connect_active_tab。永遠以 puppeteer_navigate 全新開始。

---

### 步驟 3：閱讀規格與功能清單

```bash
cat app_spec.txt
cat feature_list.json
cat podcastbrain/analyzer.py
cat podcastbrain/qa_engine.py
cat podcastbrain/app.py
```

不要重複邏輯。不要破壞已通過的功能。

---

### 步驟 4：實作功能

**Python 風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有 docstring
- 所有檔案 I/O 明確使用 `encoding='utf-8'`
- 不使用裸露的 `except:`——永遠捕捉特定例外
- 不使用硬編碼的絕對路徑——使用 `pathlib.Path`

---

#### yt-dlp 與 Whisper 模式（與 v2 相同）

使用與 v2 相同的 `download_audio()` 和 `transcribe_audio()` 模式。
`load_whisper_model()` 上的 `@st.cache_resource` 是必要的。

---

#### 三個獨立的 Claude 分析函式

**三個函式必須都是 analyzer.py 中的獨立函式。** 絕不合併為單一呼叫。

```python
import anthropic, json, os
from pathlib import Path

def _get_client() -> anthropic.Anthropic:
    """Load API key from /tmp/api-key or ANTHROPIC_API_KEY env var."""
    key_file = Path("/tmp/api-key")
    api_key = key_file.read_text().strip() if key_file.exists() else os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        raise RuntimeError("No Anthropic API key found")
    return anthropic.Anthropic(api_key=api_key)


def generate_chapters(transcript_text: str) -> list[dict]:
    """Detect chapters from transcript. Returns [{title, start_time, summary}]."""
    client = _get_client()
    prompt = f"""Analyze this podcast transcript and identify the main chapters or sections.
Return ONLY a JSON array with no other text:
[{{"title": "...", "start_time": 0, "summary": "one sentence"}}]

Transcript:
{transcript_text[:8000]}"""
    response = client.messages.create(
        model="claude-sonnet-4-6", max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    if raw.startswith("```"):
        raw = "\n".join(raw.split("\n")[1:-1])
    return json.loads(raw)


def generate_summary_quotes_actions(transcript_text: str) -> dict:
    """Generate summary, key quotes, and action items from transcript.

    Returns:
        dict with keys:
          summary (str): 2-3 paragraph executive summary
          quotes (list[str]): 3-5 memorable direct quotes
          action_items (list[str]): actionable takeaways
    """
    client = _get_client()
    prompt = f"""Analyze this podcast transcript and provide:
1. A 2-3 paragraph executive summary
2. 3-5 memorable direct quotes (exact words from the transcript)
3. Key action items or takeaways for the listener

Return ONLY a JSON object with no other text:
{{
  "summary": "...",
  "quotes": ["...", "..."],
  "action_items": ["...", "..."]
}}

Transcript:
{transcript_text[:12000]}"""
    response = client.messages.create(
        model="claude-sonnet-4-6", max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    if raw.startswith("```"):
        raw = "\n".join(raw.split("\n")[1:-1])
    return json.loads(raw)


def identify_speakers(transcript_text: str) -> list[dict]:
    """Identify distinct speakers in the transcript.

    Returns:
        list of dicts: [{name, role, description}]
        name is "Speaker 1", "Speaker 2", etc. if actual names unknown.
    """
    client = _get_client()
    prompt = f"""Identify the distinct speakers in this podcast transcript.
For each speaker, provide their apparent name (or "Speaker 1", "Speaker 2" if unknown),
their role (host/guest/interviewer/expert/etc.), and a brief description.

Return ONLY a JSON array:
[{{"name": "...", "role": "...", "description": "..."}}]

Transcript:
{transcript_text[:6000]}"""
    response = client.messages.create(
        model="claude-sonnet-4-6", max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = response.content[0].text.strip()
    if raw.startswith("```"):
        raw = "\n".join(raw.split("\n")[1:-1])
    return json.loads(raw)
```

---

#### 問答引擎模式

```python
import json
import anthropic
from pathlib import Path
import os

def answer_question(question: str, segments: list[dict], episode_title: str) -> dict:
    """Answer a question using transcript segments as context.

    Strategy:
    1. Split question into keywords
    2. Score each segment by keyword overlap
    3. Take top 10 segments as context
    4. Send to Claude with strict grounding system prompt

    Args:
        question: The user's question string.
        segments: List of {start, end, text} dicts from Whisper.
        episode_title: Used for context in the prompt.

    Returns:
        dict with keys: answer (str), sources (list of {start, text})
    """
    # 關鍵字檢索：依關鍵字重疊為片段評分
    keywords = {w.lower() for w in question.split() if len(w) > 3}
    scored = []
    for seg in segments:
        text_lower = seg["text"].lower()
        score = sum(1 for kw in keywords if kw in text_lower)
        scored.append((score, seg))
    scored.sort(key=lambda x: x[0], reverse=True)
    top_segments = [s for _, s in scored[:10]]

    # 格式化含時間戳的上下文
    context_parts = []
    for seg in top_segments:
        mins, secs = divmod(int(seg["start"]), 60)
        context_parts.append(f"[{mins:02d}:{secs:02d}] {seg['text']}")
    context = "\n".join(context_parts)

    # 以接地系統提示呼叫 Claude 問答
    key_file = Path("/tmp/api-key")
    api_key = key_file.read_text().strip() if key_file.exists() else os.environ.get("ANTHROPIC_API_KEY", "")
    client = anthropic.Anthropic(api_key=api_key)

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1024,
        system="Answer only from the provided transcript excerpts. "
               "If the answer is not in the excerpts, say so clearly. "
               "Include timestamp references like [MM:SS] when citing specific moments.",
        messages=[{
            "role": "user",
            "content": f"Episode: {episode_title}\n\nTranscript excerpts:\n{context}\n\nQuestion: {question}"
        }],
    )
    answer_text = response.content[0].text.strip()

    # 擷取引用的時間戳以顯示來源
    import re
    cited_times = re.findall(r'\[(\d{2}:\d{2})\]', answer_text)
    sources = [
        {"start": seg["start"], "text": seg["text"]}
        for seg in top_segments
        if any(f"{int(seg['start'])//60:02d}:{int(seg['start'])%60:02d}" in t for t in cited_times)
    ]

    return {"answer": answer_text, "sources": sources}
```

**問答關鍵規則：**

- 系統提示必須包含「Answer only from the provided transcript excerpts」
- v3 中片段選擇永遠使用關鍵字檢索（非嵌入式搜尋）
- 回傳 sources 清單以便 UI 顯示引用時間戳

---

#### SQLAlchemy 2.x 模式（v3 新增）

```python
from sqlalchemy.orm import Session
from sqlalchemy import select
from podcastbrain.db import engine, Episode, QAHistory
import json
from datetime import datetime

def save_claude_analysis(episode_id: int, analysis: dict) -> None:
    """Save combined Claude analysis (summary, quotes, actions, speakers) to episode.claude_analysis."""
    with Session(engine) as session:
        ep = session.get(Episode, episode_id)
        ep.claude_analysis = json.dumps(analysis)
        session.commit()

def save_qa_exchange(episode_id: int, question: str, answer: str, sources: list) -> None:
    """Persist a Q&A exchange to the database."""
    with Session(engine) as session:
        qa = QAHistory(
            episode_id=episode_id,
            question=question,
            answer=answer,
            source_ts=json.dumps([s["start"] for s in sources]),
            created_at=datetime.utcnow(),
        )
        session.add(qa)
        session.commit()

def load_qa_history(episode_id: int) -> list[dict]:
    """Load all Q&A exchanges for an episode ordered by creation time."""
    with Session(engine) as session:
        rows = list(session.execute(
            select(QAHistory)
            .where(QAHistory.episode_id == episode_id)
            .order_by(QAHistory.created_at)
        ).scalars().all())
        return [{"question": r.question, "answer": r.answer} for r in rows]
```

---

#### 4 標籤頁劇集檢視器

```python
def render_episode_viewer(episode_id: int):
    """4-tab viewer: Summary, Chapters, Transcript, Q&A."""
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

    analysis = json.loads(ep.claude_analysis) if ep.claude_analysis else {}
    segments = json.loads(transcript.segments) if transcript and transcript.segments else []

    st.subheader(f"Episode: {ep.title}")
    tab_summary, tab_chapters, tab_transcript, tab_qa = st.tabs(
        ["Summary", "Chapters", "Transcript", "Q&A"]
    )

    with tab_summary:
        if analysis.get("summary"):
            st.markdown(analysis["summary"])
        if analysis.get("quotes"):
            st.subheader("Key Quotes")
            for q in analysis["quotes"]:
                st.markdown(f"> {q}")
        if analysis.get("action_items"):
            st.subheader("Action Items")
            for item in analysis["action_items"]:
                st.markdown(f"- {item}")
        if analysis.get("speakers"):
            st.subheader("Speakers")
            for sp in analysis["speakers"]:
                st.markdown(f"**{sp['name']}** ({sp['role']}): {sp['description']}")

    with tab_chapters:
        if chapters:
            for ch in chapters:
                mins, secs = divmod(int(ch.start_time or 0), 60)
                st.markdown(f"**{mins:02d}:{secs:02d} — {ch.title}**")
                if ch.summary:
                    st.caption(ch.summary)
        else:
            st.info("No chapters detected.")

    with tab_transcript:
        search_term = st.text_input("Search transcript:", key=f"search_{episode_id}")
        for seg in segments:
            text = seg["text"]
            if search_term and search_term.lower() not in text.lower():
                continue
            mins, secs = divmod(int(seg["start"]), 60)
            st.markdown(f"**{mins:02d}:{secs:02d}** — {text}")

    with tab_qa:
        # 顯示現有的問答紀錄
        from podcastbrain.db import load_qa_history
        history = load_qa_history(episode_id)
        for exchange in history:
            with st.chat_message("user"):
                st.write(exchange["question"])
            with st.chat_message("assistant"):
                st.write(exchange["answer"])

        # 新問題輸入
        question = st.chat_input("Ask a question about this episode...")
        if question:
            from podcastbrain.qa_engine import answer_question
            with st.spinner("Thinking..."):
                result = answer_question(question, segments, ep.title)
            from podcastbrain.db import save_qa_exchange
            save_qa_exchange(episode_id, question, result["answer"], result["sources"])
            # 顯示新的問答交換
            with st.chat_message("user"):
                st.write(question)
            with st.chat_message("assistant"):
                st.write(result["answer"])
                if result["sources"]:
                    with st.expander("Sources"):
                        for src in result["sources"]:
                            mins, secs = divmod(int(src["start"]), 60)
                            st.caption(f"[{mins:02d}:{secs:02d}] {src['text']}")
```

---

#### 含全部 3 個 Claude 步驟的處理流程

```python
def _run_pipeline(url: str, uploaded_file, model_name: str):
    """Full pipeline: download → transcribe → chapters → analysis → speakers → save."""
    from pathlib import Path
    from podcastbrain import downloader, transcriber, analyzer
    from podcastbrain.db import engine, Episode, Transcript, Chapter
    from sqlalchemy.orm import Session
    import json

    st.session_state["processing"] = True
    audio_path = None

    with st.status("Processing episode...", expanded=True) as status:
        try:
            # 步驟 1：取得音訊
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
                result = downloader.download_audio(url, str(tmp_dir),
                    progress_callback=lambda p: progress_bar.progress(p / 100.0))
                audio_path = result["file_path"]
                title = result["title"]

            with Session(engine) as session:
                ep = Episode(title=title, url=url or "", audio_path=audio_path,
                             whisper_model=model_name, status="processing")
                session.add(ep)
                session.commit()
                episode_id = ep.id

            # 步驟 2：語音轉錄
            st.write(f"Transcribing with Whisper ({model_name})...")
            transcription = transcriber.transcribe_audio(audio_path, model_name)
            with Session(engine) as session:
                session.add(Transcript(episode_id=episode_id,
                                        full_text=transcription["full_text"],
                                        segments=json.dumps(transcription["segments"]),
                                        word_count=transcription["word_count"]))
                session.commit()

            # 步驟 3：Claude 章節偵測
            st.write("Detecting chapters...")
            chapters = analyzer.generate_chapters(transcription["full_text"])
            with Session(engine) as session:
                for ch in chapters:
                    session.add(Chapter(episode_id=episode_id, title=ch.get("title", ""),
                                        start_time=ch.get("start_time", 0), summary=ch.get("summary", "")))
                session.commit()

            # 步驟 4：Claude 完整分析
            st.write("Generating summary, quotes, and action items...")
            analysis = analyzer.generate_summary_quotes_actions(transcription["full_text"])

            # 步驟 5：Claude 發言人識別
            st.write("Identifying speakers...")
            speakers = analyzer.identify_speakers(transcription["full_text"])
            analysis["speakers"] = speakers

            with Session(engine) as session:
                ep = session.get(Episode, episode_id)
                ep.claude_analysis = json.dumps(analysis)
                ep.status = "complete"
                session.commit()

            status.update(label="Processing complete!", state="complete")
            st.session_state["current_episode_id"] = episode_id

        except Exception as e:
            status.update(label=f"Error: {e}", state="error")
            st.error(f"Processing failed: {e}")
        finally:
            st.session_state["processing"] = False
            if audio_path and Path(audio_path).exists():
                Path(audio_path).unlink()
```

---

### 步驟 5：手動健全性檢查

```bash
source .venv/bin/activate

for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"
tail -20 streamlit.log
```

---

### 步驟 6：以瀏覽器自動化驗證

1. 導覽至 <http://localhost:8501> 並截圖
2. 以短音訊檔測試完整流程（上傳 `/tmp/test.mp3`）
3. 驗證處理後出現全部 4 個標籤頁：摘要、章節、逐字稿、問答
4. 在摘要標籤：驗證摘要文字、引言區塊、行動項目、發言人清單
5. 在問答標籤：輸入問題，驗證含時間戳引用的有根據答案
6. 再提一個問題，驗證兩個問答都顯示在聊天紀錄中
7. 導覽至「我的劇集」，點擊劇集，驗證從資料庫載入的 4 標籤頁檢視器

**建立測試音訊：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**禁止：**

- 使用 `puppeteer_connect_active_tab`
- 未經瀏覽器驗證就標記測試通過

---

### 步驟 7：標記功能為通過

編輯 `feature_list.json`——將已透過瀏覽器驗證的功能從 `"passes": false` 改為 `"passes": true`。
**絕不移除或編輯功能描述或 testing_steps。**

---

### 步驟 8：提交進度

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### 步驟 9：更新進度檔案

以已完成的功能、各檔案狀態、已知問題、後續優先項目更新 `claude-progress.txt`。

---

### 步驟 10：確認沒有破壞任何功能

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

---

### 重要提醒

**v3 關鍵規則：**

- 三個獨立的 Claude 函式：`generate_chapters()`、`generate_summary_quotes_actions()`、`identify_speakers()`——絕不合併為單一呼叫
- `episode.claude_analysis` 以單一 JSON blob 儲存所有 Claude 結果：`{summary, quotes, action_items, speakers}`
- 問答系統提示必須包含「Answer only from the provided transcript excerpts」
- 問答紀錄持久化於 `qa_history` 資料表，並在每次開啟檢視器時載入
- 問答 UI 使用 `st.chat_input()` + `st.chat_message()`
- 4 個標籤頁的順序固定：摘要 → 章節 → 逐字稿 → 問答
- Whisper 模型必須使用 `@st.cache_resource`
- API 金鑰：優先嘗試 `/tmp/api-key` 檔案，退回使用 `ANTHROPIC_API_KEY` 環境變數
- 流程完成後清理 `/tmp/podcastbrain-audio/` 中的暫存音訊檔案

**不得破壞已通過的功能。** 開始前先閱讀 feature_list.json。
