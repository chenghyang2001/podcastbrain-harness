## CRITICAL: WORKING DIRECTORY CONSTRAINT

**Your current working directory IS the project directory. You MUST stay in it.**

- DO NOT run `cd` to any other directory
- All file reads/writes MUST use relative paths
- Run `pwd` first to confirm your working directory, then work exclusively there

---

## YOUR ROLE — CODING AGENT (Session 2+, v4: Export Options + Episode Library)

You are a coding agent in an ongoing autonomous development process for **PodcastBrain v4** —
which extends v3 with multi-format export (MD/PDF/SRT/TXT/ZIP) and a searchable
Episode Library backed by SQLite FTS5 full-text search.

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

Check FTS5 is working:

```bash
source .venv/bin/activate
python3 -c "
from podcastbrain.db import init_db, engine
from sqlalchemy import text
init_db()
with engine.connect() as conn:
    r = conn.execute(text(\"SELECT name FROM sqlite_master WHERE type='table'\")).fetchall()
    print([row[0] for row in r])
"
```

Expected output includes: `episodes`, `transcripts`, `chapters`, `qa_history`, `transcripts_fts`.

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
cat podcastbrain/db.py
cat podcastbrain/exporter.py
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

#### FTS5 search pattern

```python
from sqlalchemy import text
from podcastbrain.db import engine

def search_episodes(query: str) -> list[dict]:
    """Full-text search across all episode transcripts using FTS5.

    Args:
        query: The search term. Will be passed directly to FTS5 MATCH.

    Returns:
        List of dicts: [{episode_id, title, snippet, created_at}]

    SECURITY: Use parameterized query only. Never use f-string or format() with query.
    FTS5 MATCH with string interpolation is a SQL injection vector.
    """
    if not query or not query.strip():
        return []
    with engine.connect() as conn:
        rows = conn.execute(
            text("""
                SELECT
                    e.id AS episode_id,
                    e.title,
                    e.created_at,
                    snippet(transcripts_fts, 1, '<b>', '</b>', '...', 32) AS snippet
                FROM transcripts_fts
                JOIN episodes e ON transcripts_fts.episode_id = e.id
                WHERE transcripts_fts MATCH :query
                ORDER BY rank
                LIMIT 20
            """),
            {"query": query},
        ).fetchall()
    return [
        {"episode_id": r.episode_id, "title": r.title, "snippet": r.snippet, "created_at": r.created_at}
        for r in rows
    ]
```

**FTS5 critical rules:**

- ALWAYS use `{"query": query}` parameterized binding — never string interpolation
- `snippet()` function: args are (table, column_index, open_tag, close_tag, ellipsis, fragment_tokens)
- Column index 1 = `full_text` (0-indexed from the FTS5 virtual table definition)
- `ORDER BY rank` sorts by relevance (lower rank = more relevant)
- FTS5 is only populated via the after-insert trigger on `transcripts` — retroactive search on
  existing episodes requires rebuilding: `INSERT INTO transcripts_fts(transcripts_fts) VALUES('rebuild')`

---

#### Export module pattern

