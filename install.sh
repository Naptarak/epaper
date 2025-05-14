#!/bin/bash

# ===============================================================
# E-Paper Display Telepítő
# Waveshare 4.01" E-Paper HAT (F) kijelzőhöz
# Raspberry Pi Zero 2W-re optimalizálva
# ===============================================================

set -e  # Hiba esetén leáll

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
USE_DIRECT_DRIVER=false

# Ellenőrizze, hogy root jogosultság nélkül futtatják-e
if [ "$EUID" -eq 0 ]; then
    log_error "Ezt a szkriptet NE root-ként futtasd! Használd normál felhasználóként."
    exit 1
fi

clear
log_section "E-Paper Display Telepítő"
log_info "Telepítési könyvtár: $INSTALL_DIR"
log_info "Ez a telepítő beállítja a kijelzőt a Waveshare 4.01\" E-Paper HAT (F) kijelzőhöz"

# ===================================================
# 1. Előfeltételek ellenőrzése
# ===================================================
log_section "1. Előfeltételek ellenőrzése"

# 1.1 Rendszerfrissítés
log_info "Rendszerfrissítés..."
sudo apt-get update -y
# Kötelező csomagok frissítése csak
log_info "Csak a kritikus csomagok frissítése (hogy ne tartson sokáig)..."
sudo apt-get upgrade -y python3 python3-pip

# 1.2 Szükséges rendszercsomagok telepítése - JAVÍTVA
# Először az alapvető csomagokat
log_info "Alap rendszercsomagok telepítése..."
sudo apt-get install -y git python3-pip python3-rpi.gpio python3-spidev python3-gpiozero

# Már előre fordított csomagokat telepítünk, ahol lehetséges
log_info "Előre fordított Python csomagok telepítése rendszercsomagokból..."
sudo apt-get install -y python3-pil python3-numpy python3-bs4 python3-lxml python3-html5lib

# 1.3 SPI interfész ellenőrzése
log_info "SPI interfész ellenőrzése..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    log_warn "SPI interfész nincs engedélyezve. Engedélyezés..."
    sudo bash -c "echo 'dtparam=spi=on' >> /boot/config.txt"
    log_warn "A rendszert újra kell indítani az SPI aktiválásához!"
    read -p "Újraindítás most? (y/n) " -n 1 -r
    echo    # új sor
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Újraindítás..."
        sudo reboot
        exit 0
    else
        log_warn "Az SPI nem lesz aktív a telepítés során! A telepítés folytatódik, de valószínűleg nem fog működni a kijelző."
    fi
fi

# Ellenőrizzük, hogy az SPI eszköz elérhető-e
if [ ! -e /dev/spidev0.0 ]; then
    log_warn "Az SPI eszköz (/dev/spidev0.0) nem található!"
    log_warn "A telepítés folytatódik, de valószínűleg nem fog működni a kijelző."
    log_warn "Telepítés után indítsd újra a rendszert."
else
    log_info "SPI eszköz megfelelően elérhető."
fi

# ===================================================
# 2. Telepítési könyvtár létrehozása
# ===================================================
log_section "2. Telepítési könyvtár létrehozása"

# 2.1 Korábbi telepítés ellenőrzése
if [ -d "$INSTALL_DIR" ]; then
    log_warn "A telepítési könyvtár ($INSTALL_DIR) már létezik!"
    read -p "Töröljem a korábbi telepítést? (y/n) " -n 1 -r
    echo    # új sor
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Korábbi telepítés törlése..."
        if [ -f "$INSTALL_DIR/venv/bin/python" ]; then
            log_info "Korábbi kijelző tisztítása..."
            # Próbáljuk meg tisztán leállítani
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
        # Nem állítjuk le a folyamatot, folytassuk a törlést
except Exception as e:
    print(f"Hiba: {e}")
' 2>/dev/null || true
        fi
        
        # Állítsuk le a szolgáltatást, ha fut
        sudo systemctl stop epaper_display.service 2>/dev/null || true
        sudo systemctl disable epaper_display.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/epaper_display.service 2>/dev/null || true
        sudo systemctl daemon-reload 2>/dev/null || true
        
        # Könyvtár törlése
        rm -rf "$INSTALL_DIR"
        log_info "Korábbi telepítés törölve."
    else
        log_error "Telepítés megszakítva a felhasználó által."
        exit 1
    fi
fi

# 2.2 Könyvtár létrehozása és váltás
log_info "Könyvtár létrehozása: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 2.3 A forrásfájlok létrehozása
log_info "Szükséges fájlok létrehozása..."

# ===================================================
# 3. Waveshare e-Paper könyvtár telepítése
# ===================================================
log_section "3. Waveshare e-Paper könyvtár telepítése"

# Közvetlenül hozzuk létre a szükséges driver fájlokat
log_info "Waveshare e-Paper driverek közvetlen létrehozása..."

# Waveshare könyvtárszerkezet létrehozása
mkdir -p waveshare_epd
    
