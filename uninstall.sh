#!/bin/bash

# ===============================================================
# E-Paper Display Eltávolító
# Waveshare 4.01" E-Paper HAT (F) kijelző alkalmazás eltávolítása
# ===============================================================

# Színek a jobb olvashatóságért
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'

# Log funkcók
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[FIGYELEM]${NC} $1"
}

log_error() {
    echo -e "${RED}[HIBA]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}====== $1 ======${NC}"
}

INSTALL_DIR=~/epaper_display

# Ellenőrizze, hogy root jogosultság nélkül futtatják-e
if [ "$EUID" -eq 0 ]; then
    log_error "Ezt a szkriptet NE root-ként futtasd! Használd normál felhasználóként."
    exit 1
fi

clear
log_section "E-Paper Display Eltávolító"

# Megerősítés kérése
log_warn "Ez a script eltávolítja az E-Paper Display alkalmazást és minden kapcsolódó fájlt."
read -p "Biztosan folytatni szeretnéd? (y/n) " -n 1 -r
echo    # új sor
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Eltávolítás megszakítva."
    exit 0
fi

# ===================================================
# 1. Kijelző tisztítása és szolgáltatás leállítása
# ===================================================
log_section "1. Kijelző tisztítása és szolgáltatás leállítása"

# 1.1 Próbáljuk meg tisztán leállítani a kijelzőt
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/venv/bin/python" ]; then
    log_info "Kijelző tisztítása..."
    cd "$INSTALL_DIR"
    source venv/bin/activate 2>/dev/null || true
    python -c '
import sys
try:
    # Kísérlet a Waveshare könyvtár keresésére és használatára
    paths = ["e-Paper/RaspberryPi_JetsonNano/python/lib", 
            "e-Paper/RaspberryPi/python/lib", 
            "waveshare_epd"]
    
    for path in paths:
        if path not in sys.path:
            sys.path.append(path)
    
    try:
        from waveshare_epd import epd4in01f
        epd = epd4in01f.EPD()
        epd.init()
        epd.Clear()
        epd.sleep()
        print("E-Paper kijelző sikeresen leállítva.")
    except Exception as e:
        print(f"Hiba a kijelző leállításakor: {e}")
except Exception as e:
    print(f"Hiba: {e}")
' 2>/dev/null || true
fi

# 1.2 Szolgáltatás leállítása és eltávolítása
log_info "Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop epaper_display.service 2>/dev/null || true
sudo systemctl disable epaper_display.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/epaper_display.service 2>/dev/null || true
sudo systemctl daemon-reload 2>/dev/null || true
log_info "Szolgáltatás sikeresen eltávolítva."

# ===================================================
# 2. Telepítési könyvtár eltávolítása
# ===================================================
log_section "2. Telepítési könyvtár eltávolítása"

if [ -d "$INSTALL_DIR" ]; then
    log_info "Telepítési könyvtár törlése: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    log_info "Telepítési könyvtár sikeresen törölve."
else
    log_warn "A telepítési könyvtár ($INSTALL_DIR) nem található."
fi

# ===================================================
# 3. Összegzés
# ===================================================
log_section "Eltávolítás befejezve!"

log_info "Az E-Paper Display alkalmazás sikeresen eltávolítva."
log_info "Ha újra szeretnéd telepíteni, futtasd az install.sh szkriptet."

exit 0
