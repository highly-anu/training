# Custom Icons

How the app draws an icon SF Symbols does not have, so the next one looks
like it came from the same hand as the last. The first was `kettlebell`
(2026-10-15); the tools in `ios/tools/` were built around it so the second
costs an afternoon, not a redesign.

Read with `design-system.md` §6.12 (activity vs modality icons), which says
*which* icon a screen shows; this document says how a custom one is made.

---

## 1. Only when SF Symbols has nothing

A custom icon is a maintenance cost and never quite as polished as Apple's.
Make one only when no system symbol reads correctly — not when one exists
and is merely plain.

Check the full list of the runtime we ship against, not the SF Symbols app
or memory:

```bash
f="$(find /Library/Developer/CoreSimulator/Volumes -path '*iOS*CoreGlyphs.bundle*' \
      -name name_availability.plist 2>/dev/null | sort | tail -1)"
plutil -convert json -o - "$f" | python3 -c "import json,sys
for k in sorted(json.load(sys.stdin)['symbols']):
    print(k)" | grep -i <word>
```

`kettlebell` exists because that search, on iOS 26.3's 9,184 names, found
only `dumbbell`, `figure.strengthtraining.functional` (which reads as a
lunge) and `figure.strengthtraining.traditional` (a barbell, already Max
Strength's).

If Apple later ships a symbol for the same thing, switch to it and delete
ours.

## 2. The style

Every rule here comes from making a custom glyph sit in a row of Apple's
without looking like a guest.

**Silhouette first.** The icon must be recognisable at list size — `.title3`,
about 20 pt — in one flat colour. Find the one feature that says what the
object is and exaggerate it. The kettlebell's first two drafts had a narrow
handle and a small window and read as a **padlock** at 20 pt; widening the
handle to nearly the ball's width and doubling the window fixed it. Always
ask what else the shape could be mistaken for.

**Filled, for objects.** Object icons in this app are the `.fill` variants
(`dumbbell.fill`, `bolt.fill`, `backpack.fill`), so a custom object icon is
a solid shape with holes, not an outline. Do not draw human figures: SF
Symbols' figures have a pose and stroke language we would not match. If an
activity needs a person, use a `figure.*` symbol and accept the nearest pose.

**Monochrome.** The SVG carries no colour. The modality colour comes from
`.foregroundStyle` at the call site, as it does for system symbols
(§6.12: the icon says what you did, the colour where it sits in the
palette). No hierarchical or multicolour layers.

**Geometry on the 100 grid** (y down), built from a few primitives:

| | Kettlebell | Rule |
|---|---|---|
| Ink height | 85 units (y 7–92) | Fill the grid's height; the writer scales it to the house size anyway. |
| Ink width | 68 units | No wider than tall — a wide glyph looks bigger than its neighbours. |
| Stroke-like parts | 9–10 units (the handle) | ≈ 2 pt at 20 pt, the weight of SF Regular strokes at that size. Thinner vanishes. |
| Smallest detail or gap | 9 units (the handle's top bar) | Nothing under ~6 units: it is under 1.5 pt on screen. |
| Outer corners | radius ≈ 17 (quadratic) | Soft, never sharp, never a full semicircle on a straight part. |
| Inner corners | radius ≈ 10 | About 60 % of the outer one, so the stroke keeps its width round the bend. |
| Curves | circle arcs, quadratic corners | No freehand Béziers — they are what makes a glyph look home-made. |

**House metrics are shared, not per icon.** `symbol_template.py` scales every
glyph to `HEIGHT_S` = 74 units in the template's Small row (about the
dumbbell's height), centres it on the cap height and gives it `SIDEBEARING`
= 3 units each side. Change those only for every icon at once.

**One shape for every weight.** The writer emits the three required sources
(Ultralight-S, Regular-S, Black-S) with the same outline; a filled glyph does
not thin with the font weight, and Xcode interpolates the rest. An outline
icon that had to follow the weight would need three drawings — another reason
to stay filled.

**Holes by winding, never by fill rule.** Draw solid outlines clockwise (on
screen) and holes counter-clockwise. The template is filled non-zero; an
even-odd hole is ignored and fills solid.

## 3. Making one

1. **Draw it in code.** Copy `ios/tools/make_kettlebell_symbol.py` to
   `make_<name>_symbol.py`. Describe the glyph with `Glyph` —
   `move / line / quad / arc` — and call `write_symbolset('<name>', glyph,
   script=…)`. It writes `TrainingCompanion/Assets.xcassets/<name>.symbolset/`
   (SVG + `Contents.json`). Never edit the SVG by hand; edit the script and
   run it again.

   ```bash
   python3 ios/tools/make_<name>_symbol.py
   ```

2. **Look at it beside its neighbours.** The preview draws the custom symbol
   next to the system symbols you name — the ones it will sit beside in a
   list, and the one it replaces — in dark and light, large and at list size
   in the modality colours:

   ```bash
   swift ios/tools/preview_symbol.swift <name> /tmp/<name>.png \
       dumbbell.fill figure.strengthtraining.functional figure.run bolt.fill
   ```

   Iterate here until it reads at list size. Show the sheet before wiring it in.

3. **Register it.** Add the name to `AppSymbol.custom` (with a constant) in
   `ModalityStyle.swift`. `ActivityIconTests.testCustomSymbolsLoadFromTheCatalog`
   then fails if Xcode cannot compile the symbolset — a rejected custom symbol
   is silently an empty image.

4. **Draw it with `Image(symbol:)`.** A custom name passed to
   `Image(systemName:)` or `Label(_:systemImage:)` draws nothing. Every place
   that shows an icon name from `ActivityIcon` or `ModalityStyle` uses
   `Image(symbol:)`; a `Label` needs `Label { … } icon: { Image(symbol: …) }`.

5. **Check the real screen.** `./ios/run_tests.sh`, then
   `LOCAL_API=1 ROUTE=… ./ios/run_sim.sh /tmp/x.png` on a screen that shows
   it. The preview approximates SwiftUI's sizing; the simulator is the truth.

6. **Record it** in the inventory below and, if it changes which icon a
   screen shows, in design-system §6.12.

**Naming.** Lowercase, dot-separated, as Apple names things (`kettlebell`,
not `KettlebellIcon`). No `figure.` prefix — we do not draw figures — and no
name Apple already uses.

**Other targets.** Asset catalogs are per target. The watch app, widgets and
watch widgets have their own `Assets.xcassets` and their own `ModalityStyle`;
to use an icon there, write the symbolset into that catalog too (`write_symbolset(…, assets=<that catalog>)`) and add the same `Image(symbol:)`
routing to that target.

## 4. Inventory

| Symbol | Shows | Used for | Script |
|---|---|---|---|
| `kettlebell` | A kettlebell: wide handle, large window, round ball, short flat base | Recorded workouts whose activity names a kettlebell (`kb`, `kettlebell`) — `ActivityIcon.forActivityType` | `ios/tools/make_kettlebell_symbol.py` |
