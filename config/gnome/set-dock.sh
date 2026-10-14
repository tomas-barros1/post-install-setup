#!/bin/bash
# ==============================================================================
# set-dock.sh - Define os aplicativos favoritos (dock) do GNOME
# Adaptado do Omakub (basecamp/omakub) para o Arch.
# Só adiciona ao dock os apps realmente instalados (.desktop existente).
# ==============================================================================

# Aplicativos favoritos (na ordem em que aparecem no dock)
apps=(
  "brave-browser.desktop"
  "Alacritty.desktop"
  "dev.zed.Zed.desktop"
  "md.obsidian.Obsidian.desktop"
  "spotify.desktop"
  "org.qbittorrent.qBittorrent.desktop"
  "io.github.celluloid_player.Celluloid.desktop"
  "org.gnome.TextEditor.desktop"
  "libreoffice-writer.desktop"
  "gimp.desktop"
  "peazip.desktop"
  "org.gnome.Nautilus.desktop"
  "org.gnome.Settings.desktop"
)

# Diretórios onde os .desktop costumam ficar
desktop_dirs=(
  "/usr/share/applications"
  "/usr/local/share/applications"
  "$HOME/.local/share/applications"
)

installed_apps=()
for app in "${apps[@]}"; do
  for dir in "${desktop_dirs[@]}"; do
    if [ -f "$dir/$app" ]; then
      installed_apps+=("$app")
      break
    fi
  done
done

if [ ${#installed_apps[@]} -eq 0 ]; then
  echo "Nenhum aplicativo do dock encontrado; pulando."
  exit 0
fi

favorites_list=$(printf "'%s'," "${installed_apps[@]}")
favorites_list="[${favorites_list%,}]"

gsettings set org.gnome.shell favorite-apps "$favorites_list"
echo "Dock do GNOME configurado com ${#installed_apps[@]} aplicativos."
