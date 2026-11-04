#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 02_trust_trends.R
# "Say vs do": adoption, favourability and trust, 2023-2026 (DATA_NOTES Q1-Q6).
# Pre-specified plan: outputs/trust_trends/PLAN.md
# Input : data_clean/ai_harmonised.parquet (row-level, gitignored; never written out)
# Output: outputs/trust_trends/tables/*.csv  (AGGREGATES ONLY)
# Run   : "C:\Program Files\R\R-4.6.2\bin\Rscript.exe" scripts/02_trust_trends.R
#         then scripts/02_trust_trends_figs.R and scripts/02_trust_trends_verify.R
# Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., ODbL 1.0.
# =============================================================================
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(if (length(f)) dirname(f) else "scripts", "02_trust_trends_lib.R"))
}, envir = globalenv())
suppressPackageStartupMessages({ library(lme4); library(ordinal) })
set.seed(20261104)
NSIM <- 2000
wtab <- function(x, name) { fwrite(x, file.path(TAB, paste0(name, ".csv"))); msg("  wrote tables/%s.csv (%d rows)", name, nrow(x)) }
r1 <- function(x) round(x, 1); r2 <- function(x) round(x, 2); r3 <- function(x) round(x, 3)

H <- load_data()
D1 <- H[P1 == TRUE]; D2 <- H[P2 == TRUE]; D3 <- H[P3 == TRUE]
msg("P1 n by year: %s", paste(D1[, .N, by = year][order(year), paste(year, N)], collapse = "; "))

# =============================================================================
# 1. Raw proportions by year (Wilson CIs)
# =============================================================================
OUTS <- data.table(
  outcome = c("use", "plan", "fav", "fav_ex_unsure", "trust", "distrust", "complex_good", "threat_yes"),
  var     = c("y_use", "y_plan", "y_fav", "y_fav_ex", "y_trust", "y_distrust", "y_complex", "y_threat"),
  pop     = c("P1", "P1", "P2", "P2", "P2", "P2", "P2", "P3"))
