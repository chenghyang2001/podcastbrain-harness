## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — INITIALIZER AGENT (Session 1, v2: Audio + Whisper + Chapters)

You are the **first agent** in a multi-session autonomous development pipeline.
Your job is to establish the foundation for all future coding agents.

This project builds **PodcastBrain v2** — a Streamlit web application that downloads
audio from YouTube URLs using yt-dlp, transcribes it locally using OpenAI Whisper,
and detects chapters using Claude AI. Results are persisted in a SQLite database and
browsable through a sidebar-navigated episode viewer.

Tech stack: Python 3.11+, Streamlit (port 8501), yt-dlp, openai-whisper (local),
Anthropic Claude claude-sonnet-4-6, SQLAlchemy 2.x + SQLite, ffmpeg-python.

---

### First: Read the project specification

Start by reading `app_spec.txt` from the working directory. This file contains the complete
specification of what you need to build. Read it carefully before proceeding.

---

### Task 1: Create feature_list.json

Based on `app_spec.txt`, create a file named `feature_list.json` with exactly **14**
detailed end-to-end test cases. This file is the single source of truth for all future
coding agents — it defines precisely what must be built and how to verify it.

**feature_list.json format:**

```json
[
  {
    "id": 1,
    "feature": "Streamlit app loads at port 8501 with sidebar navigation",
    "category": "functional",
    "priority": 1,
    "passes": false,
    "testing_steps": [
      "puppeteer_navigate to http://localhost:8501",
      "puppeteer_screenshot to verify page loaded",
      "Check page title or header contains 'PodcastBrain'",
      "Verify sidebar contains 'Process New Episode' navigation item",
      "Verify sidebar contains 'My Episodes' navigation item"
    ]
  }
]
```

