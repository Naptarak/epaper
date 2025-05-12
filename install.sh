#!/bin/bash

# install_improved.sh - Speciálisan a 7-színű Waveshare 4.01 inch HAT (F) e-paper kijelzőhöz
# Frissítve: 2025.05.13 - Javított támogatással a 7-színű kijelzőhöz

set -e  # Kilépés hiba esetén
LOG_FILE="install_improved_log.txt"
echo "Telepítés indítása: $(date)" | tee -a "$LOG_FILE"

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

# Telepítési könyvtár létrehozása
INSTALL_DIR="/opt/epaper-display"
VENV_DIR="${INSTALL_DIR}/venv"  # Virtuális környezet könyvtára
echo "Telepítési könyvtár létrehozása: $INSTALL_DIR" | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a telepítési könyvtárat"

# Python verzió ellenőrzése
echo "Python telepítés ellenőrzése..." | tee -a "$LOG_FILE"
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    echo "Python nem található, telepítési kísérlet..." | tee -a "$LOG_FILE"
    sudo apt-get update && sudo apt-get install -y python3 python3-pip 2>> "$LOG_FILE"
    check_success "Nem sikerült telepíteni a Python-t. Próbáld manuálisan: sudo apt-get install python3 python3-pip"
    PYTHON_CMD="python3"
fi

echo "Python parancs: $PYTHON_CMD" | tee -a "$LOG_FILE"
$PYTHON_CMD --version | tee -a "$LOG_FILE"

# Szükséges rendszercsomagok telepítése
echo "Szükséges rendszercsomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get update 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a csomaglistákat"

# Python-venv csomag telepítése virtuális környezethez
echo "Python virtuális környezet támogatás telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-venv 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni a python3-venv csomagot"

# Alapvető rendszercsomagok telepítése
echo "Alapvető rendszercsomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y git xvfb scrot 2>> "$LOG_FILE" || true

# SPI és GPIO modulok telepítése RENDSZERSZINTEN (fontos!)
echo "SPI és GPIO modulok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-rpi.gpio python3-spidev 2>> "$LOG_FILE" || true

# Pillow és NumPy telepítése RENDSZERSZINTEN (fontos!)
echo "Pillow és NumPy telepítése RENDSZERSZINTEN..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-pil python3-numpy 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni a Python képfeldolgozási modulokat"

# Pillow függőségek telepítése
echo "Pillow függőségek telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-pil.imagetk libjpeg-dev zlib1g-dev libfreetype6-dev liblcms2-dev libwebp-dev 2>> "$LOG_FILE" || true

# Weboldal capture eszközök telepítése
echo "Weboldal megjelenítéshez szükséges eszközök telepítése..." | tee -a "$LOG_FILE"
if ! sudo apt-get install -y wkhtmltopdf 2>> "$LOG_FILE"; then
    echo "wkhtmltopdf telepítése sikertelen, cutycapt kipróbálása..." | tee -a "$LOG_FILE"
    sudo apt-get install -y cutycapt 2>> "$LOG_FILE" || echo "cutycapt telepítése is sikertelen, a midori böngészőt fogjuk használni" | tee -a "$LOG_FILE"
fi

# Virtuális környezet létrehozása
echo "Python virtuális környezet létrehozása: $VENV_DIR" | tee -a "$LOG_FILE"
sudo $PYTHON_CMD -m venv "$VENV_DIR" --system-site-packages 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a virtuális környezetet"

# Jogosultságok beállítása a jelenlegi felhasználóra
echo "Jogosultságok beállítása a felhasználó számára: $CURRENT_USER" | tee -a "$LOG_FILE"
sudo chown -R $CURRENT_USER:$CURRENT_USER "$VENV_DIR" 2>> "$LOG_FILE"
sudo chown -R $CURRENT_USER:$CURRENT_USER "$INSTALL_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült beállítani a jogosultságokat"

# Python függőségek telepítése a virtuális környezetbe
echo "Python függőségek telepítése a virtuális környezetbe..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install --upgrade pip 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a pip-et"

# Rendszermodulok ellenőrzése a virtuális környezetben
echo "Rendszermodulok ellenőrzése a virtuális környezetben..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/python" -c "import numpy; import PIL; print('NumPy verzió:', numpy.__version__); print('PIL verzió:', PIL.__version__)" 2>> "$LOG_FILE" || {
    echo "Rendszermodulok nem érhetők el a virtuális környezetben, telepítés a venv-be..." | tee -a "$LOG_FILE"
    "$VENV_DIR/bin/pip" install numpy pillow 2>> "$LOG_FILE"
    check_success "Nem sikerült telepíteni a numpy és pillow csomagokat a virtuális környezetbe"
}