popdat <- list(P1 = D1, P2 = D2, P3 = D3)
raw <- rbindlist(lapply(seq_len(nrow(OUTS)), function(i) {
  o <- OUTS[i]; r <- raw_props(popdat[[o$pop]], o$var, "year")
  r[, `:=`(outcome = o$outcome, population = o$pop)]
}))
raw[, series := fifelse(year == 2026, "B (2026, series break)", "A (2023-2025)")]
# trust items are not comparable in 2026 (different construct) -> harmonised var is NA, so no rows.
raw <- raw[order(outcome, year)]
setcolorder(raw, c("outcome", "population", "year", "series", "x", "n", "pct", "lo", "hi"))
raw[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")]
wtab(raw, "t01_raw_by_year")

# use-while-distrusting share of all professional developers (users with missing trust dropped)
ud <- D1[!(y_use & is.na(y_trust)) & year %in% YEARS_A,
         .(x = sum(y_use & y_distrust %in% TRUE), x_trust = sum(y_use & y_trust %in% TRUE), n = .N), by = year]
ci <- wilson(ud$x, ud$n); ci2 <- wilson(ud$x_trust, ud$n)
ud[, `:=`(pct_use_distrust = r1(100 * ci$p), lo = r1(100 * ci$lo), hi = r1(100 * ci$hi),
          pct_use_trust = r1(100 * ci2$p), lo_trust = r1(100 * ci2$lo), hi_trust = r1(100 * ci2$hi))]
wtab(ud[order(year)], "t02_use_while_distrusting_P1")

# intent ceiling (cohort-level, not panel)
ad <- dcast(raw[outcome %in% c("use", "plan") & year %in% YEARS_A], year ~ outcome, value.var = "pct")
ad[, `:=`(ceiling_from_prev = shift(use) + shift(plan), use_minus_ceiling = r1(use - (shift(use) + shift(plan))))]
wtab(ad, "t03_intent_ceiling")

# 2026 frequency + 2025 frequency among users (context only)
fq <- D2[year >= 2025 & !is.na(ai_use_freq), .N, by = .(year, ai_use_freq)]
fq[, pct := r1(100 * N / sum(N)), by = year]
wtab(fq[order(year, ai_use_freq)], "t04_use_frequency_users")

# 2026 AITrust (conditional, non-ordinal) -- descriptive only
tr26 <- D2[year == 2026 & !is.na(ai_trust_raw), .(opt = trimws(unlist(strsplit(ai_trust_raw, ";", fixed = TRUE)))), by = uid]
n26 <- uniqueN(tr26$uid)
tr26 <- tr26[, .(x = .N), by = opt][, n := n26]
ci <- wilson(tr26$x, tr26$n)
tr26[, `:=`(pct = r1(100 * ci$p), lo = r1(100 * ci$lo), hi = r1(100 * ci$hi))]
wtab(tr26[order(-pct)], "t05_aitrust_2026_options_users")

# =============================================================================
# 2. Primary contrasts (Holm) + adjusted year ORs + standardised estimates
# =============================================================================
RHS <- "yearf + exp_band + role_f + region_f + org_f"
std_series <- function(d, y, years, target_d) {
  dd <- d[year %in% years]; dd[, yearf := factor(year, levels = years)]
  ag <- agg_binom(dd, y, c("yearf", COVS)); fit <- fit_binom(ag, RHS)
  tg <- target_d[, .(w = .N), by = COVS]
  st <- data.table(yearf = factor(years, levels = years))
  g <- gcomp(fit, tg, st, NSIM)
  list(fit = fit, g = g, years = years, n = dd[!is.na(get(y)), .N])
}
std_2026 <- function(d, y, target_d) {
  dd <- d[year == 2026]
  ag <- agg_binom(dd, y, COVS); fit <- fit_binom(ag, "exp_band + role_f + region_f + org_f")
  g <- gcomp(fit, target_d[, .(w = .N), by = COVS], data.table(dummy = 1), NSIM)
  list(point = g$point, draws = g$draws)
}
PRIMARY <- data.table(outcome = c("use", "fav", "trust", "distrust"),
                      var = c("y_use", "y_fav", "y_trust", "y_distrust"), pop = c("P1", "P2", "P2", "P2"))
STD <- list(); stdtab <- list(); ortab <- list()
for (i in seq_len(nrow(PRIMARY))) {
  o <- PRIMARY[i]; d <- popdat[[o$pop]]; tgt <- d[year %in% YEARS_A]
  s <- std_series(d, o$var, YEARS_A, tgt); STD[[o$outcome]] <- s
  for (k in seq_along(YEARS_A)) stdtab[[length(stdtab) + 1]] <- data.table(outcome = o$outcome, year = YEARS_A[k],
    std_pct = 100 * s$g$point[k], lo = 100 * quantile(s$g$draws[, k], .025), hi = 100 * quantile(s$g$draws[, k], .975))
  if (o$outcome %in% c("use", "fav")) {
    s26 <- std_2026(d, o$var, tgt)
    stdtab[[length(stdtab) + 1]] <- data.table(outcome = o$outcome, year = 2026L, std_pct = 100 * s26$point,
      lo = 100 * quantile(s26$draws, .025), hi = 100 * quantile(s26$draws, .975))
  }
  ortab[[i]] <- or_contr(coef(s$fit), vcov(s$fit), o$outcome, "logit, fixed effects")
}
stdtab <- rbindlist(stdtab); stdtab[, c("std_pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("std_pct", "lo", "hi")]
stdtab[, standardised_to := "pooled 2023-2025 covariate mix (experience, role, region, org size) of the population"]
wtab(stdtab, "t06_standardised_by_year")

# primary contrast table
pc <- rbindlist(lapply(seq_len(nrow(PRIMARY)), function(i) {
  o <- PRIMARY[i]; r <- raw[outcome == o$outcome]; s <- STD[[o$outcome]]
  rbindlist(lapply(list(c(2023, 2024), c(2024, 2025), c(2023, 2025)), function(yy) {
    a <- r[year == yy[1]]; b <- r[year == yy[2]]
    nc <- newcombe(a$x, a$n, b$x, b$n)
    k1 <- match(yy[1], s$years); k2 <- match(yy[2], s$years)
    dd <- s$g$draws[, k2] - s$g$draws[, k1]; dpt <- s$g$point[k2] - s$g$point[k1]
    data.table(outcome = o$outcome, contrast = paste0(yy[1], "->", yy[2]),
      p_from = a$pct, p_to = b$pct, n_from = a$n, n_to = b$n,
      raw_diff_pp = 100 * nc$d, raw_lo = 100 * nc$lo, raw_hi = 100 * nc$hi,
      raw_p = ztest_p(a$x, a$n, b$x, b$n), cohen_h = cohen_h(a$x / a$n, b$x / b$n),
      std_diff_pp = 100 * dpt, std_lo = 100 * quantile(dd, .025), std_hi = 100 * quantile(dd, .975),
      std_p = sim_p(dd, dpt))
  }))
}))
pc[, in_holm_family := contrast != "2023->2025"]
pc[in_holm_family == TRUE, `:=`(raw_p_holm = p.adjust(raw_p, "holm"), std_p_holm = p.adjust(std_p, "holm"))]
num <- c("raw_diff_pp", "raw_lo", "raw_hi", "std_diff_pp", "std_lo", "std_hi")
pc[, (num) := lapply(.SD, r1), .SDcols = num]; pc[, cohen_h := r3(cohen_h)]
wtab(pc, "t07_primary_contrasts")

# =============================================================================
# 3. Ordinal logits (5-point trust / sentiment, Unsure excluded) and multilevel
# =============================================================================
ord_fit <- function(d, yv, lab) {
  dd <- d[year %in% YEARS_A & !is.na(get(yv))]; dd[, yearf := factor(year, levels = YEARS_A)]
  ag <- dd[, .(w = .N), by = c("yearf", COVS, yv)]; ag[, yo := factor(get(yv), levels = 1:5, ordered = TRUE)]
  f <- clm(as.formula(paste("yo ~", RHS)), weights = w, data = ag)
  or_contr(coef(f), vcov(f), lab, "ordinal logit (cumulative OR, >1 = more positive)")
}
ortab[[length(ortab) + 1]] <- ord_fit(D2, "ai_trust_5", "trust_5pt")
ortab[[length(ortab) + 1]] <- ord_fit(D2, "ai_sent_5", "sentiment_5pt")

ml_icc <- list()
for (i in seq_len(nrow(PRIMARY))) {
  o <- PRIMARY[i]; dd <- popdat[[o$pop]][year %in% YEARS_A & !is.na(get(o$var))]
  dd[, yearf := factor(year, levels = YEARS_A)]
  dd[, cty := fifelse(is.na(country), paste("Unknown", region_f), country)]
  small <- dd[, .N, by = cty][N < 30, cty]
  dd[cty %in% small, cty := paste("Other", region_f)]
  ag <- dd[, .(s = sum(get(o$var)), n = .N), by = c("yearf", COVS, "cty")]
  t0 <- Sys.time()
  m <- glmer(as.formula(paste("cbind(s, n - s) ~", RHS, "+ (1 | cty)")), family = binomial, data = ag,
             nAGQ = 0)   # PIRLS approximation: Laplace (nAGQ=1) did not finish in 15 min on these data
  ortab[[length(ortab) + 1]] <- or_contr(fixef(m), vcov(m), o$outcome,
                                         "logit, random country intercept (glmer nAGQ=0)")
  v <- as.numeric(VarCorr(m)$cty)
  ml_icc[[i]] <- data.table(outcome = o$outcome, n_countries = uniqueN(ag$cty), country_var = v,
                            icc_latent = v / (v + pi^2 / 3), justified = v / (v + pi^2 / 3) >= 0.01)
  msg("  glmer %s done in %.0fs (ICC %.3f)", o$outcome, as.numeric(difftime(Sys.time(), t0, units = "secs")), v / (v + pi^2 / 3))
}
ortab <- rbindlist(ortab); ortab[, c("OR", "lo", "hi") := lapply(.SD, r3), .SDcols = c("OR", "lo", "hi")]
wtab(ortab, "t08_year_odds_ratios")
ml_icc <- rbindlist(ml_icc); ml_icc[, c("country_var", "icc_latent") := lapply(.SD, r3), .SDcols = c("country_var", "icc_latent")]
wtab(ml_icc, "t09_multilevel_icc")

# =============================================================================
# 4. Subgroups: paradox (E4) and favourability decline (E2)
# =============================================================================
DIMS <- c(exp_band = "Experience (years coding)", role_f = "Role family", region_f = "Region", age_f = "Age band")
sub_y <- rbindlist(lapply(names(DIMS), function(dv) rbindlist(lapply(PRIMARY$outcome, function(oc) {
  o <- PRIMARY[outcome == oc]; r <- raw_props(popdat[[o$pop]], o$var, c("year", dv))
  setnames(r, dv, "level"); r[, `:=`(dimension = DIMS[[dv]], outcome = oc, level = as.character(level))]
}))))
sub_y <- sub_y[level != "Missing"]
sub_y[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")]
setcolorder(sub_y, c("dimension", "level", "outcome", "year"))
wtab(sub_y[order(dimension, level, outcome, year)], "t10_subgroup_by_year")

sub_contrast <- function(oc, dims, y1 = 2023, y2 = 2025, nmin = 100) {
  rbindlist(lapply(dims, function(dm) {
    s <- sub_y[outcome == oc & dimension == dm & year %in% c(y1, y2)]
    w <- dcast(s, level ~ year, value.var = c("x", "n"))
    setnames(w, c("level", "x1", "x2", "n1", "n2"))
    w <- w[n1 >= nmin & n2 >= nmin]
    nc <- newcombe(w$x1, w$n1, w$x2, w$n2)
    w[, `:=`(dimension = dm, outcome = oc, contrast = paste0(y1, "->", y2),
             pct_from = 100 * x1 / n1, pct_to = 100 * x2 / n2,
             diff_pp = 100 * nc$d, lo = 100 * nc$lo, hi = 100 * nc$hi, p = ztest_p(x1, n1, x2, n2),
             cohen_h = cohen_h(x1 / n1, x2 / n2))]
    w[, -c("x1", "x2")]
  }))
}
par_dims <- DIMS[c("exp_band", "role_f", "region_f")]
par <- rbindlist(lapply(c("use", "trust", "distrust"), sub_contrast, dims = par_dims))
par[, q_bh := p.adjust(p, "BH")]                        # one BH family for the paradox table
num <- c("pct_from", "pct_to", "diff_pp", "lo", "hi")
par[, (num) := lapply(.SD, r1), .SDcols = num]; par[, cohen_h := r3(cohen_h)]
wtab(par, "t11_paradox_subgroup_contrasts")
pv <- dcast(par, dimension + level ~ outcome, value.var = c("diff_pp", "lo", "hi", "q_bh"))
pv[, paradox_holds := lo_use > 0 & q_bh_use < .05 & hi_trust < 0 & q_bh_trust < .05]
pv[, distrust_rises := lo_distrust > 0 & q_bh_distrust < .05]
wtab(pv, "t11b_paradox_verdict_by_subgroup")

favsub <- sub_contrast("fav", DIMS)
favsub[, q_bh := p.adjust(p, "BH")]
favsub[, (num) := lapply(.SD, r1), .SDcols = num]; favsub[, cohen_h := r3(cohen_h)]
favsub[, decline_sig := hi < 0 & q_bh < .05]
wtab(favsub, "t11c_favourability_subgroup_contrasts")

# =============================================================================
# 5. Experience gradient (E5): standardised Pr by year x experience; widening test
# =============================================================================
grad_rows <- list(); widen <- list(); lvl_rows <- list()
tgt2 <- D2[year %in% YEARS_A][, .(w = .N), by = COVS]
for (oc in c("trust", "distrust", "fav")) {
  o <- PRIMARY[outcome == oc]
  dd <- D2[year %in% YEARS_A]; dd[, yearf := factor(year, levels = YEARS_A)]
  ag <- agg_binom(dd, o$var, c("yearf", COVS))
  f_add <- fit_binom(ag, RHS)
  f_int <- fit_binom(ag, "yearf * exp_band + role_f + region_f + org_f")
  lr_p <- anova(f_add, f_int, test = "Chisq")[2, "Pr(>Chi)"]
  st <- CJ(yearf = factor(YEARS_A, levels = YEARS_A), exp_band = factor(EXP_LEVELS, levels = levels(D2$exp_band)))
  g <- gcomp(f_int, tgt2, st, NSIM)
  for (k in seq_len(nrow(st))) lvl_rows[[length(lvl_rows) + 1]] <- data.table(outcome = oc,
    year = as.integer(as.character(st$yearf[k])), exp_band = as.character(st$exp_band[k]),
    std_pct = 100 * g$point[k], lo = 100 * quantile(g$draws[, k], .025), hi = 100 * quantile(g$draws[, k], .975))
  gd <- sapply(YEARS_A, function(y) { i20 <- which(st$yearf == y & st$exp_band == "20+ yrs"); i0 <- which(st$yearf == y & st$exp_band == "0-4 yrs")
    g$draws[, i20] - g$draws[, i0] })
  gp <- sapply(YEARS_A, function(y) g$point[st$yearf == y & st$exp_band == "20+ yrs"] - g$point[st$yearf == y & st$exp_band == "0-4 yrs"])
  wd <- gd[, 3] - gd[, 1]; wp <- gp[3] - gp[1]
  widen[[oc]] <- data.table(outcome = oc,
    gap_2023_pp = 100 * gp[1], gap_2023_lo = 100 * quantile(gd[, 1], .025), gap_2023_hi = 100 * quantile(gd[, 1], .975),
    gap_2024_pp = 100 * gp[2], gap_2024_lo = 100 * quantile(gd[, 2], .025), gap_2024_hi = 100 * quantile(gd[, 2], .975),
    gap_2025_pp = 100 * gp[3], gap_2025_lo = 100 * quantile(gd[, 3], .025), gap_2025_hi = 100 * quantile(gd[, 3], .975),
    widening_pp = 100 * wp, widening_lo = 100 * quantile(wd, .025), widening_hi = 100 * quantile(wd, .975),
    widening_p_sim = sim_p(wd, wp), lr_interaction_p = lr_p)
}
# 2026 favourability gradient (series B; own model, same target)
d26 <- D2[year == 2026]; ag26 <- agg_binom(d26, "y_fav", COVS)
f26 <- fit_binom(ag26, "exp_band + role_f + region_f + org_f")
st26 <- data.table(exp_band = factor(EXP_LEVELS, levels = levels(D2$exp_band)))
g26 <- gcomp(f26, tgt2, st26, NSIM)
for (k in seq_along(EXP_LEVELS)) lvl_rows[[length(lvl_rows) + 1]] <- data.table(outcome = "fav", year = 2026L,
  exp_band = EXP_LEVELS[k], std_pct = 100 * g26$point[k], lo = 100 * quantile(g26$draws[, k], .025), hi = 100 * quantile(g26$draws[, k], .975))
gd26 <- g26$draws[, 4] - g26$draws[, 1]
widen$fav[, `:=`(gap_2026_seriesB_pp = 100 * (g26$point[4] - g26$point[1]),
                 gap_2026_seriesB_lo = 100 * quantile(gd26, .025), gap_2026_seriesB_hi = 100 * quantile(gd26, .975))]
lv <- rbindlist(lvl_rows); lv[, c("std_pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("std_pct", "lo", "hi")]
lv[, note := "standardised to pooled 2023-2025 users' role/region/org mix; 2026 = series B"]
wtab(lv, "t12_experience_gradient_levels")
wdt <- rbindlist(widen, fill = TRUE)
wdt[, widening_q_bh := p.adjust(widening_p_sim, "BH")]
nn <- grep("_pp$|_lo$|_hi$", names(wdt), value = TRUE); wdt[, (nn) := lapply(.SD, r1), .SDcols = nn]
wtab(wdt, "t13_experience_gradient_widening")
raw_exp <- sub_y[dimension == DIMS[["exp_band"]]]
wtab(raw_exp, "t12b_experience_raw_by_year")

# =============================================================================
# 6. Complex-task capability (Q5) and job threat (Q6)
# =============================================================================
cx <- rbindlist(lapply(2024:2026, function(y) {
  dd <- D2[year == y & !is.na(ai_complex_5) & !is.na(y_fav)]
  ag <- dd[, .(s = sum(y_fav), n = .N), by = c("ai_complex_5", COVS)]
  f <- fit_binom(ag, "ai_complex_5 + exp_band + role_f + region_f + org_f")
  cf <- summary(f)$coefficients["ai_complex_5", ]
  data.table(year = y, series = fifelse(y == 2026, "B", "A"), n = nrow(dd),
             OR_fav_per_point = exp(cf[1]), lo = exp(cf[1] - Z * cf[2]), hi = exp(cf[1] + Z * cf[2]), p = cf[4])
}))
cx[, c("OR_fav_per_point", "lo", "hi") := lapply(.SD, r2), .SDcols = c("OR_fav_per_point", "lo", "hi")]
wtab(cx, "t14_complexity_predicts_favourability")
cxs <- std_series(D2, "y_complex", 2024:2025, D2[year %in% 2024:2025])
cxr <- raw[outcome == "complex_good"]
nc <- newcombe(cxr[year == 2024]$x, cxr[year == 2024]$n, cxr[year == 2025]$x, cxr[year == 2025]$n)
dd <- cxs$g$draws[, 2] - cxs$g$draws[, 1]
wtab(data.table(outcome = "complex_good", contrast = "2024->2025", raw_diff_pp = r1(100 * nc$d), raw_lo = r1(100 * nc$lo),
  raw_hi = r1(100 * nc$hi), std_2024 = r1(100 * cxs$g$point[1]), std_2025 = r1(100 * cxs$g$point[2]),
  std_diff_pp = r1(100 * diff(cxs$g$point)), std_lo = r1(100 * quantile(dd, .025)), std_hi = r1(100 * quantile(dd, .975)),
  rated_share_note = "denominator excludes 'I don't use AI for complex tasks / don't know'"), "t14b_complexity_contrast")

thr <- raw_props(D3, "y_threat", c("year", "ai_use_status"))
thr[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")]
wtab(thr[order(year, ai_use_status)], "t15_threat_by_use_status")
ths <- std_series(D3, "y_threat", 2024:2025, D3[year %in% 2024:2025])
tr <- raw[outcome == "threat_yes"]; nc <- newcombe(tr[year == 2024]$x, tr[year == 2024]$n, tr[year == 2025]$x, tr[year == 2025]$n)
dd <- ths$g$draws[, 2] - ths$g$draws[, 1]
th_over <- data.table(dimension = "All", level = "All professional users + planners", n1 = tr[year == 2024]$n, n2 = tr[year == 2025]$n,
  pct_from = tr[year == 2024]$pct, pct_to = tr[year == 2025]$pct, diff_pp = 100 * nc$d, lo = 100 * nc$lo, hi = 100 * nc$hi,
  p = ztest_p(tr[year == 2024]$x, tr[year == 2024]$n, tr[year == 2025]$x, tr[year == 2025]$n),
  std_diff_pp = 100 * diff(ths$g$point), std_lo = 100 * quantile(dd, .025), std_hi = 100 * quantile(dd, .975))
thy <- rbindlist(lapply(c("role_f", "region_f"), function(dv) {
  r <- raw_props(D3[year %in% 2024:2025], "y_threat", c("year", dv)); setnames(r, dv, "level")
  r[, level := as.character(level)]; r <- r[level != "Missing"]
  w <- dcast(r, level ~ year, value.var = c("x", "n")); setnames(w, c("level", "x1", "x2", "n1", "n2"))
  w <- w[n1 >= 100 & n2 >= 100]; nc <- newcombe(w$x1, w$n1, w$x2, w$n2)
  w[, `:=`(dimension = DIMS[[dv]], pct_from = 100 * x1 / n1, pct_to = 100 * x2 / n2, diff_pp = 100 * nc$d,
           lo = 100 * nc$lo, hi = 100 * nc$hi, p = ztest_p(x1, n1, x2, n2))][, -c("x1", "x2")]
}))
thy[, q_bh := p.adjust(p, "BH")]
th <- rbindlist(list(th_over, thy), fill = TRUE)
nn <- c("pct_from", "pct_to", "diff_pp", "lo", "hi", "std_diff_pp", "std_lo", "std_hi")
th[, (nn) := lapply(.SD, r1), .SDcols = nn]
wtab(th, "t16_threat_2024_2025")

# =============================================================================
# 7. Sensitivity analyses
# =============================================================================
props_for <- function(d1, d2, label) rbindlist(lapply(seq_len(nrow(PRIMARY)), function(i) {
  o <- PRIMARY[i]; d <- if (o$pop == "P1") d1 else d2
  r <- raw_props(d[year %in% YEARS_A], o$var, "year"); r[, `:=`(outcome = o$outcome, method = label)]
}))
# S1a: re-include QC-excluded rows that answered AISelect; S1b: strict QC
S1a_1 <- H[is_professional_dev & adult & !is.na(ai_use_status)]
S1b_1 <- D1[!(qc_years_implausible %in% TRUE) & !(qc_ai_inconsistent %in% TRUE) & !(qc_straightline %in% TRUE)]
sens_p <- rbindlist(list(
  props_for(D1, D2, "raw (default base)"),
  props_for(S1a_1, S1a_1[ai_user %in% TRUE], "S1a include QC-excluded"),
  props_for(S1b_1, S1b_1[ai_user %in% TRUE], "S1b strict QC")))
qc_n <- data.table(year = YEARS_A, n_P1 = D1[, .N, keyby = year][J(YEARS_A)]$N,
                   n_S1a = S1a_1[, .N, keyby = year][J(YEARS_A)]$N, n_S1b = S1b_1[, .N, keyby = year][J(YEARS_A)]$N)

# S2a: completion + Manski bounds
E <- H[elig_all == TRUE]
comp <- E[, .(n_eligible = .N, n_answered_aiselect = sum(!is.na(ai_use_status)), x_use = sum(y_use)), keyby = year]
comp[, `:=`(completion_pct = r1(100 * n_answered_aiselect / n_eligible),
            use_lower_pct = r1(100 * x_use / n_eligible),
            use_upper_pct = r1(100 * (x_use + n_eligible - n_answered_aiselect) / n_eligible))]
ub <- rbindlist(lapply(c("fav", "trust", "distrust"), function(oc) {
  v <- PRIMARY[outcome == oc]$var
  D2[, .(outcome = oc, n_users = .N, n_item = sum(!is.na(get(v))), x = sum(get(v), na.rm = TRUE)), keyby = year][
    , `:=`(item_missing_pct = r1(100 * (1 - n_item / n_users)), lower_pct = r1(100 * x / n_users),
           upper_pct = r1(100 * (x + n_users - n_item) / n_users))]
}))
ub <- ub[!(outcome != "fav" & year == 2026)]
wtab(comp, "t17_completion_and_adoption_bounds")
wtab(ub, "t17b_item_nonresponse_bounds_users")

# S2b: inverse probability of completion weighting
cand <- c(age_f = "age band", exp_band = "experience", emp_f = "employment", edu_f = "education",
          remote_f = "remote work", org_f = "org size", role_f = "role family", region_f = "region")
avail <- rbindlist(lapply(names(cand), function(v) E[is.na(ai_use_status),
  .(variable = v, observed_pct_noncompleters = r1(100 * mean(get(v) != "Missing"))), keyby = year]))
inc <- avail[, .(included = all(observed_pct_noncompleters >= 90)), by = variable]
avail <- merge(avail, inc, by = "variable")
wtab(avail, "t18_ipw_covariate_availability")
ipw_vars <- inc[included == TRUE, variable]
msg("IPW covariates: %s", paste(ipw_vars, collapse = ", "))
E[, R := !is.na(ai_use_status)]
E[, ipw := NA_real_]
for (y in 2023:2026) {
  if (all(E[year == y]$R)) { E[year == y, ipw := 1]; next }   # 2023: no AISelect dropout among eligible
  f <- glm(as.formula(paste("R ~", paste(ipw_vars, collapse = " + "))), binomial, data = droplevels(E[year == y]))
  ph <- fitted(f); w <- 1 / ph
  q <- quantile(w[E[year == y]$R], c(.01, .99)); w <- pmin(pmax(w, q[1]), q[2])
  E[year == y, ipw := w]
}
ipw_tab <- rbindlist(lapply(c(OUTS[outcome %in% c("use", "fav", "trust", "distrust")]$outcome), function(oc) {
  o <- OUTS[outcome == oc]
  dd <- E[R == TRUE & in_default_base == TRUE]; if (o$pop == "P2") dd <- dd[ai_user %in% TRUE]
  dd[!is.na(get(o$var)), { wp <- wprop(get(o$var), ipw); list(outcome = oc, pct = 100 * wp$p, lo = 100 * wp$lo, hi = 100 * wp$hi,
     n = wp$n, n_eff = wp$neff) }, keyby = year]
}))
ipw_tab[, method := "S2b IPW (completion propensity)"]

# S3: 2023 column mislabelling (aggregated counts from the raw 2023 file only)
r23 <- fread(file.path(ROOT, "data_raw", "2023_results.csv"), select = c("AIBen", "AIAcc"), na.strings = c("", "NA"))
TRUST_LV <- c("Highly trust", "Somewhat trust", "Neither trust nor distrust", "Somewhat distrust", "Highly distrust")
s3 <- rbindlist(lapply(c("AIBen", "AIAcc"), function(cn) { v <- r23[[cn]][!is.na(r23[[cn]])]
  data.table(raw_column_2023 = cn, n_nonmissing = length(v), n_distinct_values = uniqueN(v),
    pct_values_on_trust_scale = r1(100 * mean(v %in% TRUST_LV)), pct_multiselect = r1(100 * mean(grepl(";", v, fixed = TRUE))),
    harmonised_use = fifelse(cn == "AIBen", "trust (ai_trust_5) - mapped by meaning", "benefits (ai_benefits_raw)"),
    naive_name_based_use = fifelse(cn == "AIAcc", "would be read as 'trust in accuracy'", "would be read as 'benefits'"))
}))
wtab(s3, "t19_2023_column_swap_check")
# routed-base check: 2023 trust among users+planners (as asked) vs users only
rb <- rbindlist(lapply(c("y_trust", "y_distrust"), function(v) rbind(
  raw_props(D3[year == 2023], v, "year")[, base := "users + planners (as routed in 2023)"],
  raw_props(D2[year == 2023], v, "year")[, base := "users only (analysis base)"])[, outcome := sub("y_", "", v)]))
# S4: 2025 everyone asked vs users only
s4 <- rbindlist(lapply(c("y_fav", "y_trust", "y_distrust"), function(v) rbind(
  raw_props(D1[year == 2025], v, "year")[, base := "all professional devs (2025 asked everyone)"],
  raw_props(D2[year == 2025], v, "year")[, base := "users only (analysis base)"])[, outcome := sub("y_", "", v)]))
rt <- rbind(rb, s4); rt[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")]
wtab(rt, "t20_routing_base_sensitivity")

# =============================================================================
# 8. Sensitivity summary + robustness verdicts for primary contrasts
# =============================================================================
diff_from_props <- function(tb, method) {
  rbindlist(lapply(unique(tb$outcome), function(oc) rbindlist(lapply(list(c(2023, 2024), c(2024, 2025), c(2023, 2025)), function(yy) {
    a <- tb[outcome == oc & year == yy[1]]; b <- tb[outcome == oc & year == yy[2]]
    nx <- if ("n_eff" %in% names(tb)) c(a$n_eff, b$n_eff) else c(a$n, b$n)
    nc <- newcombe(a$pct / 100 * nx[1], nx[1], b$pct / 100 * nx[2], nx[2])
    data.table(outcome = oc, contrast = paste0(yy[1], "->", yy[2]), method = method,
               estimate = 100 * nc$d, lo = 100 * nc$lo, hi = 100 * nc$hi, scale = "pp")
  }))))
}
sens <- rbindlist(list(
  pc[, .(outcome, contrast, method = "raw (default base)", estimate = raw_diff_pp, lo = raw_lo, hi = raw_hi, scale = "pp")],
  pc[, .(outcome, contrast, method = "standardised (g-computation)", estimate = std_diff_pp, lo = std_lo, hi = std_hi, scale = "pp")],
  diff_from_props(sens_p[method == "S1a include QC-excluded"], "S1a include QC-excluded"),
  diff_from_props(sens_p[method == "S1b strict QC"], "S1b strict QC"),
  diff_from_props(ipw_tab[year %in% YEARS_A], "S2b IPW (completion propensity)"),
  ortab[model %like% "random country", .(outcome, contrast, method = "multilevel logit (OR)", estimate = OR, lo, hi, scale = "OR")],
  ortab[model %like% "fixed effects", .(outcome, contrast, method = "fixed-effects logit (OR)", estimate = OR, lo, hi, scale = "OR")],
  ortab[outcome == "trust_5pt", .(outcome = "trust", contrast, method = "ordinal logit 5-pt (OR)", estimate = OR, lo, hi, scale = "OR")],
  ortab[outcome == "sentiment_5pt", .(outcome = "fav", contrast, method = "ordinal logit 5-pt, Unsure excl. (OR)", estimate = OR, lo, hi, scale = "OR")]
), fill = TRUE)
# S5: favourability excluding Unsure
fe <- raw[outcome == "fav_ex_unsure"]
sens <- rbind(sens, diff_from_props(fe[, .(outcome = "fav", year, pct, n)], "S5 fav excl. Unsure"))
# Manski bounds on the difference (adoption: dropout before AISelect; attitudes: item non-response among users)
mb <- rbindlist(lapply(list(c(2023, 2024), c(2024, 2025), c(2023, 2025)), function(yy) {
  a <- comp[year == yy[1]]; b <- comp[year == yy[2]]
  out <- data.table(outcome = "use", contrast = paste0(yy[1], "->", yy[2]), method = "S2a Manski bounds (dropout)",
    estimate = NA_real_, lo = b$use_lower_pct - a$use_upper_pct, hi = b$use_upper_pct - a$use_lower_pct, scale = "pp")
  rbind(out, rbindlist(lapply(c("fav", "trust", "distrust"), function(oc) {
    a <- ub[outcome == oc & year == yy[1]]; b <- ub[outcome == oc & year == yy[2]]
    data.table(outcome = oc, contrast = paste0(yy[1], "->", yy[2]), method = "S2a Manski bounds (item non-response)",
      estimate = NA_real_, lo = b$lower_pct - a$upper_pct, hi = b$upper_pct - a$lower_pct, scale = "pp")
  })))
}))
sens <- rbind(sens, mb)
sens[, c("estimate", "lo", "hi") := lapply(.SD, function(z) fifelse(scale == "OR", r3(z), r1(z))), .SDcols = c("estimate", "lo", "hi")]
wtab(sens[order(outcome, contrast, method)], "t21_sensitivity_contrasts")
wtab(rbind(sens_p, ipw_tab, fill = TRUE)[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")][order(outcome, method, year)],
     "t21b_sensitivity_levels")
wtab(qc_n, "t21c_sensitivity_base_sizes")

verdict <- sens[, {
  pp <- .SD[scale == "pp" & !grepl("Manski", method)]; orr <- .SD[scale == "OR"]
  sg <- sign(pp[method == "raw (default base)"]$estimate)
  pp_ok <- all(sign(pp$estimate) == sg & (pp$lo > 0 | pp$hi < 0))
  or_ok <- all(sign(log(orr$estimate)) == sg & (orr$lo > 1 | orr$hi < 1))
  bd <- .SD[grepl("Manski", method)]
  list(direction = fifelse(sg > 0, "increase", "decrease"), n_checks = nrow(pp) + nrow(orr),
       all_pp_checks_agree = pp_ok, all_or_checks_agree = or_ok,
       manski_lo = bd$lo, manski_hi = bd$hi, manski_excludes_zero = bd$lo > 0 | bd$hi < 0,
       verdict = fifelse(pp_ok & or_ok, "robust (model/QC/IPW); see Manski bounds", "fragile"))
}, by = .(outcome, contrast)]
wtab(verdict, "t22_robustness_verdicts")

# =============================================================================
# 9. Added after seeing results (declared deviation): is the trust decline just a broader user pool?
# Dilution check: if earlier-year users kept their earlier level, what level among the *additional*
# users would reproduce the later aggregate? Compare with 2025 light (monthly/infrequent) users.
# =============================================================================
dil <- rbindlist(lapply(c("trust", "distrust", "fav"), function(oc) rbindlist(lapply(list(c(2023, 2024), c(2023, 2025), c(2024, 2025)), function(yy) {
  u1 <- raw[outcome == "use" & year == yy[1]]$pct; u2 <- raw[outcome == "use" & year == yy[2]]$pct
  o1 <- raw[outcome == oc & year == yy[1]]$pct; o2 <- raw[outcome == oc & year == yy[2]]$pct
  data.table(outcome = oc, contrast = paste0(yy[1], "->", yy[2]), use_from = u1, use_to = u2,
             level_from = o1, level_to = o2, implied_level_new_users = r1((u2 * o2 - u1 * o1) / (u2 - u1)))
}))))
wtab(dil, "t23_dilution_check")
fr <- rbindlist(lapply(c("y_trust", "y_distrust", "y_fav"), function(v)
  raw_props(D2[year == 2025], v, "ai_use_freq")[, outcome := sub("y_", "", v)]))
fr[, c("pct", "lo", "hi") := lapply(.SD, r1), .SDcols = c("pct", "lo", "hi")]
wtab(fr[order(outcome, ai_use_freq)], "t23b_2025_by_use_frequency")
msg("Done: %s", format(Sys.time()))
