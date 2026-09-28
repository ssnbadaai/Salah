"""Derive approximate coordinates for every MARA city from its published
sunrise/maghrib times, so the watch can pick the nearest city from GPS.

MARA publishes 86 place names but no coordinates, and several are remote
oil fields or villages. The sun gives them away:
  * the midpoint of sunrise and maghrib is local solar noon -> longitude
  * the length of the day across the year                   -> latitude
MARA adds small fixed safety margins (ihtiyat) to its times, so those are
calibrated on cities whose coordinates are well known, then applied to all.

Usage:
    python tools/fit_city_coords.py sample.json > garmin/resources/cities.json
where sample.json holds {"cities": [[id, name], ...],
"data": {"<id>-<month>": [[fajr, sunrise, dhuhr, asr, maghrib, isha], ...]}}
for 2026 (see the README for the one-liner that produces it).
"""

import json
import math
import sys

YEAR = 2026
TZ_MIN = 240  # Oman is UTC+4, no DST

# Well-known reference coordinates used to calibrate MARA's margins.
KNOWN = {
    "Muscat": (23.588, 58.383),
    "Salalah": (17.015, 54.092),
    "Sohar": (24.347, 56.709),
    "Nizwa": (22.933, 57.533),
    "Sur": (22.567, 59.529),
    "Ibri": (23.226, 56.516),
    "Buraimi": (24.251, 55.793),
    "Ibra": (22.690, 58.533),
    "Al Duqm": (19.662, 57.705),
    "Rustaq": (23.391, 57.424),
}
ALIASES = {"Ristaq": "Rustaq"}


def solar(day_of_year):
    """Return (declination_deg, equation_of_time_min) at local noon."""
    g = 2 * math.pi / 365 * (day_of_year - 1 + 0.5 - TZ_MIN / 1440)
    eot = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                    - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g)
            - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
            - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    return math.degrees(decl), eot


def half_day(lat, decl):
    """Minutes from sunrise to solar noon for a -0.833 deg sun altitude."""
    la, de = math.radians(lat), math.radians(decl)
    c = (math.sin(math.radians(-0.833)) - math.sin(la) * math.sin(de)) / (math.cos(la) * math.cos(de))
    return math.degrees(math.acos(max(-1, min(1, c)))) * 4


def day_of_year(month, day):
    return sum([31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][: month - 1]) + day


def observations(data, cid):
    out = []
    for key, rows in data.items():
        c, m = (int(x) for x in key.split("-"))
        if c != cid:
            continue
        for d, t in enumerate(rows, 1):
            decl, eot = solar(day_of_year(m, d))
            out.append((decl, eot, t[1], t[4]))  # sunrise, maghrib
    return out


def raw_lon(obs):
    # mid = 720 + TZ - 4*lon - eot  (+ margin c_mid)
    return sum((720 + TZ_MIN - eot - (sr + mg) / 2) / 4 for _, eot, sr, mg in obs) / len(obs)


def fit_lat(obs, c_half):
    best = None
    for i in range(0, 1400):
        lat = 14 + i * 0.01
        err = sum((half_day(lat, de) + c_half - (mg - sr) / 2) ** 2 for de, _, sr, mg in obs)
        if best is None or err < best[0]:
            best = (err, lat)
    return best[1]


def main():
    sample = json.load(open(sys.argv[1], encoding="utf-8"))
    cities = [(int(i), n) for i, n in sample["cities"]]
    data = sample["data"]

    # Calibrate: longitude bias and half-day margin from well-known cities.
    lon_bias, half_bias = [], []
    for cid, name in cities:
        ref = KNOWN.get(ALIASES.get(name, name))
        if not ref:
            continue
        obs = observations(data, cid)
        lon_bias.append(ref[1] - raw_lon(obs))
        half_bias.append(sum((mg - sr) / 2 - half_day(ref[0], de) for de, _, sr, mg in obs) / len(obs))
    c_lon = sum(lon_bias) / len(lon_bias)
    c_half = sum(half_bias) / len(half_bias)
    print(f"calibration: lon {c_lon:+.3f} deg, half-day {c_half:+.2f} min "
          f"(lon spread {min(lon_bias):+.3f}..{max(lon_bias):+.3f})", file=sys.stderr)

    result = []
    for cid, name in cities:
        obs = observations(data, cid)
        lat, lon = fit_lat(obs, c_half), raw_lon(obs) + c_lon
        ref = KNOWN.get(ALIASES.get(name, name))
        if ref:
            print(f"  check {name:10s} fit {lat:6.2f},{lon:6.2f}  known {ref[0]:6.2f},{ref[1]:6.2f}", file=sys.stderr)
        result.append([cid, name, round(lat, 2), round(lon, 2)])
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    print()


if __name__ == "__main__":
    main()
