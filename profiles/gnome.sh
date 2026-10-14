#!/bin/bash
# ==============================================================================
# profiles/gnome.sh - Perfil GNOME Desktop
# ==============================================================================

PROFILE_NAME="GNOME"
PROFILE_DESCRIPTION="Ambiente Desktop GNOME com extensões, atalhos e tema Catppuccin"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"

EXTRA_PACMAN_PACKAGES=(
  # Rede
  "networkmanager"

  # Terminal & CLI específicos do GNOME
  "alacritty"
  "xdg-terminal-exec"
  "zellij"

  # Utilitários do desktop (atalhos do GNOME)
  "flameshot"

  # Fontes adicionais
  "ttf-meslo-nerd"
  "ttf-0xproto-nerd"
)

EXTRA_AUR_PACKAGES=(
  "brave-bin"
  "vicinae"   # launcher do atalho Super+Space
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${DESKTOP_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${DESKTOP_AUR_PACKAGES[@]}" "${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "alacritty"
  "fish"
  "zed"
  "astro-nvim"
  "scripts"
  "btop"
  "xdg-terminals"
)

HAS_GREETER=""
HAS_CHAOTIC_AUR=false
HAS_DESKTOP_MODULES=true
HAS_GAMING=false

profile_post_install() {
  # Gsettings padrão + associações MIME (como os perfis de WM fazem)
  setup_gsettings "xdg-terminal-exec"
  setup_mime_associations "brave-browser.desktop" "org.gnome.TextEditor.desktop" "org.gnome.Loupe.desktop"

  log_step "Executando scripts específicos de personalização do GNOME..."

  local gnome_scripts=(
    "$REPO_ROOT/config/gnome/set-terminal-default.sh"
    "$REPO_ROOT/config/gnome/set-gnome-settings.sh"
    "$REPO_ROOT/config/gnome/set-gnome-hotkeys.sh"
    "$REPO_ROOT/config/gnome/set-gnome-extensions.sh"
    "$REPO_ROOT/config/gnome/set-catppuccin-theme.sh"
    "$REPO_ROOT/config/gnome/set-dock.sh"
    "$REPO_ROOT/config/gnome/set-app-grid.sh"
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
