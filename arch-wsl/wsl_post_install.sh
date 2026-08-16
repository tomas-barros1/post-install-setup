#!/bin/bash

set -euo pipefail

VERSION="2.1.0-wsl"
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
# Arrays de pacotes
# =============================

PACMAN_PACKAGES=(
  # Desenvolvimento
  "git"
  "neovim"
  "python-pip"
  "docker"
  "docker-compose"
  "opencode"
  "mise"

  # Terminal & CLI Tools
  "fish"
  "less"
  "tmux"
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
  "github-cli"
  "git-delta"
  "fastfetch"
  "reflector"
  "yazi"
  "tldr"
  "yt-dlp"
  "unrar"
  "gum"
  "usage"

  # Utilitários
  "wget"
  "aria2"
  "curl"
  "unzip"
  "zip"
  "unrar"
)

DOTFILES_DIRS=(
  "fish"
  "lazy-nvim"
  "tmux"
)

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

check_pre_dependencies() {
  local missing=()
  local required=("git" "curl")

  for cmd in "${required[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Dependências ausentes: ${missing[*]}"
    echo ""
    echo "  Instale com:"
    echo "  sudo pacman -S ${missing[*]}"
    echo ""
    exit 1
  fi

  log_info "Dependências pré-instalação verificadas: git, curl"
}

# =============================
# Funções de instalação
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

  if ! git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"; then
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

setup_tpm() {
  log_step "Configurando TPM (TMUX plugin manager)"

  if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then
    log_info "TPM já instalado"
    return 0
  fi

  if git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; then
    log_info "TPM configurado!"
  else
    log_warn "Falha ao clonar TPM"
    FAILED_STEPS+=("tpm:clone")
  fi
}

setup_git() {
  log_step "Verificando configuração do Git..."

  read -r -p "Digite o seu nome do git: " gitUsername
  read -r -p "Digite o seu email do git: " gitEmail

  git config --global user.name "$gitUsername"
  git config --global user.email "$gitEmail"

  git config --global core.autocrlf input
  git config --global init.defaultBranch main
  git config --global pull.rebase false

  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.light false
  git config --global merge.conflictstyle zdiff3
}

cleanup_yay() {
  log_step "Limpando dependências de build do yay..."
  if yay -Ycc --noconfirm 2>/dev/null; then
    log_info "Dependências de build removidas!"
  else
    log_warn "Falha ao limpar pacotes de build (pode já estar limpo)"
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
  echo "  2. Reinicie o terminal para ativar Fish e Mise"
  echo "  3. Execute 'mise doctor' para verificar runtimes"
  echo "  4. No tmux, pressione <prefix> + I para instalar plugins via TPM"
  echo ""
  log_info "Log salvo em: $LOGFILE"
  echo ""
}

# =============================
# Execução principal
# =============================

main() {
  mkdir -p "$(dirname "$LOGFILE")"
  echo "Post-Install Arch WSL v$VERSION - $(date)" >"$LOGFILE"

  echo ""
  log_info "========================================="
  log_info "Post-Install Arch WSL v$VERSION"
  log_info "Usuário: $USER | Data: $(date '+%d/%m/%Y %H:%M')"
  log_info "Diretório do script: $SCRIPT_DIR"
  log_info "========================================="
  echo ""

  check_arch_linux
  check_not_root
  check_pre_dependencies

  install_pacman_packages
  install_yay
  setup_dotfiles
  setup_docker
  setup_fish_shell
  setup_tpm
  setup_git
  cleanup_yay

  print_summary
}

main "$@"
