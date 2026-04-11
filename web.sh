#!/usr/bin/env bash
# Launch the ECK Glance web UI.

# Shell safety
set -euo pipefail

# Paths and defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="${SCRIPT_DIR}/web"
SERVER_SCRIPT="${WEB_DIR}/server.py"
CONFIG_FILE="${SCRIPT_DIR}/config"
PORT="${PORT:-}"
NO_OPEN=false
DIAG_PATH=""

# Config defaults
DEFAULT_PORT="3333"
DEFAULT_THEME="light"
UPLOADS_DIR="/tmp/eck-glance-uploads"
GEMINI_API_KEY=""
GEMINI_REVIEW_PROMPT="${GEMINI_REVIEW_PROMPT:-}"
SSL_CERT_FILE="${SSL_CERT_FILE:-}"

# Load local config.
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# Normalize config values.
DEFAULT_PORT="${DEFAULT_PORT:-3333}"
DEFAULT_THEME="${DEFAULT_THEME:-light}"
UPLOADS_DIR="${UPLOADS_DIR:-/tmp/eck-glance-uploads}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
GEMINI_REVIEW_PROMPT="${GEMINI_REVIEW_PROMPT:-}"
SSL_CERT_FILE="${SSL_CERT_FILE:-}"

# Resolve the runtime port.
PORT="${PORT:-${DEFAULT_PORT}}"

if [[ "${DEFAULT_THEME}" != "light" && "${DEFAULT_THEME}" != "dark" ]]; then
  echo "WARNING: DEFAULT_THEME must be 'light' or 'dark'; using 'light'."
  DEFAULT_THEME="light"
fi

# Export backend settings.
export ECK_GLANCE_DEFAULT_THEME="${DEFAULT_THEME}"
export ECK_GLANCE_UPLOAD_DIR="${UPLOADS_DIR}"
export ECK_GLANCE_GEMINI_API_KEY="${GEMINI_API_KEY}"
if [[ -n "${GEMINI_REVIEW_PROMPT}" ]]; then
  export ECK_GLANCE_GEMINI_REVIEW_PROMPT="${GEMINI_REVIEW_PROMPT}"
fi
if [[ -n "${SSL_CERT_FILE}" ]]; then
  export SSL_CERT_FILE
fi

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

check_for_updates() {
  if ! git rev-parse --git-dir &>/dev/null; then
    return 0
  fi

  git fetch origin &>/dev/null || return 0

  local changed_files
  changed_files="$(git diff --name-only origin/main 2>/dev/null)"
  if [[ -n "${changed_files}" ]]; then
    echo -e "${YELLOW}Updates available for the following files:${RESET}"
    echo "${changed_files}"
    echo -e "${YELLOW}Please run ${BOLD}git pull${RESET}${YELLOW} to update.${RESET}"
    echo ""
  fi
}

# Help
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

# Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    -p|--port)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo -e "${RED}ERROR: --port requires a value.${RESET}"
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
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

if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo -e "${RED}ERROR: Port must be an integer between 1 and 65535.${RESET}"
  exit 1
fi

# Prerequisites
check_for_updates

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

# Use the project root as the working directory.
cd "${SCRIPT_DIR}"

