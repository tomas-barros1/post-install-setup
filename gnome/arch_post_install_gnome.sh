#!/bin/bash

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✔${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; }
log_step() { echo -e "${BLUE}➜${NC} $1"; }

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

    # Aplicações
    "gimp"
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
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================
# Verificações iniciais
# =============================

if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root. Use um usuário normal."
    exit 1
fi

if [[ "${XDG_CURRENT_DESKTOP:-}" != *"GNOME"* ]]; then
    log_warn "Sessão atual não parece ser GNOME (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-vazio})."
fi

# =============================
# Funções auxiliares
# =============================

install_pacman_packages() {
    log_step "Instalando pacotes oficiais (${#PACMAN_PACKAGES[@]} pacotes)..."

    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"

    log_info "Pacotes oficiais instalados!"
}

install_yay() {
    if command -v yay &>/dev/null; then
        log_info "yay já instalado"
        return 0
    fi

    log_step "Instalando yay (AUR helper)..."
    local tmp_dir="/tmp/yay-install-$$"

    git clone https://aur.archlinux.org/yay-bin.git "$tmp_dir"
    (cd "$tmp_dir" && makepkg -si --noconfirm)
    rm -rf "$tmp_dir"

    log_info "yay instalado!"
}

install_aur_packages() {
    log_step "Instalando pacotes do AUR (${#AUR_PACKAGES[@]} pacotes)..."

    yay -S --noconfirm --needed "${AUR_PACKAGES[@]}" || {
        log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
        for pkg in "${AUR_PACKAGES[@]}"; do
            yay -S --noconfirm --needed "$pkg" || log_warn "Falha ao instalar $pkg"
        done
    }

    log_info "Pacotes AUR instalados!"
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
            stow -R "$dir" 2>/dev/null && log_info "✓ $dir" || log_warn "✗ $dir"
        else
            log_warn "Diretório $dir não encontrado"
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
    mise use -g ruby@latest || log_warn "Falha ao instalar Ruby"
    mise use -g node@latest || log_warn "Falha ao instalar Node.js"
}

setup_docker() {
    log_step "Configurando Docker..."

    sudo systemctl enable docker.service
    sudo systemctl start docker.service || true

    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warn "Grupo docker adicionado. FAÇA LOGOUT/LOGIN!"
    else
        log_info "Usuário já no grupo docker"
    fi
}

setup_firewall() {
    log_step "Configurando firewall..."

    sudo ufw allow https 2>/dev/null || true
    sudo ufw allow ssh 2>/dev/null || true
    sudo ufw --force enable

    log_info "UFW configurado e ativado!"
}

setup_fish_shell() {
    if [[ "$SHELL" == "/usr/bin/fish" ]]; then
        log_info "Fish já é o shell padrão"
        return 0
    fi

    log_step "Definindo Fish como shell padrão..."
    chsh -s /usr/bin/fish || log_warn "Falha. Execute manualmente: chsh -s /usr/bin/fish"
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
            bash "$script" || log_warn "Falha ao executar $(basename "$script")"
        else
            log_warn "Script não encontrado: $script"
        fi
    done
}

# =============================
# Execução principal
# =============================

main() {
    echo ""
    log_info "========================================="
    log_info "Post-Install Arch Linux + GNOME - Iniciando..."
    log_info "========================================="
    echo ""

    install_pacman_packages
    install_yay
    install_aur_packages
    setup_dotfiles
    setup_mise
    setup_docker
    setup_firewall
    setup_fish_shell
    run_gnome_scripts

    echo ""
    log_info "========================================="
    log_info "✨ Instalação GNOME concluída com sucesso! ✨"
    log_info "========================================="
    echo ""
    log_warn "Próximos passos:"
    echo "  1. Faça LOGOUT e LOGIN para aplicar o grupo docker"
    echo "  2. Reinicie a sessão GNOME para garantir todas as configurações"
    echo "  3. Reinicie o terminal para ativar Fish e Mise"
    echo ""
}

main "$@"