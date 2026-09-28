import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Cached MARA timetables and next-prayer logic. Read-only on Storage so it can
// run in the glance; Sync (full app only) is what downloads and writes data.
//
// Storage layout:
//   "city"               [cityId, name, distanceKm or -1]
//   "d<id>_<y>_<m>"      one month: [[fajr, sunrise, dhuhr, asr, maghrib, isha], ...]
//                        minutes after midnight, Oman time, one entry per day
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

    function monthKey(cityId as Number, year as Number, month as Number) as String {
        return "d" + cityId + "_" + year + "_" + month;
    }

    function city() as Array? {
        return Application.Storage.getValue("city") as Array?;
    }

    // Prayer times for one Oman calendar day, or null if that month isn't cached.
    function dayTimes(cityId as Number, info as Gregorian.Info) as Array? {
        var days = Application.Storage.getValue(monthKey(cityId, info.year as Number, info.month as Number)) as Array?;
        if (days == null || (info.day as Number) > days.size()) {
            return null;
        }
        return days[(info.day as Number) - 1] as Array;
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
        // falls in a month that hasn't been downloaded yet).
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
