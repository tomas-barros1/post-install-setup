#!/bin/bash
# ==============================================================================
# ai-agents-refresh - Integra ai-memory + RTK aos agentes de IA instalados
# ==============================================================================
# Template instalado em /usr/local/bin/ai-agents-refresh. O placeholder
# @TARGET_USER@ é substituído pelo usuário que rodou o post-install-setup.
# Roda como root (hooks do pacman) e delega o que mexe em $HOME ao usuário.
#
# Modos:
#   (sem argumento)  detecta os agentes e (re)integra ai-memory e RTK. É o mesmo
#                    caminho usado pelo install.sh e pelos hooks (idempotente).
#   --restart        antes, reinicia o serviço do ai-memory (binário novo)
#   --schedule       PostTransaction do pacman: lê os pacotes do stdin e agenda
#                    o refresh para daqui a alguns segundos
#   --backup         PreTransaction do pacman: backup do ai-memory antes de
#                    atualizar (as migrações do banco são só para frente)
#
# Por que NÃO é preciso refresh a cada upgrade de agente/RTK: os hooks gravados
# são comandos nativos (`rtk hook claude`, `ai-memory hook --event ...`) que
# chamam o binário instalado; atualizar o binário já basta. O refresh só importa
# quando (a) o ai-memory é atualizado (reiniciar o serviço e re-staging dos
# scripts/plugins), (b) um agente novo é instalado ou (c) o OpenCode muda de
# versão (o ai-memory escolhe o plugin V1/V2 na hora do setup).
# ==============================================================================

set -uo pipefail
# -e omitido de propósito: falha de um agente não deve impedir os demais.

TARGET_USER="@TARGET_USER@"
LOG_FILE="/var/log/ai-agents-refresh.log"
LOCK_FILE="/run/lock/ai-agents-refresh.lock"
AI_MEMORY_URL="${AI_MEMORY_URL:-http://127.0.0.1:49374}"
BACKUP_KEEP=5
MODE="run"
RESTART=false

usage() {
  echo "uso: ai-agents-refresh [--restart] | --schedule | --backup" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --schedule) MODE="schedule" ;;
    --backup) MODE="backup" ;;
    --restart) RESTART=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

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

# Hooks do pacman e systemd-run começam em CWD=/. O self-check do `ai-memory setup`
# deriva o projeto do diretório atual, então rode a partir da home.
cd "$TARGET_HOME" || {
  echo "ai-agents-refresh: não foi possível entrar em '$TARGET_HOME'" >&2
  exit 1
}

mkdir -p "$(dirname "$LOCK_FILE")"
touch "$LOG_FILE"
chmod 0644 "$LOG_FILE"

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE"
  if [[ -t 1 || -n "${AI_AGENTS_REFRESH_VERBOSE:-}" ]]; then
    printf '%s\n' "$*"
  fi
}

run_as_user() {
  runuser -u "$TARGET_USER" -- env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    SHELL="$TARGET_SHELL" \
    XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
    PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.opencode/bin:$TARGET_HOME/.bun/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.npm-global/bin:$TARGET_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" \
    "$@"
}

user_has() {
  # shellcheck disable=SC2016
  run_as_user sh -c 'command -v "$1" >/dev/null 2>&1' sh "$1"
}