# Fő driver: epdconfig.py
log_info "epdconfig.py létrehozása..."
cat > waveshare_epd/epdconfig.py << 'EOL'
# /*****************************************************************************
# * | File        :   epdconfig.py
# * | Author      :   Waveshare team
# * | Function    :   Hardware underlying interface
# * | Info        :
# *----------------
# * | This version:   V1.0
# * | Date        :   2020-12-21
# * | Info        :   
# ******************************************************************************
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documnetation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to  whom the Software is
# furished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

import os
import logging
import sys
import time

logger = logging.getLogger(__name__)

class RaspberryPi:
    # Pin definition
    RST_PIN         = 17
    DC_PIN          = 25
    CS_PIN          = 8
    BUSY_PIN        = 24

    def __init__(self):
        import spidev
        import RPi.GPIO

        self.GPIO = RPi.GPIO

        # SPI device, bus = 0, device = 0
        self.SPI = spidev.SpiDev()
        self.SPI.open(0, 0)
        self.SPI.max_speed_hz = 4000000
        self.SPI.mode = 0b00
        # self.SPI.lsbfirst = False

    def digital_write(self, pin, value):
        self.GPIO.output(pin, value)

    def digital_read(self, pin):
        return self.GPIO.input(pin)

    def delay_ms(self, delaytime):
        time.sleep(delaytime / 1000.0)

    def spi_writebyte(self, data):
        self.SPI.writebytes(data)

    def spi_write_bytes(self, data):
        # logger.debug("Write bytes, len: %d, data: %s", len(data), ' '.join([hex(x) for x in data]))
        chunks = [data[i:i+4096] for i in range(0, len(data), 4096)]
        for chunk in chunks:
            self.SPI.writebytes(chunk)
        
    def module_init(self):
        self.GPIO.setmode(self.GPIO.BCM)
        self.GPIO.setwarnings(False)
        self.GPIO.setup(self.RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(self.BUSY_PIN, self.GPIO.IN)
        self.GPIO.output(self.CS_PIN, 0)
        return 0

    def module_exit(self):
        logger.debug("spi end")
        self.SPI.close()

        logger.debug("close 5V, Module enters 0 power consumption ...")
        self.GPIO.output(self.RST_PIN, 0)
        self.GPIO.output(self.DC_PIN, 0)

        self.GPIO.cleanup([self.RST_PIN, self.DC_PIN, self.CS_PIN, self.BUSY_PIN])

implementation = RaspberryPi()

for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))
EOL

# E-Paper 4.01" F driver
log_info "epd4in01f.py létrehozása..."
cat > waveshare_epd/epd4in01f.py << 'EOL'
# *****************************************************************************
# * | File        :   epd4in01f.py
# * | Author      :   Waveshare team
# * | Function    :   Electronic paper driver
# * | Info        :
# *----------------
# * | This version:   V1.1
# * | Date        :   2022-08-12
# # | Info        :   python demo
# -----------------------------------------------------------------------------
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documnetation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to  whom the Software is
# furished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS OR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

import logging
from . import epdconfig
from PIL import Image

# Display resolution
EPD_WIDTH  = 640
EPD_HEIGHT = 400

logger = logging.getLogger(__name__)

