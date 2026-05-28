## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — CODING AGENT (Session 2+, v2: Audio + Whisper + Chapters)

You are a coding agent in an ongoing autonomous development process for **PodcastBrain v2** —
a Streamlit web application that downloads audio from YouTube, transcribes it locally
with OpenAI Whisper, detects chapters using Claude AI, and persists results in SQLite.

You pick up where the previous agent left off. Your job: implement features, verify them
through the browser, mark them passing in feature_list.json, and commit.

---

### STEP 1: ORIENT YOURSELF

```bash
pwd
cat claude-progress.txt          # What was done last session
cat feature_list.json            # Which features still need work
git log --oneline -10            # Recent commits
ls -la podcastbrain/             # Current file state
```

Identify the highest-priority feature with `"passes": false`. That is your target.

Check system dependencies first:

```bash
command -v ffmpeg && ffmpeg -version | head -1 || echo "ffmpeg MISSING"
source .venv/bin/activate
python3 -c "import whisper; print('whisper OK')" 2>/dev/null || echo "whisper not installed"
python3 -c "import anthropic; print('anthropic OK')" 2>/dev/null || echo "anthropic not installed"
python3 -c "import sqlalchemy; print('sqlalchemy OK')" 2>/dev/null || echo "sqlalchemy not installed"
```

If dependencies are missing: `source .venv/bin/activate && pip install -r requirements.txt`

---

### STEP 2: START THE STREAMLIT SERVER

If not already running:

```bash
source .venv/bin/activate
curl -s http://localhost:8501 > /dev/null && echo "Already running" || \
  nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &
sleep 3
```

Verify it is up:

```bash
curl -s http://localhost:8501 | head -20
```

If Streamlit fails to start, check logs:

```bash
tail -30 streamlit.log
```

Fix any import errors or syntax errors before proceeding.

**Streamlit URL:** <http://localhost:8501>
**CRITICAL:** Never use puppeteer_connect_active_tab. Always start fresh with puppeteer_navigate.

---

### STEP 3: READ THE SPEC AND FEATURE LIST

```bash
cat app_spec.txt
cat feature_list.json
```

Understand what the next feature requires. Read existing code before writing new code:

```bash
cat podcastbrain/db.py
cat podcastbrain/downloader.py
cat podcastbrain/transcriber.py
cat podcastbrain/analyzer.py
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

#### yt-dlp subprocess pattern (same as v1)

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

#### Whisper transcription pattern

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

**Critical Whisper rules:**

- The `@st.cache_resource` decorator prevents reloading the model on every Streamlit rerun
- NEVER call `whisper.load_model()` outside of `load_whisper_model()` — it takes 10-60 seconds
- Supported model names: `tiny`, `base`, `small`, `medium`, `large`
- Temp audio files must be stored in `/tmp/podcastbrain-audio/` and cleaned up after transcription is saved to DB

---

#### Claude chapter detection pattern

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

#### SQLAlchemy 2.x patterns

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

#### Streamlit app structure (v2 sidebar navigation)

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

#### Processing pipeline with st.status()

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

### STEP 5: MANUAL SANITY CHECK

Before browser verification:

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

Fix all errors before browser testing.

---

### STEP 6: VERIFY WITH BROWSER AUTOMATION

**CRITICAL:** You MUST verify UI features through the actual Streamlit browser interface.
Code that works in a Python shell but breaks in Streamlit is NOT passing.

1. **Navigate to the dashboard:**

   ```
   puppeteer_navigate: http://localhost:8501
   ```

2. **Take a screenshot to see current state:**

   ```
   puppeteer_screenshot
   ```

3. **Test the full pipeline:**
   - Use `puppeteer_fill` to enter a short YouTube URL (< 1 minute)
   - Click "Process Episode"
   - Screenshot during download to verify progress bar appears
   - Screenshot during Whisper to verify status indicator
   - Screenshot after completion to verify 2-tab Episode Viewer appears
   - Verify Transcript tab shows timestamped text
   - Verify Chapters tab shows chapter list

4. **Test My Episodes page:**
   - Navigate to My Episodes in sidebar
   - Verify processed episode appears in list
   - Click episode → verify viewer loads without reprocessing

5. **Test error handling:**
   - Type an invalid URL and click Process
   - Verify user-friendly error (not a Python traceback)

**Test with a short silent audio file to skip network download:**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

Upload via the file upload widget in Streamlit.

**DO:**

- Navigate to <http://localhost:8501> to test all features
- Take screenshots at each step
- Verify My Episodes page persists data across page navigations

**DON'T:**

- Use `puppeteer_connect_active_tab` — always start fresh with `puppeteer_navigate`
- Mark tests passing without verifying through the browser

---

### STEP 7: MARK FEATURES PASSING

Only after browser verification confirms the feature works:

Edit `feature_list.json` — change `"passes": false` to `"passes": true` for verified features.

**Never mark a feature passing if:**

- You only tested via Python (not browser)
- The feature partially works
- You see a Streamlit error box

**CRITICAL:** Never remove or edit feature descriptions or testing_steps. Only change "passes".

---

### STEP 8: COMMIT PROGRESS

After each verified feature:

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### STEP 9: UPDATE PROGRESS FILE

Update `claude-progress.txt` with:

- Features completed this session (IDs from feature_list.json)
- Current state of each source file (stub/partial/complete)
- Any known issues or limitations
- Recommended priority for next session

---

### STEP 10: VERIFY NOTHING BROKE

Before finishing, run a final check:

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

If any previously passing feature is now broken, fix it before ending the session.

---

### IMPORTANT REMINDERS

**v2 Critical Rules:**

- Whisper model MUST be loaded via `@st.cache_resource` — never reload per interaction
- Three separate DB tables: `episodes`, `transcripts`, `chapters`
- Processing pipeline MUST use `st.status()` for multi-step progress display
- `episode.status` must be set to `"complete"` only after all steps succeed
- My Episodes page must load from DB — never re-run the pipeline for existing episodes
- Temp audio files in `/tmp/podcastbrain-audio/` must be deleted after saving to DB
- Claude chapter detection must handle JSON parsing errors gracefully
- API key loading: try `/tmp/api-key` file first, fall back to `ANTHROPIC_API_KEY` env var
- SQLAlchemy 2.x: always use `with Session(engine) as session:` context manager

**Do not break existing passing features.** Read feature_list.json before starting.
