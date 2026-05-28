#!/bin/bash
set -e

echo "=== PodcastBrain v1 Init ==="

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

# 4. Create downloads directory (v1 stores audio files here, no DB)
mkdir -p downloads

# 5. Start Streamlit on port 8501 in background
nohup streamlit run podcastbrain/app.py --server.port 8501 --server.headless true \
    --server.fileWatcherType none > streamlit.log 2>&1 &

echo "Streamlit PID: $!"
echo "Dashboard: http://localhost:8501"
sleep 3
echo "init.sh complete"
