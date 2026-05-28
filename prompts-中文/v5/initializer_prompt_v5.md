## 重要：工作目錄限制

**您目前的工作目錄即為專案目錄。您必須留在其中。**

- 不可執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後完全在此目錄中工作

---

## 您的角色——初始化代理（Session 1，v5：批次處理佇列）

您是多 Session 自主開發流程中的**第一個代理**。
您的任務是為所有後續程式碼代理建立基礎。

本專案建置 **PodcastBrain v5**——完整的生產就緒版本，
在 v4 的基礎上增加批次處理佇列功能：接受多個 YouTube URL，
依序處理並提供即時狀態更新，並在節目檢視器中新增基於 Plotly 的
章節時間軸視覺化圖表。

技術堆疊：Python 3.11+、Streamlit（port 8501）、yt-dlp、openai-whisper（本地）、
Anthropic Claude claude-sonnet-4-6、SQLAlchemy 2.x + SQLite with FTS5、
pydub、reportlab、plotly、ffmpeg-python。

---

### 首先：閱讀專案規格

從工作目錄讀取 `app_spec.txt`。此檔案包含您需要建置的完整規格。
在繼續之前請仔細閱讀。

---

### 任務 1：建立 feature_list.json

根據 `app_spec.txt`，建立名為 `feature_list.json` 的檔案，包含恰好 **30** 個
詳細的端對端測試案例。此檔案是所有未來程式碼代理的唯一事實來源——
它精確定義了必須建置的內容以及如何驗證。

**feature_list.json 格式：**

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

- 總共恰好 **30** 個功能
- 同時包含「functional」和「style」類別
- 混合窄範圍（2-5 步驟）與全面性（10+ 步驟）測試
- 至少 1 個測試必須有 10+ 步驟
- 優先順序：基礎性優先（應用程式載入 → 輸入 → 流程 → 檢視器 → 匯出 → 資料庫 → 批次 → 樣式）
- 全部以 `"passes": false` 開始
- 透過 puppeteer 工具進行瀏覽器自動化測試（導覽至 <http://localhost:8501>）
- 每個測試以 puppeteer_navigate 開始；**絕不使用 puppeteer_connect_active_tab**
- 涵蓋所有主要功能與完整處理流程

**需涵蓋的功能領域（共 30 個）：**

1. 應用程式在 port 8501 載入，含側邊欄導覽（Process New、Episode Library、Batch Queue）
2. URL 輸入欄位接受 YouTube 觀看 URL
3. 檔案上傳小工具接受 .mp3 和 .m4a 檔案
4. Whisper 模型選擇下拉選單顯示所有 5 個選項（tiny、base、small、medium、large）
5. 「Process Episode」按鈕觸發完整處理流程
6. 下載階段顯示 yt-dlp 進度條即時更新
7. Whisper 轉錄階段顯示進度指示器
8. Claude 章節偵測執行並產生章節清單
9. Claude 完整分析執行：摘要、重要引言、行動事項
10. Claude 說話者辨識執行
11. 節目檢視器出現，含 4 個分頁：Summary、Chapters、Transcript、Q&A
12. Summary 分頁顯示格式化的摘要、引言與行動事項
13. Chapters 分頁顯示視覺化 Plotly 水平長條圖時間軸（非純文字清單）
14. Transcript 分頁顯示附時間戳與關鍵字搜尋的文字
15. Q&A 分頁接受問題並回傳附引用的依據答案
16. Q&A 答案包含來源引用時間戳
17. Markdown 匯出下載非空的 .md 檔案
18. PDF 匯出下載非空的 .pdf 檔案
19. SRT 匯出下載含 HH:MM:SS,mmm 時間戳的有效字幕檔
20. ZIP 匯出下載包含多個檔案的壓縮檔
21. Episode Library 頁面在 3 欄卡片網格中顯示已處理的節目
22. FTS5 關鍵字搜尋找到逐字稿中包含該詞的節目
23. 資料庫中的日期範圍篩選正確縮小結果
24. 點擊節目卡片開啟其檢視器，無需重新處理
25. Batch Queue 頁面透過 textarea 接受多個 URL（每行一個）
26. 「Add to Queue」按鈕將所有 URL 儲存為資料庫中的排隊節目
27. 批次佇列依序處理節目，含每個節目的狀態更新
28. 批次佇列每 5 秒自動重新整理以顯示目前處理狀態
29. 樣式：章節時間軸為視覺化水平長條圖（Plotly），非純清單
30. 樣式：在標準 1280px 視窗寬度下無版面溢出

**重要說明：**
在未來的 Session 中移除或編輯功能是災難性的。
功能只能被標記為通過（將 `"passes": false` 改為 `"passes": true`）。
絕不移除功能、絕不編輯描述、絕不修改 testing_steps。
未來的代理依賴此檔案的確切內容。

