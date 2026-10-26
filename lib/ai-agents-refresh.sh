#!/bin/bash
# ==============================================================================
# ai-agents-refresh - Atualiza integrações de agentes de IA após upgrades
# ==============================================================================
# Este arquivo é um template instalado em /usr/local/bin/ai-agents-refresh.
# O placeholder @TARGET_USER@ é substituído pelo usuário que rodou o
# post-install-setup. O script é executado como root por um hook do pacman e
# delega as alterações em $HOME ao usuário de destino.
# ==============================================================================

set -uo pipefail
# Nota: -e omitido intencionalmente — falhas individuais de agentes não devem
# abortar o refresh dos demais. Erros críticos têm '|| exit N' explícito.

TARGET_USER="@TARGET_USER@"
LOG_FILE="/var/log/ai-agents-refresh.log"
LOCK_FILE="/run/lock/ai-agents-refresh.lock"
MODE="${1:-}"

if [[ -n "$MODE" && "$MODE" != "--schedule" ]]; then
  echo "uso: ai-agents-refresh [--schedule]" >&2
  exit 2
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ai-agents-refresh precisa ser executado como root" >&2
  exit 1
fi

if ! id "$TARGET_USER" &>/dev/null; then
  echo "ai-agents-refresh: usuário '$TARGET_USER' não existe; nada a fazer" >&2
  exit 0
fi

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7)"

# O hook do pacman e o systemd-run começam em CWD=/. O self-check do
# `ai-memory setup` tenta derivar o projeto do diretório atual, então execute a
# partir da home do usuário.
cd "$TARGET_HOME" || {
  echo "ai-agents-refresh: não foi possível entrar em '$TARGET_HOME'" >&2
  exit 1
}

mkdir -p "$(dirname "$LOCK_FILE")"
touch "$LOG_FILE"
chmod 0644 "$LOG_FILE"

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE"
}

# O hook do pacman roda durante a transação, enquanto o user manager ainda pode
# estar recarregando. Agendar para depois evita que o self-check do
# `ai-memory setup` encontre o serviço temporariamente indisponível.
if [[ "$MODE" == "--schedule" ]]; then
  delay="${AI_AGENTS_REFRESH_DELAY:-45}"
  [[ "$delay" =~ ^[0-9]+$ ]] || delay=45
  unit="ai-agents-refresh-$(date +%s%N)"

  if command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --quiet --collect \
      --unit="$unit" \
      --description="ai-agents-refresh (pós-transação do pacman)" \
      --on-active="${delay}s" \
      --timer-property=AccuracySec=1s \
      /usr/local/bin/ai-agents-refresh; then
    log "refresh agendado para daqui a ${delay}s (unit $unit)"
    exit 0
  fi
  log "não foi possível agendar o refresh; executando imediatamente"
fi

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

log "=== refresh iniciado ==="

run_as_user() {
  runuser -u "$TARGET_USER" -- env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    SHELL="$TARGET_SHELL" \
    XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
    PATH="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

user_has() {
  # shellcheck disable=SC2016
  run_as_user sh -c 'command -v "$1" >/dev/null 2>&1' sh "$1"
}

wait_for_ai_memory() {
  local attempt
  for attempt in {1..30}; do
    if run_as_user curl -fsS --max-time 2 http://127.0.0.1:49374/healthz >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# --- ai-memory: atualiza hooks, MCP e skills dos agentes instalados ----------
if user_has ai-memory; then
  # O upgrade pode recarregar o user manager e deixar o serviço momentaneamente
  # indisponível. Reinicia com o binário novo e espera o /healthz responder.
  log "ai-memory: reiniciando serviço"
  run_as_user systemctl --user restart ai-memory.service >>"$LOG_FILE" 2>&1 || true
  if ! wait_for_ai_memory; then
    log "ai-memory: serviço não respondeu após o restart; seguindo mesmo assim"
  fi

  log "ai-memory: atualizando integrações detectadas"
  run_as_user ai-memory setup --yes >>"$LOG_FILE" 2>&1 || log "ai-memory setup falhou"

  # Cursor e Claude Code não são sempre autodetectados, mas podem ter config.
  if [[ -d "$TARGET_HOME/.cursor" ]]; then
    run_as_user ai-memory setup --yes --agent cursor >>"$LOG_FILE" 2>&1 || true
  fi
  if [[ -d "$TARGET_HOME/.claude" ]]; then
    run_as_user ai-memory setup --yes --agent claude-code >>"$LOG_FILE" 2>&1 || true
  fi
fi

# --- RTK: regenera hooks/plugins dos agentes instalados ----------------------
if user_has rtk; then
  log "rtk: reaplicando integrações"

  if user_has claude || [[ -d "$TARGET_HOME/.claude" ]]; then
    run_as_user rtk init -g --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has opencode; then
    run_as_user rtk init -g --opencode --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has codex; then
    # O modo --codex não aceita --auto-patch; confirma o patch via stdin.
    printf 'y\ny\ny\n' | run_as_user rtk init -g --codex >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has copilot; then
    run_as_user rtk init -g --copilot --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has cursor-agent || [[ -d "$TARGET_HOME/.cursor" ]]; then
    run_as_user rtk init -g --agent cursor --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has agy || [[ -d "$TARGET_HOME/.gemini/antigravity-cli" ]]; then
    run_as_user rtk init -g --agent antigravity --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
  if user_has gemini; then
    run_as_user rtk init -g --gemini --auto-patch --no-trust-filters >>"$LOG_FILE" 2>&1 || true
  fi
fi

log "=== refresh concluído ==="
