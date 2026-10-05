# Wellness Spike

A **throwaway hardware probe**, not a feature. Before any wellness code goes into the real watch
app (`../TrainingCompanionCIQ/`), this app answers six questions on the athlete's own watch that
the simulator cannot: which of the Connect IQ signals a watch app may read are real, whether they
can be read from a background service with the app closed, and whether a web request through the
phone works from there. It has its own app id, so it sideloads beside the real app; nothing in it
talks to the training API except one public reachability check.

When the answers are in, record them in `docs/roadmap.md` (the *Garmin wellness via Connect IQ*
item) and delete this directory.

## What it does

- **Foreground.** Opening the app takes a reading at once (`O`) and registers three background
  events: a temporal event every 15 minutes, and the wake and sleep events. The outcome of every
  registration is logged, because a registration that silently did not happen looks exactly like
  "the event never fires".
- **Background service.** On every event it counts the fire, keeps a per-day summary, and reads
  every candidate signal: always in the morning window (04:00-12:00), otherwise on the first fire of
  each hour. A line goes to the log only when a slow signal changed; the rest are counted.
- **Reachability.** Once an hour the service requests `GET <apiBaseUrl>/devices/status`, a public
  route that answers `400 {"detail":"Missing device token"}` without touching the database. The
  point is the transport, not the body: any HTTP status counts as reachable, and so does a reply
  whose body was not JSON (the SDK reports that as -400 or -1002 instead of the status).
- **Nothing leaves the watch except that one request.** Results are kept in `Storage` (small rings,
  a few KB) and shown on the app's own pages, so nothing needs a cable to read back.

## Build and sideload

