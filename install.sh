#!/bin/bash

# install_7color.sh - Speciális telepítő szkript 7-színű Waveshare 4.01 inch HAT (F) kijelzőhöz
# Készítve: 2025.05.13

set -e  # Kilépés hiba esetén
LOG_FILE="install_7color_log.txt"
echo "7-színű e-Paper telepítés indítása: $(date)" | tee -a "$LOG_FILE"

# Aktuális felhasználó azonosítása
CURRENT_USER=$(whoami)
echo "Aktuális felhasználó: $CURRENT_USER" | tee -a "$LOG_FILE"

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

# Korábbi telepítés eltávolítása (ha létezik)
echo "Korábbi telepítés ellenőrzése és eltávolítása..." | tee -a "$LOG_FILE"

# Szolgáltatás leállítása
if systemctl is-active --quiet epaper-display.service; then
    echo "Futó szolgáltatás leállítása..." | tee -a "$LOG_FILE"
    sudo systemctl stop epaper-display.service 2>> "$LOG_FILE" || true
fi

# Szolgáltatás letiltása
if systemctl is-enabled --quiet epaper-display.service 2>/dev/null; then
    echo "Szolgáltatás letiltása..." | tee -a "$LOG_FILE"
    sudo systemctl disable epaper-display.service 2>> "$LOG_FILE" || true
fi

# Szolgáltatásfájl eltávolítása
if [ -f /etc/systemd/system/epaper-display.service ]; then
    echo "Szolgáltatásfájl eltávolítása..." | tee -a "$LOG_FILE"
    sudo rm /etc/systemd/system/epaper-display.service 2>> "$LOG_FILE" || true
    sudo systemctl daemon-reload 2>> "$LOG_FILE" || true
fi

# Kényelmi szkriptek eltávolítása
echo "Kényelmi szkriptek eltávolítása (ha léteznek)..." | tee -a "$LOG_FILE"
for script in epaper-config epaper-service epaper-logs; do
    if [ -f /usr/local/bin/$script ]; then
        sudo rm /usr/local/bin/$script 2>> "$LOG_FILE" || true
    fi
done

# Futó háttérfolyamatok leállítása
echo "Futó háttérfolyamatok ellenőrzése..." | tee -a "$LOG_FILE"
sudo pkill -f "display_webpage.py" 2>/dev/null || true
sudo pkill -f "Xvfb" 2>/dev/null || true
sudo pkill -f "midori" 2>/dev/null || true
sudo pkill -f "wkhtmltoimage" 2>/dev/null || true
sudo pkill -f "cutycapt" 2>/dev/null || true

# Ideiglenes könyvtárak tisztítása
echo "Ideiglenes könyvtárak tisztítása..." | tee -a "$LOG_FILE"
sudo rm -rf /tmp/screenshot 2>/dev/null || true
sudo rm -rf /tmp/waveshare-install 2>/dev/null || true

# Telepítési könyvtár tisztítása
INSTALL_DIR="/opt/epaper-display"
if [ -d "$INSTALL_DIR" ]; then
    echo "Korábbi telepítési könyvtár eltávolítása: $INSTALL_DIR" | tee -a "$LOG_FILE"
    sudo rm -rf "$INSTALL_DIR" 2>> "$LOG_FILE" || true
fi

# Új könyvtár létrehozása
echo "Új telepítési könyvtár létrehozása: $INSTALL_DIR" | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a telepítési könyvtárat"

# Jogosultságok beállítása
sudo chown $CURRENT_USER:$CURRENT_USER "$INSTALL_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült beállítani a jogosultságokat"

# Python verzió ellenőrzése
echo "Python telepítés ellenőrzése..." | tee -a "$LOG_FILE"
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    echo "Python nem található, telepítési kísérlet..." | tee -a "$LOG_FILE"
    sudo apt-get update && sudo apt-get install -y python3 python3-pip 2>> "$LOG_FILE"
    check_success "Nem sikerült telepíteni a Python-t"
    PYTHON_CMD="python3"
fi

echo "Python parancs: $PYTHON_CMD" | tee -a "$LOG_FILE"
$PYTHON_CMD --version | tee -a "$LOG_FILE"

# Rendszerfrissítés
echo "Rendszerfrissítés..." | tee -a "$LOG_FILE"
sudo apt-get update 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a csomaglistákat"

# Szükséges rendszercsomagok telepítése
echo "Szükséges rendszercsomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-pip python3-venv git 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni az alapvető csomagokat"

# SPI és GPIO modulok telepítése
echo "SPI és GPIO modulok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-rpi.gpio python3-spidev 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni az SPI és GPIO modulokat"

# Pillow és NumPy telepítése
echo "Pillow és NumPy telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-pil python3-numpy 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni a képfeldolgozási modulokat"

# Weboldal megjelenítés csomagok telepítése
echo "Weboldal megjelenítéshez szükséges csomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y xvfb scrot 2>> "$LOG_FILE" || true
if ! sudo apt-get install -y wkhtmltopdf 2>> "$LOG_FILE"; then
    echo "wkhtmltopdf telepítése sikertelen, alternatív módszer megpróbálása..." | tee -a "$LOG_FILE"
    sudo apt-get install -y cutycapt 2>> "$LOG_FILE" || echo "cutycapt telepítése is sikertelen" | tee -a "$LOG_FILE"
fi

# Virtuális környezet könyvtára
VENV_DIR="${INSTALL_DIR}/venv"

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása: $VENV_DIR" | tee -a "$LOG_FILE"
$PYTHON_CMD -m venv "$VENV_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a virtuális környezetet"

# Jogosultságok beállítása a virtuális környezethez
echo "Jogosultságok beállítása a virtuális környezethez..." | tee -a "$LOG_FILE"
sudo chown -R $CURRENT_USER:$CURRENT_USER "$VENV_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült beállítani a jogosultságokat a virtuális környezethez"

