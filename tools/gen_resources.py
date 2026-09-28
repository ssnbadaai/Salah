"""Generate the watch app's city resources and launcher icon.

    python tools/gen_resources.py cities.json

cities.json is the output of tools/fit_city_coords.py: [[id, name, lat, lon], ...].
Writes:
    garmin/resources/jsonData/cities.json     city table used to pick the nearest city
    garmin/resources/settings/settings.xml    Garmin Connect settings (city picker)
    garmin/resources/strings/cities.xml       city names for the settings list
    garmin/resources/drawables/launcher_icon.png
"""

import json
import math
import os
import struct
import sys
import zlib
from xml.sax.saxutils import escape

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "garmin", "resources")


def write(rel, text):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def gen_cities(cities):
    write("jsonData/cities.json", json.dumps({"c": cities}, ensure_ascii=False, separators=(",", ":")) + "\n")

    strings = ['<strings>', '    <string id="CityAuto">Automatic (nearest to GPS)</string>']
    strings += [f'    <string id="City{c[0]}">{escape(c[1])}</string>' for c in cities]
    write("strings/cities.xml", "\n".join(strings + ["</strings>", ""]))

    entries = ['            <listEntry value="-1">@Strings.CityAuto</listEntry>']
    entries += [f'            <listEntry value="{c[0]}">@Strings.City{c[0]}</listEntry>'
                for c in sorted(cities, key=lambda c: c[1].lower())]
    write("settings/settings.xml", "\n".join([
        "<settings>",
        '    <setting propertyKey="@Properties.cityId" title="@Strings.CityTitle">',
        '        <settingConfig type="list">',
        *entries,
        "        </settingConfig>",
        "    </setting>",
        '    <setting propertyKey="@Properties.dataUrl" title="@Strings.DataUrlTitle">',
        '        <settingConfig type="alphaNumeric" />',
        "    </setting>",
        "</settings>",
        "",
    ]))


def png(path, size, pixel):
    """Write an RGBA PNG; pixel(x, y) -> (r, g, b, a), 4x4 supersampled."""
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(4):
                for sx in range(4):
                    r, g, b, a = pixel(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)
                    acc = [acc[0] + r * a, acc[1] + g * a, acc[2] + b * a, acc[3] + a]
            a = acc[3] / 16
            row += bytes([round(acc[i] / acc[3]) if acc[3] else 0 for i in range(3)] + [round(a)])
        rows.append(bytes(row))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def gen_icon(size=70):
    c = size / 2

    def pixel(x, y):
        dx, dy = x - c, y - c
        if math.hypot(dx, dy) > c - 0.5:
            return (0, 0, 0, 0)
        # Kaaba: dark cube with a gold band
        k = size * 0.19
        kx, ky = c + size * 0.08, c + size * 0.12
        if abs(x - kx) <= k and abs(y - ky) <= k:
            if abs(y - (ky - k * 0.45)) <= size * 0.035:
                return (230, 180, 40, 255)
            return (20, 20, 20, 255)
        # crescent above-left
        mx, my, mr = c - size * 0.12, c - size * 0.13, size * 0.2
        if math.hypot(x - mx, y - my) <= mr and math.hypot(x - mx - mr * 0.45, y - my + mr * 0.2) > mr * 0.8:
            return (245, 245, 245, 255)
        return (0, 120, 90, 255)

    png(os.path.join(ROOT, "drawables", "launcher_icon.png"), size, pixel)


if __name__ == "__main__":
    cities = json.load(open(sys.argv[1], encoding="utf-8"))
    gen_cities(cities)
    gen_icon()
