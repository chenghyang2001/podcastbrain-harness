# PodcastBrain Harness 軟體規格文件

**版本**：v1.0
**生成日期**：2026-05-28
**狀態**：草稿（Autonomous Coding Harness 待執行）

---

## 1. 專案概覽

### 1.1 目標

PodcastBrain 是一個將 Podcast / YouTube 影片自動轉換為**結構化知識資產**的工具。使用者貼上 URL，系統自動完成下載、轉錄、章節偵測、語意分析，最終輸出可搜尋的知識庫與多格式匯出檔案。

### 1.2 核心價值

- **無縫自動化**：一個 URL 輸入，全程自動（下載→轉錄→分析→匯出）
- **本地 Whisper 轉錄**：不依賴雲端 STT，隱私可控
- **Claude 語意理解**：章節偵測、全文摘要、Q&A 問答
- **FTS5 全文搜尋**：節目庫可跨集快速搜尋
- **自主編碼驅動**：Harness 由 `autonomous_cli_loop.sh` 自主迭代建構

### 1.3 使用者 Persona

| Persona | 需求 | 主要頁面 |
|---------|------|---------|
| 播客重度聽眾 | 快速掌握集數重點，不想全程收聽 | 新增/分析（Page 1） |
| 知識工作者 | 從多集節目中找特定主題 | 節目庫搜尋（Page 3） |
| 研究人員 | 與轉錄內容深度問答，引用時間戳 | Q&A 對話（Page 2） |
| 批次處理者 | 大量 URL 一次餵入，離線等結果 | 批次佇列（Page 3） |

### 1.4 技術堆疊

| 層次 | 技術 | 版本需求 |
|------|------|---------|
| 語言 | Python | 3.11+ |
| Web UI | Streamlit | >=1.35.0，port 8501 |
| 音訊下載 | yt-dlp | >=2024.1.0 |
| 語音轉文字 | openai-whisper（本地） | >=20231117 |
| AI 分析 | anthropic claude-sonnet-4-6 | >=0.25.0 |
| 資料庫 | SQLite + SQLAlchemy 2.x + FTS5 | >=2.0.0 |
| 音訊處理 | pydub + ffmpeg | ffmpeg-python>=0.2.0 |
| PDF 匯出 | reportlab | >=4.0.0 |
| 圖表 | Plotly | >=5.20.0 |
| 郵件通知 | smtplib（標準庫） | — |

---

## 2. 功能清單

| ID | 功能名稱 | 分類 | 優先級 | 狀態 | 簡述 |
|----|---------|------|--------|------|------|
| 1 | Streamlit App 載入（port 8501） | functional | P1 | 未通過 | `streamlit run app.py` 能在 port 8501 正常啟動，瀏覽器可訪問 |
| 2 | URL 輸入框接受 YouTube 網址 | functional | P2 | 未通過 | Page 1 含 `st.text_input`，支援 YouTube 標準 / Shorts URL 格式 |
| 3 | 「Download Audio」按鈕可見並可點擊 | functional | P3 | 未通過 | 按鈕點擊後觸發 yt-dlp 下載流程，UI 進入下載狀態 |
| 4 | yt-dlp 下載時進度條從 0% 到 100% | functional | P4 | 未通過 | 解析 yt-dlp stderr 進度，以 `st.progress()` 即時更新 |
| 5 | 下載完成後顯示檔案路徑與大小訊息 | functional | P5 | 未通過 | 下載成功後在 UI 顯示輸出路徑與檔案大小（MB） |
| 6 | 無效 URL 顯示友善錯誤訊息（非 Traceback） | functional | P6 | 未通過 | 捕獲 `InvalidURLError` 等例外，顯示可讀錯誤文字 |
| 7 | Cancel 按鈕可中斷下載並清除暫存檔 | functional | P7 | 未通過 | `stop_event.set()` 終止 subprocess，刪除 `.part` 暫存檔 |
| 8 | 單頁版面在 1280px 寬度無溢出 | style | P8 | 未通過 | Page 1/2/3 在 1280px 視窗下均無水平捲軸或元件溢出 |

---

## 3. 資料庫設計

### 3.1 連線設定

