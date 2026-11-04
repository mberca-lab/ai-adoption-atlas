# Segmentation and tool co-use — final exploratory recovery

## Status and scope

Completed on public Stack Overflow survey data. Selected K: 3. LCA sample: 25780 complete-case 2025 current AI users out of 26469 eligible current users (689 excluded for missing indicators).

This is an exploratory descriptive analysis, **not preregistered** and not representative of all developers. Classes are attitudes, not fabricated behavioural archetypes. Sentiment (favourable / neutral-or-unsure / unfavourable), trust (4), complex-task ability (5 including non-use/uncertainty), and job threat (3) define the measurement model.

## Recovery deviations and model selection

The interrupted plan requested 629 fits on 12 workers and produced no fit cache. It was abandoned. Recovery uses one worker per script (maximum two concurrent), K=1:4, four reference starts, and two starts for each of three split pairs plus three bootstraps per K>1: 31 fit calls, 70 nominal EM starts, maximum 1,200 iterations/start. Complete cases avoid treating missing categories as answers. Every resample must preserve all coded categories. No cross-year replication, broad all-respondent model, attribute-rule search, or measurement-invariance claim is made.

Eligible K>1 must have no reference iteration-cap hit, class proportions >=5%, at least two best log-likelihood starts within 0.1, mean split ARI >=0.75, mean bootstrap ARI >=0.75, and minimum class mean Jaccard >=0.75. Choose minimum BIC among eligible models. These judgement thresholds and bounded grid are exploratory revisions made during recovery. The selected model need not minimize BIC among unstable candidates or outside this grid. Diagnostics use full-sample classification by resampled fits, not held-out performance. Conditional-independence assumptions may split continuous attitude gradients into classes; no claim of natural immutable types.

Selection diagnostics: `lca_model_selection.csv`; all class response probabilities: `lca_profiles.csv`; model proportions versus modal counts: `lca_class_sizes.csv`. Class intervals are null: three bootstrap refits cannot support defensible percentile confidence intervals. Survey sampling uncertainty and model-selection uncertainty are not quantified.

## Observed attitude groups

- Class 1: Favourable, trusting: model share 46.8%; modal n=12271; favourable 96.1%; trusts accuracy 75.5%.
- Class 2: Favourable, cautious on accuracy: model share 34.5%; modal n=8624; favourable 63.9%; trusts accuracy 10.6%.
- Class 3: Unfavourable, cautious on accuracy: model share 18.6%; modal n=4885; favourable 29.4%; trusts accuracy 1.1%.

These probabilities describe different dimensions: favourable sentiment does not imply trusting accuracy. Profiles, not demographics or inferred career stages, define the labels. Entropy is reported in the selection CSV: modal assignments remain uncertain even when partitions are stable across resampling. Class shares sum to one by the fitted mixture, not by survey weighting.

## Bugs corrected

- `paste0` on empty IDE/LLM lists created phantom prefix-only items (notably `IDE:` in 9,496 old 2025 baskets); use an explicit empty-list-safe prefix helper.

- Wilson helper used scalar `ifelse(n > 0, ...)` with vector counts, recycling the first item's support across a basket. Explicit vector broadcasting now preserves each count/denominator and its own interval; regression tests check this.

- Prior stored bootstrap lifts had identical lower/upper endpoints. Fresh intervals now come from direct multinomial resampling of each rule's respondent 2x2 table, not reused arules quality slots. This is equivalent marginally to respondent resampling for a fixed rule, but not a joint bootstrap across rules.

- Multi-antecedent improvement is recomputed against every singleton sub-antecedent and the empty baseline, not just surviving pruned rules. No unsupported 3-item antecedents remain.

- Posterior probabilities are computed explicitly in log space, marginalising missing items, and checked against poLCA's fitted posterior. This avoids brittle package helper assumptions and handles one-row inputs correctly. Category schemas are checked to prevent silent recoding gaps.

## Basket suitability and denominators

Each basket uses QC default-base respondents answering its question(s); unanswered is not treated as non-use. 2025 agent-tools is conditional on agent-user question routing. 2025 model+IDE and 2026 agent+LLM baskets require both lists answered; do not compare supports across these populations. Model/provider selections and IDE usage are different constructs. They describe repertoire overlap, not simultaneous workflow integration.

Exploratory suitability screen: >=1,000 baskets; >=60% with 2+ items; >=8 items at 1% support; top item <90% support. Failure is a caution, not evidence that associations are absent.

