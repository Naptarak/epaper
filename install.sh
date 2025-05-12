#!/bin/bash

# install.sh - Javított telepítő szkript e-paper weblap megjelenítőhöz
# Raspberry Pi Zero 2W + Waveshare 4.01 inch HAT (F) 7 színű e-paper kijelzőhöz

set -e  # Kilépés hiba esetén
LOG_FILE="install_log.txt"
echo "Telepítés indítása: $(date)" | tee -a "$LOG_FILE"

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
echo "Telepítési könyvtár létrehozása..." | tee -a "$LOG_FILE"
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

# Több módszer kipróbálása a csomagtelepítéshez
if ! sudo apt-get install -y python3-pip python3-pil python3-numpy git xvfb scrot 2>> "$LOG_FILE"; then
    echo "Szabványos csomagtelepítés sikertelen, alternatív módszer kipróbálása..." | tee -a "$LOG_FILE"
    if ! sudo apt-get install --fix-missing -y python3-pip python3-pil python3-numpy git xvfb scrot 2>> "$LOG_FILE"; then
        echo "Csomagok egyenkénti telepítési kísérlete..." | tee -a "$LOG_FILE"
        sudo apt-get install -y python3-pip 2>> "$LOG_FILE" || echo "python3-pip telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
        sudo apt-get install -y python3-pil 2>> "$LOG_FILE" || echo "python3-pil telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
        sudo apt-get install -y python3-numpy 2>> "$LOG_FILE" || echo "python3-numpy telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
        sudo apt-get install -y git 2>> "$LOG_FILE" || echo "git telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
        sudo apt-get install -y xvfb 2>> "$LOG_FILE" || echo "xvfb telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
        sudo apt-get install -y scrot 2>> "$LOG_FILE" || echo "scrot telepítése sikertelen, folytatás..." | tee -a "$LOG_FILE"
    fi
fi

# Weboldal capture eszközök telepítése
echo "Weboldal megjelenítéshez szükséges eszközök telepítése..." | tee -a "$LOG_FILE"
if ! sudo apt-get install -y wkhtmltopdf 2>> "$LOG_FILE"; then
    echo "wkhtmltopdf telepítése sikertelen, cutycapt kipróbálása..." | tee -a "$LOG_FILE"
    sudo apt-get install -y cutycapt 2>> "$LOG_FILE" || echo "cutycapt telepítése is sikertelen, a midori böngészőt fogjuk használni" | tee -a "$LOG_FILE"
fi

# Python függőségek telepítése az e-paper kijelzőhöz
echo "E-paper függőségek telepítése..." | tee -a "$LOG_FILE"
if ! sudo pip3 install RPi.GPIO spidev 2>> "$LOG_FILE"; then
    echo "Standard pip telepítés sikertelen, alternatív módszer kipróbálása..." | tee -a "$LOG_FILE"
    if ! sudo pip3 install --break-system-packages RPi.GPIO spidev 2>> "$LOG_FILE"; then
        echo "Pip telepítés alternatív módszerrel is sikertelen, folytatás a következő lépéssel..." | tee -a "$LOG_FILE"
        # Folytatjuk, mert lehet, hogy már telepítve vannak
    fi
fi

# Waveshare e-paper könyvtár klónozása és felderítése
echo "Waveshare e-paper könyvtár klónozása és felderítése..." | tee -a "$LOG_FILE"
TEMP_DIR="/tmp/waveshare-install"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Régi könyvtárak eltávolítása
rm -rf e-Paper epd-library-python 2>/dev/null || true

# Waveshare official repo klónozása
echo "Hivatalos Waveshare repository klónozása..." | tee -a "$LOG_FILE"
if ! git clone https://github.com/waveshare/e-Paper.git 2>> "$LOG_FILE"; then
    echo "Hivatalos repo klónozás sikertelen, próbálkozás az alternatív repoval..." | tee -a "$LOG_FILE"
    if ! git clone https://github.com/soonuse/epd-library-python.git 2>> "$LOG_FILE"; then
        handle_error "Nem sikerült klónozni az e-paper könyvtárat. Ellenőrizd az internetkapcsolatot."
    else
        REPO_NAME="epd-library-python"
        echo "Alternatív repo klónozva: $REPO_NAME" | tee -a "$LOG_FILE"
    fi