```python
# 啟動時執行（db.py）
PRAGMA journal_mode=WAL;   -- 支援多執行緒並行讀寫
PRAGMA foreign_keys=ON;    -- 強制外鍵約束
```

### 3.2 完整 DDL

```sql
-- ===== 主要資料表 =====

CREATE TABLE episodes (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    url             TEXT    NOT NULL UNIQUE,
    title           TEXT,
    channel         TEXT,
    duration_sec    INTEGER,
    language        TEXT    NOT NULL DEFAULT 'zh-TW',
    status          TEXT    NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','downloading','transcribing',
                                      'analyzing','done','error')),
    error_msg       TEXT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_episodes_status     ON episodes(status);
CREATE INDEX idx_episodes_created_at ON episodes(created_at DESC);
CREATE TRIGGER trg_episodes_updated
    AFTER UPDATE ON episodes FOR EACH ROW BEGIN
        UPDATE episodes SET updated_at = datetime('now') WHERE id = NEW.id;
    END;

CREATE TABLE transcripts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    episode_id  INTEGER NOT NULL UNIQUE,
    full_text   TEXT    NOT NULL,
    word_count  INTEGER,
    model_used  TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (episode_id) REFERENCES episodes(id) ON DELETE CASCADE
);

CREATE TABLE chapters (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    episode_id  INTEGER NOT NULL,
    seq         INTEGER NOT NULL,
    title       TEXT    NOT NULL,
    summary     TEXT,
    start_time  REAL    NOT NULL,
    end_time    REAL,
    keywords    TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (episode_id) REFERENCES episodes(id) ON DELETE CASCADE,
    UNIQUE (episode_id, seq)
);
CREATE INDEX idx_chapters_episode ON chapters(episode_id, start_time);

CREATE TABLE qa_history (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    episode_id          INTEGER NOT NULL,
    question            TEXT    NOT NULL,
    answer              TEXT    NOT NULL,
    context_chapter_ids TEXT,
    model_used          TEXT,
    tokens_used         INTEGER,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (episode_id) REFERENCES episodes(id) ON DELETE CASCADE
);
CREATE INDEX idx_qa_episode ON qa_history(episode_id, created_at DESC);

-- ===== FTS5 虛擬表（全文搜尋） =====

CREATE VIRTUAL TABLE transcripts_fts USING fts5(
    full_text,
    content='transcripts',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 1'
);

-- FTS5 同步觸發器
CREATE TRIGGER trg_fts_insert AFTER INSERT ON transcripts BEGIN
    INSERT INTO transcripts_fts(rowid, full_text) VALUES (NEW.id, NEW.full_text);
END;
CREATE TRIGGER trg_fts_update AFTER UPDATE OF full_text ON transcripts BEGIN
    UPDATE transcripts_fts SET full_text = NEW.full_text WHERE rowid = OLD.id;
END;
CREATE TRIGGER trg_fts_delete BEFORE DELETE ON transcripts BEGIN
    DELETE FROM transcripts_fts WHERE rowid = OLD.id;
END;
```

### 3.3 表格說明

| 表格 | 用途 | 關鍵欄位 |
|------|------|---------|
| `episodes` | 節目主記錄，含狀態機 | `status`（6 狀態）、`updated_at`（自動觸發） |
| `transcripts` | 完整逐字稿，1:1 對應 episode | `full_text`、`word_count`、`model_used` |
| `chapters` | Claude 偵測的章節列表，1:N | `seq`（順序）、`start_time`/`end_time`（秒） |
| `qa_history` | Q&A 對話記錄，1:N | `context_chapter_ids`（JSON 陣列）、`tokens_used` |
| `transcripts_fts` | FTS5 虛擬表，自動與 transcripts 同步 | `full_text`（unicode61 tokenizer） |

---

## 4. 模組結構

### 4.1 目錄樹