class EPD:
    def __init__(self):
        self.reset_pin = epdconfig.RST_PIN
        self.dc_pin = epdconfig.DC_PIN
        self.busy_pin = epdconfig.BUSY_PIN
        self.cs_pin = epdconfig.CS_PIN
        self.width = EPD_WIDTH
        self.height = EPD_HEIGHT
        
    # Hardware reset
    def reset(self):
        epdconfig.digital_write(self.reset_pin, 1)
        epdconfig.delay_ms(200) 
        epdconfig.digital_write(self.reset_pin, 0)
        epdconfig.delay_ms(1)
        epdconfig.digital_write(self.reset_pin, 1)
        epdconfig.delay_ms(200)   

    # send command
    def send_command(self, command):
        epdconfig.digital_write(self.dc_pin, 0)
        epdconfig.digital_write(self.cs_pin, 0)
        epdconfig.spi_writebyte([command])
        epdconfig.digital_write(self.cs_pin, 1)

    # send data
    def send_data(self, data):
        epdconfig.digital_write(self.dc_pin, 1)
        epdconfig.digital_write(self.cs_pin, 0)
        epdconfig.spi_writebyte([data])
        epdconfig.digital_write(self.cs_pin, 1)
        
    # Wait until the busy_pin goes LOW
    def ReadBusy(self):
        logger.debug("e-Paper busy")
        busy = epdconfig.digital_read(self.busy_pin)
        while(busy == 1):
            busy = epdconfig.digital_read(self.busy_pin)
        epdconfig.delay_ms(200)
            
    # initialization
    def init(self):
        if (epdconfig.module_init() != 0):
            return -1
            
        self.reset()
        
        self.send_command(0x00)
        self.send_data(0x2f)
        self.send_data(0x00)
        self.send_command(0x01)
        self.send_data(0x37)
        self.send_data(0x00)
        self.send_data(0x05)
        self.send_data(0x05)
        self.send_command(0x03)
        self.send_data(0x00)
        self.send_command(0x06)
        self.send_data(0xC7)
        self.send_data(0xC7)
        self.send_data(0x1D)
        self.send_command(0x41)
        self.send_data(0x00)
        self.send_command(0x50)
        self.send_data(0x37)
        self.send_command(0x60)
        self.send_data(0x22)
        self.send_command(0x61)
        self.send_data(0x02)
        self.send_data(0x80)
        self.send_data(0x01)
        self.send_data(0x90)
        self.send_command(0xE3)
        self.send_data(0xAA)
        
        epdconfig.delay_ms(100)
        self.send_command(0x50)
        self.send_data(0x37)
        
        return 0

    # Drawing on the image
    def getbuffer(self, image):
        img = image.convert('RGB')
        imwidth, imheight = img.size
        if imwidth == self.width and imheight == self.height:
            for y in range(imheight):
                for x in range(imwidth):
                    # Set buffer to RGBA pixels.
                    pos = (x + y * self.width) * 2
                    (r, g, b) = img.getpixel((x, y))
                    if (r == 0 and g == 0 and b == 0):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x00 #black
                    elif (r == 255 and g == 255 and b == 255):
                        self.buffer[pos] = 0xFF
                        self.buffer[pos + 1] = 0xFF #white
                    elif (r == 0 and g == 255 and b == 0):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x07 #green
                    elif (r == 0 and g == 0 and b == 255):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x06 #blue
                    elif (r == 255 and g == 0 and b == 0):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x05 #red
                    elif (r == 255 and g == 255 and b == 0):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x02 #yellow
                    elif (r == 255 and g == 165 and b == 0):
                        self.buffer[pos] = 0x00
                        self.buffer[pos + 1] = 0x01 #orange
            return self.buffer
        else:
            buf = [0x00] * int(self.width * self.height * 2)
            self.buffer = buf
            img = img.resize((self.width, self.height), Image.BILINEAR)
            imwidth, imheight = img.size
            for y in range(imheight):
                for x in range(imwidth):
                    # Set buffer to RGBA pixels.
                    pos = (x + y * self.width) * 2
                    (r, g, b) = img.getpixel((x, y))
                    if (r == 0 and g == 0 and b == 0):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x00 #black
                    elif (r == 255 and g == 255 and b == 255):
                        buf[pos] = 0xFF
                        buf[pos + 1] = 0xFF #white
                    elif (r == 0 and g == 255 and b == 0):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x07 #green
                    elif (r == 0 and g == 0 and b == 255):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x06 #blue
                    elif (r == 255 and g == 0 and b == 0):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x05 #red
                    elif (r == 255 and g == 255 and b == 0):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x02 #yellow
                    elif (r == 255 and g == 165 and b == 0):
                        buf[pos] = 0x00
                        buf[pos + 1] = 0x01 #orange
                    # else:
                        # print("Cannot use color conversion")
                        # buf[pos] = 0xFF
                        # buf[pos + 1] = 0xFF #white
            return buf
            
    def display(self, buffer):
        self.send_command(0x61)
        self.send_data(0x02)
        self.send_data(0x80)
        self.send_data(0x01)
        self.send_data(0x90)
        
        self.send_command(0x10)
        epdconfig.spi_write_bytes(buffer)
        
        self.send_command(0x04)
        self.ReadBusy()
        self.send_command(0x12)
        self.ReadBusy()
        self.send_command(0x02)
        self.ReadBusy()
        
    def Clear(self):
        buf = [0xFF] * int(self.width * self.height * 2)
        buf[0] = 0x00
        buf[1] = 0x00
        
        self.send_command(0x61)
        self.send_data(0x02)
        self.send_data(0x80)
        self.send_data(0x01)
        self.send_data(0x90)
        
        self.send_command(0x10)
        epdconfig.spi_write_bytes(buf)
        
        self.send_command(0x04)
        self.ReadBusy()
        self.send_command(0x12)
        self.ReadBusy()
        self.send_command(0x02)
        self.ReadBusy()

    def sleep(self):
        self.send_command(0x07)
        self.send_data(0xA5)
        
        epdconfig.delay_ms(1000)
        epdconfig.module_exit()
EOL

# Inicializáló fájl
log_info "__init__.py létrehozása..."
cat > waveshare_epd/__init__.py << 'EOL'
# Waveshare E-Paper Driver csomag
EOL

# HTML megjelenítő létrehozása egyszerűbb HTML parser használatával (html.parser beépített modul)
log_info "html_display.py létrehozása egyszerűbb parserrel..."
cat > html_display.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import logging
import time
import sys
import os
import requests
import schedule
import traceback
from PIL import Image, ImageDraw, ImageFont
from html.parser import HTMLParser
import signal
import datetime
import re
from urllib.parse import urljoin