- B23 (2023): n=59369, mean items=1.98, 2+ items=56.3%, top support=88.4%; limited: many single-item baskets;.
- B24 (2024): n=44195, mean items=2.34, 2+ items=65.5%, top support=85.3%; suitable.
- B25M (2025): n=15086, mean items=4.13, 2+ items=83.4%, top support=83.0%; suitable.
- B25A (2025): n=8325, mean items=3.45, 2+ items=84.8%, top support=81.7%; suitable.
- B26 (2026): n=9272, mean items=6.25, 2+ items=99.9%, top support=81.7%; suitable.

## Apriori versus a pairwise baseline

Apriori is bounded to total rule length 3 (at most two antecedent items), support >=1% and count >=30, confidence >=25%, lift >=1.2, Fisher Bonferroni alpha .01 within each filtered mining call, confidence-nonredundant. Stable means bootstrap threshold retention >=90% and presence in both halves for >=80% of three split pairs (thus all three pairs). Reportable multi-item rules must improve confidence by >=5 percentage points over every proper sub-rule. These are exploratory screening thresholds, not confirmatory inference; bootstrap retention does not repeat significance/pruning. Lift intervals are conditional fixed-rule 95% percentile bootstrap intervals, not multiplicity- or selection-adjusted population intervals.

Pairwise baseline tests all pairs of items each with >=1% support using phi, lift and Fisher/BH; positive significance threshold q<.001. Pairs with joint count<30 have association metrics suppressed and are omitted from the aggregate output. Rule direction is conditional prevalence, not temporal ordering. Same-vendor effects may reflect ecosystems or overlapping labels.

- B23: 55 pairwise tests; 20 stable/reportable Apriori rules, of which 9 have a two-item antecedent adding >=5pp.
- B24: 136 pairwise tests; 52 stable/reportable Apriori rules, of which 32 have a two-item antecedent adding >=5pp.
- B25M: 253 pairwise tests; 1177 stable/reportable Apriori rules, of which 1024 have a two-item antecedent adding >=5pp.
- B25A: 190 pairwise tests; 268 stable/reportable Apriori rules, of which 222 have a two-item antecedent adding >=5pp.
- B26: 820 pairwise tests; 788 stable/reportable Apriori rules, of which 660 have a two-item antecedent adding >=5pp.

Apriori adds qualifying conditional combinations beyond a pairwise graph, but more rules are not inherently more insight. The primary graph therefore uses genuine singleton rules only, ranked by absolute leverage (maximum 40 undirected pairs/basket). Multi-item combinations remain separate in `multi_item_rules`; never project their lift onto constituent pair edges. Review full counts in `rules_apriori_vs_pairwise.csv` and support sensitivity (1%, 2%, 3%) before selecting a public example. No predictive or causal superiority was established. Dense mixed-question baskets can produce many nested combinations mechanically.

- Illustrative highest-leverage qualifying combination in B25M: {M:Claude Sonnet + M:Gemini Flash} => {M:Gemini Pro}; support 12.5%, confidence 64.5%, lift 2.43, improvement over strongest proper sub-rule 10.1pp. Selected post hoc, not an independent validation.
- Illustrative highest-leverage qualifying combination in B26: {Agent:Claude Code + LLM:OpenAI} => {Agent:OpenAI Codex}; support 24.5%, confidence 44.6%, lift 1.40, improvement over strongest proper sub-rule 5.3pp. Selected post hoc, not an independent validation.

## Runtime and reproduction

Run from the repository root in PowerShell, with R packages arrow, data.table, poLCA, mclust, arules and jsonlite installed:

```powershell
& 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' scripts\04_segments_lca.R
& 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' scripts\04_segments_rules.R
& 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' scripts\04_segments_lca_profiles.R
& 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' scripts\04_segments_verify.R
```

- lca: 168.9 seconds; 1 worker.
- rules: 59.6 seconds; 1 worker.

Seed: 20261104 with deterministic per-fit offsets. Inputs are local gitignored `data_clean/ai_harmonised.parquet` and raw year CSVs. Model caches contain parameters only, no respondent rows. Exported CSV/JSON are aggregates. Old broad-fit caches and attribute-rule outputs are not part of this final analysis.

## References

- Linzer & Lewis (2011), poLCA, Journal of Statistical Software 42(10), https://doi.org/10.18637/jss.v042.i10

- Hennig (2007), Cluster-wise assessment of cluster stability, Computational Statistics & Data Analysis 52, https://doi.org/10.1016/j.csda.2006.11.025 (Jaccard is a heuristic diagnostic, not proof of truth).

- Stack Overflow annual developer survey public files; source provenance and QC definitions are documented by the project's harmonisation pipeline.

