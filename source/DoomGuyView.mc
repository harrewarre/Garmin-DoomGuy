import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.SensorHistory;
import Toybox.ActivityMonitor;
import Toybox.Math;

class DoomGuyView extends WatchUi.WatchFace {

    private const BATT_WARN = 20;          // show charge reminder at/below this %

    private var _background as BitmapResource?;
    private var _hudBg as BitmapResource?;
    private var _lastBB as Number = -1;    // last successfully read Body Battery

    // Per tier: a forward-facing default face, plus a set of "variation" faces
    // (2 side glances + 3 mood expressions) shown only ~1 in VARY_ONE_IN wakes.
    private const VARY_ONE_IN = 8;
    private var _front as Array<ResourceId>;
    private var _vary as Array<Array<ResourceId> >;
    private var _god as ResourceId;
    private var _dead as ResourceId;
    private var _wakeFace as BitmapResource?;
    private var _reroll as Boolean = true;

    // Doom red numerals (native glyph height is 18px)
    private const GLYPH_H = 18;
    private var _digits as Array<BitmapResource>?;
    private var _colon as BitmapResource?;
    private var _pct as BitmapResource?;

    // HUD (yellow small Doom font): 3 stat labels + digits 0-9
    private var _labels as Array<BitmapResource>?;   // [RCRY, STRS, STPS]
    private var _hy as Array<BitmapResource>?;        // yellow digits

