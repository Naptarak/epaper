#!/bin/bash

# install.sh - Telepítő szkript e-paper weblap megjelenítőhöz
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

# Waveshare e-paper könyvtár klónozása
echo "Waveshare e-paper könyvtár klónozása..." | tee -a "$LOG_FILE"
cd /tmp
if [ -d "e-Paper" ]; then
    sudo rm -rf e-Paper
fi

if ! git clone https://github.com/waveshare/e-Paper.git 2>> "$LOG_FILE"; then
    echo "Git klónozás sikertelen, alternatív repozitórium kipróbálása..." | tee -a "$LOG_FILE"
    if ! git clone https://github.com/soonuse/epd-library-python.git 2>> "$LOG_FILE"; then
        handle_error "Nem sikerült klónozni az e-paper könyvtárat. Ellenőrizd az internetkapcsolatot vagy próbáld manuálisan."
    else
        echo "Alternatív e-paper könyvtár használata" | tee -a "$LOG_FILE"
        cd epd-library-python/RaspberryPi
        LIB_SRC_DIR="$(pwd)"
    fi
else
    echo "Hivatalos Waveshare könyvtár használata" | tee -a "$LOG_FILE"
    cd e-Paper/RaspberryPi
    LIB_SRC_DIR="$(pwd)"
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

# E-paper könyvtár másolása a telepítési könyvtárba
echo "E-paper könyvtár másolása a telepítési könyvtárba..." | tee -a "$LOG_FILE"
sudo mkdir -p "$INSTALL_DIR/lib" 2>> "$LOG_FILE"
sudo cp -r "$LIB_SRC_DIR/python" "$INSTALL_DIR/lib" 2>> "$LOG_FILE" || true
# Ha a fenti nem működik, próbáljuk meg a közvetlen másolást
if [ ! -d "$INSTALL_DIR/lib/python" ]; then
    echo "Alternatív másolási módszer kipróbálása..." | tee -a "$LOG_FILE"
    sudo cp -r "$LIB_SRC_DIR"/* "$INSTALL_DIR/lib/" 2>> "$LOG_FILE" || true
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

# A megfelelő e-paper modul meghatározása
echo "E-paper modul keresése..." | tee -a "$LOG_FILE"
EPD_MODULE_PATHS=(
    "$INSTALL_DIR/lib/python/waveshare_epd/epd4in01f.py"
    "$INSTALL_DIR/lib/waveshare_epd/epd4in01f.py"
    "$INSTALL_DIR/lib/python/waveshare_epd/epd4_01f.py"
    "$INSTALL_DIR/lib/waveshare_epd/epd4_01f.py"
    "$INSTALL_DIR/lib/e_paper_driver/epd4in01f.py"
)

EPD_MODULE=""
EPD_MODULE_PATH=""
for path in "${EPD_MODULE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        EPD_MODULE=$(basename "$path" .py)
        EPD_MODULE_PATH=$(dirname "$path")
        echo "E-paper modul megtalálva: $EPD_MODULE ($EPD_MODULE_PATH)" | tee -a "$LOG_FILE"
        break
    fi
done

if [ -z "$EPD_MODULE" ]; then
    echo "Figyelmeztetés: Nem sikerült automatikusan meghatározni az e-paper modul nevét" | tee -a "$LOG_FILE"
    echo "Az alapértelmezett 'epd4in01f' modul használata, de lehet, hogy manuálisan módosítani kell" | tee -a "$LOG_FILE"
    EPD_MODULE="epd4in01f"
    # Próbáljuk megtalálni a lib könyvtár helyét
    if [ -d "$INSTALL_DIR/lib/python/waveshare_epd" ]; then
        EPD_MODULE_PATH="$INSTALL_DIR/lib/python/waveshare_epd"
    elif [ -d "$INSTALL_DIR/lib/waveshare_epd" ]; then
        EPD_MODULE_PATH="$INSTALL_DIR/lib/waveshare_epd"
    else
        EPD_MODULE_PATH="waveshare_epd"
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
sys.path.append('$INSTALL_DIR/lib/python')

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
    
    while attempts < max_attempts:
        try:
            # E-paper modul importálása
            try:
                import waveshare_epd.$EPD_MODULE as epd_module
                logger.info("Waveshare EPD modul betöltve")
            except ImportError as e:
                logger.warning(f"Hiba az elsődleges betöltésnél: {e}")
                try:
                    from waveshare_epd import $EPD_MODULE as epd_module
                    logger.info("Alternatív Waveshare EPD modul betöltve")
                except ImportError as e2:
                    logger.warning(f"Hiba a másodlagos betöltésnél: {e2}")
                    try:
                        sys.path.append('$EPD_MODULE_PATH')
                        from $EPD_MODULE import EPD
                        logger.info("Közvetlenül betöltve: $EPD_MODULE")
                        epd_module = __import__('$EPD_MODULE')
                    except ImportError as e3:
                        logger.error(f"Hiba a harmadlagos betöltésnél: {e3}")
                        logger.error("Próbált útvonalak:")
                        logger.error(sys.path)
                        raise ImportError("Nem sikerült importálni az e-paper modult")
            
            # E-paper kijelző inicializálása
            epd = epd_module.EPD()
            logger.info("EPD objektum létrehozva, inicializálás...")
            epd.init()
            logger.info("EPD inicializálás sikeres")
            return epd
            
        except Exception as e:
            attempts += 1
            logger.error(f"Hiba a kijelző inicializálásakor (Próbálkozás {attempts}/{max_attempts}): {e}")
            if attempts < max_attempts:
                logger.info(f"Újrapróbálkozás {5} másodperc múlva...")
                time.sleep(5)
    
    logger.error("Nem sikerült inicializálni a kijelzőt több próbálkozás után sem")
    raise Exception("EPD inicializálási hiba")

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
        # Próbáljuk újraindítani a programot hiba esetén
        logger.info("Újraindítás 30 másodperc múlva...")
        time.sleep(30)
        main()  # Rekurzív újraindítás

if __name__ == "__main__":
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
    content = content.replace(f'WEBPAGE_URL = "{WEBPAGE_URL}"', f'WEBPAGE_URL = "{new_url}"')
    
    with open(config_file, 'w') as f:
        f.write(content)
    
    print(f"URL frissítve: {new_url}")
    print("Kérlek indítsd újra a szolgáltatást: sudo systemctl restart epaper-display.service")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Használat: python3 configure.py <URL>")
        sys.exit(1)
    
    WEBPAGE_URL = "http://example.com"  # Alapértelmezett érték
    
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