# Konfiguráció
CONFIG = {
    "url": "https://example.com", # Ezt később felülírhatod
    "update_interval": 5,  # percekben
    "font_sizes": {
        "title": 32,
        "heading": 26,
        "normal": 18,
        "small": 14
    },
    "max_content_length": 2000,  # Ennyi karaktert próbálunk max megjeleníteni
    "debug": False
}

# Logging beállítása
if CONFIG["debug"]:
    logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
else:
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Színek definiálása
COLORS = {
    "white": (255, 255, 255),
    "black": (0, 0, 0),
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "yellow": (255, 255, 0),
    "orange": (255, 165, 0),
    "background": (255, 255, 255)
}

# Globális változók
epd = None
fonts = {}
shutdown_flag = False

# Egyszerű HTML parser osztály
class SimpleHTMLParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self.content = []
        self.current_tag = None
        self.recording_title = False
        self.current_text = ""
        
    def handle_starttag(self, tag, attrs):
        self.current_tag = tag
        
        if tag == "title":
            self.recording_title = True
        elif tag in ["h1", "h2", "h3"]:
            if self.current_text:
                self.save_current_text()
            self.current_text = ""
        elif tag == "p":
            if self.current_text:
                self.save_current_text()
            self.current_text = ""
        elif tag == "li":
            if self.current_text:
                self.save_current_text()
            self.current_text = "• "
        elif tag == "img":
            alt = ""
            src = ""
            for attr in attrs:
                if attr[0] == "alt":
                    alt = attr[1]
                elif attr[0] == "src":
                    src = attr[1]
            if src:
                self.content.append({
                    "type": "image",
                    "url": src,
                    "alt": alt or "Kép"
                })
    
    def handle_endtag(self, tag):
        if tag == "title":
            self.recording_title = False
        elif tag in ["h1", "h2", "h3", "p", "li"]:
            self.save_current_text()
            self.current_tag = None
            self.current_text = ""
    
    def handle_data(self, data):
        if self.recording_title:
            self.title += data
        elif self.current_tag in ["h1", "h2", "h3", "p", "li"]:
            self.current_text += data.strip()
    
    def save_current_text(self):
        text = self.current_text.strip()
        if text:
            if self.current_tag in ["h1", "h2", "h3"]:
                level = int(self.current_tag[1])
                self.content.append({
                    "type": "heading",
                    "text": text,
                    "level": level
                })
            elif self.current_tag == "p":
                self.content.append({
                    "type": "paragraph",
                    "text": text
                })
            elif self.current_tag == "li":
                self.content.append({
                    "type": "list_item",
                    "text": text
                })

# Waveshare könyvtár importálása
try:
    # Elérési utak a modulhoz
    sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'waveshare_epd'))
    
    from waveshare_epd import epd4in01f
    logger.info("Waveshare modul sikeresen importálva")
except ImportError as e:
    logger.error(f"Hiba a Waveshare modul importálásakor: {e}")
    logger.error("Ellenőrizd, hogy megfelelően telepítetted-e a könyvtárat.")
    sys.exit(1)

# Betűtípusok betöltése
def load_fonts():
    global fonts
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
    ]
    
    font_path = None
    for path in font_paths:
        if os.path.exists(path):
            font_path = path
            break
    
    if font_path is None:
        logger.warning("Nem található megfelelő betűtípus, alapértelmezett használata...")
        for size_name, size in CONFIG["font_sizes"].items():
            fonts[size_name] = ImageFont.load_default()
    else:
        for size_name, size in CONFIG["font_sizes"].items():
            try:
                fonts[size_name] = ImageFont.truetype(font_path, size)
                logger.debug(f"{size_name} betűtípus betöltve ({size}px)")
            except Exception as e:
                logger.error(f"Hiba a {size_name} betűtípus betöltésekor: {e}")
                fonts[size_name] = ImageFont.load_default()

# Kijelző inicializálása
def init_display():
    global epd
    try:
        epd = epd4in01f.EPD()
        epd.init()
        logger.info("E-Paper kijelző inicializálva")
    except Exception as e:
        logger.error(f"Hiba a kijelző inicializálásakor: {e}")
        logger.error(traceback.format_exc())
        sys.exit(1)

# HTML tartalom lekérése
def fetch_html_content(url):
    try:
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        response = requests.get(url, headers=headers, timeout=15)
        response.raise_for_status()
        return response.text
    except requests.exceptions.RequestException as e:
        logger.error(f"Hiba a HTML letöltésekor: {e}")
        return None

# HTML feldolgozása a beépített HTML parser használatával
def parse_html(html_content, base_url):
    parser = SimpleHTMLParser()
    parser.feed(html_content)
    
    # Limitáljuk a tartalmat
    total_length = 0
    limited_content = []
    for item in parser.content:
        if 'text' in item:
            total_length += len(item['text'])
        if total_length > CONFIG["max_content_length"]:
            break
        limited_content.append(item)
    
    return parser.title or "Nincs cím", limited_content