# Python függőségek telepítése a virtuális környezetbe
echo "Python függőségek telepítése a virtuális környezetbe..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install --upgrade pip 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a pip-et"

# Telepítjük a szükséges függőségeket
echo "Szükséges Python csomagok telepítése..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install pillow numpy RPi.GPIO spidev 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni a szükséges Python csomagokat"

# Könyvtárstruktúra létrehozása
echo "Könyvtárstruktúra létrehozása..." | tee -a "$LOG_FILE"
mkdir -p "$INSTALL_DIR/lib/waveshare_epd" 2>> "$LOG_FILE"
mkdir -p "$INSTALL_DIR/examples" 2>> "$LOG_FILE"
touch "$INSTALL_DIR/lib/__init__.py"
touch "$INSTALL_DIR/lib/waveshare_epd/__init__.py"

# SPI interfész engedélyezése
echo "SPI interfész engedélyezése..." | tee -a "$LOG_FILE"
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    echo "SPI nincs engedélyezve, engedélyezés..." | tee -a "$LOG_FILE"
    sudo sh -c "echo 'dtparam=spi=on' >> /boot/config.txt" 2>> "$LOG_FILE"
    check_success "Nem sikerült engedélyezni az SPI interfészt"
    echo "SPI engedélyezve, újraindítás szükséges lesz" | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=true
else
    echo "SPI már engedélyezve van" | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=false
fi

# Speciális epdconfig.py modul létrehozása a 7-színű kijelzőhöz
echo "epdconfig.py létrehozása a 7-színű kijelzőhöz..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import os
import logging
import sys
import time

# GPIO Pin definíciók a 7-színű kijelzőhöz
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

class RaspberryPi:
    def __init__(self):
        import RPi.GPIO
        import spidev
        self.GPIO = RPi.GPIO
        self.SPI = spidev.SpiDev()

    def digital_write(self, pin, value):
        self.GPIO.output(pin, value)

    def digital_read(self, pin):
        return self.GPIO.input(pin)

    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)

    def spi_writebyte(self, data):
        self.SPI.writebytes(data)

    def spi_writebyte2(self, data):
        self.SPI.writebytes2(data)

    def module_init(self):
        self.GPIO.setmode(self.GPIO.BCM)
        self.GPIO.setwarnings(False)
        self.GPIO.setup(RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(BUSY_PIN, self.GPIO.IN)
        
        # SPI eszköz inicializálása
        self.SPI.open(0, 0)
        self.SPI.max_speed_hz = 4000000
        self.SPI.mode = 0b00
        return 0

    def module_exit(self):
        logging.debug("spi end")
        self.SPI.close()
        self.GPIO.output(RST_PIN, 0)
        self.GPIO.output(DC_PIN, 0)
        self.GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])

# Raspberry Pi inicializálása
implementation = RaspberryPi()

# Függvények exportálása modulszintre
for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))

# Pin konstansok exportálása
BUSY_PIN = 24
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
EOF

# Speciális epd4in01f.py modul létrehozása a 7-színű kijelzőhöz
echo "epd4in01f.py létrehozása a 7-színű kijelzőhöz..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/lib/waveshare_epd/epd4in01f.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import logging
import time
from PIL import Image

# epdconfig
import epdconfig

