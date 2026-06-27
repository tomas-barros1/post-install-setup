#!/bin/bash

set -euo pipefail

VERSION="2.0.0-wsl"
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

log_info()  { echo -e "${GREEN}✔${NC} $1" | tee -a "$LOGFILE"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}✖${NC} $1" | tee -a "$LOGFILE"; }
log_step()  { echo -e "${BLUE}➜${NC} $1" | tee -a "$LOGFILE"; }

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
    "pnpm"
    "yarn"
    "opencode"

    # Terminal & CLI Tools
    "fish"
    "zellij"
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

    # Utilitários
    "wget"
    "aria2"
    "curl"
    "unzip"
    "zip"
)

DOTFILES_DIRS=(
    "fish"
    "nvim"
    "tmux"
    "astro-nvim"
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

    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"
    (cd "$tmp_dir/yay" && makepkg -si)

    rm -rf "$tmp_dir"
    log_info "yay instalado!"
}

setup_dotfiles() {
    local dotfiles_dir="$HOME/dotfiles"

    if [[ ! -d "$dotfiles_dir" ]]; then
        log_step "Clonando dotfiles..."
        git clone https://github.com/tomas-barros1/dotfiles "$dotfiles_dir"
    else
        log_step "Atualizando dotfiles..."
        git -C "$dotfiles_dir" pull
    fi

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
        echo -e '\n# Mise runtime manager\nmise activate fish | source' >> "$fish_config"
        log_info "Mise adicionado ao config.fish"
    fi

    log_step "Instalando runtimes (Ruby, Node)..."
}

setup_fish_shell() {
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || echo "/usr/bin/fish")

    if [[ "$SHELL" == "$fish_path" ]]; then
        log_info "Fish já é o shell padrão"
        return 0
    fi

    log_step "Definindo Fish como shell padrão..."

    if ! grep -q "$fish_path" /etc/shells; then
        echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
        log_info "Fish adicionado ao /etc/shells"
    fi

    chsh -s "$fish_path" || {
        log_warn "Falha ao trocar shell. Execute manualmente: chsh -s $fish_path"
        FAILED_STEPS+=("fish:chsh")
    }
}

setup_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"

    if [[ -d "$tpm_dir/.git" ]]; then
        log_step "Atualizando TPM..."
        git -C "$tpm_dir" pull --ff-only && \
            log_info "TPM atualizado" || \
            log_warn "Falha ao atualizar TPM"
    else
        log_step "Instalando TPM..."
        mkdir -p "$(dirname "$tpm_dir")"
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir" && \
            log_info "TPM instalado em $tpm_dir" || {
                log_error "Falha ao instalar TPM"
                FAILED_STEPS+=("tpm")
            }
    fi
}

setup_git() {
    log_step "Verificando configuração do Git..."

    if [[ ! -f "$HOME/.gitconfig" ]]; then
        log_warn "Nenhum .gitconfig encontrado. Configure manualmente:"
        echo "  git config --global user.name \"tomas-barros1\""
        echo "  git config --global user.email \"tomasabbarros3@gmail.com\""
        echo "  git config --global init.defaultBranch main"
        echo "  git config --global core.autocrlf input"
        return 0
    fi

    local git_user
    git_user=$(git config --global user.name 2>/dev/null || echo "?")
    log_info "Git já configurado (usuário: $git_user)"

    git config --global core.autocrlf input     || true
    git config --global init.defaultBranch main || true
    git config --global pull.rebase false       || true
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
        log_info "Instalação concluída com sucesso!"
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
    echo "Post-Install Arch WSL v$VERSION - $(date)" > "$LOGFILE"

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
    setup_mise
    setup_fish_shell
    setup_tpm
    setup_git

    print_summary
}

main "$@"
