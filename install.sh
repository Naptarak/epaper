#!/bin/bash

set -e

echo "Frissítés és függőségek telepítése..."
sudo apt-get update
sudo apt-get install -y python3 python3-pip git

echo "Python csomagok telepítése..."
pip3 install pillow requests

APPDIR="/home/pi/weather-epaper"
PYFILE="$APPDIR/epaper_display.py"

echo "Alkalmazás mappa létrehozása..."
mkdir -p "$APPDIR"

echo "Waveshare driver letöltése..."
cd "$APPDIR"
if [ ! -d "$APPDIR/e-Paper" ]; then
    git clone https://github.com/waveshare/e-Paper.git
fi

echo "Python alkalmazás generálása..."

cat > "$PYFILE" << 'EOF'
# epaper_display.py
import time
import datetime
import requests
from PIL import Image, ImageDraw, ImageFont
import os
import sys

# --- Waveshare driver import ---
sys.path.append(os.path.join(os.path.dirname(__file__), 'e-Paper/RaspberryPi_JetsonNano/python/lib'))
from waveshare_epd import epd4in01f

# ----- Felhasználói beállítások -----
API_KEY = "1e39a49c6785626b3aca124f4d4ce591"
CITY = "Pécs"
COUNTRY = "HU"
LAT = 46.0763
LON = 18.2281

epd = epd4in01f.EPD()
W, H = epd.width, epd.height

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SMALL_FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

font_large = ImageFont.truetype(FONT_PATH, 38)
font_mid = ImageFont.truetype(FONT_PATH, 22)
font_small = ImageFont.truetype(SMALL_FONT_PATH, 16)
font_tiny = ImageFont.truetype(SMALL_FONT_PATH, 12)

def get_weather():
    try:
        url = f"https://api.openweathermap.org/data/2.5/weather?q={CITY},{COUNTRY}&units=metric&appid={API_KEY}&lang=hu"
        resp = requests.get(url, timeout=10)
        data = resp.json()
        return data
    except:
        return None

def get_forecast():
    try:
        url = f"https://api.openweathermap.org/data/2.5/forecast?q={CITY},{COUNTRY}&units=metric&appid={API_KEY}&lang=hu"
        resp = requests.get(url, timeout=10)
        data = resp.json()
        return data
    except:
        return None

def get_holiday(dt):
    # fix magyar ünnepek, bővíthető
    mozgok = moving_holidays(dt.year)
    key = dt.strftime("%m-%d")
    fixed = {
        "01-01": "Újév", "03-15": "Nemzeti ünnep", "05-01": "Munka ünnepe", "08-20": "Államalapítás",
        "10-23": "Nemzeti ünnep", "11-01": "Mindenszentek", "12-24": "Szenteste",
        "12-25": "Karácsony", "12-26": "Karácsony", "12-31": "Szilveszter"
    }
    if key in fixed:
        return fixed[key]
    # mozgó ünnepek
    for name, date in mozgok.items():
        if dt.date() == date:
            return name
    return ""

def moving_holidays(year):
    # húsvét algoritmus (Gauss)
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    easter = datetime.date(year, month, day)
    return {
        "Nagypéntek": easter - datetime.timedelta(days=2),
        "Húsvét": easter,
        "Húsvéthétfő": easter + datetime.timedelta(days=1),
        "Áldozócsütörtök": easter + datetime.timedelta(days=39),
        "Pünkösd": easter + datetime.timedelta(days=49),
        "Pünkösdhétfő": easter + datetime.timedelta(days=50),
    }

def get_weekday_hu(dt):
    napok = ["Hét", "Ke", "Sze", "Csüt", "Pén", "Szo", "Vas"]
    return napok[dt.weekday()]

def draw_weather(epd, weather, forecast):
    image = Image.new("RGB", (W, H), (255, 255, 255))
    draw = ImageDraw.Draw(image)

    now = datetime.datetime.now()
    date_str = now.strftime("%Y. %m.%d. %a")
    holiday = get_holiday(now)
    if holiday:
        draw.rectangle([0,0,W,35], fill=(255,0,0))
        draw.text((10, 2), date_str, font=font_mid, fill=(255,255,255))
        draw.text((200, 2), holiday, font=font_mid, fill=(255,255,0))
    else:
        draw.rectangle([0,0,W,35], fill=(0,51,255))
        draw.text((10, 2), date_str, font=font_mid, fill=(255,255,255))

    # Aktuális időjárás
    if weather:
        temp = int(round(weather['main']['temp']))
        desc = weather['weather'][0]['description'].capitalize()
        wind = round(weather['wind']['speed']*3.6)
        humid = weather['main']['humidity']
        press = weather['main']['pressure']
        draw.text((10,40), f"{temp}°C  {desc}", font=font_large, fill=(255,0,0))
        draw.text((10,95), f"Szél: {wind} km/h", font=font_mid, fill=(0,0,0))
        draw.text((180,95), f"Párat.: {humid}%", font=font_mid, fill=(0,0,0))
        draw.text((320,95), f"Nyomás: {press} hPa", font=font_mid, fill=(0,0,0))
        # Ikon (egyszerűsített)
        code = weather['weather'][0]['icon']
        if "d" in code:
            color = (255,200,50)
        else:
            color = (50,100,255)
        draw.ellipse([420,40,490,110], fill=color, outline=(0,0,0), width=2)
    else:
        draw.text((10,40), "Nincs adat", font=font_large, fill=(128,128,128))

    # 4 napos előrejelzés
    if forecast:
        x0 = 20
        dx = 110
        y0 = 150
        n = 0
        seen = set()
        for f in forecast['list']:
            dt = datetime.datetime.fromtimestamp(f['dt'])
            daykey = dt.date().isoformat()
            if dt.hour in [11,12,13,14] and daykey not in seen and n < 4:
                seen.add(daykey)
                temp = int(round(f['main']['temp']))
                day = get_weekday_hu(dt)
                holiday_f = get_holiday(dt)
                fillcol = (255,0,0) if holiday_f else (0,0,255)
                draw.text((x0 + n*dx, y0), day, font=font_mid, fill=fillcol)
                draw.text((x0 + n*dx, y0+30), f"{temp}°C", font=font_large, fill=(0,128,0))
                draw.ellipse([x0 + n*dx + 5, y0+75, x0 + n*dx + 45, y0+115], fill=(128,128,128), outline=(0,0,0))
                n += 1
    draw.text((10, H-35), f"Frissítve: {now.strftime('%H:%M:%S')}", font=font_small, fill=(100,100,100))
    return image

def mainloop():
    epd.init()
    epd.Clear()
    while True:
        try:
            weather = get_weather()
            forecast = get_forecast()
            image = draw_weather(epd, weather, forecast)
            epd.display(epd.getbuffer(image))
        except Exception as e:
            image = Image.new("RGB", (W, H), (255,255,255))
            draw = ImageDraw.Draw(image)
            draw.text((10,10), "Hiba!", font=font_large, fill=(255,0,0))
            draw.text((10,60), str(e), font=font_small, fill=(0,0,0))
            epd.display(epd.getbuffer(image))
        time.sleep(300)

if __name__ == '__main__':
    mainloop()
EOF

# SYSTEMD service készítése
SERVICE_FILE="/etc/systemd/system/weather-epaper.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Weather E-Paper display autostart
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=$APPDIR
ExecStart=/usr/bin/python3 $PYFILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable weather-epaper.service
sudo systemctl restart weather-epaper.service

echo "Telepítés kész! A kijelző 5 percenként automatikusan frissül."
