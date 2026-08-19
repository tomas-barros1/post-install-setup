#!/bin/bash
# ==============================================================================
# profiles/hyprland.sh - Perfil Hyprland (Wayland)
# ==============================================================================

PROFILE_NAME="Hyprland"
PROFILE_DESCRIPTION="Sessão Wayland moderna com Hyprland, Waybar, Walker e Regreet"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"

EXTRA_PACMAN_PACKAGES=(
  # Hyprland e Wayland
  "hyprland"
  "uwsm"
  "xdg-desktop-portal"
  "xdg-desktop-portal-hyprland"
  "swaybg"
  "flameshot"
  "hyprshot"
  "hyprsunset"
  "swaync"
  "waybar"
  "nwg-look"
  "wdisplays"
  "wlr-randr"
  "network-manager-applet"
  "playerctl"
  "greetd-regreet"
  "foot"
  "fcitx5"
  "grim"
  "slurp"
)

EXTRA_AUR_PACKAGES=(
  "helium-browser-bin"
  "qt6ct-kde"
  "ttf-ms-fonts"
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
  "sunsetr-bin"
  "waybar-weather"
  "nautilus-open-any-terminal-git"
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${DESKTOP_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${DESKTOP_AUR_PACKAGES[@]}" "${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "foot"
  "fish"
  "zed"
  "hypr"
  "uwsm"
  "swaync"
  "waybar-hyprland"
  "walker"
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
