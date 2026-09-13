using Toybox.Application;

// Central constants + storage keys. Mirrors the iOS app's UserDefaults keys where
// it helps keep the two companions conceptually aligned.
module Config {
    // Must match src/device_store.py TOKEN_PREFIX and the backend routes.
    const TOKEN_PREFIX = "ciqdev_";

    // Storage keys (Application.Storage).
    const KEY_DEVICE_TOKEN   = "deviceToken";
    const KEY_CLAIMED        = "claimed";
    const KEY_TODAY_SESSION  = "todaySession";   // cached today-session JSON dict
    const KEY_TODAY_DATE     = "todaySessionDate";
    const KEY_UPLOAD_BUFFER  = "uploadBuffer";    // array of pending upload dicts

    // Poll cadence for pairing status (ms).
    const PAIR_POLL_MS = 3000;

    // Seconds between captured GPS track points during cardio sessions.
    const GPS_STRIDE_SEC = 5;

    // Consecutive seconds outside the prescribed HR zone before a drift alert fires.
    const HR_DRIFT_HOLD_SEC = 15;

    // Default per-modality rest seconds — mirrors ios/.../WatchSessionManager.swift
    // modalityRestDefaults, used only when the backend omits a value.
    function defaultRestSec(modality) {
        var m = {
            "max_strength" => 240, "relative_strength" => 180, "strength_endurance" => 90,
            "power" => 240, "aerobic_base" => 0, "anaerobic_intervals" => 120,
            "mixed_modal_conditioning" => 60, "mobility" => 30, "movement_skill" => 30,
            "durability" => 0, "combat_sport" => 0, "rehab" => 30
        };
        return m.hasKey(modality) ? m[modality] : 60;
    }

    function apiBaseUrl() {
        var url = Application.Properties.getValue("apiBaseUrl");
        if (url == null || url.length() == 0) {
            return "https://training-api.fly.dev/api";
        }
        return url;
    }

    // Value encoded in the pairing QR. When a web base URL is configured we build a
    // deep link that opens the claim page with the code prefilled; otherwise we
    // encode the raw code (still scannable, just not a one-tap link).
    function pairQrValue(code) {
        var web = Application.Properties.getValue("webBaseUrl");
        if (web != null && web.length() > 0) {
            return web + "/pair?code=" + code;
        }
        return code;
    }
}
