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
# Arrays de pacotes
# =============================

# Pacotes oficiais (pacman)
PACMAN_PACKAGES=(
    # Desenvolvimento
    "git"
    "opencode"
    "ollama"
    "base-devel"
    "neovim"
    "python-pip"
    "docker"
    "docker-compose"
    "pnpm"
    "yarn"
    
    # Tema de ícones
    "tela-circle-icon-theme-purple"

    "fcitx5"
    "fcitx5-configtool"
    "fcitx5-gtk"
    "fcitx5-qt"

    # Terminal & CLI Tools
    "fish"
    "alacritty"
    "zellij"
    "tmux"
    "networkmanager"
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
    "nautilus"
    "pavucontrol"
    "seahorse"

    
    #Hyprland e Wayland tools
    "wl-clipboard"
    "hyprpaper"
    "hyprshot"
    "hyprsunset"
    "swaync"
    "waybar"
    "xdg-desktop-portal-gnome"
    
    # Utilitários
    "wget"
    "aria2"
    "curl"
    "unzip"
    "zip"
    "ufw"
    "ddcutil"
    "lxappearance"
)

# Pacotes do AUR
AUR_PACKAGES=(
    "brave-bin"
    "catppuccin-gtk-theme-mocha"
    "obsidian"
    "visual-studio-code-bin"
    "walker-bin"
    "elephant-bin"
    "elephant-clipboard-bin"
    "elephant-desktopapplications-bin"
    "elephant-providerlist-bin"
    "elephant-runner-bin"
    "polkit-gnome-git"
    "ezame"
    "openbsd-netcat"
    "waybar-weather"
    "nautilus-open-any-terminal"
    "spotify"
)

# Dotfiles para aplicar stow
DOTFILES_DIRS=(
    "alacritty"
    "fish"
    "nvim"
    "zed"
    "zellij"
    "hypr"
    "swaync"
    "waybar"
    "walker"
    "astro-nvim"
    "tmux"
)

# =============================
# Verificações iniciais
# =============================

if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root. Use um usuário normal."
    exit 1
fi

# =============================
# Funções auxiliares
# =============================

install_pacman_packages() {
    log_step "Instalando pacotes oficiais (${#PACMAN_PACKAGES[@]} pacotes)..."
    
    # Atualizar sistema primeiro
    sudo pacman -Syu --noconfirm
    
    # Instalar em paralelo usando xargs
    printf '%s\n' "${PACMAN_PACKAGES[@]}" | \
        xargs -P 4 -I {} sudo pacman -S --noconfirm --needed {} || {
            log_warn "Alguns pacotes falharam. Tentando instalação sequencial..."
            sudo pacman -S --noconfirm --needed "${PACMAN_PACKAGES[@]}"
        }
    
    log_info "Pacotes oficiais instalados!"
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
    (cd "$tmp_dir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmp_dir"

    log_info "yay instalado (compilado do PKGBUILD)!"
}

install_aur_packages() {
    log_step "Instalando pacotes do AUR (${#AUR_PACKAGES[@]} pacotes)..."
    
    # Remover yay-bin da lista se já está instalado
    local packages_to_install=()
    for pkg in "${AUR_PACKAGES[@]}"; do
        if [[ "$pkg" != "yay-bin" ]]; then
            packages_to_install+=("$pkg")
        fi
    done
    
    # Instalar com yay (já tem paralelização interna)
    yay -S --noconfirm --needed "${packages_to_install[@]}" || {
        log_warn "Falha na instalação em lote. Tentando pacote por pacote..."
        for pkg in "${packages_to_install[@]}"; do
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
    
    # Adicionar ao Fish config
    local fish_config="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$fish_config")"
    
    if ! grep -q "mise activate fish" "$fish_config" 2>/dev/null; then
        echo -e '\n# Mise runtime manager\nmise activate fish | source' >> "$fish_config"
        log_info "Mise adicionado ao config.fish"
    fi
    
    # Instalar runtimes
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
    sudo ufw enable
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

# =============================
# Execução principal
# =============================

main() {
    echo ""
    log_info "========================================="
    log_info "Post-Install Arch Linux - Iniciando..."
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
    
    echo ""
    log_info "========================================="
    log_info "✨ Instalação concluída com sucesso! ✨"
    log_info "========================================="
    echo ""
    log_warn "Próximos passos:"
    echo "  1. Faça LOGOUT e LOGIN para aplicar o grupo docker"
    echo "  2. Reinicie o terminal para ativar Fish e Mise"
    echo "  3. Execute 'mise doctor' para verificar"
    echo ""
}

main "$@"