- Exactly **14** features total
- Include both "functional" and "style" categories
- Mix narrow (2-5 steps) and comprehensive (10+ steps) tests
- At least 1 test must have 10+ steps
- Priority: foundational first (app loads → input → processing pipeline → viewer → library → style)
- All start with `"passes": false`
- Testing via browser automation through puppeteer tools (navigate to <http://localhost:8501>)
- Every test starts with puppeteer_navigate; **never use puppeteer_connect_active_tab**
- Cover all major features and the complete processing pipeline

**Feature areas to cover (14 total):**

1. App loads at port 8501 with sidebar navigation (Process New Episode, My Episodes)
2. URL input field accepts YouTube watch URLs
3. File upload widget accepts .mp3 and .m4a files
4. Whisper model selection dropdown shows all 5 options (tiny, base, small, medium, large)
5. "Process Episode" button triggers the full processing pipeline
6. Download phase shows yt-dlp progress bar updating live
7. Whisper transcription phase shows progress indicator and model name
8. Claude chapter detection runs and produces chapter list
9. Episode Viewer appears after processing with 2 tabs: Transcript and Chapters
10. Transcript tab displays full transcribed text with timestamps
11. Chapters tab displays chapter list with title and timestamp for each chapter
12. My Episodes page lists all previously processed episodes
13. Clicking a processed episode opens its viewer without reprocessing (loads from DB)
14. Style: sidebar layout has no overflow at standard 1280px window width

**Important instructions:**
Removing or editing features in future sessions is catastrophic.
Features may only be marked as passing (change `"passes": false` to `"passes": true`).
Never remove features, never edit descriptions, never modify testing_steps.
Future agents rely on the exact content of this file.

---

### Task 2: Create init.sh and requirements.txt

Create an executable `init.sh` that bootstraps the project in a fresh Linux environment:

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

# 4. Create audio temp directory and downloads directory
mkdir -p /tmp/podcastbrain-audio
mkdir -p downloads

# 5. Initialize SQLite database (creates all tables)
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized')
"

# 6. Start Streamlit on port 8501 in background
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

Also create `requirements.txt` with pinned minimum versions:

```
streamlit>=1.35.0
yt-dlp>=2024.1.0
openai-whisper>=20231117
anthropic>=0.25.0
sqlalchemy>=2.0.0
ffmpeg-python>=0.2.0
```

---

### Task 3: Initialize Git

Add and commit all created files:

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v2: feature list, init script, requirements"
```

If README.md does not exist, create a minimal one first:

```markdown
# PodcastBrain v2 — Audio + Whisper + Chapters

Downloads audio from YouTube, transcribes locally with Whisper, detects chapters with Claude AI.

## Quick Start
```bash
bash init.sh
# Open http://localhost:8501
```

## Requirements

- Python 3.11+
- ffmpeg (system package)
- ANTHROPIC_API_KEY environment variable or /tmp/api-key file

## Features

- Download YouTube and direct URL audio via yt-dlp
- Local Whisper transcription (audio never leaves your machine)
- Claude AI chapter detection
- Episode library with transcript and chapter viewer
- SQLite persistence across sessions

```

---

### Task 4: Create Project Structure

Create the package directory structure with stub files:

```

podcastbrain/
  **init**.py
  app.py         — Streamlit entry point: sidebar nav, Process New page, My Episodes page
  downloader.py  — yt-dlp subprocess wrapper: progress parsing, cancel support
  transcriber.py — Whisper transcription: model loading (cached), segment output
  analyzer.py    — Claude: chapter detection only (v2 scope)
  db.py          — SQLAlchemy ORM models, session factory, init_db()

```

For each file, at minimum create:
- A module docstring explaining the purpose
- Import statements
- Class/function signatures with docstrings and `pass` body
- `if __name__ == "__main__":` smoke test block

The goal is for future coding agents to fill in implementations without needing to re-architect.

**db.py must be functional** (not a stub), because init.sh calls `init_db()`.
Implement all 3 SQLAlchemy ORM models and the `init_db()` function.

**v2 DB schema — 3 tables:**

```python
from sqlalchemy import Column, Integer, String, Float, Text, DateTime, ForeignKey, create_engine
from sqlalchemy.orm import DeclarativeBase, relationship
from datetime import datetime
from pathlib import Path

DB_PATH = Path.cwd() / "podcastbrain.db"
engine = create_engine(f"sqlite:///{DB_PATH}", echo=False)

class Base(DeclarativeBase):
    pass

class Episode(Base):
    __tablename__ = "episodes"
    id = Column(Integer, primary_key=True)
    title = Column(String, nullable=False)
    url = Column(String)
    audio_path = Column(String)
    duration_seconds = Column(Float)
    whisper_model = Column(String)
    status = Column(String, default="pending")   # pending / processing / complete / error
    created_at = Column(DateTime, default=datetime.utcnow)
    transcripts = relationship("Transcript", back_populates="episode", cascade="all, delete-orphan")
    chapters = relationship("Chapter", back_populates="episode", cascade="all, delete-orphan")

class Transcript(Base):
    __tablename__ = "transcripts"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    full_text = Column(Text)
    segments = Column(Text)   # JSON string of [{start, end, text}]
    word_count = Column(Integer)
    episode = relationship("Episode", back_populates="transcripts")

class Chapter(Base):
    __tablename__ = "chapters"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    title = Column(String, nullable=False)
    start_time = Column(Float)
    summary = Column(Text)
    episode = relationship("Episode", back_populates="chapters")

def init_db():
    """Create all tables."""
    Base.metadata.create_all(engine)
    print("DB initialized (v2: episodes, transcripts, chapters)")
```

**No FTS5 in v2** — full-text search is not required until v4.

---

### Optional: Start Implementation

If time remains after the above four tasks, implement in priority order:

1. **db.py** — Complete (required for init.sh)
2. **downloader.py** — `download_audio()` with yt-dlp subprocess and progress parsing
3. **transcriber.py** — `transcribe_audio()` calling `whisper.load_model()` + `model.transcribe()`
4. **analyzer.py** — `generate_chapters()` calling Claude API
5. **app.py** — Sidebar navigation + Process New Episode page skeleton

After implementing each file:

- Test it (run the module directly or launch Streamlit and verify in the browser)
- Only mark `"passes": true` in feature_list.json after **browser** verification
- Commit before moving to the next file

**Test audio without downloading:** Create a short silent test file:

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

Then upload via the Streamlit file upload widget.

---

### Ending This Session

Before finishing:

1. **Commit all work**:

   ```bash
   git add -A
   git commit -m "Session 1: v2 scaffold, feature list, DB models, initial stubs"
   ```

2. **Create `claude-progress.txt`** summarizing:
   - What was completed this session
   - Current status of each file (stub/partial/complete)
   - Which feature_list.json items now pass
   - Any issues encountered
   - Suggested next steps for Session 2

3. **Confirm feature_list.json** is valid JSON with exactly **14** entries, all `"passes": false`
   (only mark true for features verified via browser)

4. **Confirm init.sh is executable:** `chmod +x init.sh`

5. **Keep the environment clean**: Streamlit running or gracefully stopped

**Remember:** Architecture and correctness matter more than speed.
The DB schema and init_db() function are the most critical parts to get right.
Future agents will build entirely on the foundation you leave behind.
