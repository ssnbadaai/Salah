import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Glance: city and the next prayer with a countdown, from cached data only.
(:glance)
class SalahGlanceView extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var h = dc.getHeight();
        var city = PrayerData.city();
        var next = city != null ? PrayerData.nextPrayer(city[0] as Number) : null;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 4, Graphics.FONT_XTINY,
            city != null ? "SALAH  " + (city[1] as String).toUpper() : "SALAH",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var line = next == null
            ? "Open to sync"
            : (PrayerData.NAMES[next[0] as Number] as String) + " " + PrayerData.formatTime(next[1] as Number)
                + "  in " + PrayerData.formatCountdown(next[2] as Number);
        dc.drawText(0, h * 2 / 3, Graphics.FONT_TINY, line,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