# ------------------------------------------------------------------------------
# --backup (PreTransaction)
# ------------------------------------------------------------------------------
if [[ "$MODE" == "backup" ]]; then
  data_dir="$TARGET_HOME/.local/share/ai-memory"
  dest_dir="$TARGET_HOME/.local/share/ai-memory-backups"

  if [[ ! -d "$data_dir" ]] || ! user_has ai-memory; then
    log "backup: ai-memory ainda sem dados; nada a fazer"
    exit 0
  fi

  run_as_user mkdir -p "$dest_dir"
  dest="$dest_dir/pre-upgrade-$(date +%Y%m%d-%H%M%S).tar.gz"
  # `ai-memory backup` pede o snapshot ao servidor em execução
  if run_as_user ai-memory backup --to "$dest" >>"$LOG_FILE" 2>&1; then
    log "backup: $dest"
  elif ! run_as_user curl -fsS --max-time 2 "$AI_MEMORY_URL/healthz" >/dev/null 2>&1; then
    # Servidor parado: copiar os arquivos é seguro
    if run_as_user tar -C "$data_dir" -czf "$dest" db wiki config.toml >>"$LOG_FILE" 2>&1; then
      log "backup (servidor parado, cópia direta): $dest"
    else
      log "backup: FALHOU (a atualização segue normalmente)"
    fi
  else
    log "backup: FALHOU com o servidor no ar (a atualização segue normalmente)"
  fi

  # Mantém só os N backups mais recentes
  # shellcheck disable=SC2016
  run_as_user sh -c 'ls -1t "$1"/pre-upgrade-*.tar.gz 2>/dev/null | tail -n +"$2" | xargs -r rm -f --' \
    sh "$dest_dir" "$((BACKUP_KEEP + 1))"
  exit 0
fi

# ------------------------------------------------------------------------------
# --schedule (PostTransaction)
# ------------------------------------------------------------------------------
if [[ "$MODE" == "schedule" ]]; then
  # O pacman entrega os nomes dos pacotes da transação no stdin (NeedsTargets).
  # Só reinicia o serviço se o próprio ai-memory foi instalado/atualizado.
  while IFS= read -r target; do
    case "$target" in
      ai-memory | ai-memory-bin) RESTART=true ;;
    esac
  done

  delay="${AI_AGENTS_REFRESH_DELAY:-45}"
  [[ "$delay" =~ ^[0-9]+$ ]] || delay=45
  unit="ai-agents-refresh-$(date +%s%N)"
  args=()
  [[ "$RESTART" == "true" ]] && args+=(--restart)

  # Durante a transação o user manager pode estar recarregando; agendar para
  # depois evita que o self-check do `ai-memory setup` pegue o serviço fora do ar.
  if command -v systemd-run >/dev/null 2>&1 &&
    systemd-run --quiet --collect \
      --unit="$unit" \
      --description="ai-agents-refresh (pós-transação do pacman)" \
      --on-active="${delay}s" \
      --timer-property=AccuracySec=1s \
      /usr/local/bin/ai-agents-refresh "${args[@]}"; then
    log "refresh agendado para daqui a ${delay}s (unit $unit, restart=$RESTART)"
    exit 0
  fi
  log "não foi possível agendar o refresh; executando imediatamente"
fi

# ------------------------------------------------------------------------------
# Execução principal
# ------------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

FAILED=()
log "=== refresh iniciado (restart=$RESTART) ==="

