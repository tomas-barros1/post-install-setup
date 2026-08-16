#!/bin/bash
# ==============================================================================
# install.sh - Pós-Instalação Arch Linux 100% Interativo com Gum
# ==============================================================================

set -euo pipefail

VERSION="3.0.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$HOME/post-install-$(date +%Y%m%d-%H%M%S).log"

# Carregar módulos da biblioteca
source "$REPO_ROOT/lib/log.sh"
source "$REPO_ROOT/lib/checks.sh"
source "$REPO_ROOT/lib/packages.sh"
source "$REPO_ROOT/lib/system.sh"

select_profile_interactive() {
  log_banner "🚀 POST-INSTALL ARCH LINUX v$VERSION"

  local options=(
    "hyprland           -> Hyprland + Waybar + Walker + Regreet"
    "hyprland-noctalia  -> Hyprland com a suíte Noctalia Shell"
    "gnome              -> GNOME Desktop com extensões e atalhos"
    "sway               -> Sway Wayland i3-compatible"
    "wsl                -> Arch WSL (Desenvolvimento CLI)"
  )

  local choice
  if command -v gum &>/dev/null; then
    choice=$(printf '%s\n' "${options[@]}" | gum choose --header "Selecione o ambiente que deseja instalar:")
    SELECTED_PROFILE=$(echo "$choice" | awk '{print $1}')
  else
    echo "Selecione o ambiente que deseja instalar:"
    PS3="Digite o número da opção: "
    select opt in "hyprland" "hyprland-noctalia" "gnome" "sway" "wsl" "Sair"; do
      case "$opt" in
        "hyprland"|"hyprland-noctalia"|"gnome"|"sway"|"wsl")
          SELECTED_PROFILE="$opt"
          break
          ;;
        "Sair")
          exit 0
          ;;
        *)
          echo "Opção inválida."
          ;;
      esac
    done
  fi
}

main() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo "Post-Install Arch Linux v$VERSION - $(date)" >"$LOGFILE"

  # 1. Validações iniciais e garantia do Gum
  check_arch_linux
  check_not_root
  check_pre_dependencies
  ensure_gum

  # 2. Seleção interativa do perfil
  SELECTED_PROFILE=""
  select_profile_interactive

  if [[ -z "$SELECTED_PROFILE" ]]; then
    log_error "Nenhum perfil selecionado. Abortando."
    exit 1
  fi

  SELECTED_PROFILE="$(echo "$SELECTED_PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  local profile_file="$REPO_ROOT/profiles/$SELECTED_PROFILE.sh"

  if [[ ! -f "$profile_file" ]]; then
    log_error "Arquivo de perfil não encontrado: $profile_file"
    exit 1
  fi

  # Carregar perfil selecionado
  source "$profile_file"

  # 3. Perguntas interativas opcionais com Gum
  local enable_chaotic=false
  if [[ "${HAS_CHAOTIC_AUR:-false}" == "true" ]]; then
    if command -v gum &>/dev/null; then
      if gum confirm "Deseja habilitar o repositório Chaotic AUR (binários pré-compilados do AUR)?"; then
        enable_chaotic=true
      fi
    else
      enable_chaotic=true
    fi
  fi

  local enable_gaming=false
  if [[ "${HAS_GAMING:-false}" == "true" ]]; then
    if command -v gum &>/dev/null; then
      if gum confirm "Deseja instalar o setup de Jogos (Steam, Lutris, GameMode, LACT, GOverlay)?"; then
        enable_gaming=true
      fi
    fi
  fi

  local configure_git=true
  if command -v gum &>/dev/null; then
    if ! gum confirm "Deseja configurar o seu perfil do Git (Nome, Email e Pager)?"; then
      configure_git=false
    fi
  fi

  # 4. Confirmação para início
  if command -v gum &>/dev/null; then
    gum style \
      --border normal \
      --margin "1 0" \
      --padding "1 2" \
      --border-foreground 39 \
      "Perfil: $PROFILE_NAME" \
      "Descrição: $PROFILE_DESCRIPTION" \
      "Chaotic AUR: $([[ "$enable_chaotic" == "true" ]] && echo "Sim" || echo "Não")" \
      "Setup Gaming: $([[ "$enable_gaming" == "true" ]] && echo "Sim" || echo "Não")" \
      "Configurar Git: $([[ "$configure_git" == "true" ]] && echo "Sim" || echo "Não")" \
      "Log: $LOGFILE"

    if ! gum confirm "Iniciar a instalação agora?"; then
      log_warn "Instalação cancelada pelo usuário."
      exit 0
    fi
  fi

  log_banner "Executando: $PROFILE_NAME"

  # 5. Pacotes oficiais (Pacman)
  install_pacman_packages "${PACMAN_PACKAGES[@]}"

  # 6. AUR Helper (yay)
  install_yay

  # 7. Chaotic AUR
  if [[ "$enable_chaotic" == "true" ]]; then
    setup_chaotic_aur
  fi

  # 8. Pacotes do AUR
  if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    install_aur_packages "${AUR_PACKAGES[@]}"
  fi

  # 9. Dotfiles
  if [[ ${#DOTFILES_DIRS[@]} -gt 0 ]]; then
    setup_dotfiles "${DOTFILES_DIRS[@]}"
  fi

  # 10. Serviços base
  setup_docker
  setup_fish_shell
  setup_tpm

  # 11. Firewall
  if [[ "${HAS_DESKTOP_MODULES:-false}" == "true" ]]; then
    setup_firewall
  fi

  # 12. Git
  if [[ "$configure_git" == "true" ]]; then
    setup_git
  fi

  # 13. Greeter
  if [[ -n "${HAS_GREETER:-}" ]]; then
    setup_greeter "$HAS_GREETER"
  fi

  # 14. Gaming
  if [[ "$enable_gaming" == "true" ]]; then
    log_step "Instalando ferramentas e pacotes de gaming..."
    if ! sudo pacman -S --noconfirm --needed gamemode lact 2>/dev/null; then
      log_warn "Falha ao instalar gamemode / lact via pacman"
      FAILED_STEPS+=("gaming:gamemode-lact")
    fi

    if command -v yay &>/dev/null; then
      yay -S --noconfirm --needed steam-devices-git 2>/dev/null || FAILED_STEPS+=("gaming:steam-devices")
    fi

    if command -v flatpak &>/dev/null; then
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
      flatpak install -y flathub com.valvesoftware.Steam 2>/dev/null || FAILED_STEPS+=("gaming:steam-flatpak")
      flatpak install -y flathub io.github.benjamimgois.goverlay 2>/dev/null || FAILED_STEPS+=("gaming:goverlay")
      flatpak install -y flathub net.lutris.Lutris 2>/dev/null || FAILED_STEPS+=("gaming:lutris")
      flatpak install -y flathub net.davidotek.pupgui2 2>/dev/null || FAILED_STEPS+=("gaming:pupgui2")
    fi
    log_info "Setup de gaming concluído!"
  fi

  # 15. Pós-instalação específica do perfil
  if declare -f profile_post_install >/dev/null; then
    profile_post_install
  fi

  # 16. Limpeza
  cleanup_yay

  # 17. Resumo final
  print_summary "$PROFILE_NAME"
}

main "$@"
