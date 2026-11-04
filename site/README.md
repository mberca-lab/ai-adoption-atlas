# AI Adoption Atlas: front end

This is a static, scroll-driven data story. There is no build step, it uses no CDN and no tracking, and every path is relative, so it is ready for GitHub Pages.

## Preview
To preview it locally, serve from the project root so that both `site/data/` and `../site_data/` resolve:

```powershell
cd ai-adoption-atlas
python -m http.server 8000
# open http://localhost:8000/site/index.html
```

Opening `index.html` straight from disk (`file://`) blocks result loading. Serve it over HTTP.
Missing or malformed analysis exports fail closed with a visible error; they never silently become invented results.
Only explicit `?demo=1` development mode permits labelled illustrative fixtures.

### Debug URL parameters

| Parameter | Effect |
|---|---|
| `?chapter=0..7` | Jump to a chapter |
| `?step=2023\|2024\|2025\|2026` | Centre an adoption-wave step |
| `?theme=dark\|light` or `?scoutTheme=dark\|light` | Force the theme. The toggle saves the choice in `localStorage` under `atlas-theme`. |
| `?demo=1` | Permit clearly labelled illustrative fallbacks for development only. |
| `?motion=reduce` | Static mode, the same as `prefers-reduced-motion` |

## Wiring the real numbers
1. The analysis writes `site_data/trust_trends.json`, `modelling.json` and `segments.json`.
2. Run `powershell -File site\tools\copy-data.ps1`. It requires all three exports, rejects illustrative or unfinished results, copies them to `site/data/` and writes `site/data/manifest.json`.
3. Reload the page.

`js/data.js` is the **only** place numbers come from.
- **Missing files:** normal publication fails closed. In explicit development demo mode only, missing sections fall back to `DEV_FIXTURES`, with a global warning and a hatched badge on every affected chart.
- **Tolerant normalisers:** they accept proportions as 0–1 or 0–100, long or wide formats, and several alias keys.
- **trust_trends.json:** two shapes are supported:
  - the current wide shape: `series:[{name, series_group, labels, values, ci_low, ci_high, n}]`, with names `<o>_raw_2023_2025`, `<o>_raw_2026`, `<o>_standardised` and `<o>_by_experience_<band>`.
  - long tables: `raw_by_year`, `standardised_by_year` and `experience_gradient`.
- **modelling.json:** the schema written by `scripts/03_modelling.py`, which includes `model_metrics`, `diff_vs_logit` (with `vs`), `calibration_bins` and `shap_drivers`.
- **segments.json**: the normaliser expects
  - `classes:[{id,label,share,share_lo,share_hi,n,description,trust_pct,fav_pct,profile:[{label,value}]}]`
  - `rules:[{basket|year, lhs|a|source, rhs|b|target, lift, lift_lo, lift_hi, support, confidence}]`; arules-style strings `"{A,B} => {C}"` also work.
  - `items:[{item, vendor, support, basket}]`
  - `meta.status` set to `"final"` only after validation, plus population and computational-budget notes.
  - Higher-order rules are retained in the analysis tables, not projected onto pairwise network edges with misleading lift values.

## Copy
All narrative text is in `js/story.js`, with `{{placeholders}}` filled from `Atlas.data.facts`. Those facts are derived in `deriveFacts()` in `data.js`.
- **Available keys:** `use_2023…use_2026`, `trust_*`, `fav_*`, `distrust_*`, `use_change`, `use_dir`, `trust_dir`, `gap_2023`, `gap_2025`, `use_distrust_<year>`, `n_respondents`, `years_span`, `exp_young`, `exp_old`, `exp_gap_2023`, `exp_gap_2025`, `exp_gap_dir`, `auc_logit`, `auc_best`, `best_model`, `d_auc`, `d_auc_ci`, `verdict`, `margin_auc`, `top_driver`, `n_segments`, `largest_segment`, `largest_share`, `n_tools`, `basket_label`, `top_pair`, `top_lift`.
- **Missing values:** a missing placeholder renders as a dotted "—" and triggers one console warning. It is never a made-up number.
- **Links:** edit the repo, CV and LinkedIn URLs in `story.meta.links`.

## Files

| Path | Contents |
|---|---|
| `index.html` | Page markup |
| `css/atlas.css` | Light and dark themes, print styles, reduced motion |
| `js/story.js` | All narrative copy |
| `js/data.js` | The data adapter and fixtures |
| `js/util.js` | Shared helpers |
| `js/particles.js` | Canvas field for the hero and adoption wave |
| `js/charts/trust.js` | Chapter 2 |
| `js/charts/experience.js` | Chapter 3 |
| `js/charts/segments.js` | Chapter 4 |
| `js/charts/models.js` | Chapter 5 |
| `js/charts/network.js` | Chapter 6 |
| `js/main.js` | Boot sequence, scrolly, nav |
| `vendor/d3.v7.min.js` | d3 v7.9.0, ISC licence |
| `tools/copy-data.ps1` | Copies the data |
| `tools/qa.py` | Dev QA: screenshots and console errors (Playwright) |
| `screenshots/` | QA output |

Data: Stack Overflow Developer Survey 2023–2026, Stack Exchange Inc. The data is licensed under the ODbL 1.0.
