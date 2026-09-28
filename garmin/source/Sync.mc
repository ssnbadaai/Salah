import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.WatchUi;

// Location, city selection and download of MARA timetables (via the phone).
class Sync {
    var lat as Float? = null;       // degrees, last known position
    var lon as Float? = null;
    var cityId as Number = 0;
    var cityName as String = "Muscat";
    var cityDistKm as Number = -1;  // -1 when the city was chosen without GPS
    var status as String? = null;   // shown when today's times aren't cached

    hidden var _busy as Boolean = false;
    hidden var _failedKey as String? = null;

    function initialize() {
        var loc = Application.Storage.getValue("loc") as Array?;
        if (loc != null) {
            lat = loc[0] as Float;
            lon = loc[1] as Float;
        }
        chooseCity();
    }

    // Called when a view is shown: refresh GPS and make sure data is cached.
    function start() as Void {
        _failedKey = null;
        var info = Position.getInfo();
        if (info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            onPosition(info);
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        ensureData();
    }

    function stop() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info.position == null) {
            return;
        }
        var deg = (info.position as Position.Location).toDegrees();
        var newLat = deg[0].toFloat();
        var newLon = deg[1].toFloat();
        if (newLat.abs() > 90 || newLon.abs() > 180 || (newLat == 0.0 && newLon == 0.0)) {
            return; // no fix
        }
        lat = newLat;
        lon = newLon;
        Application.Storage.setValue("loc", [newLat, newLon]);
        var oldCity = cityId;
        chooseCity();
        if (cityId != oldCity) {
            ensureData();
        }
        WatchUi.requestUpdate();
    }

    // Fixed city from settings, else the MARA city nearest to the last position.
    function chooseCity() as Void {
        var fixed = Application.Properties.getValue("cityId") as Number?;
        var cities = (WatchUi.loadResource(Rez.JsonData.Cities) as Dictionary)["c"] as Array;
        var best = null;
        var bestDist = 0;
        for (var i = 0; i < cities.size(); i++) {
            var c = cities[i] as Array;
            if (fixed != null && fixed >= 0) {
                if (c[0] == fixed) {
                    best = c;
                    break;
                }
            } else if (lat != null) {
                var d = distanceKm(lat, lon, c[2] as Float, c[3] as Float);
                if (best == null || d < bestDist) {
                    best = c;
                    bestDist = d;
                }
            }
        }
        if (best == null) {
            best = cities[0] as Array; // Muscat until the first GPS fix
        }
        cityId = best[0] as Number;
        cityName = best[1] as String;
        cityDistKm = lat != null ? distanceKm(lat, lon, best[2] as Float, best[3] as Float).toNumber() : -1;
        Application.Storage.setValue("city", [cityId, cityName, cityDistKm]);
    }

    // Download this month if missing, and next month from the 20th on.
    function ensureData() as Void {
        var t = PrayerData.omanInfo(0);
        var y = t.year as Number;
        var m = t.month as Number;
        if (!has(y, m)) {
            request(y, m);
            return;
        }
        status = null;
        if ((t.day as Number) >= 20) {
            var ny = m == 12 ? y + 1 : y;
            var nm = m == 12 ? 1 : m + 1;
            if (!has(ny, nm)) {
                request(ny, nm);
            }
        }
    }

    hidden function has(year as Number, month as Number) as Boolean {
        return Application.Storage.getValue(PrayerData.monthKey(cityId, year, month)) != null;
    }

    hidden function request(year as Number, month as Number) as Void {
        var key = PrayerData.monthKey(cityId, year, month);
        if (_busy || key.equals(_failedKey)) {
            return;
        }
        _busy = true;
        if (PrayerData.dayTimes(cityId, PrayerData.omanInfo(0)) == null) {
            status = "Syncing...";
        }
        var base = Application.Properties.getValue("dataUrl") as String;
        while (base.length() > 0 && base.substring(base.length() - 1, base.length()).equals("/")) {
            base = base.substring(0, base.length() - 1);
        }
        var url = base + "/v1/" + cityId + "/" + year + "-" + month.format("%02d") + ".json";
        Communications.makeWebRequest(url, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :context => key
        }, method(:onResponse));
    }

    function onResponse(code as Number, data, key) as Void {
        _busy = false;
        if (code == 200 && data instanceof Dictionary && data["days"] instanceof Array) {
            var got = PrayerData.monthKey(data["city"] as Number, data["year"] as Number, data["month"] as Number);
            Application.Storage.setValue(got, data["days"]);
            remember(got, (data["year"] as Number) * 12 + (data["month"] as Number));
            status = null;
            ensureData(); // may queue next month
        } else {
            _failedKey = key as String;
            if (PrayerData.dayTimes(cityId, PrayerData.omanInfo(0)) == null) {
                status = code == Communications.BLE_CONNECTION_UNAVAILABLE
                    ? "Phone not connected"
                    : "Sync failed (" + code + ")";
            }
            ensureData(); // the city may have changed meanwhile; failed key isn't retried
        }
        WatchUi.requestUpdate();
    }

    // Track cached months and drop those older than the current one.
    hidden function remember(key as String, monthIndex as Number) as Void {
        var t = PrayerData.omanInfo(0);
        var current = (t.year as Number) * 12 + (t.month as Number);
        var kept = [[key, monthIndex]];
        var list = Application.Storage.getValue("months") as Array?;
        if (list != null) {
            for (var i = 0; i < list.size(); i++) {
                var e = list[i] as Array;
                if ((e[0] as String).equals(key)) {
                    continue;
                }
                if ((e[1] as Number) < current) {
                    Application.Storage.deleteValue(e[0] as String);
                } else {
                    kept.add(e);
                }
            }
        }
        Application.Storage.setValue("months", kept);
    }

    static function distanceKm(lat1, lon1, lat2, lon2) as Float {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dp = p2 - p1;
        var dl = Math.toRadians(lon2 - lon1);
        var a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return (6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).toFloat();
    }
}
