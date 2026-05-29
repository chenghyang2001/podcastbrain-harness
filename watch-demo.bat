@echo off
REM ============================================================
REM watch-demo.bat
REM 用途：每 3 秒清螢幕並 SSH 到 VPS 執行遠端儀表板腳本，
REM       在 Windows 本機即時監看 PodcastBrain demo 自主編碼迴圈進度。
REM 用法：在本機直接雙擊或於命令列執行 watch-demo.bat
REM 停止：按 Ctrl+C 中斷迴圈
REM 注意：所有 bash 邏輯都放在 VPS 的 progress.sh，本檔不放任何 bash。
REM       ssh 遠端指令只用單一變數 %REMOTE%，避免巢狀雙引號被 batch 截斷。
REM ============================================================

setlocal

REM VPS 連線帳號與遠端儀表板指令（遠端絕對路徑，非本機路徑）
set VPS=claude@187.127.109.145
set REMOTE=bash /home/claude/podcastbrain-demo/progress.sh

:loop
cls
ssh %VPS% "%REMOTE%"
if errorlevel 1 (
    echo.
    echo SSH 連線失敗，3 秒後重試
)
timeout /t 3 /nobreak >nul
goto loop
