## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — CODING AGENT (Session 2+, v5: Batch Processing Queue)

You are a coding agent in an ongoing autonomous development process for **PodcastBrain v5** —
the complete production-ready version, extending v4 with a Batch Processing Queue
(multiple URLs → sequential processing → live status) and a Plotly visual chapter
timeline replacing the plain chapter list in the Chapters tab.

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

Check dependencies:

```bash
source .venv/bin/activate
python3 -c "import plotly; print('plotly OK')"
python3 -c "from podcastbrain.db import init_db, engine; from sqlalchemy import text; init_db(); print('DB OK')"
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
cat podcastbrain/app.py
cat podcastbrain/db.py
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

#### Plotly chapter timeline (replaces plain chapter list in Chapters tab)

```python
import plotly.graph_objects as go

def render_chapter_timeline(chapters, total_duration_seconds: float = None):
    """Render chapters as a Plotly horizontal bar chart timeline.

    Each chapter is a horizontal bar from its start_time to the next chapter's start_time
    (or total_duration_seconds for the last chapter).

    Args:
        chapters: List of Chapter ORM objects with start_time and title attributes.
        total_duration_seconds: Total episode duration for sizing the last bar.
                                Falls back to start_time + 60 if None.
    """
    if not chapters:
        st.info("No chapters detected.")
        return

    # Sort chapters by start time
    sorted_chapters = sorted(chapters, key=lambda c: c.start_time or 0)

    bars = []
    for i, ch in enumerate(sorted_chapters):
        start = ch.start_time or 0
        if i + 1 < len(sorted_chapters):
            end = sorted_chapters[i + 1].start_time or (start + 60)
        else:
            end = total_duration_seconds or (start + 60)
        duration = max(end - start, 1)

        mins_start, secs_start = divmod(int(start), 60)
        label = f"{mins_start:02d}:{secs_start:02d} — {ch.title}"

        bars.append(
            go.Bar(
                x=[duration],
                y=[label],
                orientation="h",
                hovertemplate=f"<b>{ch.title}</b><br>Start: {mins_start:02d}:{secs_start:02d}<br>Duration: {int(duration)}s<extra></extra>",
                name=ch.title,
            )
        )

    fig = go.Figure(
        data=bars,
        layout=go.Layout(
            title="Chapter Timeline",
            xaxis_title="Duration (seconds)",
            yaxis=dict(autorange="reversed"),
            barmode="stack",
            showlegend=False,
            height=max(200, len(sorted_chapters) * 40 + 100),
            margin=dict(l=200, r=20, t=40, b=40),
        ),
    )

    st.plotly_chart(fig, use_container_width=True)

    # Also show a text list below the chart for accessibility
    for ch in sorted_chapters:
        mins, secs = divmod(int(ch.start_time or 0), 60)
        st.caption(f"{mins:02d}:{secs:02d} — {ch.title}")
        if ch.summary:
            st.caption(f"  {ch.summary}")
```

**Plotly integration in the Chapters tab:**

Replace the plain chapter list in `render_episode_viewer()` Chapters tab with:

```python
with tab_chapters:
    render_chapter_timeline(chapters, total_duration_seconds=ep.duration_seconds)
```

---

#### Batch Queue page

```python
def render_batch_page():
    """Batch Queue: accept multiple URLs, queue them, process sequentially, show live status."""
    from podcastbrain.db import engine, Episode
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    from datetime import datetime

    st.header("Batch Queue")

    # --- Add URLs to queue ---
    st.subheader("Add URLs to Queue")
    url_text = st.text_area(
        "Enter YouTube URLs (one per line):",
        height=150,
        placeholder="https://www.youtube.com/watch?v=...\nhttps://www.youtube.com/watch?v=...",
    )

    model_name = st.selectbox(
        "Whisper model for batch:",
        ["tiny", "base", "small", "medium", "large"],
        index=1,
    )

    if st.button("Add to Queue"):
        urls = [u.strip() for u in url_text.strip().splitlines() if u.strip()]
        if not urls:
            st.warning("No valid URLs entered.")
        else:
            added = 0
            with Session(engine) as session:
                for url in urls:
                    ep = Episode(
                        title=f"Queued: {url[:60]}",
                        url=url,
                        whisper_model=model_name,
                        status="queued",
                        created_at=datetime.utcnow(),
                    )
                    session.add(ep)
                    added += 1
                session.commit()
            st.success(f"Added {added} URL(s) to the queue.")

    st.markdown("---")

    # --- Process queue ---
    if st.button("Process Queue Now"):
        _process_batch_queue(model_name)

    st.markdown("---")

    # --- Queue status table ---
    st.subheader("Queue Status")
    _render_queue_status()

    # Auto-refresh every 5 seconds while items are processing
    with Session(engine) as session:
        active = session.execute(
            select(Episode).where(Episode.status.in_(["queued", "processing"]))
        ).scalars().first()
    if active:
        import time
        time.sleep(5)
        st.rerun()


