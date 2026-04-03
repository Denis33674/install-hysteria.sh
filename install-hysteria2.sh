#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Hysteria 2 one-click setup (Ubuntu/Debian)
# Self-signed certificate by server IP
# + QR code output for client URI
# ==========================================

# ---------------------------
# User-overridable variables
# ---------------------------
HY2_PORT="${HY2_PORT:-8443}"
CERT_DAYS="${CERT_DAYS:-3650}"
HY2_PASS="${HY2_PASS:-}"

CONFIG_DIR="/etc/hysteria"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"
CERT_KEY="${CONFIG_DIR}/server.key"
CERT_CRT="${CONFIG_DIR}/server.crt"
CLIENT_CONFIG_PATH="${CONFIG_DIR}/client-example.yaml"
QR_PNG_PATH="${CONFIG_DIR}/client-uri-qr.png"

SERVICE_NAME="hysteria-server.service"

# ---------------------------
# Helpers
# ---------------------------
log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
  printf '\n[%s] WARNING: %s\n' "$(date '+%F %T')" "$*" >&2
}

fail() {
  printf '\n[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
  exit 1
}

cleanup_on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo
    echo "========================================"
    echo "Installation failed"
    echo "========================================"
    echo
    echo "Useful diagnostics:"
    echo "systemctl status ${SERVICE_NAME} --no-pager -l"
    echo "journalctl -u ${SERVICE_NAME} -n 100 --no-pager -l"
    echo "ss -ulnp | grep ${HY2_PORT}"
    echo
  fi
}
trap cleanup_on_exit EXIT

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
}

require_apt_system() {
  command -v apt >/dev/null 2>&1 || fail "This script supports apt-based systems only."
  command -v systemctl >/dev/null 2>&1 || fail "systemd is required."
  [[ -f /etc/os-release ]] || fail "/etc/os-release not found."
}

check_os() {
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian)
      ;;
    *)
      warn "Detected OS: ${PRETTY_NAME:-unknown}. Script is intended for Ubuntu/Debian."
      ;;
  esac
}

validate_port() {
  [[ "${HY2_PORT}" =~ ^[0-9]+$ ]] || fail "HY2_PORT must be a number."
  (( HY2_PORT >= 1 && HY2_PORT <= 65535 )) || fail "HY2_PORT must be between 1 and 65535."
}

install_packages() {
  log "Installing required packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y curl openssl ca-certificates iproute2 ufw grep sed coreutils qrencode
}

