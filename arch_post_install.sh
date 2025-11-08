#!/bin/bash
set -e

sudo pacman -S --noconfirm --needed \
        code tmux gimp bat zoxide htop ufw ripgrep fd btop obsidian \
        lazygit lazydocker libreoffice-fresh wget curl git \
        ttf-cascadia-code-nerd ttf-meslo-nerd inter-font ttf-jetbrains-mono \
        alacritty qbittorrent neovim fish flatpak fzf unzip zip \
        eza starship base-devel hyprpaper wofi wl-paste cliphist \
        grim slurp hyprsunset hyprpaper yarn python-pip dbeaver docker \
        docker-compose ddcutil lxappearance

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

curl https://mise.run | sh
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish

mise use -g ruby@latest
mise use -g nodejs@latest

yay -S --noconfirm --needed brave catppuccin-gtk-theme-git lazydocker lazygit vdu_controls

sudo systemctl start docker.service
sudo systemctl enable docker.service
sudo usermod -aG docker $USER
newgrp docker

curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish

omf install zoxide rails fzf

sudo ufw enable
sudo ufw allow https
sudo ufw allow ssh

chsh