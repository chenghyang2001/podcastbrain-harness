## 重要：工作目錄限制

**您目前的工作目錄即為專案目錄。您必須留在其中。**

- 不可執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後完全在此目錄中工作

---

## 您的角色——程式碼代理（Session 2+，v5：批次處理佇列）

您是 **PodcastBrain v5** 持續自主開發流程中的一個程式碼代理——
完整的生產就緒版本，在 v4 的基礎上增加批次處理佇列
（多個 URL → 依序處理 → 即時狀態）以及在章節分頁中
以 Plotly 視覺章節時間軸取代原本的純文字章節清單。

您從上一個代理離開的地方接手。您的任務：實作功能、透過瀏覽器驗證、
在 feature_list.json 中標記通過，並提交。

---

### 步驟 1：了解現況

```bash
pwd
cat claude-progress.txt
cat feature_list.json
git log --oneline -10
ls -la podcastbrain/
```

找出 `"passes": false` 且優先級最高的功能。那就是您的目標。

檢查相依套件：

```bash
source .venv/bin/activate
python3 -c "import plotly; print('plotly OK')"
python3 -c "from podcastbrain.db import init_db, engine; from sqlalchemy import text; init_db(); print('DB OK')"
```

---

### 步驟 2：啟動 STREAMLIT 伺服器

```bash
source .venv/bin/activate
curl -s http://localhost:8501 > /dev/null && echo "Already running" || \
  nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &
sleep 3
tail -20 streamlit.log
```

**Streamlit URL：** <http://localhost:8501>
**重要：** 絕不使用 puppeteer_connect_active_tab。始終以 puppeteer_navigate 全新開始。

---

### 步驟 3：閱讀規格與功能清單

```bash
cat app_spec.txt
cat feature_list.json
cat podcastbrain/app.py
cat podcastbrain/db.py
```

不要重複邏輯。不要破壞現有已通過的功能。

---

### 步驟 4：實作功能

**Python 風格：**

- 函式/變數使用 snake_case，類別使用 PascalCase
- 每個函式都有 docstring
- 所有檔案 I/O 使用明確的 `encoding='utf-8'`
- 不使用裸 `except:`——始終捕捉特定例外
- 不使用硬編碼的絕對路徑——使用 `pathlib.Path`

---

#### Plotly 章節時間軸（取代章節分頁中的純文字章節清單）

```python
import plotly.graph_objects as go

def render_chapter_timeline(chapters, total_duration_seconds: float = None):
    """以 Plotly 水平長條圖時間軸渲染章節。

    每個章節是從其 start_time 到下一個章節的 start_time
    （最後一個章節則到 total_duration_seconds）的水平長條。

    Args:
        chapters: 含 start_time 和 title 屬性的 Chapter ORM 物件清單。
        total_duration_seconds: 節目總時長，用於調整最後一個長條的大小。
                                若為 None，則退回 start_time + 60。
    """
    if not chapters:
        st.info("No chapters detected.")
        return

    # 依開始時間排序章節
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

    # 在圖表下方同時顯示文字清單以提升無障礙性
    for ch in sorted_chapters:
        mins, secs = divmod(int(ch.start_time or 0), 60)
        st.caption(f"{mins:02d}:{secs:02d} — {ch.title}")
        if ch.summary:
            st.caption(f"  {ch.summary}")
```

**Plotly 整合至章節分頁：**

將 `render_episode_viewer()` 章節分頁中的純文字章節清單替換為：

```python
with tab_chapters:
    render_chapter_timeline(chapters, total_duration_seconds=ep.duration_seconds)
```

---

#### 批次佇列頁面

```python
def render_batch_page():
    """批次佇列：接受多個 URL，排入佇列，依序處理，顯示即時狀態。"""
    from podcastbrain.db import engine, Episode
    from sqlalchemy.orm import Session
    from sqlalchemy import select
    from datetime import datetime

    st.header("Batch Queue")

    # --- 將 URL 加入佇列 ---
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

    # --- 處理佇列 ---
    if st.button("Process Queue Now"):
        _process_batch_queue(model_name)

    st.markdown("---")

    # --- 佇列狀態表格 ---
    st.subheader("Queue Status")
    _render_queue_status()

    # 當有項目正在處理時，每 5 秒自動重新整理
    with Session(engine) as session:
        active = session.execute(
            select(Episode).where(Episode.status.in_(["queued", "processing"]))
        ).scalars().first()
    if active:
        import time
        time.sleep(5)
        st.rerun()


def _render_queue_status():
    """將目前佇列顯示為狀態表格。"""
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
    """依序處理所有排隊中的節目。

    每個節目按順序處理：下載 → 轉錄 → 分析。
    每個步驟後更新資料庫中的狀態，使佇列表格反映即時進度。
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
            # 標記為處理中
            with Session(engine) as session:
                ep = session.get(Episode, episode_id)
                ep.status = "processing"
                session.commit()

            # 步驟 1：下載
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

            # 步驟 2：轉錄
            transcription = transcriber.transcribe_audio(audio_path, model_name)
            with Session(engine) as session:
                session.add(Transcript(
                    episode_id=episode_id,
                    full_text=transcription["full_text"],
                    segments=json.dumps(transcription["segments"]),
                    word_count=transcription["word_count"],
                ))
                session.commit()

            # 步驟 3：Claude 分析
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

#### 側邊欄導覽（v5——3 個頁面全部可用）

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

#### FTS5 搜尋（與 v4 相同——僅使用參數化查詢）

```python
from sqlalchemy import text
from podcastbrain.db import engine

