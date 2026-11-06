#!/usr/bin/env bash
set -eo pipefail

echo "=========================================================="
echo " Starting Hermes Agent Cloud Runner (Render Optimized)"
echo "=========================================================="

export PORT="${PORT:-8000}"
export HERMES_DASHBOARD_PORT="$PORT"
export HERMES_DASHBOARD_HOST="0.0.0.0"
export HERMES_DASHBOARD_BASIC_AUTH_USERNAME="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-admin}"
export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-5002112A}"
export HERMES_DASHBOARD_BASIC_AUTH_SECRET="${HERMES_DASHBOARD_BASIC_AUTH_SECRET:-hermes-render-cloud-persistent-token-signing-secret-2026}"
export HERMES_HOME="/opt/data"
export HERMES_WRITE_SAFE_ROOT="/opt/data"
export PYTHONUNBUFFERED=1

# Resolve Python and Hermes binaries
PYTHON_BIN="/opt/hermes/.venv/bin/python"
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_BIN="$(command -v python3)"
fi

HERMES_BIN="/opt/hermes/.venv/bin/hermes"
if [ ! -f "$HERMES_BIN" ]; then
    HERMES_BIN="$(command -v hermes)"
fi

mkdir -p /opt/data /tmp/hermes-runtime
chmod 777 /opt/data /tmp/hermes-runtime 2>/dev/null || true

# 1. Restore state.db, skills, and configuration from Hugging Face if configured
if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
    echo "[Entrypoint] Checking cloud dataset for existing state..."
    "$PYTHON_BIN" /opt/hermes/cloud/hf_sync.py download || echo "[Entrypoint] Initial state download warning, proceeding..."
    chmod 666 /opt/data/*.db 2>/dev/null || true
    chmod -R 777 /opt/data 2>/dev/null || true

    # Periodic background database backup (every 15 mins)
    run_periodic_sync() {
        while true; do
            sleep 900
            echo "[Storage] Periodic state.db backup starting..."
            "$PYTHON_BIN" /opt/hermes/cloud/hf_sync.py upload || echo "[Storage] Periodic backup warning"
        done
    }
    run_periodic_sync &
    SYNC_LOOP_PID=$!
    echo "[Entrypoint] Background dataset sync loop started."
fi

# 2. Seed default config.yaml if none exists
if [ ! -f /opt/data/config.yaml ]; then
    echo "[Entrypoint] Seeding default configuration to /opt/data/config.yaml..."
    cp /opt/hermes/cloud/default_config.yaml /opt/data/config.yaml
    chmod 666 /opt/data/config.yaml || true
fi

# Ensure dashboard basic_auth is always injected so the auth gate never refuses bind to 0.0.0.0
"$PYTHON_BIN" -c "
import hermes_yaml as yaml
from pathlib import Path

p = Path('/opt/data/config.yaml')
try:
    cfg = yaml.safe_load(p.read_text()) if p.exists() else {}
    if not isinstance(cfg, dict):
        cfg = {}
except Exception:
    cfg = {}

dash = cfg.setdefault('dashboard', {})
dash['host'] = '0.0.0.0'
ba = dash.setdefault('basic_auth', {})
if not ba.get('username'):
    ba['username'] = 'admin'
if not ba.get('password_hash') and not ba.get('password'):
    ba['password_hash'] = 'scrypt' + '$' + '16384' + '$' + '8' + '$' + '1' + '$' + 'aSijr7grIdbXMF8yI9DvAA==' + '$' + 'TelcVwk+9APn8LUrCZaXF468X5h2VGca7a7QRt3nxeY='
if not ba.get('secret'):
    ba['secret'] = 'hermes-render-cloud-persistent-token-signing-secret-2026'

p.write_text(yaml.safe_dump(cfg))
"
chmod 666 /opt/data/config.yaml 2>/dev/null || true

# 3. Start zero-RAM 9-minute keep-alive self-pinger
run_keepalive() {
    local target_url="http://127.0.0.1:${PORT}/api/status"
    local fallback_url="http://127.0.0.1:${PORT}/"
    local interval="${PING_INTERVAL_SECONDS:-540}"
    echo "[KeepAlive] Zero-RAM keep-alive active on port $PORT (every ${interval}s)"
    sleep 30
    while true; do
        if curl -s -f -A "Hermes-KeepAlive/1.0" --max-time 15 "$target_url" > /dev/null 2>&1 || \
           curl -s -f -A "Hermes-KeepAlive/1.0" --max-time 15 "$fallback_url" > /dev/null 2>&1; then
            echo "[KeepAlive] $(date '+%Y-%m-%d %H:%M:%S UTC') Ping to local dashboard -> HTTP 200 OK"
        else
            echo "[KeepAlive] $(date '+%Y-%m-%d %H:%M:%S UTC') Ping pending or waiting for server"
        fi
        sleep "$interval"
    done
}
run_keepalive &
PINGER_PID=$!
echo "[Entrypoint] Zero-RAM keep-alive pinger started."

# 4. Trap termination signals for a graceful final state.db upload
cleanup() {
    echo ""
    echo "[Entrypoint] Received termination signal (SIGTERM/SIGINT)."
    if [ -n "$HF_TOKEN" ] && [ -n "$HF_DATASET_ID" ]; then
        echo "[Entrypoint] Performing final state.db backup to dataset..."
        "$PYTHON_BIN" /opt/hermes/cloud/hf_sync.py upload || echo "[Entrypoint] Final backup warning."
    fi

    if [ -n "$PINGER_PID" ]; then
        kill "$PINGER_PID" 2>/dev/null || true
    fi

    if [ -n "$SYNC_LOOP_PID" ]; then
        kill "$SYNC_LOOP_PID" 2>/dev/null || true
    fi

    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    echo "[Entrypoint] Cleanup complete. Exiting."
    exit 0
}

trap cleanup SIGTERM SIGINT

# 5. Launch Hermes Web UI Dashboard on $PORT
echo "[Entrypoint] Launching Hermes Agent Web Dashboard on port ${PORT}..."
"$HERMES_BIN" dashboard --host 0.0.0.0 --port "$PORT" --no-open &
APP_PID=$!

wait "$APP_PID"
