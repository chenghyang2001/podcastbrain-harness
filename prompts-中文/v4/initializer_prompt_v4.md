## 重要限制：工作目錄約束

**你目前的工作目錄即為專案目錄。你必須留在其中。**

- 不可執行 `cd` 切換至其他目錄
- 所有檔案的讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，之後完全在此目錄內作業

---

## 你的角色 — 初始化代理（第 1 階段，v4：匯出選項 + 節目庫）

你是多階段自主開發流程中的**第一個代理**。
你的任務是為所有後續編碼代理奠定基礎。

本專案建構 **PodcastBrain v4** — 一個 Streamlit 網頁應用程式，可從 YouTube 下載
音訊、以 Whisper 在本地轉錄、執行三項 Claude AI 分析、
提供互動式問答，並新增：匯出為 Markdown/PDF/SRT/TXT/ZIP 格式，以及
由 SQLite FTS5 全文搜尋支撐的可搜尋節目庫。

技術堆疊：Python 3.11+、Streamlit（port 8501）、yt-dlp、openai-whisper（本地），
Anthropic Claude claude-sonnet-4-6、SQLAlchemy 2.x + SQLite with FTS5、
pydub、reportlab、ffmpeg-python。

---

### 首先：閱讀專案規格

先從工作目錄讀取 `app_spec.txt`。此檔案包含你需要建構的完整
規格說明。請在繼續之前仔細閱讀。

---

### 任務 1：建立 feature_list.json

根據 `app_spec.txt`，建立名為 `feature_list.json` 的檔案，內含恰好 **27** 個
詳細的端到端測試案例。此檔案是所有未來編碼代理的唯一事實來源 —
它精確定義了必須建構的內容及驗證方式。

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
      "Verify sidebar contains 'Batch Queue' navigation item (stub)"
    ]
  }
]
```

- 總共恰好 **27** 個功能
- 同時包含 "functional" 和 "style" 類別
- 混合簡短（2-5 步驟）和完整（10+ 步驟）的測試
- 至少 1 個測試必須有 10+ 步驟
- 優先順序：基礎先行（應用程式載入 → 輸入 → 流程 → 檢視器 → 匯出 → 節目庫 → 樣式）
- 全部以 `"passes": false` 開始
- 透過 puppeteer 工具進行瀏覽器自動化測試（導覽至 <http://localhost:8501>）
- 每個測試以 puppeteer_navigate 開始；**絕對不使用 puppeteer_connect_active_tab**
- 涵蓋所有主要功能與完整處理流程

**需涵蓋的功能範圍（共 27 個）：**

1. 應用程式在 port 8501 載入並顯示側邊欄導覽（處理新集數、節目庫、批次佇列占位）
2. URL 輸入欄位接受 YouTube 觀看網址
3. 檔案上傳元件接受 .mp3 和 .m4a 檔案
4. Whisper 模型選擇下拉選單顯示全部 5 個選項
5. 「處理集數」按鈕觸發完整處理流程
6. 下載階段顯示 yt-dlp 進度條即時更新
7. Whisper 轉錄階段顯示進度指示
8. Claude 章節偵測執行並產生章節列表
9. Claude 完整分析執行：摘要、引述、行動項目
10. Claude 說話者識別執行
11. 節目檢視器顯示 4 個分頁：摘要、章節、逐字稿、問答
12. 摘要分頁顯示格式化的摘要、引述和行動項目
13. 章節分頁顯示含時間戳的章節列表
14. 逐字稿分頁顯示帶時間戳的文字及搜尋功能
15. 問答分頁接受問題並回傳含引用的有依據回答
16. 問答回答包含來源引用時間戳
17. Markdown 匯出下載非空 .md 檔案
18. PDF 匯出下載非空 .pdf 檔案
19. SRT 匯出下載含 HH:MM:SS,mmm 時間戳的有效字幕檔案
20. TXT 匯出下載含逐字稿內容的純文字檔案
21. ZIP 匯出下載包含多個檔案的壓縮檔
22. 節目庫頁面以 3 欄卡片網格顯示已處理集數
23. FTS5 以關鍵字搜尋能找到逐字稿中包含該詞的集數
24. 節目庫中的日期範圍篩選能正確縮小結果
25. 點擊節目庫中的集數卡片可開啟其 4 分頁檢視器而無需重新處理
26. 樣式：節目庫中的集數卡片使用網格排版（非清單）
27. 樣式：在標準 1280px 視窗寬度下無版面溢位

**重要說明：**
在未來的階段中移除或編輯功能將造成災難性後果。
功能只能被標記為通過（將 `"passes": false` 改為 `"passes": true`）。
絕對不可移除功能、不可編輯描述、不可修改 testing_steps。
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

# 2. 建立 Python 虛擬環境
python3 -m venv .venv

# 3. 啟用並安裝相依套件
source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 4. 建立音訊暫存目錄和下載目錄
mkdir -p /tmp/podcastbrain-audio
mkdir -p downloads

# 5. 初始化 SQLite 資料庫（建立所有資料表，包含 FTS5）
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

同時建立含固定最低版本號的 `requirements.txt`：

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

---

### 任務 3：初始化 Git

新增並提交所有已建立的檔案：

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v4: feature list, init script, requirements"
```

