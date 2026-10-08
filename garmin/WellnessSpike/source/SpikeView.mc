import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Five pages of plain text (Pages.mc): the live reading, the service's counters, its value
// lines, its fires per day and the foreground's own log. Wrapped by hand rather than with a
// TextArea so the layout does not depend on undocumented overflow behaviour.
class SpikeView extends WatchUi.View {
    private var _font as Graphics.FontType = Graphics.FONT_XTINY;
    private var _page as Number = 0;
    private var _scroll as Number = 0;
    private var _d as Dictionary? = null;
    private var _probe as String = "not run";
    private var _tNet as Number = 0;
    private var _cx as Number = 0;
    private var _hy as Number = 0;
    private var _bx as Number = 0;
    private var _by as Number = 0;
    private var _bw as Number = 100;
    private var _lh as Number = 1;
    private var _maxLines as Number = 1;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        _lh = dc.getFontHeight(_font);
        _cx = w / 2;
        if (System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND) {
            _hy = h * 7 / 100;
            _bx = w * 14 / 100;
            _by = h * 20 / 100;
            _bw = w * 72 / 100;
            _maxLines = (h * 62 / 100) / _lh;
        } else {
            _hy = 1;
            _bx = w * 3 / 100;
            _by = _lh + 3;
            _bw = w * 94 / 100;
            _maxLines = (h - _by - 2) / _lh;
        }
        if (_maxLines < 1) { _maxLines = 1; }
    }

    function onShow() as Void {
        if (_d == null) { refresh("O"); }
    }

    function pageIndex() as Number {
        return _page;
    }

    function turn(dir as Number) as Void {
        _page = (_page + dir + Pages.COUNT) % Pages.COUNT;
        _scroll = 0;
        WatchUi.requestUpdate();
    }

    function scroll(dir as Number) as Void {
        var n = Pages.entries(_page, _d, _probe).size();
        _scroll += dir;
        if (_scroll > n - 1) { _scroll = n - 1; }
        if (_scroll < 0) { _scroll = 0; }
        WatchUi.requestUpdate();
    }

    // A fresh foreground reading (logged to fgLog) and a fresh reachability probe.
    function refresh(tag as String) as Void {
        var d = {} as Dictionary;
        try {
            d = Reader.read();
        } catch (ex) {
            d["t"] = Time.now().value();
            d["err"] = "rd:" + Reader.clip(ex.getErrorMessage(), 14);
        }
        _d = d;
        Store.push("fgLog", Reader.line(tag, d, 0));
        _probe = "waiting";
        _tNet = System.getTimer();
        try {
            Net.probe(method(:onProbe));
        } catch (ex) {
            _probe = "!" + Reader.clip(ex.getErrorMessage(), 14);
        }
        WatchUi.requestUpdate();
    }

    function onProbe(code as Number, data as Dictionary or String or Null) as Void {
        var ms = System.getTimer() - _tNet;
        _probe = code.toString() + "  " + ms.toString() + " ms";
        var st = Store.stats("fgSt");
        st["fcode"] = code;
        st["flat"] = ms;
        if (Net.answered(code)) {
            st["fOk"] = Store.cnt(st, "fOk") + 1;
        } else {
            st["fFail"] = Store.cnt(st, "fFail") + 1;
        }
        Store.save("fgSt", st);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var all = Pages.entries(_page, _d, _probe);
        var n = all.size();
        if (_scroll > n - 1) { _scroll = n - 1; }
        if (_scroll < 0) { _scroll = 0; }
        var head = Pages.NAMES[_page] + " " + (_page + 1) + "/" + Pages.COUNT;
        if (n > 1) { head += "  " + (_scroll + 1) + "/" + n; }
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _hy, _font, head, Graphics.TEXT_JUSTIFY_CENTER);
        var y = _by;
        var drawn = 0;
        for (var i = _scroll; i < n && drawn < _maxLines; i++) {
            var ls = wrap(dc, all[i], _maxLines - drawn);
            for (var j = 0; j < ls.size(); j++) {
                dc.setColor((j == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_bx, y, _font, ls[j], Graphics.TEXT_JUSTIFY_LEFT);
                y += _lh;
                drawn++;
            }
        }
    }

    // Greedy word wrap of one entry to the body width, at most `max` lines. A single word wider
    // than the body is cut rather than wrapped.
    private function wrap(dc as Graphics.Dc, text as String, max as Number) as Array<String> {
        var out = [] as Array<String>;
        var chars = text.toCharArray();
        var line = "";
        var word = "";
        for (var i = 0; i <= chars.size(); i++) {
            var ch = (i < chars.size()) ? chars[i] : ' ';
            if (ch != ' ') {
                word += ch.toString();
                continue;
            }
            if (word.length() == 0) { continue; }
            while (word.length() > 1 && dc.getTextWidthInPixels(word, _font) > _bw) {
                word = word.substring(0, word.length() - 1) as String;
            }
            var cand = (line.length() == 0) ? word : (line + " " + word);
            if (dc.getTextWidthInPixels(cand, _font) <= _bw) {
                line = cand;
            } else {
                if (line.length() > 0) {
                    out.add(line);
                    if (out.size() >= max) { return out; }
                }
                line = word;
            }
            word = "";
        }
        if (line.length() > 0 && out.size() < max) { out.add(line); }
        return out;
    }
}