def _render_queue_status():
    """Display current queue as a status table."""
    from podcastbrain.db import engine, Episode
    from sqlalchemy.orm import Session
    from sqlalchemy import select

    STATUS_ICONS = {
        "queued": "⏳",
        "processing": "🔄",
        "complete": "✅",
        "error": "❌",
        "pending": "⏸",
    }

    with Session(engine) as session:
        episodes = list(session.execute(
            select(Episode)
            .where(Episode.status.in_(["queued", "processing", "complete", "error"]))
            .order_by(Episode.created_at.desc())
            .limit(50)
        ).scalars().all())

    if not episodes:
        st.info("No episodes in queue.")
        return

    for ep in episodes:
        icon = STATUS_ICONS.get(ep.status, "❓")
        col_icon, col_title, col_status, col_action = st.columns([0.5, 3, 1, 1])
        with col_icon:
            st.write(icon)
        with col_title:
            st.write(ep.title)
        with col_status:
            st.caption(ep.status)
        with col_action:
            if ep.status == "complete":
                if st.button("View", key=f"view_batch_{ep.id}"):
                    st.session_state["current_episode_id"] = ep.id
                    st.session_state["nav_page"] = "Process New Episode"
                    st.rerun()


def _process_batch_queue(default_model: str = "base"):
    """Process all queued episodes sequentially.

    Each episode is processed in order: download → transcribe → analyze.
    Status is updated in DB after each step so the queue table reflects live progress.
    """
    from podcastbrain.db import engine, Episode, Transcript, Chapter
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    from podcastbrain import downloader, transcriber, analyzer
    import json
    from pathlib import Path

    with Session(engine) as session:
        queued = list(session.execute(
            select(Episode).where(Episode.status == "queued").order_by(Episode.created_at)
        ).scalars().all())

    if not queued:
        st.info("No queued episodes to process.")
        return

    progress_container = st.empty()

    for i, ep_stub in enumerate(queued):
        episode_id = ep_stub.id
        url = ep_stub.url
        model_name = ep_stub.whisper_model or default_model

        with progress_container.container():
            st.write(f"Processing {i+1}/{len(queued)}: {url[:60]}...")

        audio_path = None
        try:
            # Mark as processing
            with Session(engine) as session:
                ep = session.get(Episode, episode_id)
                ep.status = "processing"
                session.commit()

            # Step 1: Download
            tmp_dir = Path("/tmp/podcastbrain-audio")
            tmp_dir.mkdir(exist_ok=True)
            result = downloader.download_audio(url, str(tmp_dir))
            audio_path = result["file_path"]
            title = result["title"]

            with Session(engine) as session:
                ep = session.get(Episode, episode_id)
                ep.title = title
                ep.audio_path = audio_path
                session.commit()

            # Step 2: Transcribe
            transcription = transcriber.transcribe_audio(audio_path, model_name)
            with Session(engine) as session:
                session.add(Transcript(
                    episode_id=episode_id,
                    full_text=transcription["full_text"],
                    segments=json.dumps(transcription["segments"]),
                    word_count=transcription["word_count"],
                ))
                session.commit()

            # Step 3: Claude analysis
            chapters = analyzer.generate_chapters(transcription["full_text"])
            analysis = analyzer.generate_summary_quotes_actions(transcription["full_text"])
            speakers = analyzer.identify_speakers(transcription["full_text"])
            analysis["speakers"] = speakers

            with Session(engine) as session:
                for ch in chapters:
                    session.add(Chapter(
                        episode_id=episode_id,
                        title=ch.get("title", ""),
                        start_time=ch.get("start_time", 0),
                        summary=ch.get("summary", ""),
                    ))
                ep = session.get(Episode, episode_id)
                ep.claude_analysis = json.dumps(analysis)
                ep.status = "complete"
                session.commit()

        except Exception as e:
            with Session(engine) as session:
                ep = session.get(Episode, episode_id)
                ep.status = "error"
                ep.claude_analysis = json.dumps({"error": str(e)})
                session.commit()
        finally:
            if audio_path and Path(audio_path).exists():
                Path(audio_path).unlink()

    progress_container.empty()
    st.success(f"Batch complete: {len(queued)} episode(s) processed.")
    st.rerun()
