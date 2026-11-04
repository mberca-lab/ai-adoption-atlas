#!/usr/bin/env python
# =============================================================================
# AI Adoption Atlas -- 03_modelling.py   (modelling stream)
#
# Question: which developers are favourable toward / trust AI, and does
# advanced ML (random forest, XGBoost, LightGBM, ensemble) earn its place over a
# regularised logistic regression benchmark?
#
#   Input : data_clean/ai_harmonised.parquet  (respondent-level, gitignored)
#   Output: outputs/modelling/tables/*.csv     (AGGREGATES ONLY - never rows)
#           outputs/modelling/SESSION_INFO.txt
#           outputs/modelling/run_log.txt
#           site_data/modelling.json
#
# Run:  python scripts/03_modelling.py      (then scripts/03_modelling_figures.R,
#                                             then scripts/03_modelling_verify.py)
# Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., ODbL 1.0.
# =============================================================================
import hashlib, json, os, platform, sys, time, warnings
NJ = min(2, max(1, int(os.environ.get("NJOBS", "2"))))
os.environ.setdefault("OMP_WAIT_POLICY", "PASSIVE")
for thread_var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ[thread_var] = str(NJ)
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import rankdata
import sklearn, xgboost as xgb, lightgbm as lgb
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import MissingIndicator, SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, SplineTransformer

warnings.simplefilter("default")
SEED = 20261104
RNG = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "modelling"
TAB = OUT / "tables"
SITE = ROOT / "site_data"
for p in (OUT, TAB, SITE):
    p.mkdir(parents=True, exist_ok=True)
FAST = os.environ.get("FAST", "1") == "1"      # bounded exploratory mode by default
SAMPLE_FRACTION = float(os.environ.get("SAMPLE_FRACTION", "0.12" if FAST else "1"))
if not 0 < SAMPLE_FRACTION <= 1:
    raise ValueError("SAMPLE_FRACTION must be in (0, 1]")
B_MAIN = 200 if FAST else 1000                 # bootstrap reps, primary tests
B_SEC = 100 if FAST else 500                   # bootstrap reps, secondary tests
N_RANDOM = 2 if FAST else 10                   # random-search configs per GBM
N_STAB = 8 if FAST else 30                     # descriptive stability, not inferential CIs
N_TREES = 100 if FAST else 300
MAX_BOOST = 350 if FAST else 3000
N_SUB_BOOT = 100 if FAST else 200
MIN_CELL = 100                                 # suppress subgroup cells below this n
# Analyst-selected exploratory thresholds; no registered protocol.
MATTER_DAUC = 0.01          # >= +0.01 AUC with 95% CI excluding 0
MATTER_DLL_REL = 0.01       # >= 1% relative reduction in log-loss with CI excluding 0

LOG = open(OUT / "run_log.txt", "w", encoding="utf-8")
T0 = time.time()
def log(*a):
    s = f"[{time.time() - T0:7.1f}s] " + " ".join(str(x) for x in a)
    print(s, flush=True); LOG.write(s + "\n"); LOG.flush()

# ---- 1. Data & features -------------------------------------------------------
H = pd.read_parquet(ROOT / "data_clean" / "ai_harmonised.parquet")
assert not H.duplicated(["year", "response_id"]).any(), "Duplicate respondent/year keys"
H = H[H["in_default_base"]].copy()
BASE_N = len(H)
if SAMPLE_FRACTION < 1:
    H = H.sample(frac=SAMPLE_FRACTION, random_state=SEED)
H = H.reset_index(drop=True)
SAMPLED_N = len(H)
log("default base rows:", len(H))

CAT_D = ["age_band", "dev_status", "employment_status", "remote_work", "education",
         "role_family", "org_size", "ic_or_pm", "region"]
NUM_D = ["years_code", "log_comp"]
TASKS = ["aiw_writing_code", "aiw_debugging", "aiw_documenting", "aiw_testing",
         "aiw_learn_codebase", "aiw_review_code", "aiw_planning", "aiw_deployment"]

for c in CAT_D:
    H[c] = H[c].astype("object").where(H[c].notna(), "Missing").astype(str)
H["years_code"] = H["years_code"].where(~H["qc_years_implausible"].fillna(False).astype(bool))
# fixed (not data-derived) clipping of compensation -> no information from test rows
H["log_comp"] = np.log10(H["comp_usd_yearly"].clip(1e3, 1e6))
for c in TASKS:
    H[c] = H[c].astype("float")
H["n_ai_tasks"] = H[TASKS].sum(axis=1, min_count=1)
H["ai_threat_c"] = H["ai_threat"].astype("object").where(H["ai_threat"].notna(), "Missing").astype(str)
H["year_f"] = H["year"].astype(str)
H["country_g"] = H["country"].fillna("Missing")
H["exp_band"] = pd.cut(H["years_code"], [-1, 4, 9, 19, 100],
                       labels=["0-4 yrs", "5-9 yrs", "10-19 yrs", "20+ yrs"]).astype(str).replace("nan", "Missing")

# Outcomes
H["y_fav"] = H["ai_sent_favorable"].astype("float")               # Unsure counts as not favourable
H["y_trust"] = H["ai_trust_any"].astype("float")                  # Somewhat/Highly trust (2023-25)
t26 = H["ai_trust_raw"]
H["y_trust26"] = np.where(H["year"] != 2026, np.nan,
    np.where(t26.isna() | (t26 == "Not sure / I do not use AI tools"), np.nan,
             t26.isin(["I trust it for many tasks, but not important work decisions",
                       "I trust it for many tasks, including important work decisions"]).astype(float)))
H["y_use"] = H["ai_user"].astype("float")

FEATURE_SETS = {
    # D: demographics / work context only -- nothing downstream of AI attitudes
    "D": dict(cat=CAT_D, num=NUM_D),
    # B: + AI-usage behaviour (which tasks AI is used for); plausibly co-determined with attitude
    "B": dict(cat=CAT_D, num=NUM_D + TASKS + ["n_ai_tasks"]),
}
def ext_set(outcome):
    # E: + sibling AI-attitude items -> leakage-prone (consequences/correlates of the outcome)
    sib = ["ai_trust_5"] if outcome == "fav" else ["ai_sent_5"]
    return dict(cat=CAT_D + ["ai_threat_c"], num=NUM_D + TASKS + ["n_ai_tasks", "ai_complex_5"] + sib)

ALL_CATS = {c: sorted(H[c].unique().tolist()) for c in CAT_D + ["ai_threat_c", "year_f"]}

def make_X(df, fs, with_year):
    cats = fs["cat"] + (["year_f"] if with_year else [])
    X = df[cats + fs["num"]].copy()
    for c in cats:
        X[c] = pd.Categorical(X[c], categories=ALL_CATS[c])
    for c in fs["num"]:
        X[c] = X[c].astype(float)
    return X, cats, fs["num"]

