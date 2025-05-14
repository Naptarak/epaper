cd ~/epaper_weather

cat > uninstall.sh << 'EOL'
#!/bin/bash

# E-Paper Időjárás Display Eltávolító

echo "=========================================================="
echo "     E-Paper Időjárás Display Eltávolító                  "
echo "=========================================================="

# Szolgáltatás leállítása és letiltása
echo "[1/3] Szolgáltatás leállítása és eltávolítása..."
sudo systemctl stop weather_display.service
sudo systemctl disable weather_display.service
sudo rm /etc/systemd/system/weather_display.service
sudo systemctl daemon-reload

# Kijelző tisztítása és alvó módba helyezése
echo "[2/3] E-Paper kijelző tisztítása..."
cd ~/epaper_weather
if [ -f "venv/bin/python" ]; then
    source venv/bin/activate
    python3 - << 'EOPY'
import sys, os

# Waveshare e-Paper modul betöltése
sys.path.append('e-Paper/RaspberryPi_JetsonNano/python/lib')
try:
    from waveshare_epd import epd4in01f
    epd = epd4in01f.EPD()
    epd.init()
    epd.Clear()
    epd.sleep()
    print("E-Paper kijelző sikeresen tisztítva és alvó módba helyezve.")
except Exception as e:
    print(f"Hiba a kijelző tisztítása során: {e}")
EOPY
fi

# Fájlok törlése
echo "[3/3] Telepített fájlok törlése..."
rm -rf ~/epaper_weather

echo "=========================================================="
echo "     Eltávolítás befejezve!                              "
echo "     Az időjárás alkalmazás eltávolítva a rendszerről.    "
echo "=========================================================="
EOL

chmod +x uninstall.sh
