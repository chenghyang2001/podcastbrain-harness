## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — CODING AGENT (Session 2+, v1 MVP: Audio Downloader)

You are a coding agent in an ongoing autonomous development process for **PodcastBrain v1** —
a Streamlit web application that downloads audio from YouTube URLs and direct audio links
using yt-dlp, with a live progress bar and cancel support.

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
command -v ffmpeg && ffmpeg -version | head -1 || echo "ffmpeg MISSING — install with apt-get"
source .venv/bin/activate
python3 -c "import yt_dlp; print('yt-dlp OK')" 2>/dev/null || echo "yt-dlp not installed"
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
cat podcastbrain/downloader.py
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
- No hardcoded absolute paths — use `pathlib.Path.cwd() / "downloads"` for the output dir

**Streamlit patterns:**

- Use `st.progress()` + `st.empty()` for the live download progress bar
- Use `st.session_state` to share state between the main thread and the download thread
- Use `st.error()` for user-facing errors — **never** show raw Python tracebacks
- Use `st.success()` to display the saved file path and size on completion
- Disable the Download button while a download is in progress (`st.button(..., disabled=True)`)

**yt-dlp subprocess pattern with live progress parsing:**

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

**Streamlit app pattern (background thread + progress polling):**

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

### STEP 5: MANUAL SANITY CHECK

Before browser verification:

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

3. **Interact like a real user:**
   - Use `puppeteer_fill` to type a URL into the input field
   - Use `puppeteer_click` to click "Download Audio"
   - Use `puppeteer_screenshot` after each interaction to see the progress bar
   - Allow sufficient time for yt-dlp to run before checking completion

4. **Check for errors:**
   - Red Streamlit exception boxes = Python error in the app
   - Blank page or infinite spinner = crash or import error

5. **Test the full download flow:**

   Use a short public YouTube video (< 1 minute) to keep test time manageable:

   ```
   puppeteer_fill url_input: https://www.youtube.com/watch?v=jNQXAC9IVRw
   puppeteer_click: Download Audio
   puppeteer_screenshot  (should show progress bar > 0%)
   # wait ~10 seconds
   puppeteer_screenshot  (should show success message)
   ```

   Verify the file exists:

   ```bash
   ls -la downloads/
   ```

6. **Test error handling:**
   Type an invalid URL (e.g., `not-a-url`) and click Download.
   Screenshot should show a red `st.error()` box, not a Python traceback.

7. **Test cancel:**
   Start a download, then immediately click Cancel.
   Screenshot should show the UI reset to input state, no partial files in downloads/.

**DO:**

- Navigate to <http://localhost:8501> to test all features
- Use short YouTube videos (< 1 minute) to keep tests fast
- Take screenshots at each step to verify progress bar appears
- Check `downloads/` directory contents after a successful download
- Verify error message is user-friendly (no traceback text)

**DON'T:**

- Only test via Python directly — browser UI verification is required
- Use `puppeteer_connect_active_tab` — always start fresh with `puppeteer_navigate`
- Mark tests passing without verifying through the browser

---

### STEP 7: MARK FEATURES PASSING

Only after browser verification confirms the feature works:

Edit `feature_list.json` — change `"passes": false` to `"passes": true` for verified features.

**Never mark a feature passing if:**

- You only tested via Python (not browser)
- The feature partially works (e.g., download runs but progress bar not visible)
- You see a Streamlit error box
- The test steps in feature_list.json were not all executed

**CRITICAL:** Never remove or edit feature descriptions or testing_steps. Only change "passes".

---

### STEP 8: COMMIT PROGRESS

After each verified feature (or logical group of related features):

```bash
git add -A
git commit -m "Implement [feature name]: [brief description of what was done]"
```

Good commit messages: `"Implement progress bar: live yt-dlp stdout parsing via background thread"`
Bad commit messages: `"fix"`, `"update"`, `"wip"`

---

### STEP 9: UPDATE PROGRESS FILE

Update `claude-progress.txt` with:

- Features completed this session (IDs from feature_list.json)
- Current state of each source file (stub/partial/complete)
- Any known issues or limitations
- Recommended priority for next session

```
SESSION N SUMMARY
=================
Completed features: #1 (loads), #2 (URL input), #3 (download button), #4 (progress bar)
Files changed: podcastbrain/downloader.py (complete), podcastbrain/app.py (complete)
Known issues: Cancel button timing — must click within first 2 seconds of download start
Next priority: Features #5 (file saved), #6 (error handling), #7 (cancel)
```

---

### STEP 10: VERIFY NOTHING BROKE

Before finishing, run a final check:

```bash
# Re-check Streamlit is still running
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"

# Quick browser check
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

If any previously passing feature is now broken, fix it before ending the session.
Do not introduce regressions.

---

### IMPORTANT REMINDERS

**v1 Quality Bar:**

- Progress bar MUST update live during download — polling the subprocess stdout in a background thread
- Progress regex MUST be: `r'\[download\]\s+(\d+\.\d+)%'` — this matches yt-dlp's `--newline` output
- Cancel MUST call `process.terminate()` AND delete the partial `.part` file from downloads/
- yt-dlp subprocess MUST have a timeout (`proc.wait(timeout=300)`) to prevent hanging forever
- Output path MUST use `Path.cwd() / "downloads"` — never hardcode an absolute path
- Error display MUST use `st.error()` — never show raw Python exception tracebacks to the user
- The `--newline` flag is required in the yt-dlp command — without it, progress lines won't flush

**yt-dlp output format notes:**

yt-dlp with `--newline` prints progress like:

```
[download]   0.0% of   42.30MiB at  Unknown B/s ETA Unknown
[download]  15.3% of   42.30MiB at    1.23MiB/s ETA 00:33
[download] 100% of   42.30MiB in 00:34
```

The regex `r'\[download\]\s+(\d+\.\d+)%'` captures the percentage from lines 1 and 2.
Line 3 (100%) uses an integer — also match it with `r'\[download\]\s+100%'` to set progress to 1.0.

**Do not break existing passing features.** Read feature_list.json before starting.
If a feature is already passing, do not touch its related code unless fixing a confirmed bug.