def preproc(cats, nums, spline):
    tr = []
    for c in cats:
        tr.append((f"{c}|oh", OneHotEncoder(handle_unknown="ignore", min_frequency=30,
                                            sparse_output=False), [c]))
    for c in nums:
        cont = c in ("years_code", "log_comp")
        steps = [("imp", SimpleImputer(strategy="median"))]
        if spline and cont:
            steps.append(("sp", SplineTransformer(n_knots=5, degree=3, knots="quantile",
                                                  extrapolation="constant")))
        tr.append((f"{c}|val", Pipeline(steps), [c]))
        tr.append((f"{c}|miss", MissingIndicator(features="all"), [c]))
    return ColumnTransformer(tr, remainder="drop", verbose_feature_names_out=True)

def to_obj(X):
    X = X.copy()
    for c in X.columns:
        if isinstance(X[c].dtype, pd.CategoricalDtype):
            X[c] = X[c].astype(str)
    return X

# ---- 2. Metrics -----------------------------------------------------------------
EPS = 1e-6
def auc_fast(y, p):
    n1 = y.sum(); n0 = len(y) - n1
    if n1 == 0 or n0 == 0: return np.nan
    r = rankdata(p)
    return (r[y == 1].sum() - n1 * (n1 + 1) / 2) / (n1 * n0)
def logloss(y, p):
    p = np.clip(p, EPS, 1 - EPS); return -np.mean(y * np.log(p) + (1 - y) * np.log(1 - p))
def brier(y, p): return np.mean((p - y) ** 2)
def prauc(y, p): return average_precision_score(y, p) if 0 < y.sum() < len(y) else np.nan
METRICS = {"auc": auc_fast, "pr_auc": prauc, "log_loss": logloss, "brier": brier}

def probability_bins(p):
    # Do not split identical predictions across arbitrary rank-based bins.
    if np.ptp(p) < 1e-12:
        return pd.Series(np.zeros(len(p), dtype=int))
    return pd.qcut(pd.Series(p), 10, labels=False, duplicates="drop")

def calib_stats(y, p):
    lp = np.log(np.clip(p, EPS, 1 - EPS) / (1 - np.clip(p, EPS, 1 - EPS)))
    if np.std(lp) < 1e-9:
        slope, inter = np.nan, np.nan
    else:
        m = LogisticRegression(C=1e6, max_iter=1000).fit(lp.reshape(-1, 1), y)
        slope, inter = m.coef_[0, 0], m.intercept_[0]
    q = probability_bins(p)
    g = pd.DataFrame({"y": y, "p": p, "b": q}).groupby("b")
    ece = float((g.size() / len(y) * (g["y"].mean() - g["p"].mean()).abs()).sum())
    return dict(calib_slope=slope, calib_intercept=inter, ece=ece,
                mean_pred=float(np.mean(p)), observed=float(np.mean(y)))

def bootstrap(y, P, groups=None, B=1000, ref="logit", seed=SEED):
    """Percentile CIs for each model's metrics and paired differences vs `ref`.
    groups -> cluster (country) bootstrap."""
    rng = np.random.default_rng(seed)
    names = list(P)
    if groups is not None:
        codes, uniq = pd.factorize(groups)
        idx_by_g = [np.where(codes == k)[0] for k in range(len(uniq))]
    res = {m: {k: [] for k in METRICS} for m in names}
    for _ in range(B):
        if groups is None:
            ix = rng.integers(0, len(y), len(y))
        else:
            gs = rng.integers(0, len(idx_by_g), len(idx_by_g))
            ix = np.concatenate([idx_by_g[g] for g in gs])
        yb = y[ix]
        for m in names:
            pb = P[m][ix]
            for k, f in METRICS.items():
                res[m][k].append(f(yb, pb))
    rows, drows = [], []
    for m in names:
        r = {"model": m}
        for k, f in METRICS.items():
            arr = np.array(res[m][k], dtype=float)
            r[k] = f(y, P[m]); r[k + "_lo"], r[k + "_hi"] = np.nanpercentile(arr, [2.5, 97.5])
        rows.append(r)
        if m != ref and ref in P:
            d = {"model": m, "vs": ref}
            for k, f in METRICS.items():
                diff = np.array(res[m][k], float) - np.array(res[ref][k], float)
                d[f"d_{k}"] = f(y, P[m]) - f(y, P[ref])
                d[f"d_{k}_lo"], d[f"d_{k}_hi"] = np.nanpercentile(diff, [2.5, 97.5])
                d[f"bootstrap_fraction_{k}_improved"] = float(np.nanmean(diff > 0) if k in ("auc", "pr_auc") else np.nanmean(diff < 0))
            ll_ref = np.array(res[ref]["log_loss"], float)
            rel = (np.array(res[m]["log_loss"], float) - ll_ref) / ll_ref
            d["d_log_loss_rel"] = (logloss(y, P[m]) - logloss(y, P[ref])) / logloss(y, P[ref])
            d["d_log_loss_rel_lo"], d["d_log_loss_rel_hi"] = np.nanpercentile(rel, [2.5, 97.5])
            drows.append(d)
    return pd.DataFrame(rows), pd.DataFrame(drows)

# ---- 3. Model fitting with nested / time-aware tuning ----------------------------
def sample_cfgs(kind, n, rng):
    out = []
    for _ in range(n):
        if kind == "xgb":
            out.append(dict(learning_rate=rng.choice([0.03, 0.05, 0.1]), max_depth=int(rng.choice([3, 4, 6, 8])),
                            min_child_weight=float(rng.choice([1, 5, 20, 50])), subsample=float(rng.choice([0.7, 0.85, 1.0])),
                            colsample_bytree=float(rng.choice([0.6, 0.8, 1.0])), reg_lambda=float(rng.choice([1, 5, 20]))))
        else:
            out.append(dict(learning_rate=rng.choice([0.03, 0.05, 0.1]), num_leaves=int(rng.choice([7, 15, 31, 63])),
                            min_child_samples=int(rng.choice([20, 50, 200, 500])), subsample=float(rng.choice([0.7, 0.85, 1.0])),
                            subsample_freq=1, colsample_bytree=float(rng.choice([0.6, 0.8, 1.0])),
                            reg_lambda=float(rng.choice([0, 5, 20])), cat_smooth=float(rng.choice([10, 50]))))
    return out

def fit_categories(X):
    return {c: sorted(X[c].dropna().astype(str).unique())
            for c in X if isinstance(X[c].dtype, pd.CategoricalDtype)}

def align_categories(X, vocab):
    X = X.copy()
    for c, levels in vocab.items():
        X[c] = pd.Categorical(X[c], categories=levels)
    return X

