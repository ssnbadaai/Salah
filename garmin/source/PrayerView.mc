import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Today's MARA timetable with the next prayer highlighted and a countdown.
class PrayerView extends WatchUi.View {
    hidden var _sync as Sync;
    hidden var _timer as Timer.Timer?;

    function initialize(sync as Sync) {
        View.initialize();
        _sync = sync;
    }

    function onShow() as Void {
        _sync.start();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 10000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        _sync.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var label = _sync.cityName;
        if (_sync.cityDistKm > 50) {
            label += " (" + _sync.cityDistKm + " km)";
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 9 / 100, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var today = PrayerData.dayTimes(_sync.cityId, PrayerData.omanInfo(0));
        if (today == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL,
                _sync.status != null ? _sync.status as String : "No data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 66 / 100, Graphics.FONT_XTINY, "Start: Qibla",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var next = PrayerData.nextPrayer(_sync.cityId) as Array;
        var nextIdx = next[0] as Number;
        var tomorrow = next[3] as Boolean; // after Isha: every row today is past

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 18 / 100, Graphics.FONT_XTINY, (PrayerData.NAMES[nextIdx] as String).toUpper() + " IN",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 28 / 100, Graphics.FONT_MEDIUM, PrayerData.formatCountdown(next[2] as Number),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Six rows: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha
        var top = h * 39 / 100;
        var rowH = (h * 92 / 100 - top) / 6;
        var font = dc.getFontHeight(Graphics.FONT_TINY) <= rowH ? Graphics.FONT_TINY : Graphics.FONT_XTINY;
        var left = w * 23 / 100;
        var right = w * 77 / 100;
        for (var i = 0; i < 6; i++) {
            var y = top + rowH * i + rowH / 2;
            var isNext = i == nextIdx && !tomorrow;
            if (isNext) {
                dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(w * 18 / 100, y - rowH / 2 + 1, w * 64 / 100, rowH - 2, rowH / 3);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            } else if (i == PrayerData.SUNRISE || tomorrow || (today[i] as Number) < (next[1] as Number)) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(left, y, font, PrayerData.NAMES[i] as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(right, y, font, PrayerData.formatTime(today[i] as Number),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}

class PrayerDelegate extends WatchUi.BehaviorDelegate {
    hidden var _sync as Sync;

    function initialize(sync as Sync) {
        BehaviorDelegate.initialize();
        _sync = sync;
    }

    // START (or tap / down) opens the Qibla compass.
    function onSelect() as Boolean {
        WatchUi.pushView(new QiblaView(_sync), new QiblaDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    function onNextPage() as Boolean {
        return onSelect();
    }
}
