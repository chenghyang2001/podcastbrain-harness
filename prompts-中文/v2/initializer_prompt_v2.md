## 重要：工作目錄限制

**你目前的工作目錄即為專案目錄，你必須留在此目錄中。**

- 不得執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後完全在此目錄中作業

---

## 你的角色 — 初始化代理（Session 1，v2：音訊 + Whisper + 章節）

你是多工作階段自主開發流水線中的**第一個代理**。
你的任務是為所有後續編碼代理奠定基礎。

此專案建構 **PodcastBrain v2** — 一個 Streamlit 網頁應用程式，使用 yt-dlp 從
YouTube URL 下載音訊，使用 OpenAI Whisper 在本機進行轉錄，
並使用 Claude AI 進行章節偵測。結果持久化於 SQLite 資料庫，
並可透過側邊欄導覽的單集檢視器瀏覽。

技術堆疊：Python 3.11+、Streamlit（連接埠 8501）、yt-dlp、openai-whisper（本機）、
Anthropic Claude claude-sonnet-4-6、SQLAlchemy 2.x + SQLite、ffmpeg-python。

---

### 第一步：閱讀專案規格

從工作目錄讀取 `app_spec.txt`。此檔案包含你需要建構的完整規格。
請在繼續之前仔細閱讀。

---

### 任務 1：建立 feature_list.json

根據 `app_spec.txt`，建立一個名為 `feature_list.json` 的檔案，包含恰好 **14** 個
詳細的端對端測試案例。此檔案是所有未來編碼代理的唯一真實來源 — 它精確定義了
需要建構的內容及其驗證方式。

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
      "Verify sidebar contains 'My Episodes' navigation item"
    ]
  }
]
```

- 總計恰好 **14** 個功能項目
- 包含「functional」與「style」兩種類別
- 混合精簡（2-5 步驟）與全面（10+ 步驟）的測試
- 至少 1 個測試必須有 10+ 步驟
- 優先順序：基礎優先（應用載入 → 輸入 → 處理流水線 → 檢視器 → 資料庫 → 樣式）
- 全部以 `"passes": false` 開始
- 透過瀏覽器自動化工具測試（導覽至 <http://localhost:8501>）
- 每個測試以 puppeteer_navigate 開頭；**絕不使用 puppeteer_connect_active_tab**
- 涵蓋所有主要功能與完整處理流水線

**需涵蓋的功能領域（共 14 項）：**

1. 應用程式在連接埠 8501 載入，具備側邊欄導覽（Process New Episode、My Episodes）
2. URL 輸入欄位接受 YouTube 觀看網址
3. 檔案上傳元件接受 .mp3 與 .m4a 檔案
4. Whisper 模型選擇下拉選單顯示全部 5 個選項（tiny、base、small、medium、large）
5. 「Process Episode」按鈕觸發完整處理流水線
6. 下載階段顯示即時更新的 yt-dlp 進度條
7. Whisper 轉錄階段顯示進度指示器與模型名稱
8. Claude 章節偵測執行並產生章節清單
9. 處理完成後出現單集檢視器，含 2 個分頁：逐字稿與章節
10. 逐字稿分頁顯示附時間戳記的完整轉錄文字
11. 章節分頁顯示每個章節的標題與時間戳記清單
12. 「我的單集」頁面列出所有已處理的單集
13. 點擊已處理的單集，在不重新處理的情況下開啟其檢視器（從資料庫載入）
14. 樣式：在標準 1280px 視窗寬度下，側邊欄佈局無溢出

**重要說明：**
在未來的工作階段中移除或編輯功能項目將造成災難性後果。
功能只能標記為通過（將 `"passes": false` 改為 `"passes": true`）。
絕不移除功能，絕不編輯描述，絕不修改 testing_steps。
未來的代理依賴此檔案的確切內容。

---

### 任務 2：建立 init.sh 與 requirements.txt

建立一個可執行的 `init.sh`，在全新的 Linux 環境中引導啟動專案：

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

# 4. Create audio temp directory and downloads directory
mkdir -p /tmp/podcastbrain-audio
mkdir -p downloads

# 5. Initialize SQLite database (creates all tables)
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized')
"

# 6. Start Streamlit on port 8501 in background
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

同時建立 `requirements.txt`，附帶已鎖定的最低版本：

```
streamlit>=1.35.0
yt-dlp>=2024.1.0
openai-whisper>=20231117
anthropic>=0.25.0
sqlalchemy>=2.0.0
ffmpeg-python>=0.2.0
```

---

### 任務 3：初始化 Git

新增並提交所有已建立的檔案：

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain v2: feature list, init script, requirements"
```