class EPD:
    # Display resolution
    WIDTH = 640
    HEIGHT = 400
    
    # Display colors
    BLACK = 0x000000
    WHITE = 0xffffff
    GREEN = 0x00ff00
    BLUE = 0x0000ff
    RED = 0xff0000
    YELLOW = 0xffff00
    ORANGE = 0xffa500
    
    # Command constants
    PANEL_SETTING = 0x00
    POWER_SETTING = 0x01
    POWER_OFF = 0x02
    POWER_OFF_SEQUENCE = 0x03
    POWER_ON = 0x04
    POWER_ON_MEASURE = 0x05
    BOOSTER_SOFT_START = 0x06
    DEEP_SLEEP = 0x07
    DATA_START_TRANSMISSION_1 = 0x10
    DATA_STOP = 0x11
    DISPLAY_REFRESH = 0x12
    
    def __init__(self):
        self.width = self.WIDTH
        self.height = self.HEIGHT
        self.colors = {
            0: self.BLACK,
            1: self.WHITE,
            2: self.GREEN,
            3: self.BLUE,
            4: self.RED,
            5: self.YELLOW,
            6: self.ORANGE
        }
        
    def init(self):
        if epdconfig.module_init() != 0:
            return -1
        
        # 7-színű e-Paper kijelző inicializálása
        self.reset()
        
        self.send_command(self.POWER_SETTING)
        self.send_data(0x07)
        self.send_data(0x07)
        self.send_data(0x3f)
        self.send_data(0x3f)
        
        self.send_command(self.POWER_ON)
        self.wait_until_idle()
        
        self.send_command(self.PANEL_SETTING)
        self.send_data(0x0f)
        
        logging.info("7-színű e-Paper inicializálás sikeres")
        return 0

    def wait_until_idle(self):
        logging.debug("Várakozás a kijelző BUSY jelére...")
        while epdconfig.digital_read(epdconfig.BUSY_PIN) == 0:
            epdconfig.delay_ms(100)
        logging.debug("Kijelző kész")

    def reset(self):
        logging.debug("Kijelző reset...")
        epdconfig.digital_write(epdconfig.RST_PIN, 1)
        epdconfig.delay_ms(200) 
        epdconfig.digital_write(epdconfig.RST_PIN, 0)
        epdconfig.delay_ms(10)
        epdconfig.digital_write(epdconfig.RST_PIN, 1)
        epdconfig.delay_ms(200)   

    def send_command(self, command):
        epdconfig.digital_write(epdconfig.DC_PIN, 0)
        epdconfig.digital_write(epdconfig.CS_PIN, 0)
        epdconfig.spi_writebyte([command])
        epdconfig.digital_write(epdconfig.CS_PIN, 1)

    def send_data(self, data):
        epdconfig.digital_write(epdconfig.DC_PIN, 1)
        epdconfig.digital_write(epdconfig.CS_PIN, 0)
        epdconfig.spi_writebyte([data])
        epdconfig.digital_write(epdconfig.CS_PIN, 1)
        
    def display(self, image):
        """
        A 7-színű e-Paper kijelző képének megjelenítése
        """
        logging.debug("Kép megjelenítése a 7-színű kijelzőn")
        if isinstance(image, str):
            logging.debug("Kép betöltése fájlból: %s", image)
            image = Image.open(image)
        
        # Ellenőrizzük, hogy RGB módban van-e a kép
        if image.mode != 'RGB':
            logging.debug("Kép konvertálása RGB-re")
            image = image.convert('RGB')
        
        # Átméretezés a kijelző felbontására, ha szükséges
        if image.width != self.width or image.height != self.height:
            logging.debug("Kép átméretezése: %sx%s -> %sx%s", 
                          image.width, image.height, self.width, self.height)
            image = image.resize((self.width, self.height))
        
        # Adat küldése a kijelzőnek
        self.send_command(self.DATA_START_TRANSMISSION_1)
        
        # Képadatok feldolgozása és küldése
        pixels = image.load()
        for y in range(self.height):
            for x in range(self.width):
                r, g, b = pixels[x, y]
                # Színek egyszerű megfeleltetése a 7 színhez
                if r == 0 and g == 0 and b == 0:  # Fekete
                    self.send_data(0x00)
                elif r == 255 and g == 255 and b == 255:  # Fehér
                    self.send_data(0x01)
                elif r == 0 and g == 255 and b == 0:  # Zöld
                    self.send_data(0x02)
                elif r == 0 and g == 0 and b == 255:  # Kék
                    self.send_data(0x03)
                elif r == 255 and g == 0 and b == 0:  # Piros
                    self.send_data(0x04)
                elif r == 255 and g == 255 and b == 0:  # Sárga 
                    self.send_data(0x05)
                elif r == 255 and g >= 165 and b == 0:  # Narancs
                    self.send_data(0x06)
                else:
                    # Ha a szín nem közvetlen megfelelő, használjuk a legközelebbi 7 színt
                    self.send_data(0x01)  # Alapértelmezetten fehér
        
        # Kijelző frissítése
        self.send_command(self.DISPLAY_REFRESH)
        self.wait_until_idle()
        
        logging.debug("Kép megjelenítve a 7-színű kijelzőn")
        return 0
        
    def getbuffer(self, image):
        """
        A kép előkészítése a kijelzőhöz
        """
        # A 7-színű kijelző esetén egyszerűen visszaadjuk az eredeti képet
        return image
    
    def sleep(self):
        """
        Kijelző alvó módba helyezése
        """
        logging.debug("Alvó mód aktiválása")
        self.send_command(self.POWER_OFF)
        self.wait_until_idle()
        self.send_command(self.DEEP_SLEEP)
        self.send_data(0xA5)
        
    def Clear(self, color=0xFF):
        """
        Kijelző törlése adott színre (alapértelmezetten fehér)
        """
        logging.debug("Kijelző törlése")
        # Fehér képet hozunk létre és azt jelenítjük meg
        image = Image.new('RGB', (self.width, self.height), 'white')
        self.display(image)
EOF

# Teszt szkript létrehozása a 7-színű kijelző teszteléséhez
echo "Teszt szkript létrehozása a 7-színű kijelzőhöz..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/test_7color_display.py" << EOF
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import logging
from PIL import Image, ImageDraw, ImageFont

# Logging beállítása
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/epaper-test.log')
    ]
)

logging.info("7-színű E-Paper teszt program indítása")
logging.info("Python verzió: %s", sys.version)

# Elérési útvonal beállítása
lib_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib')
sys.path.append(lib_dir)
logging.info("Lib könyvtár hozzáadva: %s", lib_dir)

waveshare_dir = os.path.join(lib_dir, 'waveshare_epd')
sys.path.append(waveshare_dir)
logging.info("Waveshare könyvtár hozzáadva: %s", waveshare_dir)

# Elérhető modulok kilistázása
logging.info("Elérhető modulok a lib/waveshare_epd könyvtárban:")
for file in os.listdir(waveshare_dir):
    if file.endswith('.py'):
        logging.info("  - %s", file)