```
podcastbrain-harness/
├── autonomous_cli_loop.sh      # 自主編碼 Harness 主腳本
├── init.sh                     # 環境初始化腳本
├── requirements.txt            # Python 依賴清單（完整版）
├── feature_list.json           # 8 功能狀態追蹤（Harness 讀寫）
├── .env.example                # 環境變數範本
├── app.py                      # Streamlit 入口（multipage 導覽）
├── scripts/
│   └── parse_claude_stream.py  # 解析 Claude 串流輸出
├── prompts/
│   └── v5/                     # 版本化 System Prompt 目錄
│       ├── chapter_detection.txt
│       ├── full_analysis.txt
│       └── qa_answer.txt
├── podcastbrain/               # 核心業務邏輯套件
│   ├── __init__.py             # 版本常數
│   ├── config.py               # 設定讀取
│   ├── audio.py                # 音訊下載與處理
│   ├── transcribe.py           # Whisper 轉錄
│   ├── analyzer.py             # Claude 章節 + 全文分析
│   ├── qa.py                   # Q&A 問答
│   ├── exporter.py             # 多格式匯出
│   ├── database.py             # SQLite CRUD + FTS5 搜尋
│   ├── queue.py                # 批次佇列管理
│   └── models.py               # 共用資料模型
├── pages/
│   ├── page_1.py               # 新增/分析頁
│   ├── page_2.py               # Q&A 對話頁
│   └── page_3.py               # 節目庫/批次頁
├── data/
│   ├── podcasts/               # 下載的音訊檔
│   ├── transcripts/            # 逐字稿暫存
│   ├── reports/                # 匯出檔案
│   └── podcastbrain.db         # SQLite 資料庫
└── tests/
    ├── test_audio.py
    ├── test_transcribe.py
    ├── test_analyzer.py
    ├── test_exporter.py
    └── test_database.py
```

### 4.2 模組職責與主要函式簽名

#### `podcastbrain/config.py`

讀取 `.env` 與環境變數，提供全域設定物件。

```python
@dataclass
class Config:
    anthropic_api_key: str
    whisper_model: str = "base"      # tiny/base/small/medium/large
    download_dir: Path = Path("data/podcasts")
    db_path: Path = Path("data/podcastbrain.db")
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    notify_email: str = ""

def load_config() -> Config: ...
```

#### `podcastbrain/audio.py`

yt-dlp subprocess 下載，支援進度回呼與 Cancel 機制。

```python
def download_audio(
    url: str,
    output_dir: Path,
    progress_callback: Callable[[int], None],
    stop_event: threading.Event
) -> Path:
    """下載音訊，進度 0-100 回呼，Cancel 時 raise CancelledError"""

def parse_progress(line: str) -> int | None:
    """解析 yt-dlp stderr 進度行，回傳 0-100 整數或 None"""

def validate_url(url: str) -> bool:
    """驗證是否為有效 YouTube URL"""
```

#### `podcastbrain/transcribe.py`

使用本地 Whisper 模型轉錄音訊。

```python
def transcribe_audio(
    audio_path: Path,
    model_name: str = "base",
    progress_callback: Callable[[int], None] | None = None
) -> dict:
    """
    回傳：{"text": str, "segments": list[dict], "language": str}
    segments 每項含 {"start": float, "end": float, "text": str}
    """

def load_whisper_model(model_name: str) -> whisper.Whisper:
    """快取模型，避免重複載入"""
```

#### `podcastbrain/analyzer.py`

Claude API 章節偵測與全文分析，含重試機制。

```python
def detect_chapters(
    client: anthropic.Anthropic,
    full_text: str,
    duration_seconds: int
) -> list[dict]:
    """
    duration < 300s → 回傳 fallback 單章節
    否則呼叫 Claude，驗證 4 欄位：title/start_seconds/end_seconds/summary
    """

def analyze_full(
    client: anthropic.Anthropic,
    full_text: str
) -> dict:
    """
    3 個獨立 Claude API 呼叫：
    Call1 → summary + speaker_labels
    Call2 → quotes（引用句）
    Call3 → action_items（待辦事項）
    回傳合併 dict
    """

def _call_claude_with_retry(
    client: anthropic.Anthropic,
    messages: list[dict],
    system: str,
    max_retries: int = 3
) -> str:
    """指數退避 1s/2s/4s，3 次後 raise RuntimeError"""

def _validate_chapters(data: list[dict]) -> bool:
    """驗證每個章節含 title(str)/start_seconds(int)/end_seconds(int)/summary(str)"""

def _validate_full_analysis(data: dict) -> bool:
    """驗證含 summary/speaker_labels/quotes/action_items 四欄位"""
```