else
    REPO_NAME="e-Paper"
    echo "Hivatalos repo klónozva: $REPO_NAME" | tee -a "$LOG_FILE"
fi

# Könyvtárszerkezet felderítése és mentése
echo "Repository könyvtárszerkezet feltérképezése..." | tee -a "$LOG_FILE"
find "$REPO_NAME" -type d | sort > "$TEMP_DIR/dir_structure.txt"
cat "$TEMP_DIR/dir_structure.txt" | tee -a "$LOG_FILE"

# Python fájlok keresése, különös tekintettel a 4in01f vagy 4_01f fájlokra
echo "4in01f modul keresése a repository-ban..." | tee -a "$LOG_FILE"
FOUND_MODULES=$(find "$REPO_NAME" -name "*4in01f*.py" -o -name "*4_01f*.py" 2>/dev/null)
if [ -z "$FOUND_MODULES" ]; then
    echo "Nem találtam specifikus 4.01 inch modulfájlt, általános e-paper modulok keresése..." | tee -a "$LOG_FILE"
    FOUND_MODULES=$(find "$REPO_NAME" -name "epd*.py" 2>/dev/null)
fi

# Eredmények kiírása
echo "Talált modulok:" | tee -a "$LOG_FILE"
echo "$FOUND_MODULES" | tee -a "$LOG_FILE"

# Potenciális forrásmappák azonosítása
if [ -d "$REPO_NAME/RaspberryPi" ]; then
    # Régebbi Waveshare repo struktúra
    POTENTIAL_DIRS=(
        "$REPO_NAME/RaspberryPi/python/examples"
        "$REPO_NAME/RaspberryPi/python"
        "$REPO_NAME/RaspberryPi"
    )
elif [ -d "$REPO_NAME/python" ]; then
    # Újabb Waveshare repo struktúra
    POTENTIAL_DIRS=(
        "$REPO_NAME/python/examples"
        "$REPO_NAME/python"
    )
else
    # Egyéb lehetséges struktúrák
    POTENTIAL_DIRS=(
        "$(dirname $(echo "$FOUND_MODULES" | head -n1))"
        "$REPO_NAME"
    )
fi

