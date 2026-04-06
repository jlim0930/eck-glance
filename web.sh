#!/usr/bin/env bash
# web.sh - Launch the ECK Glance Web UI
# Usage: web.sh [OPTIONS] [path-to-eck-diagnostics]
#
# This script acts as the entry-point for the ECK Glance web interface.
# It validates prerequisites, resolves the diagnostic bundle path, manages
# port conflicts, starts the Python HTTP server (server.py) in the background,
# waits until the server is accepting connections, and then opens the browser.
# A trap ensures the server is cleanly shut down when the script exits.
#
# Options:
#   -p, --port PORT    Port number (default: 3333)
#   --no-open          Don't open browser automatically
#   -h, --help         Show this help

# ─── SHELL SAFETY FLAGS ───────────────────────────────────────────────────────
# -e  exit immediately if any command returns a non-zero status
# -u  treat unset variables as an error (prevents silent typo bugs)
# -o pipefail  if any command in a pipeline fails, the pipeline itself fails
set -euo pipefail

# ─── VARIABLE INITIALIZATION ──────────────────────────────────────────────────
# SCRIPT_DIR: resolved absolute path of this script's directory (eck-glance root).
# WEB_DIR:    directory containing the web backend/frontend assets.
# SERVER_SCRIPT: absolute path to the Python backend entry point.
# CONFIG_FILE: optional shell config loaded from the script directory.
# PORT:       server port; can be overridden via the PORT env variable or -p flag.
# NO_OPEN:    when true the browser is NOT launched automatically.
# DIAG_PATH:  optional path to an eck-diagnostics directory or zip supplied as a
#             positional argument; empty means the user will upload via the UI.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="${SCRIPT_DIR}/web"
SERVER_SCRIPT="${WEB_DIR}/server.py"
CONFIG_FILE="${SCRIPT_DIR}/config"
PORT="${PORT:-}"
NO_OPEN=false
DIAG_PATH=""

# Defaults overridden by config when present
DEFAULT_PORT="3333"
DEFAULT_THEME="light"
UPLOADS_DIR="/tmp/eck-glance-uploads"
GEMINI_API_KEY=""
SSL_CERT_FILE="${SSL_CERT_FILE:-}"

# Load optional user config from the same directory as web.sh
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# Normalize/validate values after config load
DEFAULT_PORT="${DEFAULT_PORT:-3333}"
DEFAULT_THEME="${DEFAULT_THEME:-light}"
UPLOADS_DIR="${UPLOADS_DIR:-/tmp/eck-glance-uploads}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
SSL_CERT_FILE="${SSL_CERT_FILE:-}"

# Resolve effective runtime port after loading config.
# Precedence: CLI -p/--port > env PORT > config DEFAULT_PORT.
PORT="${PORT:-${DEFAULT_PORT}}"

if [[ "${DEFAULT_THEME}" != "light" && "${DEFAULT_THEME}" != "dark" ]]; then
  echo "WARNING: DEFAULT_THEME must be 'light' or 'dark'; using 'light'."
  DEFAULT_THEME="light"
fi

# Export settings for server.py
export ECK_GLANCE_DEFAULT_THEME="${DEFAULT_THEME}"
export ECK_GLANCE_UPLOAD_DIR="${UPLOADS_DIR}"
export ECK_GLANCE_GEMINI_API_KEY="${GEMINI_API_KEY}"
if [[ -n "${SSL_CERT_FILE}" ]]; then
  export SSL_CERT_FILE
fi