---

### 任務 2：建立 init.sh 和 requirements.txt

建立可執行的 `init.sh`，在全新的 Linux 環境中引導專案：

```bash
#!/bin/bash
set -e

echo "=== PodcastBrain Init ==="

# 1. 檢查系統相依套件
command -v ffmpeg >/dev/null 2>&1 || {
    echo "ffmpeg not found. Installing..."
    apt-get update -qq && apt-get install -y -qq ffmpeg
}

# 2. 建立 Python virtualenv
python3 -m venv .venv

# 3. 啟用並安裝相依套件
source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 4. 建立音訊暫存目錄與下載目錄
mkdir -p /tmp/podcastbrain-audio
mkdir -p downloads

# 5. 初始化 SQLite 資料庫（建立所有資料表，含 FTS5）
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized with FTS5 support')
"

# 6. 在背景以 port 8501 啟動 Streamlit
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

同時建立附釘定最低版本的 `requirements.txt`：

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

### 任務 3：初始化 Git

新增並提交所有已建立的檔案：

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v5: feature list, init script, requirements"
```

若 README.md 不存在，先建立一個最簡版本：

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

### 任務 4：建立專案結構

建立附有 stub 檔案的套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py         — Streamlit 進入點：側邊欄導覽，3 個頁面（Process New、Library、Batch Queue）
  downloader.py  — yt-dlp 子程序包裝器：進度解析，支援取消
  transcriber.py — Whisper 轉錄：模型載入（已快取），片段輸出
  analyzer.py    — Claude：3 個獨立函式（chapters、summary+quotes+actions、speakers）
  qa_engine.py   — Q&A：關鍵字檢索，Claude 依據提示，回應解析器
  exporter.py    — 匯出：MD、PDF（reportlab）、SRT、TXT、ZIP
  db.py          — SQLAlchemy ORM 模型，FTS5 設定，session factory，init_db()

```

對每個檔案，至少建立：
- 說明目的的模組 docstring
- import 陳述式
- 含 docstring 和 `pass` 主體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是讓未來的程式碼代理能填入實作，無需重新架構。

**db.py 必須是可運行的**（非 stub），因為 init.sh 會呼叫 `init_db()`。
實作所有 4 個 SQLAlchemy ORM 模型、FTS5 虛擬資料表 DDL、插入後
觸發器 DDL 以及 `init_db()` 函式。

**v5 資料庫 schema——與 v4 相同的 4 個 ORM 資料表 + FTS5：**

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
    """建立所有 ORM 資料表，以及 FTS5 虛擬資料表與插入後觸發器。"""
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

**v5 中 Episode.status 的值：**

- `pending` — 新建立，尚未排隊
- `queued` — 已加入批次佇列，等待處理
- `processing` — 目前正在處理
- `complete` — 已完整處理，所有分頁可用
- `error` — 處理失敗，錯誤詳情在 claude_analysis 欄位中

---

### 可選：開始實作

若完成上述四項任務後還有時間，依優先順序實作：

1. **db.py** — 完整（init.sh 需要）
2. **downloader.py** — 附 yt-dlp 子程序與進度解析的 `download_audio()`
3. **transcriber.py** — 呼叫 Whisper 的 `transcribe_audio()`
4. **analyzer.py** — 三個 Claude 函式
5. **qa_engine.py** — 附關鍵字檢索的 `answer_question()`
6. **exporter.py** — 所有 5 種匯出格式
7. **app.py** — 3 個頁面：Process New、Episode Library、附自動重新整理的 Batch Queue

實作每個檔案後：

- 測試它（直接執行模組或啟動 Streamlit 並在瀏覽器中驗證）
- 只有在**瀏覽器**驗證後才在 feature_list.json 中標記 `"passes": true`
- 移至下一個檔案前先提交

**無需下載即可測試音訊：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

---

### 結束本 Session

完成前：

1. **提交所有工作**：

   ```bash
   git add -A
   git commit -m "Session 1: v5 scaffold, feature list, DB with FTS5, initial stubs"
   ```

2. **建立 `claude-progress.txt`**，摘要說明：
   - 本 Session 完成的項目
   - 每個檔案的目前狀態（stub/partial/complete）
   - 哪些 feature_list.json 項目現在通過
   - 遇到的任何問題
   - Session 2 的建議後續步驟

3. **確認 feature_list.json** 是有效的 JSON，恰好 **30** 個條目，全部 `"passes": false`
   （只有透過瀏覽器驗證的功能才標記為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境乾淨**：Streamlit 正在執行或優雅地停止

**請記住：** 批次佇列與 Plotly 時間軸是比 v4 新增的部分。
FTS5 設定與 v4 相同——先把這部分做對。
架構與正確性比速度更重要。