try:
    # Modul importálása
    logging.info("epdconfig importálása...")
    import epdconfig
    logging.info("epdconfig sikeresen importálva")
    
    logging.info("epd4in01f importálása...")
    import epd4in01f
    logging.info("epd4in01f sikeresen importálva")
    
    # Kijelző inicializálása
    logging.info("E-Paper objektum létrehozása...")
    epd = epd4in01f.EPD()
    logging.info("E-Paper objektum sikeresen létrehozva")
    
    logging.info("Kijelző méretei: %d x %d", epd.width, epd.height)
    
    # Kijelző inicializálása
    logging.info("Kijelző inicializálása...")
    epd.init()
    logging.info("Kijelző inicializálása sikeres")
    
    # Kijelző törlése
    logging.info("Kijelző törlése...")
    epd.Clear()
    logging.info("Kijelző törölve")
    
    # 7-színű teszt kép létrehozása
    logging.info("7-színű teszt kép létrehozása...")
    image = Image.new('RGB', (epd.width, epd.height), 'white')
    draw = ImageDraw.Draw(image)
    
    # Betűtípus betöltése
    font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    if os.path.exists(font_path):
        font_large = ImageFont.truetype(font_path, 40)
        font_medium = ImageFont.truetype(font_path, 30)
        font_small = ImageFont.truetype(font_path, 24)
    else:
        # Ha nincs betűtípus, használjuk az alapértelmezettet
        font_large = ImageFont.load_default()
        font_medium = ImageFont.load_default()
        font_small = ImageFont.load_default()
    
    # Főcím kirajzolása
    draw.text((50, 40), '7-színű E-Paper teszt', fill='black', font=font_large)
    draw.text((50, 100), 'Sikeres inicializálás!', fill='red', font=font_medium)
    
    # Színtesztek
    colors = [
        ('Fekete', (0, 0, 0)),
        ('Fehér', (255, 255, 255)),
        ('Piros', (255, 0, 0)),
        ('Zöld', (0, 255, 0)),
        ('Kék', (0, 0, 255)),
        ('Sárga', (255, 255, 0)),
        ('Narancs', (255, 165, 0))
    ]
    
    y_pos = 160
    for i, (color_name, color) in enumerate(colors):
        # Színes téglalap rajzolása
        draw.rectangle([(50, y_pos), (150, y_pos + 30)], fill=color)
        
        # Színnév kiírása
        text_color = 'black' if color_name in ['Fehér', 'Sárga', 'Zöld', 'Narancs'] else 'white'
        draw.text((160, y_pos + 5), color_name, fill='black', font=font_small)
        
        y_pos += 35
    
    # Telepítés dátuma
    draw.text((50, 350), 'Telepítés dátuma: $(date +%Y-%m-%d)', fill='blue', font=font_small)
    
    # Kép megjelenítése
    logging.info("Kép megjelenítése a kijelzőn...")
    epd.display(image)
    logging.info("Kép sikeresen megjelenítve")
    
    # Alvó mód
    logging.info("Alvó mód aktiválása...")
    epd.sleep()
    logging.info("Alvó mód aktiválva")
    
    logging.info("Teszt sikeresen befejezve")
    print("Teszt sikeresen lefutott! A kijelző 7 színnel működik!")
    
except ImportError as e:
    logging.error("Importálási hiba: %s", str(e))
    print(f"Importálási hiba: {e}")
    print("Ellenőrizd a log fájlt: /var/log/epaper-test.log")
    sys.exit(1)
except Exception as e:
    logging.error("Hiba történt: %s", str(e), exc_info=True)
    print(f"Hiba történt: {e}")
    print("Ellenőrizd a log fájlt: /var/log/epaper-test.log")
    sys.exit(1)
EOF

# Weboldal megjelenítő szkript létrehozása
echo "Weboldal megjelenítő szkript létrehozása..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/display_webpage.py" << EOF
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import subprocess
import logging
import traceback
from PIL import Image, ImageDraw, ImageFont

# Logging beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/epaper-display.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('epaper-display')

# Elérési útvonalak beállítása
lib_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib')
sys.path.append(lib_dir)
logger.info("Lib könyvtár hozzáadva: %s", lib_dir)

waveshare_dir = os.path.join(lib_dir, 'waveshare_epd')
sys.path.append(waveshare_dir)
logger.info("Waveshare könyvtár hozzáadva: %s", waveshare_dir)

# Weboldal URL meghatározása
WEBPAGE_URL = "http://example.com"  # Cseréld ki a kívánt URL-re

# Várakozás a hálózati kapcsolatra
def wait_for_network():
    max_attempts = 30  # Max 5 perc (30 * 10 másodperc)
    attempts = 0
    
    logger.info("Várakozás a hálózati kapcsolat elérhetőségére...")
    
    while attempts < max_attempts:
        try:
            result = subprocess.run(
                ["ping", "-c", "1", "8.8.8.8"], 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                timeout=5
            )
            if result.returncode == 0:
                logger.info("Hálózat elérhető")
                return True
        except Exception as e:
            logger.warning(f"Ping hiba: {e}")
        
        logger.info(f"Hálózat még nem elérhető, várakozás... ({attempts+1}/{max_attempts})")
        attempts += 1
        time.sleep(10)
    
    logger.error("Nem sikerült kapcsolódni a hálózathoz az időkorláton belül")
    return False

# E-paper inicializálása
def initialize_epd():
    try:
        logger.info("epdconfig importálása...")
        import epdconfig
        logger.info("epdconfig sikeresen importálva")
        
        logger.info("epd4in01f importálása...")
        import epd4in01f
        logger.info("epd4in01f sikeresen importálva")
        
        logger.info("E-Paper objektum létrehozása...")
        epd = epd4in01f.EPD()
        logger.info("E-Paper objektum sikeresen létrehozva")
        
        logger.info("Kijelző méretei: %d x %d", epd.width, epd.height)
        
        # Kijelző inicializálása
        logger.info("Kijelző inicializálása...")
        epd.init()
        logger.info("Kijelző inicializálása sikeres")
        
        return epd
    except Exception as e:
        logger.error(f"Hiba a kijelző inicializálásakor: {e}")
        logger.error(traceback.format_exc())
        raise

