#!/bin/bash

# E-Paper Időjárás Display Telepítő (TELJESEN ÚJRAÍRT)
# Raspberry Pi Zero 2W + Waveshare 4.01" E-Paper HAT (F)

echo "=========================================================="
echo "     E-Paper Időjárás Display Telepítő                    "
echo "     Waveshare 4.01\" E-Paper HAT (F) kijelzőhöz          "
echo "=========================================================="

# Függőségek telepítése
echo "[1/7] Függőségek telepítése..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-pil python3-numpy git wiringpi python3-venv python3-rpi.gpio

# Python virtuális környezet létrehozása
echo "[2/7] Python virtuális környezet létrehozása..."
mkdir -p ~/epaper_weather
cd ~/epaper_weather
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install requests pillow numpy schedule RPi.GPIO spidev

# Waveshare könyvtárszerkezet létrehozása
echo "[3/7] Waveshare driverek kézi letöltése és telepítése..."
mkdir -p waveshare_epd

# Forrás: https://github.com/waveshare/e-Paper/tree/master/RaspberryPi_JetsonNano/python/lib/waveshare_epd
# epd4in01f.py letöltése közvetlenül
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

# epdconfig.py letöltése
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

# If do not understand RPi.GPIO, please execute the following command in the terminal:
# sudo apt-get update
# sudo apt-get install python-rpi.gpio
# sudo apt-get install python3-rpi.gpio

# For Jetson Nano
# sudo apt-get install python-jetson-gpio
# sudo apt-get install python3-jetson-gpio

implementation = RaspberryPi()

for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))
EOL

# __init__.py létrehozása
cat > waveshare_epd/__init__.py << 'EOL'
# Placeholder for package initialization
EOL

# Telepítés a virtuális környezetbe
echo "[4/7] Waveshare modulok telepítése a virtuális környezetbe..."
cp -r waveshare_epd venv/lib/python*/site-packages/

# Python alkalmazás létrehozása
echo "[5/7] Python alkalmazás létrehozása..."
cat > weather_display.py << 'EOL'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import json
import logging
import schedule
import requests
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont
from math import ceil

# Logging beállítása
logging.basicConfig(level=logging.INFO)

# Waveshare e-Paper modul importálása
try:
    from waveshare_epd import epd4in01f
    logging.info("Waveshare e-Paper modul sikeresen importálva")
except ImportError as e:
    logging.error(f"Hiba a Waveshare e-Paper modul importálásakor: {e}")
    sys.exit(1)

# Konfiguráció
API_KEY = "1e39a49c6785626b3aca124f4d4ce591"  # OpenWeatherMap API kulcs
CITY = "Pécs"
COUNTRY = "HU"
LAT = 46.0763
LON = 18.2281
REFRESH_TIME = 300  # 5 perc másodpercekben

# Hónapok és napok magyarul
MONTHS = ["jan", "feb", "már", "ápr", "máj", "jún", "júl", "aug", "szep", "okt", "nov", "dec"]
DAYS = ["Vas", "Hét", "Ke", "Sze", "Csüt", "Pén", "Szo"]

# Ünnepek
FIXED_HOLIDAYS = {
    "01-01": "Újév",
    "03-15": "Nemzeti ünnep",
    "05-01": "Munka ünnepe",
    "08-20": "Államalapítás ünnepe",
    "10-23": "Nemzeti ünnep",
    "11-01": "Mindenszentek",
    "12-24": "Szenteste",
    "12-25": "Karácsony",
    "12-26": "Karácsony",
    "12-31": "Szilveszter"
}

# Időjárás ikon megfeleltetés
WEATHER_ICONS = {
    "01d": "nap",
    "01n": "hold",
    "02d": "nap_felho",
    "02n": "hold_felho",
    "03d": "felhos",
    "03n": "felhos",
    "04d": "borult",
    "04n": "borult",
    "09d": "zapor",
    "09n": "zapor",
    "10d": "eso",
    "10n": "eso",
    "11d": "vihar",
    "11n": "vihar",
    "13d": "ho",
    "13n": "ho",
    "50d": "kod",
    "50n": "kod"
}

