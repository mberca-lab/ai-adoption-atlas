#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 02_trust_trends_verify.R
# Verifies that every number quoted in outputs/trust_trends/FINDINGS.md appears
# (at the quoted precision) in the aggregate tables, and recomputes the subgroup
# counts quoted in the text. Exits with status 1 on any mismatch.
# =============================================================================
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(if (length(f)) dirname(f) else "scripts", "02_trust_trends_lib.R"))
}, envir = globalenv())

files <- list.files(TAB, pattern = "\\.csv$", full.names = TRUE)
tabs <- setNames(lapply(files, fread), basename(files))
vals <- unique(abs(unlist(lapply(tabs, function(d) unlist(lapply(d, function(col) suppressWarnings(as.numeric(col))))))))
vals <- vals[is.finite(vals)]

txt <- paste(readLines(file.path(OUT, "FINDINGS.md"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
clean <- txt
clean <- gsub("\\]\\([^)]*\\)", "]", clean)                                    # markdown link targets
clean <- gsub("\\b[A-Za-z]+_?[0-9]+[a-z]?\\b", " ", clean, perl = TRUE)        # t07, S1a, Q1, E3, f1 ...
clean <- gsub("\\b(0|5|10|18|20|25|35|45|55)\\s*[\u2013-]\\s*(4|9|19|24|34|44|54|64)\\b", " ", clean, perl = TRUE)  # bands
clean <- gsub("20\\+|65\\+", " ", clean)
clean <- gsub("\\b(2023|2024|2025|2026)\\s*(\u2013|\u2192|->|-)\\s*(20)?(23|24|25|26)\\b", " ", clean, perl = TRUE)
clean <- gsub("\u2212", "-", clean)
tok <- regmatches(clean, gregexpr("[0-9][0-9,]*(\\.[0-9]+)?", clean, perl = TRUE))[[1]]

STRUCT <- c(90, 95, 182)   # thresholds / CI level; 182 = row discrepancy quoted from DATA_NOTES ([VERIFY] item)
res <- rbindlist(lapply(tok, function(s) {
  x <- as.numeric(gsub(",", "", s)); d <- if (grepl("\\.", s)) nchar(sub(".*\\.", "", s)) else 0
  kind <- if (d == 0 && x %in% 2023:2026) "year" else if (d == 0 && (x <= 30 || x %in% STRUCT)) "structural/count"
          else if (any(abs(round(vals, d) - x) < 1e-9)) "matched" else "UNMATCHED"
  data.table(token = s, value = x, kind = kind)
}))

# Counts quoted in the text, recomputed from the tables
pv <- tabs[["t11b_paradox_verdict_by_subgroup.csv"]]; fc <- tabs[["t11c_favourability_subgroup_contrasts.csv"]]
th <- tabs[["t16_threat_2024_2025.csv"]][dimension != "All"]; pc <- tabs[["t07_primary_contrasts.csv"]][in_holm_family == TRUE]
ip <- tabs[["t11_paradox_subgroup_contrasts.csv"]]; rv <- tabs[["t22_robustness_verdicts.csv"]]
checks <- data.table(claim = c("paradox holds 12 of 18", "distrust rose 18 of 18", "favourability fell 23 of 23",
                               "threat rose sig. 11 of 14", "8 Holm contrasts all significant", "54 subgroup tests",
                               "use checks = 7", "fav checks = 9", "trust checks = 8", "distrust checks = 7",
                               "all 12 robustness contrasts agree"),
  ok = c(sum(pv$paradox_holds) == 12 && nrow(pv) == 18, sum(pv$distrust_rises) == 18,
         sum(fc$decline_sig) == 23 && nrow(fc) == 23, sum(th$q_bh < 0.05 & th$diff_pp > 0) == 11 && nrow(th) == 14,
         nrow(pc) == 8 && all(pc$raw_p_holm < 0.05 & pc$std_p_holm < 0.05), nrow(ip) == 54,
         all(rv[outcome == "use"]$n_checks == 7), all(rv[outcome == "fav"]$n_checks == 9),
         all(rv[outcome == "trust"]$n_checks == 8), all(rv[outcome == "distrust"]$n_checks == 7),
         all(rv$all_pp_checks_agree & rv$all_or_checks_agree)))

msg("Numbers in FINDINGS.md: %d (matched %d, structural/count %d, year %d, UNMATCHED %d)", nrow(res),
    sum(res$kind == "matched"), sum(res$kind == "structural/count"), sum(res$kind == "year"), sum(res$kind == "UNMATCHED"))
if (any(res$kind == "UNMATCHED")) print(res[kind == "UNMATCHED"])
print(checks)
fwrite(res[, .N, by = kind], file.path(OUT, "verification_summary.csv"))
if (any(res$kind == "UNMATCHED") || !all(checks$ok)) { msg("VERIFICATION FAILED"); quit(status = 1) }
msg("VERIFICATION PASSED")
