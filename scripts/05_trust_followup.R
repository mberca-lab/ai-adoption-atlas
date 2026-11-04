#!/usr/bin/env Rscript
local({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(if (length(f)) dirname(f) else "scripts", "02_trust_trends_lib.R"))
}, envir = globalenv())
library(jsonlite)
setDTthreads(1)
SEED <- 20261104L
UPSTREAM <- "9dd5c163b7ec09ce5503f711c37a99dbd80ff3c7"
FREQ <- c("Monthly or infrequent", "Weekly", "Daily")
FOLLOW <- file.path(ROOT, "outputs", "trust_followup")

source_sha <- function(path) {
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  digest::digest(gsub("\r\n", "\n", rawToChar(bytes), fixed = TRUE),
                 algo = "sha256", serialize = FALSE)
}

frequency_fit <- function(d, label, nsim = 4000L) {
  d <- copy(d)
  d[, freq_f := factor(ai_use_freq, levels = FREQ)]
  stopifnot(!anyNA(d$freq_f), !anyNA(d$y_trust),
            all(d$y_trust %in% c(FALSE, TRUE)), uniqueN(d$freq_f) == 3)
  ag <- agg_binom(d, "y_trust", c("freq_f", COVS))
  fit <- fit_binom(ag, paste(c("freq_f", COVS), collapse = " + "))
  stopifnot(fit$converged, !anyNA(coef(fit)))
  target <- d[, .(w = .N), by = COVS]
  set.seed(SEED)
  g <- gcomp(fit, target, data.table(freq_f = FREQ), nsim = nsim)
  levels <- data.table(analysis = label, frequency = FREQ, n_target = nrow(d),
    adjusted_pct = 100 * g$point,
    lo = 100 * apply(g$draws, 2, quantile, .025),
    hi = 100 * apply(g$draws, 2, quantile, .975))
  contrast <- g$draws[, 3] - g$draws[, 1]
  list(levels = levels, contrast = data.table(analysis = label,
    comparison = "Daily minus monthly or infrequent", n = nrow(d),
    adjusted_difference_pp = 100 * (g$point[3] - g$point[1]),
    lo = 100 * quantile(contrast, .025), hi = 100 * quantile(contrast, .975)),
    diagnostics = list(converged = fit$converged, rank = fit$rank,
      parameters = length(coef(fit)), aggregated_patterns = nrow(ag),
      fitted_probability_min = min(fitted(fit)), fitted_probability_max = max(fitted(fit))))
}

self_test <- function() {
  grid <- CJ(ai_use_freq = FREQ, exp_band = c("A", "B"), role_f = c("A", "B"),
             region_f = c("A", "B"), org_f = c("A", "B"))
  grid[, n := fifelse((ai_use_freq == "Daily" & role_f == "B") |
                      (ai_use_freq == "Monthly or infrequent" & role_f == "A"), 160L, 40L)]
  grid[, positive := as.integer(n * fifelse(role_f == "A", .25, .75))]
  d <- grid[, .(y_trust = c(rep(TRUE, positive), rep(FALSE, n - positive))),
            by = c("ai_use_freq", COVS)]
  for (v in COVS) set(d, j = v, value = factor(d[[v]]))
  raw <- d[, mean(y_trust), by = ai_use_freq]
  stopifnot(raw[ai_use_freq == "Daily"]$V1 > raw[ai_use_freq == "Monthly or infrequent"]$V1)
  result <- frequency_fit(d, "synthetic", nsim = 100)
  stopifnot(abs(result$contrast$adjusted_difference_pp) < 1e-6,
            all(result$levels$lo <= result$levels$hi))
  bad <- copy(d); bad[1, ai_use_freq := "unmapped"]
  stopifnot(inherits(try(frequency_fit(bad, "bad", 10), silent = TRUE), "try-error"))
  msg("Frequency adjustment self-tests passed (confounding and unmapped answers).")
}

