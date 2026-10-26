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

check_connectivity() {
  log_step "Verificando conectividade..."
  if ! curl -fsSI --max-time 10 https://archlinux.org >/dev/null 2>&1; then
    log_error "Sem conectividade com https://archlinux.org. Verifique a rede e tente novamente."
    exit 1
  fi
  log_info "Conectividade OK"
}

check_disk_space() {
  local required_gb=10
  local mount avail_gb
  log_step "Verificando espaço em disco..."

  for mount in / /var; do
    [[ -d "$mount" ]] || continue
    avail_gb=$(df -BG --output=avail "$mount" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [[ -n "$avail_gb" && "$avail_gb" -lt "$required_gb" ]]; then
      log_error "Espaço insuficiente em $mount: ${avail_gb}GB livres (mínimo ${required_gb}GB)."
      exit 1
    fi
  done

  log_info "Espaço em disco OK"
}

start_sudo_keepalive() {
  if ! sudo -v; then
    log_error "Não foi possível validar o sudo."
    exit 1
  fi

  (
    while true; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'stop_sudo_keepalive' EXIT
}

stop_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
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
