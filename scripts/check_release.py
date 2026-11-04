"""Check that the published story contains complete, identical aggregate exports."""
import json
import hashlib
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check_followups(trust, modelling):
    followup = trust["followup"]
    model = modelling["primary_stability"]
    assert followup == json.loads((ROOT / "outputs/trust_followup/summary.json").read_text())
    assert model == json.loads((ROOT / "outputs/model_stability/summary.json").read_text())
    for path, digest in (
        ("scripts/05_trust_followup.R", followup["meta"]["source_script_sha256"]),
        ("scripts/02_trust_trends_lib.R", followup["meta"]["helper_sha256"]),
        ("scripts/05_model_stability.py", model["meta"]["script_sha256"]),
        ("scripts/03_modelling.py", model["meta"]["original_script_sha256"]),
    ):
        assert hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest() == digest, path
    assert followup["meta"]["data_sha256"] == model["meta"]["data_sha256"]
    assert len(followup["population_flow"]) == len(followup["source_audit"]["files"]) == 4
    for row in followup["population_flow"]:
        assert row["eligible_professionals"] == row["answered_ai_status"] + row["missing_ai_status"]
        assert row["current_ai_users"] <= row["answered_ai_status"]
        if row["year"] < 2026:
            assert row["current_ai_users"] == row["trust_answered_users"] + row["trust_missing_users"]
        else:
            assert row["trust_answered_users"] is row["trust_missing_users"] is None
    assert all(r["upstream_match"] and len(r["sha256"]) == 64 for r in followup["source_audit"]["files"])
    assert followup["adoption_change_bounds"]["lo"] < 0 < followup["adoption_change_bounds"]["hi"]
    assert len(followup["frequency_adjusted"]) == 6 and len(followup["frequency_contrasts"]) == 2
    assert sum(r["n"] for r in followup["frequency_raw"]) == followup["meta"]["n_analyzed"]
    for r in followup["frequency_adjusted"]:
        assert 0 <= r["lo"] <= r["adjusted_pct"] <= r["hi"] <= 100
    for r in followup["frequency_contrasts"]:
        assert -100 <= r["lo"] <= r["adjusted_difference_pp"] <= r["hi"] <= 100
    assert followup["diagnostics"]["main"]["converged"] and followup["diagnostics"]["complete"]["converged"]
    assert model["meta"]["sample_fraction"] == 1
    assert len(model["runs"]) == 8 and len(model["summary"]) == 2
    for summary in model["summary"]:
        rows = [r for r in model["runs"] if r["outcome"] == summary["outcome"]]
        assert len(rows) == 4 and len({r["seed"] for r in rows}) == 4
        assert sum(r["training_bootstrap"] for r in rows) == 3
        assert {r["n_test"] for r in rows} == {summary["n_test"]}
        assert summary["d_auc_min"] == min(r["d_auc"] for r in rows)
        assert summary["d_auc_max"] == max(r["d_auc"] for r in rows)
        for r in rows:
            assert r["n_refit"] == r["n_inner_fit"] + r["n_tune"]
            assert not any(r[k] for k in ("fit_calibration_overlap", "test_fit_overlap",
                                         "test_calibration_overlap"))
            assert math.isclose(r["d_auc"], r["metrics"]["ensemble"]["auc"] -
                                r["metrics"]["logit_recal"]["auc"], abs_tol=1e-12)
            assert -1 <= r["d_auc_lo"] <= r["d_auc_hi"] <= 1


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
        assert len(series["n"]) == len(values), series["name"]
        assert all(n is None or (type(n) is int and n >= 0) for n in series["n"]), series["name"]
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
    check_followups(data["trust_trends.json"], data["modelling.json"])
    print("Release checks passed: identical aggregates, valid intervals, audited analytical follow-ups.")


if __name__ == "__main__":
    main()