# Kép rajzolása a kijelzőre
def draw_content(title, content_items):
    # Kép létrehozása
    image = Image.new('RGB', (epd4in01f.EPD_WIDTH, epd4in01f.EPD_HEIGHT), COLORS["background"])
    draw = ImageDraw.Draw(image)
    
    # Cím megjelenítése
    draw.rectangle([(0, 0), (epd4in01f.EPD_WIDTH, 50)], fill=COLORS["blue"])
    draw.text((10, 10), title, font=fonts["title"], fill=COLORS["white"])
    
    # Frissítési idő kiírása
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    draw.text((epd4in01f.EPD_WIDTH - 200, 10), f"Frissítve: {current_time}", 
              font=fonts["small"], fill=COLORS["white"])
    
    # Tartalom kirajzolása
    y_position = 60
    for item in content_items:
        if item['type'] == 'heading':
            level = item.get('level', 1)
            color = COLORS["black"]
            if level == 1:
                font_key = "heading"
                color = COLORS["red"]
            else:
                font_key = "heading" if level == 2 else "normal"
            
            # Hosszú címsorok tördelése
            text = item['text']
            max_width = epd4in01f.EPD_WIDTH - 20
            
            # Felosztás sorokra, ha nem fér ki
            words = text.split()
            lines = []
            current_line = []
            
            for word in words:
                test_line = " ".join(current_line + [word])
                width = fonts[font_key].getbbox(test_line)[2]
                if width <= max_width:
                    current_line.append(word)
                else:
                    lines.append(" ".join(current_line))
                    current_line = [word]
            
            if current_line:
                lines.append(" ".join(current_line))
            
            for line in lines:
                draw.text((10, y_position), line, font=fonts[font_key], fill=color)
                y_position += fonts[font_key].getbbox(line)[3] + 5
            
            y_position += 10
            
        elif item['type'] == 'paragraph':
            # Bekezdés szövegének tördelése
            text = item['text']
            max_width = epd4in01f.EPD_WIDTH - 20
            font_key = "normal"
            
            words = text.split()
            lines = []
            current_line = []
            
            for word in words:
                test_line = " ".join(current_line + [word])
                width = fonts[font_key].getbbox(test_line)[2]
                if width <= max_width:
                    current_line.append(word)
                else:
                    lines.append(" ".join(current_line))
                    current_line = [word]
            
            if current_line:
                lines.append(" ".join(current_line))
            
            for line in lines:
                draw.text((10, y_position), line, font=fonts[font_key], fill=COLORS["black"])
                y_position += fonts[font_key].getbbox(line)[3] + 5
            
            y_position += 10
            
        elif item['type'] == 'list_item':
            # Lista elem kiíratása
            text = item['text']
            max_width = epd4in01f.EPD_WIDTH - 20
            font_key = "normal"
            
            words = text.split()
            lines = []
            current_line = []
            
            for word in words:
                test_line = " ".join(current_line + [word])
                width = fonts[font_key].getbbox(test_line)[2]
                if width <= max_width:
                    current_line.append(word)
                else:
                    lines.append(" ".join(current_line))
                    current_line = [word]
            
            if current_line:
                lines.append(" ".join(current_line))
            
            for i, line in enumerate(lines):
                if i == 0:  # Első sor listajellel
                    draw.text((10, y_position), line, font=fonts[font_key], fill=COLORS["black"])
                else:  # Többi sor behúzással
                    draw.text((30, y_position), line, font=fonts[font_key], fill=COLORS["black"])
                
                y_position += fonts[font_key].getbbox(line)[3] + 5
            
            y_position += 5
            
        elif item['type'] == 'image':
            # Kép helyének jelzése (magát a képet most nem jelenítjük meg)
            draw.text((10, y_position), f"[Kép: {item['alt']}]", font=fonts["small"], fill=COLORS["blue"])
            y_position += fonts["small"].getbbox(f"[Kép: {item['alt']}]")[3] + 10
        
        # Ellenőrizzük, hogy kifutunk-e a képernyőről
        if y_position > epd4in01f.EPD_HEIGHT - 30:
            # Ha kifutnánk, akkor egy figyelmeztetést írunk a képernyő aljára
            draw.rectangle([(0, epd4in01f.EPD_HEIGHT - 30), (epd4in01f.EPD_WIDTH, epd4in01f.EPD_HEIGHT)], 
                         fill=COLORS["yellow"])
            draw.text((10, epd4in01f.EPD_HEIGHT - 25), 
                     "További tartalom nem fért ki a kijelzőre...", 
                     font=fonts["small"], fill=COLORS["black"])
            break
    
    # Lábléc rajzolása
    if y_position <= epd4in01f.EPD_HEIGHT - 30:
        draw.line([(0, epd4in01f.EPD_HEIGHT - 30), (epd4in01f.EPD_WIDTH, epd4in01f.EPD_HEIGHT - 30)], 
                fill=COLORS["blue"], width=2)
        draw.text((10, epd4in01f.EPD_HEIGHT - 25), 
                 f"Automatikus frissítés {CONFIG['update_interval']} percenként", 
                 font=fonts["small"], fill=COLORS["blue"])
    
    return image