source_audit <- function() {
  # Read the constant registry, without executing the harmonisation job.
  expressions <- as.list(parse(file.path(ROOT, "scripts", "01_harmonise.R")))
  registry <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
                       identical(x[[2]], as.name("RAWFILES")), expressions)
  stopifnot(length(registry) == 1)
  registry <- eval(registry[[1]][[3]])
  checks <- rbindlist(lapply(seq_len(nrow(registry)), function(i) {
    r <- registry[i]
    path <- file.path(ROOT, "data_raw", r$results)
    sha <- digest::digest(file = path, algo = "sha256")
    stopifnot(identical(sha, r$sha256))
    archive_name <- if (r$year == 2026) "survey_results_public.csv" else "results.csv"
    endpoint <- sprintf("repos/StackExchange/Survey/contents/packages/archive/%d/%s?ref=%s",
                        r$year, archive_name, UPSTREAM)
    encoded <- system2("gh", c("api", endpoint, "--jq", ".content"), stdout = TRUE)
    stopifnot(is.null(attr(encoded, "status")))
    pointer <- rawToChar(base64_dec(gsub("[[:space:]]", "", paste(encoded, collapse = ""))))
    stopifnot(grepl(paste0("oid sha256:", sha), pointer, fixed = TRUE))
    n_cols <- ncol(fread(path, nrows = 0, showProgress = FALSE))
    n_rows <- nrow(fread(path, select = 1L, showProgress = FALSE))
    stopifnot(n_cols == r$n_cols, n_rows == r$n_rows)
    data.table(year = r$year, rows = n_rows, columns = n_cols, sha256 = sha,
      upstream_match = TRUE,
      source = sprintf("https://github.com/StackExchange/Survey/blob/%s/packages/archive/%d/%s",
                       UPSTREAM, r$year, archive_name))
  }))
  page <- paste(readLines("https://survey.stackoverflow.co/2025/methodology/",
                          warn = FALSE, encoding = "UTF-8"), collapse = " ")
  stopifnot(grepl("49,009", page, fixed = TRUE))
  list(checked = as.character(Sys.Date()), upstream_commit = UPSTREAM, files = checks,
    issues = list(
      list(id = "2025_count", status = "unresolved publisher discrepancy",
        archive_rows = 49191L, published_topline = 49009L, difference = 182L,
        source = "https://survey.stackoverflow.co/2025/methodology/",
        decision = "Use the hash-verified public archive and our declared QC base. Do not remove 182 arbitrary rows or claim exact reproduction of the published topline."),
      list(id = "2026_dates", status = "historical invalid date withdrawn; close date unverified",
        source = paste0("https://github.com/StackExchange/Survey/blob/", UPSTREAM,
                        "/packages/archive/2026/README.md"),
        decision = "The current archive README no longer states the historical invalid close date. No verified replacement close date is asserted. Analyses use survey year only; 2026 remains a separate instrument series.")))
}

main <- function() {
  dir.create(FOLLOW, recursive = TRUE, showWarnings = FALSE)
  self_test()
  H <- load_data()
  stopifnot(!anyDuplicated(H[, .(year, response_id)]))
  audit <- source_audit()
  flow <- H[elig_all %in% TRUE, .(
    eligible_professionals = .N, answered_ai_status = sum(!is.na(ai_use_status)),
    missing_ai_status = sum(is.na(ai_use_status)), current_ai_users = sum(P2 %in% TRUE),
    trust_answered_users = sum(P2 %in% TRUE & !is.na(y_trust)),
    trust_missing_users = sum(P2 %in% TRUE & is.na(y_trust))), by = year][order(year)]
  flow[, completion_pct := 100 * answered_ai_status / eligible_professionals]
  flow[year == 2026, c("trust_answered_users", "trust_missing_users") := NA_integer_]
  stopifnot(all(flow$answered_ai_status + flow$missing_ai_status == flow$eligible_professionals),
    all(flow[year <= 2025, trust_answered_users + trust_missing_users == current_ai_users]))
  fwrite(flow, file.path(FOLLOW, "population_flow.csv"))
  fwrite(audit$files, file.path(FOLLOW, "source_files.csv"))
  write_json(audit, file.path(FOLLOW, "source_audit.json"), auto_unbox = TRUE,
             pretty = TRUE, na = "null", digits = NA)

  users <- H[year == 2025 & P2 %in% TRUE]
  stopifnot(all(na.omit(users$ai_use_freq) %in% FREQ))
  d <- copy(users[!is.na(y_trust) & !is.na(ai_use_freq)])
  d[qc_years_implausible %in% TRUE, exp_band := "Missing"]
  missing <- d[, .(variable = COVS,
    missing_n = vapply(.SD, function(v) sum(as.character(v) == "Missing"), integer(1))),
    .SDcols = COVS]
  main_fit <- frequency_fit(d, "Missing covariates retained as categories")
  complete <- d[d[, Reduce(`&`, lapply(.SD, function(v) as.character(v) != "Missing")),
                   .SDcols = COVS]]
  stopifnot(nrow(complete) > 1000)
  complete_fit <- frequency_fit(complete, "Complete-covariate sensitivity")
  levels <- rbind(main_fit$levels, complete_fit$levels)
  contrasts <- rbind(main_fit$contrast, complete_fit$contrast)
  raw <- raw_props(d, "y_trust", "ai_use_freq")
  overlap <- rbindlist(lapply(COVS, function(v) {
    x <- as.data.table(as.data.frame(table(
      frequency = factor(d$ai_use_freq, levels = FREQ), level = droplevels(d[[v]]))))
    setnames(x, "Freq", "n")
    x[, variable := v][]
  }))
  fwrite(levels, file.path(FOLLOW, "frequency_adjusted.csv"))
  fwrite(contrasts, file.path(FOLLOW, "frequency_contrasts.csv"))
  fwrite(raw, file.path(FOLLOW, "frequency_raw.csv"))
  fwrite(missing, file.path(FOLLOW, "frequency_missing_covariates.csv"))
  fwrite(overlap, file.path(FOLLOW, "frequency_overlap.csv"))
  sensitivity <- fread(file.path(TAB, "t21_sensitivity_contrasts.csv"))
  bounds <- sensitivity[outcome == "use" & contrast == "2024->2025" &
                          method == "S2a Manski bounds (dropout)"]
  stopifnot(nrow(bounds) == 1, bounds$lo < 0, bounds$hi > 0)
  payload <- list(
    meta = list(seed = SEED, year = 2025L, population = "Adult professional current AI users answering accuracy trust and use frequency; same professional base as the trends.",
      n_current_users = nrow(users), n_analyzed = nrow(d),
      n_missing_trust_or_frequency = nrow(users) - nrow(d),
      n_complete_covariates = nrow(complete), covariates = COVS,
      method = "Grouped binomial logistic regression; marginal probabilities standardised to the observed covariate mix. Coding experience uses the existing bands; implausible years are marked Missing.",
      uncertainty = "95% model-based coefficient-normal simulation intervals, 4000 draws; conditional on the fitted main-effects model and observed sample. Independent-response/model assumptions; no correction for survey selection, module dropout or unmeasured confounding.",
      interpretation = "Exploratory follow-up selected after seeing the raw frequency gradient, not preregistered. Contemporary association, not evidence that use causes trust or that this explains the cross-year trend. Missing-category and complete-case analyses target different samples.",
      source_hash_format = "Source hashes normalise CRLF to LF; data hash uses exact bytes.",
      source_script_sha256 = source_sha(file.path(ROOT, "scripts", "05_trust_followup.R")),
      helper_sha256 = source_sha(file.path(ROOT, "scripts", "02_trust_trends_lib.R")),
      data_sha256 = digest::digest(file = file.path(ROOT, "data_clean", "ai_harmonised.parquet"), algo = "sha256")),
    source_audit = audit, population_flow = flow,
    adoption_change_bounds = list(contrast = "2024->2025", lo = bounds$lo, hi = bounds$hi,
      unit = "pp", interpretation = "Worst-case missing-AI-status bounds, not a confidence interval; includes zero."),
    frequency_raw = raw, frequency_adjusted = levels, frequency_contrasts = contrasts,
    missing_covariates = missing, frequency_overlap = overlap,
    diagnostics = list(main = main_fit$diagnostics, complete = complete_fit$diagnostics))
  write_json(payload, file.path(FOLLOW, "summary.json"), auto_unbox = TRUE,
             pretty = TRUE, na = "null", digits = NA)
  json <- file.path(SITE, "trust_trends.json")
  public <- read_json(json, simplifyVector = FALSE)
  public$followup <- payload
  write_json(public, json, auto_unbox = TRUE, pretty = TRUE, na = "null",
             null = "null", digits = NA)
  writeLines(capture.output(sessionInfo()), file.path(FOLLOW, "SESSION_INFO.txt"))
  print(contrasts)
  msg("Source, population and adjusted-frequency follow-up completed.")
}

