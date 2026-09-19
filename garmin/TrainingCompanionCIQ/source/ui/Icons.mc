using Toybox.Application;
using Toybox.Graphics as Gfx;
using Toybox.Lang;

// Icon lookup, caching and tinted drawing.
//
// Assets are pure-white-on-transparent SVGs (see tools/gen_icons.py), recoloured
// at runtime with drawBitmap2(:tintColor), so ONE asset serves all twelve modality
// accents instead of 46 x 12 baked variants.
//
// Memory: Application.loadResource() on a bitmap returns a BitmapReference whose
// pixels live in the 3 MB GRAPHICS POOL, not the 768 KB app heap. The reference
// is passed straight to drawBitmap2 — we deliberately never call .get(), which
// would PIN the resource in the pool and is the usual cause of pool thrash. And
// because these are static resources, a pool purge is transparent: the system
// reloads them from the PRG (unlike a BufferedBitmap, which is not restored).
//
// The cache is a small round-robin, not a true LRU — with 8 slots and at most a
// few icons on screen at once the distinction does not pay for itself.
module Icons {

    const CACHE_N = 8;
    var _key = new [CACHE_N];
    var _ref = new [CACHE_N];
    var _next = 0;

    // Movement pattern -> hero icon. This is the "down to each exercise" layer:
    // every exercise in the corpus carries movement_patterns, and all 18 distinct
    // values in the data map here.
    function patternKey(p) {
        if (p == null) { return null; }
        if (p.equals("squat"))                  { return Rez.Drawables.IcSquat; }
        if (p.equals("hip_hinge"))              { return Rez.Drawables.IcHipHinge; }
        if (p.equals("vertical_push"))          { return Rez.Drawables.IcVerticalPush; }
        if (p.equals("horizontal_push"))        { return Rez.Drawables.IcHorizontalPush; }
        if (p.equals("vertical_pull"))          { return Rez.Drawables.IcVerticalPull; }
        if (p.equals("horizontal_pull"))        { return Rez.Drawables.IcHorizontalPull; }
        if (p.equals("loaded_carry"))           { return Rez.Drawables.IcLoadedCarry; }
        if (p.equals("farmer_carry"))           { return Rez.Drawables.IcFarmerCarry; }
        if (p.equals("rack_carry"))             { return Rez.Drawables.IcRackCarry; }
        if (p.equals("rotation"))               { return Rez.Drawables.IcRotation; }
        if (p.equals("locomotion"))             { return Rez.Drawables.IcLocomotion; }
        if (p.equals("ballistic"))              { return Rez.Drawables.IcBallistic; }
        if (p.equals("olympic_lift"))           { return Rez.Drawables.IcOlympicLift; }
        if (p.equals("isometric"))              { return Rez.Drawables.IcIsometric; }
        if (p.equals("aerobic_monostructural")) { return Rez.Drawables.IcAerobicMonostructural; }
        if (p.equals("hip_flexion"))            { return Rez.Drawables.IcHipFlexion; }
        if (p.equals("knee_extension"))         { return Rez.Drawables.IcKneeExtension; }
        if (p.equals("step_up"))                { return Rez.Drawables.IcStepUp; }
        return null;
    }

    function slotKey(s) {
        if (s == null) { return Rez.Drawables.IcUiGeneric; }
        if (s.equals("sets_reps"))       { return Rez.Drawables.IcSlotSetsReps; }
        if (s.equals("time_domain"))     { return Rez.Drawables.IcSlotTimeDomain; }
        if (s.equals("emom"))            { return Rez.Drawables.IcSlotEmom; }
        if (s.equals("amrap"))           { return Rez.Drawables.IcSlotAmrap; }
        if (s.equals("amrap_movement"))  { return Rez.Drawables.IcSlotAmrapMovement; }
        if (s.equals("for_time"))        { return Rez.Drawables.IcSlotForTime; }
        if (s.equals("distance"))        { return Rez.Drawables.IcSlotDistance; }
        if (s.equals("static_hold"))     { return Rez.Drawables.IcSlotStaticHold; }
        if (s.equals("skill_practice"))  { return Rez.Drawables.IcSlotSkillPractice; }
        return Rez.Drawables.IcUiGeneric;
    }

    function categoryKey(c) {
        if (c == null) { return Rez.Drawables.IcUiGeneric; }
        if (c.equals("strength"))       { return Rez.Drawables.IcCatStrength; }
        if (c.equals("conditioning"))   { return Rez.Drawables.IcCatConditioning; }
        if (c.equals("kettlebell"))     { return Rez.Drawables.IcCatKettlebell; }
        if (c.equals("gpp_durability")) { return Rez.Drawables.IcCatGppDurability; }
        if (c.equals("movement_skill")) { return Rez.Drawables.IcCatMovementSkill; }
        if (c.equals("combat_sport"))   { return Rez.Drawables.IcCatCombatSport; }
        if (c.equals("recovery"))       { return Rez.Drawables.IcCatRecovery; }
        return Rez.Drawables.IcUiGeneric;
    }

    // The hero icon for one exercise: its movement pattern if the backend sent
    // one, otherwise the slot-type icon, otherwise a neutral mark. Never null —
    // an un-upgraded backend must degrade, not crash.
    function forExercise(ex) {
        if (ex == null) { return Rez.Drawables.IcUiGeneric; }
        var k = patternKey(ex.movementPattern());
        if (k != null) { return k; }
        return slotKey(ex.slotType());
    }

    // Load and cache. Call from onShow / on exercise change — NEVER from
    // onUpdate: "Loading a resource can be an expensive operation, so do not load
    // resources when handling screen updates."
    function prefetch(rezId) {
        if (rezId == null) { return null; }
        for (var i = 0; i < CACHE_N; i += 1) {
            if (_key[i] != null && _key[i] == rezId) { return _ref[i]; }
        }
        var r = null;
        try {
            r = Application.loadResource(rezId);
        } catch (e) {
            return null;
        }
        _key[_next] = rezId;
        _ref[_next] = r;
        _next = (_next + 1) % CACHE_N;
        return r;
    }

    // Safe in onUpdate once prefetched: a cache hit is an 8-element scan with no
    // allocation. drawBitmap2 takes the TOP-LEFT corner.
    function draw(dc, x, y, rezId, tint) {
        var r = prefetch(rezId);
        if (r == null) { return; }
        if (dc has :drawBitmap2) {
            dc.drawBitmap2(x, y, r, { :tintColor => tint });
        } else {
            dc.drawBitmap(x, y, r);
        }
    }

    function drawCentered(dc, cx, cy, size, rezId, tint) {
        draw(dc, cx - (size / 2), cy - (size / 2), rezId, tint);
    }

    // Drop every cached reference so the pool can reclaim. Call from onHide.
    function release() {
        for (var i = 0; i < CACHE_N; i += 1) { _key[i] = null; _ref[i] = null; }
        _next = 0;
    }
}