# Megjelenítés a kijelzőn
def update_display():
    global shutdown_flag
    if shutdown_flag:
        return
    
    try:
        logger.info(f"HTML tartalom lekérése innen: {CONFIG['url']}")
        html_content = fetch_html_content(CONFIG['url'])
        
        if html_content is None:
            logger.error("Nem sikerült letölteni a HTML tartalmat")
            # Hiba kijelzése a képernyőn
            image = Image.new('RGB', (epd4in01f.EPD_WIDTH, epd4in01f.EPD_HEIGHT), COLORS["white"])
            draw = ImageDraw.Draw(image)
            draw.text((50, 50), "Hiba történt a weboldal letöltésekor!", font=fonts["heading"], fill=COLORS["red"])
            draw.text((50, 100), f"URL: {CONFIG['url']}", font=fonts["normal"], fill=COLORS["black"])
            draw.text((50, 150), f"Következő próbálkozás {CONFIG['update_interval']} perc múlva...", 
                     font=fonts["normal"], fill=COLORS["black"])
            current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
            draw.text((50, 200), f"Időbélyeg: {current_time}", font=fonts["normal"], fill=COLORS["black"])
            
            # Megjelenítés a kijelzőn
            epd.display(epd.getbuffer(image))
            return
        
        # HTML feldolgozása
        title, content = parse_html(html_content, CONFIG['url'])
        
        # Kép készítése és megjelenítése
        image = draw_content(title, content)
        
        # Kijelzőre küldés
        logger.info("Tartalom megjelenítése a kijelzőn")
        epd.display(epd.getbuffer(image))
        
        logger.info("Kijelző frissítve")
        
    except Exception as e:
        logger.error(f"Hiba a kijelző frissítésekor: {e}")
        logger.error(traceback.format_exc())

# Signal handlerek a tiszta leállításhoz
def signal_handler(sig, frame):
    global shutdown_flag
    logger.info("Leállítási jelzés érkezett, tiszta leállítás...")
    shutdown_flag = True
    # Törölni próbáljuk a kijelzőt
    try:
        if epd:
            logger.info("Kijelző tisztítása...")
            epd.init()
            epd.Clear()
            epd.sleep()
    except Exception as e:
        logger.error(f"Hiba a kijelző tisztításakor: {e}")
    
    logger.info("Program leállítva")
    sys.exit(0)

# Fő funkció
def main():
    global CONFIG
    
    # Ellenőrizzük, hogy van-e parancssori argumentum URL-ként
    if len(sys.argv) > 1:
        CONFIG["url"] = sys.argv[1]
        logger.info(f"URL parancssori argumentumból: {CONFIG['url']}")
    
    # Signal handlerek regisztrálása
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Előkészítés
    load_fonts()
    init_display()
    
    # Kezdeti tartalom megjelenítése
    update_display()
    
    # Ütemező beállítása a rendszeres frissítéshez
    schedule.every(CONFIG["update_interval"]).minutes.do(update_display)
    
    # Fő loop
    logger.info(f"Alkalmazás elindult, frissítési időköz: {CONFIG['update_interval']} perc")
    while not shutdown_flag:
        schedule.run_pending()
        time.sleep(1)

if __name__ == "__main__":
    main()
EOL

# ===================================================
# 4. E-Paper tesztprogram létrehozása
# ===================================================
log_section "4. E-Paper tesztprogram létrehozása"

log_info "epaper_test.py létrehozása..."
cat > epaper_test.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import logging
import time
import sys
import os
from PIL import Image, ImageDraw, ImageFont

# Logging beállítása
logging.basicConfig(level=logging.DEBUG)

# Waveshare könyvtár importálása
try:
    # Elérési út a modulhoz
    sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'waveshare_epd'))
    
    from waveshare_epd import epd4in01f
    logging.info("Waveshare modul sikeresen importálva!")
except ImportError as e:
    logging.error(f"Hiba a Waveshare modul importálásakor: {e}")
    logging.error("Ellenőrizd, hogy megfelelően telepítetted-e a könyvtárat.")
    sys.exit(1)