1. Find the watch model (Garmin Connect app, device settings) and its id:
   `./build.sh --list <name>` lists the devices this app targets (126 of the SDK's 173) with their
   background memory budget and part numbers. The real app's manifest names only `fenix943mm` and
   `fenix947mm`, so the athlete's model may be missing from *that* list; this app covers 126 devices.
2. `DEVICE=<id> ./build.sh --device` writes `bin/<id>/WSPIKE.prg` (a release build).
3. Connect the watch over USB and copy the file into `GARMIN/APPS/`. Eject and let the watch settle.
4. **Open the app once.** Registration happens in the foreground, so a watch that was never opened
   after the copy has no background events. On the FG page, under the four counter lines, the
   newest line is the opening reading (`O`) and the one below it should read `reg T+ W+ S+` the
   first time and `reg T=every15m W= S=` afterwards (`!` instead of `+` or `=` means the SDK
   refused, with its message).

Other commands: `./build.sh` (simulator build, nothing is launched), `./build.sh --check [id ...]`
(type-check level 2 on a spread of devices, including the 32 KB-background ones; "All compiled."
is the pass). The manifest's product list is generated: `python3 tools/gen_products.py --write`.

## Using the app

| Key | Does |
|---|---|
| UP / DOWN (or swipe) | scroll the page |
| START / SELECT | next page |
| BACK | previous page; leaves the app from the first page |
| MENU (hold UP) | take a manual reading (`M`) |

Pages: **NOW** (a live reading, taken when the app opened) · **BG** (the service's counters) ·
**LOG** (the service's value lines, newest first) · **DAYS** (one line per day: fires, first, last,
longest gap) · **FG** (opens, registrations, the foreground's own readings).

On DAYS, `fires` counts every run including the wake and sleep events (a perfect day is a little
over 96), and `maxgap` is the longest gap between two runs *within* that day; the overnight gap is
yesterday's `last` to today's `first`.

## The five mornings

Each morning, before anything else: note the Garmin Connect app's **resting heart rate**,
**Body Battery** (the value on waking and the overnight high), the watch's **recovery time**, and
the configured **wake time**. Then open the app and read BG, LOG and DAYS back. Lines or counters
taken before you opened it were taken with the app closed; the lines taken after carry an `f`.

| # | Question | Look at | Pass |
|---|---|---|---|
| 1 | Is `restingHeartRate` a daily value or a static setting? | LOG `r`, and `a` for contrast, against Connect's number each morning. `h` / `hlo` is the fallback candidate | `r` moves on at least 3 of 5 mornings and is within 2 bpm of Connect. Otherwise `h` within 5 bpm of Connect and not flat |
| 2 | Do the `SensorHistory` reads work from the background? What do `getMin()` / `getMax()` return, and do they agree with the walk's own minimum and maximum? Cost? | LOG `h` and `b` on lines without `f`; BG `hr` / `bb` (`n`, `seen`, `span`, `min`, `max`), `getMin/Max` (values and kinds), `hr` / `bb` ms and `mem` | non-null on at least 4 of 5 mornings, under 5 s, peak memory at most 24 KB (the design budget is 32 KB). `seen` equal to its cap (600 heart rate, 300 Body Battery) means the walk stopped early; `span` says how far back it got |
| 3 | Is `timeToRecovery` non-null in the morning, from the background? | LOG `tr` on a line without `f` | at least 4 of 5 mornings, and equal to the watch's own recovery time |
| 4 | Does the temporal event fire with the app closed, and does a web request complete from the background within 30 s? | Read BG first: `last` against the clock when you opened the app. Then yesterday's DAYS line (`fires`, `first`, `maxgap`) and BG `api ok / fail / killed / pending`, `api last` | `last` within about 20 min of opening on at least 4 of 5 mornings; yesterday's fires near 96 (one per 15 min) with a longest gap of about 30 min or less; `ok` rising, `killed` 0, latency well under 30 000 ms |
| 5 | What are `wakeTime` and `sleepTime`? | LOG `w` / `s`; NOW `Wake`, `sleep`, `next wake` | `w` is the configured wake time, as local time of day |
| 6 | Which part number is the watch, and which products does the real manifest need? | NOW `dev` (the part number); `./build.sh --list <part>` | maps to one SDK device, so its `<iq:product>` id can be added |

### Kill criteria

- **4 fails** (no events, or the request is killed or never completes): the real feature syncs when
  the app is opened and the background service is not built.
- **1 fails and `h` is not within 5 bpm and moving**: the watch's resting heart rate is display-only
  and is not merged into readiness.
- **2 and 3 are null from the background on every morning**: stop. Record it in the roadmap; Strava
  (activities) and the dormant Garmin Developer Program code remain the fallbacks.

If nothing has been logged by the second morning, the service is not running at all. Check
`GARMIN/APPS/LOGS/CIQ_LOG.YAML` on the watch for an out-of-memory crash (the budget is 32 KB on many
watches and 64 KB on the fēnix 7/8/9 families) and tell me what it says.

## Reading a LOG line

```
05 06:41B+3 !ox:Invalid r52 a54 h49/50#212 ha2 b88/31/86#64 ba4 tr14 w06:30 s22:30 am49#210 st23#9 ox-#- v52
```

| Part | Meaning |
|---|---|
| `05 06:41` | day of month and local time of the reading |
| `B` / `W` / `S` | the temporal, wake or sleep event. `O` is the foreground's reading on open, `M` a manual one |
| `f` after the tag | the app was open (marker set within the last 30 minutes), so the foreground and the service overlapped |
| `+3` | three earlier reads had the same slow values and were not logged |
| `!ox:...` | right after the tag, so the line cap cannot cut it: a read that threw, here SpO2 (so `ox-#-`). `pf` profile, `am` activity monitor, `hr` heart rate, `bb` Body Battery, `st` stress, `ox` SpO2, `ah` AM heart rate, `ds` device settings, then the start of the message |
| `r52` `a54` | `UserProfile` resting heart rate, and the average resting heart rate (history; **never** a scoring input) |
| `h49/50#212` `ha2` | heart rate from `SensorHistory`, last 8 h: lowest sample, mean of the lowest 5, valid samples; age of the newest sample in minutes |
| `b88/31/86#64` `ba4` | Body Battery, last 12 h: highest, lowest, newest, valid samples; age of the newest |
| `tr14` | `ActivityMonitor` recovery time, hours |
| `w06:30` `s22:30` | `UserProfile` wake and sleep time (seconds since local midnight, shown as hh:mm) |
| `am49#210` | the same 8 h of heart rate through `ActivityMonitor`, as a second opinion on `h` |
| `st23#9` `ox96#4` | newest stress (3 h) and SpO2 (12 h) with their sample counts |
| `v52` | VO2max (running) |

`-` means the value was null or the read was unavailable on this watch.

A line is logged when `r`, `a`, `hmin`, `bmax`, `tr`, `w`, `s`, `v` or an error changed. The
lowest-5 mean, the Body Battery low, the `am` minimum, newest-sample values, ages and counts never
trigger one, because they drift as the window slides. Wake and sleep events always log. The ring
holds 24 lines of at most 120 characters; a longer line loses its tail, never its error.

## The BG and NOW pages

| Shown | Meaning |
|---|---|
| `runs n B W S` | service runs in total, and by event |
| `first` / `last` | first and most recent run |
| `reads` `logged` `unchanged` | readings taken, lines written, readings skipped because no slow value had changed (all time; the `+n` on a LOG line counts only the skips since the previous line) |
| `api ok / fail / killed / pending` | hourly request: answered (any HTTP status, or -400 / -1002 when the body was not JSON), failed (any other negative code, such as -104, no phone connection, or a request the SDK refused to make), still unanswered when the next one started (the service was killed first), outstanding now |
| `api last` | last status code, latency, worst latency, when |
| `run` `read` `hr` `bb` | milliseconds: the whole run, one full read, the heart-rate walk, the Body Battery walk |
| `mem start / read / peak / of` | `usedMemory` before any read, after the reads the real feature would need (resting HR, HR history, Body Battery, recovery time), the peak including the extras, and `totalMemory` (the budget this process had) |
| `getMin/Max` | what `getMin()` and `getMax()` returned for the window, then their runtime types in brackets: `N` number, `F` float, `Z` null, `X` other, `!` the call threw. Compare with the walk's own `min` / `max` (NOW: the `HR` and `BB` lines; BG: the `hr` and `bb` lines) |
| `seen` `span` | samples the walk visited out of its cap (600 heart rate, 300 Body Battery), and the minutes from the newest to the oldest of them. `seen` equal to the cap means the walk stopped early, so `min` / `max` cover only the newest part of the window |
| `hr n.. age..` | on BG: samples, newest age and the walk's `min` / `max`, from the service's last read; a read that found nothing shows `-`, not an older value |
| `dev` `fw` `mv` `phone` | part number, firmware, Monkey C version, phone connected |
| `read err`, `service err` | an error inside a read, or one that escaped it, with a count |

## Honest limits

- It reads what the open SDK offers. **Nightly HRV, sleep and training readiness are not readable**;
  this app cannot find them and the plan does not pretend otherwise.
- A pass here proves a build on one watch. The memory result is for this watch's budget only; the
  32 KB devices are type-checked, not run.
- The `mem` figures are `usedMemory` of the service process. The peak is taken inside the read,
  before the log ring is loaded to write a line, so it leaves out the few KB that takes (the real
  feature has no ring, but adds its own code and one request body).
- The probe is a request to a public route. It does not authenticate and writes nothing.
