#!/bin/bash

set -euo pipefail

VERSION="2.1.0"
LOGFILE="$HOME/post-install-$(date +%Y%m%d-%H%M%S).log"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
FAILED_PACKAGES=()
FAILED_STEPS=()

# =============================
# Cores para output
# =============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✔${NC} $1" | tee -a "$LOGFILE"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✖${NC} $1" | tee -a "$LOGFILE"; }
log_step() { echo -e "${BLUE}➜${NC} $1" | tee -a "$LOGFILE"; }

# =============================
# Pacotes para GNOME (baseado no script de Hyprland,
# removendo itens específicos de WM)
# =============================

PACMAN_PACKAGES=(
  # Desenvolvimento
  "git"
  "neovim"
  "python-pip"
  "docker"
  "docker-compose"

  # Tema de ícones
  "tela-circle-icon-theme-purple"

  # Terminal & CLI Tools
  "fish"
  "alacritty"
  "zellij"
  "stow"
  "fzf"
  "bat"
  "eza"
  "ripgrep"
  "fd"
  "btop"
  "zoxide"
  "starship"
  "lazygit"
  "lazydocker"

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
  "libreoffice-fresh"
  "qbittorrent"
  "flatpak"

  # Utilitários
  "wl-clipboard"
  "wget"
  "aria2"
  "curl"
  "unzip"
  "zip"
  "ufw"
  "ddcutil"
  "lxappearance"
  "ntfs-3g"
  "ntfsprogs"
  "qt5-wayland"
  "qt6-wayland"
)

AUR_PACKAGES=(
  "brave-bin"
  "catppuccin-gtk-theme-mocha"
  "obsidian"
  "visual-studio-code-bin"
)