verify <- function() {
  p <- read_json(file.path(FOLLOW, "summary.json"), simplifyVector = TRUE)
  stopifnot(p$meta$source_script_sha256 == source_sha(
    file.path(ROOT, "scripts", "05_trust_followup.R")),
    p$meta$helper_sha256 == source_sha(
      file.path(ROOT, "scripts", "02_trust_trends_lib.R")),
    p$meta$data_sha256 == digest::digest(
      file = file.path(ROOT, "data_clean", "ai_harmonised.parquet"), algo = "sha256"),
    p$meta$n_analyzed + p$meta$n_missing_trust_or_frequency == p$meta$n_current_users,
    sum(p$frequency_raw$n) == p$meta$n_analyzed,
    nrow(p$frequency_adjusted) == 6, nrow(p$frequency_contrasts) == 2,
    all(p$frequency_adjusted$lo <= p$frequency_adjusted$adjusted_pct),
    all(p$frequency_adjusted$hi >= p$frequency_adjusted$adjusted_pct),
    p$diagnostics$main$converged, p$diagnostics$complete$converged,
    all(p$source_audit$files$upstream_match))
  tables <- c(frequency_adjusted = "frequency_adjusted.csv",
              frequency_contrasts = "frequency_contrasts.csv",
              frequency_raw = "frequency_raw.csv", population_flow = "population_flow.csv",
              missing_covariates = "frequency_missing_covariates.csv",
              frequency_overlap = "frequency_overlap.csv")
  for (key in names(tables)) {
    stopifnot(isTRUE(all.equal(as.data.frame(fread(file.path(FOLLOW, tables[[key]]))),
                              p[[key]], check.attributes = FALSE, tolerance = 1e-10)))
  }
  public <- read_json(file.path(SITE, "trust_trends.json"), simplifyVector = FALSE)
  stopifnot(identical(public$followup, read_json(file.path(FOLLOW, "summary.json"),
                                               simplifyVector = FALSE)))
  msg("Follow-up checks passed: hashes, model diagnostics, CSVs and public export.")
}

if ("--self-test" %in% commandArgs(TRUE)) self_test() else
  if ("--verify-only" %in% commandArgs(TRUE)) verify() else { main(); verify() }
