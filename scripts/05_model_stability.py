"""Full-base, primary-only follow-up; never overwrites the original model tables."""
import os
for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[key] = "2"

import hashlib
import json
import sys
import time
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
import sklearn
import xgboost as xgb
from sklearn.compose import ColumnTransformer
from sklearn.impute import MissingIndicator, SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import brier_score_loss, log_loss, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, SplineTransformer

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "model_stability"
SEEDS = (20261104, 20261105, 20261106, 20261107)
CATS = ["age_band", "dev_status", "employment_status", "remote_work", "education",
        "role_family", "org_size", "ic_or_pm", "region"]
NUMS = ["years_code", "log_comp"]
EPS = 1e-6


def source_sha(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def partitions(d, outcome, seed, resample):
    eligible = d[d[outcome].notna()]
    fit = eligible.index[eligible.year == 2023].to_numpy()
    validation = eligible.index[eligible.year == 2024].to_numpy()
    tune, calibration = train_test_split(
        validation, test_size=0.5, stratify=d.loc[validation, outcome], random_state=seed)
    test = eligible.index[eligible.year == 2025].to_numpy()
    rng = np.random.default_rng(seed)
    if resample:
        # Partition original respondents first; duplicates cannot cross blocks.
        fit, tune, calibration = [
            rng.choice(ix, size=len(ix), replace=True) for ix in (fit, tune, calibration)]
    refit = np.concatenate([fit, tune])
    overlap = {
        "fit_calibration_overlap": len(set(refit) & set(calibration)),
        "test_fit_overlap": len(set(test) & set(refit)),
        "test_calibration_overlap": len(set(test) & set(calibration))}
    assert not any(overlap.values()), overlap
    for ix in (fit, tune, calibration, test):
        assert d.loc[ix, outcome].nunique() == 2, "Both outcome classes required"
    return fit, tune, calibration, refit, test, overlap


def logistic(C, X, y):
    transforms = [(c, OneHotEncoder(handle_unknown="ignore", min_frequency=30,
                                    sparse_output=False), [c]) for c in CATS]
    for c in NUMS:
        transforms.append((c, Pipeline([
            ("impute", SimpleImputer(strategy="median")),
            ("spline", SplineTransformer(n_knots=5, degree=3, knots="quantile",
                                         extrapolation="constant"))]), [c]))
        transforms.append((c + "_missing", MissingIndicator(features="all"), [c]))
    return Pipeline([("pre", ColumnTransformer(transforms)),
                     ("model", LogisticRegression(C=C, max_iter=3000))]).fit(X, y)


def configs(kind, rng):
    for _ in range(2):
        common = dict(learning_rate=float(rng.choice([.03, .05, .1])),
                      subsample=float(rng.choice([.7, .85, 1.])),
                      colsample_bytree=float(rng.choice([.6, .8, 1.])))
        if kind == "xgb":
            yield dict(common, max_depth=int(rng.choice([3, 4, 6, 8])),
                       min_child_weight=float(rng.choice([1, 5, 20, 50])),
                       reg_lambda=float(rng.choice([1, 5, 20])))
        else:
            yield dict(common, num_leaves=int(rng.choice([7, 15, 31, 63])),
                       min_child_samples=int(rng.choice([20, 50, 200, 500])),
                       subsample_freq=1, reg_lambda=float(rng.choice([0, 5, 20])),
                       cat_smooth=float(rng.choice([10, 50])))


def categorise(X, vocab):
    X = X.copy()
    for c, levels in vocab.items():
        X[c] = pd.Categorical(X[c], categories=levels)
    return X


def booster(kind, cfg, X, y, seed, rounds=350, validation=None):
    vocab = {c: sorted(X[c].unique()) for c in CATS}
    X = categorise(X, vocab)
    if kind == "xgb":
        model = xgb.XGBClassifier(
            n_estimators=rounds, tree_method="hist", enable_categorical=True,
            max_cat_to_onehot=1, eval_metric="logloss", random_state=seed, n_jobs=2,
            early_stopping_rounds=50 if validation is not None else None, **cfg)
        kwargs = dict(verbose=False)
    else:
        model = lgb.LGBMClassifier(n_estimators=rounds, random_state=seed,
                                   n_jobs=2, verbose=-1, **cfg)
        kwargs = {}
    if validation is not None:
        vx, vy = validation
        kwargs["eval_set"] = [(categorise(vx, vocab), vy)]
        if kind == "lgbm":
            kwargs["callbacks"] = [lgb.early_stopping(50, verbose=False)]
    model.fit(X, y, **kwargs)
    model._atlas_categories = vocab
    return model


def predict(model, X):
    if hasattr(model, "_atlas_categories"):
        X = categorise(X, model._atlas_categories)
    return model.predict_proba(X)[:, 1]


def platt(p, y):
    def logits(values):
        values = np.clip(values, EPS, 1 - EPS)
        return np.log(values / (1 - values)).reshape(-1, 1)
    model = LogisticRegression(C=1e6, max_iter=1000).fit(logits(p), y)
    return lambda values: model.predict_proba(logits(values))[:, 1]


def paired_interval(y, baseline, ensemble, seed, reps=200):
    rng = np.random.default_rng(seed)
    differences = []
    for _ in range(reps):
        ix = rng.integers(0, len(y), len(y))
        if np.unique(y[ix]).size < 2:
            continue
        differences.append([
            roc_auc_score(y[ix], ensemble[ix]) - roc_auc_score(y[ix], baseline[ix]),
            (log_loss(y[ix], ensemble[ix]) - log_loss(y[ix], baseline[ix]))
            / log_loss(y[ix], baseline[ix])])
    assert len(differences) >= .95 * reps
    bounds = np.quantile(differences, [.025, .975], axis=0)
    return dict(d_auc_lo=float(bounds[0, 0]), d_auc_hi=float(bounds[1, 0]),
                d_log_loss_rel_lo=float(bounds[0, 1]),
                d_log_loss_rel_hi=float(bounds[1, 1]))


def fit_run(d, outcome, seed, resample):
    fit, tune, cal, refit, test, overlap = partitions(d, outcome, seed, resample)
    X = d[CATS + NUMS]
    y = d[outcome].fillna(0).to_numpy(dtype=int)
    rng = np.random.default_rng(seed)
    models, tuning = {}, []
    candidates = []
    for C in [.003, .01, .03, .1, 1.]:
        model = logistic(C, X.loc[fit], y[fit])
        loss = log_loss(y[tune], predict(model, X.loc[tune]))
        candidates.append((loss, C))
        tuning.append(dict(model="logit", config={"C": C}, tuning_log_loss=float(loss)))
    models["logit"] = logistic(min(candidates)[1], X.loc[refit], y[refit])
    for kind in ("xgb", "lgbm"):
        candidates = []
        for cfg in configs(kind, rng):
            model = booster(kind, cfg, X.loc[fit], y[fit], seed,
                            validation=(X.loc[tune], y[tune]))
            rounds = int(model.best_iteration + 1 if kind == "xgb" else model.best_iteration_)
            loss = log_loss(y[tune], predict(model, X.loc[tune]))
            candidates.append((float(loss), cfg, rounds))
            tuning.append(dict(model=kind, config=dict(cfg, rounds=rounds),
                               tuning_log_loss=float(loss)))
        _, cfg, rounds = min(candidates, key=lambda row: row[0])
        models[kind] = booster(kind, cfg, X.loc[refit], y[refit], seed, rounds)
    cp = {name: predict(model, X.loc[cal]) for name, model in models.items()}
    tp = {name: predict(model, X.loc[test]) for name, model in models.items()}
    baseline = platt(cp["logit"], y[cal])(tp["logit"])
    ensemble = platt(np.mean(list(cp.values()), axis=0), y[cal])(
        np.mean(list(tp.values()), axis=0))
    yt = y[test]
    metrics = {}
    for name, p in (("logit_recal", baseline), ("ensemble", ensemble)):
        selected = p >= y[refit].mean()
        metrics[name] = dict(auc=float(roc_auc_score(yt, p)),
                             log_loss=float(log_loss(yt, p)),
                             brier=float(brier_score_loss(yt, p)),
                             calibration_gap=float(p.mean() - yt.mean()),
                             false_positive=int(np.sum(selected & (yt == 0))),
                             false_negative=int(np.sum(~selected & (yt == 1))))
    row = dict(outcome=outcome.removeprefix("y_"), seed=seed,
               training_bootstrap=resample, n_inner_fit=len(fit), n_tune=len(tune),
               n_calibration=len(cal), n_refit=len(refit),
               n_unique_refit=len(set(refit)), n_test=len(test), **overlap,
               d_auc=metrics["ensemble"]["auc"] - metrics["logit_recal"]["auc"],
               d_log_loss_rel=(metrics["ensemble"]["log_loss"] -
                              metrics["logit_recal"]["log_loss"]) / metrics["logit_recal"]["log_loss"],
               metrics=metrics, tuning=tuning)
    row.update(paired_interval(yt, baseline, ensemble, seed))
    return row


def verify(payload):
    runs = payload["runs"]
    assert len(runs) == 8
    for outcome in ("fav", "trust"):
        group = [r for r in runs if r["outcome"] == outcome]
        assert {r["seed"] for r in group} == set(SEEDS)
        assert sum(r["training_bootstrap"] for r in group) == 3
        assert len({r["n_test"] for r in group}) == 1
        for r in group:
            assert r["n_refit"] == r["n_inner_fit"] + r["n_tune"]
            assert r["n_unique_refit"] <= r["n_refit"]
            assert not any(r[k] for k in ("fit_calibration_overlap", "test_fit_overlap",
                                         "test_calibration_overlap"))
            assert r["n_unique_refit"] < r["n_refit"] if r["training_bootstrap"] else r["n_unique_refit"] == r["n_refit"]
            for m in r["metrics"].values():
                assert 0 <= m["auc"] <= 1 and 0 <= m["brier"] <= 1 and m["log_loss"] >= 0
    assert payload["meta"]["sample_fraction"] == 1
    assert payload["meta"]["script_sha256"] == source_sha(Path(__file__))


def main():
    if "--verify-only" in sys.argv:
        payload = json.loads((OUT / "summary.json").read_text(encoding="utf-8"))
        verify(payload)
        exported = json.loads((ROOT / "site_data" / "modelling.json").read_text(encoding="utf-8"))
        assert exported["primary_stability"] == payload
        print("Full-base model stability checks passed.")
        return
    started = time.monotonic()
    d = pd.read_parquet(ROOT / "data_clean" / "ai_harmonised.parquet")
    assert not d.duplicated(["year", "response_id"]).any()
    d = d[d.in_default_base & d.ai_user.eq(True) & d.year.isin([2023, 2024, 2025])].copy().reset_index(drop=True)
    for c in CATS:
        d[c] = d[c].astype("object").where(d[c].notna(), "Missing").astype(str)
    d["years_code"] = d.years_code.where(~d.qc_years_implausible.fillna(False).astype(bool))
    d["log_comp"] = np.log10(d.comp_usd_yearly.clip(1e3, 1e6))
    for c in NUMS:
        d[c] = d[c].astype(float)
    d["y_fav"] = d.ai_sent_favorable.astype(float)
    d["y_trust"] = d.ai_trust_any.astype(float)
    runs = []
    for outcome in ("y_fav", "y_trust"):
        for i, seed in enumerate(SEEDS):
            print(f"{outcome}: seed {seed}, training bootstrap={i > 0}", flush=True)
            runs.append(fit_run(d, outcome, seed, i > 0))
    summaries = []
    for outcome in ("fav", "trust"):
        group = [r for r in runs if r["outcome"] == outcome]
        summaries.append(dict(
            outcome=outcome, n_test=group[0]["n_test"],
            reference_d_auc=group[0]["d_auc"], reference_d_auc_lo=group[0]["d_auc_lo"],
            reference_d_auc_hi=group[0]["d_auc_hi"],
            d_auc_min=min(r["d_auc"] for r in group), d_auc_max=max(r["d_auc"] for r in group),
            d_log_loss_rel_min=min(r["d_log_loss_rel"] for r in group),
            d_log_loss_rel_max=max(r["d_log_loss_rel"] for r in group)))
    payload = dict(meta=dict(
        sample_fraction=1, seeds=list(SEEDS), full_pipeline_runs_per_outcome=4,
        training_bootstrap_refits_per_outcome=3, threads=2, conditional_test_bootstrap_reps=200,
        population="All default-base current AI users with observed outcome, 2023-2025; all default-base ages, not the adult-professional trend population.",
        design="Fit 2023; split 2024 original respondents into tuning/calibration before any within-block bootstrap; refit 2023+tuning; fixed 2025 test. Equal-weight logistic/XGB/LGBM ensemble and logistic both Platt-calibrated.",
        tuning="Five logistic C values; two seeded configurations per booster, up to 350 rounds, patience 50; validation log-loss only. Same bounded recipe, not an exhaustive algorithm search.",
        interpretation="Exploratory follow-up after observing the original results, not preregistered. Three full training-bootstrap refits vary fitting, tuning, partition and calibration; ranges are descriptive, not confidence intervals. Per-run paired test-bootstrap intervals condition on each fitted pipeline. No population, causal or equivalence claim.",
        source_hash_format="Source hashes normalise CRLF to LF; data hash uses exact bytes.",
        script_sha256=source_sha(Path(__file__)),
        original_script_sha256=source_sha(ROOT / "scripts" / "03_modelling.py"),
        data_sha256=hashlib.sha256((ROOT / "data_clean" / "ai_harmonised.parquet").read_bytes()).hexdigest(),
        versions={m.__name__: m.__version__ for m in (np, pd, sklearn, xgb, lgb)},
        elapsed_seconds=round(time.monotonic() - started, 1)),
        summary=summaries, runs=runs)
    verify(payload)
    OUT.mkdir(exist_ok=True, parents=True)
    (OUT / "summary.json").write_text(json.dumps(payload, indent=2, allow_nan=False), encoding="utf-8")
    pd.DataFrame(summaries).to_csv(OUT / "summary.csv", index=False, float_format="%.8f")
    public = ROOT / "site_data" / "modelling.json"
    exported = json.loads(public.read_text(encoding="utf-8"))
    exported["primary_stability"] = payload
    public.write_text(json.dumps(exported, separators=(",", ":"), allow_nan=False), encoding="utf-8")
    print(json.dumps(summaries, indent=2), flush=True)


if __name__ == "__main__":
    main()