try:
    logging.info("E-Paper teszt indítása...")
    
    # E-Paper inicializálása
    epd = epd4in01f.EPD()
    logging.info("Kijelző inicializálása...")
    epd.init()
    
    # Kijelző tisztítása
    logging.info("Kijelző törlése...")
    epd.Clear()
    
    # Font keresése
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf"
    ]
    
    font = None
    for path in font_paths:
        if os.path.exists(path):
            font = ImageFont.truetype(path, 24)
            logging.info(f"Betűtípus betöltve: {path}")
            break
    
    if font is None:
        logging.warning("Nem található megfelelő betűtípus, alapértelmezett használata...")
        font = ImageFont.load_default()
    
    # Teszt kép létrehozása
    logging.info("Teszt kép létrehozása...")
    image = Image.new('RGB', (epd.width, epd.height), 'white')
    draw = ImageDraw.Draw(image)
    
    # Teszt minta rajzolása
    draw.rectangle([(20, 20), (620, 380)], outline='blue')
    draw.text((180, 120), 'E-Paper Teszt!', font=font, fill='black')
    draw.text((180, 160), 'A teszt sikeresen fut!', font=font, fill='red')
    draw.text((180, 200), 'Waveshare 4.01" kijelző', font=font, fill='green')
    
    # Ez a kép, ahogy kijelzőre kerül
    logging.info("Kép megjelenítése a kijelzőn...")
    epd.display(epd.getbuffer(image))
    logging.info("A képnek most látszódnia kell a kijelzőn!")
    
    # Várunk, hogy lássuk az eredményt
    time.sleep(5)
    
    # Kijelző alvó módba helyezése
    logging.info("Kijelző alvó módba helyezése...")
    epd.sleep()
    
    logging.info("Teszt sikeresen befejezve!")
    
except Exception as e:
    logging.error(f"Hiba a teszt során: {e}")
    sys.exit(1)
EOL

# Teszt futtathatóvá tétele
chmod +x epaper_test.py

# ===================================================
# 5. Konfiguráció mentése
# ===================================================
log_section "5. Konfiguráció létrehozása"

log_info "config.ini létrehozása..."
cat > config.ini << 'EOL'
[Display]
# A megjelenítendő weboldal URL-je
url = https://example.com

# Frissítési időköz percekben
update_interval = 5

# Debug mód (true/false)
debug = false
EOL

# ===================================================
# 6. Konfigurációt betöltő szkript
# ===================================================
log_info "config_loader.py létrehozása..."
cat > config_loader.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import configparser
import os
import sys
import logging

def load_config():
    """Konfiguráció betöltése a config.ini fájlból"""
    config = {
        "url": "https://example.com",
        "update_interval": 5,
        "debug": False
    }
    
    config_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config.ini')
    
    if os.path.exists(config_file):
        try:
            parser = configparser.ConfigParser()
            parser.read(config_file)
            
            if 'Display' in parser:
                if 'url' in parser['Display']:
                    config["url"] = parser['Display']['url']
                
                if 'update_interval' in parser['Display']:
                    try:
                        config["update_interval"] = int(parser['Display']['update_interval'])
                    except ValueError:
                        print(f"Figyelem: Érvénytelen frissítési időköz a konfigurációs fájlban, alapértelmezett használata: {config['update_interval']}")
                
                if 'debug' in parser['Display']:
                    config["debug"] = parser['Display']['debug'].lower() in ('true', 'yes', '1', 'on')
            
            print(f"Konfiguráció betöltve: {config}")
            return config
        except Exception as e:
            print(f"Hiba a konfigurációs fájl betöltésekor: {e}")
            return config
    else:
        print(f"Figyelem: A konfigurációs fájl nem található ({config_file}), alapértelmezett beállítások használata")
        return config

if __name__ == "__main__":
    # Teszt a konfiguráció betöltésére
    config = load_config()
    print(f"URL: {config['url']}")
    print(f"Frissítési időköz: {config['update_interval']} perc")
    print(f"Debug mód: {'Bekapcsolva' if config['debug'] else 'Kikapcsolva'}")
EOL

# ===================================================
# 7. Fő program létrehozása a konfigurációs betöltéssel
# ===================================================
log_info "display_app.py fő alkalmazás létrehozása..."
cat > display_app.py << 'EOL'
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import signal
import logging
import traceback
from config_loader import load_config

# Konfiguráció betöltése
config = load_config()

# A konfigurációs adatok átadása a HTML megjelenítőnek
if __name__ == "__main__":
    try:
        # Python elérési útvonal beállítása
        current_dir = os.path.dirname(os.path.abspath(__file__))
        if current_dir not in sys.path:
            sys.path.append(current_dir)
        
        # HTML megjelenítő importálása
        from html_display import CONFIG, main
        
        # Konfiguráció átadása
        CONFIG["url"] = config["url"]
        CONFIG["update_interval"] = config["update_interval"]
        CONFIG["debug"] = config["debug"]
        
        # Fő program indítása
        main()
    except Exception as e:
        logging.error(f"Hiba az alkalmazás indításakor: {e}")
        logging.error(traceback.format_exc())
        sys.exit(1)
EOL

# Futtathatóvá tesszük
chmod +x display_app.py

# ===================================================
# 8. Systemd service létrehozása
# ===================================================
log_section "8. Systemd szolgáltatás létrehozása"

log_info "epaper_display.service létrehozása..."
cat > epaper_display.service << 'EOL'
[Unit]
Description=E-Paper Display Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/epaper_display
ExecStart=/usr/bin/python3 /home/pi/epaper_display/display_app.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=epaper_display

[Install]
WantedBy=multi-user.target
EOL

log_info "Szolgáltatás telepítése..."
sudo mv epaper_display.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable epaper_display.service

# ===================================================
# 9. Uninstall script létrehozása
# ===================================================
log_section "9. Eltávolító script létrehozása"