    // Always-on (low-power) mode: clock text only, on black, for AMOLED burn-in safety
    private var _lowPower as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        // Forward-facing default per tier (the centered stern glance, col 1)
        _front = [
            Rez.Drawables.Fs01, Rez.Drawables.Fs11, Rez.Drawables.Fs21,
            Rez.Drawables.Fs31, Rez.Drawables.Fs41
        ];
        // Variations per tier: 2 side glances + 3 mood expressions
        _vary = [
            [Rez.Drawables.Fs00, Rez.Drawables.Fs02,
             Rez.Drawables.Fm00, Rez.Drawables.Fm10, Rez.Drawables.Fm20],
            [Rez.Drawables.Fs10, Rez.Drawables.Fs12,
             Rez.Drawables.Fm01, Rez.Drawables.Fm11, Rez.Drawables.Fm21],
            [Rez.Drawables.Fs20, Rez.Drawables.Fs22,
             Rez.Drawables.Fm02, Rez.Drawables.Fm12, Rez.Drawables.Fm22],
            [Rez.Drawables.Fs30, Rez.Drawables.Fs32,
             Rez.Drawables.Fm03, Rez.Drawables.Fm13, Rez.Drawables.Fm23],
            [Rez.Drawables.Fs40, Rez.Drawables.Fs42,
             Rez.Drawables.Fm04, Rez.Drawables.Fm14, Rez.Drawables.Fm24]
        ];
        _god = Rez.Drawables.Fgod;
        _dead = Rez.Drawables.Fdead;
    }

    function onLayout(dc as Dc) as Void {
        _background = WatchUi.loadResource(Rez.Drawables.Background) as BitmapResource;
        _hudBg = WatchUi.loadResource(Rez.Drawables.HudBg) as BitmapResource;
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
        _labels = [
            WatchUi.loadResource(Rez.Drawables.Hrcry) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hstrs) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hstps) as BitmapResource
        ];
        _hy = [
            WatchUi.loadResource(Rez.Drawables.Hy0) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy1) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy2) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy3) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy4) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy5) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy6) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy7) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy8) as BitmapResource,
            WatchUi.loadResource(Rez.Drawables.Hy9) as BitmapResource
        ];
    }

    function onShow() as Void {
    }

    // Current Body Battery (0-100). On a failed/empty read (common right at
    // wrist-raise) returns the last known value; -1 only before the first
    // successful read.
    private function getBodyBattery() as Number {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var iter = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var sample = iter.next();
                if (sample != null && sample.data != null) {
                    _lastBB = sample.data.toNumber();
                    return _lastBB;
                }
            }
        }
        // Reuse last known instead of falsely flashing full health.
        return _lastBB;
    }

    // Body Battery -> health tier 0 (healthy) .. 4 (bloodied). Doom-style 20% bands.
    private function tierFor(bb as Number) as Number {
        if (bb < 0) { return 2; }   // never read yet: neutral mid tier
        var t = 4 - bb / 20;
        if (t < 0) { t = 0; }
        if (t > 4) { t = 4; }
        return t;
    }

    // Choose the face to show for this wake: godmode on the charger or at peak
    // Body Battery (>=95, rare), the dead face when nearly empty, otherwise a
    // random glance/mood for the current tier.
    private function chooseFace() as Void {
        var id = _god;
        if (!System.getSystemStats().charging) {
            var bb = getBodyBattery();
            if (bb >= 95) {
                id = _god;                   // peak Body Battery: invulnerable (rare)
            } else if (bb >= 0 && bb <= 5) {
                id = _dead;
            } else {
                var t = tierFor(bb);
                if (Math.rand() % VARY_ONE_IN == 0) {
                    var v = _vary[t];
                    id = v[Math.rand() % v.size()];   // occasional glance/mood
                } else {
                    id = _front[t];                    // usual forward face
                }
            }
        }
        _wakeFace = WatchUi.loadResource(id) as BitmapResource;
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

    // Current stress 0-100: prefer ActivityMonitor.stressScore (API 5), else
    // the newest SensorHistory stress sample, else -1 (unknown).
    private function getStress(info as ActivityMonitor.Info) as Number {
        if (info has :stressScore && info.stressScore != null) {
            return info.stressScore;
        }
        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var iter = SensorHistory.getStressHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            if (iter != null) {
                var s = iter.next();
                if (s != null && s.data != null) { return s.data.toNumber(); }
            }
        }
        return -1;
    }

    // Map a non-negative number to yellow HUD digit bitmaps.
    private function hudDigits(n as Number) as Array<BitmapResource> {
        var hy = _hy;
        var out = [] as Array<BitmapResource>;
        if (hy == null) { return out; }
        if (n <= 0) { return [hy[0]]; }
        var stack = [] as Array<Number>;
        while (n > 0) { stack.add(n % 10); n = n / 10; }
        for (var i = stack.size() - 1; i >= 0; i--) { out.add(hy[stack[i]]); }
        return out;
    }

    // Draw a run of HUD glyph bitmaps left-aligned from xLeft, vertically centred
    // on cy, scaled to targetH tall.
    private function drawHudText(dc as Dc, xLeft as Number, cy as Number, targetH as Number,
                                bmps as Array<BitmapResource>) as Void {
        if (bmps.size() == 0) { return; }
        var gap = (targetH * 0.14).toNumber();
        if (gap < 1) { gap = 1; }
        var x = xLeft;
        var y = cy - targetH / 2;
        for (var i = 0; i < bmps.size(); i++) {
            var b = bmps[i];
            var gw = b.getWidth() * targetH / b.getHeight();
            drawSprite(dc, x, y, gw, targetH, b);
            x += gw + gap;
        }
    }

    // Doom-HUD panel on the right: RCRY (recovery hrs), STRS (stress), STPS (steps).
    private function drawHud(dc as Dc, w as Number, h as Number) as Void {
        var labels = _labels;
        if (labels == null) { return; }
        var info = ActivityMonitor.getInfo();

        var recovery = 0;
        if (info has :timeToRecovery && info.timeToRecovery != null) {
            recovery = info.timeToRecovery;
        }
        var stress = getStress(info);
        if (stress < 0) { stress = 0; }
        var steps = 0;
        if (info.steps != null) { steps = info.steps; }
        var vals = [recovery, stress, steps];

        // HUD texture anchored to the top-right: it bleeds off the top and right
        // edges so it reads as a fixed section rather than a floating card.
        var pLeft = (w * 0.58).toNumber();
        var pBottom = (h * 0.66).toNumber();
        var pw = w - pLeft;
        if (_hudBg != null) {
            dc.drawScaledBitmap(pLeft, 0, pw, pBottom, _hudBg);
        } else {
            dc.setColor(0x2A2A26, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(pLeft, 0, pw, pBottom);
        }
        // Dark bevel on the two visible (inner) edges
        dc.setColor(0x14140F, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(pLeft, 0, pLeft, pBottom);
        dc.drawLine(pLeft, pBottom, w, pBottom);
        dc.setPenWidth(1);

        // Stat rows, left-aligned. Bottom-anchor the block so the gap below the last
        // counter matches the gap to the left of the labels (pad), for consistency.
        var pad = (pw * 0.12).toNumber();
        var textLeft = pLeft + pad;
        var rowH = (h * 0.17).toNumber();
        var labelH = (rowH * 0.34).toNumber();
        var valueH = (rowH * 0.46).toNumber();
        var vOff = (rowH * 0.20).toNumber();
        var blockCy = pBottom - pad - valueH / 2 - vOff - rowH;
        for (var i = 0; i < 3; i++) {
            var rcy = blockCy + (i - 1) * rowH;
            drawHudText(dc, textLeft, rcy - vOff, labelH, [labels[i]]);
            drawHudText(dc, textLeft, rcy + vOff, valueH, hudDigits(vals[i]));
        }
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

        // Body Battery drives the face; a fresh glance/mood is picked on each wake.
        if (_reroll || _wakeFace == null) {
            chooseFace();
            _reroll = false;
        }

        // Face: the hero, shifted left to make room for the HUD
        var face = _wakeFace;
        if (face != null) {
            var faceH = (h * 0.46).toNumber();
            var fs = faceH.toFloat() / face.getHeight();
            var faceW = (face.getWidth() * fs).toNumber();
            var faceCx = (w * 0.32).toNumber();
            var faceCy = (h * 0.42).toNumber();
            drawSprite(dc, faceCx - faceW / 2, faceCy - faceH / 2, faceW, faceH, face);
        }

        // HUD panel (recovery / stress / steps) on the right
        drawHud(dc, w, h);

        // Time: red Doom numerals, along the bottom
        drawTime(dc, cx, (h * 0.82).toNumber(), (h * 0.14).toNumber());

        // Low-battery charge reminder: just the value, in the Doom font (only at/below threshold)
        var devBatt = System.getSystemStats().battery;
        if (devBatt <= BATT_WARN && _pct != null && _digits != null) {
            var seq = [] as Array<BitmapResource>;
            appendNumber(seq, devBatt.toNumber());
            seq.add(_pct);
            drawGlyphs(dc, cx, (h * 0.93).toNumber(), (h * 0.06).toNumber(), seq);
        }
    }

    function onHide() as Void {
    }

    // The user looked at the watch: return to the full face view.
    function onExitSleep() as Void {
        _lowPower = false;
        _reroll = true;      // glance a fresh face next draw
        WatchUi.requestUpdate();
    }

    // Entering low-power sleep: switch to the minimal always-on clock.
    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

}
