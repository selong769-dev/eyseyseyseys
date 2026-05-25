#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# start_services.sh
# Unified startup script for eye_project services
#
# Automatically detects hardware platform (Jetson/RPi) and applies appropriate
# configuration. Supports multiple Python virtualenv locations.
#
# Usage:
#   ./start_services.sh
#   USE_WAYLAND_KIOSK=1 ./start_services.sh  # (RPi with Wayland display)
#   CLOSE_EXISTING_BROWSERS=0 ./start_services.sh  # (Keep existing browser)
###############################################################################

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

###############################################################################
# Platform Detection
###############################################################################

detect_platform() {
  local platform=""
  
  # Check /proc/device-tree/model for Jetson or RPi identification
  if [[ -f /proc/device-tree/model ]]; then
    local model
    model=$(cat /proc/device-tree/model 2>/dev/null || true)
    if [[ "$model" =~ NVIDIA.*Jetson ]]; then
      platform="jetson"
    elif [[ "$model" =~ Raspberry.Pi ]]; then
      platform="rpi"
    fi
  fi
  
  # Fallback: check hostname
  if [[ -z "$platform" ]]; then
    local hostinfo
    hostinfo=$(hostname 2>/dev/null || true)
    if [[ "$hostinfo" =~ jetson ]]; then
      platform="jetson"
    elif [[ "$hostinfo" =~ rpi|raspberry ]]; then
      platform="rpi"
    fi
  fi
  
  # Fallback: check /proc/cpuinfo for Broadcom (RPi) or Jetson markers
  if [[ -z "$platform" ]]; then
    if grep -qi "broadcom\|BCM2" /proc/cpuinfo 2>/dev/null; then
      platform="rpi"
    elif grep -qi "jetson\|nvidia" /proc/cpuinfo 2>/dev/null; then
      platform="jetson"
    fi
  fi
  
  # Default to jetson if unable to detect
  if [[ -z "$platform" ]]; then
    echo "[WARN] Could not detect platform; defaulting to jetson"
    platform="jetson"
  fi
  
  echo "$platform"
}

PLATFORM=$(detect_platform)
echo "[INFO] Detected platform: $PLATFORM"

###############################################################################
# Venv Detection
###############################################################################

detect_venv() {
  local venv_dir=""
  
  if [[ -d "venv" ]]; then
    venv_dir="venv"
  elif [[ -d ".venv" ]]; then
    venv_dir=".venv"
  else
    echo "[ERROR] Python virtualenv not found at $PROJECT_DIR/venv or $PROJECT_DIR/.venv"
    exit 1
  fi
  
  echo "$venv_dir"
}

VENV_DIR=$(detect_venv)
source "$VENV_DIR/bin/activate"

echo "[OK] Using virtualenv: $VENV_DIR"

# Detect host IP address
HOST_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$HOST_IP" ]]; then
  HOST_IP="127.0.0.1"
fi

mkdir -p logs database

###############################################################################
# Database Initialization
###############################################################################

if [[ ! -f "database/database.db" ]]; then
  echo "[INFO] Initializing database/database.db"
  python - <<'PY'
from database.db import init_db
init_db('database/database.db')
print('database/database.db initialized')
PY
fi

###############################################################################
# Stop Legacy Services
###############################################################################

# Stop legacy minimal API server if running so port 5000 is available
if pgrep -af "python.*[ /]server.py" >/dev/null; then
  echo "[INFO] Stopping legacy server.py before starting eye_server.py"
  pkill -f "python.*[ /]server.py" || true
  sleep 1
fi

###############################################################################
# Service Startup Utilities
###############################################################################

start_if_not_running() {
  local name="$1"
  local pattern="$2"
  local cmd="$3"
  local logfile="$4"

  if pgrep -af "$pattern" >/dev/null; then
    echo "[OK] $name already running"
    pgrep -af "$pattern" | sed 's/^/[PID] /'
    return 0
  fi

  echo "[INFO] Starting $name"
  nohup bash -lc "$cmd" > "$logfile" 2>&1 &
  local pid=$!
  sleep 2

  if pgrep -af "$pattern" >/dev/null; then
    echo "[OK] $name started (pid=$pid)"
  else
    echo "[ERROR] Failed to start $name. Check $logfile"
    tail -n 80 "$logfile" || true
    exit 1
  fi
}

###############################################################################
# Start Services
###############################################################################

# eye_server.py
start_if_not_running \
  "eye_server.py (port 5000)" \
  "python.*eye_server.py" \
  "cd '$PROJECT_DIR' && source '$VENV_DIR/bin/activate' && python eye_server.py" \
  "logs/server.log"