若 README.md 不存在，請先建立一個最小版本：

```markdown
# PodcastBrain v2 — Audio + Whisper + Chapters

Downloads audio from YouTube, transcribes locally with Whisper, detects chapters with Claude AI.

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
- Claude AI chapter detection
- Episode library with transcript and chapter viewer
- SQLite persistence across sessions

```

---

### 任務 4：建立專案結構

建立含有 stub 檔案的套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py         — Streamlit 進入點：側邊欄導覽、處理新單集頁面、我的單集頁面
  downloader.py  — yt-dlp subprocess 包裝器：進度解析、取消支援
  transcriber.py — Whisper 轉錄：模型載入（已快取）、片段輸出
  analyzer.py    — Claude：僅限章節偵測（v2 範疇）
  db.py          — SQLAlchemy ORM 模型、session 工廠、init_db()

```

對每個檔案，至少建立：
- 說明用途的模組 docstring
- Import 語句
- 含 docstring 與 `pass` 本體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是讓未來的編碼代理無需重新架構，直接填入實作內容。

**db.py 必須是功能性的**（而非 stub），因為 init.sh 會呼叫 `init_db()`。
實作全部 3 個 SQLAlchemy ORM 模型與 `init_db()` 函式。

**v2 資料庫 schema — 3 張資料表：**

```python
from sqlalchemy import Column, Integer, String, Float, Text, DateTime, ForeignKey, create_engine
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
    status = Column(String, default="pending")   # pending / processing / complete / error
    created_at = Column(DateTime, default=datetime.utcnow)
    transcripts = relationship("Transcript", back_populates="episode", cascade="all, delete-orphan")
    chapters = relationship("Chapter", back_populates="episode", cascade="all, delete-orphan")

class Transcript(Base):
    __tablename__ = "transcripts"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    full_text = Column(Text)
    segments = Column(Text)   # JSON string of [{start, end, text}]
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

def init_db():
    """Create all tables."""
    Base.metadata.create_all(engine)
    print("DB initialized (v2: episodes, transcripts, chapters)")
```

**v2 不使用 FTS5** — 全文搜尋功能到 v4 才需要。

---

### 選用：開始實作

若完成以上四項任務後仍有時間，依優先順序實作：

1. **db.py** — 完整實作（init.sh 所必需）
2. **downloader.py** — 含 yt-dlp subprocess 與進度解析的 `download_audio()`
3. **transcriber.py** — 呼叫 `whisper.load_model()` + `model.transcribe()` 的 `transcribe_audio()`
4. **analyzer.py** — 呼叫 Claude API 的 `generate_chapters()`
5. **app.py** — 側邊欄導覽 + 處理新單集頁面骨架

實作每個檔案後：

- 測試它（直接執行模組，或啟動 Streamlit 並在瀏覽器中驗證）
- 只有在**瀏覽器**驗證後，才在 feature_list.json 中標記 `"passes": true`
- 在移至下一個檔案前先提交

**不下載音訊的測試方式：** 建立一個短暫的靜音測試檔案：

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

然後透過 Streamlit 檔案上傳元件上傳。

---

### 結束本工作階段

結束前：

1. **提交所有工作**：

   ```bash
   git add -A
   git commit -m "Session 1: v2 scaffold, feature list, DB models, initial stubs"
   ```

2. **建立 `claude-progress.txt`**，摘要說明：
   - 本工作階段完成的內容
   - 每個檔案的目前狀態（stub／部分完成／完整）
   - feature_list.json 中目前通過的項目
   - 遇到的任何問題
   - 給 Session 2 的建議後續步驟

3. **確認 feature_list.json** 為有效 JSON，包含恰好 **14** 個條目，全部為 `"passes": false`
   （只有在透過瀏覽器驗證的功能才標記為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境整潔**：Streamlit 正在執行或已正常停止

**記住：** 架構與正確性比速度更重要。
資料庫 schema 與 init_db() 函式是最關鍵的部分，必須正確實作。
未來的代理將完全建立在你留下的基礎之上。
