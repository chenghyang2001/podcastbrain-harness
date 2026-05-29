## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — INITIALIZER AGENT (Session 1, v1 MVP: Audio Downloader)

You are the **first agent** in a multi-session autonomous development pipeline.
Your job is to establish the foundation for all future coding agents.

This project builds **PodcastBrain v1** — a minimal Streamlit web application
that accepts a YouTube URL or direct audio link and downloads the audio file to a
local directory using yt-dlp. The user sees download progress in real time and
retrieves the saved file path when done.

**No transcription, no AI analysis, no database.** The single goal is to prove that
audio acquisition works reliably before layering any intelligence on top.

Tech stack: Python 3.11+, Streamlit (port 8501), yt-dlp, ffmpeg-python.

---

### First: Read the project specification

Start by reading `app_spec.txt` from the working directory. This file contains the complete
specification of what you need to build. Read it carefully before proceeding.

---

### Task 1: Create OR Evolve feature_list.json

`feature_list.json` is the single source of truth for all future coding agents —
it defines precisely what must be built and how to verify it.

> **EVOLUTION MODE — this harness must keep working when `app_spec.txt` is replaced
> by a newer version (e.g. the contents of `app_spec_v2.txt` copied over
> `app_spec.txt`). You therefore run in one of two modes. Detect the mode FIRST.**

#### Step 1A — Mode Detection (do this before writing anything)

```bash
ls feature_list.json 2>/dev/null && echo "EXISTS -> APPEND MODE" || echo "MISSING -> CREATE MODE"
```

**CREATE MODE** (`feature_list.json` does NOT exist — fresh v1 project):

- Parse `app_spec.txt` and create exactly **8** detailed end-to-end test cases.
- Every feature starts as: `"passes": false`, `"status": "new"`, `"version_added": "v1"`.

**APPEND MODE** (`feature_list.json` ALREADY exists — you are evolving an existing
project against a changed spec). You MUST NOT skip, regenerate, or overwrite. Do this:

1. **Read** the existing `feature_list.json` in full.
2. **Lock the stable base:** for every existing feature whose `"passes": true`, set
   `"status": "stable"`. This marks it as a protected, shipped feature.
3. **Diff against the new spec:** read `app_spec.txt` and identify every requirement
   that is **not already covered** by an existing feature.
4. **Append (never overwrite):** add a new feature entry for each uncovered
   requirement, with a fresh incrementing `id`, `"passes": false`, `"status": "new"`,
   and `"version_added"` set to the next version label (e.g. `"v2"`). If an existing
   feature's *meaning* changed in the spec, append a NEW feature describing the change
   and you may set the affected existing feature's `"status": "modified"` — but still
   never edit its description or testing_steps.
5. **Idempotency:** if the spec introduces no new requirement, leave the file
   byte-for-byte unchanged and report "no new features — already up to date".

**HARD RULES for APPEND MODE (catastrophic if violated):**

- NEVER delete an existing feature.
- NEVER edit an existing feature's `feature`, `category`, or `testing_steps`.
- NEVER flip a `"passes": true` back to `false`.
- Old features keep their original `version_added` forever.

**feature_list.json format (both modes):**

```json
[
  {
    "id": 1,
    "feature": "Streamlit app loads at port 8501",
    "category": "functional",
    "priority": 1,
    "passes": false,
    "status": "new",
    "version_added": "v1",
    "testing_steps": [
      "puppeteer_navigate to http://localhost:8501",
      "puppeteer_screenshot to verify page loaded",
      "Check page title or header contains 'PodcastBrain'",
      "Verify URL input field is visible on the page"
    ]
  }
]
```

> `status` is one of `"new"` | `"modified"` | `"stable"`. `version_added` records the
> spec version that introduced the feature and is never rewritten on old features.

The instructions below (feature areas, counts) describe the **CREATE MODE** v1 baseline.