#### `podcastbrain/qa.py`

Q&A 問答，FTS5 段落檢索 + Claude 回答。

```python
def answer_question(
    question: str,
    episode_id: int,
    db_path: Path
) -> dict:
    """回傳 {"answer": str, "citations": list[str], "model_used": str}"""

def retrieve_relevant_segments(
    question: str,
    episode_id: int,
    db_path: Path,
    top_k: int = 10
) -> list[dict]:
    """FTS5 MATCH + episode_id filter + rank DESC，回傳 Top-K 段落"""

def format_citations(segments: list[dict]) -> str:
    """seconds → [HH:MM:SS] 格式引用字串"""
```

#### `podcastbrain/exporter.py`

多格式匯出。

```python
def export_markdown(episode_id: int, db_path: Path, output_path: Path) -> Path
def export_pdf(episode_id: int, db_path: Path, output_path: Path) -> Path
    # reportlab 三段式：標題頁(24pt) / 摘要章節(14pt) / 逐字稿(含灰色[HH:MM:SS])
def export_srt(episode_id: int, db_path: Path, output_path: Path) -> Path
def export_txt(episode_id: int, db_path: Path, output_path: Path) -> Path
def create_zip(episode_id: int, db_path: Path, output_dir: Path) -> Path
    # 打包 MD + PDF + SRT + TXT 四格式

def format_srt_timestamp(seconds: float) -> str:
    """3661.5 → '01:01:01,500'"""
```

#### `podcastbrain/database.py`

SQLite CRUD + FTS5 全文搜尋。

```python
def init_db(db_path: Path) -> None:
    """建立所有表格、索引、觸發器，設 WAL + foreign_keys"""

def save_episode(episode: Episode) -> int:
    """INSERT OR REPLACE，回傳 episode.id"""

def update_episode_status(
    episode_id: int, status: str,
    error_msg: str | None = None,
    db_path: Path = ...
) -> None

def get_episode(episode_id: int, db_path: Path) -> Episode | None

def search(
    query: str,
    limit: int = 20,
    page: int = 1,
    date_from: str | None = None,
    date_to: str | None = None,
    db_path: Path = ...
) -> tuple[list[dict], int]:
    """FTS5 snippet() 搜尋，回傳 (results, total_count)"""
```

#### `podcastbrain/queue.py`

批次佇列管理。

```python
def add_to_queue(urls: list[str], db_path: Path) -> list[int]:
    """批次 INSERT episodes（status='pending'），回傳 id 列表"""

def process_queue(db_path: Path) -> None:
    """在 threading.Thread 中逐筆序列處理 pending → done/error"""

def get_status(db_path: Path) -> pd.DataFrame:
    """回傳欄位：id/title/url/status/error_msg/updated_at"""

def send_email_summary(
    summary: dict,  # {"total": N, "done": N, "error": N}
    config: Config
) -> None:
    """smtplib SMTP_SSL 寄送批次完成通知"""
```

#### `podcastbrain/models.py`

共用資料模型。

```python
@dataclass
class Episode:
    id: int | None
    url: str
    title: str | None = None
    channel: str | None = None
    duration_sec: int | None = None
    language: str = "zh-TW"
    status: str = "pending"
    error_msg: str | None = None
    created_at: str | None = None
    updated_at: str | None = None

@dataclass
class Transcript:
    episode_id: int
    full_text: str
    word_count: int | None = None
    model_used: str | None = None

@dataclass
class Chapter:
    episode_id: int
    seq: int
    title: str
    start_time: float
    end_time: float | None = None
    summary: str | None = None
    keywords: str | None = None
```

---

## 5. 功能實作規格

### 5.1 功能 1-3：Streamlit 載入 + URL 輸入 + Download 按鈕

**app.py 入口**：

```python
import streamlit as st
st.set_page_config(page_title="PodcastBrain", layout="wide", page_icon="🎙️")
pages = {
    "新增/分析": [st.Page("pages/page_1.py", title="新增/分析", icon="➕")],
    "問答":      [st.Page("pages/page_2.py", title="Q&A 對話", icon="💬")],
    "節目庫":    [st.Page("pages/page_3.py", title="節目庫/批次", icon="📚")],
}
pg = st.navigation(pages)
pg.run()
```

