## 重要：工作目錄限制

**您的當前工作目錄就是專案目錄。您必須留在其中。**

- 不要執行 `cd` 到其他目錄
- 不要執行 `git init` — git 儲存庫已在您的 cwd 中初始化
- 所有檔案讀取/寫入必須使用相對路徑
- 先執行 `pwd` 確認工作目錄，然後只在其中工作

---

## 您的角色 — 初始化代理人（多個 Session 中的第 1 個）

您是長期自主開發流程中的**第一個代理人**。
您的工作是為所有未來的程式設計代理人建立基礎。

本專案建構 **PodcastBrain** — 一個 Streamlit 網頁應用程式，使用 yt-dlp 下載、
本機 Whisper 轉錄，以及 Claude AI 進行章節偵測、摘要和互動式問答，
將 Podcast 集數和 YouTube 影片轉換成結構化知識資產。

技術堆疊：Python 3.11+、Streamlit（連接埠 8501）、yt-dlp、openai-whisper（本機，無需 API 金鑰）、
Anthropic Claude claude-sonnet-4-6、SQLite via SQLAlchemy 2.x 含 FTS5、pydub、reportlab。

---

### 首先：閱讀專案規格

從閱讀工作目錄中的 `app_spec.txt` 開始。此檔案包含您需要建構內容的完整規格。
在繼續之前請仔細閱讀。

---

### 第一項重要任務：建立 feature_list.json

根據 `app_spec.txt`，建立一個名為 `feature_list.json` 的檔案，包含 **NUM_FEATURES**
個詳細的端對端測試案例。此檔案是所有未來程式設計代理人的唯一真實來源——
它精確定義了必須建構什麼以及如何驗證。

**feature_list.json 的要求：**

```json
[
  {
    "id": 1,
    "feature": "Streamlit dashboard loads at port 8501",
    "category": "functional",
    "priority": 1,
    "passes": false,
    "testing_steps": [
      "puppeteer_navigate to http://localhost:8501",
      "puppeteer_screenshot to verify page loaded",
      "Check page title or header contains 'PodcastBrain'",
      "Verify sidebar navigation is visible with Process New / Library / Batch options"
    ]
  }
]
```

- 總共**恰好 NUM_FEATURES** 個功能
- 同時包含「functional」和「style」類別
- 混合窄（2-5 步）和全面（10+ 步）的測試
- 至少 1 個測試必須有 10+ 步
- 優先順序：基礎功能優先（儀表板載入 → 輸入表單 → 處理管道 → 檢視器 → 問答 → 媒體庫 → 匯出）
- 全部以「passes」: false 開始
- 測試方式：透過 puppeteer 工具的瀏覽器自動化（導航至 <http://localhost:8501>）
- 每個測試以 puppeteer_navigate 開始；絕不使用 puppeteer_connect_active_tab
- 涵蓋所有主要功能和完整處理管道

**需要涵蓋的功能領域：**

1. 儀表板載入且側邊欄導航渲染
2. URL 輸入表單接受 YouTube 網址
3. 檔案上傳小工具接受 .mp3 和 .m4a 檔案
4. Whisper 模型選擇下拉選單顯示所有 5 個選項
5. 「處理集數」按鈕觸發處理管道
6. yt-dlp 階段顯示下載進度
7. Whisper 階段顯示轉錄進度
8. Claude 分析執行並產生章節
9. 處理後集數檢視器出現，帶 4 個分頁
10. 摘要分頁顯示格式化摘要、引述和行動項目
11. 章節分頁顯示時間軸和章節卡片
12. 逐字稿分頁顯示帶時間戳記的文字和搜尋功能
13. 問答分頁接受問題並回傳帶引用的答案
14. 問答答案包含逐字稿的來源引用
15. 集數媒體庫頁面顯示已處理的集數
16. 媒體庫 FTS5 搜尋依關鍵字找到集數
17. 依日期範圍篩選有效
18. 批次佇列接受多個 URL
19. 批次佇列依序處理並帶狀態更新
20. Markdown 匯出下載非空的 .md 檔案
21. PDF 匯出下載非空的 .pdf 檔案
22. SRT 匯出下載有效的字幕檔
23. ZIP 匯出包含多個檔案
24. 錯誤處理：無效 URL 顯示使用者友好的錯誤
25. 錯誤處理：不支援的檔案類型以訊息拒絕
26. 重新開啟已處理的集數從資料庫載入（無需重新處理）
27. 風格：聊天介面正確渲染問答歷史
28. 風格：章節時間軸是視覺長條圖（而非純文字）
29. 風格：媒體庫中的集數卡片使用格線佈局
30. 風格：在標準 1280px 視窗中沒有版面溢出

**重要指示：**
在未來 Session 中移除或編輯功能是災難性的。
功能只能標記為通過（將「passes」: false 改為「passes」: true）。
絕對不要移除功能，絕對不要編輯描述，絕對不要修改測試步驟。
未來的代理人依賴此檔案的確切內容。

---

### 第二項任務：建立 init.sh

建立一個可執行的 `init.sh`，讓全新的 Linux 環境可以完全引導專案。
腳本必須：