def capture_webpage():
    """Weboldal képernyőkép készítése különböző módszerekkel."""
    try:
        # Képernyőkép könyvtár létrehozása ha nem létezik
        screenshot_dir = '/tmp/screenshot'
        os.makedirs(screenshot_dir, exist_ok=True)
        
        # Képernyőkép fájl útvonala
        screenshot_path = f"{screenshot_dir}/webpage.png"
        
        # Először a wkhtmltoimage-t próbáljuk
        if os.path.exists("/usr/bin/wkhtmltoimage") or os.path.exists("/usr/local/bin/wkhtmltoimage"):
            logger.info("wkhtmltoimage használata...")
            command = f"xvfb-run -a wkhtmltoimage --width 640 --height 400 {WEBPAGE_URL} {screenshot_path}"
            subprocess.run(command, shell=True, check=True)
            return screenshot_path
        
        # Cutycapt mint tartalék
        elif os.path.exists("/usr/bin/cutycapt") or os.path.exists("/usr/local/bin/cutycapt"):
            logger.info("cutycapt használata...")
            command = f"xvfb-run -a cutycapt --url={WEBPAGE_URL} --out={screenshot_path} --min-width=640 --min-height=400"
            subprocess.run(command, shell=True, check=True)
            return screenshot_path
        
        # Végső tartalék: Midori ha elérhető
        elif os.path.exists("/usr/bin/midori"):
            logger.info("Midori használata...")
            display_num = 99
            subprocess.run(f"Xvfb :{display_num} -screen 0 640x400x24 &", shell=True, check=True)
            time.sleep(2)  # Időt adunk az Xvfb indulásához
            
            # Display környezeti változó beállítása
            os.environ['DISPLAY'] = f":{display_num}"
            
            # Midori használata az oldal betöltéséhez és scrot a képernyőképhez
            if os.path.exists("/usr/bin/scrot") or os.path.exists("/usr/local/bin/scrot"):
                midori_proc = subprocess.Popen(
                    f"midori --display=:{display_num} -e Fullscreen -a {WEBPAGE_URL}",
                    shell=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )
                time.sleep(10)  # Várakozás az oldal betöltésére
                subprocess.run(f"DISPLAY=:{display_num} scrot {screenshot_path}", shell=True, check=True)
                midori_proc.terminate()
                subprocess.run(f"pkill -f 'Xvfb :{display_num}'", shell=True)
                return screenshot_path
            else:
                raise Exception("scrot nincs telepítve")
        
        else:
            raise Exception("Nem található támogatott web képernyőkép készítő eszköz")
            
    except Exception as e:
        logger.error(f"Hiba a weboldal képernyőkép készítésekor: {e}")
        logger.error(traceback.format_exc())
        # Próbáljuk megtisztítani a fennmaradt folyamatokat
        try:
            subprocess.run("pkill Xvfb", shell=True)
            subprocess.run("pkill midori", shell=True)
        except:
            pass
        return None

def display_image(epd, image_path):
    """Kép megjelenítése az e-paper kijelzőn."""
    try:
        image = Image.open(image_path)
        
        # Átméretezés a kijelző méretére
        image = image.resize((epd.width, epd.height))
        
        # Megjelenítés az e-paper kijelzőn
        logger.info("Kép megjelenítése a kijelzőn...")
        epd.display(image)
        logger.info("Kép sikeresen megjelenítve")
        return True
    except Exception as e:
        logger.error(f"Hiba a kép megjelenítésekor: {e}")
        logger.error(traceback.format_exc())
        return False

def display_error_message(epd, message):
    """Hibaüzenet megjelenítése a kijelzőn"""
    try:
        # Kép létrehozása
        image = Image.new('RGB', (epd.width, epd.height), 'white')
        draw = ImageDraw.Draw(image)
        
        # Betűtípus betöltése
        font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
        if os.path.exists(font_path):
            font_large = ImageFont.truetype(font_path, 30)
            font_small = ImageFont.truetype(font_path, 20)
        else:
            # Ha nincs betűtípus, használjuk az alapértelmezettet
            font_large = ImageFont.load_default()
            font_small = ImageFont.load_default()
        
        # Hibaüzenet kirajzolása
        draw.text((50, 50), 'HIBA!', fill='red', font=font_large)
        
        # Tördeljük a hibaüzenetet sorokra
        words = message.split()
        lines = []
        line = ""
        
        for word in words:
            test_line = line + " " + word if line else word
            if len(test_line) * 10 <= epd.width - 100:  # egyszerű becslés a szélességre
                line = test_line
            else:
                lines.append(line)
                line = word
        
        if line:
            lines.append(line)
        
        # Kirajzoljuk a sorokat
        y = 100
        for line in lines:
            draw.text((50, y), line, fill='black', font=font_small)
            y += 30
        
        # Kép megjelenítése
        epd.display(image)
        logger.info("Hibaüzenet sikeresen megjelenítve a kijelzőn")
        return True
    except Exception as e:
        logger.error(f"Hiba a hibaüzenet megjelenítésekor: {e}")
        logger.error(traceback.format_exc())
        return False