# Színek
BLACK = 0
WHITE = 1
GREEN = 2
BLUE = 3
RED = 4
YELLOW = 5
ORANGE = 6

class WeatherDisplay:
    def __init__(self):
        self.epd = epd4in01f.EPD()
        self.width = self.epd.width
        self.height = self.epd.height
        
        # Alapértelmezett font
        self.fonts = {
            'small': self.get_font(16),
            'medium': self.get_font(24),
            'large': self.get_font(36),
            'xlarge': self.get_font(48)
        }
        
        self.init_display()
        self.create_icons()

    def get_font(self, size):
        """Megfelelő font keresése a rendszeren"""
        font_paths = [
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
            "/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
        ]
        
        for path in font_paths:
            if os.path.exists(path):
                return ImageFont.truetype(path, size)
        
        logging.warning(f"Nem található megfelelő TrueType font, alapértelmezett font használata")
        return ImageFont.load_default()

    def init_display(self):
        try:
            logging.info("E-Paper kijelző inicializálása...")
            self.epd.init()
            self.epd.Clear()
            logging.info("E-Paper kijelző inicializálása kész.")
        except Exception as e:
            logging.error(f"Hiba az e-Paper inicializálása során: {e}")
            raise

    def create_icons(self):
        # Ez a függvény egyszerű ikonokat készít az időjárás állapotokhoz
        self.icons = {}
        
        # Nap ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        draw.ellipse((10, 10, 50, 50), fill=(255, 165, 0))  # Narancssárga kör
        for i in range(8):
            angle = i * 45
            x1 = 30 + 25 * (angle % 90 == 0) * (1 if angle in [0, 180] else -1 if angle in [90, 270] else 0)
            y1 = 30 + 25 * (angle % 90 == 0) * (1 if angle in [90, 270] else -1 if angle in [0, 180] else 0)
            x2 = 30 + 30 * (angle % 90 == 0) * (1 if angle in [0, 180] else -1 if angle in [90, 270] else 0)
            y2 = 30 + 30 * (angle % 90 == 0) * (1 if angle in [90, 270] else -1 if angle in [0, 180] else 0)
            if angle % 90 != 0:
                x1, y1 = 30 + 20 * 0.7071 * (1 if angle in [45, 225] else -1), 30 + 20 * 0.7071 * (1 if angle in [45, 135] else -1)
                x2, y2 = 30 + 30 * 0.7071 * (1 if angle in [45, 225] else -1), 30 + 30 * 0.7071 * (1 if angle in [45, 135] else -1)
            draw.line((x1, y1, x2, y2), fill=(255, 165, 0), width=3)
        self.icons["nap"] = img
        
        # Hold ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        draw.ellipse((15, 10, 55, 50), fill=(100, 149, 237))  # Kék kör
        draw.ellipse((10, 10, 40, 40), fill=(255, 255, 255))  # Fehér kör részben átfedve
        self.icons["hold"] = img
        
        # Felhő készítése
        def make_cloud(img, x, y, size, color):
            draw = ImageDraw.Draw(img)
            radius = size // 2
            # Felhő forma rajzolása
            draw.ellipse((x, y, x + size, y + size), fill=color)
            draw.ellipse((x + size*0.7, y, x + size*1.7, y + size), fill=color)
            draw.ellipse((x + size*0.2, y + size*0.4, x + size*1.2, y + size*1.4), fill=color)
            draw.rectangle((x, y + radius, x + size*1.7, y + size), fill=color)
            draw.rectangle((x + size*0.2, y + size*0.7, x + size*1.2, y + size*1.4), fill=color)
            return img
        
        # Napfelhős ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        draw.ellipse((5, 5, 30, 30), fill=(255, 165, 0))  # Nap
        img = make_cloud(img, 20, 20, 30, (200, 200, 200))
        self.icons["nap_felho"] = img
        
        # Holdfelhős ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        draw.ellipse((10, 5, 35, 30), fill=(100, 149, 237))  # Hold
        draw.ellipse((5, 5, 25, 25), fill=(255, 255, 255))
        img = make_cloud(img, 20, 20, 30, (180, 180, 200))
        self.icons["hold_felho"] = img
        
        # Felhős ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 5, 10, 40, (180, 180, 180))
        self.icons["felhos"] = img
        
        # Borult ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 0, 5, 30, (120, 120, 120))
        img = make_cloud(img, 25, 15, 30, (150, 150, 150))
        self.icons["borult"] = img
        
        # Eső ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 5, 5, 40, (150, 150, 150))
        draw = ImageDraw.Draw(img)
        for i in range(3):
            draw.line((15 + i*15, 40, 10 + i*15, 55), fill=(0, 0, 255), width=3)
        self.icons["eso"] = img
        
        # Zápor ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 5, 5, 40, (150, 150, 150))
        draw = ImageDraw.Draw(img)
        for i in range(5):
            draw.line((10 + i*10, 40, 5 + i*10, 55), fill=(0, 0, 255), width=3)
        self.icons["zapor"] = img
        
        # Vihar ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 5, 5, 40, (80, 80, 80))
        draw = ImageDraw.Draw(img)
        # Villám
        draw.polygon([(30, 30), (20, 45), (30, 45), (20, 60)], fill=(255, 255, 0))
        self.icons["vihar"] = img
        
        # Hó ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        img = make_cloud(img, 5, 5, 40, (180, 180, 180))
        draw = ImageDraw.Draw(img)
        for i in range(3):
            x, y = 15 + i*15, 45
            # Hópehely rajzolása
            draw.ellipse((x-5, y-5, x+5, y+5), fill=(255, 255, 255), outline=(0, 0, 255))
            draw.line((x, y-5, x, y+5), fill=(0, 0, 255), width=1)
            draw.line((x-5, y, x+5, y), fill=(0, 0, 255), width=1)
            draw.line((x-4, y-4, x+4, y+4), fill=(0, 0, 255), width=1)
            draw.line((x-4, y+4, x+4, y-4), fill=(0, 0, 255), width=1)
        self.icons["ho"] = img
        
        # Köd ikon
        img = Image.new('RGB', (60, 60), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        for i in range(5):
            draw.rectangle((5, 10 + i*10, 55, 15 + i*10), fill=(200, 200, 200), outline=(150, 150, 150))
        self.icons["kod"] = img

    def get_holiday_name(self, date):
        """Visszaadja az adott dátumra eső ünnepnap nevét, ha van"""
        month_day = date.strftime("%m-%d")
        return FIXED_HOLIDAYS.get(month_day, None)

    def calculate_sun_times(self, sunrise, sunset):
        """Napkelte és napnyugta idő formázása"""
        sunrise_time = datetime.fromtimestamp(sunrise).strftime("%H:%M")
        sunset_time = datetime.fromtimestamp(sunset).strftime("%H:%M")
        return sunrise_time, sunset_time

    def calculate_moon_times(self, date):
        """Holdkelte és holdnyugta idő egyszerű közelítése"""
        # Egy nagyon egyszerű közelítés, mely nem pontos, de demonstrációs célra jó
        base_date = datetime(date.year, 1, 1)
        day_num = (date - base_date).days
        
        # Fáziseltolásos holdmodell
        moon_age = (day_num % 29.5)
        
        # Hold alapértelmezett kelte/nyugta idők
        moonrise_hour = (14 + moon_age * (24 / 29.5)) % 24
        moonset_hour = (2 + moon_age * (24 / 29.5)) % 24
        
        # Földrajzi korrekció
        lat_offset = (LAT - 47) * 0.1  # Budapest: 47° északi szélesség
        moonrise_hour += lat_offset
        moonset_hour += lat_offset
        
        moonrise = f"{int(moonrise_hour):02d}:{int((moonrise_hour % 1) * 60):02d}"
        moonset = f"{int(moonset_hour):02d}:{int((moonset_hour % 1) * 60):02d}"
        
        return moonrise, moonset

    def fetch_weather_data(self):
        """Időjárási adatok lekérése az OpenWeatherMap API-ból"""
        try:
            # Aktuális időjárás lekérése
            current_url = f"https://api.openweathermap.org/data/2.5/weather?q={CITY},{COUNTRY}&units=metric&appid={API_KEY}&lang=hu"
            current_response = requests.get(current_url)
            current_data = current_response.json()
            
            # Előrejelzés lekérése
            forecast_url = f"https://api.openweathermap.org/data/2.5/forecast?q={CITY},{COUNTRY}&units=metric&appid={API_KEY}&lang=hu"
            forecast_response = requests.get(forecast_url)
            forecast_data = forecast_response.json()
            
            return current_data, forecast_data
        except Exception as e:
            logging.error(f"Hiba az időjárás adatok lekérésekor: {e}")
            return None, None

    def process_forecast_data(self, forecast_data):
        """Előrejelzési adatok feldolgozása"""
        daily_forecasts = []
        processed_days = set()
        today = datetime.now().date()
        
        # Következő 4 nap
        for item in forecast_data["list"]:
            date = datetime.fromtimestamp(item["dt"])
            if date.date() == today:
                continue
                
            day_key = date.strftime("%m-%d")
            if day_key not in processed_days and len(daily_forecasts) < 4:
                processed_days.add(day_key)
                daily_forecasts.append({
                    "date": date,
                    "temp": round(item["main"]["temp"]),
                    "icon": item["weather"][0]["icon"],
                    "description": item["weather"][0]["description"]
                })
                
        return daily_forecasts

    def is_severe_weather(self, weather_id, description):
        """Ellenőrzi, hogy van-e szélsőséges időjárás"""
        # Vihar
        if 200 <= weather_id < 300:
            return f"Vihar! {description}"
        
        # Erős eső, felhőszakadás
        if weather_id in [502, 503, 504, 522, 531]:
            return f"Felhőszakadás! {description}"
        
        # Havazás (csak az erősebb)
        if weather_id in [602, 622]:
            return f"Erős havazás! {description}"
        
        # Erős köd
        if weather_id == 741:
            return f"Sűrű köd! {description}"
        
        # Tornádó, hurrikán
        if weather_id in [781, 771]:
            return f"Szélvihar! {description}"
        
        return None

    def update_display(self):
        """Kijelző frissítése aktuális időjárás adatokkal"""
        try:
            current_data, forecast_data = self.fetch_weather_data()
            if not current_data or not forecast_data:
                self.show_error()
                return
                
            # Képernyő előkészítése
            image = Image.new('RGB', (self.width, self.height), color=(255, 255, 255))
            draw = ImageDraw.Draw(image)
            
            # Fejléc
            now = datetime.now()
            date_str = f"{now.year}. {MONTHS[now.month-1]} {now.day}. {DAYS[now.weekday()]}"
            draw.text((self.width//2, 20), "Pécs Időjárás", font=self.fonts['large'], fill=(0, 0, 0), anchor="mt")
            
            # Dátum és esetleges ünnepnap
            holiday_name = self.get_holiday_name(now)
            draw.text((self.width//2, 60), date_str, font=self.fonts['medium'], fill=(0, 0, 0), anchor="mt")
            
            if holiday_name:
                draw.text((self.width//2, 90), holiday_name, font=self.fonts['medium'], fill=(255, 0, 0), anchor="mt")
                
            # Nap/hold időadatok
            sunrise_time, sunset_time = self.calculate_sun_times(
                current_data["sys"]["sunrise"], 
                current_data["sys"]["sunset"]
            )
            moonrise_time, moonset_time = self.calculate_moon_times(now)
            
            # Nap adatok
            draw.text((40, 120), "Nap:", font=self.fonts['small'], fill=(0, 0, 0))
            draw.text((40, 140), f"Kel: {sunrise_time}", font=self.fonts['small'], fill=(0, 0, 0))
            draw.text((40, 160), f"Nyugszik: {sunset_time}", font=self.fonts['small'], fill=(0, 0, 0))
            
            # Hold adatok
            draw.text((self.width-40, 120), "Hold:", font=self.fonts['small'], fill=(0, 0, 0), anchor="rt")
            draw.text((self.width-40, 140), f"Kel: {moonrise_time}", font=self.fonts['small'], fill=(0, 0, 0), anchor="rt")
            draw.text((self.width-40, 160), f"Nyugszik: {moonset_time}", font=self.fonts['small'], fill=(0, 0, 0), anchor="rt")
            
            # Aktuális időjárás
            temp = round(current_data["main"]["temp"])
            description = current_data["weather"][0]["description"]
            wind_speed = round(current_data["wind"]["speed"] * 3.6)  # m/s -> km/h
            humidity = current_data["main"]["humidity"]
            pressure = current_data["main"]["pressure"]
            icon_code = current_data["weather"][0]["icon"]
            weather_id = current_data["weather"][0]["id"]
            
            # Vonalat rajzolunk elválasztónak
            draw.line([(50, 190), (self.width-50, 190)], fill=(0, 0, 255), width=2)
            
            # Hőmérséklet és leírás
            draw.text((self.width//4, 220), f"{temp}°C", font=self.fonts['xlarge'], fill=(255, 0, 0))
            draw.text((self.width//4, 280), description, font=self.fonts['medium'], fill=(0, 0, 0))
            
            # Részletek
            draw.text((self.width//4, 310), f"Szél: {wind_speed} km/h", font=self.fonts['small'], fill=(0, 0, 0))
            draw.text((self.width//4, 330), f"Páratartalom: {humidity}%", font=self.fonts['small'], fill=(0, 0, 0))
            draw.text((self.width//4, 350), f"Légnyomás: {pressure} hPa", font=self.fonts['small'], fill=(0, 0, 0))
            
            # Időjárás ikon
            icon_name = WEATHER_ICONS.get(icon_code, "nap")
            icon = self.icons[icon_name]
            image.paste(icon, (self.width-120, 220))
            
            # Időjárási figyelmeztetések
            severe_weather = self.is_severe_weather(weather_id, description)
            if severe_weather:
                # Piros háttér figyelmeztetéshez
                draw.rectangle([(50, 380), (self.width-50, 410)], fill=(255, 0, 0))
                draw.text((self.width//2, 395), severe_weather, font=self.fonts['medium'], fill=(255, 255, 255), anchor="mm")
            
            # Előrejelzés a következő 4 napra
            forecasts = self.process_forecast_data(forecast_data)
            
            # Előrejelzés vonala
            draw.line([(50, 430), (self.width-50, 430)], fill=(0, 0, 255), width=2)
            
            for i, forecast in enumerate(forecasts):
                x_pos = 80 + i * (self.width - 160) // 4
                
                # Nap neve
                day_name = DAYS[forecast["date"].weekday()]
                draw.text((x_pos, 450), day_name, font=self.fonts['medium'], 
                          fill=(0, 0, 255), anchor="mt")
                
                # Ünnepnap ellenőrzése
                holiday = self.get_holiday_name(forecast["date"])
                if holiday:
                    draw.text((x_pos, 475), holiday, font=self.fonts['small'], 
                             fill=(255, 0, 0), anchor="mt")
                
                # Ikon
                icon_name = WEATHER_ICONS.get(forecast["icon"], "nap")
                icon = self.icons[icon_name].resize((40, 40))
                image.paste(icon, (x_pos-20, 490))
                
                # Hőmérséklet
                draw.text((x_pos, 540), f"{forecast['temp']}°C", font=self.fonts['medium'], 
                         fill=(0, 128, 0), anchor="mt")
            
            # Frissítési idő
            update_time = now.strftime("%H:%M")
            draw.text((self.width-20, self.height-20), f"Frissítve: {update_time}", 
                      font=self.fonts['small'], fill=(100, 100, 100), anchor="rb")
            
            # Megjelenítés a kijelzőn
            frame_buffer = self.epd.getbuffer(image)
            self.epd.display(frame_buffer)
            logging.info("Kijelző frissítve!")
            
        except Exception as e:
            logging.error(f"Hiba a kijelző frissítésekor: {e}")
            self.show_error()

    def show_error(self):
        """Hiba esetén hibaüzenetet jelenít meg"""
        try:
            image = Image.new('RGB', (self.width, self.height), color=(255, 255, 255))
            draw = ImageDraw.Draw(image)
            
            draw.text((self.width//2, 100), "HIBA TÖRTÉNT", font=self.fonts['large'], fill=(255, 0, 0), anchor="mm")
            draw.text((self.width//2, 150), "Nem sikerült betölteni az időjárást", font=self.fonts['medium'], fill=(0, 0, 0), anchor="mm")
            draw.text((self.width//2, 200), "Próbáld újra később", font=self.fonts['medium'], fill=(0, 0, 0), anchor="mm")
            
            now = datetime.now()
            update_time = now.strftime("%H:%M")
            draw.text((self.width-20, self.height-20), f"Frissítve: {update_time}", 
                      font=self.fonts['small'], fill=(100, 100, 100), anchor="rb")
            
            frame_buffer = self.epd.getbuffer(image)
            self.epd.display(frame_buffer)
            logging.info("Hiba képernyő megjelenítve.")
            
        except Exception as e:
            logging.error(f"Hiba a hibaüzenet megjelenítésekor: {e}")

    def run(self):
        """Fő alkalmazás futtatása"""
        try:
            self.update_display()
            
            # Időzítő beállítása 5 percenkénti frissítéshez
            schedule.every(5).minutes.do(self.update_display)
            
            while True:
                schedule.run_pending()
                time.sleep(1)
                
        except KeyboardInterrupt:
            logging.info("Alkalmazás leállítva a felhasználó által.")
            self.cleanup()
        except Exception as e:
            logging.error(f"Váratlan hiba az alkalmazásban: {e}")
            self.cleanup()

    def cleanup(self):
        """Erőforrások felszabadítása"""
        try:
            logging.info("Kijelző tisztítása és alvó mód...")
            self.epd.Clear()
            self.epd.sleep()
        except Exception as e:
            logging.error(f"Hiba a tisztítás során: {e}")

if __name__ == "__main__":
    try:
        display = WeatherDisplay()
        display.run()
    except KeyboardInterrupt:
        logging.info("Program megszakítva")
        exit(0)
EOL

# Systemd service létrehozása
echo "[6/7] Systemd service létrehozása..."
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
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=weather_display

[Install]
WantedBy=multi-user.target
EOL

sudo mv weather_display.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable weather_display.service

# Indítás
echo "[7/7] Szolgáltatás indítása..."
sudo systemctl start weather_display.service

echo "=========================================================="
echo "     Telepítés befejezve!                                 "
echo "     Az időjárás alkalmazás elindult és 5 percenként      "
echo "     frissül. A rendszer újraindításakor automatikusan    "
echo "     újraindul.                                           "
echo "=========================================================="
echo "     Állapot ellenőrzése: sudo systemctl status weather_display"
echo "     Naplók megtekintése: sudo journalctl -u weather_display"
echo "     Hibakeresés: sudo systemctl restart weather_display"
echo "=========================================================="