# Waveshare e-paper könyvtár letöltése és telepítése
echo "Waveshare e-paper könyvtár letöltése..." | tee -a "$LOG_FILE"
TEMP_DIR="/tmp/waveshare-install"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Régi könyvtárak eltávolítása
rm -rf e-Paper epd-library-python 2>/dev/null || true

# Waveshare könyvtár klónozása - Több lehetséges forrás kipróbálása
echo "Különböző Waveshare repository-k kipróbálása..." | tee -a "$LOG_FILE"

# Repók sorrendbe rendezve
REPOS=(
    "https://github.com/waveshare/e-Paper.git"
    "https://github.com/waveshareteam/e-Paper.git"
    "https://github.com/soonuse/epd-library-python.git"
)

REPO_SUCCESS=false
for repo in "${REPOS[@]}"; do
    echo "Repository kipróbálása: $repo" | tee -a "$LOG_FILE"
    if git clone "$repo" 2>> "$LOG_FILE"; then
        echo "Repository sikeresen klónozva: $repo" | tee -a "$LOG_FILE"
        if [[ "$repo" == *"soonuse"* ]]; then
            REPO_NAME="epd-library-python"
        else
            REPO_NAME="e-Paper"
        fi
        REPO_SUCCESS=true
        break
    fi
done

if [ "$REPO_SUCCESS" = false ]; then
    handle_error "Nem sikerült klónozni egyetlen repository-t sem. Ellenőrizd az internetkapcsolatot."
fi

# E-paper könyvtárszerkezet létrehozása
echo "E-paper könyvtárszerkezet létrehozása..." | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR/lib/waveshare_epd" 2>> "$LOG_FILE"

# __init__.py létrehozása, hogy proper Python csomag legyen
echo "Python csomag inicializálása..." | tee -a "$LOG_FILE"
sudo touch "$INSTALL_DIR/lib/waveshare_epd/__init__.py" 2>> "$LOG_FILE"
sudo touch "$INSTALL_DIR/lib/__init__.py" 2>> "$LOG_FILE"

# Keressük a 7-színű e-paper modult (epd4in01f.py)
echo "7-színű e-paper modul keresése a repository-ban..." | tee -a "$LOG_FILE"

# A modult közvetlenül keressük
EPAPER_MODULE_FOUND=false
FOUND_EPD4IN01F=$(find "$REPO_NAME" -name "epd4in01f.py" 2>/dev/null)

if [ -n "$FOUND_EPD4IN01F" ]; then
    EPD_MODULE="epd4in01f"
    EPD_MODULE_PATH=$(dirname "$FOUND_EPD4IN01F")
    echo "Sikeresen megtalálva a 7-színű e-paper modul: $FOUND_EPD4IN01F" | tee -a "$LOG_FILE"
    EPAPER_MODULE_FOUND=true
else
    echo "A 7-színű e-paper modul (epd4in01f.py) nem található. Keresés más 4.01 inch modulok után..." | tee -a "$LOG_FILE"
    
    # Keresünk bármilyen 4in01 modult
    FOUND_EPD4IN01=$(find "$REPO_NAME" -name "epd4in01*.py" 2>/dev/null)
    
    if [ -n "$FOUND_EPD4IN01" ]; then
        EPD_MODULE_PATH=$(dirname "$(echo "$FOUND_EPD4IN01" | head -n1)")
        EPD_MODULE=$(basename "$(echo "$FOUND_EPD4IN01" | head -n1)" .py)
        echo "Alternatív 4.01 inch modul találva: $EPD_MODULE" | tee -a "$LOG_FILE"
        EPAPER_MODULE_FOUND=true
    else
        echo "Semmilyen 4.01 inch e-paper modul nem található. Visszaesés bármilyen e-paper modulra..." | tee -a "$LOG_FILE"
        
        # Próbáljunk meg bármilyen epd modult találni
        FOUND_EPD=$(find "$REPO_NAME" -name "epd*.py" 2>/dev/null)
        
        if [ -n "$FOUND_EPD" ]; then
            EPD_MODULE_PATH=$(dirname "$(echo "$FOUND_EPD" | head -n1)")
            EPD_MODULE=$(basename "$(echo "$FOUND_EPD" | head -n1)" .py)
            echo "Általános e-paper modul találva: $EPD_MODULE" | tee -a "$LOG_FILE"
            EPAPER_MODULE_FOUND=true
        fi
    fi
fi