**Page 1 URL 輸入邏輯**：

```python
url = st.text_input("YouTube URL", placeholder="https://www.youtube.com/watch?v=...")
if st.button("Download Audio", disabled=not bool(url)):
    if not validate_url(url):
        st.error("⚠️ 無效的 YouTube URL，請確認格式正確")
    else:
        # 進入下載流程
        st.session_state["downloading"] = True
```

### 5.2 功能 4：yt-dlp 進度條（Thread-safe）

**下載流程（背景執行緒）**：

```python
def run_download(url, output_dir, stop_event):
    """在 threading.Thread 中執行，寫 session_state"""
    try:
        path = download_audio(url, output_dir,
            progress_callback=lambda p: session_state.__setitem__("progress", p),
            stop_event=stop_event)
        st.session_state["download_result"] = {"path": path, "size": path.stat().st_size}
    except CancelledError:
        st.session_state["download_result"] = {"cancelled": True}
    except Exception as e:
        st.session_state["download_result"] = {"error": str(e)}

# 主執行緒每 0.5s rerun 更新
progress_bar = st.progress(0)
while st.session_state.get("downloading"):
    p = st.session_state.get("progress", 0)
    progress_bar.progress(p)
    time.sleep(0.5)
    st.rerun()
```

**progress 解析規則**：

- 解析目標：`[download]  42.3% of 123.45MiB at 1.23MiB/s ETA 00:45`
- 正規表達式：`r'\[download\]\s+([\d.]+)%'`
- 回傳值：整數 0-100

### 5.3 功能 5：下載完成顯示

```python
result = st.session_state.get("download_result", {})
if result.get("path"):
    path = result["path"]
    size_mb = result["size"] / 1024 / 1024
    st.success(f"✅ 下載完成：`{path}` ({size_mb:.1f} MB)")
```

### 5.4 功能 6：友善錯誤訊息

**錯誤類型矩陣**：

| 例外類型 | 顯示訊息 |
|---------|---------|
| `InvalidURLError` | ⚠️ 無效的 YouTube URL，請確認格式正確 |
| `NetworkError` | 🌐 網路連線失敗，請檢查網路或稍後再試 |
| `WhisperOOMError` | 🧠 記憶體不足，請改用較小的 Whisper 模型（tiny/base） |
| `ModelNotFoundError` | 🔍 找不到指定的 Whisper 模型，請重新下載 |
| `AudioCorruptError` | 🎵 音訊檔案損毀，請重新下載 |
| `Exception`（其他） | ❌ 處理失敗：{str(e)} |

所有例外均 `st.error(msg)`，不讓 Traceback 顯示在 UI。

### 5.5 功能 7：Cancel 按鈕

```python
stop_event = threading.Event()
st.session_state.setdefault("stop_event", stop_event)

if st.button("Cancel"):
    st.session_state["stop_event"].set()

# download_audio 內部
def download_audio(url, output_dir, progress_callback, stop_event):
    process = subprocess.Popen(yt_dlp_cmd, stderr=subprocess.PIPE)
    for line in process.stderr:
        if stop_event.is_set():
            process.kill()
            # 清除 .part 暫存
            for f in output_dir.glob("*.part"):
                f.unlink(missing_ok=True)
            raise CancelledError("使用者取消下載")
        p = parse_progress(line.decode())
        if p is not None:
            progress_callback(p)
    return output_path
```

### 5.6 功能 8：單頁無溢出（1280px）

Streamlit 設定：

```python
st.set_page_config(layout="wide")
# 自訂 CSS
st.markdown("""
<style>
.main .block-container { max-width: 1200px; padding: 1rem 2rem; }
.stDataFrame { overflow-x: auto; }
</style>
""", unsafe_allow_html=True)
```

所有 DataFrame/表格使用 `use_container_width=True`。

### 5.7 Whisper 轉錄規格

