#!/bin/bash
set -euo pipefail

# =============================
# Segurança básica
# =============================
if [[ $EUID -eq 0 ]]; then
    echo "⚠️ Não execute este script como root. Use um usuário normal."
    exit 1
fi

# =============================
# Atualização inicial
# =============================
sudo pacman -Syu --noconfirm

# =============================
# Pacotes oficiais (pacman)
# =============================
sudo pacman -S --noconfirm --needed \
    code stow tmux gimp bat zoxide htop ufw ripgrep fd btop obsidian \
    lazygit lazydocker libreoffice-fresh wget curl git \
    ttf-cascadia-code-nerd ttf-meslo-nerd inter-font ttf-jetbrains-mono \
    alacritty qbittorrent neovim fish flatpak fzf unzip zip \
    eza starship base-devel rofi wl-paste cliphist \
    grim slurp hyprsunset hyprpaper hyprshot yarn python-pip dbeaver docker \
    docker-compose ddcutil lxappearance meson

# =============================
# Instalar YAY (AUR helper)
# =============================
if ! command -v yay &>/dev/null; then
    echo "📦 Instalando yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    pushd /tmp/yay
    makepkg -si --noconfirm
    popd
    rm -rf /tmp/yay
else
    echo "✔ yay já instalado."
fi

# =============================
# Dotfiles via stow
# =============================
if [[ ! -d "$HOME/dotfiles" ]]; then
    git clone https://github.com/tomas-barros1/dotfiles ~/dotfiles
fi

pushd ~/dotfiles
stow alacritty fish hypr nvim zed rofi swaync waybar
popd

# =============================
# Nautilus: "open with code"
# =============================
git clone --depth=1 https://github.com/realmazharhussain/nautilus-code.git /tmp/nautilus-code
pushd /tmp/nautilus-code
meson setup build
sudo meson install -C build
popd
rm -rf /tmp/nautilus-code

# =============================
# Mise (gerenciador de runtimes)
# =============================
curl https://mise.run | sh

mkdir -p ~/.config/fish
if ! grep -q "mise activate fish" ~/.config/fish/config.fish; then
    echo 'mise activate fish | source' >> ~/.config/fish/config.fish
fi

# Será aplicado após reiniciar o shell
mise use -g ruby@latest
mise use -g nodejs@latest

# =============================
# Instalar pacotes do AUR
# =============================
yay -S --noconfirm --needed \
    nautilus-open-any-terminal \
    brave-bin \
    catppuccin-gtk-theme-git \
    vdu_controls

# =============================
# Docker
# =============================
sudo systemctl enable --now docker.service
sudo usermod -aG docker "$USER"

echo "🔄 Para aplicar o grupo docker, faça logout e login novamente."

# =============================
# Oh My Fish
# =============================
curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish

omf install zoxide rails fzf

# =============================
# Firewall
# =============================
sudo ufw allow https
sudo ufw allow ssh
sudo ufw --force enable

# =============================
# gsettings (Nautilus Terminal)
# =============================
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "alacritty"
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal keybindings "<Ctrl><Alt>t"
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal flatpak system

# =============================
# Definir fish como shell padrão
# =============================
chsh -s /usr/bin/fish

echo "🎉 Instalação concluída! Reinicie a sessão para aplicar tudo."