def fit_xgb(cfg, Xtr, ytr, n_est, Xva=None, yva=None):
    vocab = fit_categories(Xtr)
    Xtr = align_categories(Xtr, vocab)
    m = xgb.XGBClassifier(n_estimators=n_est, tree_method="hist", enable_categorical=True,
                          max_cat_to_onehot=1, eval_metric="logloss", random_state=SEED, n_jobs=NJ,
                          early_stopping_rounds=50 if Xva is not None else None, **cfg)
    if Xva is not None:
        m.fit(Xtr, ytr, eval_set=[(align_categories(Xva, vocab), yva)], verbose=False)
    else:
        m.fit(Xtr, ytr, verbose=False)
    m._atlas_categories = vocab
    return m

def fit_lgb(cfg, Xtr, ytr, n_est, Xva=None, yva=None):
    vocab = fit_categories(Xtr)
    Xtr = align_categories(Xtr, vocab)
    m = lgb.LGBMClassifier(n_estimators=n_est, random_state=SEED, n_jobs=NJ, verbose=-1, **cfg)
    if Xva is not None:
        m.fit(Xtr, ytr, eval_set=[(align_categories(Xva, vocab), yva)], callbacks=[lgb.early_stopping(50, verbose=False)])
    else:
        m.fit(Xtr, ytr)
    m._atlas_categories = vocab
    return m

def fit_logit(C, Xtr, ytr, cats, nums):
    return Pipeline([("pre", preproc(cats, nums, spline=True)),
                     ("lr", LogisticRegression(C=C, max_iter=3000))]).fit(to_obj(Xtr), ytr)

def fit_rf(cfg, Xtr, ytr, cats, nums):
    return Pipeline([("pre", preproc(cats, nums, spline=False)),
                     ("rf", RandomForestClassifier(n_estimators=N_TREES, max_samples=0.6, n_jobs=NJ,
                                                   random_state=SEED, **cfg))]).fit(to_obj(Xtr), ytr)

def pr(m, X):
    if isinstance(m, Pipeline): return m.predict_proba(to_obj(X))[:, 1]
    return m.predict_proba(align_categories(X, m._atlas_categories))[:, 1]

def platt(p_val, y_val):
    lp = np.log(np.clip(p_val, EPS, 1 - EPS) / (1 - np.clip(p_val, EPS, 1 - EPS))).reshape(-1, 1)
    m = LogisticRegression(C=1e6, max_iter=1000).fit(lp, y_val)
    def f(p):
        l = np.log(np.clip(p, EPS, 1 - EPS) / (1 - np.clip(p, EPS, 1 - EPS))).reshape(-1, 1)
        return m.predict_proba(l)[:, 1]
    return f

def calibration_partition(Xva, yva):
    """Reserve independent calibration labels before any tuning."""
    tune, cal = train_test_split(np.arange(len(yva)), test_size=0.5,
                                random_state=SEED, stratify=yva)
    assert not set(Xva.index[tune]) & set(Xva.index[cal])
    return tune, cal

def train_all(Xin, yin, Xva, yva, Xfull, yfull, cats, nums, models, tag, tune_log):
    """Split validation into tuning/calibration, then refit excluding calibration."""
    tune_ix, cal_ix = calibration_partition(Xva, yva)
    Xcal, ycal = Xva.iloc[cal_ix], yva[cal_ix]
    keep = ~Xfull.index.isin(Xcal.index)
    Xfull, yfull = Xfull.loc[keep], yfull[keep]
    Xva, yva = Xva.iloc[tune_ix], yva[tune_ix]
    assert not set(Xfull.index) & set(Xcal.index)
    SPLIT_ROWS.append(dict(tag=tag, n_inner_fit=len(yin), n_tune=len(yva),
                           n_calibration=len(ycal), n_refit=len(yfull),
                           fit_calibration_overlap=0))
    rng = np.random.default_rng(SEED)
    fitted, val_pred = {}, {}
    if "logit" in models:
        best = None
        for C in [0.003, 0.01, 0.03, 0.1, 1.0]:
            m = fit_logit(C, Xin, yin, cats, nums); p = pr(m, Xva); ll = logloss(yva, p)
            tune_log.append(dict(tag=tag, model="logit", cfg=json.dumps({"C": C}), val_log_loss=ll, val_auc=auc_fast(yva, p)))
            if best is None or ll < best[0]: best = (ll, C, p)
        val_pred["logit"] = best[2]
        fitted["logit"] = fit_logit(best[1], Xfull, yfull, cats, nums)
    if "rf" in models:
        best = None
        cfgs = [dict(min_samples_leaf=20, max_features="sqrt"), dict(min_samples_leaf=50, max_features=0.3),
                dict(min_samples_leaf=5, max_features="sqrt")]
        for cfg in cfgs[: (2 if FAST else 3)]:
            m = fit_rf(cfg, Xin, yin, cats, nums); p = pr(m, Xva); ll = logloss(yva, p)
            tune_log.append(dict(tag=tag, model="rf", cfg=json.dumps(cfg), val_log_loss=ll, val_auc=auc_fast(yva, p)))
            if best is None or ll < best[0]: best = (ll, cfg, p)
        val_pred["rf"] = best[2]
        fitted["rf"] = fit_rf(best[1], Xfull, yfull, cats, nums)
    for kind, fitf in (("xgb", fit_xgb), ("lgbm", fit_lgb)):
        if kind not in models: continue
        best = None
        for cfg in sample_cfgs(kind, N_RANDOM, rng):
            m = fitf(cfg, Xin, yin, MAX_BOOST, Xva, yva)
            nbest = (m.best_iteration + 1) if kind == "xgb" else (m.best_iteration_ or MAX_BOOST)
            p = pr(m, Xva); ll = logloss(yva, p)
            tune_log.append(dict(tag=tag, model=kind, cfg=json.dumps({**cfg, "n_estimators": int(nbest)}, default=float),
                                 val_log_loss=ll, val_auc=auc_fast(yva, p)))
            if best is None or ll < best[0]: best = (ll, cfg, nbest, p)
        val_pred[kind] = best[3]
        n_final = int(best[2])
        fitted[kind] = fitf(best[1], Xfull, yfull, n_final)
        fitted[kind + "_cfg"] = {**best[1], "n_estimators": n_final}
    cal_pred = {k: pr(fitted[k], Xcal) for k in models}
    if all(k in cal_pred for k in ("logit", "xgb", "lgbm")):
        ens_val = np.mean([cal_pred[k] for k in ("logit", "xgb", "lgbm")], axis=0)
        fitted["ensemble_cal"] = platt(ens_val, ycal)
    # same Platt recalibration for single models -> separates "recalibration" gains from "complexity" gains
    for k in ("logit", "lgbm"):
        if k in cal_pred:
            fitted[k + "_platt"] = platt(cal_pred[k], ycal)
    fitted["_train_index"] = Xfull.index
    fitted["_calibration_n"] = len(ycal)
    return fitted

