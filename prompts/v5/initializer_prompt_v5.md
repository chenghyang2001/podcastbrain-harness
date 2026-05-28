## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — INITIALIZER AGENT (Session 1, v5: Batch Processing Queue)

You are the **first agent** in a multi-session autonomous development pipeline.
Your job is to establish the foundation for all future coding agents.

This project builds **PodcastBrain v5** — the complete production-ready version,
extending v4 with a Batch Processing Queue that accepts multiple YouTube URLs,
processes them sequentially with live status updates, and adds a Plotly-based
visual chapter timeline in the Episode Viewer.

Tech stack: Python 3.11+, Streamlit (port 8501), yt-dlp, openai-whisper (local),
Anthropic Claude claude-sonnet-4-6, SQLAlchemy 2.x + SQLite with FTS5,
pydub, reportlab, plotly, ffmpeg-python.

---

### First: Read the project specification

Start by reading `app_spec.txt` from the working directory. This file contains the complete
specification of what you need to build. Read it carefully before proceeding.

---

### Task 1: Create feature_list.json

Based on `app_spec.txt`, create a file named `feature_list.json` with exactly **30**
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
      "Verify sidebar contains 'Episode Library' navigation item",
      "Verify sidebar contains 'Batch Queue' navigation item (fully functional)"
    ]
  }
]
```

- Exactly **30** features total
- Include both "functional" and "style" categories
- Mix narrow (2-5 steps) and comprehensive (10+ steps) tests
- At least 1 test must have 10+ steps
- Priority: foundational first (app loads → input → pipeline → viewer → exports → library → batch → style)
- All start with `"passes": false`
- Testing via browser automation through puppeteer tools (navigate to <http://localhost:8501>)
- Every test starts with puppeteer_navigate; **never use puppeteer_connect_active_tab**
- Cover all major features and the complete processing pipeline

**Feature areas to cover (30 total):**

1. App loads at port 8501 with sidebar navigation (Process New, Episode Library, Batch Queue)
2. URL input field accepts YouTube watch URLs
3. File upload widget accepts .mp3 and .m4a files
4. Whisper model selection dropdown shows all 5 options (tiny, base, small, medium, large)
5. "Process Episode" button triggers the full processing pipeline
6. Download phase shows yt-dlp progress bar updating live
7. Whisper transcription phase shows progress indicator
8. Claude chapter detection runs and produces chapter list
9. Claude full analysis runs: summary, key quotes, action items
10. Claude speaker identification runs
11. Episode Viewer appears with 4 tabs: Summary, Chapters, Transcript, Q&A
12. Summary tab displays formatted summary, quotes, and action items
13. Chapters tab displays a visual Plotly horizontal bar chart timeline (not plain text list)
14. Transcript tab displays text with timestamps and keyword search
15. Q&A tab accepts question and returns grounded answer with citations
16. Q&A answer includes source citation timestamps
17. Markdown export downloads a non-empty .md file
18. PDF export downloads a non-empty .pdf file
19. SRT export downloads a valid subtitle file with HH:MM:SS,mmm timestamps
20. ZIP export downloads an archive containing multiple files
21. Episode Library page displays processed episodes in a 3-column card grid
22. FTS5 search by keyword finds episodes containing that word in the transcript
23. Date range filter in library narrows results correctly
24. Clicking an episode card opens its viewer without reprocessing
25. Batch Queue page accepts multiple URLs via textarea (one URL per line)
26. "Add to Queue" button saves all URLs as queued episodes in the database
27. Batch Queue processes episodes sequentially with per-episode status updates
28. Batch Queue auto-refreshes every 5 seconds to show current processing status
29. Style: chapter timeline is a visual horizontal bar chart (Plotly), not a plain list
30. Style: no layout overflow at standard 1280px window width

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

# 5. Initialize SQLite database (creates all tables including FTS5)
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized with FTS5 support')
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
pydub>=0.25.1
reportlab>=4.0.0
plotly>=5.18.0
ffmpeg-python>=0.2.0
```

---

### Task 3: Initialize Git

Add and commit all created files:

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v5: feature list, init script, requirements"
```

If README.md does not exist, create a minimal one first:

```markdown
# PodcastBrain v5 — Complete Production Version

Full podcast knowledge extraction with batch processing, visual timelines, and multi-format export.

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
- Claude AI: chapters, summary, quotes, action items, speakers
- Interactive Q&A with transcript citations
- Visual chapter timeline (Plotly horizontal bar chart)
- Export: Markdown, PDF, SRT, TXT, ZIP
- Episode Library with FTS5 full-text search and date filtering
- Batch Queue: process multiple URLs sequentially with live status
- SQLite persistence with FTS5 virtual table

```

---

### Task 4: Create Project Structure

Create the package directory structure with stub files:

```

