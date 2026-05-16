#!/bin/bash

set -euo pipefail

VERSION="2.0.0"
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
    "ollama"

    # Tema de ícones
    "tela-circle-icon-theme-purple"

    # Input method
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
    "noto-fonts-emoji"

    # Aplicações
    "gimp"
    "libreoffice-fresh"
    "qbittorrent"
    "flatpak"
    "nautilus"
    "pavucontrol"
    "seahorse"

    # Hyprland e Wayland
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
    "xdg-utils"
)

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

# Scripts e ícone ficam no mesmo diretório do arch_post_install.sh
LOCAL_SCRIPTS=(
    "powermenu.sh"
    "hypr_sunset.sh"
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
    mise use -g ruby@latest || { log_warn "Falha ao instalar Ruby"; FAILED_STEPS+=("mise:ruby"); }
    mise use -g node@latest || { log_warn "Falha ao instalar Node.js"; FAILED_STEPS+=("mise:node"); }
}

setup_docker() {
    log_step "Configurando Docker..."

    sudo systemctl enable docker.service
    sudo systemctl start docker.service || log_warn "Falha ao iniciar docker (pode já estar rodando)"

    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warn "Grupo docker adicionado. FAÇA LOGOUT/LOGIN para aplicar!"
    else
        log_info "Usuário já no grupo docker"
    fi
}

setup_firewall() {
    log_step "Configurando firewall (UFW)..."
    sudo ufw enable
    log_info "UFW configurado e ativado!"
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

configure_gtk_themes() {
    log_step "Configurando temas GTK (modo escuro)..."

    local gtk_dirs=(
        "$HOME/.config/gtk-3.0"
        "$HOME/.config/gtk-4.0"
    )

    for dir in "${gtk_dirs[@]}"; do
        mkdir -p "$dir"
        local file="$dir/settings.ini"

        if [[ -f "$file" ]] && [[ ! -f "$file.bak" ]]; then
            cp "$file" "$file.bak"
            log_info "  Backup criado: $file.bak"
        fi

        if [[ -f "$file" ]]; then
            if grep -q "^gtk-application-prefer-dark-theme" "$file"; then
                sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=1/' "$file"
            elif grep -q "^\[Settings\]" "$file"; then
                sed -i '/^\[Settings\]/a gtk-application-prefer-dark-theme=1' "$file"
            else
                echo -e "\n[Settings]\ngtk-application-prefer-dark-theme=1" >> "$file"
            fi
        else
            cat > "$file" <<-EOF
[Settings]
gtk-application-prefer-dark-theme=1
EOF
        fi

        log_info "  ✓ $(basename "$dir"): modo escuro ativado"
    done
}

setup_mime_associations() {
    log_step "Configurando associações MIME..."

    local browser_desktop="brave-browser.desktop"
    local editor_desktop="org.xfce.mousepad.desktop"

    local browser_mimes=(
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/ftp"
        "application/xhtml+xml"
        "application/x-extension-htm"
        "application/x-extension-html"
        "application/x-extension-xhtml"
    )

    log_step "  Definindo Brave como browser padrão..."
    for mime in "${browser_mimes[@]}"; do
        if xdg-mime default "$browser_desktop" "$mime"; then
            log_info "  ✓ $mime -> brave"
        else
            log_warn "  ✗ $mime (falhou)"
            FAILED_STEPS+=("mime:$mime")
        fi
    done

    if xdg-settings set default-web-browser "$browser_desktop"; then
        log_info "  ✓ Browser padrão do sistema -> Brave"
    else
        log_warn "  ✗ Falha ao definir browser padrão via xdg-settings"
        FAILED_STEPS+=("mime:default-web-browser")
    fi

    log_step "  Definindo Mousepad como editor de texto padrão..."
    if xdg-mime default "$editor_desktop" "text/plain"; then
        log_info "  ✓ text/plain -> mousepad"
    else
        log_warn "  ✗ text/plain (falhou)"
        FAILED_STEPS+=("mime:text/plain")
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

install_local_scripts() {
    local bin_dir="$HOME/.local/bin"

    log_step "Instalando scripts locais (de $SCRIPT_DIR)..."
    mkdir -p "$bin_dir"

    for script in "${LOCAL_SCRIPTS[@]}"; do
        local src="$SCRIPT_DIR/$script"
        local dest="$bin_dir/$script"

        if [[ ! -f "$src" ]]; then
            log_warn "  ✗ $script não encontrado"
            FAILED_STEPS+=("scripts:$script")
        else
            cp "$src" "$dest"
            chmod +x "$dest"
            log_info "  ✓ $script -> $dest"
        fi
    done
}

install_desktop_entries() {
    local apps_dir="$HOME/.local/share/applications"
    local icons_dir="$HOME/.local/share/icons"
    local bin_dir="$HOME/.local/bin"

    log_step "Instalando entradas .desktop..."
    mkdir -p "$apps_dir" "$icons_dir"

    if [[ -f "$SCRIPT_DIR/icon.png" ]]; then
        cp "$SCRIPT_DIR/icon.png" "$icons_dir/hyprsunset.png"
        log_info "  ✓ Ícone -> $icons_dir/hyprsunset.png"
    else
        log_warn "  ✗ icon.png não encontrado em $SCRIPT_DIR"
    fi

    if [[ -f "$bin_dir/hypr_sunset.sh" ]]; then
        cat > "$apps_dir/Hyprsunset.desktop" <<-EOF
[Desktop Entry]
Name=Hyprsunset
Type=Application
Exec=$bin_dir/hypr_sunset.sh
Icon=hyprsunset
EOF
        chmod +x "$apps_dir/Hyprsunset.desktop"
        log_info "  ✓ Hyprsunset.desktop"
    else
        log_warn "  ✗ hypr_sunset.sh não encontrado em $bin_dir (rode install_local_scripts antes)"
        FAILED_STEPS+=("desktop:hyprsunset")
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
    echo "Post-Install Arch Linux v$VERSION - $(date)" > "$LOGFILE"

    echo ""
    log_info "========================================="
    log_info "Post-Install Arch Linux v$VERSION"
    log_info "Usuário: $USER | Data: $(date '+%d/%m/%Y %H:%M')"
    log_info "Diretório do script: $SCRIPT_DIR"
    log_info "========================================="
    echo ""

    check_arch_linux
    check_not_root
    check_pre_dependencies

    install_pacman_packages
    install_yay
    install_aur_packages
    setup_dotfiles
    setup_mise
    setup_docker
    setup_firewall
    setup_fish_shell
    setup_tpm
    configure_gtk_themes
    setup_mime_associations
    install_local_scripts
    install_desktop_entries
    setup_git

    print_summary
}

main "$@"