# ─── ANSI COLOR CONSTANTS ─────────────────────────────────────────────────────
# These escape sequences are used with printf/echo -e to colorize terminal output.
# RED    – errors and fatal messages
# GREEN  – success / ready messages
# YELLOW – warnings (e.g. port already in use)
# CYAN   – informational highlights (URLs, process actions)
# BOLD   – emphasis in plain text (section headings in usage)
# RESET  – revert all attributes back to the terminal default
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── usage() ──────────────────────────────────────────────────────────────────
# Prints a formatted help message to stdout, then exits 0.
# Called when -h / --help is passed, or when no valid arguments are provided.
usage() {
  printf "%beck-glance web%b - ECK Diagnostics Web Viewer\n" "${BOLD}" "${RESET}"
  echo ""
  printf "%bUSAGE:%b\n" "${BOLD}" "${RESET}"
  echo "  web.sh [OPTIONS] [PATH]"
  echo ""
  printf "%bARGUMENTS:%b\n" "${BOLD}" "${RESET}"
  echo "  PATH    Path to eck-diagnostics directory or zip file"
  echo "          If not provided, you can upload via the web interface"
  echo ""
  printf "%bOPTIONS:%b\n" "${BOLD}" "${RESET}"
  echo "  -p, --port PORT    Server port (default: ${DEFAULT_PORT}, env: PORT)"
  echo "  --no-open          Don't auto-open browser"
  echo "  -h, --help         Show this help"
  echo ""
  printf "%bEXAMPLES:%b\n" "${BOLD}" "${RESET}"
  echo "  # Launch web UI (upload diagnostics via browser)"
  echo "  web.sh"
  echo ""
  echo "  # Launch with a specific diagnostic bundle"
  echo "  web.sh /path/to/eck-diagnostics"
  echo ""
  echo "  # Launch with a zip file"
  echo "  web.sh /path/to/eck-diagnostics.zip"
  echo ""
  echo "  # Custom port"
  echo "  web.sh -p 8080 /path/to/eck-diagnostics"
  echo ""
  printf "%bREQUIREMENTS:%b\n" "${BOLD}" "${RESET}"
  echo "  Python 3.6+ (no additional packages needed)"
  echo ""
  exit 0
}

# ─── ARGUMENT PARSING ─────────────────────────────────────────────────────────
# Walk through all positional parameters.  Named flags are consumed with `shift`
# (two shifts for flags that take a value like --port).  The first non-flag
# argument is treated as DIAG_PATH; a second non-flag argument is an error.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    -p|--port) PORT="$2"; shift 2 ;;
    --no-open) NO_OPEN=true; shift ;;
    -*)
      echo -e "${RED}ERROR: Unknown option: $1${RESET}"
      echo "Run 'web.sh --help' for usage."
      exit 1
      ;;
    *)
      if [[ -z "${DIAG_PATH}" ]]; then
        DIAG_PATH="$1"
      else
        echo -e "${RED}ERROR: Unexpected argument: $1${RESET}"
        exit 1
      fi
      shift
      ;;
  esac
done

# ─── PREREQUISITE CHECK: PYTHON 3 ─────────────────────────────────────────────
# server.py requires Python 3.6+ (uses f-strings and the built-in http.server
# module).  No third-party packages are needed, so a bare `python3` binary is
# sufficient.  We exit early with install instructions rather than letting a
# cryptic "command not found" error surface later.
# Check for Python 3
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: Python 3 is required but not found.${RESET}"
  echo ""
  echo "Install Python 3:"
  echo "  macOS:  brew install python3"
  echo "  Linux:  sudo apt install python3"
  exit 1
fi

if [[ ! -f "${SERVER_SCRIPT}" ]]; then
  echo -e "${RED}ERROR: Backend server not found at ${SERVER_SCRIPT}${RESET}"
  exit 1
fi

# ─── WORKING DIRECTORY ────────────────────────────────────────────────────────
# Change into the script root directory.  We invoke server.py by absolute path,
# so this keeps relative diagnostics-path handling predictable for the wrapper.
cd "${SCRIPT_DIR}"

