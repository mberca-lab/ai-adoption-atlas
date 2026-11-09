# AI, in Practice

**Developers are adopting AI at speed. Do they trust what they use?**

[Explore the interactive story](https://mberca-lab.github.io/ai-adoption-atlas/) |
[Trust and trends](outputs/trust_trends/FINDINGS.md) |
[Model comparison](outputs/modelling/FINDINGS.md) |
[Segments and tool baskets](outputs/segments/FINDINGS.md)

An independent, AI-assisted public-data learning and showcase project by Margarita Bermejo Cano.
The story follows four Stack Overflow Developer Survey waves through a living particle field,
interactive trends, experience matrices, developer profiles, model comparisons and tool networks.
It is not affiliated with Stack Overflow or a claim of impact at an employer.

## What the evidence says

Among professional respondents who answered the AI module, reported use rose from **44.1% (2023)**
to **80.8% (2025)**. Among current AI users, trust in accuracy fell from **46.2%** to **38.4%**.
Those are different denominators, not a numerical "trust gap".
Using a common denominator, professional respondents who both use AI and distrust its accuracy
increased from **11.0%** to **30.6%**.

That does **not** show that individuals lost trust as they adopted AI: each year surveys different
people. Selection matters, too. Only 76.9% of eligible professionals reached the AI question in
2025, and worst-case dropout bounds for the 2024-2025 adoption change include zero.
2026 uses redesigned questions and is shown as a **separate series**, not another trend point.

The modelling and segmentation chapters ask whether more complexity earns its place.
Their populations and computational budgets differ from the full professional-developer trends;
read the linked findings before quoting their results. All thresholds are analyst choices,
not an externally preregistered protocol.

The scoped analytical follow-up adds a pinned source/population audit, an adjusted 2025
frequency–trust comparison and full-base repeated primary model comparisons. Adjusted trust is
**47.2% for daily users vs 16.2% for monthly/infrequent users** (difference **31.0 pp**,
95% model-based interval **[29.4, 32.5] pp**). This is an association, not a causal effect.
The full-base reference trust comparison finds a **small detectable ensemble advantage**
(ΔAUC **0.00265**, conditional 95% interval **[0.00096, 0.00415]**), still below the analyst-set
**0.01** practical benchmark. Three training-bootstrap refits support a similarly small gain;
their range is descriptive, not a confidence interval. The original subset charts are retained
and explicitly distinguished from this follow-up.

## Explore without installing anything

The [published story](https://mberca-lab.github.io/ai-adoption-atlas/) is a static website.
It includes keyboard-operable controls, accessible data tables, light/dark themes, print styles,
and reduced-motion support. Charts load only the checked aggregate JSON exports.
Missing or malformed results produce an explicit error, never silently invented findings.
The optional `?demo=1` development mode is labelled illustrative and is not the published default.
No analytics, trackers, cookies, or external runtime dependencies are used.

## Evidence and source boundaries

| Location | Contents |
|---|---|
| `docs/DATA_NOTES.md` | Official sources, hashes, inclusion rules, unresolved discrepancies and limitations |
| `docs/CODEBOOK_AI.md` and `docs/codebook_ai.csv` | Question-level harmonisation and comparability decisions |
| `docs/tables/` | Aggregate data-quality profiles |
| `outputs/trust_trends/` | Full professional-developer trends, models, sensitivity analyses and figures |
| `outputs/modelling/` | Exploratory predictive model comparison and diagnostics |
| `outputs/trust_followup/` | Pinned source audit, population flow, adjusted frequency estimates and sensitivity |
| `outputs/model_stability/` | Full-base primary comparisons with repeated tuning/refitting/calibration |
| `outputs/segments/` | Exploratory segmentation and within-year association rules |
| `site_data/` | Aggregate JSON exports, mirrored to `site/data/` for publication |
| `site/` | Self-hosted D3 scrollytelling site; no build step |

Only public-source **aggregates** are committed. Raw files, respondent-level derivatives,
fitted-model caches and local run logs are excluded. Demographics are used descriptively,
not to score or target individuals. These models are not production decision systems.

## Reproduce the analysis

Use the [official survey archive](https://github.com/StackExchange/Survey/tree/main/packages/archive).
Place results and schemas in `data_raw/` with the exact filenames listed in
`scripts/01_harmonise.R` (`RAWFILES`). The harmoniser checks SHA-256, shapes and signature columns.
Do not substitute a newer archive version without recording and investigating the change.

R packages: `data.table`, `arrow`, `countrycode`, `digest`, `jsonlite`, `ggplot2`, `scales`,
`lme4`, `ordinal`, `MASS`, `poLCA`, `mclust`, `arules`. Stream-specific environment details and budgets
are recorded beside their findings. Python dependencies are listed in `requirements.txt`;
browser QA uses `requirements-dev.txt`.

Run from the repository root, using an R installation with these packages:

```powershell
Rscript scripts\01_harmonise.R
Rscript scripts\02_trust_trends.R
Rscript scripts\02_trust_trends_figs.R
Rscript scripts\02_trust_trends_verify.R
```

Predictive modelling and segmentation have separate reproduction commands in their
`FINDINGS.md` files. Large bootstrap/model-search budgets can be slow; do not describe
a smoke test or a subset analysis as a full-data run.

After generating the original trust and model exports, run these follow-ups **last**, before
copying data to the site. They add sections without replacing the original exploratory results:

```powershell
Rscript scripts\05_trust_followup.R
python scripts\05_model_stability.py
Rscript scripts\05_trust_followup.R --verify-only
python scripts\05_model_stability.py --verify-only
python -B -m unittest discover -s tests -p test_followup.py
```

The source audit requires authenticated `gh` access to the public publisher repository and access
to the official methodology page. It verifies large local files but fetches only small upstream
Git LFS pointers, not the survey data again. The model follow-up uses all eligible outcome rows,
two threads and a bounded search. Details and limits are in each follow-up's `FINDINGS.md`.
Rerunning an original export generator removes its nested follow-up; rerun the corresponding
follow-up afterwards. Release checks reject missing, stale or mismatched follow-up evidence.

## Preview and check the story

```powershell
powershell -File site\tools\copy-data.ps1
python scripts\check_release.py
node --test tests\data_adapter.test.cjs
python -m pip install -r requirements-dev.txt
python -m playwright install chromium
python site\tools\qa.py
python -m http.server 8000 --bind 127.0.0.1 --directory site
```

Open `http://127.0.0.1:8000/`. Serving the site is necessary; `file://` cannot load JSON.
Browser QA checks every chapter at desktop/mobile sizes, dark/reduced-motion variants,
keyboard interactions, real-data status, missing-data failure, and console errors.
GitHub Actions runs the lightweight release checks and data-adapter tests.
Browser QA runs locally with the command above. Hosting uses GitHub's built-in
Pages publishing from `gh-pages`, without a custom deployment pipeline.
After checking a website update, publish **only `site/`** from the repository root:

```powershell
$snapshot = git subtree split --prefix=site
git push origin "${snapshot}:gh-pages"
```

Raw data and analysis outputs outside the website are never included in that branch.

## Limits

Unweighted, self-selected, English-language developer surveys are not population estimates.
Intervals describe model/sampling variation, not non-response or selection bias.
Country and role coverage change over time. Within-year tool lists and segment profiles
are not interchangeable across survey years. Associations, SHAP values and predictive accuracy
are not causal evidence. Source discrepancies still under investigation are documented,
not silently reconciled.

## Licence and attribution

Data: **Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc.**, licensed under the
[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/);
individual database contents under the
[Database Contents License](https://opendatacommons.org/licenses/dbcl/1-0/).
The aggregate data exports retain this attribution and ODbL notice.
Raw and respondent-level data are **not** redistributed.