- Exactly **8** features total
- Include both "functional" and "style" categories
- Mix narrow (2-5 steps) and comprehensive (8+ steps) tests
- At least 1 test must have 8+ steps
- Priority: foundational first (app loads → URL input → download trigger → progress → file saved → error handling → cancel → style)
- All start with `"passes": false`
- Testing via browser automation through puppeteer tools (navigate to <http://localhost:8501>)
- Every test starts with puppeteer_navigate; **never use puppeteer_connect_active_tab**

**Feature areas to cover (8 total):**

1. App loads at port 8501 — header "PodcastBrain" visible, URL input field visible
2. URL input field accepts YouTube watch URLs (text appears in the field)
3. "Download Audio" button is visible and clickable
4. Progress bar increments from 0% to 100% during yt-dlp download
5. Downloaded file appears in ./downloads/ directory after completion; success message shows file path and size
6. Invalid URL shows a user-friendly error message (not a Python traceback)
7. Cancel button stops the active download and removes the partial file
8. Style: single-page layout has no overflow at standard 1280px window width

In CREATE MODE these 8 features all get `"status": "new"`, `"version_added": "v1"`.

**Important instructions:**
Removing or editing features in future sessions is catastrophic.
Features may only be marked as passing (change `"passes": false` to `"passes": true`).
Never remove features, never edit descriptions, never modify testing_steps.
Future agents rely on the exact content of this file.

**Scope your tests to THIS version's spec only (avoid temporal mismatch):**
Only write testing_steps that exercise modules and behaviour defined in the current
`app_spec.txt`. Do NOT add tests that check for higher-level modules or files that a
later version might introduce (e.g. transcription, database, charting) — those do not
exist yet and will trap the coding agent in an unwinnable loop. New capabilities arrive
only when a future spec adds them, via APPEND MODE.

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

Also create `requirements.txt`:

```
streamlit>=1.35.0
yt-dlp>=2024.1.0
ffmpeg-python>=0.2.0
```

---

### Task 3: Initialize Git

Add and commit all created files:

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v1: feature list, init script, requirements"
```

If README.md does not exist, create a minimal one first:

```markdown
# PodcastBrain v1 — Audio Downloader

Downloads audio from YouTube URLs and direct audio links using yt-dlp.

## Quick Start
```bash
bash init.sh
# Open http://localhost:8501
```

## Requirements

- Python 3.11+
- ffmpeg (system package — `sudo apt-get install ffmpeg`)

## Features

- Download YouTube and direct URL audio via yt-dlp
- Real-time progress bar during download
- Cancel button stops download and removes partial file
- Files saved to ./downloads/ directory

```

---

### Task 4: Create Project Structure

Create the package directory structure with stub files:

```

podcastbrain/
  **init**.py
  app.py         — Streamlit entry point: URL input, progress bar, download/cancel control
  downloader.py  — yt-dlp subprocess wrapper: progress parsing, cancel support

```

For each file, at minimum create:
- A module docstring explaining the purpose
- Import statements
- Class/function signatures with docstrings and `pass` body
- `if __name__ == "__main__":` smoke test block

The goal is for future coding agents to fill in implementations without needing to re-architect.

**Both files should be functional** if time allows, since the test harness will launch the app.
Target implementations:

- **downloader.py** — `download_audio(url, output_dir, progress_callback)`:
  - Spawns yt-dlp subprocess with `--format bestaudio --extract-audio --audio-format mp3 --newline`
  - Reads stdout line-by-line, extracts progress with `re.search(r'\[download\]\s+(\d+\.\d+)%', line)`
  - Calls `progress_callback(float)` with each parsed percentage
  - Implements `cancel_download(process)` using `process.terminate()` + partial file cleanup
  - Returns `{file_path, title, file_size_mb}` on success, raises exception on failure

- **app.py** — Single-page Streamlit app:
  - `st.text_input` for URL entry
  - "Download Audio" button starts download in background thread, stores process in `st.session_state`
  - `st.progress()` updated from a polling loop via `st.empty()`
  - "Cancel" button sets `st.session_state.cancel_flag = True` → terminates process
  - `st.success()` on completion, `st.error()` on failure (never raw tracebacks)

---

### Optional: Start Implementation

If time remains after the above four tasks, implement in priority order:

1. **downloader.py** — Complete `download_audio()` with yt-dlp subprocess and progress parsing
2. **app.py** — Complete the single-page UI

After implementing each file:
- Test it (run the module directly or launch Streamlit and verify in the browser)
- Only mark `"passes": true` in feature_list.json after **browser** verification
- Commit before moving to the next file

Test with a known short YouTube URL to verify progress parsing:
```bash
source .venv/bin/activate
python3 -c "
from podcastbrain.downloader import download_audio
result = download_audio('https://www.youtube.com/watch?v=jNQXAC9IVRw', './downloads', print)
print(result)
"
```

---

### Ending This Session

Before finishing:

1. **Commit all work**:

   ```bash
   git add -A
   git commit -m "Session 1: v1 scaffold, feature list, downloader and app stubs"
   ```

2. **Create `claude-progress.txt`** summarizing:
   - What was completed this session
   - Current status of each file (stub/partial/complete)
   - Which feature_list.json items now pass
   - Any issues encountered (e.g., ffmpeg not installed in test environment)
   - Suggested next steps for Session 2

3. **Confirm feature_list.json** is valid JSON and every entry has `id`, `feature`,
   `category`, `priority`, `passes`, `status`, `version_added`, `testing_steps`.
   - CREATE MODE: exactly **8** entries, all `"passes": false`, all `"status": "new"`,
     all `"version_added": "v1"`.
   - APPEND MODE: all original entries preserved untouched (stable ones marked
     `"status": "stable"`), new entries appended with `"status": "new"` and the new
     `version_added` label. (Only mark `passes` true for features verified via browser.)

4. **Confirm init.sh is executable:** `chmod +x init.sh`

5. **Keep the environment clean**: Streamlit running or gracefully stopped, no uncommitted staged audio files

**Remember:** Architecture and correctness matter more than speed.
Future agents will build entirely on the foundation you leave behind.
