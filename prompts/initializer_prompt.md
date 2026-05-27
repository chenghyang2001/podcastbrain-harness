## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- DO NOT run `git init` — a git repository has already been initialized in your cwd
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE - INITIALIZER AGENT (Session 1 of Many)

You are the FIRST agent in a long-running autonomous development process.
Your job is to set up the foundation for all future coding agents.

This project builds **PodcastBrain** — a Streamlit web application that converts podcast episodes
and YouTube videos into structured knowledge assets using yt-dlp for download, local Whisper for
transcription, and Claude AI for chapter detection, summarization, and interactive Q&A.

Tech stack: Python 3.11+, Streamlit (port 8501), yt-dlp, openai-whisper (local, no API key),
Anthropic Claude claude-sonnet-4-6, SQLite via SQLAlchemy 2.x with FTS5, pydub, reportlab.

---

### FIRST: Read the Project Specification

Start by reading `app_spec.txt` in your working directory. This file contains the complete
specification for what you need to build. Read it carefully before proceeding.

---

### CRITICAL FIRST TASK: Create feature_list.json

Based on `app_spec.txt`, create a file called `feature_list.json` with __NUM_FEATURES__
detailed end-to-end test cases. This file is the single source of truth for all future coding
agents — it defines exactly what must be built and how to verify it.

**Requirements for feature_list.json:**

```json
[
  {
    "id": 1,
    "feature": "Streamlit dashboard loads at port 8501",
    "category": "functional",
    "priority": 1,
    "passes": false,
    "testing_steps": [
      "puppeteer_navigate to http://localhost:8501",
      "puppeteer_screenshot to verify page loaded",
      "Check page title or header contains 'PodcastBrain'",
      "Verify sidebar navigation is visible with Process New / Library / Batch options"
    ]
  }
]
```