```python
def transcribe_audio(audio_path, model_name="base", progress_callback=None):
    model = load_whisper_model(model_name)
    result = model.transcribe(
        str(audio_path),
        language=None,     # 自動偵測
        verbose=False
    )
    return {
        "text": result["text"],
        "segments": result["segments"],  # list[{start, end, text}]
        "language": result["language"]
    }
```

### 5.8 Claude 章節偵測 System Prompt

```
You are a podcast chapter detector. Analyze the transcript and output ONLY a valid JSON array.

Rules:
- Output strictly JSON array, no markdown, no explanation
- 3 to 8 chapters (or 1 if content < 5 minutes)
- start_seconds and end_seconds must be integers
- Chapters must be continuous and non-overlapping
- Each chapter must have all 4 fields

Output format:
[
  {
    "title": "章節標題",
    "start_seconds": 0,
    "end_seconds": 300,
    "summary": "本章節摘要（50字內）"
  }
]
```

**Fallback 條件**：`duration_seconds < 300` → 回傳 `[{"title": "全集內容", "start_seconds": 0, "end_seconds": duration_seconds, "summary": ""}]`

### 5.9 Claude 全文分析 System Prompts

**Call 1 - 摘要 + 說話者**：

```
Analyze this transcript and output JSON with:
{"summary": "整體摘要（200字內）", "speaker_labels": ["人物1", "人物2"]}
Output strictly JSON only.
```

**Call 2 - 金句引用**：

```
Extract 3-5 key quotes from this transcript.
Output JSON: {"quotes": [{"text": "引用原文", "start_seconds": 120}]}
Output strictly JSON only.
```

**Call 3 - 行動事項**：

```
Extract actionable items or recommendations from this transcript.
Output JSON: {"action_items": ["待辦1", "待辦2"]}
Output strictly JSON only.
```

### 5.10 Q&A System Prompt

```
You are a helpful assistant answering questions about a podcast episode.
Answer ONLY from the provided transcript excerpts below.
Cite the timestamp [HH:MM:SS] immediately after each reference.
If the answer is not in the excerpts, say "根據逐字稿，找不到相關資訊。"

Transcript excerpts:
{context}
```

**FTS5 搜尋查詢**：

```sql
SELECT t.full_text, e.title,
       snippet(transcripts_fts, 0, '<mark>', '</mark>', '...', 20) AS highlight
FROM transcripts_fts
JOIN transcripts t ON transcripts_fts.rowid = t.id
JOIN episodes e ON t.episode_id = e.id
WHERE transcripts_fts MATCH ?
  AND t.episode_id = ?
ORDER BY rank
LIMIT 10;
```

### 5.11 FTS5 節目庫搜尋

```sql
SELECT e.id, e.title, e.channel, e.duration_sec, e.created_at,
       snippet(transcripts_fts, 0, '<mark>', '</mark>', '...', 20) AS highlight
FROM transcripts_fts
JOIN transcripts t ON transcripts_fts.rowid = t.id
JOIN episodes e ON t.episode_id = e.id
WHERE transcripts_fts MATCH ?
  AND (:date_from IS NULL OR e.created_at >= :date_from)
  AND (:date_to   IS NULL OR e.created_at <= :date_to)
ORDER BY rank
LIMIT :limit OFFSET :offset;
```

**分頁計算**：

- 每頁 12 筆（3 欄 × 4 列卡片格）
- `total_pages = math.ceil(total_count / 12)`
- `offset = (page - 1) * 12`

### 5.12 PDF 匯出規格（reportlab）

| 段落 | 字型 | 大小 | 說明 |
|------|------|------|------|
| 標題頁 | Helvetica-Bold | 24pt | 節目標題 + 頻道 + 日期 |
| 摘要/章節 | Helvetica | 14pt | 章節標題 + 摘要 |
| 逐字稿 | Courier | 10pt | 含灰色 [HH:MM:SS] 時間標記 |

### 5.13 批次佇列 Streamlit 更新機制

```python
# page_3.py - 批次狀態刷新（不在 Thread 內呼叫 st.rerun()）
if st.session_state.get("queue_running"):
    df = get_status(config.db_path)
    st.dataframe(df, use_container_width=True)
    if not df[df["status"].isin(["pending","downloading","transcribing","analyzing"])].empty:
        time.sleep(5)
        st.rerun()
    else:
        st.session_state["queue_running"] = False
        st.success("✅ 批次處理完成")
```

