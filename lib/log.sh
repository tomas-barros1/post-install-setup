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

log_info() {
  echo -e "${GREEN}✔${NC} $1" | tee -a "$LOGFILE"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
  echo -e "${RED}✖${NC} $1" | tee -a "$LOGFILE"
}

log_step() {
  echo -e "${BLUE}➜${NC} $1" | tee -a "$LOGFILE"
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
  echo ""
  log_info "Log completo salvo em: $LOGFILE"
  echo ""
}