def predict_all(fitted, X, base_p):
    P = {"baseline": base_p}
    for k in ("logit", "rf", "xgb", "lgbm"):
        if k in fitted: P[k] = pr(fitted[k], X)
    if "ensemble_cal" in fitted:
        P["ensemble"] = fitted["ensemble_cal"](np.mean([P["logit"], P["xgb"], P["lgbm"]], axis=0))
    for k in ("logit", "lgbm"):
        if k + "_platt" in fitted:
            P[k + "_recal"] = fitted[k + "_platt"](P[k])
    return P

ALL_MODELS = ("logit", "rf", "xgb", "lgbm")
METRIC_ROWS, DIFF_ROWS, CALIB_ROWS, CALSTAT_ROWS, TUNE_LOG, SPLIT_ROWS = [], [], [], [], [], []
STORE = {}   # in-memory only (never written): test predictions for explanation/audit

def record(outcome, scheme, fset, y, P, groups, B, n_train, extra=None):
    met, dif = bootstrap(y, P, groups=groups, B=B)
    if "logit_recal" in P:   # like-for-like: recalibrated complex models vs recalibrated logit
        sub_p = {k: P[k] for k in ("logit_recal", "lgbm_recal", "ensemble") if k in P}
        _, dif2 = bootstrap(y, sub_p, groups=groups, B=B, ref="logit_recal")
        dif = pd.concat([dif, dif2], ignore_index=True)
    for df in (met, dif):
        df.insert(0, "feature_set", fset); df.insert(0, "scheme", scheme); df.insert(0, "outcome", outcome)
    met["n_train"] = n_train; met["n_test"] = len(y); met["prevalence_test"] = y.mean()
    for m, p in P.items():
        cs = calib_stats(y, p); cs.update(outcome=outcome, scheme=scheme, feature_set=fset, model=m)
        CALSTAT_ROWS.append(cs)
        if m == "baseline" and np.std(p) < 1e-12:
            continue
        q = probability_bins(p)
        g = pd.DataFrame({"y": y, "p": p, "b": q}).groupby("b")
        for b, gg in g:
            n, k = len(gg), gg["y"].sum(); z = 1.96; ph = k / n
            den = 1 + z * z / n; ctr = (ph + z * z / (2 * n)) / den
            half = z * np.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n)) / den
            CALIB_ROWS.append(dict(outcome=outcome, scheme=scheme, feature_set=fset, model=m, bin=int(b) + 1, n=n,
                                   mean_pred=gg["p"].mean(), observed=ph, obs_lo=ctr - half, obs_hi=ctr + half))
    METRIC_ROWS.append(met); DIFF_ROWS.append(dif)
    log(f"  {outcome}/{scheme}/{fset}: " + "; ".join(f"{r.model} AUC={r.auc:.3f} LL={r.log_loss:.4f}" for r in met.itertuples()))

# ---- 4. Experiments -------------------------------------------------------------------
def temporal(outcome, ycol, pop, train_years, val_year, test_year, fset_name, fs, models, B):
    d = pop[pop[ycol].notna()]
    tr, te = d[d.year.isin(train_years)], d[d.year == test_year]
    inner_tr = tr[tr.year != val_year]; inner_va = tr[tr.year == val_year]
    Xtr, cats, nums = make_X(tr, fs, with_year=False)
    Xin, _, _ = make_X(inner_tr, fs, False); Xva, _, _ = make_X(inner_va, fs, False)
    Xte, _, _ = make_X(te, fs, False)
    ytr, yin, yva, yte = (x[ycol].values.astype(int) for x in (tr, inner_tr, inner_va, te))
    tag = f"{outcome}|temporal_{''.join(str(y)[2:] for y in train_years)}to{str(test_year)[2:]}|{fset_name}"
    fitted = train_all(Xin, yin, Xva, yva, Xtr, ytr, cats, nums, models, tag, TUNE_LOG)
    fit_mask = Xtr.index.isin(fitted["_train_index"])
    Xtr, ytr = Xtr.loc[fit_mask], ytr[fit_mask]
    assert not set(Xtr.index) & set(Xte.index)
    SPLIT_ROWS[-1].update(n_test=len(yte), test_fit_overlap=0, test_calibration_overlap=0)
    P = predict_all(fitted, Xte, np.full(len(yte), ytr.mean()))
    scheme = tag.split("|")[1]
    record(outcome, scheme, fset_name, yte, P, None, B, len(ytr))
    STORE[(outcome, scheme, fset_name)] = dict(fitted=fitted, Xte=Xte, yte=yte, P=P, te=te, Xtr=Xtr, ytr=ytr,
                                              cats=cats, nums=nums)
    return fitted

def grouped_cv(outcome, ycol, pop, years, fset_name, fs, models, B, with_year=True, k=5):
    d = pop[pop[ycol].notna() & pop.year.isin(years)].reset_index(drop=True)
    X, cats, nums = make_X(d, fs, with_year=with_year)
    y = d[ycol].values.astype(int); g = d["country_g"].values
    oof, fold_train_ns = {}, []
    for f, (itr, ite) in enumerate(GroupKFold(n_splits=k).split(X, y, g)):
        gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED + f)
        a, b = next(gss.split(itr, groups=g[itr])); iin, iva = itr[a], itr[b]
        tag = f"{outcome}|groupcv_country|{fset_name}|fold{f + 1}"
        fitted = train_all(X.iloc[iin], y[iin], X.iloc[iva], y[iva], X.iloc[itr], y[itr], cats, nums, models, tag, TUNE_LOG)
        fit_ix = fitted["_train_index"].to_numpy()
        fold_train_ns.append(len(fit_ix))
        assert not set(g[itr]) & set(g[ite])
        SPLIT_ROWS[-1].update(n_test=len(ite), test_fit_overlap=0, test_calibration_overlap=0,
                             test_train_country_overlap=0)
        if with_year:   # naive baseline = year-specific mean from the training fold
            ym = pd.Series(y[fit_ix]).groupby(d["year"].values[fit_ix]).mean()
            base = d["year"].iloc[ite].map(ym).fillna(y[fit_ix].mean()).values
        else:
            base = np.full(len(ite), y[fit_ix].mean())
        P = predict_all(fitted, X.iloc[ite], base)
        for m, p in P.items():
            oof.setdefault(m, np.zeros(len(y)))[ite] = p
        log(f"    fold {f + 1}/{k} done (test n={len(ite)})")
    record(outcome, "groupcv_country", fset_name, y, oof, g, B, round(np.mean(fold_train_ns), 1))

users = H[H["ai_user"] == True]
pop_use = H[H.year <= 2025]