若 README.md 不存在，請先建立一個最精簡的版本：

```markdown
# PodcastBrain v4 — Export Options + Episode Library

Full podcast analysis with Claude AI, FTS5 search library, and multi-format export.

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
- Export: Markdown, PDF, SRT, TXT, ZIP
- Episode Library with FTS5 full-text search and date filtering
- SQLite persistence with FTS5 virtual table

```

---

### 任務 4：建立專案結構

建立包含存根檔案的套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py         — Streamlit 進入點：側邊欄導覽，3 個頁面（處理新集數、節目庫、批次占位）
  downloader.py  — yt-dlp subprocess 包裝器：進度解析、取消支援
  transcriber.py — Whisper 轉錄：模型載入（已快取）、片段輸出
  analyzer.py    — Claude：3 個獨立函式（章節、摘要+引述+行動項目、說話者）
  qa_engine.py   — 問答：關鍵字檢索、Claude 有依據提示、回應解析
  exporter.py    — 匯出：MD、PDF（reportlab）、SRT、TXT、ZIP
  db.py          — SQLAlchemy ORM 模型、FTS5 設定、工作階段工廠、init_db()

```

每個檔案至少必須建立：
- 說明用途的模組文件字串
- import 語句
- 含文件字串與 `pass` 主體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是讓未來的編碼代理能填入實作內容，而無需重新設計架構。

**db.py 必須是功能性的**（非存根），因為 init.sh 會呼叫 `init_db()`。
實作全部 4 個 SQLAlchemy ORM 模型、FTS5 虛擬資料表 DDL、插入後
觸發器 DDL，以及 `init_db()` 函式。

**v4 資料庫 schema — 4 個 ORM 資料表 + FTS5 虛擬資料表：**

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
    status = Column(String, default="pending")
    claude_analysis = Column(Text)    # JSON: {summary, quotes, action_items, speakers}
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
    source_ts = Column(Text)    # JSON 引用時間戳列表
    created_at = Column(DateTime, default=datetime.utcnow)
    episode = relationship("Episode", back_populates="qa_history")


def init_db():
    """建立所有 ORM 資料表，加上 FTS5 虛擬資料表和插入後觸發器。

    重要：FTS5 虛擬資料表無法透過 SQLAlchemy ORM 建立。
    必須使用 conn.execute(text(...)) 透過原始 SQL 建立。
    先呼叫 Base.metadata.create_all()，再建立 FTS5 和觸發器。
    """
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
    print("DB initialized (v4: 4 tables + FTS5 virtual table + trigger)")
```

**FTS5 關鍵注意事項：**

- 使用 `CREATE VIRTUAL TABLE IF NOT EXISTS` — 每次啟動均可安全呼叫
- 使用 `CREATE TRIGGER IF NOT EXISTS` — 每次啟動均可安全呼叫
- 觸發器在每次 INSERT 到 `transcripts` 時自動填入 `transcripts_fts`
- FTS5 搜尋僅使用參數化查詢 — 絕對不使用字串插值（SQL 注入風險）

---

### 選擇性：開始實作

若上述四項任務完成後仍有時間，請依優先順序實作：

1. **db.py** — 完整（init.sh 必需）
2. **downloader.py** — `download_audio()`，含 yt-dlp subprocess 和進度解析
3. **transcriber.py** — `transcribe_audio()`，呼叫 Whisper
4. **analyzer.py** — 三個 Claude 函式
5. **qa_engine.py** — `answer_question()`，含關鍵字檢索
6. **exporter.py** — `export_markdown()`、`export_pdf()`、`export_srt()`、`export_txt()`、`export_zip()`
7. **app.py** — 3 頁側邊欄 + 含 FTS5 搜尋的節目庫 + 檢視器中的匯出按鈕

實作每個檔案後：

- 測試它（直接執行模組，或啟動 Streamlit 並在瀏覽器中驗證）
- 僅在**瀏覽器**驗證後才將 feature_list.json 中的 `"passes"` 標記為 `true`
- 在繼續下一個檔案前先提交

**無需下載即可測試音訊：**

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

---

### 結束本階段

結束前：

1. **提交所有工作**：

   ```bash
   git add -A
   git commit -m "Session 1: v4 scaffold, feature list, DB with FTS5, initial stubs"
   ```

2. **建立 `claude-progress.txt`** 摘要說明：
   - 本階段完成了什麼
   - 每個檔案的目前狀態（存根 / 部分完成 / 完整）
   - feature_list.json 中哪些項目現在通過
   - 遇到的任何問題
   - 第 2 階段的建議後續步驟

3. **確認 feature_list.json** 是有效 JSON，恰好包含 **27** 個條目，全部 `"passes": false`
   （只有透過瀏覽器驗證的功能才標記為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境整潔**：Streamlit 正在執行或已優雅停止

**記住：** FTS5 設定是最關鍵也最棘手的部分。
在做其他任何事之前先把 `init_db()` 做對 — 未來的代理都依賴它。
架構正確性比速度更重要。