install_hysteria() {
  log "Installing Hysteria 2..."
  HYSTERIA_USER=root bash <(curl -fsSL https://get.hy2.sh/)

  command -v hysteria >/dev/null 2>&1 || fail "hysteria binary not found after installation."
  systemctl list-unit-files | grep -q "^${SERVICE_NAME}" || fail "${SERVICE_NAME} not found after installation."
}

detect_server_ip() {
  log "Detecting public IPv4..."
  SERVER_IP="$(
    curl -4fsSL ifconfig.me 2>/dev/null ||
    curl -4fsSL api.ipify.org 2>/dev/null ||
    curl -4fsSL ipv4.icanhazip.com 2>/dev/null ||
    true
  )"

  [[ -n "${SERVER_IP}" ]] || fail "Could not detect public IPv4."
  [[ "${SERVER_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "Detected value does not look like IPv4: ${SERVER_IP}"
  export SERVER_IP
}

generate_password() {
  log "Preparing auth password..."
  if [[ -z "${HY2_PASS}" ]]; then
    HY2_PASS="$(openssl rand -hex 16)"
  fi
  export HY2_PASS
}

prepare_dirs() {
  log "Preparing directories..."
  mkdir -p "${CONFIG_DIR}"
  chmod 700 "${CONFIG_DIR}"
}

generate_certificate() {
  log "Generating self-signed certificate for IP ${SERVER_IP}..."
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${CERT_KEY}" \
    -out "${CERT_CRT}" \
    -days "${CERT_DAYS}" \
    -subj "/CN=${SERVER_IP}" \
    -addext "subjectAltName = IP:${SERVER_IP}"

  chmod 600 "${CERT_KEY}"
  chmod 644 "${CERT_CRT}"
}

write_server_config() {
  log "Writing server config..."
  cat > "${CONFIG_PATH}" <<EOF
listen: :${HY2_PORT}

tls:
  cert: ${CERT_CRT}
  key: ${CERT_KEY}

auth:
  type: password
  password: ${HY2_PASS}
EOF

  chmod 600 "${CONFIG_PATH}"
}

validate_server_config() {
  log "Validating server config..."
  hysteria server -c "${CONFIG_PATH}" >/dev/null 2>&1 || fail "Server config validation failed."
}

configure_firewall() {
  log "Configuring UFW rule for UDP ${HY2_PORT}..."
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${HY2_PORT}/udp" >/dev/null 2>&1 || true

    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      log "UFW is active. UDP ${HY2_PORT} allowed."
    else
      warn "UFW is installed but inactive. Local UFW is not blocking, but provider firewall may still block UDP ${HY2_PORT}."
    fi
  fi
}

start_service() {
  log "Starting Hysteria service..."
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"
}

validate_service() {
  log "Checking service state..."
  systemctl is-active --quiet "${SERVICE_NAME}" || {
    journalctl -u "${SERVICE_NAME}" -n 100 --no-pager -l || true
    fail "${SERVICE_NAME} is not active."
  }

  ss -uln | grep -q ":${HY2_PORT}\b" || {
    journalctl -u "${SERVICE_NAME}" -n 100 --no-pager -l || true
    fail "UDP port ${HY2_PORT} is not listening."
  }
}

collect_fingerprint() {
  log "Collecting SHA-256 certificate fingerprint..."
  HY2_FINGERPRINT="$(openssl x509 -noout -fingerprint -sha256 -in "${CERT_CRT}" | cut -d= -f2)"
  [[ -n "${HY2_FINGERPRINT}" ]] || fail "Could not extract certificate fingerprint."
  export HY2_FINGERPRINT
}

write_client_example() {
  log "Writing client example config..."
  cat > "${CLIENT_CONFIG_PATH}" <<EOF
server: "${SERVER_IP}:${HY2_PORT}"
auth: "${HY2_PASS}"

tls:
  insecure: true
  pinSHA256: "${HY2_FINGERPRINT}"

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
EOF

  chmod 600 "${CLIENT_CONFIG_PATH}"
}

urlencode() {
  local s="${1}"
  local out=""
  local i c hex

  for ((i=0; i<${#s}; i++)); do
    c="${s:$i:1}"
    case "${c}" in
      [a-zA-Z0-9.~_-])
        out+="${c}"
        ;;
      *)
        printf -v hex '%%%02X' "'${c}"
        out+="${hex}"
        ;;
    esac
  done

  printf '%s' "${out}"
}

build_uri() {
  local encoded_auth
  encoded_auth="$(urlencode "${HY2_PASS}")"

  HY2_URI="hysteria2://${encoded_auth}@${SERVER_IP}:${HY2_PORT}/?insecure=1&pinSHA256=${HY2_FINGERPRINT}"
  export HY2_URI
}

generate_qr() {
  log "Generating QR code for client URI..."

  command -v qrencode >/dev/null 2>&1 || {
    warn "qrencode is not installed, skipping QR generation."
    return 0
  }

  # Save PNG copy
  qrencode -o "${QR_PNG_PATH}" -s 8 -m 2 "${HY2_URI}" || fail "Could not save QR PNG."
  chmod 644 "${QR_PNG_PATH}"

  # Print QR in terminal
  echo
  echo "========================================"
  echo "Scan this QR code in your client"
  echo "========================================"
  echo

  qrencode -t ansiutf8 "${HY2_URI}" || warn "Could not print terminal QR code."

  echo
  echo "========================================"
  echo
}

print_result() {
  cat <<EOF

========================================
Hysteria 2 server is ready
========================================

SERVER_IP=${SERVER_IP}
PORT=${HY2_PORT}
PASSWORD=${HY2_PASS}
FINGERPRINT=${HY2_FINGERPRINT}

Server config:
${CONFIG_PATH}

Client example config:
${CLIENT_CONFIG_PATH}

Client config example:
----------------------------------------
server: "${SERVER_IP}:${HY2_PORT}"
auth: "${HY2_PASS}"

tls:
  pinSHA256: "${HY2_FINGERPRINT}"

socks5:
  listen: 127.0.0.1:1080

http:
  listen: 127.0.0.1:8080
----------------------------------------

Hysteria URI:
${HY2_URI}

QR PNG:
${QR_PNG_PATH}

Useful commands:
systemctl status ${SERVICE_NAME} --no-pager -l
journalctl -u ${SERVICE_NAME} -n 100 --no-pager -l
ss -ulnp | grep ${HY2_PORT}
cat ${CLIENT_CONFIG_PATH}

Important:
1. This setup uses a self-signed certificate bound to the server IP.
2. If the client cannot connect, the most likely cause is blocked UDP ${HY2_PORT}
   in your VPS provider firewall / security group.
3. If you change the server certificate later, the fingerprint will also change.
4. If your client app does not support pinSHA256, use insecure mode only as a fallback.

EOF
}

main() {
  require_root
  require_apt_system
  check_os
  validate_port
  install_packages
  install_hysteria
  detect_server_ip
  generate_password
  prepare_dirs
  generate_certificate
  write_server_config
  validate_server_config
  configure_firewall
  start_service
  validate_service
  collect_fingerprint
  write_client_example
  build_uri
  generate_qr
  print_result
}

main "$@"
