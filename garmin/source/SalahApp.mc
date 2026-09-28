import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SalahApp extends Application.AppBase {
    hidden var _sync as Sync?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _sync = new Sync();
        return [new PrayerView(_sync), new PrayerDelegate(_sync)];
    }

    (:glance)
    function getGlanceView() {
        return [new SalahGlanceView()];
    }

    // City or data URL changed in Garmin Connect.
    function onSettingsChanged() as Void {
        if (_sync != null) {
            _sync.chooseCity();
            _sync.status = null;
            _sync.start();
        }
        WatchUi.requestUpdate();
    }
}