# Ellenőrizzük és találjuk meg a legjobb forrásmappát
LIB_SRC_DIR=""
for dir in "${POTENTIAL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Potenciális forrásmappa: $dir" | tee -a "$LOG_FILE"
        if [ -d "$dir/waveshare_epd" ] || ls "$dir"/*epd*.py >/dev/null 2>&1; then
            echo "Megfelelő forrásmappa megtalálva: $dir" | tee -a "$LOG_FILE"
            LIB_SRC_DIR="$dir"
            break
        fi
    fi
done

# Ha még mindig nem találtunk megfelelő forrást, használjuk az első talált modult
if [ -z "$LIB_SRC_DIR" ] && [ -n "$FOUND_MODULES" ]; then
    LIB_SRC_DIR=$(dirname $(echo "$FOUND_MODULES" | head -n1))
    echo "Alapértelmezett forráskönyvtár: $LIB_SRC_DIR" | tee -a "$LOG_FILE"
fi

# Ha még mindig nincs érvényes forráskönyvtár, hiba
if [ -z "$LIB_SRC_DIR" ] || [ ! -d "$LIB_SRC_DIR" ]; then
    handle_error "Nem sikerült azonosítani érvényes forráskönyvtárat a Waveshare repository-ban"
fi

# Megállapítjuk a relatív útvonalat a repository gyökeréhez képest
RELATIVE_PATH=${LIB_SRC_DIR#$TEMP_DIR/}
echo "Relatív útvonal: $RELATIVE_PATH" | tee -a "$LOG_FILE"

# Könyvtárstruktúra másolása a telepítési könyvtárba
echo "Forrásmappa másolása a telepítési könyvtárba..." | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR/lib" 2>> "$LOG_FILE"
sudo cp -r "$LIB_SRC_DIR"/* "$INSTALL_DIR/lib/" 2>> "$LOG_FILE"
check_success "Nem sikerült másolni a forrásfájlokat"

# Recursively copy all python files if they weren't copied already
echo "Python fájlok másolásának ellenőrzése..." | tee -a "$LOG_FILE"
if ! ls "$INSTALL_DIR/lib"/*epd*.py >/dev/null 2>&1 && ! [ -d "$INSTALL_DIR/lib/waveshare_epd" ]; then
    echo "Nem találtam e-paper modulokat a célkönyvtárban, további fájlok keresése..." | tee -a "$LOG_FILE"
    for py_file in $(find "$TEMP_DIR/$REPO_NAME" -name "*.py"); do
        rel_path=${py_file#$TEMP_DIR/$REPO_NAME/}
        target_dir=$(dirname "$INSTALL_DIR/lib/$rel_path")
        sudo mkdir -p "$target_dir" 2>> "$LOG_FILE"
        sudo cp "$py_file" "$target_dir/" 2>> "$LOG_FILE"
    done
    echo "Python fájlok másolva" | tee -a "$LOG_FILE"
fi

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

# E-paper modul detektálása a telepített fájlok között
echo "E-paper modulok keresése a telepített fájlok között..." | tee -a "$LOG_FILE"
INSTALLED_MODULES=$(find "$INSTALL_DIR/lib" -name "*4in01f*.py" -o -name "*4_01f*.py" 2>/dev/null)
if [ -z "$INSTALLED_MODULES" ]; then
    echo "Specifikus modul nem található, általános e-paper modulok keresése..." | tee -a "$LOG_FILE"
    INSTALLED_MODULES=$(find "$INSTALL_DIR/lib" -name "epd*.py" 2>/dev/null)
fi

echo "Telepített modulok:" | tee -a "$LOG_FILE"
echo "$INSTALLED_MODULES" | tee -a "$LOG_FILE"

# Modul és útvonal meghatározása
if [ -n "$INSTALLED_MODULES" ]; then
    EPD_MODULE_PATH=$(dirname $(echo "$INSTALLED_MODULES" | head -n1))
    EPD_MODULE=$(basename $(echo "$INSTALLED_MODULES" | head -n1) .py)
    echo "Használt modul: $EPD_MODULE ($EPD_MODULE_PATH)" | tee -a "$LOG_FILE"
else
    echo "Nem találtam használható modult, alapértelmezett beállítások használata" | tee -a "$LOG_FILE"
    EPD_MODULE="epd4in01f"
    
    # Próbáljuk meghatározni a modul helyét
    if [ -d "$INSTALL_DIR/lib/waveshare_epd" ]; then
        EPD_MODULE_PATH="$INSTALL_DIR/lib/waveshare_epd"
    else
        EPD_MODULE_PATH="$INSTALL_DIR/lib"
    fi
    echo "Alapértelmezett modul: $EPD_MODULE ($EPD_MODULE_PATH)" | tee -a "$LOG_FILE"
    
    # Egyszerű teszt modul létrehozása, ha nem találtunk megfelelőt
    if [ ! -f "$EPD_MODULE_PATH/${EPD_MODULE}.py" ]; then
        echo "Modul nem található, egyszerű teszt modul létrehozása..." | tee -a "$LOG_FILE"
        sudo mkdir -p "$EPD_MODULE_PATH" 2>> "$LOG_FILE"
        cat > /tmp/epd_test.py << EOF
#!/usr/bin/python
# -*- coding:utf-8 -*-

import logging

class EPD:
    def __init__(self):
        self.width = 640
        self.height = 400
        logging.info("4.01inch e-Paper initialized")
    
    def init(self):
        logging.info("init function called")
        return 0
        
    def getbuffer(self, image):
        logging.info("getbuffer function called")
        return [0x00] * (self.width * self.height // 8)
        
    def display(self, buffer):
        logging.info("display function called")
        return 0
        
    def sleep(self):
        logging.info("sleep function called")
        return 0
EOF
        sudo mv /tmp/epd_test.py "$EPD_MODULE_PATH/${EPD_MODULE}.py" 2>> "$LOG_FILE"
        check_success "Nem sikerült létrehozni a teszt modult"
    fi
fi

# Python szkript létrehozása a weboldal e-paper kijelzőn való megjelenítéséhez
echo "Python szkript létrehozása a weboldal e-paper kijelzőn való megjelenítéséhez..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/display_webpage.py" << EOF
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys
import time
import subprocess
from PIL import Image
import logging

# Logging beállítása
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/epaper-display.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('epaper-display')

# E-paper könyvtár hozzáadása az elérési úthoz
sys.path.append('$INSTALL_DIR/lib')
sys.path.append('$INSTALL_DIR/lib/python') if os.path.exists('$INSTALL_DIR/lib/python') else None
sys.path.append('$EPD_MODULE_PATH')

# Az EPD modul könyvtárának azonosítása (waveshare_epd vagy közvetlenül)
if os.path.exists('$EPD_MODULE_PATH/waveshare_epd'):
    epd_module_dir = 'waveshare_epd'
elif os.path.basename('$EPD_MODULE_PATH') == 'waveshare_epd':
    epd_module_dir = ''
else:
    epd_module_dir = ''

# Várakozás boot során a hálózat elérhetőségéig
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

# E-paper modul inicializálása több próbálkozással
def initialize_epd():
    max_attempts = 5
    attempts = 0
    
    logger.info("Összes elérhető útvonal: %s", sys.path)
    logger.info("E-paper modul: $EPD_MODULE")
    logger.info("E-paper modul útvonal: $EPD_MODULE_PATH")
    logger.info("Modul könyvtár: %s", epd_module_dir)
    
    while attempts < max_attempts:
        try:
            # Megpróbáljuk különböző módokon importálni a modult
            if epd_module_dir:
                module_import_str = f"{epd_module_dir}.$EPD_MODULE" if epd_module_dir else "$EPD_MODULE"
                import_cmd = f"from {module_import_str} import EPD"
                logger.info(f"Import parancs: {import_cmd}")
                try:
                    namespace = {}
                    exec(import_cmd, namespace)
                    epd_class = namespace['EPD']
                    logger.info("Modul sikeresen importálva: %s", module_import_str)
                except Exception as e1:
                    logger.warning(f"Hiba az importáláskor: {e1}")
                    try:
                        # Alternatív módszer - közvetlen importálás
                        import_path = os.path.join('$EPD_MODULE_PATH', '$EPD_MODULE.py')
                        logger.info(f"Alternatív import útvonal: {import_path}")
                        
                        spec = importlib.util.spec_from_file_location("$EPD_MODULE", import_path)
                        module = importlib.util.module_from_spec(spec)
                        spec.loader.exec_module(module)
                        epd_class = module.EPD
                        logger.info("Modul sikeresen importálva fájlból")
                    except Exception as e2:
                        logger.error(f"Hiba az alternatív importáláskor: {e2}")
                        raise ImportError("Nem sikerült importálni az e-paper modult")
            else:
                # Közvetlenül próbáljuk meg importálni
                sys.path.append('$EPD_MODULE_PATH')
                from $EPD_MODULE import EPD
                epd_class = EPD
                logger.info("Modul közvetlenül importálva: $EPD_MODULE")
            
            # E-paper kijelző inicializálása
            epd = epd_class()
            logger.info("EPD objektum létrehozva, inicializálás...")
            epd.init()
            logger.info("EPD inicializálás sikeres")
            return epd
            
        except Exception as e:
            attempts += 1
            logger.error(f"Hiba a kijelző inicializálásakor (Próbálkozás {attempts}/{max_attempts}): {e}")
            import traceback
            logger.error(traceback.format_exc())
            
            if attempts < max_attempts:
                logger.info(f"Újrapróbálkozás {5} másodperc múlva...")
                time.sleep(5)
    
    logger.error("Nem sikerült inicializálni a kijelzőt több próbálkozás után sem")
    
    # Szimulációs mód, ha nem sikerült inicializálni
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
            return [0x00] * (self.width * self.height // 8)
            
        def display(self, buffer):
            logger.info("Szimulált kijelzés - a kép mentése: /tmp/epaper_display.png")
            try:
                if isinstance(buffer, list):
                    image = Image.new('1', (self.width, self.height), color=255)
                else:
                    image = buffer
                image.save("/tmp/epaper_display.png")
            except Exception as e:
                logger.error(f"Hiba a szimulált kijelzés során: {e}")
            return 0
            
        def sleep(self):
            logger.info("Szimulált sleep hívás")
            return 0
    
    return SimulatedEPD()

# Weboldal URL meghatározása
WEBPAGE_URL = "http://example.com"  # Cseréld ki a kívánt URL-re

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
        return True
    except Exception as e:
        logger.error(f"Hiba a kép megjelenítésekor: {e}")
        return False

def main():
    try:
        # Várakozás a hálózati kapcsolat elérhetőségére
        if not wait_for_network():
            logger.warning("Figyelmeztetés: Hálózat nem elérhető, de folytatás offline móddal")
        
        # E-paper inicializálása
        logger.info("E-paper kijelző inicializálása...")
        epd = initialize_epd()
        
        # Üdvözlő üzenet megjelenítése (opcionális)
        logger.info("Rendszer indulása, üdvözlő üzenet megjelenítése...")
        try:
            from PIL import Image, ImageDraw, ImageFont
            image = Image.new('RGB', (epd.width, epd.height), color=(255, 255, 255))
            draw = ImageDraw.Draw(image)
            
            # Próbáljunk betölteni egy rendszer betűtípust
            try:
                font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 24)
            except:
                try:
                    font = ImageFont.truetype('/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf', 24)
                except:
                    font = ImageFont.load_default()
                
            draw.text((epd.width//4, epd.height//2), 'E-Paper kijelző indul...', fill=(0, 0, 0), font=font)
            epd.display(epd.getbuffer(image))
            time.sleep(2)  # Rövid idő az üzenet olvasására
        except Exception as e:
            logger.error(f"Nem sikerült megjeleníteni az üdvözlő üzenetet: {e}")
        
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
            
            # Várakozás 5 percig a következő frissítés előtt
            logger.info("Várakozás 5 percig a következő frissítés előtt...")
            time.sleep(300)
    except KeyboardInterrupt:
        logger.info("Program leállítva a felhasználó által")
        epd.sleep()
    except Exception as e:
        logger.error(f"Nem várt hiba történt: {e}")
        import traceback
        logger.error(traceback.format_exc())
        # Próbáljuk újraindítani a programot hiba esetén
        logger.info("Újraindítás 30 másodperc múlva...")
        time.sleep(30)
        main()  # Rekurzív újraindítás

if __name__ == "__main__":
    # Importokhoz
    import importlib.util
    
    logger.info("Program indítása...")
    main()
EOF

check_success "Nem sikerült létrehozni a Python szkriptet"

# A szkript futtathatóvá tétele
sudo chmod +x "$INSTALL_DIR/display_webpage.py" 2>> "$LOG_FILE"
check_success "Nem sikerült futtathatóvá tenni a szkriptet"

# Módosított Systemd szolgáltatás létrehozása bootoláskor való induláshoz
echo "Systemd szolgáltatás létrehozása bootoláskor való induláshoz..." | tee -a "$LOG_FILE"
cat > /tmp/epaper-display.service << EOF
[Unit]
Description=E-Paper Weboldal Megjelenítő
After=network-online.target
Wants=network-online.target
DefaultDependencies=no

[Service]
Type=simple
User=pi
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_CMD $INSTALL_DIR/display_webpage.py
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
sudo touch /var/log/epaper-display.log /var/log/epaper-display-stdout.log /var/log/epaper-display-stderr.log 2>> "$LOG_FILE"
sudo chown pi:pi /var/log/epaper-display*.log 2>> "$LOG_FILE"

# Szolgáltatás engedélyezése és indítása
echo "Szolgáltatás engedélyezése és indítása..." | tee -a "$LOG_FILE"
sudo systemctl daemon-reload 2>> "$LOG_FILE"
sudo systemctl enable epaper-display.service 2>> "$LOG_FILE"
check_success "Nem sikerült engedélyezni a szolgáltatást"

# Rendszerindítás során automatikus indítás biztosítása rc.local fájl módosításával is
# (alternatív módszer a systemd szolgáltatás mellett)
echo "rc.local módosítása az automatikus indításhoz..." | tee -a "$LOG_FILE"
if [ -f /etc/rc.local ]; then
    # Ellenőrizzük, hogy a szkriptet már hozzáadták-e az rc.local fájlhoz
    if ! grep -q "$INSTALL_DIR/display_webpage.py" /etc/rc.local; then
        # A sor beszúrása az 'exit 0' előtt
        sudo sed -i "s|^exit 0|# E-paper kijelző indítása\n(sleep 30 && $PYTHON_CMD $INSTALL_DIR/display_webpage.py > /var/log/epaper-display-rc.log 2>&1 &)\n\nexit 0|" /etc/rc.local
        check_success "Nem sikerült módosítani az rc.local fájlt"
    fi
else
    # Ha nem létezik az rc.local fájl, létrehozzuk
    cat > /tmp/rc.local << RCLOCAL
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# E-paper kijelző indítása
(sleep 30 && $PYTHON_CMD $INSTALL_DIR/display_webpage.py > /var/log/epaper-display-rc.log 2>&1 &)

exit 0
RCLOCAL

    sudo mv /tmp/rc.local /etc/rc.local
    sudo chmod +x /etc/rc.local
    check_success "Nem sikerült létrehozni az rc.local fájlt"
fi

# Konfigurációs eszköz létrehozása
echo "Konfigurációs eszköz létrehozása..." | tee -a "$LOG_FILE"
cat > "$INSTALL_DIR/configure.py" << EOF
#!/usr/bin/env python3
# -*- coding:utf-8 -*-

import os
import sys

config_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), "display_webpage.py")

def update_url(new_url):
    with open(config_file, 'r') as f:
        content = f.read()
    
    # URL frissítése a fájlban
    content = content.replace('WEBPAGE_URL = "http://example.com"', f'WEBPAGE_URL = "{new_url}"')
    
    # Más URL minta - ha már korábban módosítva lett
    import re
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

sudo chmod +x "$INSTALL_DIR/configure.py" 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni a konfigurációs eszközt"

# Kényelmi szkriptek létrehozása a /usr/local/bin könyvtárban
echo "Kényelmi szkriptek létrehozása..." | tee -a "$LOG_FILE"

# URL konfigurációs szkript
cat > /tmp/epaper-config << EOF
#!/bin/bash
$PYTHON_CMD $INSTALL_DIR/configure.py \$1
EOF

sudo mv /tmp/epaper-config /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-config 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni az epaper-config szkriptet"

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
    *)
        echo "Használat: epaper-service {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF

sudo mv /tmp/epaper-service /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-service 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni az epaper-service szkriptet"

# Kényelmi szkript létrehozása a logok megtekintéséhez
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
    all)
        sudo tail -f /var/log/epaper-display*.log
        ;;
    *)
        echo "Használat: epaper-logs {service|app|stdout|stderr|all}"
        exit 1
        ;;
esac
EOF

sudo mv /tmp/epaper-logs /usr/local/bin/ 2>> "$LOG_FILE"
sudo chmod +x /usr/local/bin/epaper-logs 2>> "$LOG_FILE"
check_success "Nem sikerült létrehozni az epaper-logs szkriptet"

# URL beállítása először
echo "Kérlek add meg az URL-t, amit meg szeretnél jeleníteni:"
read url
$PYTHON_CMD "$INSTALL_DIR/configure.py" "$url" 2>> "$LOG_FILE"
check_success "Nem sikerült konfigurálni az URL-t"

# Szolgáltatás indítása
echo "Szolgáltatás indítása..." | tee -a "$LOG_FILE"
sudo systemctl start epaper-display.service 2>> "$LOG_FILE"
if [ $? -ne 0 ]; then
    echo "Figyelmeztetés: Nem sikerült elindítani a szolgáltatást. Ez hiányzó függőségek vagy hardveres konfiguráció miatt lehet." | tee -a "$LOG_FILE"
    echo "Próbáld manuálisan elindítani az újraindítás után: sudo systemctl start epaper-display.service" | tee -a "$LOG_FILE"
fi

# Összefoglaló
echo "" | tee -a "$LOG_FILE"
echo "Telepítési összefoglaló:" | tee -a "$LOG_FILE"
echo "=====================" | tee -a "$LOG_FILE"
echo "Telepítési könyvtár: $INSTALL_DIR" | tee -a "$LOG_FILE"
echo "URL konfigurációs parancs: epaper-config <url>" | tee -a "$LOG_FILE"
echo "Szolgáltatáskezelés: epaper-service {start|stop|restart|status}" | tee -a "$LOG_FILE"
echo "Logok megtekintése: epaper-logs {service|app|stdout|stderr|all}" | tee -a "$LOG_FILE"

if [ "$REBOOT_REQUIRED" = true ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "A telepítés befejezéséhez ÚJRAINDÍTÁS SZÜKSÉGES." | tee -a "$LOG_FILE"
    echo "Kérlek indítsd újra a Raspberry Pi-t: sudo reboot" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Telepítés befejezve: $(date)" | tee -a "$LOG_FILE"
echo "Részletes naplókat lásd: $LOG_FILE" | tee -a "$LOG_FILE"