# ─── DIAGNOSTIC PATH RESOLUTION ───────────────────────────────────────────────
# If the user supplied a path, canonicalize it to an absolute path before
# passing it to the server.  server.py receives relative paths as-is and later
# resolves them from its own CWD, which would be wrong after the `cd` above.
# A missing path is caught early to avoid a confusing server-side error.
EXTRA_ARGS=""
if [[ -n "${DIAG_PATH}" ]]; then
  # Convert a relative path to absolute by joining the directory's realpath
  # with the basename.  We avoid `realpath` for portability on older macOS.
  if [[ "${DIAG_PATH}" != /* ]]; then
    DIAG_PATH="$(cd "$(dirname "${DIAG_PATH}")" 2>/dev/null && pwd)/$(basename "${DIAG_PATH}")"
  fi
  if [[ ! -e "${DIAG_PATH}" ]]; then
    echo -e "${RED}ERROR: Path not found: ${DIAG_PATH}${RESET}"
    exit 1
  fi
  EXTRA_ARGS="${DIAG_PATH}"
fi

# ─── UPLOADS DIRECTORY ────────────────────────────────────────────────────────
# server.py stores bundles that are uploaded through the browser UI here.
# We create it proactively so the server never has to deal with a missing dir.
mkdir -p "${UPLOADS_DIR}"

# ─── port_in_use() ────────────────────────────────────────────────────────────
# Returns 0 (true) if something is already listening on the given TCP port.
# Arguments:
#   $1  port number to probe
# Detection strategy (in priority order):
#   1. lsof  – available on macOS and most Linux distros with lsof installed
#   2. ss    – preferred on modern Linux when lsof is absent
#   3. /dev/tcp bash built-in – last-resort fallback; works anywhere bash is used
port_in_use() {
  if command -v lsof &>/dev/null; then
    lsof -i :"$1" &>/dev/null
  elif command -v ss &>/dev/null; then
    ss -tlnp | grep -q ":$1 "
  else
    # Bash's /dev/tcp pseudo-device attempts a TCP connection; if it succeeds
    # the port is in use.  Suppress output and errors; rely on exit code only.
    (echo >/dev/tcp/localhost/"$1") 2>/dev/null
  fi
}

# ─── cleanup() ────────────────────────────────────────────────────────────────
# Signal handler registered via `trap` for EXIT, INT (Ctrl-C), TERM, and HUP.
# Responsibilities:
#   1. Preserve the original exit code so callers get the right status.
#   2. Send SIGTERM to the Python server for a graceful shutdown.
#   3. Poll up to 2 s (10 × 0.2 s) for the process to exit on its own.
#   4. Send SIGKILL if it is still running after the grace period.
#   5. Clean up any /tmp/eck-glance-*.tmp scratch files.
#
# Note: SERVER_PID may be unset if the server never started (e.g. Python was
# missing), so we guard with ${SERVER_PID:-} to avoid an -u flag error.
cleanup() {
  local exit_code=$?
  echo "" # newline after ^C
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "${CYAN}Shutting down ECK Glance server...${RESET}"
    # SIGTERM: ask the server to shut down cleanly (flushes open connections)
    kill "$SERVER_PID" 2>/dev/null || true
    # Poll until the process disappears or the grace period expires
    for i in $(seq 1 10); do
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    # Escalate to SIGKILL if SIGTERM was not enough (e.g. server ignores it)
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    echo -e "${GREEN}Server stopped.${RESET}"
  fi
  # Remove any scratch/temp files the server may have written
  rm -f /tmp/eck-glance-*.tmp 2>/dev/null || true
  exit "$exit_code"
}

# ─── PORT CONFLICT RESOLUTION ─────────────────────────────────────────────────
# Before starting the server, confirm the desired port is free.  When it is
# occupied we first try to identify the owning PID:
#   - If we can identify it, we send SIGTERM and wait 1 s before a SIGKILL,
#     on the assumption it is a stale eck-glance instance from a previous run.
#   - If we cannot identify the owner (e.g. the process is owned by another
#     user and lsof/ss require privileges), we refuse to proceed rather than
#     blindly killing an unknown process.
if port_in_use "${PORT}"; then
  echo -e "${YELLOW}Port ${PORT} is already in use.${RESET}"
  # Attempt to find the PID of the process using the port
  EXISTING_PID=""
  if command -v lsof &>/dev/null; then
    # -t outputs only the PID; -i filters by port
    EXISTING_PID=$(lsof -ti :"${PORT}" 2>/dev/null || true)
  elif command -v ss &>/dev/null; then
    # Extract pid= value from ss's process field (Linux-specific format)
    EXISTING_PID=$(ss -tlnp | grep ":${PORT} " | grep -oP 'pid=\K[0-9]+' || true)
  fi
  if [[ -n "${EXISTING_PID}" ]]; then
    echo -e "${YELLOW}Stopping existing process (PID: ${EXISTING_PID}) on port ${PORT}...${RESET}"
    kill "${EXISTING_PID}" 2>/dev/null || true
    sleep 1
    # Escalate to SIGKILL if the process is still alive after 1 s
    if kill -0 "${EXISTING_PID}" 2>/dev/null; then
      kill -9 "${EXISTING_PID}" 2>/dev/null || true
      sleep 0.5
    fi
    echo -e "${GREEN}Port ${PORT} is now free.${RESET}"
  else
    # Cannot identify the owner – refuse to continue to avoid breaking
    # unrelated services.  The user can free the port manually or pick another.
    echo -e "${RED}ERROR: Port ${PORT} is in use by an unknown process. Please free the port or use -p to specify a different port.${RESET}"
    exit 1
  fi
fi

# ─── SIGNAL TRAP ──────────────────────────────────────────────────────────────
# Register cleanup() BEFORE we fork the server process.  This ensures that even
# if the script is interrupted (Ctrl-C → INT) or the parent shell is asked to
# terminate (TERM/HUP) after the server is running, cleanup() will always have
# a valid SERVER_PID to target.
trap cleanup EXIT INT TERM HUP

# ─── SERVER LAUNCH ────────────────────────────────────────────────────────────
# Start web/server.py as a background job so we can poll for readiness and open
# the browser while it initialises.  $EXTRA_ARGS is intentionally unquoted
# here so it expands to either nothing or the single path argument.
python3 "${SERVER_SCRIPT}" --port "${PORT}" ${EXTRA_ARGS} &
SERVER_PID=$!  # capture PID immediately so cleanup() can target it

# ─── READINESS POLL & BROWSER LAUNCH ─────────────────────────────────────────
# Poll the server's root endpoint up to 50 times at 0.1 s intervals (5 s total).
# Once it responds with any HTTP status we consider it ready and open the browser.
# Between polls we also verify the server process is still alive; if it has
# already exited (crash at startup) we surface the error immediately rather than
# spinning out the full 5 s timeout.
#
# Browser opener:
#   `open`     – macOS default browser
#   `xdg-open` – Linux freedesktop-compliant launcher
# Failures in either are suppressed (|| true) because a missing opener should
# not abort the script – the user can copy the URL from the status message.
if [[ "${NO_OPEN}" != true ]]; then
  for i in $(seq 1 50); do
    if curl -s -o /dev/null "http://localhost:${PORT}/" 2>/dev/null; then
      # Server is accepting connections – open the browser
      if command -v open &>/dev/null; then
        open "http://localhost:${PORT}" 2>/dev/null || true
      elif command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:${PORT}" 2>/dev/null || true
      fi
      break
    fi
    # Server has not responded yet – make sure it is still running before
    # sleeping to avoid a pointless 5 s wait after a startup crash
    if ! kill -0 $SERVER_PID 2>/dev/null; then
      echo -e "${RED}ERROR: Server failed to start${RESET}"
      exit 1
    fi
    sleep 0.1
  done
fi

# ─── STATUS MESSAGE ───────────────────────────────────────────────────────────
# Print the server URL so the user can open it manually if the browser launcher
# was unavailable or --no-open was passed.
echo ""
echo -e "${GREEN}${BOLD}ECK Glance${RESET} is running at ${CYAN}http://localhost:${PORT}${RESET}"
echo -e "Press ${BOLD}Ctrl+C${RESET} to stop the server"
echo ""

# ─── FOREGROUND WAIT ──────────────────────────────────────────────────────────
# `wait` blocks until the server process exits on its own (e.g. an unhandled
# exception inside server.py).  When Ctrl-C is pressed, bash delivers SIGINT to
# both this script and the server; the trap fires cleanup(), which terminates
# the server and then calls `exit`, so `wait` is never reached in that path.
wait $SERVER_PID
