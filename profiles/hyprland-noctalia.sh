#!/bin/bash
# ==============================================================================
# profiles/hyprland-noctalia.sh - Perfil Hyprland com Noctalia Shell
# ==============================================================================

PROFILE_NAME="Hyprland (Noctalia)"
PROFILE_DESCRIPTION="Sessão Hyprland integrada com a suíte Noctalia Shell"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"

EXTRA_PACMAN_PACKAGES=(
  # Hyprland Core
  "hyprland"
  "uwsm"
  "xdg-desktop-portal"
  "xdg-desktop-portal-hyprland"
  "nwg-look"
  "wdisplays"
  "wlr-randr"
  "network-manager-applet"
  "networkmanager"
  "playerctl"
  "greetd-regreet"
  "satty"
  "grim"
  "slurp"
  "foot"

  # Input Method
  "fcitx5"
  "fcitx5-configtool"
  "fcitx5-gtk"
  "fcitx5-qt"
)

EXTRA_AUR_PACKAGES=(
  # Noctalia Suite
  "noctalia"
  "noctalia-shell"

  # Apps & Theming
  "helium-browser-bin"
  "qt5ct-kde"
  "qt6ct-kde"
  "nautilus-open-any-terminal-git"
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${DESKTOP_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${DESKTOP_AUR_PACKAGES[@]}" "${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "foot"
  "fish"
  "zed"
  "hyprland-noctalia"
  "noctalia-shell"
  "lazy-nvim"
  "tmux"
  "scripts"
)

HAS_GREETER="hyprland"
HAS_CHAOTIC_AUR=true
HAS_DESKTOP_MODULES=true
HAS_GAMING=true

profile_post_install() {
  setup_gsettings "footclient"
  setup_mime_associations "helium.desktop" "org.gnome.TextEditor.desktop" "org.gnome.Loupe.desktop"
}