---

## 6. 部署設計

### 6.1 requirements.txt（完整版）

```text
streamlit>=1.35.0
pandas>=2.0.0
plotly>=5.20.0
sqlalchemy>=2.0.0
anthropic>=0.25.0
openai>=1.0.0
openai-whisper>=20231117
reportlab>=4.0.0
python-dotenv>=1.0.0
requests>=2.31.0
pytest>=8.0.0
ffmpeg-python>=0.2.0
yt-dlp>=2024.1.0
```

### 6.2 .env.example

```bash
# Anthropic API
ANTHROPIC_API_KEY=sk-ant-xxxxx

# Whisper 模型（tiny/base/small/medium/large）
WHISPER_MODEL=base

# 資料庫路徑
DB_PATH=data/podcastbrain.db

# 下載目錄
DOWNLOAD_DIR=data/podcasts

# SMTP 通知（選填）
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your@gmail.com
SMTP_PASSWORD=app-password
NOTIFY_EMAIL=your@gmail.com
```

### 6.3 init.sh

```bash
#!/bin/bash
set -euo pipefail
# PodcastBrain 環境初始化腳本

echo "=== [1/5] 建立虛擬環境 ==="
python3 -m venv .venv
source .venv/bin/activate

echo "=== [2/5] 安裝依賴 ==="
pip install -r requirements.txt || { echo "❌ pip install 失敗"; exit 1; }

echo "=== [3/5] 建立目錄結構 ==="
mkdir -p data/podcasts data/transcripts data/reports data/logs

echo "=== [4/5] 驗證環境變數 ==="
if [ -f .env ]; then
    source .env
fi
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "❌ 缺少 ANTHROPIC_API_KEY，請複製 .env.example 為 .env 並填入"
    exit 1
fi

echo "=== [5/5] 初始化資料庫 ==="
PYTHONUTF8=1 python -c "
from podcastbrain.database import init_db
from pathlib import Path
init_db(Path('data/podcastbrain.db'))
print('✅ 資料庫初始化完成')
" || { echo "❌ DB 初始化失敗"; exit 1; }

echo "✅ 初始化完成，執行 streamlit run app.py 啟動"
```

### 6.4 VPS systemd unit

```ini
# /etc/systemd/system/podcastbrain.service
[Unit]
Description=PodcastBrain Streamlit App
After=network.target

[Service]
Type=simple
User=claude
WorkingDirectory=/home/claude/podcastbrain-harness
ExecStart=/home/claude/podcastbrain-harness/.venv/bin/streamlit run app.py \
    --server.port 8501 \
    --server.headless true \
    --server.address 0.0.0.0
Restart=on-failure
RestartSec=10
EnvironmentFile=/home/claude/podcastbrain-harness/.env

[Install]
WantedBy=multi-user.target
```

部署指令：

```bash
sudo systemctl daemon-reload
sudo systemctl enable podcastbrain
sudo systemctl start podcastbrain
sudo systemctl status podcastbrain
```

### 6.5 GitHub Actions CI/CD

```yaml
# .github/workflows/deploy.yml
name: Deploy PodcastBrain

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -r requirements.txt
      - run: pytest tests/ -v --tb=short

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -r requirements.txt
      - name: Verify Streamlit startup (15s timeout)
        run: |
          timeout 15 streamlit run app.py --server.headless true &
          sleep 10
          curl -f http://localhost:8501/_stcore/health || exit 1

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.VPS_HOST }}
          username: claude
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd ~/podcastbrain-harness
            git pull origin main
            source .venv/bin/activate
            pip install -r requirements.txt
            sudo systemctl restart podcastbrain
```

---

## 7. Autonomous Coding Harness

### 7.1 雙角色設計

`autonomous_cli_loop.sh` 在同一腳本中承擔兩個角色，以 `feature_list.json` 的狀態決定當前角色：