log("== O1 favourability: temporal 2023-24 -> 2025, all models, D ==")
temporal("fav", "y_fav", users, [2023, 2024], 2024, 2025, "D", FEATURE_SETS["D"], ALL_MODELS, B_MAIN)
log("== O2 trust: temporal 2023-24 -> 2025, all models, D ==")
temporal("trust", "y_trust", users, [2023, 2024], 2024, 2025, "D", FEATURE_SETS["D"], ALL_MODELS, B_MAIN)
log("== feature-set (leakage) comparison: logit vs lgbm, B and E ==")
for oc, yc in (("fav", "y_fav"), ("trust", "y_trust")):
    temporal(oc, yc, users, [2023, 2024], 2024, 2025, "B", FEATURE_SETS["B"], ("logit", "lgbm"), B_SEC)
    temporal(oc, yc, users, [2023, 2024], 2024, 2025, "E", ext_set(oc), ("logit", "lgbm"), B_SEC)
log("== O1 favourability: series-break test 2023-25 -> 2026, D ==")
temporal("fav", "y_fav", users, [2023, 2024, 2025], 2025, 2026, "D", FEATURE_SETS["D"], ALL_MODELS, B_SEC)
log("== O3 AI-use status: temporal 2023-24 -> 2025, D ==")
temporal("use", "y_use", pop_use, [2023, 2024], 2024, 2025, "D", FEATURE_SETS["D"], ALL_MODELS, B_SEC)
log("== Grouped (country) CV 2023-25 ==")
for oc, yc in (("fav", "y_fav"), ("trust", "y_trust")):
    grouped_cv(oc, yc, users, [2023, 2024, 2025], "D", FEATURE_SETS["D"], ALL_MODELS, B_SEC)
log("== O2b trust 2026 (conditional scale, broad trust): grouped CV within 2026 ==")
grouped_cv("trust26", "y_trust26", users, [2026], "D", FEATURE_SETS["D"], ALL_MODELS, B_SEC, with_year=False)

metrics = pd.concat(METRIC_ROWS, ignore_index=True)
diffs = pd.concat(DIFF_ROWS, ignore_index=True)
def verdict(r):
    auc_ok = r.d_auc >= MATTER_DAUC and r.d_auc_lo > 0
    ll_ok = -r.d_log_loss_rel >= MATTER_DLL_REL and r.d_log_loss_rel_hi < 0
    auc_bad = r.d_auc_hi < 0
    ll_bad = r.d_log_loss_rel_lo > 0
    if (r.d_auc_lo > 0 and ll_bad) or (r.d_log_loss_rel_hi < 0 and auc_bad):
        return "mixed exploratory metrics (trade-off)"
    if auc_ok or ll_ok: return "exploratory gain meets analyst threshold"
    if r.d_auc_lo > 0 or r.d_log_loss_rel_hi < 0: return "exploratory gain below analyst threshold"
    if r.d_auc_hi < 0 or r.d_log_loss_rel_lo > 0: return "exploratory evidence of worse performance"
    return "inconclusive (not evidence of equivalence)"
diffs["verdict"] = diffs.apply(verdict, axis=1)
metrics.to_csv(TAB / "model_metrics.csv", index=False, float_format="%.5f")
diffs.to_csv(TAB / "model_diff_vs_logit.csv", index=False, float_format="%.5f")
pd.DataFrame(CALIB_ROWS).to_csv(TAB / "calibration_bins.csv", index=False, float_format="%.5f")
pd.DataFrame(CALSTAT_ROWS).to_csv(TAB / "calibration_stats.csv", index=False, float_format="%.5f")
tl = pd.DataFrame(TUNE_LOG); tl.to_csv(TAB / "tuning_log.csv", index=False, float_format="%.5f")
pd.DataFrame(SPLIT_ROWS).to_csv(TAB / "split_audit.csv", index=False)
log("metrics written")

# ---- 5. Explanations (temporal D models) -------------------------------------------
FEAT_LABEL = {"age_band": "Age band", "dev_status": "Developer status", "employment_status": "Employment",
              "remote_work": "Remote/hybrid/in-person", "education": "Education", "role_family": "Role family",
              "org_size": "Organisation size", "ic_or_pm": "IC vs manager", "region": "Region",
              "years_code": "Years coding", "log_comp": "Compensation (log)"}

def lgb_shap(model, X):
    c = model.booster_.predict(align_categories(X, model._atlas_categories), pred_contrib=True)
    return pd.DataFrame(c[:, :-1], columns=X.columns)

def xgb_shap(model, X):
    dm = xgb.DMatrix(align_categories(X, model._atlas_categories), enable_categorical=True)
    c = model.get_booster().predict(dm, pred_contribs=True)
    return pd.DataFrame(c[:, :-1], columns=X.columns)

def logit_shap(pipe, X, Xbg):
    """Exact linear SHAP (log-odds), aggregated to original features."""
    pre, lr = pipe.named_steps["pre"], pipe.named_steps["lr"]
    Z = pre.transform(to_obj(X)); Zb = pre.transform(to_obj(Xbg)).mean(axis=0)
    contrib = (Z - Zb) * lr.coef_[0]
    orig = [n.split("|")[0] for n in pre.get_feature_names_out()]
    return pd.DataFrame(contrib, columns=orig).T.groupby(level=0).sum().T[X.columns]

def mean_abs(df): return df.abs().mean()