# Kakao app
start_if_not_running \
  "kakao app (port 5001)" \
  "python.*database/app.py" \
  "cd '$PROJECT_DIR' && source '$VENV_DIR/bin/activate' && KAKAO_APP_PORT=5001 python database/app.py" \
  "logs/kakao_app.log"

###############################################################################
# Health Check
###############################################################################

wait_for_http() {
  local label="$1"
  local url="$2"
  local timeout="${3:-20}"

  for _ in $(seq 1 "$timeout"); do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
    if [[ "$code" != "000" && "$code" != "404" ]]; then
      echo "[OK] $label reachable ($code)"
      return 0
    fi
    sleep 1
  done

  echo "[WARN] $label not confirmed yet: $url"
  return 1
}

wait_for_http "eye_server.py" "http://127.0.0.1:5000/status" || true
wait_for_http "kakao_login" "http://127.0.0.1:5001/kakao/login?phone=01012341234" || true

echo ""
echo "=========================================="
echo "  Platform: $PLATFORM"
echo "  eye_server  →  http://${HOST_IP}:5000"
echo "  kakao app   →  http://${HOST_IP}:5001"
echo "=========================================="

###############################################################################
# Browser Configuration
###############################################################################

export DISPLAY="${DISPLAY:-:0}"
BROWSER_URL="${BROWSER_URL:-http://127.0.0.1:5000/}"
CLOSE_EXISTING_BROWSERS="${CLOSE_EXISTING_BROWSERS:-1}"

close_existing_browser_processes() {
  local closed_any=0
  local names=(
    "epiphany"
    "epiphany-browse"
    "epiphany-browser"
    "chromium"
    "chromium-browser"
    "google-chrome"
    "firefox"
  )

  for name in "${names[@]}"; do
    if pgrep -x "$name" >/dev/null 2>&1; then
      echo "[INFO] Closing existing browser process: $name"
      pkill -x "$name" || true
      closed_any=1
    fi
  done

  if pgrep -af "epiphany.*browser" >/dev/null 2>&1; then
    echo "[INFO] Closing existing Epiphany browser windows"
    pkill -f "epiphany.*browser" || true
    closed_any=1
  fi

  if [[ "$closed_any" -eq 1 ]]; then
    sleep 1
  else
    echo "[OK] No existing browser windows to close"
  fi
}

if [[ "$CLOSE_EXISTING_BROWSERS" == "1" ]]; then
  close_existing_browser_processes
fi

###############################################################################
# Jetson-specific Browser Launch (Simpler X11-only)
###############################################################################

if [[ "$PLATFORM" == "jetson" ]]; then
  echo ""
  echo "[INFO] Jetson platform → using X11 browser mode"
  
  echo "[INFO] Launching Epiphany browser (fullscreen)..."
  nohup epiphany-browser "$BROWSER_URL" > logs/browser.log 2>&1 &
  BROWSER_PID=$!

  # Wait for browser to start then activate fullscreen
  sleep 4
  if command -v xdotool >/dev/null 2>&1; then
    WID=$(xdotool search --name "Web" 2>/dev/null | head -1 || true)
    if [[ -z "$WID" ]]; then
      WID=$(xdotool search --pid "$BROWSER_PID" 2>/dev/null | head -1 || true)
    fi
    if [[ -n "$WID" ]]; then
      xdotool windowactivate "$WID" 2>/dev/null || true
      sleep 0.5
      xdotool key F11 2>/dev/null || true
      echo "[OK] Browser fullscreen activated (window=$WID)"
    else
      echo "[WARN] Could not find browser window for fullscreen"
    fi
  fi

###############################################################################
# RPi-specific Browser Launch (Wayland + X11 fallback)
###############################################################################

