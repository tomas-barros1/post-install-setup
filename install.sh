#!/bin/bash
# ==============================================================================
# install.sh - Pós-Instalação Arch Linux (interativo com Gum ou não interativo)
# ==============================================================================

set -euo pipefail

VERSION="3.1.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${POST_INSTALL_LOGFILE:-$HOME/post-install-$(date +%Y%m%d-%H%M%S).log}"

# Opções de linha de comando (vazio = perguntar)
ASSUME_YES=false
DRY_RUN=false
SELECTED_PROFILE=""
OPT_CHAOTIC="" OPT_GAMING="" OPT_GIT="" OPT_MIRRORS="" OPT_AUTOLOGIN=""

# Carregar módulos da biblioteca
source "$REPO_ROOT/lib/log.sh"
source "$REPO_ROOT/lib/checks.sh"
source "$REPO_ROOT/lib/packages.sh"
source "$REPO_ROOT/lib/network.sh"
source "$REPO_ROOT/lib/system.sh"

usage() {
  cat <<USAGE
Post-Install Arch Linux v$VERSION

Uso: ./install.sh [opções]

Sem opções, o script é interativo (menus do gum).

Opções:
  -p, --profile NOME     hyprland | hyprland-noctalia | sway | wsl
  -y, --yes              Não pergunta nada; aceita os padrões (inclui gaming,
                         Chaotic AUR, mirrors e autologin). Exige --profile.
      --dry-run          Mostra o plano (perfil e pacotes) e sai sem alterar nada
      --[no-]chaotic     Habilita / não habilita o Chaotic AUR
      --[no-]gaming      Instala / não instala o setup de jogos
      --[no-]mirrors     Otimiza / não otimiza mirrors com reflector
      --[no-]autologin   Greeter com / sem login automático (initial_session)
      --[no-]git         Configura / não configura o Git
  -h, --help             Mostra esta ajuda

Variáveis de ambiente (opcionais):
  DOTFILES_REPO, DOTFILES_DIR       Repositório e pasta dos dotfiles
  POST_INSTALL_LOCALE               Padrão: pt_BR.UTF-8
  POST_INSTALL_TIMEZONE             Padrão: America/Sao_Paulo
  POST_INSTALL_REGDOM               Padrão: BR
  POST_INSTALL_MIRROR_COUNTRIES     Padrão: "Brazil,United States"
  POST_INSTALL_WIRED_NETWORKD=true  Habilita DHCP de cabo via systemd-networkd (iwd não faz)
  GIT_USER_NAME, GIT_USER_EMAIL     Configuração do Git sem perguntas
  POST_INSTALL_LOGFILE              Caminho do arquivo de log
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p | --profile)
        if [[ $# -lt 2 ]]; then
          echo "Faltou o nome do perfil após $1" >&2
          exit 2
        fi
        SELECTED_PROFILE="$2"
        shift 2
        ;;
      -y | --yes)
        ASSUME_YES=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --chaotic)
        OPT_CHAOTIC=true
        shift
        ;;
      --no-chaotic)
        OPT_CHAOTIC=false
        shift
        ;;
      --gaming)
        OPT_GAMING=true
        shift
        ;;
      --no-gaming)
        OPT_GAMING=false
        shift
        ;;
      --mirrors)
        OPT_MIRRORS=true
        shift
        ;;
      --no-mirrors)
        OPT_MIRRORS=false
        shift
        ;;
      --autologin)
        OPT_AUTOLOGIN=true
        shift
        ;;
      --no-autologin)
        OPT_AUTOLOGIN=false
        shift
        ;;
      --git)
        OPT_GIT=true
        shift
        ;;
      --no-git)
        OPT_GIT=false
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        echo "Opção desconhecida: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

# ask_yes_no PERGUNTA PADRÃO(true|false) [OVERRIDE]
# Retorna 0 para "sim". OVERRIDE (da linha de comando) tem prioridade; com --yes usa o padrão.
ask_yes_no() {
  local question="$1" default="${2:-true}" override="${3:-}"

  if [[ -n "$override" ]]; then
    [[ "$override" == "true" ]]
    return
  fi
  if [[ "$ASSUME_YES" == "true" ]]; then
    [[ "$default" == "true" ]]
    return
  fi

  if command -v gum &>/dev/null; then
    if [[ "$default" == "true" ]]; then
      gum confirm "$question"
    else
      gum confirm --default=false "$question"
    fi
    return
  fi

  local reply prompt="[S/n]"
  [[ "$default" == "false" ]] && prompt="[s/N]"
  read -r -p "$question $prompt " reply || reply=""
  case "${reply,,}" in
    s | sim | y | yes) return 0 ;;
    n | nao | não | no) return 1 ;;
    *) [[ "$default" == "true" ]] ;;
  esac
}

