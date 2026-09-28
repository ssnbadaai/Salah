import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.StringUtil;
import Toybox.WatchUi;

// Location, city selection and the yearly download of MARA timetables for all
// cities (via the phone). Cities come in chunks of CHUNK per request; see
// server/build_site.py.
class Sync {
    const CHUNK = 12; // cities per download; must match server/build_site.py

    var lat as Float? = null;       // degrees, last known position
    var lon as Float? = null;
    var cityId as Number = 0;
    var cityName as String = "Muscat";
    var cityDistKm as Number = -1;  // -1 when the city was chosen without GPS
    var status as String? = null;   // shown when today's times aren't downloaded

    hidden var _chunks as Number = 1;
    hidden var _busy as Boolean = false;
    hidden var _stopped as Boolean = false; // a download failed; retry next time a view opens

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
        _stopped = false;
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
            if ((c[0] as Number) / CHUNK >= _chunks) {
                _chunks = (c[0] as Number) / CHUNK + 1;
            }
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

    // Download this year for every city if anything is missing, and next
    // year during December. Runs one chunk at a time until all are stored.
    function ensureData() as Void {
        var t = PrayerData.omanInfo(0);
        var year = t.year as Number;
        dropYear(year - 1);
        if (_busy || _stopped) {
            return;
        }
        var chunk = missingChunk(year);
        if (chunk < 0 && (t.month as Number) == 12) {
            year += 1;
            chunk = missingChunk(year);
        }
        if (chunk < 0) {
            status = null;
            return;
        }
        request(year, chunk);
    }

    // First chunk of `year` not yet stored, starting with the current city's; -1 if none.
    hidden function missingChunk(year as Number) as Number {
        var done = Application.Storage.getValue("c" + year) as Array?;
        var own = cityId / CHUNK;
        if (done == null || done.indexOf(own) < 0) {
            return own;
        }
        for (var i = 0; i < _chunks; i++) {
            if (done.indexOf(i) < 0) {
                return i;
            }
        }
        return -1;
    }

    hidden function request(year as Number, chunk as Number) as Void {
        _busy = true;
        if (PrayerData.dayTimes(cityId, PrayerData.omanInfo(0)) == null) {
            var done = Application.Storage.getValue("c" + year) as Array?;
            status = "Downloading " + (done == null ? 1 : done.size() + 1) + "/" + _chunks;
        }
        var base = Application.Properties.getValue("dataUrl") as String;
        while (base.length() > 0 && base.substring(base.length() - 1, base.length()).equals("/")) {
            base = base.substring(0, base.length() - 1);
        }
        Communications.makeWebRequest(base + "/v2/" + year + "/" + chunk + ".json", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :context => [year, chunk]
        }, method(:onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or PersistedContent.Iterator or Null, context as Object) as Void {
        _busy = false;
        var year = (context as Array)[0] as Number;
        var chunk = (context as Array)[1] as Number;
        var error = null;
        if (code == 200 && data instanceof Dictionary && data["cities"] instanceof Array) {
            var cities = data["cities"] as Array;
            try {
                for (var i = 0; i < cities.size(); i++) {
                    var entry = cities[i] as Array;
                    var bytes = StringUtil.convertEncodedString(entry[1] as String, {
                        :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                        :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
                    });
                    Application.Storage.setValue(PrayerData.yearKey(year, entry[0] as Number), bytes as ByteArray);
                }
                var done = Application.Storage.getValue("c" + year) as Array?;
                done = done == null ? [chunk] : done.add(chunk);
                Application.Storage.setValue("c" + year, done);
            } catch (ex) {
                error = "Watch storage full";
            }
        } else if (code == Communications.BLE_CONNECTION_UNAVAILABLE) {
            error = "Phone not connected";
        } else {
            error = "Download failed (" + code + ")";
        }
        if (error != null) {
            _stopped = true;
            if (PrayerData.dayTimes(cityId, PrayerData.omanInfo(0)) == null) {
                status = error;
            }
        } else {
            ensureData(); // next chunk
        }
        WatchUi.requestUpdate();
    }

    // Delete a past year's data once the new year has started.
    hidden function dropYear(year as Number) as Void {
        if (Application.Storage.getValue("c" + year) == null) {
            return;
        }
        for (var id = 0; id < _chunks * CHUNK; id++) {
            Application.Storage.deleteValue(PrayerData.yearKey(year, id));
        }
        Application.Storage.deleteValue("c" + year);
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
