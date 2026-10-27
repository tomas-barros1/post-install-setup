#!/bin/bash
# ==============================================================================
# profiles/wsl.sh - Perfil Arch Linux no WSL (Windows Subsystem for Linux)
# ==============================================================================

PROFILE_NAME="Arch WSL"
PROFILE_DESCRIPTION="Ambiente Arch WSL focado em desenvolvimento CLI (sem interface gráfica)"

# Carregar base CLI
source "$REPO_ROOT/profiles/base.env"

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=(
  "${BASE_AUR_PACKAGES[@]}" # ai-memory-bin, rtk-bin
)

DOTFILES_DIRS=(
  "fish"
  "astro-nvim"
  "tmux"
  "scripts"
  "btop"
)

HAS_GREETER=""
HAS_CHAOTIC_AUR=false
HAS_DESKTOP_MODULES=false
HAS_GAMING=false

profile_post_install() {
  log_step "Configurando /etc/wsl.conf..."

  local wsl_conf="/etc/wsl.conf"
  if [[ ! -f "$wsl_conf" ]]; then
    cat <<EOF | sudo tee "$wsl_conf" >/dev/null
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=false

[user]
default=${USER}
EOF
    log_info "  ✓ /etc/wsl.conf criado (systemd=true, user=$USER)"
  else
    log_info "  ✓ /etc/wsl.conf já existente"
  fi

  log_info "Perfil WSL configurado para desenvolvimento!"
  log_warn "Execute 'wsl --shutdown' no PowerShell e reabra o WSL para aplicar o /etc/wsl.conf"
}
