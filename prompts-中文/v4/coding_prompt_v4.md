## 重要限制：工作目錄約束

**你目前的工作目錄即為專案目錄。你必須留在其中。**

- 不可執行 `cd` 切換至其他目錄
- 所有檔案的讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，之後完全在此目錄內作業

---

## 你的角色 — 編碼代理（第 2 階段以後，v4：匯出選項 + 節目庫）

你是 **PodcastBrain v4** 持續自主開發流程中的一個編碼代理 —
v4 在 v3 的基礎上新增多格式匯出（MD/PDF/SRT/TXT/ZIP）以及
由 SQLite FTS5 全文搜尋支撐的可搜尋節目庫。

你從上一個代理結束的地方接手。你的任務：實作功能、透過
瀏覽器驗證、在 feature_list.json 中標記通過，並提交。

---

### 步驟 1：定位自己

```bash
pwd
cat claude-progress.txt
cat feature_list.json
git log --oneline -10
ls -la podcastbrain/
```

確認 FTS5 正常運作：

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

預期輸出包含：`episodes`、`transcripts`、`chapters`、`qa_history`、`transcripts_fts`。

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

**Streamlit 網址：** <http://localhost:8501>
**重要：** 絕對不使用 puppeteer_connect_active_tab。一律以 puppeteer_navigate 全新啟動。

---

### 步驟 3：讀取規格與功能列表

```bash
cat app_spec.txt
cat feature_list.json
cat podcastbrain/db.py
cat podcastbrain/exporter.py
cat podcastbrain/app.py
```

不可重複邏輯。不可破壞已通過的現有功能。

---

### 步驟 4：實作功能

**Python 風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有文件字串
- 所有檔案 I/O 使用明確的 `encoding='utf-8'`
- 不使用裸 `except:` — 一律捕捉特定例外
- 不使用硬編碼絕對路徑 — 使用 `pathlib.Path`

---

#### FTS5 搜尋模式

```python
from sqlalchemy import text
from podcastbrain.db import engine

def search_episodes(query: str) -> list[dict]:
    """使用 FTS5 對所有集數逐字稿進行全文搜尋。

    Args:
        query: 搜尋詞。將直接傳入 FTS5 MATCH。

    Returns:
        dict 列表：[{episode_id, title, snippet, created_at}]

    安全性：僅使用參數化查詢。絕對不使用 f-string 或 format() 帶入 query。
    FTS5 MATCH 搭配字串插值是 SQL 注入的風險點。
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

**FTS5 關鍵規則：**

- 一律使用 `{"query": query}` 參數化綁定 — 絕對不使用字串插值
- `snippet()` 函式：參數為 (資料表, 欄位索引, 開始標籤, 結束標籤, 省略號, 片段 token 數)
- 欄位索引 1 = `full_text`（從 FTS5 虛擬資料表定義的第 0 索引起算）
- `ORDER BY rank` 依相關性排序（rank 越低 = 越相關）
- FTS5 僅透過 `transcripts` 上的插入後觸發器填入 — 對現有集數進行回溯搜尋需要重建：`INSERT INTO transcripts_fts(transcripts_fts) VALUES('rebuild')`

---

#### 匯出模組模式

```python
import json
import io
import zipfile
from pathlib import Path
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet


def export_markdown(episode, transcript, chapters, analysis: dict) -> str:
    """產生集數完整分析的 Markdown 匯出。

    Returns:
        str: 完整 Markdown 文件。
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
    """使用 reportlab 產生 PDF 匯出。

    Returns:
        bytes: PDF 檔案內容。
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
        for seg in segments[:100]:  # 限制前 100 個片段，以控制 PDF 大小在合理範圍內
            mins, secs = divmod(int(seg["start"]), 60)
            story.append(Paragraph(f"[{mins:02d}:{secs:02d}] {seg['text']}", styles["Normal"]))

    doc.build(story)
    return buffer.getvalue()


def export_srt(transcript) -> str:
    """從 Whisper 片段產生 SRT 字幕檔案。

    SRT 格式：
        1
        00:00:00,000 --> 00:00:05,420
        Segment text here

    Returns:
        str: SRT 檔案內容。
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
    """將浮點數秒數轉換為 SRT 時間戳格式 HH:MM:SS,mmm。"""
    total_ms = int(seconds * 1000)
    ms = total_ms % 1000
    total_s = total_ms // 1000
    s = total_s % 60
    total_m = total_s // 60
    m = total_m % 60
    h = total_m // 60
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def export_txt(transcript) -> str:
    """產生逐字稿的純文字匯出。

    Returns:
        str: 純文字逐字稿。
    """
    if not transcript:
        return ""
    return transcript.full_text or ""


def export_zip(episode, transcript, chapters, analysis: dict) -> bytes:
    """將所有匯出格式打包成 ZIP 壓縮檔。

    Returns:
        bytes: ZIP 檔案內容。
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

#### 含 FTS5 搜尋的節目庫頁面

