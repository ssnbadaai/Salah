"""Build the static JSON feed the watch app reads.

Scrapes MARA for every city for the current month and the next month (Oman
time) and writes:

    <out>/v1/<cityId>/<yyyy>-<mm>.json
        {"v":1,"city":0,"name":"Muscat","year":2026,"month":9,
         "days":[[fajr,sunrise,dhuhr,asr,maghrib,isha], ...]}   minutes after midnight
    <out>/v1/cities.json
        [[cityId, name], ...]

Usage:
    python server/build_site.py site            # current + next month
    python server/build_site.py site 2026 10    # a specific month only
"""

import datetime as dt
import json
import os
import sys
import time

import mara

OMAN = dt.timezone(dt.timedelta(hours=4))


def months_to_build(argv):
    if len(argv) >= 4:
        return [(int(argv[2]), int(argv[3]))]
    today = dt.datetime.now(OMAN).date()
    nxt = (today.replace(day=1) + dt.timedelta(days=32)).replace(day=1)
    return [(today.year, today.month), (nxt.year, nxt.month)]


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "site"
    cities = mara.fetch_cities()
    write_json(os.path.join(out, "v1", "cities.json"), cities)

    for year, month in months_to_build(sys.argv):
        for city_id, name in cities:
            days = mara.fetch_month(city_id, year, month)
            write_json(
                os.path.join(out, "v1", str(city_id), f"{year}-{month:02d}.json"),
                {"v": 1, "city": city_id, "name": name, "year": year, "month": month, "days": days},
            )
            time.sleep(0.3)  # be gentle with the ministry's server
        print(f"{year}-{month:02d}: {len(cities)} cities", flush=True)

    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write("<!doctype html><meta charset=utf-8><title>Salah data</title>"
                "<p>Prayer times from <a href=https://www.mara.gov.om/calendar_page2.asp>MARA</a> "
                "as JSON for the Salah Garmin app. See <a href=v1/cities.json>v1/cities.json</a>.</p>\n")


if __name__ == "__main__":
    main()
