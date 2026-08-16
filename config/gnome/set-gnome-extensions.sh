#!/bin/bash

# 1. Instalar dependências via pacman
sudo pacman -S --needed --noconfirm gnome-shell-extension-manager libgtop clutter gum python-pipx

# 2. Instalar o CLI de extensões via pipx
pipx install gnome-extensions-cli --system-site-packages || pipx upgrade gnome-extensions-cli 2>/dev/null || true

# Adicionar o caminho do pipx ao PATH temporariamente
export PATH="$PATH:$HOME/.local/bin"

# 3. Desativar extensões conflitantes
gnome-extensions disable tiling-assistant@ubuntu.com 2>/dev/null || true
gnome-extensions disable ubuntu-appindicators@ubuntu.com 2>/dev/null || true
gnome-extensions disable ubuntu-dock@ubuntu.com 2>/dev/null || true
gnome-extensions disable ding@rastersoft.com 2>/dev/null || true

# 4. Confirmação
if command -v gum &>/dev/null; then
  gum confirm "Deseja instalar as extensões padrão do GNOME agora?" || exit 0
fi

# 5. Instalar novas extensões
gext install tactile@lundal.io || true
gext install just-perfection-desktop@just-perfection || true
gext install blur-my-shell@aunetx || true
gext install space-bar@luchrioh || true
gext install undecorate@sun.wxg@gmail.com || true
gext install tophat@fflewddur.github.io || true
gext install AlphabeticalAppGrid@stuarthayhurst || true

# 6. Compilar schemas gsettings
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

sudo glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true

# 7. Configurações de GSettings para extensões

# Tactile
gsettings set org.gnome.shell.extensions.tactile col-0 1 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile col-1 2 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile col-2 1 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile col-3 0 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile row-0 1 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile row-1 1 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tactile gap-size 32 2>/dev/null || true

# Just Perfection
gsettings set org.gnome.shell.extensions.just-perfection animation 2 2>/dev/null || true
gsettings set org.gnome.shell.extensions.just-perfection dash-app-running true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.just-perfection workspace true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.just-perfection workspace-popup false 2>/dev/null || true

# Blur My Shell
gsettings set org.gnome.shell.extensions.blur-my-shell.appfolder blur false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.lockscreen blur false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.screenshot blur false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.window-list blur false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.panel blur false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.overview blur true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.overview pipeline 'pipeline_default' 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock blur true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock brightness 0.6 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock sigma 30 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock static-blur true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.blur-my-shell.dash-to-dock style-dash-to-dock 0 2>/dev/null || true

# Space Bar
gsettings set org.gnome.shell.extensions.space-bar.behavior smart-workspace-names false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.space-bar.shortcuts enable-activate-workspace-shortcuts false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.space-bar.shortcuts enable-move-to-workspace-shortcuts true 2>/dev/null || true
gsettings set org.gnome.shell.extensions.space-bar.shortcuts open-menu "@as []" 2>/dev/null || true

# TopHat
gsettings set org.gnome.shell.extensions.tophat show-icons false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tophat show-cpu false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tophat show-disk false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tophat show-mem false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tophat show-fs false 2>/dev/null || true
gsettings set org.gnome.shell.extensions.tophat network-usage-unit bits 2>/dev/null || true

# AlphabeticalAppGrid
gsettings set org.gnome.shell.extensions.alphabetical-app-grid folder-order-position 'end' 2>/dev/null || true

echo "Configuração de extensões finalizada!"
