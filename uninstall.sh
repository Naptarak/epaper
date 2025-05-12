#!/bin/bash

# uninstall.sh - Eltávolító szkript e-paper weblap megjelenítőhöz
# Raspberry Pi Zero 2W + Waveshare 4.01 inch HAT (F) e-paper kijelzőhöz

set -e  # Kilépés hiba esetén
LOG_FILE="uninstall_log.txt"
echo "Eltávolítás indítása: $(date)" | tee -a "$LOG_FILE"

# Hibakezelő függvény
handle_error() {
    echo "HIBA: $1" | tee -a "$LOG_FILE"
    echo "További részletek: $LOG_FILE"
    exit 1
}

# Sikeres végrehajtás ellenőrzése
check_success() {
    if [ $? -ne 0 ]; then
        handle_error "$1"
    fi
}

# Telepítési könyvtár
INSTALL_DIR="/opt/epaper-display"

# Szolgáltatás leállítása és letiltása
echo "Szolgáltatás leállítása és letiltása..." | tee -a "$LOG_FILE"
if systemctl is-active --quiet epaper-display.service; then
    sudo systemctl stop epaper-display.service 2>> "$LOG_FILE"
    check_success "Nem sikerült leállítani a szolgáltatást"
fi

if systemctl is-enabled --quiet epaper-display.service 2>/dev/null; then
    sudo systemctl disable epaper-display.service 2>> "$LOG_FILE"
    check_success "Nem sikerült letiltani a szolgáltatást"
fi

# Szolgáltatásfájl eltávolítása
echo "Szolgáltatásfájl eltávolítása..." | tee -a "$LOG_FILE"
if [ -f /etc/systemd/system/epaper-display.service ]; then
    sudo rm /etc/systemd/system/epaper-display.service 2>> "$LOG_FILE"
    check_success "Nem sikerült eltávolítani a szolgáltatásfájlt"
    sudo systemctl daemon-reload 2>> "$LOG_FILE"
fi

# rc.local tisztítása
echo "rc.local tisztítása..." | tee -a "$LOG_FILE"
if [ -f /etc/rc.local ]; then
    if grep -q "$INSTALL_DIR/display_webpage.py" /etc/rc.local; then
        # Eltávolítjuk a szkript indítására vonatkozó sort
        sudo sed -i "\|$INSTALL_DIR/display_webpage.py|d" /etc/rc.local
        # Eltávolítjuk a kommentet is
        sudo sed -i "/# E-paper kijelző indítása/d" /etc/rc.local
        check_success "Nem sikerült kitisztítani az rc.local fájlt"
    fi
fi

# Kényelmi szkriptek eltávolítása
echo "Kényelmi szkriptek eltávolítása..." | tee -a "$LOG_FILE"
for script in epaper-config epaper-service epaper-logs; do
    if [ -f /usr/local/bin/$script ]; then
        sudo rm /usr/local/bin/$script 2>> "$LOG_FILE"
        check_success "Nem sikerült eltávolítani a(z) $script szkriptet"
    fi
done

# Log fájlok eltávolítása
echo "Log fájlok eltávolítása..." | tee -a "$LOG_FILE"
sudo rm -f /var/log/epaper-display*.log 2>> "$LOG_FILE" || true
echo "Log fájlok eltávolítva" | tee -a "$LOG_FILE"

# Telepítési könyvtár eltávolítása
echo "Telepítési könyvtár eltávolítása..." | tee -a "$LOG_FILE"
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR" 2>> "$LOG_FILE"
    check_success "Nem sikerült eltávolítani a telepítési könyvtárat"
fi

# Futó háttérfolyamatok leállítása
echo "Futó háttérfolyamatok leállítása..." | tee -a "$LOG_FILE"
# Kijelzőhöz kapcsolódó folyamatok
sudo pkill -f "display_webpage.py" 2>/dev/null || true
# Xvfb és böngésző folyamatok
sudo pkill -f "Xvfb" 2>/dev/null || true
sudo pkill -f "midori" 2>/dev/null || true
sudo pkill -f "wkhtmltoimage" 2>/dev/null || true
sudo pkill -f "cutycapt" 2>/dev/null || true

# Python függőségek eltávolításának kérdezése
echo "El szeretnéd távolítani a Python függőségeket (RPi.GPIO, spidev)? (y/n)"
read remove_deps

if [ "$remove_deps" = "y" ] || [ "$remove_deps" = "Y" ]; then
    echo "Python függőségek eltávolítása..." | tee -a "$LOG_FILE"
    sudo pip3 uninstall -y RPi.GPIO spidev 2>> "$LOG_FILE" || true
    echo "A függőségek lehet, hogy eltávolításra kerültek. Előfordulhat, hogy néhányat más alkalmazások még használnak." | tee -a "$LOG_FILE"
else
    echo "Python függőségek eltávolításának kihagyása." | tee -a "$LOG_FILE"
fi

# SPI letiltásának kérdezése
echo "Le szeretnéd tiltani az SPI interfészt? (y/n)"
read disable_spi

if [ "$disable_spi" = "y" ] || [ "$disable_spi" = "Y" ]; then
    echo "SPI interfész letiltása..." | tee -a "$LOG_FILE"
    sudo sed -i '/dtparam=spi=on/d' /boot/config.txt 2>> "$LOG_FILE"
    check_success "Nem sikerült letiltani az SPI interfészt"
    echo "SPI interfész letiltva. A változás érvénybe lépéséhez újraindítás szükséges." | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=true
else
    echo "SPI interfész engedélyezve marad." | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=false
fi

# Ideiglenes könyvtárak tisztítása
echo "Ideiglenes könyvtárak tisztítása..." | tee -a "$LOG_FILE"
if [ -d "/tmp/screenshot" ]; then
    sudo rm -rf /tmp/screenshot 2>> "$LOG_FILE" || true
fi

# Maradványok ellenőrzése és figyelmeztetés
echo "Maradványok ellenőrzése..." | tee -a "$LOG_FILE"
remaining_files=$(find /usr/local/bin -name "epaper-*" 2>/dev/null || true)
if [ -n "$remaining_files" ]; then
    echo "Figyelmeztetés: Az alábbi szkriptek még mindig jelen vannak:" | tee -a "$LOG_FILE"
    echo "$remaining_files" | tee -a "$LOG_FILE"
    echo "Manuálisan eltávolíthatod őket: sudo rm [fájl neve]" | tee -a "$LOG_FILE"
fi

# Összefoglaló
echo "" | tee -a "$LOG_FILE"
echo "Eltávolítási összefoglaló:" | tee -a "$LOG_FILE"
echo "======================" | tee -a "$LOG_FILE"
echo "Eltávolított telepítési könyvtár: $INSTALL_DIR" | tee -a "$LOG_FILE"
echo "Eltávolított szolgáltatás: epaper-display.service" | tee -a "$LOG_FILE"
echo "Eltávolított szkriptek: epaper-config, epaper-service, epaper-logs" | tee -a "$LOG_FILE"
echo "Eltávolított logfájlok: /var/log/epaper-display*.log" | tee -a "$LOG_FILE"
echo "Tisztított rc.local fájl" | tee -a "$LOG_FILE"

if [ "$REBOOT_REQUIRED" = true ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Az eltávolítás befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Eltávolítás befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"