"""Build the static feed the watch app downloads once a year.

Scrapes MARA for every city and every month of the given years (default: this
year and next, Oman time) and writes, per year, batches of CHUNK cities:

    <out>/v2/<year>/<chunk>.json
        {"v":2,"year":2026,"chunk":0,"cities":[[cityId,"<base64>"], ...]}
        chunk = cityId // CHUNK; the base64 payload is codec.encode_year()
    <out>/v2/cities.json
        [[cityId, name], ...]

Usage:
    python server/build_site.py site              # this year and next
    python server/build_site.py site 2027         # specific year(s)
"""

import base64
import datetime as dt
import json
import os
import sys
import time

import codec
import mara

OMAN = dt.timezone(dt.timedelta(hours=4))
CHUNK = 12  # cities per download; must match Sync.CHUNK on the watch


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


def build_year(out, year, cities):
    chunks = {}
    for city_id, name in cities:
        months = []
        for month in range(1, 13):
            months.append(mara.fetch_month(city_id, year, month))
            time.sleep(0.3)  # be gentle with the ministry's server
        data = codec.encode_year(year, months)
        for month, rows in enumerate(months, 1):  # verify the round trip
            for day, times in enumerate(rows, 1):
                if codec.decode_day(data, year, month, day) != times:
                    raise RuntimeError(f"codec mismatch {city_id} {year}-{month}-{day}")
        chunks.setdefault(city_id // CHUNK, []).append([city_id, base64.b64encode(data).decode()])
        print(f"{year} {city_id:3d} {name}: {len(data)} bytes", flush=True)
    for chunk, entries in chunks.items():
        write_json(os.path.join(out, "v2", str(year), f"{chunk}.json"),
                   {"v": 2, "year": year, "chunk": chunk, "cities": entries})


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "site"
    years = [int(y) for y in sys.argv[2:]]
    if not years:
        this = dt.datetime.now(OMAN).year
        years = [this, this + 1]
    cities = mara.fetch_cities()
    write_json(os.path.join(out, "v2", "cities.json"), cities)
    for year in years:
        build_year(out, year, cities)

    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write("<!doctype html><meta charset=utf-8><title>Salah data</title>"
                "<p>Prayer times from <a href=https://www.mara.gov.om/calendar_page2.asp>MARA</a> "
                "for the Salah Garmin app. See <a href=v2/cities.json>v2/cities.json</a>.</p>\n")


if __name__ == "__main__":
    main()