```python
import json
import io
import zipfile
from pathlib import Path
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet


def export_markdown(episode, transcript, chapters, analysis: dict) -> str:
    """Generate a Markdown export of the full episode analysis.

    Returns:
        str: Complete Markdown document.
    """
    lines = [f"# {episode.title}\n"]

    if analysis.get("summary"):
        lines.append("## Summary\n")
        lines.append(analysis["summary"] + "\n")

    if analysis.get("quotes"):
        lines.append("## Key Quotes\n")
        for q in analysis["quotes"]:
            lines.append(f"> {q}\n")

    if analysis.get("action_items"):
        lines.append("## Action Items\n")
        for item in analysis["action_items"]:
            lines.append(f"- {item}\n")

    if chapters:
        lines.append("## Chapters\n")
        for ch in chapters:
            mins, secs = divmod(int(ch.start_time or 0), 60)
            lines.append(f"### {mins:02d}:{secs:02d} — {ch.title}\n")
            if ch.summary:
                lines.append(ch.summary + "\n")

    if transcript:
        segments = json.loads(transcript.segments or "[]")
        lines.append("## Transcript\n")
        for seg in segments:
            mins, secs = divmod(int(seg["start"]), 60)
            lines.append(f"**{mins:02d}:{secs:02d}** {seg['text']}\n")

    return "\n".join(lines)


def export_pdf(episode, transcript, chapters, analysis: dict) -> bytes:
    """Generate a PDF export using reportlab.

    Returns:
        bytes: PDF file content.
    """
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []

    story.append(Paragraph(episode.title, styles["Title"]))
    story.append(Spacer(1, 12))

    if analysis.get("summary"):
        story.append(Paragraph("Summary", styles["Heading2"]))
        story.append(Paragraph(analysis["summary"].replace("\n", "<br/>"), styles["Normal"]))
        story.append(Spacer(1, 12))

    if chapters:
        story.append(Paragraph("Chapters", styles["Heading2"]))
        for ch in chapters:
            mins, secs = divmod(int(ch.start_time or 0), 60)
            story.append(Paragraph(f"{mins:02d}:{secs:02d} — {ch.title}", styles["Heading3"]))
            if ch.summary:
                story.append(Paragraph(ch.summary, styles["Normal"]))
        story.append(Spacer(1, 12))

    if transcript:
        segments = json.loads(transcript.segments or "[]")
        story.append(Paragraph("Transcript", styles["Heading2"]))
        for seg in segments[:100]:  # Limit to first 100 segments to keep PDF size reasonable
            mins, secs = divmod(int(seg["start"]), 60)
            story.append(Paragraph(f"[{mins:02d}:{secs:02d}] {seg['text']}", styles["Normal"]))

    doc.build(story)
    return buffer.getvalue()


def export_srt(transcript) -> str:
    """Generate an SRT subtitle file from Whisper segments.

    SRT format:
        1
        00:00:00,000 --> 00:00:05,420
        Segment text here

    Returns:
        str: SRT file content.
    """
    if not transcript or not transcript.segments:
        return ""
    segments = json.loads(transcript.segments)
    lines = []
    for i, seg in enumerate(segments, start=1):
        start = _seconds_to_srt_time(seg["start"])
        end = _seconds_to_srt_time(seg["end"])
        lines.append(str(i))
        lines.append(f"{start} --> {end}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)


def _seconds_to_srt_time(seconds: float) -> str:
    """Convert float seconds to SRT timestamp format HH:MM:SS,mmm."""
    total_ms = int(seconds * 1000)
    ms = total_ms % 1000
    total_s = total_ms // 1000
    s = total_s % 60
    total_m = total_s // 60
    m = total_m % 60
    h = total_m // 60
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def export_txt(transcript) -> str:
    """Generate plain text export of transcript.

    Returns:
        str: Plain text transcript.
    """
    if not transcript:
        return ""
    return transcript.full_text or ""


def export_zip(episode, transcript, chapters, analysis: dict) -> bytes:
    """Bundle all export formats into a ZIP archive.

    Returns:
        bytes: ZIP file content.
    """
    buffer = io.BytesIO()
    safe_title = "".join(c if c.isalnum() or c in " -_" else "_" for c in episode.title)[:50]

    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"{safe_title}.md", export_markdown(episode, transcript, chapters, analysis))
        zf.writestr(f"{safe_title}.txt", export_txt(transcript))
        zf.writestr(f"{safe_title}.srt", export_srt(transcript))
        pdf_bytes = export_pdf(episode, transcript, chapters, analysis)
        zf.writestr(f"{safe_title}.pdf", pdf_bytes)

    return buffer.getvalue()
```

---

#### Episode Library page with FTS5 search

```python
def render_library_page():
    """Episode Library: FTS5 search, date filter, 3-column card grid."""
    from podcastbrain.db import engine, Episode, Transcript
    from sqlalchemy.orm import Session
    from sqlalchemy import select, text
    import json
    from datetime import date

    st.header("Episode Library")

    # Search and filter controls
    col_search, col_date_start, col_date_end = st.columns([2, 1, 1])
    with col_search:
        search_term = st.text_input("Search transcripts:", placeholder="Enter keywords...")
    with col_date_start:
        date_start = st.date_input("From", value=None)
    with col_date_end:
        date_end = st.date_input("To", value=None)

    # Fetch episodes: FTS5 search or full list
    if search_term and search_term.strip():
        # FTS5 search path — parameterized query only
        with engine.connect() as conn:
            rows = conn.execute(
                text("""
                    SELECT e.id, e.title, e.created_at,
                           snippet(transcripts_fts, 1, '<b>', '</b>', '...', 32) AS snippet
                    FROM transcripts_fts
                    JOIN episodes e ON transcripts_fts.episode_id = e.id
                    WHERE transcripts_fts MATCH :query
                    ORDER BY rank
                    LIMIT 20
                """),
                {"query": search_term},
            ).fetchall()
        episodes_data = [
            {"id": r.id, "title": r.title, "created_at": r.created_at, "snippet": r.snippet}
            for r in rows
        ]
    else:
        # Full list path
        with Session(engine) as session:
            q = select(Episode).where(Episode.status == "complete").order_by(Episode.created_at.desc())
            episodes = list(session.execute(q).scalars().all())
        episodes_data = [
            {"id": ep.id, "title": ep.title, "created_at": ep.created_at, "snippet": None}
            for ep in episodes
        ]

    # Date filter
    if date_start:
        episodes_data = [e for e in episodes_data if e["created_at"] and e["created_at"].date() >= date_start]
    if date_end:
        episodes_data = [e for e in episodes_data if e["created_at"] and e["created_at"].date() <= date_end]

    if not episodes_data:
        st.info("No episodes found. Process an episode first or try different search terms.")
        return

    # 3-column card grid
    cols = st.columns(3)
    for i, ep_data in enumerate(episodes_data):
        with cols[i % 3]:
            with st.container(border=True):
                st.markdown(f"**{ep_data['title']}**")
                if ep_data.get("created_at"):
                    st.caption(ep_data["created_at"].strftime("%Y-%m-%d"))
                if ep_data.get("snippet"):
                    st.markdown(ep_data["snippet"], unsafe_allow_html=True)
                if st.button("Open", key=f"open_{ep_data['id']}"):
                    st.session_state["current_episode_id"] = ep_data["id"]
                    st.session_state["nav_page"] = "Process New Episode"
                    st.rerun()
```