wait_for_ai_memory() {
  local attempt
  for attempt in {1..30}; do
    if run_as_user curl -fsS --max-time 2 "$AI_MEMORY_URL/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Agentes instalados (mesma detecção para ai-memory e RTK)
HAS_CLAUDE=false HAS_CODEX=false HAS_CURSOR=false HAS_COPILOT=false
HAS_OPENCODE=false HAS_GEMINI=false HAS_AGY=false
if user_has claude || [[ -d "$TARGET_HOME/.claude" ]]; then HAS_CLAUDE=true; fi
if user_has codex; then HAS_CODEX=true; fi
if user_has cursor-agent || [[ -d "$TARGET_HOME/.cursor" ]]; then HAS_CURSOR=true; fi
if user_has copilot; then HAS_COPILOT=true; fi
if user_has opencode; then HAS_OPENCODE=true; fi
if user_has gemini; then HAS_GEMINI=true; fi
if user_has agy || [[ -d "$TARGET_HOME/.gemini/antigravity-cli" ]]; then HAS_AGY=true; fi

# --- ai-memory ----------------------------------------------------------------
if user_has ai-memory; then
  # Os hooks gravam o caminho ABSOLUTO do binário usado no setup.
  ai_path="$(run_as_user sh -c 'command -v ai-memory')"
  if [[ -x /usr/bin/ai-memory && "$ai_path" != "/usr/bin/ai-memory" ]]; then
    log "AVISO: ai-memory resolvido em $ai_path, mas o pacote está em /usr/bin/ai-memory; os hooks apontariam para a cópia errada"
  fi

  if [[ "$RESTART" == "true" ]]; then
    log "ai-memory: reiniciando o serviço (binário novo; migrações rodam no start)"
    run_as_user systemctl --user restart ai-memory.service >>"$LOG_FILE" 2>&1 || true
    wait_for_ai_memory || log "ai-memory: serviço não respondeu em 30s; seguindo mesmo assim"
  fi

  agent_args=()
  [[ "$HAS_CLAUDE" == "true" ]] && agent_args+=(--agent claude-code)
  [[ "$HAS_CODEX" == "true" ]] && agent_args+=(--agent codex)
  [[ "$HAS_CURSOR" == "true" ]] && agent_args+=(--agent cursor)
  [[ "$HAS_COPILOT" == "true" ]] && agent_args+=(--agent copilot-cli)
  [[ "$HAS_OPENCODE" == "true" ]] && agent_args+=(--agent open-code)
  [[ "$HAS_GEMINI" == "true" ]] && agent_args+=(--agent gemini-cli)
  [[ "$HAS_AGY" == "true" ]] && agent_args+=(--agent antigravity-cli)

  # O setup só autodetecta agentes que já têm histórico de sessões; por isso os
  # agentes são nomeados explicitamente. Idempotente.
  if run_as_user ai-memory setup --yes "${agent_args[@]}" >>"$LOG_FILE" 2>&1; then
    log "ai-memory: ok (${agent_args[*]:-autodetecção})"
  else
    log "ai-memory: setup FALHOU (veja $LOG_FILE)"
    FAILED+=(ai-memory)
  fi
else
  log "ai-memory não encontrado; ignorando"
fi

# --- RTK ----------------------------------------------------------------------
rtk_init() {
  local label="$1"
  shift
  if run_as_user rtk init -g "$@" >>"$LOG_FILE" 2>&1 </dev/null; then
    log "rtk: $label ok"
  else
    log "rtk: $label FALHOU"
    FAILED+=("rtk-$label")
  fi
}

if user_has rtk; then
  [[ "$HAS_CLAUDE" == "true" ]] && rtk_init claude --auto-patch --no-trust-filters
  # Obs.: --opencode também (re)escreve os arquivos do Claude Code (RTK.md, settings.json)
  [[ "$HAS_OPENCODE" == "true" ]] && rtk_init opencode --opencode --auto-patch --no-trust-filters
  [[ "$HAS_COPILOT" == "true" ]] && rtk_init copilot --copilot --auto-patch --no-trust-filters
  [[ "$HAS_GEMINI" == "true" ]] && rtk_init gemini --gemini --auto-patch --no-trust-filters
  [[ "$HAS_CURSOR" == "true" ]] && rtk_init cursor --agent cursor --auto-patch --no-trust-filters
  [[ "$HAS_AGY" == "true" ]] && rtk_init antigravity --agent antigravity --auto-patch --no-trust-filters

  if [[ "$HAS_CODEX" == "true" ]]; then
    # --codex não aceita --auto-patch (o rtk recusa); confirma o patch via stdin
    if printf 'y\ny\ny\n' | run_as_user rtk init -g --codex >>"$LOG_FILE" 2>&1; then
      log "rtk: codex ok"
    else
      log "rtk: codex FALHOU"
      FAILED+=(rtk-codex)
    fi
  fi
else
  log "rtk não encontrado; ignorando"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "=== refresh concluído com falhas: ${FAILED[*]} ==="
  exit 1
fi
log "=== refresh concluído ==="