def main():
    try:
        # Várakozás a hálózati kapcsolat elérhetőségére
        if not wait_for_network():
            logger.warning("Figyelmeztetés: Hálózat nem elérhető, offline mód aktiválva")
        
        # E-paper inicializálása
        logger.info("E-paper kijelző inicializálása...")
        epd = initialize_epd()
        
        # Üdvözlő üzenet megjelenítése
        logger.info("Rendszer indulása, üdvözlő üzenet megjelenítése...")
        try:
            # Kép létrehozása
            image = Image.new('RGB', (epd.width, epd.height), 'white')
            draw = ImageDraw.Draw(image)
            
            # Betűtípus betöltése
            font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
            if os.path.exists(font_path):
                font_large = ImageFont.truetype(font_path, 30)
                font_small = ImageFont.truetype(font_path, 20)
            else:
                # Ha nincs betűtípus, használjuk az alapértelmezettet
                font_large = ImageFont.load_default()
                font_small = ImageFont.load_default()
            
            # Szöveg kirajzolása
            draw.text((epd.width//4, epd.height//3), '7-Színű E-Paper kijelző indul...', fill='blue', font=font_large)
            draw.text((epd.width//4, epd.height//2), f'URL: {WEBPAGE_URL}', fill='red', font=font_small)
            
            # Kép megjelenítése
            epd.display(image)
            logger.info("Üdvözlő üzenet megjelenítve")
            time.sleep(2)  # Rövid idő az üzenet olvasására
        except Exception as e:
            logger.error(f"Nem sikerült megjeleníteni az üdvözlő üzenetet: {e}")
            logger.error(traceback.format_exc())
        
        # Frissítési kísérlet számláló
        failed_attempts = 0
        
        # Fő ciklus
        while True:
            try:
                logger.info("Weboldal képernyőkép készítése...")
                screenshot = capture_webpage()
                
                if screenshot and os.path.exists(screenshot):
                    logger.info("Megjelenítés az e-paper kijelzőn...")
                    if display_image(epd, screenshot):
                        logger.info("Megjelenítés sikeres")
                        failed_attempts = 0  # Sikeres frissítés, nullázzuk a számlálót
                    else:
                        logger.error("Nem sikerült megjeleníteni a képet")
                        failed_attempts += 1
                        if failed_attempts >= 3:
                            display_error_message(epd, "Nem sikerült megjeleníteni a képet háromszor egymás után.")
                else:
                    logger.error("Nem sikerült képernyőképet készíteni a weboldalról")
                    failed_attempts += 1
                    if failed_attempts >= 3:
                        display_error_message(epd, "Nem sikerült képernyőképet készíteni a weboldalról háromszor egymás után.")
            except Exception as e:
                logger.error(f"Hiba a frissítési ciklusban: {e}")
                logger.error(traceback.format_exc())
                failed_attempts += 1
                if failed_attempts >= 3:
                    try:
                        display_error_message(epd, f"Ismétlődő hiba: {str(e)[:50]}...")
                    except:
                        pass
            
            # Várakozás a következő frissítés előtt
            logger.info("Várakozás 5 percig a következő frissítés előtt...")
            time.sleep(300)
            
    except KeyboardInterrupt:
        logger.info("Program leállítva a felhasználó által")
        try:
            epd.sleep()
        except:
            pass
    except Exception as e:
        logger.error(f"Nem várt hiba történt: {e}")
        logger.error(traceback.format_exc())
        # Várunk 30 másodpercet, majd újraindítjuk a programot
        time.sleep(30)
        main()  # Rekurzív újraindítás

if __name__ == "__main__":
    logger.info("Program indítása...")
    
    # Többszöri próbálkozás a program indítására
    max_restart_attempts = 5
    restart_attempts = 0
    
    while restart_attempts < max_restart_attempts:
        try:
            main()
            break  # Ha sikeresen lefutott, kilépünk a ciklusból
        except Exception as e:
            restart_attempts += 1
            logger.error(f"Program indítási hiba ({restart_attempts}/{max_restart_attempts}): {e}")
            logger.error(traceback.format_exc())
            
            if restart_attempts >= max_restart_attempts:
                logger.error("Túl sok újraindítási kísérlet, program leállítása.")
                sys.exit(1)
            
            # Exponenciális várakozás az újraindítás előtt
            wait_time = 30 * (2 ** (restart_attempts - 1))
            logger.info(f"Újraindítás {wait_time} másodperc múlva...")
            time.sleep(wait_time)
EOF

# Konfigurációs segédprogram létrehozása
echo "Konfigurációs segédprogram létrehozása..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/configure.py" << EOF
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import re

config_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), "display_webpage.py")

def update_url(new_url):
    with open(config_file, 'r') as f:
        content = f.read()
    
    # URL frissítése a fájlban
    pattern = r'WEBPAGE_URL = ".*?"'
    content = re.sub(pattern, f'WEBPAGE_URL = "{new_url}"', content)
    
    with open(config_file, 'w') as f:
        f.write(content)
    
    print(f"URL frissítve: {new_url}")
    print("Kérlek indítsd újra a szolgáltatást: sudo systemctl restart epaper-display.service")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Használat: python3 configure.py <URL>")
        sys.exit(1)
    
    new_url = sys.argv[1]
    update_url(new_url)
EOF

# Jogosultságok beállítása a szkriptekhez
echo "Szkriptek jogosultságainak beállítása..." | tee -a "$LOG_FILE"
chmod +x "$INSTALL_DIR/display_webpage.py"
chmod +x "$INSTALL_DIR/test_7color_display.py"
chmod +x "$INSTALL_DIR/configure.py"
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/display_webpage.py"
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/test_7color_display.py"
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/configure.py"

# Log könyvtárak és fájlok létrehozása
echo "Log könyvtárak és fájlok létrehozása..." | tee -a "$LOG_FILE"
sudo touch /var/log/epaper-display.log
sudo touch /var/log/epaper-display-stdout.log
sudo touch /var/log/epaper-display-stderr.log
sudo touch /var/log/epaper-test.log
sudo chown $CURRENT_USER:$CURRENT_USER /var/log/epaper-display*.log
sudo chown $CURRENT_USER:$CURRENT_USER /var/log/epaper-test.log

# Systemd szolgáltatás létrehozása
echo "Systemd szolgáltatás létrehozása..." | tee -a "$LOG_FILE"
cat > /tmp/epaper-display.service << EOF
[Unit]
Description=7-Színű E-Paper Weboldal Megjelenítő
After=network-online.target
Wants=network-online.target
DefaultDependencies=no

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python3 $INSTALL_DIR/display_webpage.py
Restart=always
RestartSec=30
TimeoutStartSec=180
StartLimitIntervalSec=600
StartLimitBurst=5

# Log fájlok készítése
StandardOutput=append:/var/log/epaper-display-stdout.log
StandardError=append:/var/log/epaper-display-stderr.log

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/epaper-display.service /etc/systemd/system/ 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a systemd szolgáltatást"

# Kényelmi parancsfájlok létrehozása
echo "Kényelmi parancsfájlok létrehozása..." | tee -a "$LOG_FILE"

# URL konfigurációs szkript
cat > /tmp/epaper-config << EOF
#!/bin/bash
$VENV_DIR/bin/python3 $INSTALL_DIR/configure.py \$1
EOF

sudo mv /tmp/epaper-config /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-config 2>> "$LOG_FILE"

# Szolgáltatáskezelő szkript
cat > /tmp/epaper-service << EOF
#!/bin/bash
case "\$1" in
    start)
        sudo systemctl start epaper-display.service
        ;;
    stop)
        sudo systemctl stop epaper-display.service
        ;;
    restart)
        sudo systemctl restart epaper-display.service
        ;;
    status)
        sudo systemctl status epaper-display.service
        ;;
    test)
        sudo $INSTALL_DIR/test_7color_display.py
        ;;
    *)
        echo "Használat: epaper-service {start|stop|restart|status|test}"
        exit 1
        ;;
