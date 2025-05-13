#!/bin/bash

# install_7color_4in01f_fixed.sh - Finomhangolt telepítő szkript Waveshare 4.01 inch HAT (F) 7-színű e-paper kijelzőhöz
# Készítve: 2025.05.14

set -e  # Kilépés hiba esetén
LOG_FILE="install_7color_log.txt"
echo "Finomhangolt 7-színű e-Paper 4.01 inch telepítés indítása: $(date)" | tee -a "$LOG_FILE"

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
echo "Korábbi telepítés eltávolítása..." | tee -a "$LOG_FILE"

# Szolgáltatás leállítása és letiltása
if systemctl is-active --quiet epaper-display.service; then
    sudo systemctl stop epaper-display.service 2>> "$LOG_FILE" || true
fi

if systemctl is-enabled --quiet epaper-display.service 2>/dev/null; then
    sudo systemctl disable epaper-display.service 2>> "$LOG_FILE" || true
fi

if [ -f /etc/systemd/system/epaper-display.service ]; then
    sudo rm /etc/systemd/system/epaper-display.service 2>> "$LOG_FILE" || true
    sudo systemctl daemon-reload 2>> "$LOG_FILE" || true
fi

# Kényelmi szkriptek és futó háttérfolyamatok eltávolítása
for script in epaper-config epaper-service epaper-logs; do
    if [ -f /usr/local/bin/$script ]; then
        sudo rm /usr/local/bin/$script 2>> "$LOG_FILE" || true
    fi
done

sudo pkill -f "display_webpage.py" 2>/dev/null || true
sudo pkill -f "Xvfb" 2>/dev/null || true
sudo pkill -f "midori" 2>/dev/null || true
sudo pkill -f "wkhtmltoimage" 2>/dev/null || true
sudo pkill -f "cutycapt" 2>/dev/null || true

# Ideiglenes könyvtárak és régi telepítés törlése
sudo rm -rf /tmp/screenshot /tmp/waveshare-install 2>/dev/null || true

INSTALL_DIR="/opt/epaper-display"
if [ -d "$INSTALL_DIR" ]; then
    sudo rm -rf "$INSTALL_DIR" 2>> "$LOG_FILE" || true
fi

# Új könyvtár létrehozása
echo "Új telepítési könyvtár létrehozása: $INSTALL_DIR" | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a telepítési könyvtárat"
sudo chown $CURRENT_USER:$CURRENT_USER "$INSTALL_DIR" 2>> "$LOG_FILE"

# Python és szükséges rendszercsomagok telepítése
echo "Rendszerfrissítés és csomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get update 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a csomaglistákat"

# KRITIKUS: Rendszerszintű csomagokat telepítünk, hogy ne kelljen NumPy-t fordítani
echo "Rendszerszintű Python csomagok telepítése..." | tee -a "$LOG_FILE"
sudo apt-get install -y python3-pip python3-venv python3-rpi.gpio python3-spidev python3-pil python3-numpy xvfb git 2>> "$LOG_FILE"
check_success "Nem sikerült telepíteni a szükséges csomagokat"

# Opcionális weboldal megjelenítő eszközök telepítése
sudo apt-get install -y scrot wkhtmltopdf 2>> "$LOG_FILE" || sudo apt-get install -y cutycapt 2>> "$LOG_FILE" || true

# Virtuális környezet könyvtára
VENV_DIR="${INSTALL_DIR}/venv"

# Virtuális környezet létrehozása RENDSZERMODULOKKAL - ez a kulcs a gyors telepítéshez!
echo "Python virtuális környezet létrehozása RENDSZERMODULOKKAL: $VENV_DIR" | tee -a "$LOG_FILE"
python3 -m venv "$VENV_DIR" --system-site-packages 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a virtuális környezetet"

sudo chown -R $CURRENT_USER:$CURRENT_USER "$VENV_DIR" 2>> "$LOG_FILE"
check_success "Nem sikerült beállítani a jogosultságokat a virtuális környezethez"

# Pip frissítése a virtuális környezetben
echo "Python pip frissítése a virtuális környezetben..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/pip" install --upgrade pip 2>> "$LOG_FILE"
check_success "Nem sikerült frissíteni a pip-et"

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

# Speciális epdconfig.py modul létrehozása az eredeti Waveshare pinek szerint
echo "epdconfig.py létrehozása a hivatalos Waveshare pinekkel..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-
# Waveshare hivatalos epdconfig

import os
import logging
import sys
import time

# GPIO Pin definíciók a 7-színű 4.01 inch kijelzőhöz
# A Waveshare hivatalos dokumentációja alapján
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
BUSY_PIN = 24

