"""Scraper for the Oman Ministry of Endowments and Religious Affairs (MARA)
prayer-time calendar at https://www.mara.gov.om/calendar_page2.asp.

The page is a POST form (year, month, CityID) that returns an HTML table:
    Date | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha
Times are printed on a 12-hour clock without AM/PM, so they are normalised
here to minutes after midnight (24-hour).
"""

import html
import os
import re
import ssl
import time
import urllib.parse
import urllib.request

URL = "https://www.mara.gov.om/calendar_page2.asp"

# The MARA server does not send its intermediate certificate. Browsers and
# Windows fetch it on their own; OpenSSL (Linux, GitHub Actions) does not,
# so trust the system roots plus that one intermediate.
_SSL = ssl.create_default_context()
_SSL.load_verify_locations(os.path.join(os.path.dirname(__file__), "digicert-g2-tls-rsa-sha256-2020-ca1.pem"))

# Index in each row -> True when the value is afternoon/evening (needs +12h).
PRAYERS = ("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha")
_PM = (False, False, None, True, True, True)  # None = dhuhr, decided per value

_ROW_RE = re.compile(r"<tr>(.*?)(?=<tr>|</table>)", re.S | re.I)
_CELL_RE = re.compile(r"<font[^>]*>(.*?)</font>", re.S | re.I)
_CITY_RE = re.compile(r"<option value\s*=\s*(\d+)[^>]*>(.*?)</option>", re.I)
_CITY_SELECT_RE = re.compile(r'<select name="CityID">(.*?)</select>', re.S | re.I)


def _to_minutes(value, pm):
    h, m = (int(x) for x in value.strip().split(":"))
    if pm is None:  # Dhuhr: 11:xx is morning, 12:xx and 1:xx are afternoon
        pm = h < 11
    if pm and h < 12:
        h += 12
    return h * 60 + m


def _post(fields, retries=3):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        URL,
        data=data,
        headers={
            "User-Agent": "Mozilla/5.0 (Salah prayer-time sync)",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=30, context=_SSL) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(2 * (attempt + 1))


def fetch_cities():
    """Return [(city_id, name), ...] from the form's city drop-down."""
    page = _post({"year": time.gmtime().tm_year, "month": 1, "CityID": 0, "B1": "View"})
    select = _CITY_SELECT_RE.search(page)
    if not select:
        raise RuntimeError("City list not found on MARA page")
    return [(int(i), html.unescape(n).strip()) for i, n in _CITY_RE.findall(select.group(1))]


def fetch_month(city_id, year, month):
    """Return a list of [fajr, sunrise, dhuhr, asr, maghrib, isha] (minutes
    after midnight), one entry per day of the month, in day order."""
    page = _post({"year": year, "month": month, "CityID": city_id, "B1": "View"})
    days = {}
    for row in _ROW_RE.findall(page):
        cells = [html.unescape(c).strip() for c in _CELL_RE.findall(row)]
        if len(cells) < 7 or not re.match(r"\d+/\d+/\d{4}$", cells[0]):
            continue  # header row or junk
        d, m, y = (int(x) for x in cells[0].split("/"))
        if (m, y) != (month, year):
            raise RuntimeError(f"Unexpected date {cells[0]} for {year}-{month:02d}")
        days[d] = [_to_minutes(v, pm) for v, pm in zip(cells[1:7], _PM)]
    if not days:
        raise RuntimeError(f"No prayer rows for city {city_id} {year}-{month:02d}")
    if sorted(days) != list(range(1, len(days) + 1)):
        raise RuntimeError(f"Missing days for city {city_id} {year}-{month:02d}")
    _sanity_check(days, city_id, year, month)
    return [days[d] for d in sorted(days)]


def _sanity_check(days, city_id, year, month):
    for d, t in days.items():
        if t != sorted(t) or not (180 <= t[0] <= 420) or not (1020 <= t[5] <= 1320):
            raise RuntimeError(f"Implausible times for city {city_id} {year}-{month:02d}-{d:02d}: {t}")
