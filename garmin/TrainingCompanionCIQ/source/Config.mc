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
}
