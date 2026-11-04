#!/usr/bin/env python
"""Focused aggregate/logic checks; never imports or reruns the modelling job.

Run after modelling and figures: python scripts\\03_modelling_verify.py
"""
import ast
import hashlib
import json
import os
from pathlib import Path
import unittest

for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[key] = "2"
import numpy as np
import pandas as pd
from scipy.stats import rankdata
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "modelling"
TAB = OUT / "tables"
SOURCE = ROOT / "scripts" / "03_modelling.py"
HELPERS = {"auc_fast", "logloss", "brier", "prauc", "bootstrap", "verdict",
           "calibration_partition", "fit_categories", "align_categories", "probability_bins"}
tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in HELPERS]
from sklearn.metrics import average_precision_score
scope = dict(np=np, pd=pd, rankdata=rankdata, SEED=20261104, EPS=1e-6,
             MATTER_DAUC=0.01, MATTER_DLL_REL=0.01, train_test_split=train_test_split,
             average_precision_score=average_precision_score)
exec(compile(ast.Module(body=nodes, type_ignores=[]), str(SOURCE), "exec"), scope)
scope["METRICS"] = {k: scope[f] for k, f in
                    (("auc", "auc_fast"), ("pr_auc", "prauc"), ("log_loss", "logloss"), ("brier", "brier"))}


class LogicTests(unittest.TestCase):
    def test_auc_ties_and_single_class(self):
        y = np.array([0, 1, 0, 1, 1, 0])
        p = np.array([0.2, 0.4, 0.4, 0.8, 0.8, 0.8])
        self.assertAlmostEqual(scope["auc_fast"](y, p), roc_auc_score(y, p))
        self.assertTrue(np.isnan(scope["auc_fast"](np.ones(6), p)))

    def test_calibration_partition_disjoint_deterministic(self):
        X = pd.DataFrame({"x": range(100)}, index=range(200, 300))
        y = np.tile([0, 1], 50)
        a, b = scope["calibration_partition"](X, y)
        aa, bb = scope["calibration_partition"](X, y)
        self.assertTrue(np.array_equal(a, aa) and np.array_equal(b, bb))
        self.assertFalse(set(X.index[a]) & set(X.index[b]))
        self.assertEqual(len(set(a) | set(b)), 100)
        self.assertEqual(y[a].mean(), y[b].mean())

    def test_unseen_category_not_learned(self):
        train = pd.DataFrame({"c": pd.Categorical(["B", "A", "B"], categories=["A", "B", "TEST_ONLY"])})
        vocab = scope["fit_categories"](train)
        self.assertEqual(vocab["c"], ["A", "B"])
        test = pd.DataFrame({"c": pd.Categorical(["TEST_ONLY", "A"])})
        aligned = scope["align_categories"](test, vocab)
        self.assertTrue(pd.isna(aligned.c.iloc[0]))
        self.assertEqual(aligned.c.iloc[1], "A")

    def test_paired_bootstrap_identical_models_and_clusters(self):
        y = np.tile([0, 1], 20)
        p = np.linspace(0.1, 0.9, len(y))
        for groups in (None, np.repeat(np.arange(8), 5)):
            args = dict(groups=groups, B=30, seed=3)
            met, diff = scope["bootstrap"](y, {"logit": p, "same": p}, **args)
            m2, d2 = scope["bootstrap"](y, {"logit": p, "same": p}, **args)
            pd.testing.assert_frame_equal(met, m2)
            pd.testing.assert_frame_equal(diff, d2)
            for name in ("auc", "log_loss", "brier", "pr_auc"):
                self.assertEqual(diff[f"d_{name}"].iloc[0], 0)
                self.assertEqual(diff[f"d_{name}_lo"].iloc[0], 0)
                self.assertEqual(diff[f"d_{name}_hi"].iloc[0], 0)

    def test_verdict_does_not_infer_equivalence(self):
        row = pd.Series(dict(d_auc=0.005, d_auc_lo=-0.01, d_auc_hi=0.02,
                             d_log_loss_rel=-0.005, d_log_loss_rel_lo=-0.02,
                             d_log_loss_rel_hi=0.01))
        self.assertIn("inconclusive", scope["verdict"](row))
        row.update(pd.Series(dict(d_auc=0.02, d_auc_lo=0.001)))
        self.assertIn("exploratory gain meets", scope["verdict"](row))
        row.d_log_loss_rel_lo = 0.001
        self.assertIn("trade-off", scope["verdict"](row))

    def test_equal_probabilities_are_not_arbitrarily_split(self):
        labels = scope["probability_bins"](np.repeat(0.7, 100))
        self.assertEqual(labels.nunique(), 1)
        p = np.repeat([0.2, 0.8], 50)
        labels = scope["probability_bins"](p)
        self.assertEqual(pd.DataFrame({"p": p, "bin": labels}).groupby("p").bin.nunique().max(), 1)

    def test_training_refit_and_platt_never_share_calibration_rows(self):
        train_node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "train_all")
        ns = scope.copy()
        fits, calibration = [], []
        def fake_fit(C, X, y, cats, nums):
            fits.append(set(X.index))
            return object()
        def fake_platt(p, y):
            calibration.append((p.copy(), y.copy()))
            return lambda x: x
        ns.update(json=json, fit_logit=fake_fit, fit_xgb=None, fit_lgb=None, SPLIT_ROWS=[],
                  pr=lambda model, X: X["x"].to_numpy() / 1000, platt=fake_platt)
        exec(compile(ast.Module(body=[train_node], type_ignores=[]), str(SOURCE), "exec"), ns)
        X = pd.DataFrame({"x": np.arange(10, 110)}, index=range(10, 110))
        y = np.tile([0, 1], 50)
        fitted = ns["train_all"](X.iloc[:60], y[:60], X.iloc[60:], y[60:],
                                 X, y, [], ["x"], ("logit",), "unit", [])
        cal_ids = set(np.rint(calibration[0][0] * 1000).astype(int))
        self.assertTrue(cal_ids)
        self.assertTrue(all(not ids & cal_ids for ids in fits))
        self.assertEqual(set(fitted["_train_index"]), set(X.index) - cal_ids)
        self.assertEqual(len(fits), 6)  # five tuning fits and one final refit


class AggregateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.js = json.loads((ROOT / "site_data" / "modelling.json").read_text(),
                            parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
        cls.meta = cls.js["meta"]
        cls.met = pd.read_csv(TAB / "model_metrics.csv")

    def test_provenance_and_budget(self):
        m = self.meta
        self.assertFalse(m["preregistered"])
        self.assertIn("Exploratory deterministic", m["analysis_note"])
        self.assertTrue(m["exploratory_thresholds"])
        self.assertLessEqual(m["threads"], 2)
        self.assertEqual(m["script_sha256"], hashlib.sha256(SOURCE.read_bytes()).hexdigest())
        self.assertAlmostEqual(m["realized_sample_fraction"], m["sampled_base_n"] / m["default_base_n"])
        self.assertEqual(m["bootstrap"]["metric_model_refits"], 0)
        self.assertEqual(m, json.loads((OUT / "run_metadata.json").read_text()))

    def test_export_matches_aggregate_tables(self):
        pairs = {"model_metrics": "model_metrics.csv", "diff_vs_logit": "model_diff_vs_logit.csv",
                 "shap_drivers": "driver_stability_bootstrap.csv",
                 "driver_ranks_by_year": "driver_stability_years.csv",
                 "partial_dependence": "partial_dependence.csv", "subgroup_audit": "subgroup_audit.csv"}
        for key, filename in pairs.items():
            exported = pd.DataFrame(self.js[key])
            table = pd.read_csv(TAB / filename)
            if key == "shap_drivers":
                table = table.sort_values(["outcome", "model", "mean_rank"], kind="stable")
            table = table.reset_index(drop=True)
            self.assertEqual(len(exported), len(table), key)
            for col in exported:
                if pd.api.types.is_numeric_dtype(exported[col]):
                    np.testing.assert_allclose(exported[col].astype(float), table[col].astype(float),
                                               atol=0.000101, rtol=0, equal_nan=True, err_msg=f"{key}/{col}")
                else:
                    self.assertEqual(exported[col].fillna("").astype(str).tolist(),
                                     table[col].fillna("").astype(str).tolist(), f"{key}/{col}")
        bins = pd.read_csv(TAB / "calibration_bins.csv")
        bins = bins[(bins.scheme == "temporal_2324to25") & (bins.feature_set == "D")
                    & bins.outcome.isin(["fav", "trust"])]
        exported = pd.DataFrame(self.js["calibration_bins"])
        for col in exported:
            if pd.api.types.is_numeric_dtype(exported[col]):
                np.testing.assert_allclose(exported[col], bins[col], atol=0.000101, rtol=0)
            else:
                self.assertEqual(exported[col].tolist(), bins[col].tolist())
        for key in ("calibration_bins", "shap_drivers"):
            self.assertTrue(all(r["feature_set"] == "D" and r["scheme"] == "temporal_2324to25"
                                for r in self.js[key]))

    def test_denominators_and_splits(self):
        sizes = pd.read_csv(TAB / "sample_sizes.csv")
        self.assertEqual(self.meta["sampled_base_n"], sizes[sizes.outcome == "use"].n.sum())
        audit = pd.read_csv(TAB / "split_audit.csv")
        for r in audit.itertuples():
            self.assertEqual(r.n_refit, r.n_inner_fit + r.n_tune)
            self.assertEqual(r.fit_calibration_overlap, 0)
            self.assertEqual(r.test_fit_overlap, 0)
            self.assertEqual(r.test_calibration_overlap, 0)
        self.assertTrue((audit.test_train_country_overlap.dropna() == 0).all())
        for r in self.met.itertuples():
            years = [2026] if r.outcome == "trust26" or r.scheme == "temporal_232425to26" else (
                [2023, 2024, 2025] if r.scheme == "groupcv_country" else [2025])
            expected = sizes[(sizes.outcome == r.outcome) & sizes.year.isin(years)].n.sum()
            self.assertEqual(r.n_test, expected)
            tag = f"{r.outcome}|{r.scheme}|{r.feature_set}"
            folds = audit[audit.tag.str.startswith(tag)]
            self.assertAlmostEqual(r.n_train, round(folds.n_refit.mean(), 1))
            self.assertEqual(r.n_test, folds.n_test.sum())

    def test_metrics_differences_and_verdicts(self):
        keys = ["outcome", "scheme", "feature_set"]
        for r in self.met.itertuples():
            for metric in ("auc", "pr_auc", "brier"):
                self.assertTrue(0 <= getattr(r, metric) <= 1)
            self.assertGreaterEqual(r.log_loss, 0)
        dif = pd.read_csv(TAB / "model_diff_vs_logit.csv")
        for _, row in dif.iterrows():
            group = self.met
            for key in keys:
                group = group[group[key] == row[key]]
            model = group[group.model == row.model].iloc[0]
            ref = group[group.model == row.vs].iloc[0]
            for metric in ("auc", "log_loss", "brier"):
                self.assertAlmostEqual(row[f"d_{metric}"], model[metric] - ref[metric], delta=0.000021)
                self.assertLessEqual(row[f"d_{metric}_lo"], row[f"d_{metric}_hi"])
            self.assertEqual(row.verdict, scope["verdict"](row))

    def test_calibration_subgroup_and_stability(self):
        bins = pd.read_csv(TAB / "calibration_bins.csv")
        for (outcome, scheme, fs, model), group in bins.groupby(["outcome", "scheme", "feature_set", "model"]):
            met = self.met[(self.met.outcome == outcome) & (self.met.scheme == scheme)
                           & (self.met.feature_set == fs) & (self.met.model == model)].iloc[0]
            self.assertEqual(group.n.sum(), met.n_test)
            self.assertAlmostEqual(np.average(group.observed, weights=group.n), met.prevalence_test, delta=0.00002)
            self.assertTrue(((group.obs_lo <= group.observed) & (group.observed <= group.obs_hi)).all())
        sub = pd.read_csv(TAB / "subgroup_audit.csv")
        self.assertTrue((sub.n >= 100).all())
        for model in ("logit", "lgbm"):
            self.assertTrue(((sub[f"fp_{model}"] + sub[f"fn_{model}"]) <= sub.n).all())
        stab = pd.read_csv(TAB / "driver_stability_bootstrap.csv")
        self.assertTrue((stab.n_boot == self.meta["bootstrap"]["stability_refits"]).all())
        self.assertTrue(stab.p_top3.between(0, 1).all())
        self.assertTrue((stab.rank_lo <= stab.rank_hi).all())
        tune = pd.read_csv(TAB / "tuning_log.csv")
        budget = self.meta["tuning_budget"]
        for (_, model), group in tune.groupby(["tag", "model"]):
            expected = 5 if model == "logit" else budget["rf_configs"] if model == "rf" else budget["configs_per_booster"]
            self.assertEqual(len(group), expected)

    def test_figures_match_current_tables(self):
        figures = OUT / "figures"
        for manifest, directory in (("source_table_hashes.csv", TAB), ("figure_hashes.csv", figures)):
            rows = pd.read_csv(figures / manifest)
            self.assertFalse(rows.empty)
            for r in rows.itertuples():
                self.assertEqual(r.md5, hashlib.md5((directory / r.file).read_bytes()).hexdigest(), r.file)
        alt = pd.read_csv(figures / "alt_text_manifest.csv")
        self.assertEqual(len(alt), 7)
        for r in alt.itertuples():
            self.assertTrue((OUT / r.file).is_file())
            self.assertGreater(len(r.alt_text), 40)
        self.assertEqual(len(pd.read_csv(figures / "figure_hashes.csv")), 7)

    def test_completed_run_repeatability(self):
        checks = json.loads((OUT / "repeatability_checks.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(len(checks), 5)
        for check in checks:
            self.assertTrue(check["exact_match"], check["file"])
            self.assertEqual(check["first_sha256"], check["final_sha256"])
            current = hashlib.sha256((TAB / check["file"]).read_bytes()).hexdigest().upper()
            self.assertEqual(check["final_sha256"], current)


if __name__ == "__main__":
    unittest.main(verbosity=2)