class RaspberryPi:
    def __init__(self):
        try:
            import RPi.GPIO
            import spidev
            self.GPIO = RPi.GPIO
            self.SPI = spidev.SpiDev()
        except ImportError as e:
            raise ImportError("RPi.GPIO vagy spidev importálási hiba: {}".format(e))

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
        logging.debug("GPIO mode BCM")
        self.GPIO.setmode(self.GPIO.BCM)
        self.GPIO.setwarnings(False)
        
        logging.debug("GPIO setup")
        self.GPIO.setup(RST_PIN, self.GPIO.OUT)
        self.GPIO.setup(DC_PIN, self.GPIO.OUT)
        self.GPIO.setup(CS_PIN, self.GPIO.OUT)
        self.GPIO.setup(BUSY_PIN, self.GPIO.IN)
        
        logging.debug("SPI setup")
        self.SPI.open(0, 0)
        # Fontos: Sebességcsökkentés a stabil működéshez
        self.SPI.max_speed_hz = 2000000
        self.SPI.mode = 0b00
        return 0

    def module_exit(self):
        logging.debug("SPI close")
        self.SPI.close()
        
        logging.debug("GPIO cleanup")
        self.GPIO.output(RST_PIN, 0)
        self.GPIO.output(DC_PIN, 0)
        self.GPIO.output(CS_PIN, 0)

        self.GPIO.cleanup([RST_PIN, DC_PIN, CS_PIN, BUSY_PIN])

# Csak Raspberry Pi implementáció
implementation = RaspberryPi()

# Függvények exportálása
for func in [x for x in dir(implementation) if not x.startswith('_')]:
    setattr(sys.modules[__name__], func, getattr(implementation, func))

# Konstansok
BUSY_PIN = 24
RST_PIN = 17
DC_PIN = 25
CS_PIN = 8
EOF

# Speciális epd4in01f.py modul létrehozása a finomított működéssel
echo "A precíz epd4in01f.py létrehozása a 7-színű 4.01 inch kijelzőhöz..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/lib/waveshare_epd/epd4in01f.py" << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-
# A Waveshare 4.01inch 7-Color E-Ink HAT driver - Finomhangolt, optimalizált

import logging
import time
from PIL import Image

# epdconfig importálása
import epdconfig

