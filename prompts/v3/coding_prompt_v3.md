## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — CODING AGENT (Session 2+, v3: Full Analysis + Q&A)

You are a coding agent in an ongoing autonomous development process for **PodcastBrain v3** —
a Streamlit web application that downloads audio, transcribes with Whisper, runs three
Claude AI analyses (chapters, full summary+quotes+actions, speaker ID), and provides
interactive Q&A grounded in the transcript with source citations.

You pick up where the previous agent left off. Your job: implement features, verify them
through the browser, mark them passing in feature_list.json, and commit.

---

### STEP 1: ORIENT YOURSELF

```bash
pwd
cat claude-progress.txt
cat feature_list.json
git log --oneline -10
ls -la podcastbrain/
```

Identify the highest-priority feature with `"passes": false`. That is your target.

Check system dependencies first:

```bash
source .venv/bin/activate
python3 -c "import whisper; print('whisper OK')"
python3 -c "import anthropic; print('anthropic OK')"
python3 -c "import sqlalchemy; print('sqlalchemy OK')"
python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"
```

---

### STEP 2: START THE STREAMLIT SERVER

```bash
source .venv/bin/activate
curl -s http://localhost:8501 > /dev/null && echo "Already running" || \
  nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &
sleep 3
tail -20 streamlit.log
```

**Streamlit URL:** <http://localhost:8501>
**CRITICAL:** Never use puppeteer_connect_active_tab. Always start fresh with puppeteer_navigate.

---

### STEP 3: READ THE SPEC AND FEATURE LIST

```bash
cat app_spec.txt
cat feature_list.json
cat podcastbrain/analyzer.py
cat podcastbrain/qa_engine.py
cat podcastbrain/app.py
```

Do not duplicate logic. Do not break existing passing features.

---

### STEP 4: IMPLEMENT THE FEATURE

**Python style:**

- snake_case for functions/variables, PascalCase for classes
- Every function has a docstring
- All file I/O uses explicit `encoding='utf-8'`
- No bare `except:` — always catch specific exceptions
- No hardcoded absolute paths — use `pathlib.Path`

---

#### yt-dlp and Whisper patterns (same as v2)

Use the same `download_audio()` and `transcribe_audio()` patterns from v2.
The `@st.cache_resource` on `load_whisper_model()` is mandatory.

---

#### Three separate Claude analysis functions

**All three must be separate functions in analyzer.py.** Never combine them into one call.

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

#### Q&A engine pattern

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
    # Keyword retrieval: score segments by keyword overlap
    keywords = {w.lower() for w in question.split() if len(w) > 3}
    scored = []
    for seg in segments:
        text_lower = seg["text"].lower()
        score = sum(1 for kw in keywords if kw in text_lower)
        scored.append((score, seg))
    scored.sort(key=lambda x: x[0], reverse=True)
    top_segments = [s for _, s in scored[:10]]

    # Format context with timestamps
    context_parts = []
    for seg in top_segments:
        mins, secs = divmod(int(seg["start"]), 60)
        context_parts.append(f"[{mins:02d}:{secs:02d}] {seg['text']}")
    context = "\n".join(context_parts)

    # Claude Q&A with grounding system prompt
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

    # Extract cited timestamps for source display
    import re
    cited_times = re.findall(r'\[(\d{2}:\d{2})\]', answer_text)
    sources = [
        {"start": seg["start"], "text": seg["text"]}
        for seg in top_segments
        if any(f"{int(seg['start'])//60:02d}:{int(seg['start'])%60:02d}" in t for t in cited_times)
    ]

    return {"answer": answer_text, "sources": sources}
