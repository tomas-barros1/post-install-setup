#!/bin/bash
# ==============================================================================
# set-catppuccin-theme.sh - Aplica o tema Catppuccin Mocha no GNOME
#
# Adaptação "Arch" do sistema de temas do Omakub, porém fixo no Catppuccin Mocha
# (sem troca de tema). Aplica o tema GTK, o pacote de ícones e a cor de destaque.
# ==============================================================================

if ! command -v gsettings &>/dev/null; then
  echo "gsettings não encontrado; pulando tema." >&2
  exit 0
fi

# Modo escuro
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

# --- Tema GTK: detecta o nome instalado do Catppuccin Mocha ------------------
gtk_theme=""
for d in /usr/share/themes/Catppuccin-Mocha*; do
  [ -d "$d" ] && gtk_theme="$(basename "$d")" && break
done
if [ -n "$gtk_theme" ]; then
  gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
  echo "Tema GTK: $gtk_theme"
else
  echo "Aviso: tema 'Catppuccin-Mocha*' não encontrado em /usr/share/themes (instale catppuccin-gtk-theme-mocha)." >&2
fi

# --- Ícones: Tela-circle (roxo para combinar com o Mocha) --------------------
for icon_theme in "Tela-circle-purple" "Tela-circle-purple-dark" "Tela-circle"; do
  if [ -d "/usr/share/icons/$icon_theme" ]; then
    gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
    echo "Tema de ícones: $icon_theme"
    break
  fi
done

# --- Cor de destaque do GNOME (GNOME 47+) -----------------------------------
gsettings set org.gnome.desktop.interface accent-color 'purple' 2>/dev/null || true

echo "Tema Catppuccin Mocha aplicado."
