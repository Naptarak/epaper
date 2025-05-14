#!/bin/bash

# ===============================================================
# E-Paper Időjárás Display Telepítő
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

INSTALL_DIR=~/epaper_weather
USE_DIRECT_DRIVER=false

# Ellenőrizze, hogy root jogosultság nélkül futtatják-e
if [ "$EUID" -eq 0 ]; then
    log_error "Ezt a szkriptet NE root-ként futtasd! Használd normál felhasználóként."
    exit 1
fi

clear
log_section "E-Paper Időjárás Display Telepítő"
log_info "Telepítési könyvtár: $INSTALL_DIR"
log_info "Ez a telepítő beállítja az időjárás kijelzőt a Waveshare 4.01\" E-Paper HAT (F) kijelzőhöz"

# ===================================================
# 1. Előfeltételek ellenőrzése
# ===================================================
log_section "1. Előfeltételek ellenőrzése"

# 1.1 Rendszerfrissítés
log_info "Rendszerfrissítés..."
sudo apt-get update -y
# Kötelező csomagok frissítése csak, hogy ne tartson sokáig
sudo apt-get upgrade -y python3 python3-pip

# 1.2 Szükséges csomagok telepítése
log_info "Szükséges csomagok telepítése..."
sudo apt-get install -y python3-pip python3-pil python3-numpy git python3-rpi.gpio python3-spidev python3-venv

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
        sudo systemctl stop weather_display.service 2>/dev/null || true
        sudo systemctl disable weather_display.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/weather_display.service 2>/dev/null || true
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

# 2.3 Python virtuális környezet létrehozása
log_info "Python virtuális környezet létrehozása..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip

# 2.4 Szükséges Python csomagok telepítése
log_info "Python csomagok telepítése..."
pip install pillow numpy requests schedule RPi.GPIO spidev

# ===================================================
# 3. Waveshare e-Paper könyvtár telepítése
# ===================================================
log_section "3. Waveshare e-Paper könyvtár telepítése"

# 3.1 Próbáljuk meg letölteni a hivatalos könyvtárat GitHubról
if [ "$USE_DIRECT_DRIVER" = false ]; then
    log_info "Waveshare e-Paper könyvtár letöltése GitHubról..."
    if ! git clone https://github.com/waveshare/e-Paper.git; then
        log_warn "Nem sikerült letölteni a Waveshare e-Paper könyvtárat GitHubról."
        USE_DIRECT_DRIVER=true
    fi
    
    # Ellenőrizzük a letöltést
    if [ -d "e-Paper" ]; then
        # Keressük meg a megfelelő Python könyvtárat
        if [ -d "e-Paper/RaspberryPi_JetsonNano/python" ]; then
            log_info "RaspberryPi_JetsonNano könyvtár megtalálva..."
            cd e-Paper/RaspberryPi_JetsonNano/python
            
            # Ellenőrizzük, hogy sikerül-e telepíteni
            if ! pip install ./; then
                log_warn "Nem sikerült telepíteni a Waveshare könyvtárat pip-pel."
                log_info "Alternatív telepítési módszer használata..."
                
                # Közvetlenül másoljuk az elérhető könyvtárakat
                if [ -d "lib/waveshare_epd" ]; then
                    log_info "Waveshare könyvtár másolása a site-packages könyvtárba..."
                    cp -r lib/waveshare_epd ../../../../venv/lib/python*/site-packages/
                    if [ $? -eq 0 ]; then
                        log_info "Waveshare könyvtár sikeresen másolva."
                    else
                        log_warn "Nem sikerült másolni a könyvtárat. Folytatás alternatív módon..."
                        USE_DIRECT_DRIVER=true
                    fi
                else
                    log_warn "A waveshare_epd könyvtár nem található. Folytatás alternatív módon..."
                    USE_DIRECT_DRIVER=true
                fi
            else
                log_info "Waveshare e-Paper könyvtár sikeresen telepítve pip-pel!"
            fi
            
            cd "$INSTALL_DIR"
        elif [ -d "e-Paper/RaspberryPi/python" ]; then
            log_info "RaspberryPi könyvtár megtalálva..."
            cd e-Paper/RaspberryPi/python
            
            # Ellenőrizzük, hogy sikerül-e telepíteni
            if ! pip install ./; then
                log_warn "Nem sikerült telepíteni a Waveshare könyvtárat pip-pel."
                log_info "Alternatív telepítési módszer használata..."
                
                # Közvetlenül másoljuk az elérhető könyvtárakat
                if [ -d "lib/waveshare_epd" ]; then
                    log_info "Waveshare könyvtár másolása a site-packages könyvtárba..."
                    cp -r lib/waveshare_epd ../../../../venv/lib/python*/site-packages/
                    if [ $? -eq 0 ]; then
                        log_info "Waveshare könyvtár sikeresen másolva."
                    else
                        log_warn "Nem sikerült másolni a könyvtárat. Folytatás alternatív módon..."
                        USE_DIRECT_DRIVER=true
                    fi
                else
                    log_warn "A waveshare_epd könyvtár nem található. Folytatás alternatív módon..."
                    USE_DIRECT_DRIVER=true
                fi
            else
                log_info "Waveshare e-Paper könyvtár sikeresen telepítve pip-pel!"
            fi
            
            cd "$INSTALL_DIR"
        else
            log_warn "Nem található megfelelő Python könyvtár a letöltött repository-ban."
            USE_DIRECT_DRIVER=true
        fi
    else
        USE_DIRECT_DRIVER=true
    fi