esac
EOF

sudo mv /tmp/epaper-service /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-service 2>> "$LOG_FILE"

# Log megnéző szkript
cat > /tmp/epaper-logs << EOF
#!/bin/bash
case "\$1" in
    service)
        sudo journalctl -u epaper-display.service -f
        ;;
    app)
        sudo tail -f /var/log/epaper-display.log
        ;;
    stdout)
        sudo tail -f /var/log/epaper-display-stdout.log
        ;;
    stderr)
        sudo tail -f /var/log/epaper-display-stderr.log
        ;;
    test)
        sudo tail -f /var/log/epaper-test.log
        ;;
    all)
        sudo tail -f /var/log/epaper-display*.log /var/log/epaper-test.log
        ;;
    *)
        echo "Használat: epaper-logs {service|app|stdout|stderr|test|all}"
        exit 1
        ;;
esac
EOF

sudo mv /tmp/epaper-logs /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-logs 2>> "$LOG_FILE"

# Uninstall szkript létrehozása
echo "Eltávolító szkript létrehozása..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/uninstall.sh" << EOF
#!/bin/bash

# uninstall.sh - Eltávolító szkript 7-színű e-paper weblap megjelenítőhöz
# Frissítve: 2025.05.13

set -e  # Kilépés hiba esetén
LOG_FILE="uninstall_log.txt"
echo "Eltávolítás indítása: \$(date)" | tee -a "\$LOG_FILE"

# Aktuális felhasználó azonosítása
CURRENT_USER=\$(whoami)
echo "Aktuális felhasználó: \$CURRENT_USER" | tee -a "\$LOG_FILE"

# Hibakezelő függvény
handle_error() {
    echo "HIBA: \$1" | tee -a "\$LOG_FILE"
    echo "További részletek: \$LOG_FILE"
    exit 1
}

# Sikeres végrehajtás ellenőrzése
check_success() {
    if [ \$? -ne 0 ]; then
        handle_error "\$1"
    fi
}

# Telepítési könyvtár
INSTALL_DIR="/opt/epaper-display"
VENV_DIR="\${INSTALL_DIR}/venv"

# Szolgáltatás leállítása és letiltása
echo "Szolgáltatás leállítása és letiltása..." | tee -a "\$LOG_FILE"
if systemctl is-active --quiet epaper-display.service; then
    sudo systemctl stop epaper-display.service 2>> "\$LOG_FILE"
    check_success "Nem sikerült leállítani a szolgáltatást"
fi

if systemctl is-enabled --quiet epaper-display.service 2>/dev/null; then
    sudo systemctl disable epaper-display.service 2>> "\$LOG_FILE"
    check_success "Nem sikerült letiltani a szolgáltatást"
fi

# Szolgáltatásfájl eltávolítása
echo "Szolgáltatásfájl eltávolítása..." | tee -a "\$LOG_FILE"
if [ -f /etc/systemd/system/epaper-display.service ]; then
    sudo rm /etc/systemd/system/epaper-display.service 2>> "\$LOG_FILE"
    check_success "Nem sikerült eltávolítani a szolgáltatásfájlt"
    sudo systemctl daemon-reload 2>> "\$LOG_FILE"
fi

# Kényelmi szkriptek eltávolítása
echo "Kényelmi szkriptek eltávolítása..." | tee -a "\$LOG_FILE"
for script in epaper-config epaper-service epaper-logs; do
    if [ -f /usr/local/bin/\$script ]; then
        sudo rm /usr/local/bin/\$script 2>> "\$LOG_FILE"
        check_success "Nem sikerült eltávolítani a(z) \$script szkriptet"
    fi
done

# Log fájlok eltávolítása
echo "Log fájlok eltávolítása..." | tee -a "\$LOG_FILE"
sudo rm -f /var/log/epaper-display*.log 2>> "\$LOG_FILE" || true
sudo rm -f /var/log/epaper-test.log 2>> "\$LOG_FILE" || true
echo "Log fájlok eltávolítva" | tee -a "\$LOG_FILE"

# Telepítési könyvtár eltávolítása (beleértve a virtuális környezetet is)
echo "Telepítési könyvtár eltávolítása..." | tee -a "\$LOG_FILE"
if [ -d "\$INSTALL_DIR" ]; then
    echo "Virtuális környezet eltávolítása (ha létezik): \$VENV_DIR" | tee -a "\$LOG_FILE"
    # A virtuális környezet külön törlése
    if [ -d "\$VENV_DIR" ]; then
        sudo rm -rf "\$VENV_DIR" 2>> "\$LOG_FILE" || true
    fi
    
    # Ezután a teljes telepítési könyvtár törlése
    sudo rm -rf "\$INSTALL_DIR" 2>> "\$LOG_FILE"
    check_success "Nem sikerült eltávolítani a telepítési könyvtárat"
fi

# Futó háttérfolyamatok leállítása
echo "Futó háttérfolyamatok leállítása..." | tee -a "\$LOG_FILE"
# Kijelzőhöz kapcsolódó folyamatok
sudo pkill -f "display_webpage.py" 2>/dev/null || true
# Xvfb és böngésző folyamatok
sudo pkill -f "Xvfb" 2>/dev/null || true
sudo pkill -f "midori" 2>/dev/null || true
sudo pkill -f "wkhtmltoimage" 2>/dev/null || true
sudo pkill -f "cutycapt" 2>/dev/null || true

# Ideiglenes könyvtárak tisztítása
echo "Ideiglenes könyvtárak tisztítása..." | tee -a "\$LOG_FILE"
if [ -d "/tmp/screenshot" ]; then
    sudo rm -rf /tmp/screenshot 2>> "\$LOG_FILE" || true
