# AI Adoption Atlas

An honest, reproducible look at AI-tool adoption, trust and sentiment among developers, using the
public **Stack Overflow Developer Survey 2023–2026**.

* `docs/DATA_NOTES.md` — sources, licence, collection, data-quality handling, caveats, analysis questions
* `docs/CODEBOOK_AI.md` + `docs/codebook_ai.csv` — every AI item per year and cross-year comparability verdicts
* `docs/tables/` — aggregate profiling tables (no respondent-level data)
* `scripts/01_harmonise.R` — builds `data_clean/ai_harmonised.parquet` from `data_raw/`

## Reproduce
1. Download each year's results + schema from https://github.com/StackExchange/Survey/tree/main/packages/archive/<year>
   into `data_raw/` with the names listed in `scripts/01_harmonise.R` (`RAWFILES`).
2. `Rscript scripts/01_harmonise.R`

## Licence & attribution
Data: Stack Overflow Developer Survey, Stack Exchange Inc., licensed under the
[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Raw data is **not** redistributed here.