```
┌─────────────────────────────────────────────────────────┐
│               autonomous_cli_loop.sh                    │
│                                                         │
│  ROLE 1: INITIALIZER（Session 1）                        │
│  ├── 偵測：所有功能狀態 = "未通過"                         │
│  ├── 動作：執行 init.sh 建置環境                           │
│  ├── 動作：讀取 feature_list.json                         │
│  └── 轉換：切換到 CODING SESSION LOOP                     │
│                                                         │
│  ROLE 2: CODING SESSION LOOP（Session 2+）               │
│  ├── 讀取 feature_list.json，找第一個未通過功能             │
│  ├── 呼叫 Claude claude-sonnet-4-6（--json 模式）          │
│  ├── 解析 scripts/parse_claude_stream.py                 │
│  ├── 執行 Claude 產生的指令（寫檔/建立/修改）               │
│  ├── 執行自動測試（pytest / Puppeteer）                    │
│  ├── 判斷測試結果                                         │
│  │   ├── PASS → 更新 feature_list.json 狀態 = "通過"      │
│  │   │        → git add + commit + push                  │
│  │   │        → 繼續下一個功能                             │
│  │   └── FAIL → STALL 機制（最多 3 次）                    │
│  │              └── 3 次後通知並等待人工介入                │
│  └── 所有功能通過 → 任務完成，發送通知                      │
└─────────────────────────────────────────────────────────┘
```

### 7.2 狀態機（feature_list.json）

```json
{
  "features": [
    {"id": 1, "name": "Streamlit App 載入", "status": "未通過", "retry_count": 0},
    {"id": 2, "name": "URL 輸入框", "status": "未通過", "retry_count": 0},
    ...
  ],
  "session": 1,
  "last_updated": "2026-05-28T00:00:00"
}
```

狀態流：`未通過` → （測試通過）→ `通過`

### 7.3 STALL 機制

```bash
MAX_RETRY=3
retry_count=$(jq ".features[$i].retry_count" feature_list.json)
if [ "$retry_count" -ge "$MAX_RETRY" ]; then
    echo "⚠️ 功能 $feature_name 已重試 $MAX_RETRY 次，等待人工介入"
    # 發送 Telegram 通知
    curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=🔴 PodcastBrain STALL: $feature_name 需要人工介入"
    exit 1
fi
```

### 7.4 Git 提交策略

每個功能通過後立即 commit：

```bash
git add -A
git commit -m "✅ [F${feature_id}] ${feature_name} 通過測試"
git push origin main
```

---

## 8. 成功指標

### 8.1 功能面指標（MVP 完成條件）

| 指標 | 目標值 | 驗證方式 |
|------|--------|---------|
| 所有 8 功能通過 | 100%（8/8） | `feature_list.json` 全部 "通過" |
| Streamlit 啟動時間 | < 15 秒 | GitHub Actions timeout 驗證 |
| yt-dlp 下載進度更新 | 每 0.5s 刷新 | Puppeteer UI 截圖驗證 |
| Cancel 後暫存清除 | 0 個 .part 檔 | `ls data/podcasts/*.part` = 0 |
| 無效 URL 不顯示 Traceback | 100% | UI 錯誤訊息不含 "Traceback" |
| 1280px 無溢出 | 3 頁均通過 | Puppeteer viewport 截圖驗證 |

### 8.2 技術品質指標

| 指標 | 目標值 |
|------|--------|
| 單元測試覆蓋率 | > 70%（核心模組） |
| Claude API 重試成功率 | > 95%（3 次重試內） |
| FTS5 搜尋回應時間 | < 500ms（10,000 筆資料） |
| PDF 匯出時間（60分鐘節目） | < 30 秒 |
| SQLite WAL 模式並行讀寫 | 無 SQLITE_BUSY 錯誤 |
| 記憶體峰值（Whisper base） | < 2 GB |

### 8.3 Autonomous Coding Harness 指標

| 指標 | 目標值 |
|------|--------|
| 無人工介入完成率 | 所有 8 功能不觸發 STALL |
| 每功能平均迭代次數 | ≤ 2 次（STALL 門檻 3 次） |
| Harness 總執行時間 | < 60 分鐘（8 功能） |
| git commit 數量 | = 8（每功能一次） |

---

*文件結束。由 Claude Sonnet 4.6 自動整合 Stage 1-3 分析結果生成。*
