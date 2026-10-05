#!/usr/bin/env python3
"""Product list for manifest.xml, from the installed Connect IQ device definitions.

  tools/gen_products.py --list [text]     eligible devices (id, name, CIQ, bg memory, part numbers)
  tools/gen_products.py --part 006-B5134-00   which device id(s) list that part number
  tools/gen_products.py --write           rewrite the block between the PRODUCTS markers in manifest.xml

Eligible = has watchApp and background app types and supports API level >= 3.3 (the level
SensorHistory body battery and ActivityMonitor.Info.timeToRecovery arrived in).
"""
import json, os, re, sys

DEV = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")
HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "..", "manifest.xml")
BEGIN, END = "<!-- PRODUCTS:BEGIN -->", "<!-- PRODUCTS:END -->"


def level(group):
    m = re.search(r"(\d+)\.(\d+)", group or "")
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def devices():
    out = []
    for d in sorted(os.listdir(DEV)):
        p = os.path.join(DEV, d, "compiler.json")
        if not os.path.isfile(p):
            continue
        j = json.load(open(p, encoding="utf-8"))
        apps = {a["type"]: a.get("memoryLimit") for a in j.get("appTypes", [])}
        out.append({
            "id": j.get("deviceId", d), "name": j.get("displayName", d),
            "level": level(j.get("deviceGroup")), "bg": apps.get("background"),
            "watch": apps.get("watchApp"),
            "parts": [(n.get("number"), n.get("connectIQVersion")) for n in j.get("partNumbers", [])],
        })
    return out


def eligible():
    return [d for d in devices() if d["bg"] and d["watch"] and d["level"] >= (3, 3)]


def main(argv):
    if not os.path.isdir(DEV):
        sys.exit("No Connect IQ device definitions at " + DEV)
    if argv[:1] == ["--part"] and len(argv) == 2:
        hits = [d for d in devices() if any(n == argv[1] for n, _ in d["parts"])]
        for d in hits:
            print(d["id"], "|", d["name"], "| eligible" if d in eligible() else "| NOT eligible")
        sys.exit(0 if hits else "no device lists part number " + argv[1])
    if argv[:1] == ["--list"]:
        for d in eligible():
            print("%-22s %-34s API %d.%d  bg %3d KB  %s" % (
                d["id"], d["name"], d["level"][0], d["level"][1], d["bg"] // 1024,
                ", ".join(n for n, _ in d["parts"][:3])))
        print(len(eligible()), "eligible of", len(devices()), file=sys.stderr)
        return
    if argv[:1] == ["--write"]:
        text = open(MANIFEST, encoding="utf-8").read()
        block = "\n".join('      <iq:product id="%s"/>' % d["id"] for d in eligible())
        pat = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.S)
        if not pat.search(text):
            sys.exit("markers not found in manifest.xml")
        open(MANIFEST, "w", encoding="utf-8").write(pat.sub(BEGIN + "\n" + block + "\n      " + END, text))
        print("wrote", len(eligible()), "products")
        return
    sys.exit(__doc__)


main(sys.argv[1:])