fi
if [ -d "/tmp/waveshare-install" ]; then
    sudo rm -rf /tmp/waveshare-install 2>> "\$LOG_FILE" || true
fi

# SPI letiltásának kérdezése
echo "Le szeretnéd tiltani az SPI interfészt? (y/n)"
read disable_spi

if [ "\$disable_spi" = "y" ] || [ "\$disable_spi" = "Y" ]; then
    echo "SPI interfész letiltása..." | tee -a "\$LOG_FILE"
    sudo sed -i '/dtparam=spi=on/d' /boot/config.txt 2>> "\$LOG_FILE"
    check_success "Nem sikerült letiltani az SPI interfészt"
    echo "SPI interfész letiltva. A változás érvénybe lépéséhez újraindítás szükséges." | tee -a "\$LOG_FILE"
    REBOOT_REQUIRED=true
else
    echo "SPI interfész engedélyezve marad." | tee -a "\$LOG_FILE"
    REBOOT_REQUIRED=false
fi

# Összefoglaló
echo "" | tee -a "\$LOG_FILE"
echo "Eltávolítási összefoglaló:" | tee -a "\$LOG_FILE"
echo "======================" | tee -a "\$LOG_FILE"
echo "Eltávolított telepítési könyvtár: \$INSTALL_DIR" | tee -a "\$LOG_FILE"
echo "Eltávolított virtuális környezet: \$VENV_DIR" | tee -a "\$LOG_FILE"
echo "Eltávolított szolgáltatás: epaper-display.service" | tee -a "\$LOG_FILE"
echo "Eltávolított szkriptek: epaper-config, epaper-service, epaper-logs" | tee -a "\$LOG_FILE"
echo "Eltávolított logfájlok: /var/log/epaper-display*.log, /var/log/epaper-test.log" | tee -a "\$LOG_FILE"

if [ "\$REBOOT_REQUIRED" = true ]; then
    echo "" | tee -a "\$LOG_FILE"
    echo "Az eltávolítás befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "\$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "\$LOG_FILE"
fi

echo "" | tee -a "\$LOG_FILE"
echo "Eltávolítás befejezve: \$(date)" | tee -a "\$LOG_FILE"
echo "Részletes naplókat lásd: \$LOG_FILE" | tee -a "\$LOG_FILE"
EOF

# Az uninstall szkript futtathatóvá tétele
chmod +x "$INSTALL_DIR/uninstall.sh" 2>> "$LOG_FILE"

# Teszt szkript futtatása
echo "Teszt szkript futtatása a 7-színű kijelző ellenőrzéséhez..." | tee -a "$LOG_FILE"
echo "A teszt kiírja a kijelzőre, hogy '7-színű E-Paper teszt'"
"$INSTALL_DIR/test_7color_display.py"

# URL bekérése
echo "Kérlek add meg az URL-t, amit meg szeretnél jeleníteni:"
read url
"$VENV_DIR/bin/python3" "$INSTALL_DIR/configure.py" "$url" 2>> "$LOG_FILE"
check_success "Nem sikerült konfigurálni az URL-t"

# Szolgáltatás engedélyezése
echo "Szolgáltatás engedélyezése..." | tee -a "$LOG_FILE"
sudo systemctl daemon-reload 2>> "$LOG_FILE"
sudo systemctl enable epaper-display.service 2>> "$LOG_FILE"
check_success "Nem sikerült engedélyezni a szolgáltatást"

# Kérdezzük meg, hogy elindítsuk-e a szolgáltatást
echo "A teszt sikeresen lefutott? (y/n)"
read test_success

if [ "$test_success" = "y" ] || [ "$test_success" = "Y" ]; then
    echo "Szolgáltatás indítása..." | tee -a "$LOG_FILE"
    sudo systemctl start epaper-display.service 2>> "$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "Figyelmeztetés: Nem sikerült elindítani a szolgáltatást." | tee -a "$LOG_FILE"
        echo "A szolgáltatás állapota:" | tee -a "$LOG_FILE"
        sudo systemctl status epaper-display.service | tee -a "$LOG_FILE"
    fi
else
    echo "A szolgáltatás nem lett elindítva. Kérem ellenőrizze a kijelző beállításait." | tee -a "$LOG_FILE"
    echo "Manuálisan elindíthatja később: sudo systemctl start epaper-display.service" | tee -a "$LOG_FILE"
fi

# Összefoglaló
echo "" | tee -a "$LOG_FILE"
echo "Telepítési összefoglaló:" | tee -a "$LOG_FILE"
echo "=====================" | tee -a "$LOG_FILE"
echo "Telepítési könyvtár: $INSTALL_DIR" | tee -a "$LOG_FILE"
echo "Virtuális környezet: $VENV_DIR" | tee -a "$LOG_FILE"
echo "Felhasználó: $CURRENT_USER" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Parancssori eszközök:" | tee -a "$LOG_FILE"
echo "  epaper-config <url> - URL beállítása" | tee -a "$LOG_FILE"
echo "  epaper-service start|stop|restart|status|test - Szolgáltatás kezelése" | tee -a "$LOG_FILE"
echo "  epaper-logs service|app|stdout|stderr|test|all - Logok megtekintése" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Eltávolítás:" | tee -a "$LOG_FILE"
echo "  sudo $INSTALL_DIR/uninstall.sh" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Hibaelhárítási tippek:" | tee -a "$LOG_FILE"
echo "  1. Logok megtekintése: epaper-logs test" | tee -a "$LOG_FILE"
echo "  2. Szolgáltatás újraindítása: epaper-service restart" | tee -a "$LOG_FILE"
echo "  3. Teszt újrafuttatása: epaper-service test" | tee -a "$LOG_FILE"
echo "  4. URL módosítása: epaper-config http://uj-url.hu" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$REBOOT_REQUIRED" = true ]; then
    echo "A telepítés befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "Telepítés befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"