class EPD:
    # 4.01 inch 7-Color kijelző specifikációi
    WIDTH = 640
    HEIGHT = 400
    
    # Definiáljuk a 7 színt
    BLACK = 0x00     # 0
    WHITE = 0x01     # 1
    GREEN = 0x02     # 2
    BLUE = 0x03      # 3
    RED = 0x04       # 4
    YELLOW = 0x05    # 5
    ORANGE = 0x06    # 6
    
    # Specifikus parancs konstansok a tényleges Waveshare 4.01inch 7-Color kijelzőhöz
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
    DATA_START_TRANSMISSION_2 = 0x13
    LUT_FOR_VCOM = 0x20
    LUT_BLUE = 0x21
    LUT_WHITE = 0x22
    LUT_GRAY_1 = 0x23
    LUT_GRAY_2 = 0x24
    LUT_RED_0 = 0x25
    LUT_RED_1 = 0x26
    LUT_RED_2 = 0x27
    LUT_RED_3 = 0x28
    LUT_XON = 0x29
    PLL_CONTROL = 0x30
    TEMPERATURE_SENSOR_COMMAND = 0x40
    TEMPERATURE_CALIBRATION = 0x41
    TEMPERATURE_SENSOR_WRITE = 0x42
    TEMPERATURE_SENSOR_READ = 0x43
    VCOM_AND_DATA_INTERVAL_SETTING = 0x50
    LOW_POWER_DETECTION = 0x51
    TCON_SETTING = 0x60
    RESOLUTION_SETTING = 0x61
    GSST_SETTING = 0x65
    GET_STATUS = 0x71
    AUTO_MEASUREMENT_VCOM = 0x80
    READ_VCOM_VALUE = 0x81
    VCM_DC_SETTING = 0x82
    
    def __init__(self):
        self.width = self.WIDTH
        self.height = self.HEIGHT
        self.reset_count = 0
        
    def digital_write(self, pin, value):
        return epdconfig.digital_write(pin, value)
        
    def digital_read(self, pin):
        return epdconfig.digital_read(pin)
        
    def delay_ms(self, delaytime):
        return epdconfig.delay_ms(delaytime)
        
    def send_command(self, command):
        self.digital_write(epdconfig.DC_PIN, 0)
        self.digital_write(epdconfig.CS_PIN, 0)
        epdconfig.spi_writebyte([command])
        self.digital_write(epdconfig.CS_PIN, 1)
        
    def send_data(self, data):
        self.digital_write(epdconfig.DC_PIN, 1)
        self.digital_write(epdconfig.CS_PIN, 0)
        epdconfig.spi_writebyte([data])
        self.digital_write(epdconfig.CS_PIN, 1)
        
    def reset(self):
        """Gondos, többszörös reset a megbízható inicializálásért"""
        self.reset_count += 1
        logging.debug(f"Kijelző reset ({self.reset_count}. próba)...")
        
        # Teljes reset ciklus a megbízható inicializáláshoz
        self.digital_write(epdconfig.RST_PIN, 1)
        self.delay_ms(200)
        self.digital_write(epdconfig.RST_PIN, 0)
        self.delay_ms(2)  # kritikus: >1ms legyen
        self.digital_write(epdconfig.RST_PIN, 1)
        self.delay_ms(200)  # Fontos: elegendő idő a stabil inicializáláshoz
        
    def wait_until_idle(self):
        """Gondos, időlimites busy-jel várás"""
        logging.debug("Várakozás a kijelző BUSY jelére...")
        start_time = time.time()
        timeout = 30  # 30 másodperc timeout
        
        # Várunk amíg a BUSY jel inaktív (1) lesz
        while self.digital_read(epdconfig.BUSY_PIN) == 0:
            self.delay_ms(10)  # Rövid várakozás
            if time.time() - start_time > timeout:
                logging.warning("BUSY jel timeout! Folytatás...")
                # Nincs raise, hogy az újrapróbálkozás lehetséges legyen
                break
                
        logging.debug("BUSY jel elengedve vagy timeout")
        
    def init(self):
        """Gondos inicializálás a 7-színű kijelzőhöz"""
        if epdconfig.module_init() != 0:
            return -1
            
        logging.debug("Waveshare 4.01 inch 7-Color E-Paper inicializálása")
        
        # Újrapróbálkozási logika
        max_attempts = 3
        for attempt in range(max_attempts):
            try:
                # Reset a kijelzőnek
                self.reset()
                
                # Inicializációs parancssorozat
                # A parancsok a hivatalos Waveshare kódból származnak
                
                # Power beállítás
                self.send_command(self.POWER_SETTING)
                self.send_data(0x07)  # VGH=20V, VGL=-20V
                self.send_data(0x07)  # VGH=20V, VGL=-20V
                self.send_data(0x3f)  # VDH=15V
                self.send_data(0x3f)  # VDL=-15V
                
                # Bekapcsolás
                self.send_command(self.POWER_ON)
                self.delay_ms(100)
                self.wait_until_idle()
                
                # Boost soft start
                self.send_command(self.BOOSTER_SOFT_START)
                self.send_data(0x17)
                self.send_data(0x17)
                self.send_data(0x17)
                
                # Panel beállítás - kulcsfontosságú
                self.send_command(self.PANEL_SETTING)
                self.send_data(0x0F)  # KW-3f KWR-2F BWROTP-0f BWOTP-1f
                
                # PLL vezérlés a tiszta képhez
                self.send_command(self.PLL_CONTROL)
                self.send_data(0x06)  # 100Hz
                
                # Felbontás beállítása - PONTOS 640x400 érték
                self.send_command(self.RESOLUTION_SETTING)
                self.send_data(0x02)  # 640 (high byte)
                self.send_data(0x80)  # 640 (low byte)
                self.send_data(0x01)  # 400 (high byte)
                self.send_data(0x90)  # 400 (low byte)
                
                # VCM_DC beállítás a tisztább képhez
                self.send_command(self.VCM_DC_SETTING)
                self.send_data(0x12)
                
                # VCOM és adat intervallum beállítása
                self.send_command(self.VCOM_AND_DATA_INTERVAL_SETTING)
                self.send_data(0x11)
                self.send_data(0x07)
                
                # TCON beállítás, kritikus a jó képhez
                self.send_command(self.TCON_SETTING)
                self.send_data(0x22)
                
                # Sikeres init
                logging.info("4.01 inch 7-színű E-Paper sikeres inicializálás")
                return 0
                
            except Exception as e:
                logging.error(f"Inicializálási hiba: {e} - próba {attempt+1}/{max_attempts}")
                if attempt == max_attempts - 1:
                    logging.error("Sikertelen inicializálás!")
                    return -1
                self.delay_ms(1000)  # 1mp várakozás az újrapróbálkozás előtt
                continue
                
        return -1  # Ha ide jutottunk, sikertelen az init
        
    def _set_pixmap_to_command(self, command):
        """Teljes pixeltérkép küldése adott paranccsal"""
        self.send_command(command)
        
        # Váltakozó sorminta küldése (gyorsabb és stabilabb átvitel)
        for j in range(0, self.HEIGHT, 2):
            for i in range(0, self.WIDTH):
                # Alapértelmezetten fehér
                self.send_data(self.WHITE)
            for i in range(0, self.WIDTH):
                # Alapértelmezetten fehér
                self.send_data(self.WHITE)
                
    def get_color_value(self, pixel):
        """RGB színek leképezése a 7-színű palettára hatékonyan"""
        r, g, b = pixel
        
        if r <= 10 and g <= 10 and b <= 10:  # Fekete
            return self.BLACK
        elif r >= 245 and g >= 245 and b >= 245:  # Fehér
            return self.WHITE
        elif r >= 220 and g <= 35 and b <= 35:  # Piros
            return self.RED
        elif r <= 35 and g >= 220 and b <= 35:  # Zöld
            return self.GREEN
        elif r <= 35 and g <= 35 and b >= 220:  # Kék
            return self.BLUE
        elif r >= 220 and g >= 220 and b <= 35:  # Sárga
            return self.YELLOW
        elif r >= 220 and g >= 100 and g <= 180 and b <= 35:  # Narancs
            return self.ORANGE
        else:
            # A legközelebbi szín kiválasztása távolság alapján
            colors = [
                (0, 0, 0),       # Fekete
                (255, 255, 255), # Fehér
                (0, 255, 0),     # Zöld
                (0, 0, 255),     # Kék
                (255, 0, 0),     # Piros
                (255, 255, 0),   # Sárga
                (255, 128, 0)    # Narancs
            ]
            
            min_distance = float('inf')
            closest_color = self.WHITE  # Alapértelmezett: fehér
            
            for i, color in enumerate([self.BLACK, self.WHITE, self.GREEN, 
                                     self.BLUE, self.RED, self.YELLOW, self.ORANGE]):
                cr, cg, cb = colors[i]
                distance = (r - cr)**2 + (g - cg)**2 + (b - cb)**2
                
                if distance < min_distance:
                    min_distance = distance
                    closest_color = color
                    
            return closest_color
                
    def _clear_display(self):
        """Kijelző tiszta fehérre állítása"""
        logging.debug("Kijelző törlése fehérre")
        
        self.send_command(self.DATA_START_TRANSMISSION_1)
        
        # Fehér pixelek küldése
        for i in range(self.HEIGHT * self.WIDTH // 8):
            self.send_data(0xFF)
            
        self.delay_ms(2)
        
        # Megjelenítés frissítése
        self.send_command(self.DISPLAY_REFRESH)
        self.wait_until_idle()
        
    def display(self, image):
        """Gondosan optimalizált képmegjelenítési funkció"""
        
        # Kép kezelése
        if isinstance(image, str):
            logging.debug(f"Kép betöltése fájlból: {image}")
            image = Image.open(image)
            
        # Konverzió RGB-be a megbízható színkezeléshez
        if image.mode != 'RGB':
            logging.debug(f"Kép konvertálása RGB módba ({image.mode} -> RGB)")
            image = image.convert('RGB')
            
        # Átméretezés a kijelző felbontására ha szükséges
        if image.width != self.width or image.height != self.height:
            logging.debug(f"Kép átméretezése: {image.width}x{image.height} -> {self.width}x{self.height}")
            image = image.resize((self.width, self.height), Image.LANCZOS)
            
        # Pixelek előkészítése
        pixels = image.load()
        
        # Adatátvitel indítása a kijelzőre
        logging.debug("Képadatok küldése...")
        self.send_command(self.DATA_START_TRANSMISSION_1)
        
        # Soronként küldjük az adatokat a hatékonyság és a stabilitás érdekében
        line_buffer = []
        total_bytes = 0
        
        for y in range(self.height):
            for x in range(self.width):
                # RGB pixel átalakítása a megfelelő 7-színű értékre
                pixel_color = self.get_color_value(pixels[x, y])
                line_buffer.append(pixel_color)
                total_bytes += 1
                
                # Ha a puffer megtelt, elküldjük (csökkenti az SPI átviteli hibák esélyét)
                if len(line_buffer) >= 128:
                    self.digital_write(epdconfig.DC_PIN, 1)
                    self.digital_write(epdconfig.CS_PIN, 0)
                    epdconfig.spi_writebyte(line_buffer)
                    self.digital_write(epdconfig.CS_PIN, 1)
                    line_buffer = []
            
            # Sorvégi maradék puffer küldése
            if line_buffer:
                self.digital_write(epdconfig.DC_PIN, 1)
                self.digital_write(epdconfig.CS_PIN, 0)
                epdconfig.spi_writebyte(line_buffer)
                self.digital_write(epdconfig.CS_PIN, 1)
                line_buffer = []
                
            # Időnként jelezzünk a haladásról
            if y % 50 == 0:
                logging.debug(f"Képküldés haladása: {y}/{self.height} sor")
                
        logging.debug(f"Összes küldött byte: {total_bytes}")
        
        # Refresh parancs (kijelző frissítése)
        logging.debug("Kijelző frissítése...")
        self.send_command(self.DISPLAY_REFRESH)
        self.wait_until_idle()
        logging.info("Kép megjelenítve")
        
        return 0
        
    def getbuffer(self, image):
        """Kompatibilitás érdekében megtartjuk, de közvetlenül a képet adjuk vissza."""
        # A 7-színű e-paper esetén a display funkció kezeli a képet
        return image
    
    def sleep(self):
        """Kijelző alvó módba helyezése"""
        logging.debug("Kijelző alvó módba helyezése")
        self.send_command(self.POWER_OFF)
        self.wait_until_idle()
        self.send_command(self.DEEP_SLEEP)
        self.send_data(0xA5)  # Ellenőrző byte
        self.delay_ms(100)  # Rövid várakozás hogy az alvó mód biztosan életbe lépjen
        
    def Clear(self, color=WHITE):
        """Kijelző törlése adott színre (alapértelmezetten fehér)"""
        logging.debug(f"Kijelző törlése színre: {color}")
        
        # Színes kép létrehozása a törléshez
        if color == self.WHITE:
            # Optimalizált fehér törlés
            image = Image.new('RGB', (self.width, self.height), (255, 255, 255))
        elif color == self.BLACK:
            image = Image.new('RGB', (self.width, self.height), (0, 0, 0))
        elif color == self.RED:
            image = Image.new('RGB', (self.width, self.height), (255, 0, 0))
        elif color == self.GREEN:
            image = Image.new('RGB', (self.width, self.height), (0, 255, 0))
        elif color == self.BLUE:
            image = Image.new('RGB', (self.width, self.height), (0, 0, 255))
        elif color == self.YELLOW:
            image = Image.new('RGB', (self.width, self.height), (255, 255, 0))
        elif color == self.ORANGE:
            image = Image.new('RGB', (self.width, self.height), (255, 128, 0))
        else:
            image = Image.new('RGB', (self.width, self.height), (255, 255, 255))
            
        # Megjelenítés a kijelzőn
        return self.display(image)
EOF

# Teszt szkript létrehozása finomhangolt betűméretekkel és jobb kijelzés teszteléssel
echo "Teszt szkript létrehozása..." | tee -a "$LOG_FILE"
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

logging.info("7-színű 4.01 inch E-Paper teszt program indítása")
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
   init_result = epd.init()
   logging.info("Kijelző inicializálása eredmény: %d", init_result)
   
   # Kijelző törlése fehérre
   logging.info("Kijelző törlése fehérre...")
   epd.Clear(epd.WHITE)
   logging.info("Kijelző törölve fehérre")
   
   # Teljes teszt kép, fehér háttérrel
   logging.info("7-színű teszt kép létrehozása...")
   image = Image.new('RGB', (epd.width, epd.height), 'white')
   draw = ImageDraw.Draw(image)
   
   # Betűtípus betöltése - KISEBB MÉRETEK a betűknél
   font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
   if os.path.exists(font_path):
       # Kisebb betűméreteket használunk a jobb megjelenítéshez
       font_title = ImageFont.truetype(font_path, 26)  # Csökkentett méret
       font_large = ImageFont.truetype(font_path, 20)  # Csökkentett méret
       font_medium = ImageFont.truetype(font_path, 16)  # Csökkentett méret
       font_small = ImageFont.truetype(font_path, 14)  # Csökkentett méret
   else:
       # Ha nincs betűtípus, használjuk az alapértelmezettet
       logging.warning("DejaVuSans betűtípus nem található, alapértelmezett használata")
       font_title = ImageFont.load_default()
       font_large = ImageFont.load_default()
       font_medium = ImageFont.load_default()
       font_small = ImageFont.load_default()
   
   # Címsor kirajzolása - sötét háttér, fehér szöveg a jobb olvashatóságért
   draw.rectangle([(0, 0), (epd.width, 35)], fill='black')
   draw.text((50, 5), '7-színű 4.01" E-Paper Teszt', fill='white', font=font_title)
   
   # Kijelző információk
   y_pos = 45
   draw.text((10, y_pos), f'Kijelző: Waveshare 4.01" 7-Color E-Paper ({epd.width}x{epd.height})', 
             fill='black', font=font_large)
   y_pos += 25
   draw.text((10, y_pos), f'Dátum: {time.strftime("%Y-%m-%d %H:%M")}', 
             fill='black', font=font_medium)
   y_pos += 25
   
   # Elválasztó vonal
   draw.line([(10, y_pos), (epd.width-10, y_pos)], fill='black', width=1)
   y_pos += 15
   
   # Színteszt rész címe
   draw.text((10, y_pos), "Színteszt minták:", fill='black', font=font_medium)
   y_pos += 25
   
   # 7 szín teszt - optimalizált elrendezés
   colors = [
       ('Fekete', (0, 0, 0), 'white'),
       ('Fehér', (255, 255, 255), 'black'),
       ('Piros', (255, 0, 0), 'white'),
       ('Zöld', (0, 255, 0), 'black'),
       ('Kék', (0, 0, 255), 'white'),
       ('Sárga', (255, 255, 0), 'black'),
       ('Narancs', (255, 165, 0), 'black')
   ]
   
   # Két oszlopos elrendezés a színekhez
   col_width = 300
   for i, (color_name, color, text_color) in enumerate(colors):
       col = i // 4  # 0 vagy 1, azaz bal vagy jobb oszlop
       row = i % 4   # 0-3, azaz sorindexek
       
       x_pos = 10 + col * col_width
       row_y_pos = y_pos + row * 40
       
       # Színes négyzet rajzolása
       draw.rectangle([(x_pos, row_y_pos), (x_pos + 80, row_y_pos + 30)], fill=color, outline='black')
       
       # Színnév kiírása
       draw.text((x_pos + 90, row_y_pos + 8), color_name, fill='black', font=font_medium)
   
   # Következő szakasz kezdete
   y_pos += 170
   
   # Elválasztó vonal
   draw.line([(10, y_pos), (epd.width-10, y_pos)], fill='black', width=1)
   y_pos += 15
   
   # Szövegteszt
   draw.text((10, y_pos), "Szövegteszt különböző méretekben:", fill='black', font=font_medium)
   y_pos += 25
   
   draw.text((10, y_pos), "Ez egy kisméretű szöveg teszt", fill='black', font=font_small)
   y_pos += 20
   draw.text((10, y_pos), "Ez egy közepes méretű szöveg", fill='black', font=font_medium)
   y_pos += 25
   draw.text((10, y_pos), "Ez egy nagyobb méretű szöveg", fill='black', font=font_large)
   y_pos += 30
   
   # Elválasztó vonal
   draw.line([(10, y_pos), (epd.width-10, y_pos)], fill='black', width=1)
   y_pos += 15
   
   # Telepítési információk
   draw.text((10, y_pos), "Telepítés információk:", fill='red', font=font_medium)
   y_pos += 25
   draw.text((10, y_pos), f'Telepítve: {time.strftime("%Y-%m-%d")}', fill='blue', font=font_small)
   y_pos += 20
   draw.text((10, y_pos), "Újraindítás szükséges a változtatások teljes érvénybeléséhez.", 
             fill='black', font=font_small)
   
   # Kép megjelenítése a kijelzőn
   logging.info("Kép megjelenítése a kijelzőn...")
   epd.display(image)
   logging.info("Teszt kép sikeresen megjelenítve")
   
   # Kis szünet, hogy láthassuk a kijelzőt
   time.sleep(2)
   
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

# Weboldal megjelenítő szkript - optimalizálva a 4.01 inch kijelzőhöz
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
import json

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
WEBPAGE_URL = "http://naptarak.com/e-paper.html"

# Várakozás a hálózati kapcsolatra
def wait_for_network():
   max_attempts = 30  # Max 5 perc (30 * 10 másodperc)
   attempts = 0
   
   logger.info("Várakozás a hálózati kapcsolat elérhetőségére...")
   
   while attempts < max_attempts:
       try:
           # Először a nap API-t próbáljuk - ez mutatja hogy tényleg van internet
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
       init_result = epd.init()
       if init_result != 0:
           logger.warning(f"Kijelző inicializálása hibakóddal tért vissza: {init_result}")
           # Második próbálkozás
           logger.info("Újrapróbálkozás a kijelző inicializálására...")
           time.sleep(1)
           init_result = epd.init()
           if init_result != 0:
               logger.error("Kijelző inicializálása sikertelen! Hardverhiba lehet.")
               raise Exception("Kijelző inicializálása sikertelen többszöri próbálkozás után is")
       
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
           # Kevesebb hiba - specifikus méret és jobb paraméterek
           command = f"xvfb-run -a wkhtmltoimage --width 640 --height 400 --quality 100 --disable-javascript --no-stop-slow-scripts --javascript-delay 1000 {WEBPAGE_URL} {screenshot_path}"
           subprocess.run(command, shell=True, check=True)
           return screenshot_path
       
       # Cutycapt mint tartalék
       elif os.path.exists("/usr/bin/cutycapt") or os.path.exists("/usr/local/bin/cutycapt"):
           logger.info("cutycapt használata...")
           # Jobb minőségű paraméterek
           command = f"xvfb-run -a cutycapt --url={WEBPAGE_URL} --out={screenshot_path} --min-width=640 --min-height=400 --delay=1000"
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
               # Több idő az oldal betöltéséhez
               time.sleep(15)
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
       
       # Jobb minőségű átméretezés a kijelző méretére
       image = image.resize((epd.width, epd.height), Image.LANCZOS)
       
       # Kontrasztjavítás az olvashatóságért
       from PIL import ImageEnhance
       enhancer = ImageEnhance.Contrast(image)
       image = enhancer.enhance(1.2)  # Növeljük a kontrasztot 20%-kal
       
       # Élesítés a jobb olvashatóságért
       from PIL import ImageFilter
       image = image.filter(ImageFilter.SHARPEN)
       
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
       
       # Betűtípus betöltése - kisebb méretekkel a jobb olvashatóságért
       font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
       if os.path.exists(font_path):
           font_title = ImageFont.truetype(font_path, 24)
           font_medium = ImageFont.truetype(font_path, 18)
           font_small = ImageFont.truetype(font_path, 14)
       else:
           # Ha nincs betűtípus, használjuk az alapértelmezettet
           font_title = ImageFont.load_default()
           font_medium = ImageFont.load_default()
           font_small = ImageFont.load_default()
       
       # Hibaüzenet kirajzolása - jobb formázással
       draw.rectangle([(0, 0), (epd.width, 35)], fill='red')
       draw.text((50, 5), 'HIBA!', fill='white', font=font_title)
       
       # Tördeljük a hibaüzenetet sorokra
       words = message.split()
       lines = []
       line = ""
       
       for word in words:
           test_line = line + " " + word if line else word
           text_width = draw.textlength(test_line, font=font_medium) if hasattr(draw, 'textlength') else font_medium.getlength(test_line)
           if text_width <= epd.width - 60:
               line = test_line
           else:
               lines.append(line)
               line = word
       
       if line:
           lines.append(line)
       
       # Kirajzoljuk a sorokat
       y = 50
       for line in lines:
           draw.text((30, y), line, fill='black', font=font_medium)
           y += 25
       
       # Idő bélyeg
       draw.text((30, epd.height - 40), f"Idő: {time.strftime('%Y-%m-%d %H:%M:%S')}", fill='blue', font=font_small)
       
       # Kép megjelenítése
       epd.display(image)
       logger.info("Hibaüzenet sikeresen megjelenítve a kijelzőn")
       return True
   except Exception as e:
       logger.error(f"Hiba a hibaüzenet megjelenítésekor: {e}")
       logger.error(traceback.format_exc())
       return False

def get_weather_info():
   """Időjárási információk lekérése"""
   try:
       # Ezt csak online módban adjuk hozzá a képhez
       return None
   except Exception as e:
       logger.error(f"Időjárás lekérés hiba: {e}")
       return None

       def main():
   try:
       # Várakozás a hálózati kapcsolat elérhetőségére
       network_available = wait_for_network()
       if not network_available:
           logger.warning("Figyelmeztetés: Hálózat nem elérhető, offline mód aktiválva")
       
       # E-paper inicializálása
       logger.info("E-paper kijelző inicializálása...")
       epd = initialize_epd()
       
       # Kezdőkép megjelenítése
       logger.info("Kezdőkép megjelenítése...")
       try:
           # Tiszta fehér kép létrehozása
           image = Image.new('RGB', (epd.width, epd.height), 'white')
           draw = ImageDraw.Draw(image)
           
           # Betűtípus betöltése - kisebb méretekkel
           font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
           if os.path.exists(font_path):
               font_title = ImageFont.truetype(font_path, 24)
               font_medium = ImageFont.truetype(font_path, 18)
               font_small = ImageFont.truetype(font_path, 14)
           else:
               # Ha nincs betűtípus, használjuk az alapértelmezettet
               font_title = ImageFont.load_default()
               font_medium = ImageFont.load_default()
               font_small = ImageFont.load_default()
           
           # Szöveg kirajzolása
           draw.rectangle([(0, 0), (epd.width, 35)], fill='blue')
           draw.text((50, 5), '7-Színű 4.01" E-Paper Webkijelző', fill='white', font=font_title)
           
           y_pos = 50
           draw.text((30, y_pos), f'URL: {WEBPAGE_URL}', fill='black', font=font_medium)
           y_pos += 30
           
           draw.text((30, y_pos), f'Állapot: {"Online" if network_available else "Offline"}', 
                     fill='green' if network_available else 'red', font=font_medium)
           y_pos += 30
           
           draw.text((30, y_pos), f'Méret: {epd.width}x{epd.height} pixel', fill='black', font=font_medium)
           y_pos += 30
           
           draw.text((30, y_pos), f'Indítva: {time.strftime("%Y-%m-%d %H:%M:%S")}', fill='black', font=font_medium)
           y_pos += 40
           
           # Információ
           draw.text((30, y_pos), "Weboldal betöltése folyamatban...", fill='blue', font=font_medium)
           y_pos += 40
           
           if not network_available:
               draw.text((30, y_pos), "FIGYELEM: Nincs hálózat! Offline mód aktív!", fill='red', font=font_medium)
               y_pos += 30
               draw.text((30, y_pos), "Ellenőrizze a hálózati kapcsolatot!", fill='red', font=font_medium)
           
           # Kép megjelenítése
           epd.display(image)
           logger.info("Kezdőkép megjelenítve")
           time.sleep(2)  # Rövid idő a kép megtekintésére
       except Exception as e:
           logger.error(f"Nem sikerült megjeleníteni a kezdőképet: {e}")
           logger.error(traceback.format_exc())
       
       # Frissítési kísérlet számláló
       failed_attempts = 0
       
       # Fő ciklus
       while True:
           try:
               if network_available:
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
                               display_error_message(epd, "Nem sikerült megjeleníteni a képet háromszor egymás után. Ellenőrizze a kijelző csatlakozását.")
                   else:
                       logger.error("Nem sikerült képernyőképet készíteni a weboldalról")
                       failed_attempts += 1
                       if failed_attempts >= 3:
                           display_error_message(epd, "Nem sikerült képernyőképet készíteni a weboldalról háromszor egymás után. Ellenőrizze a hálózati kapcsolatot.")
               else:
                   # Offline mód - infó kép megjelenítése
                   offline_image = Image.new('RGB', (epd.width, epd.height), 'white')
                   draw = ImageDraw.Draw(offline_image)
                   
                   # Betűtípus betöltése
                   font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
                   if os.path.exists(font_path):
                       font_title = ImageFont.truetype(font_path, 24)
                       font_medium = ImageFont.truetype(font_path, 18)
                       font_small = ImageFont.truetype(font_path, 14)
                   else:
                       font_title = ImageFont.load_default()
                       font_medium = ImageFont.load_default()
                       font_small = ImageFont.load_default()
                   
                   # Offline infó kirajzolása
                   draw.rectangle([(0, 0), (epd.width, 35)], fill='red')
                   draw.text((50, 5), 'OFFLINE MÓD', fill='white', font=font_title)
                   
                   y_pos = 50
                   draw.text((30, y_pos), "A hálózati kapcsolat nem elérhető.", fill='black', font=font_medium)
                   y_pos += 30
                   
                   draw.text((30, y_pos), "A weboldal nem jeleníthető meg.", fill='black', font=font_medium)
                   y_pos += 30
                   
                   draw.text((30, y_pos), "Kérjük, ellenőrizze a hálózati beállításokat.", fill='blue', font=font_medium)
                   y_pos += 40
                   
                   draw.text((30, y_pos), "A rendszer továbbra is megpróbál csatlakozni.", fill='black', font=font_medium)
                   y_pos += 30
                   
                   # Kép megjelenítése
                   epd.display(offline_image)
                   
                   # Újra ellenőrizzük a hálózatot
                   network_available = wait_for_network()
                   if network_available:
                       logger.info("Hálózati kapcsolat helyreállt!")
                   
           except Exception as e:
               logger.error(f"Hiba a frissítési ciklusban: {e}")
               logger.error(traceback.format_exc())
               failed_attempts += 1
               if failed_attempts >= 3:
                   try:
                       display_error_message(epd, f"Ismétlődő hiba: {str(e)[:100]}...")
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
Description=7-Színű 4.01 inch E-Paper Weboldal Megjelenítő
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

# uninstall.sh - Eltávolító szkript 7-színű 4.01 inch e-paper weblap megjelenítőhöz
# Frissítve: 2025.05.14

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
echo "Teszt szkript futtatása a 7-színű 4.01 inch kijelző ellenőrzéséhez..." | tee -a "$LOG_FILE"
"$INSTALL_DIR/test_7color_display.py" || {
   echo "A tesztprogram nem futott le sikeresen, ellenőrizd a /var/log/epaper-test.log fájlt" | tee -a "$LOG_FILE"
}

# URL bekérése
echo "Kérlek add meg az URL-t, amit meg szeretnél jeleníteni (alapértelmezett: http://naptarak.com/e-paper.html):"
read url

if [ -z "$url" ]; then
   url="http://naptarak.com/e-paper.html"
fi

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

# GPIO jogosultságok beállítása
echo "GPIO és SPI jogosultságok beállítása..." | tee -a "$LOG_FILE"
if getent group gpio >/dev/null; then
   sudo usermod -a -G gpio $CURRENT_USER 2>> "$LOG_FILE" || true
fi
if getent group spi >/dev/null; then
   sudo usermod -a -G spi $CURRENT_USER 2>> "$LOG_FILE" || true
fi

# Összefoglaló
echo "" | tee -a "$LOG_FILE"
echo "Telepítési összefoglaló:" | tee -a "$LOG_FILE"
echo "=====================" | tee -a "$LOG_FILE"
echo "Telepítési könyvtár: $INSTALL_DIR" | tee -a "$LOG_FILE"
echo "Virtuális környezet: $VENV_DIR" | tee -a "$LOG_FILE"
echo "Felhasználó: $CURRENT_USER" | tee -a "$LOG_FILE"
echo "Kijelző: 7-színű 4.01 inch (640x400) e-Paper" | tee -a "$LOG_FILE"
echo "Weboldal URL: $url" | tee -a "$LOG_FILE"
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
echo "  1. Logok megtekintése: epaper-logs test vagy epaper-logs app" | tee -a "$LOG_FILE"
echo "  2. Szolgáltatás újraindítása: epaper-service restart" | tee -a "$LOG_FILE"
echo "  3. Teszt újrafuttatása: epaper-service test" | tee -a "$LOG_FILE"
echo "  4. URL módosítása: epaper-config http://uj-url.hu" | tee -a "$LOG_FILE"
echo "  5. GPIO/SPI jogosultságok: sudo usermod -a -G gpio,spi $CURRENT_USER" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$REBOOT_REQUIRED" = true ]; then
   echo "A telepítés befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
   echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "Telepítés befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"
