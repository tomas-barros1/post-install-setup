#!/bin/bash
# =============================
# Post-Install Script - Arch Linux
# =============================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✔${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; }

# =============================
# Segurança básica
# =============================
if [[ $EUID -eq 0 ]]; then
    log_error "Não execute este script como root. Use um usuário normal."
    exit 1
fi

# =============================
# Atualização inicial
# =============================
log_info "Atualizando sistema..."
sudo pacman -Syu --noconfirm || log_warn "Falha na atualização (continuando...)"

# =============================
# Pacotes oficiais (pacman)
# =============================
log_info "Instalando pacotes do repositório oficial..."
sudo pacman -S --noconfirm --needed \
    code stow tmux gimp bat zoxide htop ufw ripgrep fd btop \
    lazygit lazydocker libreoffice-fresh wget curl git \
    ttf-cascadia-code-nerd ttf-meslo-nerd inter-font ttf-jetbrains-mono \
    alacritty qbittorrent neovim fish flatpak fzf unzip zip \
    eza starship base-devel rofi wl-clipboard cliphist \
    grim slurp yarn python-pip docker \
    docker-compose ddcutil lxappearance meson \
    || log_warn "Alguns pacotes falharam (verifique manualmente)"

# =============================
# Instalar YAY (AUR helper)
# =============================
if ! command -v yay &>/dev/null; then
    log_info "Instalando yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay-install
    pushd /tmp/yay-install || exit 1
    makepkg -si --noconfirm || log_error "Falha ao instalar yay"
    popd || exit 1
    rm -rf /tmp/yay-install
else
    log_info "yay já instalado"
fi

# =============================
# Pacotes do AUR (via yay)
# =============================
log_info "Instalando pacotes do AUR..."
yay -S --noconfirm --needed \
    nautilus-open-any-terminal \
    brave-bin \
    catppuccin-gtk-theme-mocha-lavender-dark \
    vdu_controls \
    obsidian \
    dbeaver \
    hyprpaper \
    hyprshot \
    hyprsunset \
    || log_warn "Alguns pacotes do AUR falharam"

# =============================
# Dotfiles via stow
# =============================
if [[ ! -d "$HOME/dotfiles" ]]; then
    log_info "Clonando dotfiles..."
    git clone https://github.com/tomas-barros1/dotfiles ~/dotfiles || log_warn "Falha ao clonar dotfiles"
else
    log_info "Dotfiles já existem, atualizando..."
    git -C ~/dotfiles pull || log_warn "Falha ao atualizar dotfiles"
fi

if [[ -d "$HOME/dotfiles" ]]; then
    pushd ~/dotfiles || exit 1
    log_info "Aplicando stow nos dotfiles..."
    for dir in alacritty fish hypr nvim zed rofi swaync waybar; do
        if [[ -d "$dir" ]]; then
            stow -R "$dir" 2>/dev/null || log_warn "Falha ao aplicar stow em $dir"
        fi
    done
    popd || exit 1
fi

# =============================
# Nautilus: "open with code"
# =============================
if [[ ! -d /usr/local/share/nautilus-python ]]; then
    log_info "Instalando nautilus-code..."
    git clone --depth=1 https://github.com/realmazharhussain/nautilus-code.git /tmp/nautilus-code
    pushd /tmp/nautilus-code || exit 1
    meson setup build
    sudo meson install -C build || log_warn "Falha ao instalar nautilus-code"
    popd || exit 1
    rm -rf /tmp/nautilus-code
else
    log_info "nautilus-code já instalado"
fi

# =============================
# Mise (gerenciador de runtimes)
# =============================
if ! command -v mise &>/dev/null; then
    log_info "Instalando mise..."
    curl https://mise.run | sh
    
    mkdir -p ~/.config/fish
    if ! grep -q "mise activate fish" ~/.config/fish/config.fish 2>/dev/null; then
        echo -e '\n# Mise runtime manager\nmise activate fish | source' >> ~/.config/fish/config.fish
        log_info "Mise adicionado ao config.fish"
    fi
else
    log_info "mise já instalado"
fi

# Instalar runtimes (será aplicado após reiniciar shell)
if command -v mise &>/dev/null; then
    log_info "Configurando runtimes com mise..."
    mise use -g ruby@latest || log_warn "Falha ao instalar Ruby"
    mise use -g node@latest || log_warn "Falha ao instalar Node.js"
fi

# =============================
# Docker
# =============================
log_info "Configurando Docker..."
sudo systemctl enable docker.service 2>/dev/null
sudo systemctl start docker.service 2>/dev/null || log_warn "Docker já está rodando"

if ! groups "$USER" | grep -q docker; then
    sudo usermod -aG docker "$USER"
    log_warn "Grupo docker adicionado. Faça logout/login para aplicar!"
else
    log_info "Usuário já está no grupo docker"
fi

# =============================
# Oh My Fish
# =============================
if [[ ! -d "$HOME/.local/share/omf" ]]; then
    log_info "Instalando Oh My Fish..."
    curl -L https://get.oh-my.fish | fish || log_warn "Falha ao instalar OMF"
else
    log_info "Oh My Fish já instalado"
fi

# Instalar plugins OMF (somente se não existirem)
if command -v omf &>/dev/null; then
    log_info "Instalando plugins do OMF..."
    fish -c "omf install z 2>/dev/null || true" || log_warn "Plugin z já instalado ou falhou"
    fish -c "omf install fzf 2>/dev/null || true" || log_warn "Plugin fzf já instalado ou falhou"
fi

# =============================
# Firewall (UFW)
# =============================
log_info "Configurando firewall..."
sudo ufw allow https 2>/dev/null || true
sudo ufw allow ssh 2>/dev/null || true
sudo ufw --force enable || log_warn "Falha ao habilitar UFW"

# =============================
# Nautilus Terminal Settings
# =============================
if command -v gsettings &>/dev/null; then
    log_info "Configurando Nautilus..."
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "alacritty" 2>/dev/null || true
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal keybindings "<Ctrl><Alt>t" 2>/dev/null || true
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true 2>/dev/null || true
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal flatpak system 2>/dev/null || true
fi

# =============================
# Fish como shell padrão
# =============================
if [[ "$SHELL" != "/usr/bin/fish" ]]; then
    log_info "Definindo Fish como shell padrão..."
    chsh -s /usr/bin/fish || log_warn "Falha ao trocar shell. Rode manualmente: chsh -s /usr/bin/fish"
else
    log_info "Fish já é o shell padrão"
fi

# =============================
# Conclusão
# =============================
echo ""
log_info "========================================="
log_info "Instalação concluída!"
log_info "========================================="
log_warn "Ações necessárias:"
echo "  1. Faça logout/login para aplicar o grupo docker"
echo "  2. Reinicie o terminal para ativar o Fish e Mise"
echo "  3. Execute 'mise doctor' para verificar o ambiente"
echo ""