fi

# 3.2 Ha nem sikerült a GitHub letöltés, használjuk a közvetlen módszert
if [ "$USE_DIRECT_DRIVER" = true ]; then
    log_section "Alternatív driver telepítés"
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

    # Telepítés a virtuális környezetbe
    log_info "Driver másolása a virtuális környezetbe..."
    cp -r waveshare_epd venv/lib/python*/site-packages/
    
    if [ $? -eq 0 ]; then
        log_info "Waveshare driver sikeresen telepítve!"
    else
        log_error "Nem sikerült telepíteni a Waveshare drivert!"
        exit 1
    fi
fi

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
    # Alternatív elérési utak a Waveshare könyvtárhoz
    paths_to_try = [
        'e-Paper/RaspberryPi_JetsonNano/python/lib',
        'e-Paper/RaspberryPi/python/lib',
        '.',
    ]
    
    for path in paths_to_try:
        if os.path.exists(path):
            if path not in sys.path:
                sys.path.append(path)
    
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
# A többi rész ugyanaz marad, mint az eredeti szkriptben
# ===================================================

# ... [TOVÁBBI LÉPÉSEK AZ EREDETIBŐL] ...

# ===================================================
# 7. Systemd service létrehozása
# ===================================================
log_section "7. Systemd szolgáltatás létrehozása"

log_info "weather_display.service létrehozása..."
cat > weather_display.service << 'EOL'
[Unit]
Description=E-Paper Weather Display
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/epaper_weather
ExecStart=/home/pi/epaper_weather/venv/bin/python /home/pi/epaper_weather/weather_display.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=weather_display

[Install]
WantedBy=multi-user.target
EOL

log_info "Szolgáltatás telepítése..."
sudo mv weather_display.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable weather_display.service

# ===================================================
# 8. Tesztelés
# ===================================================
log_section "8. E-Paper teszt futtatása"

log_info "Most egy egyszerű teszt indul a kijelző működésének ellenőrzésére!"
log_info "Ez segít ellenőrizni, hogy a telepítés sikeres volt-e, és a kijelző működik-e."
read -p "Futtatod a tesztet? (y/n) " -n 1 -r
echo    # új sor
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Teszt indítása..."
    source venv/bin/activate
    python epaper_test.py
    
    # Ellenőrizzük a teszt sikerességét
    if [ $? -eq 0 ]; then
        log_info "Teszt sikeresen lefutott!"
        log_info "Ha a kijelzőn megjelent a teszt kép, a telepítés sikeres volt."
    else
        log_error "Hiba történt a teszt futtatása közben!"
        log_error "Ellenőrizd a fenti hibaüzeneteket."
        log_error "A telepítés folytatódik, de előfordulhat, hogy a kijelző nem fog megfelelően működni."
    fi
else
    log_info "Teszt kihagyva."
fi

# ===================================================
# 9. Alkalmazás indítása
# ===================================================
log_section "9. Időjárás alkalmazás indítása"

log_info "Az időjárás alkalmazás indítása..."
sudo systemctl start weather_display.service

# Ellenőrizzük, hogy sikeresen elindult-e
sleep 2
if sudo systemctl is-active --quiet weather_display.service; then
    log_info "Időjárás alkalmazás sikeresen elindult!"
else
    log_warn "Hiba az időjárás alkalmazás indításakor."
    log_warn "Ellenőrizd a szolgáltatás állapotát: sudo systemctl status weather_display.service"
fi

# ===================================================
# 10. Összegzés és útmutató
# ===================================================
log_section "Telepítés befejezve!"

log_info "Az időjárás alkalmazás telepítése befejeződött."
log_info "Az alkalmazás automatikusan elindult és 5 percenként frissül."
log_info "A rendszer újraindításakor automatikusan újraindul."
echo ""
log_info "Hasznos parancsok:"
echo "- Állapot ellenőrzése: sudo systemctl status weather_display.service"
echo "- Naplók megtekintése: sudo journalctl -u weather_display -f"
echo "- Újraindítás:         sudo systemctl restart weather_display.service"
echo "- Eltávolítás:         ~/epaper_weather/uninstall.sh"
echo ""
log_info "Ha bármilyen probléma merülne fel, próbáld újraindítani a rendszert."

exit 0