# Ha nem találtunk modult, létrehozunk egy 7-színű epd4in01f.py fájlt
if [ "$EPAPER_MODULE_FOUND" = false ]; then
    echo "Nem sikerült találni megfelelő modult, 7-színű e-paper modul létrehozása manuálisan..." | tee -a "$LOG_FILE"
    EPD_MODULE="epd4in01f"
    EPD_MODULE_PATH="$INSTALL_DIR/lib/waveshare_epd"
    
    # 7-színű e-paper modul kézi létrehozása
    cat > "$TEMP_DIR/epd4in01f.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import logging
import time
from PIL import Image

# epdconfig
import epdconfig

class EPD:
    # 7-színű e-Paper kijelző specifikus konstansok
    WIDTH = 640
    HEIGHT = 400
    
    # Command konstansok
    PANEL_SETTING = 0x00
    POWER_SETTING = 0x01
    POWER_OFF = 0x02
    POWER_OFF_SEQUENCE_SETTING = 0x03
    POWER_ON = 0x04
    POWER_ON_MEASURE = 0x05
    BOOSTER_SOFT_START = 0x06
    DEEP_SLEEP = 0x07
    DATA_START_TRANSMISSION_1 = 0x10
    DATA_STOP = 0x11
    DISPLAY_REFRESH = 0x12
    DATA_START_TRANSMISSION_2 = 0x13
    PLL_CONTROL = 0x30
    TEMPERATURE_SENSOR_COMMAND = 0x40
    TEMPERATURE_SENSOR_CALIBRATION = 0x41
    TEMPERATURE_SENSOR_WRITE = 0x42
    TEMPERATURE_SENSOR_READ = 0x43
    VCOM_AND_DATA_INTERVAL_SETTING = 0x50
    LOW_POWER_DETECTION = 0x51
    TCON_SETTING = 0x60
    TCON_RESOLUTION = 0x61
    SOURCE_AND_GATE_START_SETTING = 0x62
    GET_STATUS = 0x71
    AUTO_MEASURE_VCOM = 0x80
    VCOM_VALUE = 0x81
    VCM_DC_SETTING = 0x82
    PARTIAL_WINDOW = 0x90
    PARTIAL_IN = 0x91
    PARTIAL_OUT = 0x92
    PROGRAM_MODE = 0xA0
    ACTIVE_PROGRAM = 0xA1
    READ_OTP_DATA = 0xA2
    POWER_SAVING = 0xE3
    
    def __init__(self):
        self.width = self.WIDTH
        self.height = self.HEIGHT
        self.rotate = 0
        
        self.BLACK = 0x000000  # 0
        self.WHITE = 0xffffff  # 1
        self.GREEN = 0x00ff00  # 2
        self.BLUE = 0x0000ff   # 3
        self.RED = 0xff0000    # 4
        self.YELLOW = 0xffff00 # 5
        self.ORANGE = 0xffa500 # 6
        
    def init(self):
        if (epdconfig.module_init() != 0):
            return -1
        
        # 7-színű e-Paper kijelző inicializálása
        self.reset()
        
        self.send_command(self.POWER_SETTING)
        self.send_data(0x07)
        self.send_data(0x07)
        self.send_data(0x3f)
        self.send_data(0x3f)
        
        self.send_command(self.POWER_ON)
        time.sleep(0.1)
        self.wait_until_idle()
        
        self.send_command(self.PANEL_SETTING)
        self.send_data(0x0f)
        
        self.send_command(self.TCON_RESOLUTION)
        self.send_data(0x02)
        self.send_data(0x80)
        self.send_data(0x01)
        self.send_data(0x90)
        
        self.send_command(self.VCOM_AND_DATA_INTERVAL_SETTING)
        self.send_data(0x11)
        self.send_data(0x07)
        
        self.send_command(self.TCON_SETTING)
        self.send_data(0x22)
        
        return 0

    def wait_until_idle(self):
        logging.debug("e-Paper busy")
        while(epdconfig.digital_read(epdconfig.BUSY_PIN) == 0):
            epdconfig.delay_ms(10)
        logging.debug("e-Paper busy release")

    def reset(self):
        epdconfig.digital_write(epdconfig.RST_PIN, 1)
        epdconfig.delay_ms(200) 
        epdconfig.digital_write(epdconfig.RST_PIN, 0)
        epdconfig.delay_ms(5)
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
        img = image
        if img.mode != '1' and img.mode != 'RGB':
            img = img.convert('RGB')

        image_monocolor = Image.new('1', (self.width, self.height), 255)
        imwidth, imheight = img.size
        
        if imwidth != self.width or imheight != self.height:
            logging.warning("A kép átméretezése szükséges a méretkülönbség miatt")
            img = img.resize((self.width, self.height))
        
        logging.info("7-színű megjelenítés kezdése: %dx%d", self.width, self.height)
        
        # A 7-színű megjelenítés itt történik
        self.send_command(self.DATA_START_TRANSMISSION_1)
        
        pixels = img.load()
        for y in range(self.height):
            for x in range(self.width):
                if img.mode == '1':  # Fekete-fehér kép
                    if pixels[x, y] == 0:  # Fekete
                        self.send_data(0x00)
                    else:  # Fehér
                        self.send_data(0x01)
                else:  # RGB kép
                    r, g, b = pixels[x, y]
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
                    else:  # Ha egyik sem, akkor fehér
                        self.send_data(0x01)
        
        self.send_command(self.DISPLAY_REFRESH)
        self.wait_until_idle()
        
        return 0
        
    def getbuffer(self, image):
        # A 7-színű kijelző közvetlenül használja a PIL Image objektumot
        return image
    
    def sleep(self):
        self.send_command(self.POWER_OFF)
        self.wait_until_idle()
        self.send_command(self.DEEP_SLEEP)
        self.send_data(0xA5)
        
    def Clear(self, color=0xFF):
        # Létrehozunk egy fehér képet
        image = Image.new('RGB', (self.width, self.height), 'white')
        self.display(image)
