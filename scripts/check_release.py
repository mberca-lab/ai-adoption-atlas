"""Check that the published story contains complete, identical aggregate exports."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    public = ROOT / "site" / "data"
    expected = {"trust_trends.json", "modelling.json", "segments.json"}
    manifest = json.loads((public / "manifest.json").read_text(encoding="utf-8-sig"))
    assert set(manifest["files"]) == expected, "Incomplete published manifest"
    data = {}
    for name in sorted(expected):
        source = (ROOT / "site_data" / name).read_bytes()
        assert source == (public / name).read_bytes(), f"Stale published export: {name}"
        data[name] = json.loads(source)
        assert not data[name].get("meta", {}).get("fixture"), f"Illustrative export: {name}"
    trends = data["trust_trends.json"]["series"]
    for series in trends:
        values = series["values"]
        is_change = "_change_" in series["name"]
        assert all(v is None or (-100 if is_change else 0) <= v <= 100 for v in values), series["name"]
        assert len(values) == len(series["labels"]), series["name"]
        for value, lo, hi in zip(values, series["ci_low"], series["ci_high"]):
            if value is not None and lo is not None and hi is not None:
                assert (-100 if is_change else 0) <= lo <= value <= hi <= 100, series["name"]
    segments = data["segments.json"]
    assert segments["meta"]["status"] == "final"
    assert segments["classes"], "No validated segment results"
    assert abs(sum(c["share"] for c in segments["classes"]) - 1) < 0.001
    assert segments["rules"], "No tool co-occurrence results"
    assert data["modelling.json"]["model_metrics"], "No modelling results"
    print("Release checks passed: complete, identical aggregate exports; valid trend intervals.")


if __name__ == "__main__":
    main()