- EXACTLY **NUM_FEATURES** features total
- Both "functional" and "style" categories represented
- Mix of narrow (2-5 steps) and comprehensive (10+ steps) tests
- At least 1 test MUST have 10+ steps
- Priority order: fundamental features first (dashboard loads → input form → processing pipeline → viewer → Q&A → library → export)
- ALL start with "passes": false
- Testing approach: browser automation via puppeteer tools (navigate to <http://localhost:8501>)
- Start each test with puppeteer_navigate; never use puppeteer_connect_active_tab
- Cover all major features and the complete processing pipeline

**Feature areas to cover:**

1. Dashboard loads and sidebar navigation renders
2. URL input form accepts a YouTube URL
3. File upload widget accepts .mp3 and .m4a files
4. Whisper model selection dropdown shows all 5 options
5. "Process Episode" button triggers processing pipeline
6. Download progress shown during yt-dlp phase
7. Transcription progress shown during Whisper phase
8. Claude analysis runs and produces chapters
9. Episode viewer appears after processing with 4 tabs
10. Summary tab shows formatted summary, quotes, and action items
11. Chapters tab shows timeline and chapter cards
12. Transcript tab shows timestamped text with search
13. Q&A tab accepts a question and returns a cited answer
14. Q&A answer contains source citation from transcript
15. Episode library page shows processed episodes
16. Library FTS5 search finds episodes by keyword
17. Library filter by date range works
18. Batch queue accepts multiple URLs
19. Batch queue processes sequentially with status updates
20. Markdown export downloads non-empty .md file
21. PDF export downloads non-empty .pdf file
22. SRT export downloads valid subtitle file
23. ZIP export contains multiple files
24. Error handling: invalid URL shows user-friendly error
25. Error handling: unsupported file type rejected with message
26. Re-opening a processed episode loads from DB (no re-processing)
27. Style: chat interface renders Q&A history correctly
28. Style: chapter timeline is a visual bar chart (not plain text)
29. Style: episode cards in library use a grid layout
30. Style: no layout overflow on standard 1280px viewport

**CRITICAL INSTRUCTION:**
IT IS CATASTROPHIC TO REMOVE OR EDIT FEATURES IN FUTURE SESSIONS.
Features can ONLY be marked as passing (change "passes": false to "passes": true).
Never remove features, never edit descriptions, never modify testing steps.
Future agents depend on this file exactly as written.

---

### SECOND TASK: Create init.sh

Create an executable `init.sh` that a fresh Linux environment can run to bootstrap the project
completely. The script must:

```bash
#!/bin/bash
set -e

echo "=== PodcastBrain Init ==="

# 1. Check system dependencies
command -v ffmpeg >/dev/null 2>&1 || {
    echo "ffmpeg not found. Installing..."
    apt-get update -qq && apt-get install -y -qq ffmpeg
}

# 2. Create Python virtual environment
python3 -m venv .venv

# 3. Activate and install dependencies
source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 4. Create temp directory for audio files
mkdir -p /tmp/podcastbrain-audio

# 5. Initialize SQLite database (create all tables including FTS5)
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

Also create `requirements.txt` with pinned or minimum versions:

```
streamlit>=1.35.0
yt-dlp>=2024.1.0
openai-whisper>=20231117
anthropic>=0.25.0
sqlalchemy>=2.0.0
pydub>=0.25.1
reportlab>=4.0.0
ffmpeg-python>=0.2.0
```

**Important note about FTS5:** The `init_db()` function in db.py must execute the FTS5
virtual table CREATE statement and the trigger via raw SQL (`conn.execute(text(...))`)
because SQLAlchemy ORM does not support FTS5 virtual tables natively. Use `engine.connect()`
and `connection.execute(text(...))` after `Base.metadata.create_all()`.

---

### THIRD TASK: Initialize Git

Add and commit all created files:

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain project: feature list, init script, requirements"
```

If README.md does not exist, create a minimal one first:

```markdown
# PodcastBrain

Turn podcast episodes and YouTube videos into structured knowledge assets.

## Quick Start
```bash
bash init.sh
# Open http://localhost:8501
```

## Requirements

- ffmpeg (system package)
- ANTHROPIC_API_KEY environment variable or /tmp/api-key file

## Features

- YouTube and direct URL audio download via yt-dlp
- Local Whisper transcription (no audio leaves your machine)
- Claude AI chapter detection and summarization
- Interactive Q&A grounded in transcript
- Full-text search across all episodes
- Export to Markdown, PDF, SRT, TXT

```

---

### FOURTH TASK: Create Project Structure

Create the full package directory structure with stub files:

```

podcastbrain/
  **init**.py
  app.py              — Streamlit entry point, sidebar navigation, page routing
  downloader.py       — yt-dlp subprocess wrapper, progress parsing, cancel support
  transcriber.py      — Whisper transcription, segment output, progress estimation
  analyzer.py         — Claude: chapters, summary+quotes+actions, speaker ID
  qa_engine.py        — keyword segment retrieval, Claude Q&A prompt, response parser
  db.py               — SQLAlchemy ORM models, FTS5 setup, session factory, init_db()

```

For each file, create at minimum:
- Module docstring explaining purpose
- Import statements
- Class/function signatures with docstrings and `pass` bodies
- `if __name__ == "__main__":` smoke test block

The goal is that future coding agents can fill in implementations without restructuring.

**db.py must be functional** (not a stub) because init.sh calls `init_db()`. Implement all
4 SQLAlchemy ORM models, the FTS5 virtual table DDL, the after-insert trigger DDL, and the
`init_db()` function that creates everything. This is the most critical file to get right.

**FTS5 setup pattern:**
```python
from sqlalchemy import text

def init_db():
    """Create all tables including FTS5 virtual table and trigger."""
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
```

---

### OPTIONAL: Start Implementation

If time permits after completing the above four tasks, begin implementing in priority order:

1. **db.py** (must be complete — init.sh depends on it)
2. **downloader.py** — implement `download_audio()` with yt-dlp subprocess at minimum
3. **transcriber.py** — implement `transcribe_audio()` stub that calls whisper
4. **app.py** — implement sidebar navigation and "Process New" page skeleton

Work on ONE feature at a time. After implementing a feature:

- Test it (run the module directly or verify in Streamlit)
- Only mark "passes": true in feature_list.json after verifying through browser
- Commit before moving to the next feature

**For testing transcription without downloading:** Use any local .mp3 or .wav file.
Create a short test audio file:

```bash
# Using ffmpeg to create a 5-second silent test audio
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

Then upload it via the file upload widget in Streamlit.

---

### ENDING THIS SESSION

Before finishing:

1. **Commit all work** with descriptive message:

   ```bash
   git add -A
   git commit -m "Session 1: scaffold, feature list, DB models with FTS5, initial stubs"
   ```

2. **Create `claude-progress.txt`** summarizing:
   - What was completed this session
   - Current state of each file (stub/partial/complete)
   - Which feature_list.json items are now passing
   - Any issues encountered (e.g., ffmpeg not installed in test environment)
   - Recommended next steps for Session 2

3. **Verify feature_list.json** is valid JSON with **NUM_FEATURES** entries, all with "passes": false
   (or true only for features you verified through the browser)

4. **Verify init.sh is executable:** `chmod +x init.sh`

5. **Leave environment clean**: Streamlit either running or gracefully stopped, no temp audio
   files left uncommitted, no Python processes crashing

**Remember:** This is Session 1 of many. Quality and correctness of the scaffold matter more
than implementation speed. The FTS5 setup is the trickiest part — get it right before proceeding.
Future agents will build on exactly what you leave behind.
