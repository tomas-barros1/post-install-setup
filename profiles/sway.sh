#!/bin/bash
# ==============================================================================
# profiles/sway.sh - Perfil Sway (Wayland i3-compatible)
# ==============================================================================

PROFILE_NAME="Sway"
PROFILE_DESCRIPTION="Sessão Wayland com Sway, Waybar, Walker e Regreet"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"

EXTRA_PACMAN_PACKAGES=(
  # Sway Core
  "sway"
  "xdg-desktop-portal"
  "xdg-desktop-portal-wlr"
  "swaybg"
  "flameshot"
  "swaync"
  "waybar"
  "nwg-look"
  "wdisplays"
  "wlr-randr"
  "network-manager-applet"
  "networkmanager"
  "playerctl"
  "greetd-regreet"
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
  "helium-browser-bin"
  "qt6ct-kde"
  "walker-bin"
  "elephant-bin"
  "elephant-clipboard-bin"
  "elephant-desktopapplications-bin"
  "elephant-providerlist-bin"
  "elephant-runner-bin"
  "elephant-archlinuxpkgs-bin"
  "elephant-calc-bin"
  "elephant-symbols-bin"
  "elephant-todo-bin"
  "elephant-websearch-bin"
  "qt5ct-kde"
  "polkit-gnome-git"
  "waybar-weather"
  "nautilus-open-any-terminal-git"
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${DESKTOP_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${DESKTOP_AUR_PACKAGES[@]}" "${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "foot"
  "fish"
  "nvim"
  "zed"
  "sway"
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
  setup_gsettings "footclient"
  setup_mime_associations "helium.desktop" "org.gnome.TextEditor.desktop" "org.gnome.Loupe.desktop"
}
