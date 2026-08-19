#!/bin/bash
# ==============================================================================
# profiles/gnome.sh - Perfil GNOME Desktop
# ==============================================================================

PROFILE_NAME="GNOME"
PROFILE_DESCRIPTION="Ambiente Desktop GNOME com extensões, atalhos e Alacritty"

# Carregar base CLI
source "$REPO_ROOT/profiles/base.env"

EXTRA_PACMAN_PACKAGES=(
  # Tema de ícones
  "tela-circle-icon-theme-purple"

  # Terminal & CLI
  "alacritty"
  "zellij"

  # Fontes
  "ttf-cascadia-code-nerd"
  "ttf-meslo-nerd"
  "ttf-jetbrains-mono"
  "inter-font"
  "ttf-0xproto-nerd"
  "noto-fonts"

  # Aplicações
  "gimp"
  "gnome-calculator"
  "celluloid"
  "file-roller"
  "libreoffice-fresh"
  "qbittorrent"
  "flatpak"

  # Utilitários
  "networkmanager"
  "iwd"
  "wireless-regdb"
  "gnome-keyring"
  "libsecret"
  "wl-clipboard"
  "ufw"
  "ddcutil"
  "lxappearance"
  "ntfs-3g"
  "ntfsprogs"
  "qt5-wayland"
  "qt6-wayland"

  # Aplicações Oficiais
  "obsidian"
)

EXTRA_AUR_PACKAGES=(
  "brave-bin"
  "visual-studio-code-bin"
  "catppuccin-gtk-theme-mocha"
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "alacritty"
  "fish"
  "nvim"
  "zed"
  "zellij"
  "astro-nvim"
  "scripts"
)

HAS_GREETER=""
HAS_CHAOTIC_AUR=false
HAS_DESKTOP_MODULES=true
HAS_GAMING=false

profile_post_install() {
  log_step "Executando scripts específicos de personalização do GNOME..."

  local gnome_scripts=(
    "$REPO_ROOT/config/gnome/set-alacritty-default.sh"
    "$REPO_ROOT/config/gnome/set-gnome-settings.sh"
    "$REPO_ROOT/config/gnome/set-gnome-hotkeys.sh"
    "$REPO_ROOT/config/gnome/set-gnome-extensions.sh"
  )

  for script in "${gnome_scripts[@]}"; do
    if [[ -f "$script" ]]; then
      log_step "Rodando $(basename "$script")..."
      if ! bash "$script"; then
        log_warn "Aviso ao executar $(basename "$script")"
        FAILED_STEPS+=("gnome:$(basename "$script")")
      fi
    fi
  done
}
