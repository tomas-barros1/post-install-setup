#!/bin/bash
# ==============================================================================
# lib/checks.sh - Validações de Sistema e Pré-requisitos
# ==============================================================================

check_arch_linux() {
  if [[ ! -f /etc/arch-release ]]; then
    log_error "Este script foi desenvolvido exclusivamente para Arch Linux (ou derivados)!"
    exit 1
  fi
}

check_not_root() {
  if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root ou com sudo diretamente."
    log_error "Execute como usuário normal (o script pedirá senha de sudo quando necessário)."
    exit 1
  fi
}

check_pre_dependencies() {
  local missing=()
  local required=("git" "curl")

  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Dependências essenciais ausentes: ${missing[*]}"
    echo ""
    echo "  Por favor, instale com:"
    echo "  sudo pacman -S ${missing[*]}"
    echo ""
    exit 1
  fi

  log_info "Dependências pré-instalação verificadas: git, curl"
}

ensure_gum() {
  if command -v gum &>/dev/null; then
    return 0
  fi

  log_step "Instalando 'gum' para suporte a menus e prompts interativos..."
  if sudo pacman -S --needed --noconfirm gum &>/dev/null; then
    log_info "'gum' instalado com sucesso!"
  else
    log_warn "Não foi possível instalar o 'gum' antecipadamente. Usando modo de texto padrão."
  fi
}