log_info "uninstall.sh létrehozása..."
cat > uninstall.sh << 'EOL'
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
if [ -d "$INSTALL_DIR" ]; then
    log_info "Kijelző tisztítása..."
    cd "$INSTALL_DIR"
    python3 -c '
import sys
try:
    # Kísérlet a Waveshare könyvtár keresésére és használatára
    import os
    sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveshare_epd"))
    
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
EOL

# Futtathatóvá tesszük
chmod +x uninstall.sh

# ===================================================
# 10. URL beállítása
# ===================================================
log_section "10. Megjelenítendő weboldal beállítása"

log_info "Most beállíthatod a megjelenítendő weboldal URL-jét."
log_info "Az alapértelmezett URL: https://example.com"
log_info "Üresen hagyva az alapértelmezett URL marad."

read -p "Kérlek add meg a megjelenítendő weboldal URL-jét: " user_url
if [ -n "$user_url" ]; then
    # Frissítsük a konfigurációs fájlt
    sed -i "s|url = .*|url = $user_url|g" config.ini
    log_info "URL beállítva: $user_url"
else
    log_info "Az alapértelmezett URL maradt érvényben."
fi

# ===================================================
# 11. Tesztelés
# ===================================================
log_section "11. E-Paper teszt futtatása"

log_info "Most egy egyszerű teszt indul a kijelző működésének ellenőrzésére!"
read -p "Futtatod a tesztet? (y/n) " -n 1 -r
echo    # új sor
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Teszt indítása..."
    python3 epaper_test.py
    
    # Ellenőrizzük a teszt sikerességét
    if [ $? -eq 0 ]; then
        log_info "Teszt sikeresen lefutott!"
        log_info "Ha a kijelzőn megjelent a teszt kép, a telepítés sikeres volt."
        
        # Megkérdezzük, indítsuk-e az alkalmazást
        read -p "Elindítsuk az alkalmazást? (y/n) " -n 1 -r
        echo    # új sor
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Alkalmazás indítása..."
            sudo systemctl start epaper_display.service
            
            # Ellenőrizzük, hogy sikeresen elindult-e
            sleep 2
            if sudo systemctl is-active --quiet epaper_display.service; then
                log_info "Alkalmazás sikeresen elindult!"
            else
                log_warn "Hiba az alkalmazás indításakor."
                log_warn "Ellenőrizd a szolgáltatás állapotát: sudo systemctl status epaper_display.service"
                log_warn "Naplófájl megtekintése: sudo journalctl -u epaper_display.service -f"
            fi
        else
            log_info "Az alkalmazás indítása kihagyva. Később a következő paranccsal indíthatod el:"
            log_info "sudo systemctl start epaper_display.service"
        fi
    else
        log_error "Hiba történt a teszt futtatása közben!"
        log_error "Ellenőrizd a fenti hibaüzeneteket."
    fi
else
    log_info "Teszt kihagyva."
    
    # Megkérdezzük, indítsuk-e az alkalmazást teszt nélkül
    read -p "Elindítsuk az alkalmazást teszt nélkül? (y/n) " -n 1 -r
    echo    # új sor
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Alkalmazás indítása..."
        sudo systemctl start epaper_display.service
        
        # Ellenőrizzük, hogy sikeresen elindult-e
        sleep 2
        if sudo systemctl is-active --quiet epaper_display.service; then
            log_info "Alkalmazás sikeresen elindult!"
        else
            log_warn "Hiba az alkalmazás indításakor."
            log_warn "Ellenőrizd a szolgáltatás állapotát: sudo systemctl status epaper_display.service"
            log_warn "Naplófájl megtekintése: sudo journalctl -u epaper_display.service -f"
        fi
    else
        log_info "Az alkalmazás indítása kihagyva. Később a következő paranccsal indíthatod el:"
        log_info "sudo systemctl start epaper_display.service"
    fi
fi

# ===================================================
# 12. Összegzés és útmutató
# ===================================================
log_section "Telepítés befejezve!"

log_info "Az E-Paper Display alkalmazás telepítése befejeződött."

# Olvassuk ki a konfigurációból az update_interval értékét
update_interval=$(grep -oP 'update_interval\s*=\s*\K\d+' config.ini || echo "5")
log_info "Az alkalmazás ${update_interval} percenként frissíti a kijelző tartalmát."
log_info "A rendszer újraindításakor automatikusan újraindul."
echo ""
log_info "Hasznos parancsok:"
echo "- Állapot ellenőrzése:  sudo systemctl status epaper_display.service"
echo "- Naplók megtekintése:  sudo journalctl -u epaper_display -f"
echo "- Újraindítás:          sudo systemctl restart epaper_display.service"
echo "- URL módosítása:       nano $INSTALL_DIR/config.ini"
echo "- Eltávolítás:          $INSTALL_DIR/uninstall.sh"
echo ""
log_info "Ha bármilyen probléma merülne fel, próbáld újraindítani a rendszert."

exit 0
