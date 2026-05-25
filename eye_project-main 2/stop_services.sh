#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# stop_services.sh
# Unified shutdown script for eye_project services
#
# Automatically works on any platform (Jetson/RPi).
# Gracefully stops all services with timeout-based force kill.
#
# Usage:
#   ./stop_services.sh
###############################################################################

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "[INFO] Stopping all eye_project services..."

###############################################################################
# Service Shutdown Utility
###############################################################################

stop_by_pattern() {
  local name="$1"
  local pattern="$2"
  local timeout="${3:-10}"  # Allow custom timeout

  local pids
  pids=$(pgrep -f "$pattern" 2>/dev/null || true)

  if [[ -z "$pids" ]]; then
    echo "[OK] $name not running"
    return 0
  fi

  echo "[INFO] Stopping $name: $pids"
  kill $pids 2>/dev/null || true

  # Wait for graceful shutdown (with timeout)
  for _ in $(seq 1 "$timeout"); do
    sleep 1
    if ! pgrep -f "$pattern" >/dev/null 2>/dev/null; then
      echo "[OK] $name stopped gracefully"
      return 0
    fi
  done

  echo "[WARN] $name still running after ${timeout}s, forcing termination"
  pkill -9 -f "$pattern" 2>/dev/null || true

  # Final verification
  if pgrep -f "$pattern" >/dev/null 2>/dev/null; then
    echo "[ERROR] Failed to stop $name"
    return 1
  fi

  echo "[OK] $name force-stopped"
  return 0
}

###############################################################################
# Stop Services in Reverse Startup Order
###############################################################################

# 1. Stop browser first (most dispensable)
stop_by_pattern "epiphany browser" "epiphany|epiphany-browser|epiphany-browse" 5

# 2. Stop Kakao app
stop_by_pattern "kakao app" "python.*database/app.py" 10

# 3. Stop eye_server
stop_by_pattern "eye_server.py" "python.*eye_server.py" 10

# 4. Stop legacy server (if present)
stop_by_pattern "legacy server.py" "python.*[ /]server.py" 5

###############################################################################
# Verification
###############################################################################

echo ""
echo "[INFO] Verifying all services are stopped..."

# List any remaining processes that might be related
remaining=$(pgrep -f "python.*( )?(eye_server|database/app|server)" 2>/dev/null || true)
if [[ -n "$remaining" ]]; then
  echo "[WARN] Remaining processes:"
  echo "$remaining"
else
  echo "[OK] No remaining eye_project processes"
fi

echo "[DONE] Services stop routine finished."
