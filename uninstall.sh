#!/bin/bash

set -e

APPDIR="/home/pi/weather-epaper"
SERVICE_FILE="/etc/systemd/system/weather-epaper.service"

echo "Szolgáltatás leállítása és törlése..."
sudo systemctl stop weather-epaper.service || true
sudo systemctl disable weather-epaper.service || true
sudo rm -f "$SERVICE_FILE"
sudo systemctl daemon-reload

echo "Alkalmazás törlése..."
rm -rf "$APPDIR"

echo "Eltávolítás kész!"
