import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.SensorHistory;

class DoomGuyView extends WatchUi.WatchFace {

    private const BATT_WARN = 20;          // show charge reminder at/below this %

    private var _background as BitmapResource?;
    private var _face as BitmapResource?;
    private var _faceBucket as Number = -1;
    private var _faceIds as Array<ResourceId>;

    // Doom red numerals (native glyph height is 18px)
    private const GLYPH_H = 18;
    private var _digits as Array<BitmapResource>?;
    private var _colon as BitmapResource?;
    private var _pct as BitmapResource?;

    // Always-on (low-power) mode: clock text only, on black, for AMOLED burn-in safety
    private var _lowPower as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _faceIds = [
            Rez.Drawables.Face0,
            Rez.Drawables.Face20,
            Rez.Drawables.Face40,
            Rez.Drawables.Face60,
            Rez.Drawables.Face80,
            Rez.Drawables.Face100
        ];
    }

    function onLayout(dc as Dc) as Void {
        _background = WatchUi.loadResource(Rez.Drawables.Background) as BitmapResource;
        _digits = [
            WatchUi.loadResource(Rez.Drawables.D0) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D1) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D2) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D3) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D4) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D5) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D6) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D7) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D8) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.D9) as BitmapResource
        ];
        _colon = WatchUi.loadResource(Rez.Drawables.Colon) as BitmapResource;
        _pct = WatchUi.loadResource(Rez.Drawables.Pct) as BitmapResource;
    }

    function onShow() as Void {
    }

    // Current Body Battery (0-100), or -1 if unavailable.
    private function getBodyBattery() as Number {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var iter = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    return sample.data.toNumber();
                }
            }
        }
        return -1;
    }

    // Body Battery -> face bucket 0..5 (low == bloodied).
    private function bucketFor(pct as Number) as Number {
        var v = pct;
        if (v < 0) { v = 100; }   // unknown: show healthy
        var b = (v / 20.0 + 0.5).toNumber();
        if (b > 5) { b = 5; }
        if (b < 0) { b = 0; }
        return b;
    }

    // Scale-draw a bitmap with crisp nearest-neighbor filtering (keeps the pixel-art look).
    // Falls back to bilinear on any device without drawBitmap2.
    private function drawSprite(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                               bmp as BitmapResource) as Void {
        if (dc has :drawBitmap2) {
            var xf = new Graphics.AffineTransform();
            xf.scale(w.toFloat() / bmp.getWidth(), h.toFloat() / bmp.getHeight());
            dc.drawBitmap2(x, y, bmp, {
                :transform => xf,
                :filterMode => Graphics.FILTER_MODE_POINT
            });
        } else {
            dc.drawScaledBitmap(x, y, w, h, bmp);
        }
    }

    // Draw a sequence of glyph bitmaps centered at (cx, cy), scaled to targetH tall.
    private function drawGlyphs(dc as Dc, cx as Number, cy as Number, targetH as Number,
                               seq as Array<BitmapResource>) as Void {
        var s = targetH.toFloat() / GLYPH_H;
        var track = (s * 1.5).toNumber();

        var totalW = -track;
        for (var i = 0; i < seq.size(); i++) {
            totalW += (seq[i].getWidth() * s).toNumber() + track;
        }

        var x = cx - totalW / 2;
        var y = cy - targetH / 2;
        for (var i = 0; i < seq.size(); i++) {
            var g = seq[i];
            var gw = (g.getWidth() * s).toNumber();
            drawSprite(dc, x, y, gw, targetH, g);
            x += gw + track;
        }
    }

    // Append the decimal digits of n (>= 0) to seq using the Doom glyphs.
    private function appendNumber(seq as Array<BitmapResource>, n as Number) as Void {
        var digits = _digits;
        if (digits == null) { return; }
        if (n >= 10) { appendNumber(seq, n / 10); }
        seq.add(digits[n % 10]);
    }

    // Draw HH:MM centered at (cx, cy) using the red Doom glyphs.
    private function drawTime(dc as Dc, cx as Number, cy as Number, targetH as Number) as Void {
        var digits = _digits;
        var colon = _colon;
        if (digits == null || colon == null) { return; }

        var clock = System.getClockTime();
        var h = clock.hour;
        var m = clock.min;
        drawGlyphs(dc, cx, cy, targetH, [
            digits[h / 10],
            digits[h % 10],
            colon,
            digits[m / 10],
            digits[m % 10]
        ]);
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // Always-on / low-power: clock text only, on black (burn-in safe).
        // Nudge position by the minute so the lit pixels aren't always in the same spot.
        if (_lowPower) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            var min = System.getClockTime().min;
            var ox = (min % 7) - 3;
            var oy = ((min / 7) % 7) - 3;
            drawTime(dc, cx + ox, h / 2 + oy, (h * 0.15).toNumber());
            return;
        }

        // Background: Doom stone
        if (_background != null) {
            dc.drawScaledBitmap(0, 0, w, h, _background);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
        }

        // Body Battery drives the face
        var bb = getBodyBattery();
        var bucket = bucketFor(bb);
        if (bucket != _faceBucket || _face == null) {
            _faceBucket = bucket;
            _face = WatchUi.loadResource(_faceIds[bucket]) as BitmapResource;
        }

        // Face: big, upper area
        var face = _face;
        if (face != null) {
            var faceH = (h * 0.50).toNumber();
            var fs = faceH.toFloat() / face.getHeight();
            var faceW = (face.getWidth() * fs).toNumber();
            var faceCy = (h * 0.36).toNumber();
            drawSprite(dc, cx - faceW / 2, faceCy - faceH / 2, faceW, faceH, face);
        }

        // Time: red Doom numerals, below the face
        drawTime(dc, cx, (h * 0.77).toNumber(), (h * 0.18).toNumber());

        // Low-battery charge reminder: just the value, in the Doom font (only at/below threshold)
        var devBatt = System.getSystemStats().battery;
        if (devBatt <= BATT_WARN && _pct != null && _digits != null) {
            var seq = [] as Array<BitmapResource>;
            appendNumber(seq, devBatt.toNumber());
            seq.add(_pct);
            drawGlyphs(dc, cx, (h * 0.92).toNumber(), (h * 0.08).toNumber(), seq);
        }
    }

    function onHide() as Void {
    }

    // The user looked at the watch: return to the full face view.
    function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    // Entering low-power sleep: switch to the minimal always-on clock.
    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

}
