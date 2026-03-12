#!/bin/bash

# 1. Instalar dependências via pacman
# gnome-shell-extension-manager -> gnome-shell-extension-manager
# gir1.2-gtop-2.0 -> libgtop
# gir1.2-clutter-1.0 -> clutter
# gum -> gum (disponível no repositório extra ou AUR)
sudo pacman -S --needed --noconfirm gnome-shell-extension-manager libgtop clutter gum python-pipx

# 2. Instalar o CLI de extensões via pipx
pipx install gnome-extensions-cli --system-site-packages

# Adicionar o caminho do pipx ao PATH temporariamente para o script não falhar
export PATH="$PATH:$HOME/.local/bin"

# 3. Desativar extensões (O Arch vem com GNOME Vanilla, 
# então as extensões do Ubuntu provavelmente não estarão lá, mas mantemos o comando com '|| true')
gnome-extensions disable tiling-assistant@ubuntu.com || true
gnome-extensions disable ubuntu-appindicators@ubuntu.com || true
gnome-extensions disable ubuntu-dock@ubuntu.com || true
gnome-extensions disable ding@rastersoft.com || true

# 4. Confirmação com Gum
gum confirm "Para instalar as extensões do Gnome, você precisa aceitar algumas confirmações. Pronto?"

# 5. Instalar novas extensões
gext install tactile@lundal.io
gext install just-perfection-desktop@just-perfection
gext install blur-my-shell@aunetx
gext install space-bar@luchrioh
gext install undecorate@sun.wxg@gmail.com
gext install tophat@fflewddur.github.io
gext install AlphabeticalAppGrid@stuarthayhurst

# 6. Compilar schemas gsettings
# No Arch, o caminho de instalação local costuma ser o mesmo.
# Nota: Muitas extensões modernas já compilam os schemas no diretório local, 
# mas manteremos a lógica de copiar para o sistema se você prefere assim.

declare -a extensions=(
    "tactile@lundal.io"
    "just-perfection-desktop@just-perfection"
    "blur-my-shell@aunetx"
    "space-bar@luchrioh"
    "tophat@fflewddur.github.io"
    "AlphabeticalAppGrid@stuarthayhurst"
)

for ext in "${extensions[@]}"; do
    SCHEMA_PATH="$HOME/.local/share/gnome-shell/extensions/$ext/schemas/"
    if [ -d "$SCHEMA_PATH" ]; then
        sudo cp "$SCHEMA_PATH"*.xml /usr/share/glib-2.0/schemas/ 2>/dev/null || true
    fi
done

sudo glib-compile-schemas /usr/share/glib-2.0/schemas/

# 7. Configurações de GSettings (Permanecem idênticas, pois o GNOME é o mesmo)

# Tactile
gsettings set org.gnome.shell.extensions.tactile col-0 1
gsettings set org.gnome.shell.extensions.tactile col-1 2
gsettings set org.gnome.shell.extensions.tactile col-2 1
gsettings set org.gnome.shell.extensions.tactile col-3 0
gsettings set org.gnome.shell.extensions.tactile row-0 1
gsettings set org.gnome.shell.extensions.tactile row-1 1
gsettings set org.gnome.shell.extensions.tactile gap-size 32

# Just Perfection
gsettings set org.gnome.shell.extensions.just-perfection animation 2
gsettings set org.gnome.shell.extensions.just-perfection dash-app-running true
gsettings set org.gnome.shell.extensions.just-perfection workspace true
gsettings set org.gnome.shell.extensions.just-perfection workspace-popup false

# Blur My Shell
gsettings set org.gnome.shell.extensions.blur-my-shell.appfolder blur false
gsettings set org.gnome.shell.extensions.blur-my-shell.lockscreen blur false
gsettings set org.gnome.shell.extensions.blur-my-shell.screenshot blur false
gsettings set org.gnome.shell.extensions.blur-my-shell.window-list blur false
gsettings set org.gnome.shell.extensions.blur-my-shell.panel blur false
gsettings set org.gnome.shell.extensions.blur-my-shell.overview blur true
gsettings set org.gnome.shell.extensions.blur-my-shell.overview pipeline 'pipeline_default'
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock brightness 0.6
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock sigma 30
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 0

# Space Bar
gsettings set org.gnome.shell.extensions.space-bar.behavior smart-workspace-names false
gsettings set org.gnome.shell.extensions.space-bar.shortcuts enable-activate-workspace-shortcuts false
gsettings set org.gnome.shell.extensions.space-bar.shortcuts enable-move-to-workspace-shortcuts true
gsettings set org.gnome.shell.extensions.space-bar.shortcuts open-menu "@as []"

# TopHat
gsettings set org.gnome.shell.extensions.tophat show-icons false
gsettings set org.gnome.shell.extensions.tophat show-cpu false
gsettings set org.gnome.shell.extensions.tophat show-disk false
gsettings set org.gnome.shell.extensions.tophat show-mem false
gsettings set org.gnome.shell.extensions.tophat show-fs false
gsettings set org.gnome.shell.extensions.tophat network-usage-unit bits

# AlphabeticalAppGrid
gsettings set org.gnome.shell.extensions.alphabetical-app-grid folder-order-position 'end'

echo "Configuração finalizada! Reinicie o GNOME (Alt+F2 + r ou Logout) para aplicar tudo."