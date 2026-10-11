using Toybox.Graphics as Gfx;

// Canonical palette, ported verbatim from the web app's
// frontend/src/lib/modalityColors.ts and frontend/src/lib/hrZones.ts.
//
// Those hex values are already mirrored into ios/TrainingCompanion/ModalityStyle.swift
// and the watchOS copy; this is the fourth mirror. Changing a modality hex is a
// four-file commit — nothing enforces it at build time.
//
// Everything here is a `const` or a pure function returning a Number. There are
// deliberately no Dictionary literals: a 12-entry Dictionary costs ~1 KB of heap
// and would be rebuilt on every initialize(), whereas an if-chain costs nothing.
module Theme {

    // ── surfaces ────────────────────────────────────────────────────────────────
    const BG        = 0x000000;   // AMOLED true black — luminance is power
    const TEXT      = 0xFFFFFF;
    const TEXT_DIM  = 0x9AA0A6;
    const TEXT_HINT = 0x5F6368;
    const TRACK     = 0x2A2A2E;   // neutral ring track where no accent applies

    // ── modality accents (frontend/src/lib/modalityColors.ts) ───────────────────
    const MAX_STRENGTH       = 0xEF4444;   // red-500
    const STRENGTH_ENDURANCE = 0xF97316;   // orange-500
    const RELATIVE_STRENGTH  = 0xF43F5E;   // rose-500
    const AEROBIC_BASE       = 0x0EA5E9;   // sky-500
    const ANAEROBIC          = 0x06B6D4;   // cyan-500
    const MIXED_MODAL        = 0x8B5CF6;   // violet-500
    const POWER              = 0xEAB308;   // yellow-500
    const MOBILITY           = 0x10B981;   // emerald-500
    const MOVEMENT_SKILL     = 0x14B8A6;   // teal-500
    const DURABILITY         = 0xF59E0B;   // amber-500
    const COMBAT_SPORT       = 0xEC4899;   // pink-500
    const REHAB              = 0x84CC16;   // lime-500

    // ── HR zones (frontend/src/lib/hrZones.ts), 1-indexed via zoneColor() ───────
    const Z1 = 0x94A3B8;
    const Z2 = 0x38BDF8;
    const Z3 = 0xFBBF24;
    const Z4 = 0xF97316;
    const Z5 = 0xEF4444;

    // ── readiness ───────────────────────────────────────────────────────────────
    const READY_GREEN  = 0x10B981;
    const READY_YELLOW = 0xEAB308;
    const READY_RED    = 0xEF4444;

    // Accent for a modality id. Falls back to a neutral grey for ids we don't know
    // (a new modality shipped server-side should degrade, not crash).
    function accent(modalityId) {
        if (modalityId == null) { return TEXT_DIM; }
        if (modalityId.equals("max_strength"))             { return MAX_STRENGTH; }
        if (modalityId.equals("strength_endurance"))       { return STRENGTH_ENDURANCE; }
        if (modalityId.equals("relative_strength"))        { return RELATIVE_STRENGTH; }
        if (modalityId.equals("aerobic_base"))             { return AEROBIC_BASE; }
        if (modalityId.equals("anaerobic_intervals"))      { return ANAEROBIC; }
        if (modalityId.equals("mixed_modal_conditioning")) { return MIXED_MODAL; }
        if (modalityId.equals("power"))                    { return POWER; }
        if (modalityId.equals("mobility"))                 { return MOBILITY; }
        if (modalityId.equals("movement_skill"))           { return MOVEMENT_SKILL; }
        if (modalityId.equals("durability"))               { return DURABILITY; }
        if (modalityId.equals("combat_sport"))             { return COMBAT_SPORT; }
        if (modalityId.equals("rehab"))                    { return REHAB; }
        return TEXT_DIM;
    }

    // HR zone colour for a 1-indexed zone number.
    function zoneColor(z) {
        if (z == null) { return TEXT_DIM; }
        if (z <= 1) { return Z1; }
        if (z == 2) { return Z2; }
        if (z == 3) { return Z3; }
        if (z == 4) { return Z4; }
        return Z5;
    }

    function readiness(status) {
        if (status == null) { return TEXT_HINT; }
        if (status.equals("green"))  { return READY_GREEN; }
        if (status.equals("yellow")) { return READY_YELLOW; }
        if (status.equals("red"))    { return READY_RED; }
        return TEXT_HINT;
    }

    // Scale a colour toward black by pct (0-100).
    //
    // Used instead of an alpha fill for ring tracks and de-emphasised marks.
    // setStroke()/setFill() take 32-bit AARRGGBB but they are STICKY and take
    // precedence over setColor() until reset — easy to leave the Dc in a state
    // that silently ignores later setColor calls. On a pure-black ground a
    // pre-multiplied solid is pixel-identical to the alpha blend, so this
    // sidesteps the state machine entirely.
    function dimmed(color, pct) {
        var r = ((color >> 16) & 0xFF) * pct / 100;
        var g = ((color >> 8)  & 0xFF) * pct / 100;
        var b = ( color        & 0xFF) * pct / 100;
        return (r << 16) | (g << 8) | b;
    }

    // Linear blend a -> b, f in [0.0, 1.0]. Drives the HR-zone crossfade.
    function lerpColor(a, b, f) {
        if (f <= 0.0) { return a; }
        if (f >= 1.0) { return b; }
        var ar = (a >> 16) & 0xFF; var ag = (a >> 8) & 0xFF; var ab = a & 0xFF;
        var br = (b >> 16) & 0xFF; var bg = (b >> 8) & 0xFF; var bb = b & 0xFF;
        var r = (ar + ((br - ar) * f)).toNumber();
        var g = (ag + ((bg - ag) * f)).toNumber();
        var bl = (ab + ((bb - ab) * f)).toNumber();
        return (r << 16) | (g << 8) | bl;
    }
}