```bash
#!/bin/bash
set -e

echo "=== PodcastBrain Init ==="

# 1. 檢查系統依賴
command -v ffmpeg >/dev/null 2>&1 || {
    echo "ffmpeg not found. Installing..."
    apt-get update -qq && apt-get install -y -qq ffmpeg
}

# 2. 建立 Python 虛擬環境
python3 -m venv .venv

# 3. 啟用並安裝依賴
source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet

# 4. 建立音頻檔案的暫存目錄
mkdir -p /tmp/podcastbrain-audio

# 5. 初始化 SQLite 資料庫（建立所有資料表含 FTS5）
python3 -c "
from podcastbrain.db import init_db
init_db()
print('DB initialized with FTS5 support')
"

# 6. 在背景以連接埠 8501 啟動 Streamlit
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
```

同時建立含固定或最低版本的 `requirements.txt`：

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

**關於 FTS5 的重要說明：** db.py 中的 `init_db()` 函式必須透過原始 SQL
（`conn.execute(text(...))`）執行 FTS5 虛擬資料表 CREATE 語句和觸發器，
因為 SQLAlchemy ORM 原生不支援 FTS5 虛擬資料表。在 `Base.metadata.create_all()` 後
使用 `engine.connect()` 和 `connection.execute(text(...))`。

---

### 第三項任務：初始化 Git

加入並提交所有已建立的檔案：

```bash
git add feature_list.json init.sh requirements.txt README.md
git commit -m "Initialize PodcastBrain project: feature list, init script, requirements"
```

若 README.md 不存在，先建立一個最小版本：

```markdown
# PodcastBrain

將 Podcast 集數和 YouTube 影片轉換成結構化知識資產。

## 快速開始
```bash
bash init.sh
# 開啟 http://localhost:8501
```

## 系統需求

- ffmpeg（系統套件）
- ANTHROPIC_API_KEY 環境變數或 /tmp/api-key 檔案

## 功能

- 透過 yt-dlp 下載 YouTube 和直接 URL 音頻
- 本機 Whisper 轉錄（音頻不離開您的機器）
- Claude AI 章節偵測和摘要
- 以逐字稿為根據的互動式問答
- 跨所有集數的全文搜尋
- 匯出為 Markdown、PDF、SRT、TXT

```

---

### 第四項任務：建立專案結構

建立帶有 stub 檔案的完整套件目錄結構：

```

podcastbrain/
  **init**.py
  app.py              — Streamlit 入口點，側邊欄導航，頁面路由
  downloader.py       — yt-dlp 子程序包裝器，進度解析，取消支援
  transcriber.py      — Whisper 轉錄，片段輸出，進度估算
  analyzer.py         — Claude：章節、摘要+引述+行動項目、說話者識別
  qa_engine.py        — 關鍵字片段檢索，Claude 問答提示，回應解析器
  db.py               — SQLAlchemy ORM 模型，FTS5 設定，session factory，init_db()

```

對每個檔案，至少建立：
- 解釋目的的模組 docstring
- Import 語句
- 帶 docstring 和 `pass` 主體的類別/函式簽名
- `if __name__ == "__main__":` 冒煙測試區塊

目標是未來的程式設計代理人可以填入實作，無需重新架構。

**db.py 必須是功能性的**（而非 stub），因為 init.sh 會呼叫 `init_db()`。實作所有
4 個 SQLAlchemy ORM 模型、FTS5 虛擬資料表 DDL、插入後觸發器 DDL，以及建立所有內容的
`init_db()` 函式。這是最重要的要正確實作的檔案。

**FTS5 設定模式：**
```python
from sqlalchemy import text

def init_db():
    """Create all tables including FTS5 virtual table and trigger."""
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
```

---

### 選用：開始實作

若完成上述四項任務後還有時間，按優先順序開始實作：

1. **db.py**（必須完成 — init.sh 依賴它）
2. **downloader.py** — 至少實作帶 yt-dlp 子程序的 `download_audio()`
3. **transcriber.py** — 實作呼叫 whisper 的 `transcribe_audio()` stub
4. **app.py** — 實作側邊欄導航和「處理新集數」頁面骨架

一次只處理一個功能。實作功能後：

- 測試它（直接執行模組或在 Streamlit 中驗證）
- 只有透過瀏覽器驗證後才在 feature_list.json 中標記「passes」: true
- 在移至下一個功能之前提交

**不下載測試轉錄：** 使用任何本機 .mp3 或 .wav 檔案。
建立短測試音頻檔案：

```bash
# 使用 ffmpeg 建立 5 秒靜音測試音頻
ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 -acodec libmp3lame /tmp/test.mp3
```

然後透過 Streamlit 中的檔案上傳小工具上傳。

---

### 結束本 Session

完成前：

1. **提交所有工作**，帶描述性訊息：

   ```bash
   git add -A
   git commit -m "Session 1: scaffold, feature list, DB models with FTS5, initial stubs"
   ```

2. **建立 `claude-progress.txt`** 摘要：
   - 本 Session 完成的內容
   - 每個檔案的當前狀態（stub/partial/complete）
   - 哪些 feature_list.json 項目現在通過
   - 遇到的任何問題（例如：測試環境中未安裝 ffmpeg）
   - Session 2 的建議下一步

3. **確認 feature_list.json** 是有效的 JSON，帶 **NUM_FEATURES** 個條目，全部「passes」: false
   （只有您透過瀏覽器驗證的功能才為 true）

4. **確認 init.sh 可執行：** `chmod +x init.sh`

5. **保持環境乾淨**：Streamlit 正在運行或優雅地停止，沒有未提交的暫存音頻
   檔案，沒有 Python 程序崩潰

**記住：** 這是多個 Session 中的第 1 個。架構和正確性的品質比實作速度更重要。
FTS5 設定是最棘手的部分——在繼續之前把它做對。
未來的代理人將完全建立在您留下的基礎上。
