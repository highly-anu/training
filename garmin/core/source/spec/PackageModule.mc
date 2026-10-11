using Toybox.Lang;

// A package's compiled extension: the escape hatch for a screen the vocabulary
// cannot express.
//
// Most packages need none -- their watch.yaml picks from the vocabulary and the
// core draws it. A package that does need code puts it in
// garmin/packages/<id>/source (a subclass of this, annotated (:pkg_<id>)),
// names it in garmin/packages/<id>/package.json, and names the module in its
// watch.yaml (`module: <id>`) and the screen on a slot (`module_screen: <name>`).
// garmin/tools/gen_registry.py writes Registry.mc and packages.jungle from those
// files: Monkey C has no reflection, so the registry is how the core reaches a
// class it cannot name.
//
// Every hook defaults to "not handled", and a slot's spec is complete without
// the module, so a build that leaves the module out (or a watch on an older
// build) draws the declarative screen. Packages fill content, never chrome:
// a module renderer supplies the same title / fields / lines / LAP as any other,
// inside Garmin's data page that ExerciseScreen draws.
class PackageModule {

    function initialize() {}

    // A Renderer for the named module_screen, or null for the declarative one.
    function renderer(screen as Lang.String, spec as Lang.Dictionary) { return null; }
}
