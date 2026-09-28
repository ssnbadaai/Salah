"""Compact binary encoding of one city's prayer times for a whole year.

Day-to-day changes are almost always -1, 0 or +1 minute, so each change is
stored in 2 bits. The watch app decodes this (see garmin/source/PrayerData.mc);
keep both in sync.

Layout, all integers big-endian:
    12 month blocks, January first:
        6 x uint16      fajr, sunrise, dhuhr, asr, maghrib, isha on day 1
                        (minutes after midnight)
        packed deltas   (days_in_month - 1) * 6 codes, 4 per byte, low bits
                        first; delta k (day k // 6 + 2, prayer k % 6) = code - 2
    uint16              number of exceptions
    exceptions          uint8 month, uint16 k, uint8 (correction + 128)
                        for deltas outside -2..+1: true delta = code - 2 + correction
"""

import calendar
import struct

PRAYERS = 6


def block_size(days):
    return 2 * PRAYERS + ((days - 1) * PRAYERS + 3) // 4


def encode_year(year, months):
    """months: 12 lists of [fajr, sunrise, dhuhr, asr, maghrib, isha] per day."""
    out = bytearray()
    exceptions = []
    for month, rows in enumerate(months, 1):
        if len(rows) != calendar.monthrange(year, month)[1]:
            raise ValueError(f"{year}-{month:02d}: {len(rows)} days")
        out += struct.pack(">6H", *rows[0])
        codes = []
        for d in range(1, len(rows)):
            for p in range(PRAYERS):
                delta = rows[d][p] - rows[d - 1][p]
                clamped = min(1, max(-2, delta))
                if clamped != delta:
                    exceptions.append((month, len(codes), delta - clamped))
                codes.append(clamped + 2)
        packed = bytearray((len(codes) + 3) // 4)
        for k, code in enumerate(codes):
            packed[k // 4] |= code << ((k % 4) * 2)
        out += packed
    out += struct.pack(">H", len(exceptions))
    for month, k, corr in exceptions:
        out += struct.pack(">BHB", month, k, corr + 128)
    return bytes(out)


def decode_day(data, year, month, day):
    """Reference decoder, mirrors PrayerData.dayTimes on the watch."""
    offset = sum(block_size(calendar.monthrange(year, m)[1]) for m in range(1, month))
    times = list(struct.unpack_from(">6H", data, offset))
    n = (day - 1) * PRAYERS
    base = offset + 2 * PRAYERS
    for k in range(n):
        times[k % PRAYERS] += ((data[base + k // 4] >> ((k % 4) * 2)) & 3) - 2
    exc = sum(block_size(calendar.monthrange(year, m)[1]) for m in range(1, 13))
    for i in range(struct.unpack_from(">H", data, exc)[0]):
        m, k, corr = struct.unpack_from(">BHB", data, exc + 2 + 4 * i)
        if m == month and k < n:
            times[k % PRAYERS] += corr - 128
    return times
