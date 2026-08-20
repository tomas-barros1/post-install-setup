#!/bin/bash
# ==============================================================================
# profiles/gnome.sh - Perfil GNOME Desktop
# ==============================================================================

PROFILE_NAME="GNOME"
PROFILE_DESCRIPTION="Ambiente Desktop GNOME com extensões, atalhos e Alacritty"

# Carregar bases
source "$REPO_ROOT/profiles/base.env"
source "$REPO_ROOT/profiles/desktop.env"

EXTRA_PACMAN_PACKAGES=(
  # Terminal & CLI específicos do GNOME
  "alacritty"
  "zellij"

  # Fontes adicionais
  "ttf-meslo-nerd"
  "ttf-0xproto-nerd"
)

EXTRA_AUR_PACKAGES=(
  "brave-bin"
)

PACMAN_PACKAGES=("${BASE_PACMAN_PACKAGES[@]}" "${DESKTOP_PACMAN_PACKAGES[@]}" "${EXTRA_PACMAN_PACKAGES[@]}")
AUR_PACKAGES=("${DESKTOP_AUR_PACKAGES[@]}" "${EXTRA_AUR_PACKAGES[@]}")

DOTFILES_DIRS=(
  "alacritty"
  "fish"
  "nvim"
  "zed"
  "zellij"
  "astro-nvim"
  "scripts"
  "btop"
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
