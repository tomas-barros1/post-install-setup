#!/bin/bash
# ==============================================================================
# lib/log.sh - Funções de Log, Cores e Relatório de Status
# ==============================================================================

# Cores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # Sem Cor

# Arrays globais para rastreamento de falhas
FAILED_PACKAGES=()
FAILED_STEPS=()

# Grava no arquivo de log (sem cores) — LOGFILE pode não existir em --help
_log_file() {
  printf '%s %s\n' "$(date +%H:%M:%S)" "$1" >>"${LOGFILE:-/dev/null}"
}

log_info() {
  echo -e "${GREEN}✔${NC} $1"
  _log_file "✔ $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  _log_file "⚠ $1"
}

log_error() {
  echo -e "${RED}✖${NC} $1" >&2
  _log_file "✖ $1"
}

log_step() {
  echo -e "${BLUE}➜${NC} $1"
  _log_file "➜ $1"
}

# Executa um comando mostrando a saída na tela E gravando no log.
# Preserva o código de saída do comando (não o do tee).
run_logged() {
  local -a st
  "$@" 2>&1 | tee -a "${LOGFILE:-/dev/null}" && st=("${PIPESTATUS[@]}") || st=("${PIPESTATUS[@]}")
  return "${st[0]}"
}

# Executa uma etapa não-crítica: se falhar, registra em FAILED_STEPS e segue em frente.
# (Sem isso, o `set -e` do install.sh derrubaria o script inteiro em qualquer falha.)
run_step() {
  local name="$1"
  shift
  local before=${#FAILED_STEPS[@]} rc=0
  "$@" || rc=$?
  if [[ $rc -ne 0 ]]; then
    log_warn "Etapa '$name' falhou (código $rc); continuando com as demais."
    # A própria função pode já ter registrado um motivo mais específico
    if [[ ${#FAILED_STEPS[@]} -eq $before ]]; then
      FAILED_STEPS+=("$name")
    fi
  fi
  return 0
}

log_banner() {
  local title="$1"
  if command -v gum &>/dev/null; then
    gum style \
      --border double \
      --margin "1 0" \
      --padding "0 2" \
      --border-foreground 212 \
      --foreground 212 \
      --bold \
      "$title"
  else
    echo -e "\n${MAGENTA}${BOLD}=====================================================${NC}"
    echo -e "${MAGENTA}${BOLD}  $title${NC}"
    echo -e "${MAGENTA}${BOLD}=====================================================${NC}\n"
  fi
}

print_summary() {
  local profile_name="${1:-Arch Linux}"
  echo ""
  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 || ${#FAILED_STEPS[@]} -gt 0 ]]; then
    log_warn "Instalação do perfil '$profile_name' concluída com avisos."
  else
    log_info "✨ Instalação do perfil '$profile_name' concluída com sucesso! ✨"
  fi

  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    log_warn "Pacotes que falharam (${#FAILED_PACKAGES[@]}):"
    for pkg in "${FAILED_PACKAGES[@]}"; do
      echo "  • $pkg"
    done
  fi

  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo ""
    log_warn "Etapas que falharam (${#FAILED_STEPS[@]}):"
    for step in "${FAILED_STEPS[@]}"; do
      echo "  • $step"
    done
  fi

  echo ""
  log_warn "Próximos passos recomendados:"
  echo "  1. Faça LOGOUT e LOGIN para aplicar as permissões de grupos (ex: docker)"
  echo "  2. Reinicie o terminal para ativar Fish shell e Mise"
  echo "  3. Execute 'mise doctor' para validar as runtimes instaladas"
  echo "  4. Se estiver usando tmux, pressione <prefix> + I para instalar plugins via TPM"
  if [[ "${HAS_DESKTOP_MODULES:-false}" == "true" ]]; then
    echo "  5. Rede: a troca NetworkManager -> iwd vale a partir do PRÓXIMO boot."
    echo "     Wi-Fi: conecte com 'impala' ou 'iwctl'. (iwd puro: cabo não é gerenciado.)"
  fi
  echo ""
  log_info "Log salvo em: $LOGFILE (inclui a saída do pacman/yay)"
  echo ""
}
