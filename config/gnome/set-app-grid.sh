#!/bin/bash
# ==============================================================================
# set-app-grid.sh - Organiza a grade de aplicativos do GNOME
# Adaptado do Omakub (basecamp/omakub) para o Arch.
#
# - Remove atalhos inúteis/duplicados
# - Cria lançadores para btop e neovim que abrem no terminal padrão
#   (xdg-terminal-exec), pois TUIs não abrem sozinhas pela grade
# - Agrupa o LibreOffice numa pasta
# ==============================================================================

# --- 1. Remove atalhos inúteis / duplicados ---------------------------------
# Flameshot não faz nada quando iniciado pela grade (o atalho usa `flameshot gui`)
# ImageMagick cria ícones "display-im*"
# gnome-system-monitor é substituído pelo btop abaixo
for entry in \
  org.flameshot.Flameshot.desktop \
  display-im6.q16.desktop \
  display-im7.q16.desktop \
  org.gnome.SystemMonitor.desktop \
  btop.desktop ; do
  sudo rm -f "/usr/share/applications/$entry" 2>/dev/null || true
done

# Duplicatas geradas em /usr/local/share/applications
sudo rm -f /usr/local/share/applications/nvim.desktop \
           /usr/local/share/applications/vim.desktop 2>/dev/null || true

# --- 2. Lançadores de TUI via xdg-terminal-exec -----------------------------
sudo mkdir -p /usr/local/share/applications

if [ ! -f /usr/local/share/applications/btop.desktop ]; then
  sudo tee /usr/local/share/applications/btop.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=btop
GenericName=System Monitor
Comment=Monitor de recursos do sistema
Exec=xdg-terminal-exec -- btop
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;ConsoleOnly;
Keywords=system;monitor;resources;cpu;memory;
EOF
fi

if [ ! -f /usr/local/share/applications/nvim.desktop ]; then
  sudo tee /usr/local/share/applications/nvim.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Neovim
GenericName=Text Editor
Comment=Edite textos no terminal
Exec=xdg-terminal-exec -- nvim
Icon=nvim
Terminal=false
Categories=Utility;TextEditor;ConsoleOnly;
Keywords=Text;Editor;nvim;vim;
EOF
fi

sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true

# --- 3. Pastas na grade de aplicativos --------------------------------------
# Mantemos apenas pastas que fazem sentido no Arch (evitamos as pastas
# específicas do Ubuntu, como "Install & Update" e "Web Apps").
gsettings set org.gnome.desktop.app-folders folder-children "['LibreOffice', 'Utilities']"

gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/LibreOffice/ name 'LibreOffice'
gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/LibreOffice/ apps \
  "['libreoffice-base.desktop','libreoffice-calc.desktop','libreoffice-draw.desktop','libreoffice-impress.desktop','libreoffice-math.desktop','libreoffice-startcenter.desktop','libreoffice-writer.desktop','libreoffice-xsltfilter.desktop']"

gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilities/ name 'Utilities'
gsettings set org.gnome.desktop.app-folders.folder:/org/gnome/desktop/app-folders/folders/Utilities/ apps \
  "['btop.desktop','nvim.desktop','org.gnome.TextEditor.desktop','org.gnome.Calculator.desktop','org.gnome.DiskUtility.desktop','org.gnome.seahorse.Application.desktop','org.gnome.FileRoller.desktop','pavucontrol.desktop','blueman-manager.desktop']"

echo "Grade de aplicativos do GNOME organizada."