EOF
    
    # epdconfig.py modul kézi létrehozása
    cat > "$TEMP_DIR/epdconfig.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import os
import logging
import sys
import time

# Pin definíciók
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

class RaspberryPi:
    def __init__(self):
        try:
            import spidev
            import RPi.GPIO
            
            self.GPIO = RPi.GPIO
            self.SPI = spidev.SpiDev()
            
            self.module_init()
            self.module_initialized = True
        except Exception as e:
            logging.error("RaspberryPi GPIO/SPI inicializálási hiba: %s", e)
            self.module_initialized = False
            raise

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
        
        # Tüskék beállítása
        self.GPIO.setup(RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(BUSY_PIN, self.GPIO.IN)
        
        # SPI beállítások
        self.SPI.open(0, 0)
        self.SPI.max_speed_hz = 4000000
        self.SPI.mode = 0b00
        return 0

    def module_exit(self):
        logging.debug("spi end")
        self.SPI.close()

        logging.debug("close 5V, Module enters 0 power consumption ...")
        self.GPIO.output(RST_PIN, 0)
        self.GPIO.output(DC_PIN, 0)

        self.GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])

# Detektáljuk a platformot
if os.path.exists('/sys/bus/platform/drivers/gpiomem-bcm2835'):
    implementation = RaspberryPi()
else:
    raise RuntimeError("Nem támogatott platform! Csak Raspberry Pi támogatott!")

# Export a funkciókat modulszintre
for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))

# Export a pin konstansokat
# A 7-színű kijelzőhöz optimalizált pin beállítások
BUSY_PIN = 24
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
EOF

    sudo cp "$TEMP_DIR/epd4in01f.py" "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
    sudo cp "$TEMP_DIR/epdconfig.py" "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
