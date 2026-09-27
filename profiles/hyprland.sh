#!/bin/bash
# ==============================================================================
# profiles/hyprland.sh - Perfil Hyprland (Wayland)
# ==============================================================================

PROFILE_NAME="Hyprland"
PROFILE_DESCRIPTION="Sessão Wayland moderna com Hyprland, Waybar, Walker e Regreet"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"
source "$REPO_ROOT/profiles/wayland-wm.env"

EXTRA_PACMAN_PACKAGES=(
  # Hyprland Core
  "hyprland"
  "uwsm"
  "xdg-desktop-portal-hyprland"
  "hyprshot"
  "hyprsunset"
)

EXTRA_AUR_PACKAGES=(
  "ttf-ms-fonts"
  "sunsetr-bin"
)

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
  "zed"
  "hypr"
  "uwsm"
  "systemd-user"
  "swaync"
  "waybar-hyprland"
  "walker"
  "lazy-nvim"
  "tmux"
  "scripts"
  "btop"
  "xdg-terminals"
)

HAS_GREETER="hyprland"
HAS_CHAOTIC_AUR=true
HAS_DESKTOP_MODULES=true
HAS_GAMING=true

profile_post_install() {
  default_wayland_post_install
  setup_graphical_session_services \
    "waybar.service:waybar" \
    "swaync.service:swaync" \
    "foot-server.service:foot" \
    "walker.service:walker" \
    "nautilus.service:nautilus" \
    "flameshot.service:flameshot" \
    "polkit-gnome.service:/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" \
    "waypaper-restore.service:waypaper_rs"
}