podcastbrain/
  **init**.py
  app.py         — Streamlit entry point: sidebar nav, 3 pages (Process New, Library, Batch Queue)
  downloader.py  — yt-dlp subprocess wrapper: progress parsing, cancel support
  transcriber.py — Whisper transcription: model loading (cached), segment output
  analyzer.py    — Claude: 3 separate functions (chapters, summary+quotes+actions, speakers)
  qa_engine.py   — Q&A: keyword retrieval, Claude grounded prompt, response parser
  exporter.py    — Export: MD, PDF (reportlab), SRT, TXT, ZIP
  db.py          — SQLAlchemy ORM models, FTS5 setup, session factory, init_db()

```

For each file, at minimum create:
- A module docstring explaining the purpose
- Import statements
- Class/function signatures with docstrings and `pass` body
- `if __name__ == "__main__":` smoke test block

The goal is for future coding agents to fill in implementations without needing to re-architect.

**db.py must be functional** (not a stub), because init.sh calls `init_db()`.
Implement all 4 SQLAlchemy ORM models, the FTS5 virtual table DDL, the after-insert
trigger DDL, and the `init_db()` function.

**v5 DB schema — same 4 ORM tables as v4 + FTS5:**

```python
from sqlalchemy import Column, Integer, String, Float, Text, DateTime, ForeignKey, create_engine, text
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
    status = Column(String, default="pending")   # pending / queued / processing / complete / error
    claude_analysis = Column(Text)               # JSON: {summary, quotes, action_items, speakers}
    created_at = Column(DateTime, default=datetime.utcnow)
    transcripts = relationship("Transcript", back_populates="episode", cascade="all, delete-orphan")
    chapters = relationship("Chapter", back_populates="episode", cascade="all, delete-orphan")
    qa_history = relationship("QAHistory", back_populates="episode", cascade="all, delete-orphan")

class Transcript(Base):
    __tablename__ = "transcripts"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    full_text = Column(Text)
    segments = Column(Text)    # JSON [{start, end, text}]
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

class QAHistory(Base):
    __tablename__ = "qa_history"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    question = Column(Text, nullable=False)
    answer = Column(Text, nullable=False)
    source_ts = Column(Text)    # JSON list of cited timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    episode = relationship("Episode", back_populates="qa_history")


def init_db():
    """Create all ORM tables plus FTS5 virtual table and after-insert trigger."""
    Base.metadata.create_all(engine)
    with engine.connect() as conn:
        conn.execute(text("""
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(
                episode_id UNINDEXED,
                full_text,
                content='transcripts',
                content_rowid='id'
            )
        """))
        conn.execute(text("""
            CREATE TRIGGER IF NOT EXISTS transcripts_ai
            AFTER INSERT ON transcripts BEGIN
                INSERT INTO transcripts_fts(rowid, episode_id, full_text)
                VALUES (new.id, new.episode_id, new.full_text);
            END
        """))
        conn.commit()
    print("DB initialized (v5: 4 tables + FTS5 virtual table + trigger)")
```

**Episode.status values in v5:**

- `pending` — newly created, not yet queued
- `queued` — added to batch queue, waiting for processing
- `processing` — currently being processed
- `complete` — fully processed, all tabs available
- `error` — processing failed, error details in claude_analysis field

---

### Optional: Start Implementation

If time remains after the above four tasks, implement in priority order:

1. **db.py** — Complete (required for init.sh)
2. **downloader.py** — `download_audio()` with yt-dlp subprocess and progress parsing
3. **transcriber.py** — `transcribe_audio()` calling Whisper
4. **analyzer.py** — Three Claude functions
5. **qa_engine.py** — `answer_question()` with keyword retrieval
6. **exporter.py** — All 5 export formats
7. **app.py** — 3 pages: Process New, Episode Library, Batch Queue with auto-refresh

After implementing each file:

- Test it (run the module directly or launch Streamlit and verify in the browser)
- Only mark `"passes": true` in feature_list.json after **browser** verification
- Commit before moving to the next file

**Test audio without downloading:**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

---

### Ending This Session

Before finishing:

1. **Commit all work**:

   ```bash
   git add -A
   git commit -m "Session 1: v5 scaffold, feature list, DB with FTS5, initial stubs"
   ```

2. **Create `claude-progress.txt`** summarizing:
   - What was completed this session
   - Current status of each file (stub/partial/complete)
   - Which feature_list.json items now pass
   - Any issues encountered
   - Suggested next steps for Session 2

3. **Confirm feature_list.json** is valid JSON with exactly **30** entries, all `"passes": false`
   (only mark true for features verified via browser)

4. **Confirm init.sh is executable:** `chmod +x init.sh`

5. **Keep the environment clean**: Streamlit running or gracefully stopped

**Remember:** The Batch Queue and Plotly timeline are the new additions over v4.
The FTS5 setup is identical to v4 — get it right first.
Architecture and correctness matter more than speed.
