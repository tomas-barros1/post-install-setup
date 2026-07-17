#!/usr/bin/env bash

opcoes="  Desligar
  Reiniciar"

escolha=$(echo -e "$opcoes" | walker -d)

case "$escolha" in
    *Desligar)
        systemctl poweroff
        ;;
    *Reiniciar)
        systemctl reboot
        ;;
esac
