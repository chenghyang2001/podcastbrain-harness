@echo off
REM ============================================================
REM watch-demo.bat
REM 用途：串流顯示 VPS 上 PodcastBrain demo 的最新 tool 執行指令與輸出，
REM       最新內容附加（append）到畫面結尾、不清屏（不 cls）。
REM 用法：在本機直接雙擊或於命令列執行 watch-demo.bat；按 Ctrl+C 停止。
REM 原理：透過 ssh + tail -f 跟隨 VPS 上的 loop.log。
REM       該檔內含 parser 翻譯好的 [Tool: ...] 指令行與 [OK]/[ERR] 輸出行；
REM       tail -f 先顯示最近 15 行、之後每有新行自動附加到結尾，
REM       天然達成「append 不清屏」。外層 :loop 在 SSH 斷線時自動重連。
REM 注意：遠端指令只用變數展開（%LOG% 為無空白絕對路徑），不放任何巢狀
REM       雙引號，避免 Windows batch 把命令列截斷。整支腳本核心是讓輸出
REM       持續往下附加，因此絕對不使用 cls。
REM ============================================================

setlocal

REM VPS 連線帳號與遠端 log 絕對路徑（遠端路徑，非本機路徑）
set VPS=claude@187.127.109.145
set LOG=/home/claude/podcastbrain-demo/loop.log

echo [watch-demo] 串流最新 tool 指令與輸出，Ctrl+C 停止

:loop
REM tail -f 正常情況會持續跟隨；只有 SSH 斷線才會返回
ssh %VPS% "tail -n 15 -f %LOG%"
echo.
echo [watch-demo] 連線中斷，3 秒後重連（Ctrl+C 結束）...
timeout /t 3 /nobreak >nul
goto loop
