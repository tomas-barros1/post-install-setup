#!/bin/bash
# ==============================================================================
# profiles/sway.sh - Perfil Sway (Wayland i3-compatible)
# ==============================================================================

PROFILE_NAME="Sway"
PROFILE_DESCRIPTION="Sessão Wayland com Sway, Waybar, Walker e Regreet"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"
source "$REPO_ROOT/profiles/wayland-wm.env"

EXTRA_PACMAN_PACKAGES=(
  # Sway Core
  "sway"
  "xdg-desktop-portal-wlr"
)

EXTRA_AUR_PACKAGES=()

PACMAN_PACKAGES=(
  "${BASE_PACMAN_PACKAGES[@]}"
  "${DESKTOP_PACMAN_PACKAGES[@]}"
  "${WAYLAND_WM_PACMAN_PACKAGES[@]}"
  "${WAYBAR_SWAYNC_PACMAN_PACKAGES[@]}"
  "${EXTRA_PACMAN_PACKAGES[@]}"
)

AUR_PACKAGES=(
  "${DESKTOP_AUR_PACKAGES[@]}"
  "${WAYLAND_WM_AUR_PACKAGES[@]}"
  "${WALKER_AUR_PACKAGES[@]}"
  "${WAYBAR_SWAYNC_AUR_PACKAGES[@]}"
  "${EXTRA_AUR_PACKAGES[@]}"
)

DOTFILES_DIRS=(
  "foot"
  "fish"
  "nvim"
  "zed"
  "sway"
  "uwsm"
  "swaync"
  "waybar-sway"
  "walker"
  "tmux"
  "scripts"
)

HAS_GREETER="sway"
HAS_CHAOTIC_AUR=true
HAS_DESKTOP_MODULES=true
HAS_GAMING=true

profile_post_install() {
  default_wayland_post_install
}