SHAP_ROWS, STAB_ROWS, YEAR_ROWS, PERM_ROWS, PDP_ROWS, COEF_ROWS = [], [], [], [], [], []
for oc in ("fav", "trust", "use"):
    S = STORE[(oc, "temporal_2324to25", "D")]
    fitted, Xte, yte, Xtr, ytr = S["fitted"], S["Xte"], S["yte"], S["Xtr"], S["ytr"]
    ix = RNG.choice(len(Xte), min(5000, len(Xte)), replace=False); Xs = Xte.iloc[ix]
    bg = Xtr.iloc[RNG.choice(len(Xtr), min(5000, len(Xtr)), replace=False)]
    imp = {"lgbm": mean_abs(lgb_shap(fitted["lgbm"], Xs)), "xgb": mean_abs(xgb_shap(fitted["xgb"], Xs)),
           "logit": mean_abs(logit_shap(fitted["logit"], Xs, bg))}
    for m, s in imp.items():
        for f, v in s.items():
            SHAP_ROWS.append(dict(outcome=oc, model=m, feature=f, label=FEAT_LABEL.get(f, f), mean_abs_shap=v,
                                  rank=int(s.rank(ascending=False)[f]), n_explained=len(Xs)))
    log(f"  SHAP {oc}: top lgbm =", list(imp["lgbm"].sort_values(ascending=False).index[:5]))

    # permutation importance on the full temporal test set (AUC drop), LR & LGBM
    for m in ("logit", "lgbm"):
        base_auc = auc_fast(yte, pr(fitted[m], Xte))
        for f in Xte.columns:
            drops = []
            for r in range(3 if FAST else 5):
                Xp = Xte.copy(); Xp[f] = Xp[f].sample(frac=1, random_state=SEED + r).values
                drops.append(base_auc - auc_fast(yte, pr(fitted[m], Xp)))
            PERM_ROWS.append(dict(outcome=oc, model=m, feature=f, label=FEAT_LABEL.get(f, f),
                                  auc_drop=np.mean(drops), auc_drop_sd=np.std(drops), n_test=len(yte)))
    if oc == "use":
        continue

    # bootstrap stability of top drivers: refit LGBM (fixed tuned cfg) and logit on bootstrap resamples
    cfg = fitted["lgbm_cfg"]; Cbest = fitted["logit"].named_steps["lr"].C
    xs_small = Xs.iloc[:2000]
    for b in range(N_STAB):
        bi = RNG.integers(0, len(Xtr), len(Xtr))
        mb = fit_lgb({k: v for k, v in cfg.items() if k != "n_estimators"},
                     Xtr.iloc[bi], ytr[bi], cfg["n_estimators"])
        lb = fit_logit(Cbest, Xtr.iloc[bi], ytr[bi], S["cats"], S["nums"])
        for m, s in (("lgbm", mean_abs(lgb_shap(mb, xs_small))), ("logit", mean_abs(logit_shap(lb, xs_small, bg.iloc[:2000])))):
            rk = s.rank(ascending=False)
            for f in s.index:
                STAB_ROWS.append(dict(outcome=oc, model=m, b=b, feature=f, mean_abs_shap=s[f], rank=rk[f]))
    log(f"  bootstrap stability {oc} done")

    # stability across survey years: within-year LGBM + logit (80/20 split), SHAP on the 20%
    yrs = [2023, 2024, 2025] + ([2026] if oc == "fav" else [])
    ycol = "y_fav" if oc == "fav" else "y_trust"
    for yr in yrs:
        dy = users[(users.year == yr) & users[ycol].notna()]
        Xy, cats, nums = make_X(dy, FEATURE_SETS["D"], False); yy = dy[ycol].values.astype(int)
        perm = RNG.permutation(len(dy)); cut = int(0.8 * len(dy)); a, b = perm[:cut], perm[cut:]
        my = fit_lgb({k: v for k, v in cfg.items() if k != "n_estimators"},
                     Xy.iloc[a], yy[a], cfg["n_estimators"])
        ly = fit_logit(Cbest, Xy.iloc[a], yy[a], cats, nums)
        hb = Xy.iloc[b]
        auc_l, auc_g = auc_fast(yy[b], pr(ly, hb)), auc_fast(yy[b], pr(my, hb))
        for m, s in (("lgbm", mean_abs(lgb_shap(my, hb))), ("logit", mean_abs(logit_shap(ly, hb, Xy.iloc[a[:5000]])))):
            rk = s.rank(ascending=False)
            for f in s.index:
                YEAR_ROWS.append(dict(outcome=oc, model=m, year=yr, feature=f, label=FEAT_LABEL.get(f, f),
                                      mean_abs_shap=s[f], rank=int(rk[f]), n_year=len(dy), prevalence=yy.mean(),
                                      holdout_auc=auc_l if m == "logit" else auc_g))
    log(f"  year stability {oc} done")

    # partial dependence (probability scale) on a 3,000-row test sample
    Xp0 = Xte.iloc[RNG.choice(len(Xte), min(3000, len(Xte)), replace=False)]
    for f in ["years_code", "age_band", "region", "role_family", "dev_status", "org_size", "remote_work", "ic_or_pm"]:
        if f == "years_code":
            grid = list(range(0, 41, 2))
        else:
            vc = S["te"][f].value_counts(); grid = [v for v in vc.index if vc[v] >= MIN_CELL and v != "Missing"]
        for v in grid:
            Xg = Xp0.copy()
            Xg[f] = float(v) if f == "years_code" else pd.Categorical([v] * len(Xg), categories=ALL_CATS[f])
            for m in ("logit", "lgbm"):
                PDP_ROWS.append(dict(outcome=oc, model=m, feature=f, label=FEAT_LABEL.get(f, f), value=str(v),
                                     value_num=float(v) if f == "years_code" else np.nan,
                                     mean_pred=float(pr(fitted[m], Xg).mean()),
                                     n_level_test=int((S["te"][f] == v).sum()) if f != "years_code" else int(((S["te"][f] - v).abs() <= 1).sum())))
    log(f"  PDP {oc} done")

    # Full one-hot coding + L2: exp(coef) is not a reference-category odds ratio.
    pre, lr = fitted["logit"].named_steps["pre"], fitted["logit"].named_steps["lr"]
    for n, c in zip(pre.get_feature_names_out(), lr.coef_[0]):
        if "|oh__" in n:
            f, lvl = n.split("|oh__")[0], n.split("|oh__")[1][len(n.split("|oh__")[0]) + 1:]
            COEF_ROWS.append(dict(outcome=oc, feature=f, level=lvl, coef=c,
                                  exp_penalized_coefficient=np.exp(c), C=lr.C))

pd.DataFrame(SHAP_ROWS).to_csv(TAB / "shap_importance.csv", index=False, float_format="%.5f")
stab = pd.DataFrame(STAB_ROWS)
stab_sum = stab.groupby(["outcome", "model", "feature"]).agg(
    mean_abs_shap=("mean_abs_shap", "mean"), shap_lo=("mean_abs_shap", lambda x: np.percentile(x, 2.5)),
    shap_hi=("mean_abs_shap", lambda x: np.percentile(x, 97.5)), mean_rank=("rank", "mean"),
    rank_lo=("rank", lambda x: np.percentile(x, 2.5)), rank_hi=("rank", lambda x: np.percentile(x, 97.5)),
    p_top3=("rank", lambda x: np.mean(x <= 3)), p_top5=("rank", lambda x: np.mean(x <= 5)),
    n_boot=("b", "nunique")).reset_index()
stab_sum["label"] = stab_sum["feature"].map(FEAT_LABEL)
stab_sum["feature_set"] = "D"
stab_sum["scheme"] = "temporal_2324to25"
stab_sum.to_csv(TAB / "driver_stability_bootstrap.csv", index=False, float_format="%.4f")
yr_df = pd.DataFrame(YEAR_ROWS); yr_df.to_csv(TAB / "driver_stability_years.csv", index=False, float_format="%.5f")
pd.DataFrame(PERM_ROWS).to_csv(TAB / "permutation_importance.csv", index=False, float_format="%.5f")
pd.DataFrame(PDP_ROWS).to_csv(TAB / "partial_dependence.csv", index=False, float_format="%.5f")
pd.DataFrame(COEF_ROWS).to_csv(TAB / "logit_penalized_coefficients.csv", index=False, float_format="%.5f")
(TAB / "logit_odds_ratios.csv").unlink(missing_ok=True)

# rank agreement between models / years (Spearman of mean |SHAP|)
agree = []
sh = pd.DataFrame(SHAP_ROWS)
for oc in sh.outcome.unique():
    w = sh[sh.outcome == oc].pivot(index="feature", columns="model", values="mean_abs_shap")
    for a_, b_ in (("lgbm", "xgb"), ("lgbm", "logit"), ("xgb", "logit")):
        agree.append(dict(outcome=oc, comparison=f"{a_} vs {b_} (temporal test)", spearman=w[a_].rank().corr(w[b_].rank())))
