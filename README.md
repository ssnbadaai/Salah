# Salah

Prayer times from Oman's Ministry of Endowments and Religious Affairs
([MARA](https://www.mara.gov.om/calendar_page2.asp)) and a Qibla compass for the
Garmin Fēnix 7X.

```
MARA website ──(monthly GitHub Action: server/build_site.py)──► feed on GitHub Pages
                                                                   │
                                          Garmin Connect app on phone (Bluetooth)
                                                                   ▼
                                   Fēnix 7X widget (garmin/), stores a whole year
```

Why the extra hop: Connect IQ watches can only read JSON or `text/plain`
through the phone, and MARA serves an HTML form (`POST year, month, CityID`).
The scraper packs each city's whole year into 678 bytes, so the watch can
hold every MARA city for the year.

## The watch app (`garmin/`)

* **Glance** – next prayer, its time and a countdown.
* **Prayer screen** – today's Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha for the
  MARA city nearest to your GPS position. The next prayer is highlighted and passed
  ones are greyed. If the nearest city is over 50 km away, the distance is shown.
* **Qibla compass** – press **START** (or tap, or press **DOWN**). The rose turns
  with the watch's compass. The arrow and Kaaba marker point to Makkah, and they
  turn green with a short vibration when the top of the watch faces the Qibla
  (±5°). The centre shows the Qibla bearing; distance to Makkah is shown below it.
  **BACK** returns.

Times are MARA's (Oman time, UTC+4) regardless of the watch's time zone.

**Data on the watch:** on first open the watch downloads the **whole year for all
86 cities** (~58 KB) in 8 requests, starting with the batch that holds your
city. From 1 December it downloads next year the same way, and last year's data
is deleted in January. Between those downloads the app needs no phone or
internet, including when you travel between cities. The app has to be open while
it downloads; an interrupted download resumes the next time you open it.

Settings (Garmin Connect app → Connect IQ → Salah → Settings):

| Setting  | Default | |
|----------|---------|-|
| City     | Automatic (nearest to GPS) | or any of MARA's 86 cities |
| Data URL | `https://ssnbadaai.github.io/Salah` | where the JSON feed is hosted |

### Build and run

1. Open the Connect IQ SDK Manager
   (`connectiq-sdk-manager-windows\sdkmanager.exe`). Sign in, install the latest SDK,
   and under *Devices* download **fēnix 7X / 7X Pro**.
2. VS Code: install the **Monkey C** extension, then run *Monkey C: Generate a
   Developer Key* once.
3. Open this folder and run *Monkey C: Build for Device* → `fenix7x`, or
   *Run App* to use the simulator. In the simulator, set a position under
   *Simulation → Set Position* and a compass heading under *Simulation → Sensor Data*.

   Command line equivalent:
   ```
   monkeyc -f garmin/monkey.jungle -d fenix7x -o bin/Salah.prg -y developer_key.der
   ```
4. Sideload: connect the watch by USB and copy `Salah.prg` to `GARMIN/APPS/`.
   The Garmin Connect phone app must be paired, because it relays the downloads.

Other Fēnix 7 or Epix models can be added in `garmin/manifest.xml`. The layout
scales with screen size.

## Data feed (`server/`)

`server/build_site.py <outdir> [year …]` scrapes every month of this year and
next (1,032 requests per year) for all cities and writes:

* `v2/<year>/<chunk>.json` →
  `{"v":2,"year":2026,"chunk":0,"cities":[[cityId,"<base64>"],…]}`, 12 cities per
  chunk (`chunk = cityId // 12`). Each base64 payload is one city's year, packed
  by [server/codec.py](server/codec.py): day-1 times per month, then each day's
  change in 2 bits. Every day is checked by decoding it again before writing.
  MARA prints a 12-hour clock with no AM/PM, so times are converted to 24-hour
  minutes first.
* `v2/cities.json` → `[[cityId, name], …]`

`.github/workflows/prayer-data.yml` runs it on the 1st of each month and
publishes to GitHub Pages.
To enable it: **Settings → Pages → Source: GitHub Actions**. On the free GitHub
plan, Pages needs a **public** repository. Otherwise, host the `site/` folder
anywhere that serves `application/json` over HTTPS, and point the *Data URL*
setting at it.

MARA's server omits its intermediate TLS certificate. Windows works around this,
but Linux/OpenSSL does not, so the DigiCert intermediate is bundled
(`server/digicert-g2-tls-rsa-sha256-2020-ca1.pem`, valid until 2031).

## City coordinates (`tools/`)

MARA lists 86 places but no coordinates. `tools/fit_city_coords.py` recovers them
from the timetables themselves: the sunrise–maghrib midpoint gives longitude, and
day length over the year gives latitude. It is calibrated on 10 well-known cities,
where it lands within about 5 km. `tools/gen_resources.py` turns the result into
the watch's city table, the settings list and the launcher icon.

To regenerate (e.g. if MARA adds cities):
```
python -c "import sys,json,time; sys.path.insert(0,'server'); import mara; c=mara.fetch_cities(); json.dump({'cities':c,'data':{f'{i}-{m}':mara.fetch_month(i,2026,m) for i,_ in c for m in (3,6,9,12)}},open('sample.json','w'))"
python tools/fit_city_coords.py sample.json > cities.json
python tools/gen_resources.py cities.json
```

## Notes

* The Qibla is the great-circle bearing to the Kaaba (21.4225° N, 39.8262° E),
  e.g. 266° from Muscat, 290° from Salalah. Calibrate the watch compass
  (Settings → Sensors → Compass → Calibrate) if the arrow seems off. Keep the watch
  level and away from metal.
* Outside Oman the app still shows the nearest MARA city (with its distance). The
  Qibla compass works anywhere.