DOTFILES_DIRS=(
  "alacritty"
  "fish"
  "nvim"
  "zed"
  "zellij"
  "astro-nvim"
  "scripts"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================
# Funções auxiliares
# =============================

install_pacman_packages() {
  log_step "Instalando pacotes oficiais (${#PACMAN_PACKAGES[@]} pacotes)..."

  sudo pacman -Syu --noconfirm

  if ! sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"; then
    log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
    for pkg in "${PACMAN_PACKAGES[@]}"; do
      if ! sudo pacman -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_PACKAGES+=("$pkg (pacman)")
      fi
    done
  fi

  log_info "Pacotes oficiais processados!"
}

install_yay() {
  if command -v yay &>/dev/null; then
    log_info "yay já instalado"
    return 0
  fi

  log_step "Instalando yay (AUR helper)..."
  local tmp_dir
  tmp_dir=$(mktemp -d)

  if ! sudo pacman -S --needed --noconfirm git base-devel; then
    log_warn "Falha ao instalar dependências de build do yay"
    FAILED_STEPS+=("yay:base-devel")
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! git clone https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay"; then
    log_warn "Falha ao clonar repositório do yay"
    FAILED_STEPS+=("yay:clone")
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! (cd "$tmp_dir/yay" && makepkg -si --noconfirm); then
    log_warn "Falha ao compilar/instalar yay"
    FAILED_STEPS+=("yay:makepkg")
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  log_info "yay instalado!"
}

install_aur_packages() {
  log_step "Instalando pacotes do AUR (${#AUR_PACKAGES[@]} pacotes)..."

  if ! yay -S --noconfirm --needed "${AUR_PACKAGES[@]}"; then
    log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
    for pkg in "${AUR_PACKAGES[@]}"; do
      if ! yay -S --noconfirm --needed "$pkg"; then
        log_warn "Falha ao instalar: $pkg"
        FAILED_PACKAGES+=("$pkg (aur)")
      fi
    done
  fi

  log_info "Pacotes AUR processados!"
}

setup_dotfiles() {
  local dotfiles_dir="$HOME/dotfiles"

  if [[ ! -d "$dotfiles_dir" ]]; then
    log_step "Clonando dotfiles..."
    if ! git clone https://github.com/tomas-barros1/dotfiles "$dotfiles_dir"; then
      log_warn "Falha ao clonar dotfiles"
      FAILED_STEPS+=("dotfiles:clone")
      return 1
    fi
  else
    log_step "Atualizando dotfiles..."
    if ! git -C "$dotfiles_dir" pull; then
      log_warn "Falha ao atualizar dotfiles"
      FAILED_STEPS+=("dotfiles:pull")
    fi
  fi

  mkdir -p "$HOME/.local"

  log_step "Aplicando stow nos dotfiles..."
  cd "$dotfiles_dir"

  for dir in "${DOTFILES_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      if stow -R "$dir" 2>/dev/null; then
        log_info "  ✓ $dir"
      else
        log_warn "  ✗ $dir (conflito ou erro)"
        FAILED_STEPS+=("stow:$dir")
      fi
    else
      log_warn "  Diretório $dir não encontrado em dotfiles"
    fi
  done

  if [[ -d "scripts" ]]; then
    if ! stow --adopt scripts/; then
      log_warn "  ✗ scripts (falha no stow --adopt)"
      FAILED_STEPS+=("stow:scripts")
    fi
  else
    log_warn "  Diretório scripts não encontrado em dotfiles"
  fi

  cd - >/dev/null
}

setup_mise() {
  if command -v mise &>/dev/null; then
    log_info "mise já instalado"
  else
    log_step "Instalando mise..."
    curl https://mise.run | sh
  fi

  local fish_config="$HOME/.config/fish/config.fish"
  mkdir -p "$(dirname "$fish_config")"

  if ! grep -q "mise activate fish" "$fish_config" 2>/dev/null; then
    echo -e '\n# Mise runtime manager\nmise activate fish | source' >>"$fish_config"
    log_info "Mise adicionado ao config.fish"
  fi

  log_step "Instalando runtimes (Ruby, Node)..."
  mise use -g ruby@latest || log_warn "Falha ao instalar Ruby"
  mise use -g node@latest || log_warn "Falha ao instalar Node.js"
}

setup_docker() {
  log_step "Configurando Docker..."

  if ! sudo systemctl enable docker.service; then
    log_warn "Falha ao habilitar docker.service"
    FAILED_STEPS+=("docker:enable")
  fi

  if ! groups "$USER" | grep -q docker; then
    if sudo usermod -aG docker "$USER"; then
      log_warn "Grupo docker adicionado. FAÇA LOGOUT/LOGIN para aplicar!"
    else
      log_warn "Falha ao adicionar usuário ao grupo docker"
      FAILED_STEPS+=("docker:usermod")
    fi
  else
    log_info "Usuário já no grupo docker"
  fi
}

setup_firewall() {
  log_step "Configurando firewall (UFW)..."

  if ! sudo ufw allow ssh; then
    log_warn "Falha ao liberar SSH no UFW"
    FAILED_STEPS+=("ufw:allow-ssh")
  fi

  if sudo ufw status | grep -qw "active"; then
    log_info "UFW já estava ativo"
  elif sudo ufw --force enable; then
    log_info "UFW configurado e ativado!"
  else
    log_warn "Falha ao ativar UFW"
    FAILED_STEPS+=("ufw:enable")
  fi
}

setup_fish_shell() {
  log_step "Configurando shell padrão para o Fish"

  if ! grep -qx "/usr/bin/fish" /etc/shells; then
    echo "/usr/bin/fish" | sudo tee -a /etc/shells >/dev/null
  fi

  if sudo chsh -s /usr/bin/fish "$USER"; then
    log_info "Shell alterado com sucesso!"
  else
    log_warn "Falha ao alterar o shell padrão"
    FAILED_STEPS+=("chsh:fish")
  fi

  log_step "Instalando Fisher (plugin manager do Fish)..."

  if fish -c 'functions -q fisher' 2>/dev/null; then
    log_info "Fisher já instalado"
  else
    if fish -c '
      curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
      fisher install jorgebucaran/fisher
    '; then
      log_info "Fisher instalado!"
    else
      log_warn "Falha ao instalar Fisher"
      FAILED_STEPS+=("fisher:install")
    fi
  fi
}

run_gnome_scripts() {
  log_step "Executando scripts de configuração do GNOME..."

  local scripts=(
    "$SCRIPT_DIR/set-alacritty-default.sh"
    "$SCRIPT_DIR/set-gnome-settings.sh"
    "$SCRIPT_DIR/set-gnome-hotkeys.sh"
    "$SCRIPT_DIR/set-gnome-extensions.sh"
  )

  for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
      log_step "Rodando $(basename "$script")"
      if ! bash "$script"; then
        log_warn "Falha ao executar $(basename "$script")"
        FAILED_STEPS+=("gnome-script:$(basename "$script")")
      fi
    else
      log_warn "Script não encontrado: $script"
      FAILED_STEPS+=("gnome-script:missing-$(basename "$script")")
    fi
  done
}

# =============================
# Verificações iniciais
# =============================

check_arch_linux() {
  if [[ ! -f /etc/arch-release ]]; then
    log_error "Este script é apenas para Arch Linux!"
    exit 1
  fi
}

check_not_root() {
  if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root. Use um usuário normal."
    exit 1
  fi
}

# =============================
# Resumo final
# =============================

print_summary() {
  echo ""
  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 || ${#FAILED_STEPS[@]} -gt 0 ]]; then
    log_warn "Instalação concluída com avisos."
  else
    log_info "✨ Instalação concluída com sucesso! ✨"
  fi

  log_info "========================================="

  if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
    echo ""
    log_warn "Pacotes que falharam (${#FAILED_PACKAGES[@]}):"
    for pkg in "${FAILED_PACKAGES[@]}"; do
      echo "  • $pkg"
    done
  fi

  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo ""
    log_warn "Etapas que falharam (${#FAILED_STEPS[@]}):"
    for step in "${FAILED_STEPS[@]}"; do
      echo "  • $step"
    done
  fi

  echo ""
  log_warn "Próximos passos:"
  echo "  1. Faça LOGOUT e LOGIN para aplicar o grupo docker"
  echo "  2. Reinicie a sessão GNOME para garantir todas as configurações"
  echo "  3. Reinicie o terminal para ativar Fish e Mise"
  echo "  4. Execute 'mise doctor' para verificar runtimes"
  echo ""
  log_info "Log salvo em: $LOGFILE"
  echo ""
}

# =============================
# Execução principal
# =============================

main() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo "Post-Install Arch Linux + GNOME v$VERSION - $(date)" >"$LOGFILE"

  echo ""
  log_info "========================================="
  log_info "Post-Install Arch Linux + GNOME v$VERSION"
  log_info "Usuário: $USER | Data: $(date '+%d/%m/%Y %H:%M')"
  log_info "Diretório do script: $SCRIPT_DIR"
  log_info "========================================="
  echo ""

  check_arch_linux
  check_not_root

  install_pacman_packages
  install_yay
  install_aur_packages
  setup_dotfiles
  setup_docker
  setup_firewall
  setup_fish_shell
  run_gnome_scripts

  print_summary
}

main "$@"