for (oc, m), g in yr_df.groupby(["outcome", "model"]):
    w = g.pivot(index="feature", columns="year", values="mean_abs_shap")
    cs = w.rank().corr().values[np.triu_indices(w.shape[1], 1)]
    agree.append(dict(outcome=oc, comparison=f"{m}: across years (min pairwise)", spearman=cs.min()))
    agree.append(dict(outcome=oc, comparison=f"{m}: across years (mean pairwise)", spearman=cs.mean()))
pd.DataFrame(agree).to_csv(TAB / "driver_rank_agreement.csv", index=False, float_format="%.4f")
log("explanations written")

# ---- 6. Subgroup audit & fairness-style check (temporal test year 2025) ------------------
SUB_ROWS, FAIR_ROWS = [], []
rng = np.random.default_rng(SEED + 7)
for oc in ("fav", "trust"):
    S = STORE[(oc, "temporal_2324to25", "D")]; te, yte, P = S["te"], S["yte"], S["P"]
    thr = S["ytr"].mean()   # decision threshold = training prevalence (documented choice)
    for dim in ("exp_band", "role_family", "region", "age_band"):
        for lvl, idx in te.reset_index(drop=True).groupby(dim).groups.items():
            idx = np.asarray(idx)
            if len(idx) < MIN_CELL: continue
            yy = yte[idx]
            row = dict(outcome=oc, dimension=dim, group=lvl, n=len(idx), prevalence=yy.mean())
            boots = {m: [] for m in ("logit", "lgbm")}
            for _ in range(N_SUB_BOOT):
                bi = rng.integers(0, len(idx), len(idx))
                for m in boots: boots[m].append(auc_fast(yy[bi], P[m][idx][bi]))
            for m in ("logit", "lgbm", "ensemble"):
                pp = P[m][idx]
                row[f"auc_{m}"] = auc_fast(yy, pp); row[f"brier_{m}"] = brier(yy, pp)
                row[f"calib_gap_{m}"] = pp.mean() - yy.mean()
            for m in boots:
                a = np.array(boots[m]); row[f"auc_{m}_lo"], row[f"auc_{m}_hi"] = np.nanpercentile(a, [2.5, 97.5])
            d = np.array(boots["lgbm"]) - np.array(boots["logit"])
            row["d_auc_lgbm_vs_logit"] = row["auc_lgbm"] - row["auc_logit"]
            row["d_auc_lo"], row["d_auc_hi"] = np.nanpercentile(d, [2.5, 97.5])
            for m in ("logit", "lgbm"):
                pp = P[m][idx] >= thr
                row[f"fp_{m}"] = int(np.sum(pp & (yy == 0)))
                row[f"fn_{m}"] = int(np.sum(~pp & (yy == 1)))
            SUB_ROWS.append(row)
            for m in ("logit", "lgbm"):
                pp = P[m][idx]; pos = pp >= thr
                FAIR_ROWS.append(dict(outcome=oc, dimension=dim, group=lvl, model=m, n=len(idx), threshold=thr,
                                      selection_rate=pos.mean(), observed_rate=yy.mean(),
                                      tpr=pos[yy == 1].mean() if (yy == 1).sum() else np.nan,
                                      fpr=pos[yy == 0].mean() if (yy == 0).sum() else np.nan,
                                      calib_gap=pp.mean() - yy.mean()))
sub = pd.DataFrame(SUB_ROWS); sub.to_csv(TAB / "subgroup_audit.csv", index=False, float_format="%.5f")
fair = pd.DataFrame(FAIR_ROWS); fair.to_csv(TAB / "fairness_check.csv", index=False, float_format="%.5f")
fair_sum = fair.groupby(["outcome", "dimension", "model"]).agg(
    n_groups=("group", "size"), tpr_gap=("tpr", lambda x: x.max() - x.min()),
    fpr_gap=("fpr", lambda x: x.max() - x.min()), selection_gap=("selection_rate", lambda x: x.max() - x.min()),
    max_abs_calib_gap=("calib_gap", lambda x: x.abs().max())).reset_index()
auc_gap = sub.groupby(["outcome", "dimension"]).agg(auc_gap_logit=("auc_logit", lambda x: x.max() - x.min()),
                                                     auc_gap_lgbm=("auc_lgbm", lambda x: x.max() - x.min())).reset_index()
fair_sum.to_csv(TAB / "fairness_summary.csv", index=False, float_format="%.5f")
auc_gap.to_csv(TAB / "subgroup_auc_gaps.csv", index=False, float_format="%.5f")

# sample sizes by outcome / year (aggregate)
ns = []
for oc, yc, pop in (("fav", "y_fav", users), ("trust", "y_trust", users), ("trust26", "y_trust26", users), ("use", "y_use", H)):
    g = pop[pop[yc].notna()].groupby("year")[yc].agg(["size", "mean"]).reset_index()
    for r in g.itertuples(): ns.append(dict(outcome=oc, year=r.year, n=r.size, prevalence=r.mean))
pd.DataFrame(ns).to_csv(TAB / "sample_sizes.csv", index=False, float_format="%.5f")
log("audit written")

# ---- 7. site_data/modelling.json (compact aggregates for charts) ------------------------
def rnd(x, k=4):
    if isinstance(x, (float, np.floating)): return None if np.isnan(x) else round(float(x), k)
    if isinstance(x, (np.integer,)): return int(x)
    return x
def recs(df, cols): return [{c: rnd(v) for c, v in zip(cols, r)} for r in df[cols].itertuples(index=False)]

