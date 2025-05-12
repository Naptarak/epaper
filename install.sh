#!/bin/bash

# install.sh - Optimalizált telepítő szkript NumPy fordítás nélkül
# Raspberry Pi + Waveshare 4.01 inch HAT (F) 7 színű e-paper kijelzőhöz
# Frissítve: 2025.05.13 - NumPy telepítési és importálási hibák javítva

set -e  # Kilépés hiba esetén
LOG_FILE="install_log.txt"
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

# Rendszermodulok elérhetővé tétele a virtuális környezetben
echo "Rendszermodulok ellenőrzése a virtuális környezetben..." | tee -a "$LOG_FILE"
"$VENV_DIR/bin/python" -c "import numpy; import PIL; print('NumPy verzió:', numpy.__version__); print('PIL verzió:', PIL.__version__)" 2>> "$LOG_FILE" || {
    echo "Rendszermodulok nem érhetők el a virtuális környezetben, szimbolikus linkek létrehozása..." | tee -a "$LOG_FILE"
    
    # Python verzió meghatározása a site-packages könyvtárhoz
    PY_VERSION=$("$PYTHON_CMD" -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    VENV_SITE_PACKAGES="$VENV_DIR/lib/python$PY_VERSION/site-packages"
    
    # NumPy elérhetővé tétele
    SYSTEM_NUMPY_PATH=$($PYTHON_CMD -c "import numpy; print(numpy.__path__[0])" 2>/dev/null)
    if [ -n "$SYSTEM_NUMPY_PATH" ]; then
        sudo mkdir -p "$VENV_SITE_PACKAGES/numpy"
        sudo cp -r "$SYSTEM_NUMPY_PATH"/* "$VENV_SITE_PACKAGES/numpy/"
        sudo touch "$VENV_SITE_PACKAGES/numpy/__init__.py"
        echo "NumPy másolva a virtuális környezetbe" | tee -a "$LOG_FILE"
    fi
    
    # PIL elérhetővé tétele
    SYSTEM_PIL_PATH=$($PYTHON_CMD -c "import PIL; print(PIL.__path__[0])" 2>/dev/null)
    if [ -n "$SYSTEM_PIL_PATH" ]; then
        sudo mkdir -p "$VENV_SITE_PACKAGES/PIL"
        sudo cp -r "$SYSTEM_PIL_PATH"/* "$VENV_SITE_PACKAGES/PIL/"
        sudo touch "$VENV_SITE_PACKAGES/PIL/__init__.py"
        echo "PIL másolva a virtuális környezetbe" | tee -a "$LOG_FILE"
    fi
}

# Waveshare e-paper könyvtár letöltése és telepítése
echo "Waveshare e-paper könyvtár letöltése..." | tee -a "$LOG_FILE"
TEMP_DIR="/tmp/waveshare-install"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Régi könyvtárak eltávolítása
rm -rf e-Paper epd-library-python 2>/dev/null || true

# Waveshare könyvtár klónozása
echo "Waveshare repository klónozása..." | tee -a "$LOG_FILE"
git clone https://github.com/waveshare/e-Paper.git 2>> "$LOG_FILE"
check_success "Nem sikerült klónozni a Waveshare repository-t"

# E-paper modul könyvtárszerkezet létrehozása
echo "E-paper könyvtárszerkezet létrehozása..." | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR/lib/waveshare_epd" 2>> "$LOG_FILE"

# __init__.py létrehozása, hogy proper Python csomag legyen
echo "Python csomag inicializálása..." | tee -a "$LOG_FILE"
sudo touch "$INSTALL_DIR/lib/waveshare_epd/__init__.py" 2>> "$LOG_FILE"
sudo touch "$INSTALL_DIR/lib/__init__.py" 2>> "$LOG_FILE"

# E-paper modul másolása
echo "E-paper modulok másolása..." | tee -a "$LOG_FILE"
if [ -d "$TEMP_DIR/e-Paper/RaspberryPi/python/lib/waveshare_epd" ]; then
    sudo cp -r "$TEMP_DIR/e-Paper/RaspberryPi/python/lib/waveshare_epd"/* "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
    check_success "Nem sikerült másolni a waveshare_epd modulokat"
else
    handle_error "Nem található a Waveshare e-paper modul könyvtára"
fi

# Példakódok másolása
echo "Példakódok másolása..." | tee -a "$LOG_FILE"
if [ -d "$TEMP_DIR/e-Paper/RaspberryPi/python/examples" ]; then
    sudo mkdir -p "$INSTALL_DIR/examples" 2>> "$LOG_FILE"
    sudo cp -r "$TEMP_DIR/e-Paper/RaspberryPi/python/examples"/* "$INSTALL_DIR/examples/" 2>> "$LOG_FILE"
    echo "Példakódok másolva" | tee -a "$LOG_FILE"
fi

# Importálási problémák javítása
echo "Importálási problémák javítása..." | tee -a "$LOG_FILE"
# Ellenőrzés, hogy melyik 4.01 inch modul van jelen
if [ -f "$INSTALL_DIR/lib/waveshare_epd/epd4in01f.py" ]; then
    EPD_MODULE="epd4in01f"
elif [ -f "$INSTALL_DIR/lib/waveshare_epd/epd4in01.py" ]; then
    EPD_MODULE="epd4in01"
else
    # Keressünk bármilyen 4 inch modult
    FOUND_4IN_MODULES=$(find "$INSTALL_DIR/lib/waveshare_epd" -name "*4in*.py" | sort)
    if [ -n "$FOUND_4IN_MODULES" ]; then
        # Vesszük az első találatot
        EPD_MODULE=$(basename $(echo "$FOUND_4IN_MODULES" | head -n1) .py)
        echo "Talált 4 inches modul: $EPD_MODULE" | tee -a "$LOG_FILE"
    else
        EPD_MODULE="epd4in01f"  # Alapértelmezett
        echo "Nem található specifikus 4 inches modul, alapértelmezett használata: $EPD_MODULE" | tee -a "$LOG_FILE"
    fi
fi

echo "Használt e-paper modul: $EPD_MODULE" | tee -a "$LOG_FILE"

# Relatív importok javítása
echo "Relatív importok javítása a modul fájlokban..." | tee -a "$LOG_FILE"
for pyfile in $(find "$INSTALL_DIR/lib/waveshare_epd" -name "*.py"); do
    # Relatív importok cseréje abszolút importokra
    sudo sed -i 's/from \. import epdconfig/import epdconfig/g' "$pyfile" 2>> "$LOG_FILE"
    # Ellenőrizzük, hogy van-e szükség az epdconfig.py másolására
    if grep -q "import epdconfig" "$pyfile"; then
        if [ ! -f "$INSTALL_DIR/lib/waveshare_epd/epdconfig.py" ]; then
            echo "epdconfig.py másolása..." | tee -a "$LOG_FILE"
            sudo cp "$TEMP_DIR/e-Paper/RaspberryPi/python/lib/waveshare_epd/epdconfig.py" "$INSTALL_DIR/lib/waveshare_epd/" 2>> "$LOG_FILE"
        fi
    fi
done

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

# Teszt szkript létrehozása
echo "Teszt szkript létrehozása a kijelző működésének ellenőrzéséhez..." | tee -a "$LOG_FILE"
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

logging.info("E-Paper teszt program indítása")
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
logging.info("Elérhető modulok a lib könyvtárban:")
for file in os.listdir(lib_dir):
    logging.info("  - %s", file)

if os.path.exists(waveshare_dir):
    logging.info("Elérhető modulok a waveshare_epd könyvtárban:")
    for file in os.listdir(waveshare_dir):
        logging.info("  - %s", file)

try:
    # Próbáljunk importálni
    logging.info("Pillow importálása...")
    try:
        import PIL
        logging.info("PIL verzió: %s", PIL.__version__)
    except ImportError as e:
        logging.error("PIL importálási hiba: %s", e)
    
    logging.info("NumPy importálása...")
    try:
        import numpy
        logging.info("NumPy verzió: %s", numpy.__version__)
    except ImportError as e:
        logging.error("NumPy importálási hiba: %s", e)
    
    # E-paper modul importálása
    module_name = "$EPD_MODULE"
    logging.info("Megpróbáljuk importálni a modult: %s", module_name)
    
    try:
        from waveshare_epd import $EPD_MODULE
        logging.info("Modul sikeresen importálva a waveshare_epd csomagból")
        epd = $EPD_MODULE.EPD()
    except ImportError as e:
        logging.warning("Import hiba a waveshare_epd csomagból: %s", e)
        logging.warning("Direkt import próbálása...")
        try:
            import $EPD_MODULE
            epd = $EPD_MODULE.EPD()
            logging.info("Modul sikeresen importálva közvetlenül")
        except ImportError as e2:
            logging.error("Közvetlen import is sikertelen: %s", e2)
            raise
    
    logging.info("EPD objektum létrehozva")
    logging.info("Kijelző méretei: %s x %s", epd.width, epd.height)
    
    # Kijelző inicializálása
    logging.info("Kijelző inicializálása...")
    epd.init()
    logging.info("Inicializálás sikeres")
    
    # Kijelző törlése
    logging.info("Kijelző törlése...")
    try:
        epd.Clear()
        logging.info("Kijelző törölve")
    except Exception as e:
        logging.warning("Kijelző törlése nem sikerült: %s", e)
        logging.warning("Folytatás a törlés nélkül...")
    
    # Teszt kép rajzolása
    logging.info("Teszt kép létrehozása...")
    image = Image.new('RGB', (epd.width, epd.height), 'white')
    draw = ImageDraw.Draw(image)
    
    # Betűtípus betöltése
    font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    if os.path.exists(font_path):
        font_large = ImageFont.truetype(font_path, 40)
        font_small = ImageFont.truetype(font_path, 24)
    else:
        # Ha nincs betűtípus, használjuk az alapértelmezettet
        font_large = ImageFont.load_default()
        font_small = ImageFont.load_default()
    
    # Szöveg kirajzolása
    draw.text((50, 50), 'E-Paper teszt', fill='black', font=font_large)
    draw.text((50, 120), 'Sikeres inicializálás!', fill='red', font=font_small)
    draw.text((50, 190), 'Modul: $EPD_MODULE', fill='black', font=font_small)
    draw.text((50, 250), 'Telepítés dátuma:', fill='black', font=font_small)
    draw.text((50, 290), '$(date +%Y-%m-%d)', fill='red', font=font_small)
    
    # Kép megjelenítése
    logging.info("Kép megjelenítése a kijelzőn...")
    epd.display(epd.getbuffer(image))
    logging.info("Kép megjelenítve")
    
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

# Python szkript létrehozása a weboldal megjelenítéséhez
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
        logger.info("E-paper modul importálása: $EPD_MODULE")
        # Importálási kísérlet a waveshare_epd csomagból
        try:
            from waveshare_epd import $EPD_MODULE
            logger.info("Modul sikeresen importálva a waveshare_epd csomagból")
            epd = $EPD_MODULE.EPD()
        except ImportError as e:
            logger.warning(f"Nem sikerült importálni a waveshare_epd csomagból: {e}")
            logger.warning("Direkt importálási kísérlet...")
            # Ha nem sikerült, próbáljunk közvetlen importálást
            import $EPD_MODULE
            epd = $EPD_MODULE.EPD()
        
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
        
        # Szimulációs mód fallback
        logger.warning("Szimulációs mód aktiválása...")
        
        class SimulatedEPD:
            def __init__(self):
                self.width = 640
                self.height = 400
                logger.info("Szimulált e-Paper inicializálva")
            
            def init(self):
                logger.info("Szimulált init hívás")
                return 0
                
            def getbuffer(self, image):
                logger.info("Szimulált getbuffer hívás")
                return image
                
            def display(self, buffer):
                logger.info("Szimulált kijelzés - a kép mentése: /tmp/epaper_display.png")
                if isinstance(buffer, Image.Image):
                    image = buffer
                else:
                    image = Image.new('RGB', (self.width, self.height), 'white')
                image.save("/tmp/epaper_display.png")
                return 0
                
            def sleep(self):
                logger.info("Szimulált sleep hívás")
                return 0
                
            def Clear(self, color=0xFF):
                logger.info("Szimulált képernyő törlés")
                return 0
        
        return SimulatedEPD()

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
        epd.display(epd.getbuffer(image))
        logger.info("Kép sikeresen megjelenítve")
        return True
    except Exception as e:
        logger.error(f"Hiba a kép megjelenítésekor: {e}")
        logger.error(traceback.format_exc())
        return False

def main():
    try:
        # Várakozás a hálózati kapcsolat elérhetőségére
        if not wait_for_network():
            logger.warning("Figyelmeztetés: Hálózat nem elérhető, de folytatás offline móddal")
        
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
            draw.text((epd.width//4, epd.height//3), 'E-Paper kijelző indul...', fill='black', font=font_large)
            draw.text((epd.width//4, epd.height//2), f'URL: {WEBPAGE_URL}', fill='red', font=font_small)
            
            # Kép megjelenítése
            epd.display(epd.getbuffer(image))
            logger.info("Üdvözlő üzenet megjelenítve")
            time.sleep(2)  # Rövid idő az üzenet olvasására
        except Exception as e:
            logger.error(f"Nem sikerült megjeleníteni az üdvözlő üzenetet: {e}")
            logger.error(traceback.format_exc())
        
        # Fő ciklus
        while True:
            logger.info("Weboldal képernyőkép készítése...")
            screenshot = capture_webpage()
            
            if screenshot and os.path.exists(screenshot):
                logger.info("Megjelenítés az e-paper kijelzőn...")
                if display_image(epd, screenshot):
                    logger.info("Megjelenítés sikeres")
                else:
                    logger.error("Nem sikerült megjeleníteni a képet")
            else:
                logger.error("Nem sikerült képernyőképet készíteni a weboldalról")
            
            # Várakozás a következő frissítés előtt
            logger.info("Várakozás 5 percig a következő frissítés előtt...")
            time.sleep(300)
    except KeyboardInterrupt:
        logger.info("Program leállítva a felhasználó által")
        epd.sleep()
    except Exception as e:
        logger.error(f"Nem várt hiba történt: {e}")
        logger.error(traceback.format_exc())
        # Próbáljuk újraindítani a programot hiba esetén
        logger.info("Újraindítás 30 másodperc múlva...")
        time.sleep(30)
        main()  # Rekurzív újraindítás

if __name__ == "__main__":
    logger.info("Program indítása...")
    main()
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
Description=E-Paper Weboldal Megjelenítő
After=network-online.target
Wants=network-online.target
DefaultDependencies=no

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python3 $INSTALL_DIR/display_webpage.py
Restart=always
RestartSec=10
TimeoutStartSec=120
StartLimitIntervalSec=500
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

# Jogosultságok hozzáadása GPIO és SPI használatához
echo "Felhasználó hozzáadása a gpio és spi csoportokhoz..." | tee -a "$LOG_FILE"
if ! groups $CURRENT_USER | grep -q "gpio"; then
    sudo usermod -a -G gpio $CURRENT_USER 2>> "$LOG_FILE" || true
fi

if ! groups $CURRENT_USER | grep -q "spi"; then
    sudo usermod -a -G spi $CURRENT_USER 2>> "$LOG_FILE" || true
fi

# Waveshare teszt futtatása
echo "Waveshare teszt futtatása a kijelző ellenőrzéséhez..." | tee -a "$LOG_FILE"
echo "A teszt kiírja a kijelzőre, hogy 'E-Paper teszt' és 'Sikeres inicializálás!'"
sudo $INSTALL_DIR/test_display.py

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

if [ "$REBOOT_REQUIRED" = true ]; then
    echo "A telepítés befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "Telepítés befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"