```

---

#### Sidebar navigation (v5 — all 3 pages functional)

```python
def main():
    st.set_page_config(page_title="PodcastBrain", layout="wide")
    from podcastbrain.db import init_db
    init_db()

    page = st.sidebar.selectbox(
        "Navigation",
        ["Process New Episode", "Episode Library", "Batch Queue"],
    )
    st.session_state["nav_page"] = page

    if page == "Process New Episode":
        render_process_page()
    elif page == "Episode Library":
        render_library_page()
    elif page == "Batch Queue":
        render_batch_page()
```

---

#### FTS5 search (same as v4 — parameterized only)

```python
from sqlalchemy import text
from podcastbrain.db import engine

def search_episodes(query: str) -> list[dict]:
    """FTS5 full-text search. MUST use parameterized query — never f-string."""
    if not query or not query.strip():
        return []
    with engine.connect() as conn:
        rows = conn.execute(
            text("""
                SELECT e.id AS episode_id, e.title, e.created_at,
                       snippet(transcripts_fts, 1, '<b>', '</b>', '...', 32) AS snippet
                FROM transcripts_fts
                JOIN episodes e ON transcripts_fts.episode_id = e.id
                WHERE transcripts_fts MATCH :query
                ORDER BY rank LIMIT 20
            """),
            {"query": query},
        ).fetchall()
    return [{"episode_id": r.episode_id, "title": r.title, "snippet": r.snippet, "created_at": r.created_at} for r in rows]
```

---

### STEP 5: MANUAL SANITY CHECK

```bash
source .venv/bin/activate

for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

python3 -c "import plotly.graph_objects as go; print('plotly OK')"
python3 -c "from podcastbrain.db import init_db; init_db(); print('DB OK')"
tail -20 streamlit.log
```

---

### STEP 6: VERIFY WITH BROWSER AUTOMATION

1. Navigate to <http://localhost:8501> and screenshot
2. Verify 3 sidebar items: Process New Episode, Episode Library, Batch Queue
3. **Plotly chapter timeline:**
   - Process a short episode
   - Open Chapters tab
   - Verify a horizontal bar chart appears (not a plain text list)
   - Hover over a bar to verify tooltip shows chapter name, start time, duration
4. **Batch Queue:**
   - Navigate to Batch Queue page
   - Enter 2-3 YouTube URLs in the textarea (one per line)
   - Click "Add to Queue" → verify success message
   - Click "Process Queue Now" → verify per-episode status updates in the table
   - Verify status changes: queued → processing → complete
   - Verify auto-refresh (table updates every 5 seconds while items are processing)
5. **Episode Library:** verify FTS5 search and 3-column grid still work
6. **Exports:** verify all 5 download buttons still work

**Create test audio:**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**DON'T:**

- Use `puppeteer_connect_active_tab`
- Use string interpolation for FTS5 queries
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

**v5 Critical Rules:**

- Plotly chart MUST be `go.Bar` with `orientation="h"` — horizontal bars, not vertical
- Chapter bars are sized by duration (start of next chapter minus start of this chapter)
- `yaxis=dict(autorange="reversed")` ensures chapters appear in chronological order top-to-bottom
- Batch queue uses `Episode.status = "queued"` when added, `"processing"` while active, `"complete"` when done
- Auto-refresh: use `time.sleep(5)` + `st.rerun()` only when active items exist (avoid infinite loop)
- Batch processes episodes **sequentially** — never parallel (Whisper is resource-heavy)
- FTS5 search MUST use parameterized queries — `{"query": search_term}` binding, never f-string
- SRT timestamps: HH:MM:SS,mmm (comma before milliseconds)
- PDF uses reportlab with `io.BytesIO` buffer
- ZIP bundles MD + TXT + SRT + PDF
- Three separate Claude functions: `generate_chapters()`, `generate_summary_quotes_actions()`, `identify_speakers()`
- Q&A system prompt MUST contain "Answer only from the provided transcript excerpts"
- API key: try `/tmp/api-key` file first, fall back to `ANTHROPIC_API_KEY` env var
- Whisper model: always load via `@st.cache_resource` — never reload per interaction

**Do not break existing passing features.** Read feature_list.json before starting.