---

#### Export buttons in Episode Viewer

Add an export section below the 4 tabs in `render_episode_viewer()`:

```python
def render_export_section(episode, transcript, chapters, analysis: dict):
    """Render export download buttons: MD, PDF, SRT, TXT, ZIP."""
    from podcastbrain import exporter

    st.markdown("---")
    st.subheader("Export")
    col_md, col_pdf, col_srt, col_txt, col_zip = st.columns(5)

    safe_title = "".join(c if c.isalnum() or c in " -_" else "_" for c in episode.title)[:50]

    with col_md:
        st.download_button(
            "Markdown",
            data=exporter.export_markdown(episode, transcript, chapters, analysis).encode("utf-8"),
            file_name=f"{safe_title}.md",
            mime="text/markdown",
        )
    with col_pdf:
        st.download_button(
            "PDF",
            data=exporter.export_pdf(episode, transcript, chapters, analysis),
            file_name=f"{safe_title}.pdf",
            mime="application/pdf",
        )
    with col_srt:
        st.download_button(
            "SRT",
            data=exporter.export_srt(transcript).encode("utf-8"),
            file_name=f"{safe_title}.srt",
            mime="text/plain",
        )
    with col_txt:
        st.download_button(
            "TXT",
            data=exporter.export_txt(transcript).encode("utf-8"),
            file_name=f"{safe_title}.txt",
            mime="text/plain",
        )
    with col_zip:
        st.download_button(
            "ZIP (all)",
            data=exporter.export_zip(episode, transcript, chapters, analysis),
            file_name=f"{safe_title}.zip",
            mime="application/zip",
        )
```

---

#### FTS5 rebuild for existing episodes

If episodes were added before the FTS5 trigger was in place, rebuild the index:

```python
def rebuild_fts_index():
    """Rebuild FTS5 index from all existing transcripts. Safe to call multiple times."""
    with engine.connect() as conn:
        conn.execute(text("INSERT INTO transcripts_fts(transcripts_fts) VALUES('rebuild')"))
        conn.commit()
```

---

### STEP 5: MANUAL SANITY CHECK

```bash
source .venv/bin/activate

for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# Verify FTS5 table exists
python3 -c "
from podcastbrain.db import engine, init_db
from sqlalchemy import text
init_db()
with engine.connect() as conn:
    tables = conn.execute(text(\"SELECT name FROM sqlite_master WHERE type='table'\")).fetchall()
    print('Tables:', [t[0] for t in tables])
    assert 'transcripts_fts' in [t[0] for t in tables], 'FTS5 table missing!'
    print('FTS5 OK')
"

# Verify reportlab
python3 -c "from reportlab.lib.pagesizes import A4; print('reportlab OK')"

tail -20 streamlit.log
```

---

### STEP 6: VERIFY WITH BROWSER AUTOMATION

1. Navigate to <http://localhost:8501> and screenshot
2. Verify 3 sidebar items: Process New Episode, Episode Library, Batch Queue
3. Process a short episode (upload `/tmp/test.mp3`)
4. After processing, verify export buttons appear below the 4-tab viewer
5. Click each export button and verify a file downloads (check for non-empty content)
6. Navigate to Episode Library:
   - Verify episode cards appear in 3-column grid
   - Type a keyword in the search box → verify FTS5 results appear with highlighted snippets
   - Use date filter → verify results narrow down
7. Click an episode card → verify viewer opens without reprocessing

**Create test audio:**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**DON'T:**

- Use `puppeteer_connect_active_tab`
- Use string interpolation for FTS5 queries — SQL injection risk
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

**v4 Critical Rules:**

- FTS5 search MUST use parameterized queries — `{"query": search_term}` binding, never f-string
- `snippet()` column index is 1 (full_text is the second column in the FTS5 definition)
- SRT timestamps MUST use HH:MM:SS,mmm format (comma before milliseconds, not period)
- PDF generation uses `reportlab.platypus.SimpleDocTemplate` with `io.BytesIO` buffer
- ZIP export bundles MD + TXT + SRT + PDF into one archive using `zipfile.ZipFile`
- Episode Library grid uses `st.columns(3)` with `st.container(border=True)` cards
- FTS5 index is auto-populated by the after-insert trigger on `transcripts`
- If FTS5 index is empty for existing episodes: call `rebuild_fts_index()`
- Three separate Claude functions (same as v3): `generate_chapters()`, `generate_summary_quotes_actions()`, `identify_speakers()`
- Q&A system prompt MUST contain "Answer only from the provided transcript excerpts"
- API key: try `/tmp/api-key` file first, fall back to `ANTHROPIC_API_KEY` env var

**Do not break existing passing features.** Read feature_list.json before starting.