def search_episodes(query: str) -> list[dict]:
    """FTS5 全文搜尋。必須使用參數化查詢——絕不使用 f-string。"""
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

### 步驟 5：手動健全性檢查

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

### 步驟 6：以瀏覽器自動化驗證

1. 導覽至 <http://localhost:8501> 並截圖
2. 驗證 3 個側邊欄項目：Process New Episode、Episode Library、Batch Queue
3. **Plotly 章節時間軸：**
   - 處理一個短節目
   - 開啟章節分頁
   - 驗證出現水平長條圖（非純文字清單）
   - 將滑鼠懸停在長條上，驗證 tooltip 顯示章節名稱、開始時間、時長
4. **批次佇列：**
   - 導覽至批次佇列頁面
   - 在 textarea 中輸入 2-3 個 YouTube URL（每行一個）
   - 點擊「Add to Queue」→ 驗證成功訊息
   - 點擊「Process Queue Now」→ 驗證表格中每個節目的狀態更新
   - 驗證狀態變化：queued → processing → complete
   - 驗證自動重新整理（表格在項目處理期間每 5 秒更新一次）
5. **節目資料庫：** 驗證 FTS5 搜尋與 3 欄網格仍正常運作
6. **匯出：** 驗證所有 5 個下載按鈕仍正常運作

**建立測試音訊：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

**禁止事項：**

- 使用 `puppeteer_connect_active_tab`
- 對 FTS5 查詢使用字串插值
- 未經瀏覽器驗證就標記測試通過

---

### 步驟 7：標記功能通過

編輯 `feature_list.json`——將已透過瀏覽器驗證的功能的 `"passes": false` 改為 `"passes": true`。
**絕不移除或編輯功能描述或 testing_steps。**

---

### 步驟 8：提交進度

```bash
git add -A
git commit -m "Implement [feature name]: [brief description]"
```

---

### 步驟 9：更新進度檔案

更新 `claude-progress.txt`，記載已完成的功能、檔案狀態、已知問題、後續優先事項。

---

### 步驟 10：確認沒有破壞任何東西

```bash
curl -s http://localhost:8501 | grep -c "streamlit" || echo "STREAMLIT DOWN"
puppeteer_navigate http://localhost:8501
puppeteer_screenshot
```

---

### 重要提醒

**v5 關鍵規則：**

- Plotly 圖表必須使用 `go.Bar` 搭配 `orientation="h"`——水平長條，非垂直
- 章節長條的大小依時長決定（下一個章節的開始時間減去本章節的開始時間）
- `yaxis=dict(autorange="reversed")` 確保章節由上至下以時間順序排列
- 批次佇列加入時使用 `Episode.status = "queued"`，處理中為 `"processing"`，完成後為 `"complete"`
- 自動重新整理：僅在有活躍項目時使用 `time.sleep(5)` + `st.rerun()`（避免無限迴圈）
- 批次**依序**處理節目——絕不並行（Whisper 耗用大量資源）
- FTS5 搜尋必須使用參數化查詢——使用 `{"query": search_term}` 綁定，絕不使用 f-string
- SRT 時間戳：HH:MM:SS,mmm（毫秒前用逗號）
- PDF 使用 reportlab 搭配 `io.BytesIO` buffer
- ZIP 打包 MD + TXT + SRT + PDF
- 三個獨立的 Claude 函式：`generate_chapters()`、`generate_summary_quotes_actions()`、`identify_speakers()`
- Q&A 系統提示必須包含「Answer only from the provided transcript excerpts」
- API 金鑰：先嘗試 `/tmp/api-key` 檔案，退回 `ANTHROPIC_API_KEY` 環境變數
- Whisper 模型：始終透過 `@st.cache_resource` 載入——絕不在每次互動時重新載入

**不要破壞現有已通過的功能。** 開始前先閱讀 feature_list.json。
