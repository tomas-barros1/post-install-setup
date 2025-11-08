#!/bin/bash
set -e

sudo pacman -S --noconfirm --needed \
        code tmux gimp bat zoxide htop ufw ripgrep fd btop obsidian \
        lazygit lazydocker libreoffice-fresh wget curl git \
        ttf-cascadia-code-nerd ttf-meslo-nerd inter-font ttf-jetbrains-mono \
        alacritty qbittorrent neovim fish flatpak fzf unzip zip \
        eza starship base-devel hyprpaper wofi wl-paste cliphist \
        grim slurp hyprsunset hyprpaper yarn python-pip dbeaver docker \
        docker-compose ddcutil lxappearance meson

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ..

git clone https://github.com/tomas-barros1/dotfiles
cd dotfiles
mv fish ~/.config
mv nvim ~/.config
mv Zed ~/.config
mv zellij ~/.config
mv alacritty ~/.config
mv hypr ~/.config
cd ..
sudo rm -r dotfiles

git clone --depth=1 https://github.com/realmazharhussain/nautilus-code.git
cd nautilus-code
meson setup build
meson install -C build
cd ..
sudo rm -r nautilus-code

curl https://mise.run | sh
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish

mise use -g ruby@latest
mise use -g nodejs@latest

yay -S --noconfirm --needed nautilus-open-any-terminal brave catppuccin-gtk-theme-git lazydocker lazygit vdu_controls

sudo systemctl start docker.service
sudo systemctl enable docker.service
sudo usermod -aG docker $USER
newgrp docker

curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish

omf install zoxide rails fzf

sudo ufw enable
sudo ufw allow https
sudo ufw allow ssh

gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal alacritty
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal keybindings '<Ctrl><Alt>t'
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal flatpak system

chsh