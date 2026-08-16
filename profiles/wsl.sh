#!/bin/bash
# ==============================================================================
# profiles/wsl.sh - Perfil Arch Linux no WSL (Windows Subsystem for Linux)
# ==============================================================================

PROFILE_NAME="Arch WSL"
PROFILE_DESCRIPTION="Ambiente Arch WSL focado em desenvolvimento CLI (sem interface gráfica)"

# Carregar base CLI
source "$REPO_ROOT/profiles/base.env"

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=()

DOTFILES_DIRS=(
  "fish"
  "lazy-nvim"
  "tmux"
  "scripts"
)

HAS_GREETER=""
HAS_CHAOTIC_AUR=false
HAS_DESKTOP_MODULES=false
HAS_GAMING=false

profile_post_install() {
  log_info "Perfil WSL configurado para desenvolvimento!"
}
