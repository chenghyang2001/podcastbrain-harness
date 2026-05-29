@echo off
REM ====================================================================
REM tunnel-8502.bat
REM 用途：開一條 SSH local port forward 通道，把本機 8502 轉送到 VPS
REM       （claude@187.127.109.145）的 localhost:8502，讓你在本機瀏覽器
REM       看 VPS 上的 PodcastBrain streamlit app。
REM 用法：雙擊本檔，或在終端機執行；接著在瀏覽器開 http://localhost:8502。
REM       通道建立後請保持此視窗開著；按 Ctrl+C 或關閉視窗即關閉通道。
REM 提醒：若出現 Address already in use，表示本機 8502 已被其他通道佔用，
REM       請先關掉其他佔用 8502 的通道視窗再重新執行本檔。
REM 本檔獨立可用，不依賴任何 Claude session。
REM ====================================================================
setlocal
set VPS=claude@187.127.109.145

echo ====================================================================
echo  SSH 通道：本機 8502 轉送到 VPS localhost:8502
echo  通道建立後，請在瀏覽器開 http://localhost:8502
echo  保持此視窗開著；按 Ctrl+C 或關閉視窗即關閉通道。
echo ====================================================================
echo.

:loop
REM -N 純轉發不執行遠端指令；ExitOnForwardFailure 確保轉發失敗時 ssh 立即返回
ssh -o ExitOnForwardFailure=yes -L 8502:localhost:8502 -N %VPS%
echo [tunnel] 通道中斷或失敗，3 秒後重連（Ctrl+C 結束）...
timeout /t 3 /nobreak >nul
goto loop