cb = pd.DataFrame(CALIB_ROWS)
js = dict(
    meta=dict(title="AI Adoption Atlas - who favours and trusts AI, and does complex ML earn its place?",
              attribution="Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., licensed under ODbL 1.0 (https://opendatacommons.org/licenses/odbl/1-0/; https://survey.stackoverflow.co/).",
              seed=SEED, generated=time.strftime("%Y-%m-%d"), unweighted=True,
              analysis_mode="exploratory_deterministic_subsample" if SAMPLE_FRACTION < 1 else "exploratory_full_data",
              analysis_note=f"Exploratory deterministic {SAMPLE_FRACTION:.0%} subsample ({SAMPLED_N:,}/{BASE_N:,} rows); "
                            f"{B_MAIN}/{B_SEC} fixed-prediction metric bootstrap resamples; "
                            f"{N_STAB} driver refits (descriptive ranges, not CIs); "
                            f"{N_RANDOM} configurations per booster. Separate tuning/calibration; no test-label fitting. "
                            "Analyst-selected thresholds, no preregistration or multiplicity correction.",
              sample_fraction=SAMPLE_FRACTION, realized_sample_fraction=SAMPLED_N / BASE_N,
              default_base_n=BASE_N, sampled_base_n=SAMPLED_N, threads=NJ,
              sampling="pandas sample without replacement, fixed seed; before outcome filtering; all default-base ages retained",
              bootstrap=dict(primary_metric_reps=B_MAIN, secondary_metric_reps=B_SEC,
                             subgroup_metric_reps=N_SUB_BOOT, stability_refits=N_STAB,
                             metric_model_refits=0, driver_interval="descriptive 2.5/97.5 percentiles of only these refits; not a confidence interval",
                             metric_scope="paired fixed-prediction percentile intervals; respondent resampling for temporal tests, country clusters for grouped CV; conditional on fitted models and selected sample",
                             multiplicity_adjusted=False, p_values=False),
              tuning_budget=dict(logit_C=[0.003, 0.01, 0.03, 0.1, 1.0],
                                 rf_configs=2 if FAST else 3, rf_trees=N_TREES,
                                 configs_per_booster=N_RANDOM, max_boost_rounds=MAX_BOOST,
                                 early_stopping_patience=50, objective="validation log-loss",
                                 boost_refit_rounds="selected best iteration; no test-based adjustment"),
              calibration="Split validation year/country holdout 50:50, stratified by outcome: tune on first half, reserve second half. Refit excludes calibration rows. Fit Platt on predictions of final refit, never test labels. Equal-weight logistic/XGB/LGBM ensemble.",
              split_audit="outputs/modelling/tables/split_audit.csv; grouped n_train is mean actual per-fold refit size",
              exploratory_thresholds=True, preregistered=False,
              limitations=["Self-selected unweighted survey; not population estimates or causal effects.",
                           "Repeated cross-sections, not tracked people; no deployment or individual decisions.",
                           "2026 sentiment/trust measurement break; trust26 is separate, not a trend.",
                           "B tasks and E sibling attitudes are contemporaneous, leakage-prone correlates; D is primary.",
                           "Many comparisons, no multiplicity correction; no superiority/equivalence claim.",
                           "Calibration may drift across years; grouped CV pools years and is not future forecasting.",
                           "Small tuning and refit budgets; driver ranges are descriptive, not inferential CIs."],
              data_sha256=hashlib.sha256((ROOT / "data_clean" / "ai_harmonised.parquet").read_bytes()).hexdigest(),
              script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              outcomes={"fav": "AI favourable (Very/Favorable vs rest incl. Unsure), AI users 2023-26",
                        "trust": "Trusts AI accuracy (Somewhat/Highly trust vs rest), AI users 2023-25",
                        "trust26": "2026 conditional trust: trusts AI for many tasks vs narrower/no trust (different scale)",
                        "use": "Uses AI tools vs not (2023-25; 2025 definition CC)"},
              feature_sets={"D": "demographics/context only", "B": "D + AI-usage tasks", "E": "B + sibling AI-attitude items (leakage-prone)"},
              margin_that_matters=dict(d_auc=MATTER_DAUC, rel_log_loss=MATTER_DLL_REL),
              sample_sizes=recs(pd.DataFrame(ns), ["outcome", "year", "n", "prevalence"])),
    model_metrics=recs(metrics, ["outcome", "scheme", "feature_set", "model", "n_train", "n_test", "prevalence_test",
                                 "auc", "auc_lo", "auc_hi", "pr_auc", "pr_auc_lo", "pr_auc_hi", "log_loss", "log_loss_lo",
                                 "log_loss_hi", "brier", "brier_lo", "brier_hi"]),
    diff_vs_logit=recs(diffs, ["outcome", "scheme", "feature_set", "model", "vs", "d_auc", "d_auc_lo", "d_auc_hi",
                               "d_log_loss", "d_log_loss_lo", "d_log_loss_hi", "d_log_loss_rel",
                               "d_log_loss_rel_lo", "d_log_loss_rel_hi", "d_brier", "d_brier_lo",
                               "d_brier_hi", "verdict"]),
    calibration_bins=recs(cb[(cb.scheme == "temporal_2324to25") & (cb.feature_set == "D") & cb.outcome.isin(["fav", "trust"])],
                          ["outcome", "scheme", "feature_set", "model", "bin", "n", "mean_pred", "observed", "obs_lo", "obs_hi"]),
    shap_drivers=recs(stab_sum.sort_values(["outcome", "model", "mean_rank"]),
                      ["outcome", "scheme", "feature_set", "model", "feature", "label", "mean_abs_shap", "shap_lo", "shap_hi", "mean_rank",
                       "rank_lo", "rank_hi", "p_top3", "p_top5", "n_boot"]),
    driver_ranks_by_year=recs(yr_df, ["outcome", "model", "year", "feature", "rank", "mean_abs_shap", "n_year", "holdout_auc"]),
    partial_dependence=recs(pd.DataFrame(PDP_ROWS), ["outcome", "model", "feature", "value", "mean_pred", "n_level_test"]),
    subgroup_audit=recs(sub, ["outcome", "dimension", "group", "n", "prevalence", "auc_logit", "auc_lgbm",
                              "d_auc_lgbm_vs_logit", "d_auc_lo", "d_auc_hi", "calib_gap_logit", "calib_gap_lgbm"]),
)
with open(SITE / "modelling.json", "w", encoding="utf-8") as fh:
    json.dump(js, fh, separators=(",", ":"), allow_nan=False)
with open(OUT / "run_metadata.json", "w", encoding="utf-8") as fh:
    json.dump(js["meta"], fh, indent=2, allow_nan=False)
pd.DataFrame([dict(sample_fraction=SAMPLE_FRACTION, sampled_base_n=SAMPLED_N,
                   primary_reps=B_MAIN, secondary_reps=B_SEC, stability_refits=N_STAB,
                   seed=SEED)]).to_csv(TAB / "run_metadata.csv", index=False)
log("site_data/modelling.json written")

# ---- 8. Session info ------------------------------------------------------------------------
with open(OUT / "SESSION_INFO.txt", "w", encoding="utf-8") as fh:
    fh.write("AI Adoption Atlas - modelling stream session info\n")
    fh.write(f"run date: {time.strftime('%Y-%m-%d %H:%M')}\nseed: {SEED}\nFAST mode: {FAST}\nsample fraction: {SAMPLE_FRACTION}\n")
    fh.write(f"bootstrap reps: primary={B_MAIN}, secondary={B_SEC}; random-search configs/GBM={N_RANDOM}; stability refits={N_STAB}; threads={NJ}\n\n")
    fh.write(f"[python]\n{sys.version}\nplatform: {platform.platform()}\n")
    for m in (np, pd, sklearn, xgb, lgb):
        fh.write(f"{m.__name__} {m.__version__}\n")
    import scipy, pyarrow; fh.write(f"scipy {scipy.__version__}\npyarrow {pyarrow.__version__}\n")
log("done; total minutes:", round((time.time() - T0) / 60, 1))