```

**Critical Q&A rules:**

- System prompt MUST contain "Answer only from the provided transcript excerpts"
- Always use keyword retrieval (not embedding search) for segment selection in v3
- Return sources list so UI can display citation timestamps

---

#### SQLAlchemy 2.x patterns (v3 additions)

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

#### 4-tab Episode Viewer

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
        # Show existing Q&A history
        from podcastbrain.db import load_qa_history
        history = load_qa_history(episode_id)
        for exchange in history:
            with st.chat_message("user"):
                st.write(exchange["question"])
            with st.chat_message("assistant"):
                st.write(exchange["answer"])

        # New question input
        question = st.chat_input("Ask a question about this episode...")
        if question:
            from podcastbrain.qa_engine import answer_question
            with st.spinner("Thinking..."):
                result = answer_question(question, segments, ep.title)
            from podcastbrain.db import save_qa_exchange
            save_qa_exchange(episode_id, question, result["answer"], result["sources"])
            # Display the new exchange
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

#### Processing pipeline with all 3 Claude steps

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

            # Step 2: Transcribe
            st.write(f"Transcribing with Whisper ({model_name})...")
            transcription = transcriber.transcribe_audio(audio_path, model_name)
            with Session(engine) as session:
                session.add(Transcript(episode_id=episode_id,
                                        full_text=transcription["full_text"],
                                        segments=json.dumps(transcription["segments"]),
                                        word_count=transcription["word_count"]))
                session.commit()

            # Step 3: Claude chapter detection
            st.write("Detecting chapters...")
            chapters = analyzer.generate_chapters(transcription["full_text"])
            with Session(engine) as session:
                for ch in chapters:
                    session.add(Chapter(episode_id=episode_id, title=ch.get("title", ""),
                                        start_time=ch.get("start_time", 0), summary=ch.get("summary", "")))
                session.commit()

            # Step 4: Claude full analysis
            st.write("Generating summary, quotes, and action items...")
            analysis = analyzer.generate_summary_quotes_actions(transcription["full_text"])

            # Step 5: Claude speaker identification
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

### STEP 5: MANUAL SANITY CHECK

```bash
source .venv/bin/activate

for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"
tail -20 streamlit.log
```

---

### STEP 6: VERIFY WITH BROWSER AUTOMATION

1. Navigate to <http://localhost:8501> and screenshot
2. Test the full pipeline with a short audio file (upload `/tmp/test.mp3`)
3. Verify all 4 tabs appear after processing: Summary, Chapters, Transcript, Q&A
4. In Summary tab: verify summary text, quotes section, action items, speaker list
5. In Q&A tab: type a question, verify grounded answer with timestamp citations
6. Ask a second question, verify both exchanges show in chat history
7. Navigate to My Episodes, click episode, verify 4-tab viewer loads from DB

**Create test audio:**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**DON'T:**

- Use `puppeteer_connect_active_tab`
- Mark tests passing without browser verification

---

### STEP 7: MARK FEATURES PASSING

Edit `feature_list.json` — change `"passes": false` to `"passes": true` for browser-verified features.
**Never remove or edit feature descriptions or testing_steps.**

---

### STEP 8: COMMIT PROGRESS

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### STEP 9: UPDATE PROGRESS FILE

Update `claude-progress.txt` with completed features, file statuses, known issues, next priorities.

---

### STEP 10: VERIFY NOTHING BROKE

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

---

### IMPORTANT REMINDERS

**v3 Critical Rules:**

- Three separate Claude functions: `generate_chapters()`, `generate_summary_quotes_actions()`, `identify_speakers()` — NEVER combine into one call
- `episode.claude_analysis` stores ALL Claude results as one JSON blob: `{summary, quotes, action_items, speakers}`
- Q&A system prompt MUST contain "Answer only from the provided transcript excerpts"
- Q&A history persisted in `qa_history` table and loaded on every viewer open
- `st.chat_input()` + `st.chat_message()` for Q&A UI
- 4-tab order is fixed: Summary → Chapters → Transcript → Q&A
- Whisper model MUST use `@st.cache_resource`
- API key: try `/tmp/api-key` file first, fall back to `ANTHROPIC_API_KEY` env var
- Clean up temp audio files from `/tmp/podcastbrain-audio/` after pipeline completes

**Do not break existing passing features.** Read feature_list.json before starting.