select_profile_interactive() {
  log_banner "🚀 POST-INSTALL ARCH LINUX v$VERSION"

  local options=(
    "hyprland           -> Hyprland + Waybar + Walker + Regreet"
    "hyprland-noctalia  -> Hyprland com a suíte Noctalia Shell"
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
    select opt in "hyprland" "hyprland-noctalia" "sway" "wsl" "Sair"; do
      case "$opt" in
        "hyprland" | "hyprland-noctalia" | "sway" | "wsl")
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

print_plan() {
  local yn_chaotic="$1" yn_gaming="$2" yn_git="$3" yn_mirrors="$4" yn_autologin="$5"
  echo ""
  echo "Perfil:            $PROFILE_NAME"
  echo "Descrição:         $PROFILE_DESCRIPTION"
  echo "Chaotic AUR:       $yn_chaotic"
  echo "Setup Gaming:      $yn_gaming"
  echo "Configurar Git:    $yn_git"
  echo "Otimizar mirrors:  $yn_mirrors"
  echo "Autologin greeter: $yn_autologin"
  echo "Log:               $LOGFILE"
  echo ""
  echo "Pacotes pacman (${#PACMAN_PACKAGES[@]}):"
  printf '  %s\n' "${PACMAN_PACKAGES[@]}"
  if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    echo "Pacotes AUR (${#AUR_PACKAGES[@]}):"
    printf '  %s\n' "${AUR_PACKAGES[@]}"
  fi
  if [[ ${#DOTFILES_DIRS[@]} -gt 0 ]]; then
    echo ""
    echo "Dotfiles (stow): ${DOTFILES_DIRS[*]}"
  fi
  echo ""
}

yn() { [[ "$1" == "true" ]] && echo "Sim" || echo "Não"; }

main() {
  parse_args "$@"

  mkdir -p "$(dirname "$LOGFILE")"
  echo "Post-Install Arch Linux v$VERSION - $(date)" >"$LOGFILE"

  # 1. Validações iniciais e garantia do Gum
  check_arch_linux
  check_not_root
  check_pre_dependencies
  check_connectivity
  check_disk_space
  if [[ "$ASSUME_YES" != "true" ]]; then
    ensure_gum
  fi

  # 2. Seleção do perfil (flag ou menu)
  if [[ -z "$SELECTED_PROFILE" ]]; then
    if [[ "$ASSUME_YES" == "true" ]]; then
      log_error "--yes exige --profile NOME."
      exit 2
    fi
    select_profile_interactive
  fi

  if [[ -z "$SELECTED_PROFILE" ]]; then
    log_error "Nenhum perfil selecionado. Abortando."
    exit 1
  fi

  SELECTED_PROFILE="$(echo "$SELECTED_PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  if [[ ! "$SELECTED_PROFILE" =~ ^[a-z0-9-]+$ ]]; then
    log_error "Nome de perfil inválido: $SELECTED_PROFILE"
    exit 2
  fi

  local profile_file="$REPO_ROOT/profiles/$SELECTED_PROFILE.sh"
  if [[ ! -f "$profile_file" ]]; then
    log_error "Arquivo de perfil não encontrado: $profile_file"
    exit 1
  fi

  # Carregar perfil selecionado
  source "$profile_file"

  # 3. Perguntas opcionais
  local enable_chaotic=false enable_gaming=false configure_git=false
  local enable_mirrors=false
  GREETER_AUTOLOGIN=false

  if [[ "${HAS_CHAOTIC_AUR:-false}" == "true" ]] &&
    ask_yes_no "Deseja habilitar o repositório Chaotic AUR (binários pré-compilados do AUR)?" true "$OPT_CHAOTIC"; then
    enable_chaotic=true
  fi

  if [[ "${HAS_GAMING:-false}" == "true" ]] &&
    ask_yes_no "Deseja instalar o setup de Jogos (Steam, driver Vulkan da sua GPU, Lutris, GameMode, GOverlay)?" true "$OPT_GAMING"; then
    enable_gaming=true
  fi

  if ask_yes_no "Deseja otimizar os mirrors do pacman com reflector?" true "$OPT_MIRRORS"; then
    enable_mirrors=true
  fi

  if [[ -n "$OPT_GIT" ]]; then
    [[ "$OPT_GIT" == "true" ]] && configure_git=true
  elif [[ "$ASSUME_YES" == "true" ]]; then
    # Sem perguntas: só configura se nome e email vierem do ambiente
    if [[ -n "${GIT_USER_NAME:-}" && -n "${GIT_USER_EMAIL:-}" ]]; then
      configure_git=true
    fi
  elif ask_yes_no "Deseja configurar o seu perfil do Git (Nome, Email e Pager)?" true; then
    configure_git=true
  fi

  if [[ -n "${HAS_GREETER:-}" ]] &&
    ask_yes_no "Login automático no greeter (sem senha)? Só recomendado com disco criptografado." true "$OPT_AUTOLOGIN"; then
    GREETER_AUTOLOGIN=true
  fi

  # 4. Plano / confirmação
  if [[ "$DRY_RUN" == "true" ]]; then
    log_banner "DRY-RUN: nada será alterado"
    print_plan "$(yn "$enable_chaotic")" "$(yn "$enable_gaming")" "$(yn "$configure_git")" \
      "$(yn "$enable_mirrors")" "$(yn "$GREETER_AUTOLOGIN")"
    exit 0
  fi

  if [[ "$ASSUME_YES" != "true" ]] && command -v gum &>/dev/null; then
    gum style \
      --border normal \
      --margin "1 0" \
      --padding "1 2" \
      --border-foreground 39 \
      "Perfil: $PROFILE_NAME" \
      "Descrição: $PROFILE_DESCRIPTION" \
      "Chaotic AUR: $(yn "$enable_chaotic")" \
      "Setup Gaming: $(yn "$enable_gaming")" \
      "Configurar Git: $(yn "$configure_git")" \
      "Otimizar mirrors: $(yn "$enable_mirrors")" \
      "Log: $LOGFILE"

    if ! gum confirm "Iniciar a instalação agora?"; then
      log_warn "Instalação cancelada pelo usuário."
      exit 0
    fi
  fi

  log_banner "Executando: $PROFILE_NAME"

  start_sudo_keepalive

  # Etapas não-críticas usam run_step: se falharem, são registradas em FAILED_STEPS
  # e o script segue. Só a atualização/instalação de pacotes oficiais aborta tudo.

  # 5. Locale e timezone (antes de tudo — xdg-user-dirs depende do locale)
  run_step locale setup_locale

  # 6. Ajustes de pacman/makepkg, mirrors e Chaotic AUR
  run_step pacman-conf setup_pacman_conf
  run_step makepkg-conf setup_makepkg_conf
  if [[ "$enable_mirrors" == "true" ]]; then
    run_step mirrors setup_mirrors
  fi
  if [[ "$enable_chaotic" == "true" ]]; then
    run_step chaotic-aur setup_chaotic_aur
  fi

  # 7. Pacotes oficiais (crítico: se falhar, abortamos)
  install_pacman_packages "${PACMAN_PACKAGES[@]}"

  # 8. AUR Helper (yay) e pacotes do AUR
  run_step yay install_yay
  if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    run_step aur-packages install_aur_packages "${AUR_PACKAGES[@]}"
  fi

  # 9. Dotfiles
  if [[ ${#DOTFILES_DIRS[@]} -gt 0 ]]; then
    run_step dotfiles setup_dotfiles "${DOTFILES_DIRS[@]}"
  fi

  # 10. Diretórios XDG + bookmarks do Nautilus (todos os perfis)
  run_step user-dirs setup_user_dirs

  # 11. Agentes de IA (ai-memory + RTK) e hook de refresh do pacman
  run_step ai-agents setup_ai_agents

  # 12. Higiene e manutenção do sistema
  run_step maintenance setup_maintenance

  # 13. Serviços base
  run_step docker setup_docker
  run_step fish setup_fish_shell
  run_step tpm setup_tpm

  # 14. Git
  if [[ "$configure_git" == "true" ]]; then
    run_step git setup_git
  fi

  # 15. Greeter
  if [[ -n "${HAS_GREETER:-}" ]]; then
    run_step greeter setup_greeter "$HAS_GREETER"
  fi

  # 16. Gaming
  if [[ "$enable_gaming" == "true" ]]; then
    run_step gaming setup_gaming
  fi

  # 17. Pós-instalação específica do perfil
  if declare -f profile_post_install >/dev/null; then
    run_step profile-post-install profile_post_install
  fi

  # 18. Rede, firewall, bluetooth e áudio — por ÚLTIMO, para que a troca de
  #     gerenciador de rede nunca interrompa downloads das etapas anteriores.
  if [[ "${HAS_DESKTOP_MODULES:-false}" == "true" ]]; then
    run_step bluetooth setup_bluetooth
    run_step audio setup_audio
    run_step firewall setup_firewall
    run_step network setup_network
  fi

  # 19. Limpeza
  run_step cleanup cleanup_yay

  # 20. Resumo final
  print_summary "$PROFILE_NAME"
}

main "$@"
