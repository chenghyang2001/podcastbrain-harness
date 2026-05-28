## 重要：工作目錄限制

**你目前的工作目錄就是專案目錄。你必須留在其中。**

- 禁止執行 `cd` 切換至其他目錄
- 所有檔案讀寫必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，之後只在該目錄中工作

---

## 你的角色 — 初始化代理（第 1 次 Session，v3：完整分析 + 問答）

你是多 session 自主開發流程中的**第一個代理**。
你的任務是為所有後續程式碼代理奠定基礎。

本專案建構 **PodcastBrain v3** — 一個 Streamlit 網頁應用程式，可從 YouTube 下載音訊，
以 Whisper 在本地轉錄，執行三種 Claude AI 分析
（章節偵測、含引言與行動項目的完整摘要、發言人識別），
並提供以逐字稿為基礎的互動式問答介面。

技術堆疊：Python 3.11+、Streamlit（port 8501）、yt-dlp、openai-whisper（本地）、
Anthropic Claude claude-sonnet-4-6、SQLAlchemy 2.x + SQLite、ffmpeg-python。

---

### 首先：閱讀專案規格

從工作目錄中讀取 `app_spec.txt`。此檔案包含你需要建構的完整規格。
仔細閱讀後再繼續。

---

### 任務 1：建立 feature_list.json

根據 `app_spec.txt`，建立名為 `feature_list.json` 的檔案，包含恰好 **21** 個
詳細的端對端測試案例。此檔案是所有後續程式碼代理的唯一事實來源——
精確定義必須建構的內容及驗證方式。

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

- 總計恰好 **21** 個功能
- 包含「functional」和「style」兩種類別
- 混合精簡（2-5 步驟）與完整（10+ 步驟）的測試
- 至少 1 個測試必須有 10+ 個步驟
- 優先順序：基礎功能優先（應用程式載入 → 輸入 → 流程 → 檢視器標籤頁 → 問答 → 資料庫 → 樣式）
- 全部從 `"passes": false` 開始
- 透過 puppeteer 工具進行瀏覽器自動化測試（導覽至 <http://localhost:8501>）
- 每個測試都從 puppeteer_navigate 開始；**絕不使用 puppeteer_connect_active_tab**
- 涵蓋所有主要功能及完整的處理流程

**需涵蓋的功能範圍（共 21 個）：**

1. 應用程式在 port 8501 載入，含側欄導覽（處理新劇集、我的劇集）
2. URL 輸入欄位接受 YouTube 觀看 URL
3. 檔案上傳元件接受 .mp3 和 .m4a 檔案
4. Whisper 模型選擇下拉選單顯示全部 5 個選項（tiny、base、small、medium、large）
5. 「處理劇集」按鈕觸發完整處理流程
6. 下載階段顯示 yt-dlp 進度條即時更新
7. Whisper 語音轉錄階段顯示進度指示器
8. Claude 章節偵測執行並產生章節清單
9. Claude 完整分析執行：摘要、關鍵引言、行動項目
10. Claude 發言人識別執行並標記發言人
11. 劇集檢視器顯示 4 個標籤頁：摘要、章節、逐字稿、問答
12. 摘要標籤顯示格式化摘要、關鍵引言與行動項目
13. 章節標籤顯示含標題與時間戳的章節清單
14. 逐字稿標籤顯示含時間戳的文字及逐字稿內搜尋功能
15. 問答標籤接受問題並回傳以逐字稿為基礎的答案
16. 問答答案包含來源引用（來自逐字稿的時間戳參考）
17. 問答聊天紀錄在 session 中保存（可見多個問答）
18. 我的劇集頁面列出所有先前處理過的劇集
19. 點擊已處理的劇集可開啟檢視器，無需重新處理
20. 樣式：問答聊天介面正確呈現使用者/助理訊息樣式
21. 樣式：4 個標籤頁的檢視器在標準 1280px 視窗寬度下沒有溢出

**重要說明：**
在未來 session 中移除或編輯功能是災難性的。
功能只能被標記為通過（將 `"passes": false` 改為 `"passes": true`）。
絕不移除功能、絕不編輯描述、絕不修改 testing_steps。
後續代理依賴此檔案的確切內容。

---

### 任務 2：建立 init.sh 與 requirements.txt

建立一個可執行的 `init.sh`，用於在全新 Linux 環境中啟動專案：

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

# 4. 建立音訊暫存目錄與下載目錄
mkdir -p /tmp/podcastbrain-audio
mkdir -p downloads

# 5. 初始化 SQLite 資料庫（建立所有資料表）
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized')
"

# 6. 在背景以 port 8501 啟動 Streamlit
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