# Resolve an optional diagnostics path.
if [[ -n "${DIAG_PATH}" ]]; then
  # Avoid realpath for older macOS shells.
  if [[ "${DIAG_PATH}" != /* ]]; then
    DIAG_PATH="$(cd "$(dirname "${DIAG_PATH}")" 2>/dev/null && pwd)/$(basename "${DIAG_PATH}")"
  fi
  if [[ ! -e "${DIAG_PATH}" ]]; then
    echo -e "${RED}ERROR: Path not found: ${DIAG_PATH}${RESET}"
    exit 1
  fi
fi

# Ensure the upload directory exists.
mkdir -p "${UPLOADS_DIR}"

# Port checks
port_in_use() {
  if command -v lsof &>/dev/null; then
    lsof -i :"$1" &>/dev/null
  elif command -v ss &>/dev/null; then
    ss -tlnp | grep -q ":$1 "
  else
    # Fall back to a TCP connect probe.
    (echo >/dev/tcp/localhost/"$1") 2>/dev/null
  fi
}

# Readiness checks
server_ready() {
  local port="$1"

  if command -v curl &>/dev/null; then
    curl -s -o /dev/null "http://localhost:${port}/" 2>/dev/null
  else
    (echo >/dev/tcp/127.0.0.1/"${port}") >/dev/null 2>&1
  fi
}

# Cleanup
cleanup() {
  local exit_code=$?
  echo ""
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "${CYAN}Shutting down ECK Glance server...${RESET}"
    # Stop the server cleanly first.
    kill "$SERVER_PID" 2>/dev/null || true
    # Wait briefly before forcing shutdown.
    for ((attempt=1; attempt<=10; attempt++)); do
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    # Force shutdown if needed.
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
    echo -e "${GREEN}Server stopped.${RESET}"
  fi
  # Remove scratch files.
  rm -f /tmp/eck-glance-*.tmp 2>/dev/null || true
  exit "$exit_code"
}

# Port conflicts
if port_in_use "${PORT}"; then
  echo -e "${YELLOW}Port ${PORT} is already in use.${RESET}"
  # Attempt to find the PID of the process using the port
  EXISTING_PID=""
  if command -v lsof &>/dev/null; then
    # lsof can return the owning PID directly.
    EXISTING_PID=$(lsof -ti :"${PORT}" 2>/dev/null || true)
  elif command -v ss &>/dev/null; then
    # Extract the PID from ss output.
    EXISTING_PID=$(ss -tlnp | grep ":${PORT} " | grep -oP 'pid=\K[0-9]+' || true)
  fi
  if [[ -n "${EXISTING_PID}" ]]; then
    echo -e "${YELLOW}Stopping existing process (PID: ${EXISTING_PID}) on port ${PORT}...${RESET}"
    kill "${EXISTING_PID}" 2>/dev/null || true
    sleep 1
    # Force shutdown if it stays alive.
    if kill -0 "${EXISTING_PID}" 2>/dev/null; then
      kill -9 "${EXISTING_PID}" 2>/dev/null || true
      sleep 0.5
    fi
    echo -e "${GREEN}Port ${PORT} is now free.${RESET}"
  else
    # Do not kill unknown processes.
    echo -e "${RED}ERROR: Port ${PORT} is in use by an unknown process. Please free the port or use -p to specify a different port.${RESET}"
    exit 1
  fi
fi

# Signals
trap cleanup EXIT INT TERM HUP

# Server launch
SERVER_CMD=(python3 "${SERVER_SCRIPT}" --port "${PORT}")
if [[ -n "${DIAG_PATH}" ]]; then
  SERVER_CMD+=("${DIAG_PATH}")
fi
"${SERVER_CMD[@]}" &
SERVER_PID=$!  # capture PID immediately so cleanup() can target it

# Readiness and browser launch
if [[ "${NO_OPEN}" != true ]]; then
  for ((attempt=1; attempt<=50; attempt++)); do
    if server_ready "${PORT}"; then
      # Open the browser when the server is ready.
      if command -v open &>/dev/null; then
        open "http://localhost:${PORT}" 2>/dev/null || true
      elif command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:${PORT}" 2>/dev/null || true
      fi
      break
    fi
    # Stop early if the server already exited.
    if ! kill -0 $SERVER_PID 2>/dev/null; then
      echo -e "${RED}ERROR: Server failed to start${RESET}"
      exit 1
    fi
    sleep 0.1
  done
fi

# Status
echo ""
echo -e "${GREEN}${BOLD}ECK Glance${RESET} is running at ${CYAN}http://localhost:${PORT}${RESET}"
echo -e "Press ${BOLD}Ctrl+C${RESET} to stop the server"
echo ""

# Wait for the server process.
wait $SERVER_PID