else
    # Másolás a Waveshare könyvtárból
    echo "A talált modul másolása: $EPD_MODULE" | tee -a "$LOG_FILE"
    
    # Először másoljuk a teljes waveshare_epd könyvtárat, ha megtaláltuk
    echo "Waveshare EPD könyvtár másolása $EPD_MODULE_PATH -> $INSTALL_DIR/lib/waveshare_epd" | tee -a "$LOG_FILE"
    sudo cp -r "$EPD_MODULE_PATH"/* "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE" || true
    
    # Ellenőrizzük az epdconfig.py fájlt
    if [ ! -f "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" ]; then
        echo "epdconfig.py hiányzik, keresés..." | tee -a "$LOG_FILE"
        EPDCONFIG_FILES=$(find "$TEMP_DIR/$REPO_NAME" -name "epdconfig.py" 2>/dev/null)
        
        if [ -n "$EPDCONFIG_FILES" ]; then
            echo "epdconfig.py másolása: $(echo "$EPDCONFIG_FILES" | head -n1) -> $INSTALL_DIR/lib/waveshare_epd/" | tee -a "$LOG_FILE"
            sudo cp "$(echo "$EPDCONFIG_FILES" | head -n1)" "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
        else
            echo "epdconfig.py nem található, egyszerű epdconfig.py létrehozása..." | tee -a "$LOG_FILE"
            
            # Egyszerű epdconfig.py létrehozása
            cat > "$TEMP_DIR/epdconfig.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import os
import logging
import sys
import time

# Pin definíciók a 7-színű kijelzőhöz
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

class RaspberryPi:
    def __init__(self):
        try:
            import spidev
            import RPi.GPIO
            
            self.GPIO = RPi.GPIO
            self.SPI = spidev.SpiDev()
            
            self.module_init()
            self.module_initialized = True
        except Exception as e:
            logging.error("RaspberryPi GPIO/SPI inicializálási hiba: %s", e)
            self.module_initialized = False
            raise

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
        
        # Tüskék beállítása
        self.GPIO.setup(RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(BUSY_PIN, self.GPIO.IN)
        
        # SPI beállítások
        self.SPI.open(0, 0)
        self.SPI.max_speed_hz = 4000000
        self.SPI.mode = 0b00
        return 0

    def module_exit(self):
        logging.debug("spi end")
        self.SPI.close()

        logging.debug("close 5V, Module enters 0 power consumption ...")
        self.GPIO.output(RST_PIN, 0)
        self.GPIO.output(DC_PIN, 0)

        self.GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])

# Detektáljuk a platformot
if os.path.exists('/sys/bus/platform/drivers/gpiomem-bcm2835'):
    implementation = RaspberryPi()
else:
    raise RuntimeError("Nem támogatott platform! Csak Raspberry Pi támogatott!")

# Export a funkciókat modulszintre
for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))

# Export a pin konstansokat
BUSY_PIN = 24
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
EOF
            sudo cp "$TEMP_DIR/epdconfig.py" "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
        fi
    fi
fi

# Pin beállítások ellenőrzése - különös tekintettel a 7-színű kijelzőre
echo "7-színű kijelző pin beállítások ellenőrzése és javítása..." | tee -a "$LOG_FILE"
if [ -f "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" ]; then
    # Biztosítjuk, hogy a helyes pin beállítások vannak használva
    sudo sed -i 's/RST_PIN\s*=\s*[0-9]\+/RST_PIN = 17/g' "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" 2>> "$LOG_FILE"
    sudo sed -i 's/DC_PIN\s*=\s*[0-9]\+/DC_PIN = 25/g' "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" 2>> "$LOG_FILE" 
    sudo sed -i 's/CS_PIN\s*=\s*[0-9]\+/CS_PIN = 8/g' "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" 2>> "$LOG_FILE"
    sudo sed -i 's/BUSY_PIN\s*=\s*[0-9]\+/BUSY_PIN = 24/g' "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" 2>> "$LOG_FILE"
fi

# Relatív importok javítása
echo "Relatív importok javítása a modul fájlokban..." | tee -a "$LOG_FILE"
for pyfile in $(find "$INSTALL_DIR/lib/waveshare_epd" -name "*.py"); do
    # Relatív importok cseréje abszolút importokra
    sudo sed -i 's/from \. import epdconfig/import epdconfig/g' "$pyfile" 2>> "$LOG_FILE"
done

echo "Használt e-paper modul: $EPD_MODULE" | tee -a "$LOG_FILE"

# SPI interfész engedélyezése
echo "SPI interfész engedélyezése..." | tee -a "$LOG_FILE"
if ! grep -q "dtparam=spi=on" /boot/config.txt; then
    echo "SPI nincs engedélyezve, engedélyezés..." | tee -a "$LOG_FILE"
    sudo sh -c "echo 'dtparam=spi=on' >> /boot/config.txt" 2>> "$LOG_FILE"
    check_success "Nem sikerült engedélyezni az SPI interfészt"
    echo "SPI engedélyezve, a telepítés után újraindítás szükséges" | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=true
else
    echo "SPI már engedélyezve van" | tee -a "$LOG_FILE"
    REBOOT_REQUIRED=false
fi

# Részletes teszt szkript létrehozása a 7-színű kijelzőhöz
echo "Részletes teszt szkript létrehozása a 7-színű kijelző működésének ellenőrzéséhez..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/test_display.py" << EOF
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
logging.info("Elérési út: %s", sys.path)
logging.info("Elérhető modulok a lib/waveshare_epd könyvtárban:")
for file in os.listdir(waveshare_dir):
    logging.info("  - %s", file)

try:
    # Importálások
    logging.info("NumPy és PIL importálása...")
    try:
        import numpy
        logging.info("NumPy verzió: %s", numpy.__version__)
    except ImportError as e:
        logging.warning("NumPy importálási hiba: %s - ez nem kritikus", e)
    
    try:
        import PIL
        logging.info("PIL verzió: %s", PIL.__version__)
    except ImportError as e:
        logging.error("PIL importálási hiba: %s", e)
        raise
    
    # GPIO modul ellenőrzése
    logging.info("RPi.GPIO ellenőrzése...")
    try:
        import RPi.GPIO
        logging.info("RPi.GPIO verzió: %s", RPi.GPIO.VERSION)
    except ImportError as e:
        logging.error("RPi.GPIO importálási hiba: %s", e)
        raise
    
    # SPI modul ellenőrzése
    logging.info("spidev ellenőrzése...")
    try:
        import spidev
        logging.info("spidev elérhető")
    except ImportError as e:
        logging.error("spidev importálási hiba: %s", e)
        raise
    
    # epdconfig.py importálása
    logging.info("epdconfig.py importálása...")
    try:
        sys.path.insert(0, waveshare_dir)  # waveshare_epd könyvtárat prioritássá tesszük
        import epdconfig
        logging.info("epdconfig sikeresen importálva")
    except ImportError as e:
        logging.error("epdconfig importálási hiba: %s", e)
        raise
    
    # e-Paper modul importálása - először megpróbáljuk a 7-színű modult
    module_name = "$EPD_MODULE"
    logging.info("Megpróbáljuk importálni a modult: %s", module_name)
    
    epd = None
    try:
        # Próbáljuk először a waveshare_epd csomagból
        logging.info("Importálás a waveshare_epd csomagból...")
        exec("from waveshare_epd import " + module_name)
        epd_module = sys.modules.get("waveshare_epd." + module_name)
        if epd_module:
            epd = epd_module.EPD()
            logging.info("Modul sikeresen importálva a waveshare_epd csomagból")
    except ImportError as e:
        logging.warning("Import hiba a waveshare_epd csomagból: %s", e)
        try:
            # Próbáljuk direkt importtal
            logging.info("Direkt import próbálása...")
            exec("import " + module_name)
            epd_module = sys.modules.get(module_name)
            if epd_module:
                epd = epd_module.EPD()
                logging.info("Modul sikeresen importálva közvetlenül")
        except ImportError as e2:
            logging.error("Közvetlen import is sikertelen: %s", e2)
            raise
    
    if not epd:
        logging.error("Nem sikerült létrehozni az EPD objektumot!")
        raise ImportError("EPD objektum létrehozása sikertelen")
    
    logging.info("EPD objektum létrehozva")
    logging.info("Kijelző méretei: %s x %s", epd.width, epd.height)
    
    # Ellenőrizzük a 7-színű kijelző specifikus tulajdonságait
    try:
        logging.info("EPD objektum változói:")
        for name in dir(epd):
            if not name.startswith('__'):
                value = getattr(epd, name)
                if not callable(value):
                    logging.info("  %s = %s", name, value)
        
        # Ellenőrizzük, hogy ez tényleg egy 7-színű kijelző
        if hasattr(epd, 'BLACK') and hasattr(epd, 'WHITE') and hasattr(epd, 'GREEN') and hasattr(epd, 'RED'):
            logging.info("7-színű kijelző tulajdonságok megtalálva")
        else:
            logging.warning("7-színű kijelző tulajdonságok hiányoznak - nem biztos, hogy ez 7-színű kijelző")
    except Exception as e:
        logging.warning("Kijelző tulajdonságok ellenőrzése sikertelen: %s", e)
    
    # Kijelző inicializálása
    logging.info("Kijelző inicializálása...")
    init_result = epd.init()
    logging.info("Inicializálás eredménye: %s", init_result)
    
    # Kijelző törlése
    logging.info("Kijelző törlése...")
    try:
        epd.Clear()
        logging.info("Kijelző törölve")
    except Exception as e:
        logging.warning("Kijelző törlése nem sikerült: %s", e)
        logging.warning("Folytatás a törlés nélkül...")
    
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
    
    # Szöveg kirajzolása
    draw.text((50, 40), '7-színű E-Paper teszt', fill='black', font=font_large)
    draw.text((50, 100), 'Sikeres inicializálás!', fill='red', font=font_medium)
    draw.text((50, 150), 'Modul: ' + module_name, fill='blue', font=font_small)
    
    # 7-színű teszt
    colors = [
        ('Fekete', (0, 0, 0)),
        ('Fehér', (255, 255, 255)),
        ('Piros', (255, 0, 0)),
        ('Zöld', (0, 255, 0)),
        ('Kék', (0, 0, 255)),
        ('Sárga', (255, 255, 0)),
        ('Narancs', (255, 165, 0))
    ]
    
    y_pos = 200
    for i, (color_name, color) in enumerate(colors):
        # Színes téglalap rajzolása
        draw.rectangle([(50, y_pos), (150, y_pos + 30)], fill=color)
        
        # Színnév kiírása
        text_color = 'black' if color_name in ['Fehér', 'Sárga', 'Zöld', 'Narancs'] else 'white'
        draw.text((160, y_pos + 5), color_name, fill='black', font=font_small)
        
        y_pos += 40
    
    # Kép megjelenítése
    logging.info("Kép megjelenítése a kijelzőn...")
    try:
        # getbuffer hívása előtt ellenőrizzük a módszert
        logging.info("getbuffer metódus hívása...")
        buffer = epd.getbuffer(image)
        logging.info("getbuffer sikeres, buffer típusa: %s", type(buffer))
        
        # display metódus hívása
        logging.info("display metódus hívása...")
        epd.display(buffer)
        logging.info("Kép megjelenítve")
    except Exception as e:
        logging.error("Hiba a kép megjelenítésekor: %s", e)
        import traceback
        logging.error(traceback.format_exc())
        raise
    
    # Alvó mód
    logging.info("Kijelző alvó módba helyezése...")
    epd.sleep()
    logging.info("Kijelző alvó módban")
    
    logging.info("Teszt sikeresen befejezve.")
    print("Teszt sikeresen befejezve. Ellenőrizd a kijelzőt!")
    
except ImportError as e:
    logging.error("Importálási hiba: %s", e)
    import traceback
    logging.error(traceback.format_exc())
    print(f"Importálási hiba: {e}")
    print("Ellenőrizd a log fájlt: /var/log/epaper-test.log")
    sys.exit(1)
except Exception as e:
    logging.error("Hiba történt: %s", e, exc_info=True)
    import traceback
    logging.error(traceback.format_exc())
    print(f"Hiba történt: {e}")
    print("Ellenőrizd a log fájlt: /var/log/epaper-test.log")
    sys.exit(1)
EOF

# Teszt szkript futtathatóvá tétele
sudo chmod +x "$INSTALL_DIR/test_display.py"
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/test_display.py"

# Weboldal megjelenítő szkript létrehozása a 7-színű kijelzőhöz
echo "Weboldal megjelenítő szkript létrehozása a 7-színű kijelzőhöz..." | tee -a "$LOG_FILE"
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
        # Garantáljuk, hogy a lib/waveshare_epd legyen az első az import path-ban
        if waveshare_dir in sys.path:
            sys.path.remove(waveshare_dir)
        sys.path.insert(0, waveshare_dir)
        
        logger.info("epdconfig importálása...")
        try:
            import epdconfig
            logger.info("epdconfig sikeresen importálva")
        except ImportError as e:
            logger.error("epdconfig importálási hiba: %s", e)
            raise
        
        logger.info("E-paper modul importálása: $EPD_MODULE")
        # Importálási kísérlet a waveshare_epd csomagból
        epd = None
        try:
            # Próbáljuk először a waveshare_epd csomagból
            logger.info("Importálás a waveshare_epd csomagból...")
            exec("from waveshare_epd import $EPD_MODULE")
            epd_module = sys.modules.get("waveshare_epd.$EPD_MODULE")
            if epd_module:
                epd = epd_module.EPD()
                logger.info("Modul sikeresen importálva a waveshare_epd csomagból")
        except ImportError as e:
            logger.warning(f"Nem sikerült importálni a waveshare_epd csomagból: {e}")
            logger.warning("Direkt importálási kísérlet...")
            try:
                # Próbáljuk direkt importtal
                exec("import $EPD_MODULE")
                epd_module = sys.modules.get("$EPD_MODULE")
                if epd_module:
                    epd = epd_module.EPD()
                    logger.info("Modul sikeresen importálva közvetlenül")
            except ImportError as e2:
                logger.error(f"Közvetlen import is sikertelen: {e2}")
                raise
        
        if not epd:
            logger.error("Nem sikerült létrehozni az EPD objektumot!")
            raise ImportError("EPD objektum létrehozása sikertelen")
        
        logger.info("EPD objektum létrehozva")
        logger.info("Kijelző méretei: %s x %s", epd.width, epd.height)
        
        # Inicializálás
        logger.info("Kijelző inicializálása...")
        epd.init()
        logger.info("Inicializálás sikeres")
        
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
        buffer = epd.getbuffer(image)
        epd.display(buffer)
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
            if draw.textsize(test_line, font=font_small)[0] <= epd.width - 100:
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
        buffer = epd.getbuffer(image)
        epd.display(buffer)
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
            epd.display(epd.getbuffer(image))
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
                            display_error_message(epd, "Nem sikerült megjeleníteni a képet háromszor egymás után. Kérlek ellenőrizd a rendszert!")
                else:
                    logger.error("Nem sikerült képernyőképet készíteni a weboldalról")
                    failed_attempts += 1
                    if failed_attempts >= 3:
                        display_error_message(epd, "Nem sikerült képernyőképet készíteni a weboldalról háromszor egymás után. Kérlek ellenőrizd a hálózatot és a weboldalt!")
            except Exception as e:
                logger.error(f"Hiba a frissítési ciklusban: {e}")
                logger.error(traceback.format_exc())
                failed_attempts += 1
                if failed_attempts >= 3:
                    try:
                        display_error_message(epd, f"Ismétlődő hiba: {str(e)[:50]}... Újraindítás szükséges lehet.")
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

# A szkript futtathatóvá tétele és virtuális környezet használata
echo "Python szkript konfigurálása..." | tee -a "$LOG_FILE"
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/display_webpage.py"
sudo chmod +x "$INSTALL_DIR/display_webpage.py" 2>> "$LOG_FILE"
check_success "Nem sikerült futtathatóvá tenni a szkriptet"

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

# Log könyvtárak és fájlok létrehozása, jogosultságok beállítása
echo "Log könyvtárak létrehozása és jogosultságok beállítása..." | tee -a "$LOG_FILE"
sudo touch /var/log/epaper-display.log /var/log/epaper-display-stdout.log /var/log/epaper-display-stderr.log /var/log/epaper-test.log 2>> "$LOG_FILE"
sudo chown $CURRENT_USER:$CURRENT_USER /var/log/epaper-display*.log /var/log/epaper-test.log 2>> "$LOG_FILE"

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

# A konfigurációs szkript futtathatóvá tétele
sudo sed -i "1s|.*|#!$VENV_DIR/bin/python3|" "$INSTALL_DIR/configure.py"
sudo chmod +x "$INSTALL_DIR/configure.py" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a konfigurációs eszközt"

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
        sudo $INSTALL_DIR/test_display.py
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

# uninstall.sh - Eltávolító szkript a 7-színű e-paper weblap megjelenítőhöz
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

# Maradványok ellenőrzése és figyelmeztetés
echo "Maradványok ellenőrzése..." | tee -a "\$LOG_FILE"
remaining_files=\$(find /usr/local/bin -name "epaper-*" 2>/dev/null || true)
if [ -n "\$remaining_files" ]; then
    echo "Figyelmeztetés: Az alábbi szkriptek még mindig jelen vannak:" | tee -a "\$LOG_FILE"
    echo "\$remaining_files" | tee -a "\$LOG_FILE"
    echo "Manuálisan eltávolíthatod őket: sudo rm [fájl neve]" | tee -a "\$LOG_FILE"
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
sudo chmod +x "$INSTALL_DIR/uninstall.sh" 2>> "$LOG_FILE"

# URL bekérése
echo "Kérlek add meg az URL-t, amit meg szeretnél jeleníteni:"
read url
$VENV_DIR/bin/python3 "$INSTALL_DIR/configure.py" "$url" 2>> "$LOG_FILE"
check_success "Nem sikerült konfigurálni az URL-t"

# Szolgáltatás engedélyezése és indítása
echo "Szolgáltatás engedélyezése..." | tee -a "$LOG_FILE"
sudo systemctl daemon-reload 2>> "$LOG_FILE"
sudo systemctl enable epaper-display.service 2>> "$LOG_FILE"
check_success "Nem sikerült engedélyezni a szolgáltatást"

# Teszt szkript futtatása
echo "Teszt szkript futtatása a 7-színű kijelző ellenőrzéséhez..." | tee -a "$LOG_FILE"
echo "A teszt kiírja a kijelzőre, hogy '7-színű E-Paper teszt'"
sudo $INSTALL_DIR/test_display.py

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
echo "E-Paper modul: $EPD_MODULE" | tee -a "$LOG_FILE"
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
echo "  1. Ha a kijelző nem működik, ellenőrizd a logokat: epaper-logs test" | tee -a "$LOG_FILE"
echo "  2. Ellenőrizd az SPI interfészt: lsmod | grep spi" | tee -a "$LOG_FILE"
echo "  3. Ellenőrizd a GPIO jogosultságokat: sudo usermod -a -G gpio,spi $CURRENT_USER" | tee -a "$LOG_FILE"
echo "  4. Újraindítás segíthet az SPI és GPIO problémák megoldásában" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$REBOOT_REQUIRED" = true ]; then
    echo "A telepítés befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "Telepítés befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"
