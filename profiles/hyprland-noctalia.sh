#!/bin/bash
# ==============================================================================
# profiles/hyprland-noctalia.sh - Perfil Hyprland com Noctalia Shell
# ==============================================================================

PROFILE_NAME="Hyprland (Noctalia)"
PROFILE_DESCRIPTION="Sessão Hyprland integrada com a suíte Noctalia Shell"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"
source "$REPO_ROOT/profiles/wayland-wm.env"

EXTRA_PACMAN_PACKAGES=(
  # Hyprland & Noctalia Core
  "hyprland"
  "uwsm"
  "xdg-desktop-portal-hyprland"
  "satty"
  "noctalia"
)

EXTRA_AUR_PACKAGES=(
  "noctalia-shell"
)

PACMAN_PACKAGES=(
  "${BASE_PACMAN_PACKAGES[@]}"
  "${DESKTOP_PACMAN_PACKAGES[@]}"
  "${WAYLAND_WM_PACMAN_PACKAGES[@]}"
  "${EXTRA_PACMAN_PACKAGES[@]}"
)

AUR_PACKAGES=(
  "${DESKTOP_AUR_PACKAGES[@]}"
  "${WAYLAND_WM_AUR_PACKAGES[@]}"
  "${EXTRA_AUR_PACKAGES[@]}"
)

DOTFILES_DIRS=(
  "foot"
  "fish"
  "zed"
  "hyprland-noctalia"
  "noctalia-shell"
  "uwsm"
  "lazy-nvim"
  "tmux"
  "scripts"
)

HAS_GREETER="hyprland"
HAS_CHAOTIC_AUR=true
HAS_DESKTOP_MODULES=true
HAS_GAMING=true

profile_post_install() {
  default_wayland_post_install
}
