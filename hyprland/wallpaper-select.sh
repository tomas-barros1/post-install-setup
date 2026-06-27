#!/usr/bin/env bash

WALLPAPER_DIR="$HOME/Wallpapers"

if [[ ! -d "$WALLPAPER_DIR" ]]; then
    exit 1
fi

shopt -s globstar nocaseglob nullglob
IMAGES=("$WALLPAPER_DIR"/**/*.{png,jpg,jpeg,webp})

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    exit 1
fi

TMP_FILE=$(mktemp)

imv -c "bind <Return> exec echo \"\$imv_current_file\" > \"$TMP_FILE\"; quit" "${IMAGES[@]}"

SELECTION=$(cat "$TMP_FILE")
rm -f "$TMP_FILE"

if [[ -z "$SELECTION" || ! -f "$SELECTION" ]]; then
    exit 0
fi

pkill swaybg
swaybg -i "$SELECTION" -m fill &
disown
