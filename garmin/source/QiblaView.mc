import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.Timer;
import Toybox.WatchUi;

// Compass that points to the Kaaba from the watch's GPS position. The rose
// turns with the watch's compass heading, so the green/gold arrow always
// points at the Qibla; the top index marks the direction the watch faces.
class QiblaView extends WatchUi.View {
    const KAABA_LAT = 21.422487;
    const KAABA_LON = 39.826206;
    const ALIGNED_DEG = 5;

    hidden var _sync as Sync;
    hidden var _timer as Timer.Timer?;
    hidden var _sx as Float? = null; // smoothed heading as a unit vector
    hidden var _sy as Float? = null;
    hidden var _aligned as Boolean = false;

    function initialize(sync as Sync) {
        View.initialize();
        _sync = sync;
    }

    function onShow() as Void {
        _sync.start();
        Sensor.enableSensorEvents(method(:onSensor));
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 100, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        Sensor.enableSensorEvents(null);
        _sync.stop();
    }

    function onSensor(info as Sensor.Info) as Void {
        addHeading(info.heading);
    }

    // The sensor callback only fires once a second; poll for a smoother needle.
    function onTick() as Void {
        addHeading(Sensor.getInfo().heading);
        WatchUi.requestUpdate();
    }

    hidden function addHeading(heading as Float?) as Void {
        if (heading == null) {
            return;
        }
        var x = Math.sin(heading).toFloat();
        var y = Math.cos(heading).toFloat();
        if (_sx == null) {
            _sx = x;
            _sy = y;
        } else {
            _sx = _sx * 0.6 + x * 0.4;
            _sy = _sy * 0.6 + y * 0.4;
        }
    }

    // Great-circle initial bearing to the Kaaba, degrees clockwise from true north.
    hidden function qiblaBearing(lat as Float, lon as Float) as Float {
        var p1 = Math.toRadians(lat);
        var p2 = Math.toRadians(KAABA_LAT);
        var dl = Math.toRadians(KAABA_LON - lon);
        var y = Math.sin(dl) * Math.cos(p2);
        var x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        var b = Math.toDegrees(Math.atan2(y, x)).toFloat();
        return b < 0 ? b + 360 : b;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (w < h ? w : h) / 2 - 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        if (_sync.lat == null) {
            message(dc, "Finding location...");
            return;
        }
        if (_sx == null) {
            message(dc, "Compass unavailable");
            return;
        }

        var lat = _sync.lat as Float;
        var lon = _sync.lon as Float;
        var heading = Math.toDegrees(Math.atan2(_sx as Float, _sy as Float)).toFloat();
        var qibla = qiblaBearing(lat, lon);
        // Angle of the Qibla relative to where the watch points, -180..180.
        var rel = qibla - heading;
        while (rel > 180) { rel -= 360; }
        while (rel < -180) { rel += 360; }
        var aligned = rel.abs() <= ALIGNED_DEG;
        if (aligned && !_aligned && Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 250)]);
        }
        _aligned = aligned;

        // Rose: ticks every 10 degrees, cardinal letters, north in red.
        for (var d = 0; d < 360; d += 10) {
            var a = Math.toRadians(d - heading);
            var inner = d % 90 == 0 ? r * 0.86 : (d % 30 == 0 ? r * 0.90 : r * 0.94);
            dc.setColor(d == 0 ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(d % 30 == 0 ? 3 : 1);
            dc.drawLine(cx + inner * Math.sin(a), cy - inner * Math.cos(a), cx + r * Math.sin(a), cy - r * Math.cos(a));
        }
        dc.setPenWidth(1);
        var letters = ["N", "E", "S", "W"];
        for (var i = 0; i < 4; i++) {
            var a = Math.toRadians(i * 90 - heading);
            dc.setColor(i == 0 ? Graphics.COLOR_RED : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + r * 0.74 * Math.sin(a), cy - r * 0.74 * Math.cos(a), Graphics.FONT_XTINY, letters[i] as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Qibla arrow and Kaaba marker on the rim.
        var qa = Math.toRadians(rel);
        var color = aligned ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            point(cx, cy, qa, -r * 0.03, r * 0.32), point(cx, cy, qa, r * 0.03, r * 0.32),
            point(cx, cy, qa, r * 0.03, r * 0.48), point(cx, cy, qa, r * 0.10, r * 0.48),
            point(cx, cy, qa, 0, r * 0.64),
            point(cx, cy, qa, -r * 0.10, r * 0.48), point(cx, cy, qa, -r * 0.03, r * 0.48)
        ]);
        drawKaaba(dc, cx + r * 0.88 * Math.sin(qa), cy - r * 0.88 * Math.cos(qa), (r * 0.09).toNumber());

        // Fixed index: the direction the watch (12 o'clock) is facing.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - 8, 1], [cx + 8, 1], [cx, 15]]);

        // Qibla bearing in the centre; distance to Makkah beneath it.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_SMALL, qibla.toNumber() + "°",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var km = Sync.distanceKm(lat, lon, KAABA_LAT, KAABA_LON).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + r * 0.47, Graphics.FONT_XTINY, aligned ? "QIBLA" : km + " km",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Point at distance `along` in direction `angle` (radians clockwise from
    // up), offset `across` perpendicular to it.
    hidden function point(cx, cy, angle, across, along) as Array {
        var s = Math.sin(angle);
        var c = Math.cos(angle);
        return [cx + along * s + across * c, cy - along * c + across * s];
    }

    hidden function drawKaaba(dc as Graphics.Dc, x, y, half as Number) as Void {
        var x0 = (x - half).toNumber();
        var y0 = (y - half).toNumber();
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x0, y0, half * 2, half * 2);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x0, y0 + half / 2, half * 2, half / 3 + 1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x0, y0, half * 2, half * 2);
    }

    hidden function message(dc as Graphics.Dc, text as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class QiblaDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onPreviousPage() as Boolean {
        return onBack();
    }
}