elif [[ "$PLATFORM" == "rpi" ]]; then
  echo ""
  echo "[INFO] Raspberry Pi platform → using enhanced browser mode (Wayland-aware)"
  
  # Setup X11 authority if needed
  if [[ -z "${XAUTHORITY:-}" ]]; then
    XA_FROM_MUTTER="$(ls /run/user/"$(id -u)"/.mutter-Xwaylandauth.* 2>/dev/null | head -1 || true)"
    if [[ -n "$XA_FROM_MUTTER" ]]; then
      export XAUTHORITY="$XA_FROM_MUTTER"
    elif [[ -f "$HOME/.Xauthority" ]]; then
      export XAUTHORITY="$HOME/.Xauthority"
    fi
  fi

  RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  WAYLAND_SOCKET="${WAYLAND_DISPLAY:-wayland-0}"
  WAYLAND_AVAILABLE=0
  USE_WAYLAND_KIOSK="${USE_WAYLAND_KIOSK:-0}"

  if [[ -S "$RUNTIME_DIR/$WAYLAND_SOCKET" ]]; then
    WAYLAND_AVAILABLE=1
  fi

  # Wayland mode (if available and enabled)
  if [[ "$USE_WAYLAND_KIOSK" == "1" && "$WAYLAND_AVAILABLE" -eq 1 ]]; then
    export XDG_RUNTIME_DIR="$RUNTIME_DIR"
    export WAYLAND_DISPLAY="$WAYLAND_SOCKET"
    unset GDK_BACKEND

    echo "[INFO] Wayland session detected; launching Epiphany for touch compatibility"

    if pgrep -af "epiphany --private-instance --new-window" >/dev/null 2>&1; then
      pkill -f "epiphany --private-instance --new-window" || true
      sleep 1
    fi

    if pgrep -x epiphany >/dev/null 2>&1 || pgrep -x epiphany-browse >/dev/null 2>&1 || pgrep -af "epiphany.*browser" >/dev/null 2>&1; then
      echo "[OK] Epiphany browser already running (Wayland mode)"
    else
      echo "[INFO] Launching Epiphany browser (Wayland mode, touchscreen-optimized)..."
      nohup epiphany-browser --new-window "$BROWSER_URL" > logs/browser.log 2>&1 &
      sleep 2
      if pgrep -x epiphany >/dev/null 2>&1 || pgrep -x epiphany-browse >/dev/null 2>&1 || pgrep -af "epiphany.*browser" >/dev/null 2>&1; then
        echo "[OK] Epiphany browser started (Wayland mode)"
      else
        echo "[WARN] Epiphany browser did not start in Wayland mode; check logs/browser.log"
      fi
    fi

  else
    # X11 mode (default or fallback)
    if [[ "$USE_WAYLAND_KIOSK" == "1" && "$WAYLAND_AVAILABLE" -eq 0 ]]; then
      echo "[WARN] USE_WAYLAND_KIOSK=1 but Wayland socket not found; falling back to X11 mode"
    fi
    echo "[INFO] Using X11 kiosk mode"

    activate_epiphany_fullscreen() {
      if ! command -v xdotool >/dev/null 2>&1; then
        echo "[WARN] xdotool is not installed; browser fullscreen step skipped"
        return 1
      fi

      local wid epiphany_pid
      wid=$(xdotool search --onlyvisible --class "epiphany" 2>/dev/null | head -1 || true)
      if [[ -z "$wid" ]]; then
        wid=$(xdotool search --class "epiphany" 2>/dev/null | head -1 || true)
      fi
      if [[ -z "$wid" ]]; then
        epiphany_pid=$(pgrep -n epiphany || true)
        if [[ -n "$epiphany_pid" ]]; then
          wid=$(xdotool search --pid "$epiphany_pid" 2>/dev/null | head -1 || true)
        fi
      fi
      if [[ -n "$wid" ]]; then
        xdotool windowactivate "$wid" 2>/dev/null || true
        sleep 0.5
        xdotool key F11 2>/dev/null || true
        echo "[OK] Browser fullscreen activated (window=$wid)"
        return 0
      fi

      echo "[WARN] Could not find browser window for fullscreen (DISPLAY=$DISPLAY, XAUTHORITY=${XAUTHORITY:-unset})"
      return 1
    }

    # Try fullscreen on existing process first
    fullscreen_done=0
    if pgrep -x epiphany >/dev/null 2>&1 || pgrep -x epiphany-browse >/dev/null 2>&1 || pgrep -af "epiphany.*browser" >/dev/null 2>&1; then
      echo "[INFO] Epiphany browser already running; trying fullscreen on current window"
      if activate_epiphany_fullscreen; then
        fullscreen_done=1
      fi
    else
      echo "[INFO] Launching Epiphany browser (fullscreen)..."
    fi

    # If fullscreen not done, launch with X11 fallback
    if [[ "$fullscreen_done" -eq 0 ]]; then
      echo "[INFO] Launching dedicated kiosk window via X11 fallback"
      GDK_BACKEND=x11 nohup epiphany-browser --private-instance --new-window "$BROWSER_URL" > logs/browser.log 2>&1 &
      sleep 4
      if activate_epiphany_fullscreen; then
        fullscreen_done=1
      fi
    fi
  fi
fi

echo "[DONE] Services startup routine finished."
