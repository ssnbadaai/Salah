import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Downloaded MARA timetables and next-prayer logic. Read-only on Storage so it
// can run in the glance; Sync (full app only) downloads and writes the data.
//
// Storage layout:
//   "city"             [cityId, name, distanceKm or -1]
//   "y<year>_<id>"     ByteArray: one city's whole year, packed as described
//                      in server/codec.py (keep the two in sync)
//   "c<year>"          Array of downloaded chunk numbers for that year
(:glance)
module PrayerData {
    const FAJR = 0;
    const SUNRISE = 1;
    const ISHA = 5;
    const NAMES = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"];

    // MARA publishes Oman local time (UTC+4, no DST); work in that zone
    // regardless of the watch's own time zone.
    const OMAN_OFFSET_SEC = 4 * 3600;

    function omanInfo(dayOffset as Number) as Gregorian.Info {
        var t = Time.now().add(new Time.Duration(OMAN_OFFSET_SEC + dayOffset * 86400));
        return Gregorian.utcInfo(t, Time.FORMAT_SHORT);
    }

    function yearKey(year as Number, cityId as Number) as String {
        return "y" + year + "_" + cityId;
    }

    function city() as Array? {
        return Application.Storage.getValue("city") as Array?;
    }

    function daysInMonth(year as Number, month as Number) as Number {
        if (month == 2) {
            return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28;
        }
        return (month == 4 || month == 6 || month == 9 || month == 11) ? 30 : 31;
    }

    // Bytes in one month block: 6 uint16 start times + 2-bit daily deltas.
    function blockSize(days as Number) as Number {
        return 12 + ((days - 1) * 6 + 3) / 4;
    }

    // Prayer times [fajr, sunrise, dhuhr, asr, maghrib, isha] in minutes for
    // one Oman calendar day, or null if that year isn't downloaded.
    function dayTimes(cityId as Number, info as Gregorian.Info) as Array? {
        var year = info.year as Number;
        var month = info.month as Number;
        var data = Application.Storage.getValue(yearKey(year, cityId)) as ByteArray?;
        if (data == null) {
            return null;
        }
        var offset = 0;
        for (var m = 1; m < month; m++) {
            offset += blockSize(daysInMonth(year, m));
        }
        var times = new [6];
        for (var p = 0; p < 6; p++) {
            times[p] = ((data[offset + 2 * p] as Number) << 8) | (data[offset + 2 * p + 1] as Number);
        }
        var n = ((info.day as Number) - 1) * 6;
        var base = offset + 12;
        for (var k = 0; k < n; k++) {
            times[k % 6] = (times[k % 6] as Number) + ((((data[base + k / 4] as Number) >> ((k % 4) * 2)) & 3) - 2);
        }
        // Rare deltas outside -2..+1 are stored as corrections after month 12.
        var exc = offset;
        for (var mm = month; mm <= 12; mm++) {
            exc += blockSize(daysInMonth(year, mm));
        }
        var count = ((data[exc] as Number) << 8) | (data[exc + 1] as Number);
        for (var i = 0; i < count; i++) {
            var e = exc + 2 + 4 * i;
            var ek = ((data[e + 1] as Number) << 8) | (data[e + 2] as Number);
            if ((data[e] as Number) == month && ek < n) {
                times[ek % 6] = (times[ek % 6] as Number) + (data[e + 3] as Number) - 128;
            }
        }
        return times;
    }

    // [prayerIndex, timeMinutes, minutesUntil, isTomorrow] for the next of the
    // five prayers (sunrise is shown but isn't a prayer), or null when today
    // isn't cached.
    function nextPrayer(cityId as Number) as Array? {
        var now = omanInfo(0);
        var nowMin = (now.hour as Number) * 60 + (now.min as Number);
        var today = dayTimes(cityId, now);
        if (today == null) {
            return null;
        }
        for (var i = FAJR; i <= ISHA; i++) {
            if (i != SUNRISE && (today[i] as Number) > nowMin) {
                return [i, today[i], (today[i] as Number) - nowMin, false];
            }
        }
        // After Isha: tomorrow's Fajr (today's is within a minute if tomorrow
        // falls in a year that hasn't been downloaded yet).
        var tomorrow = dayTimes(cityId, omanInfo(1));
        var fajr = (tomorrow != null ? tomorrow[FAJR] : today[FAJR]) as Number;
        return [FAJR, fajr, fajr + 1440 - nowMin, true];
    }

    function formatTime(minutes as Number) as String {
        var h = (minutes / 60) % 24;
        var m = minutes % 60;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            return (h == 0 ? 12 : h) + ":" + m.format("%02d");
        }
        return h.format("%02d") + ":" + m.format("%02d");
    }

    function formatCountdown(minutes as Number) as String {
        if (minutes < 60) {
            return minutes + "m";
        }
        return (minutes / 60) + "h " + (minutes % 60).format("%02d") + "m";
    }
}
