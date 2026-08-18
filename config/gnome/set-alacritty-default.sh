#!/usr/bin/env bash

# Make alacritty default terminal emulator
if command -v update-alternatives &>/dev/null; then
  sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty 2>/dev/null || true
fi
