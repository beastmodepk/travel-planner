#!/usr/bin/env python3
"""Validate packages/dataset/dataset.json.

Two layers, both stdlib-only so this runs anywhere (CI ubuntu included):
1. JSON Schema validation against dataset.schema.json when the `jsonschema`
   package is importable; skipped with a note otherwise.
2. House structural checks the schema can't express: unique destination ids,
   exactly one exact Epic ladder rung at 3 days ($386), the researched golden
   anchors (Niseko Jan comfort hotel $434.02, Jackson Jan 3-of-4 $618.34),
   null hotel name <=> null price, every ready destination fully priced.

Exit code 0 = valid. Run from anywhere; paths resolve relative to the repo.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "packages" / "dataset" / "dataset.json"
SCHEMA = ROOT / "packages" / "dataset" / "dataset.schema.json"

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def main():
    data = json.loads(DATASET.read_text())
    schema = json.loads(SCHEMA.read_text())

    try:
        import jsonschema

        jsonschema.validate(data, schema)
        print("schema: OK (jsonschema)")
    except ImportError:
        print("schema: jsonschema package not installed — structural checks only")
    except Exception as e:  # jsonschema.ValidationError
        failures.append(f"schema validation failed: {e.message if hasattr(e, 'message') else e}")

    check(data.get("checkedAt") == "2026-11-13", "checkedAt must stay 2026-11-13 for dataset v1")
    check(data.get("origin") == "BOS", "dataset origin must be BOS")

    dests = data["destinations"]
    ids = [d["id"] for d in dests]
    check(len(ids) == len(set(ids)), "destination ids must be unique")
    check(set(ids) == {"park-city", "tahoe", "alta", "jackson", "breckenridge", "niseko"},
          f"expected the 6 researched destinations, got {sorted(ids)}")

    ladder = {r["days"]: r for r in data["epicPass"]["ladder"]}
    check(sorted(ladder) == list(range(1, 11)), "Epic ladder must cover 1..10 days")
    exact = [d for d, r in ladder.items() if not r["estimate"]]
    check(exact == [3] and ladder[3]["price"] == 386,
          f"only the 3-day $386 rung may be exact, got exact rungs {exact}")
    check(ladder[6]["price"] == 640, "6-day Epic Day Pass estimate must be $640")
    check(data["epicPass"]["fullPassPrice"] == 1169, "Full Epic Pass must be $1169")

    lift = data["nonEpicLift"]
    check(lift["jackson"]["dec"]["threeOfFour"] == 782.58, "Jackson Dec 3-of-4 anchor drifted")
    check(lift["jackson"]["jan"]["threeOfFour"] == 618.34, "Jackson Jan 3-of-4 anchor drifted")
    check(lift["niseko"]["jan"]["threeDay"] == 255, "Niseko Jan 3-day anchor drifted")

    by_id = {d["id"]: d for d in dests}
    niseko_jan_comfort = by_id["niseko"]["hotels"]["jan"]["comfort"]
    check(niseko_jan_comfort["name"] == "Torifito Hotel And Pod Niseko"
          and niseko_jan_comfort["price"] == 434.02
          and niseko_jan_comfort["expediaId"] == "58975020",
          "Niseko Jan comfort golden anchor (Torifito $434.02) drifted")
    pc_dec_comfort = by_id["park-city"]["hotels"]["dec"]["comfort"]
    check(pc_dec_comfort["price"] == 883.48 and pc_dec_comfort["expediaId"] == "5692776",
          "Park City Dec comfort golden anchor (Chateau Apres $883.48) drifted")

    for d in dests:
        for window in ("dec", "jan"):
            for tier in ("value", "comfort", "premium"):
                h = d["hotels"][window][tier]
                check((h["name"] is None) == (h["price"] is None),
                      f"{d['id']}/{window}/{tier}: hotel name and price must be null together")
            check(d["flights"][window]["basic"] > 0, f"{d['id']}/{window}: basic fare must be priced")

    if failures:
        print("DATASET INVALID:")
        for f in failures:
            print(" -", f)
        return 1
    print(f"dataset: OK — {len(dests)} destinations, checkedAt {data['checkedAt']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