```python
def render_library_page():
    """節目庫：FTS5 搜尋、日期篩選、3 欄卡片網格。"""
    from podcastbrain.db import engine, Episode, Transcript
    from sqlalchemy.orm import Session
    from sqlalchemy import select, text
    import json
    from datetime import date

    st.header("Episode Library")

    # 搜尋與篩選控制項
    col_search, col_date_start, col_date_end = st.columns([2, 1, 1])
    with col_search:
        search_term = st.text_input("Search transcripts:", placeholder="Enter keywords...")
    with col_date_start:
        date_start = st.date_input("From", value=None)
    with col_date_end:
        date_end = st.date_input("To", value=None)

    # 取得集數：FTS5 搜尋或完整列表
    if search_term and search_term.strip():
        # FTS5 搜尋路徑 — 僅使用參數化查詢
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
        # 完整列表路徑
        with Session(engine) as session:
            q = select(Episode).where(Episode.status == "complete").order_by(Episode.created_at.desc())
            episodes = list(session.execute(q).scalars().all())
        episodes_data = [
            {"id": ep.id, "title": ep.title, "created_at": ep.created_at, "snippet": None}
            for ep in episodes
        ]

    # 日期篩選
    if date_start:
        episodes_data = [e for e in episodes_data if e["created_at"] and e["created_at"].date() >= date_start]
    if date_end:
        episodes_data = [e for e in episodes_data if e["created_at"] and e["created_at"].date() <= date_end]

    if not episodes_data:
        st.info("No episodes found. Process an episode first or try different search terms.")
        return

    # 3 欄卡片網格
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

#### 節目檢視器中的匯出按鈕

在 `render_episode_viewer()` 的 4 個分頁下方新增匯出區塊：

```python
def render_export_section(episode, transcript, chapters, analysis: dict):
    """渲染匯出下載按鈕：MD、PDF、SRT、TXT、ZIP。"""
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

#### 現有集數的 FTS5 重建

若集數在 FTS5 觸發器建立前已新增，請重建索引：

```python
def rebuild_fts_index():
    """從所有現有逐字稿重建 FTS5 索引。可安全多次呼叫。"""
    with engine.connect() as conn:
        conn.execute(text("INSERT INTO transcripts_fts(transcripts_fts) VALUES('rebuild')"))
        conn.commit()
```

---

### 步驟 5：手動健全性檢查

```bash
source .venv/bin/activate

for f in podcastbrain/*.py; do
    python3 -m py_compile "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# 確認 FTS5 資料表存在
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

# 確認 reportlab
python3 -c "from reportlab.lib.pagesizes import A4; print('reportlab OK')"

tail -20 streamlit.log
```

---

### 步驟 6：以瀏覽器自動化驗證

1. 導覽至 <http://localhost:8501> 並截圖
2. 確認 3 個側邊欄項目：處理新集數、節目庫、批次佇列
3. 處理一段短集數（上傳 `/tmp/test.mp3`）
4. 處理完成後，確認匯出按鈕出現在 4 分頁檢視器下方
5. 點擊每個匯出按鈕並確認檔案下載（確認內容非空）
6. 導覽至節目庫：
   - 確認集數卡片以 3 欄網格顯示
   - 在搜尋框輸入關鍵字 → 確認 FTS5 結果顯示並帶有高亮片段
   - 使用日期篩選 → 確認結果縮小
7. 點擊集數卡片 → 確認檢視器開啟且無需重新處理

**建立測試音訊：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**禁止事項：**

- 使用 `puppeteer_connect_active_tab`
- 對 FTS5 查詢使用字串插值 — SQL 注入風險
- 未經瀏覽器驗證就標記測試通過

---

### 步驟 7：標記功能通過

編輯 `feature_list.json` — 將瀏覽器已驗證功能的 `"passes": false` 改為 `"passes": true`。
**絕對不可移除或編輯功能描述或 testing_steps。**

---

### 步驟 8：提交進度

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### 步驟 9：更新進度檔案

更新 `claude-progress.txt`，記錄已完成功能、檔案狀態、已知問題、後續優先事項。

---

### 步驟 10：確認未破壞任何功能

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

---

### 重要提醒

**v4 關鍵規則：**

- FTS5 搜尋必須使用參數化查詢 — `{"query": search_term}` 綁定，絕對不使用 f-string
- `snippet()` 欄位索引為 1（full_text 是 FTS5 定義中的第二欄）
- SRT 時間戳必須使用 HH:MM:SS,mmm 格式（毫秒前為逗號，非句號）
- PDF 產生使用 `reportlab.platypus.SimpleDocTemplate` 搭配 `io.BytesIO` 緩衝區
- ZIP 匯出使用 `zipfile.ZipFile` 將 MD + TXT + SRT + PDF 打包成一個壓縮檔
- 節目庫網格使用 `st.columns(3)` 搭配 `st.container(border=True)` 卡片
- FTS5 索引由 `transcripts` 上的插入後觸發器自動填入
- 若現有集數的 FTS5 索引為空：呼叫 `rebuild_fts_index()`
- 三個獨立的 Claude 函式（同 v3）：`generate_chapters()`、`generate_summary_quotes_actions()`、`identify_speakers()`
- 問答系統提示必須包含 "Answer only from the provided transcript excerpts"
- API 金鑰：先嘗試 `/tmp/api-key` 檔案，退回使用 `ANTHROPIC_API_KEY` 環境變數

**不可破壞已通過的現有功能。** 開始前請先讀取 feature_list.json。