同時建立含固定最低版本的 `requirements.txt`：

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
git commit -m "Initialize PodcastBrain v3: feature list, init script, requirements"
```

若 README.md 不存在，先建立一個最小版本：

```markdown
# PodcastBrain v3 — Full Analysis + Q&A

Downloads audio, transcribes with Whisper, runs Claude AI analysis and Q&A.

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
- Claude AI: chapter detection, summary, key quotes, action items, speaker identification
- Interactive Q&A grounded in the transcript with source citations
- Episode library with 4-tab viewer
- SQLite persistence across sessions

```

---

### 任務 4：建立專案目錄結構

建立含存根檔案的套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py         — Streamlit 進入點：側欄導覽、處理新劇集頁面、我的劇集頁面
  downloader.py  — yt-dlp 子程序包裝器：解析進度、支援取消
  transcriber.py — Whisper 語音轉錄：模型載入（快取）、片段輸出
  analyzer.py    — Claude：章節偵測、摘要+引言+行動項目、發言人識別（3 個獨立函式）
  qa_engine.py   — 問答：關鍵字檢索、Claude 提示、回應解析器
  db.py          — SQLAlchemy ORM 模型、session 工廠、init_db()

```

每個檔案至少建立：
- 說明用途的模組 docstring
- import 語句
- 含 docstring 與 `pass` 主體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是讓後續程式碼代理可以直接填入實作，無需重新設計架構。

**db.py 必須是可運作的**（非存根），因為 init.sh 呼叫 `init_db()`。
實作全部 4 個 SQLAlchemy ORM 模型與 `init_db()` 函式。

**v3 資料庫結構 — 4 個資料表：**

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
    status = Column(String, default="pending")    # pending / processing / complete / error
    claude_analysis = Column(Text)                # JSON: {summary, quotes, action_items, speakers}
    created_at = Column(DateTime, default=datetime.utcnow)
    transcripts = relationship("Transcript", back_populates="episode", cascade="all, delete-orphan")
    chapters = relationship("Chapter", back_populates="episode", cascade="all, delete-orphan")
    qa_history = relationship("QAHistory", back_populates="episode", cascade="all, delete-orphan")

class Transcript(Base):
    __tablename__ = "transcripts"
    id = Column(Integer, primary_key=True)
    episode_id = Column(Integer, ForeignKey("episodes.id"), nullable=False)
    full_text = Column(Text)
    segments = Column(Text)    # JSON string of [{start, end, text}]
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
    source_ts = Column(Text)     # JSON list of cited timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    episode = relationship("Episode", back_populates="qa_history")

def init_db():
    """Create all tables (v3: episodes, transcripts, chapters, qa_history)."""
    Base.metadata.create_all(engine)
    print("DB initialized (v3: 4 tables)")
```

**v3 不使用 FTS5** — 全文搜尋功能直到 v4 才需要。

---

### 選做：開始實作

完成上述四個任務後若仍有時間，依優先順序實作：

1. **db.py** — 完整實作（init.sh 所需）
2. **downloader.py** — `download_audio()`，使用 yt-dlp 子程序及解析進度
3. **transcriber.py** — `transcribe_audio()`，呼叫 `whisper.load_model()` + `model.transcribe()`
4. **analyzer.py** — 三個獨立函式：`generate_chapters()`、`generate_summary_quotes_actions()`、`identify_speakers()`
5. **qa_engine.py** — `answer_question()`，含關鍵字檢索 + Claude 提示
6. **app.py** — 側欄導覽 + 處理新劇集頁面 + 4 標籤頁劇集檢視器

實作每個檔案後：

- 測試（直接執行模組，或啟動 Streamlit 並在瀏覽器中驗證）
- 僅在**瀏覽器**驗證後才在 feature_list.json 中標記 `"passes": true`
- 移至下一個檔案前先提交

**不下載音訊進行測試：** 建立一個短暫的靜音測試檔案：

```bash
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

然後透過 Streamlit 的檔案上傳元件上傳。

---

### 結束本次 Session

完成前：

1. **提交所有工作**：

   ```bash
   git add -A
   git commit -m "Session 1: v3 scaffold, feature list, DB models with qa_history, initial stubs"
   ```

2. **建立 `claude-progress.txt`**，摘要說明：
   - 本次 session 完成的工作
   - 每個檔案的當前狀態（存根/部分完成/完整）
   - feature_list.json 中哪些項目現在通過
   - 遇到的任何問題
   - 第 2 次 Session 的建議後續步驟

3. **確認 feature_list.json** 是有效 JSON，恰好 **21** 個條目，全部 `"passes": false`
   （僅對瀏覽器驗證過的功能標記為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境乾淨**：Streamlit 正在執行或已優雅停止

**記住：** 架構正確性比速度重要。
4 個資料表的資料庫結構與三個 Claude 函式必須從一開始就設計正確。
後續代理將完全基於你留下的基礎繼續建構。
