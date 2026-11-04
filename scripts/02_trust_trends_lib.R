# =============================================================================
# AI Adoption Atlas -- 02_trust_trends_lib.R
# Shared helpers for the trust-trends ("say vs do") stream. Sourced by
# 02_trust_trends.R and 02_trust_trends_figs.R. Writes nothing.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(MASS)
})

get_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1) return(normalizePath(file.path(dirname(f), ".."), winslash = "/"))
  normalizePath(".", winslash = "/")
}
ROOT <- get_root()
OUT  <- file.path(ROOT, "outputs", "trust_trends")
TAB  <- file.path(OUT, "tables")
FIG  <- file.path(OUT, "figures")
SITE <- file.path(ROOT, "site_data")
for (p in c(TAB, FIG, SITE)) dir.create(p, showWarnings = FALSE, recursive = TRUE)
msg <- function(...) cat(sprintf(...), "\n", sep = "")

YEARS_A <- 2023:2025
Z <- qnorm(0.975)

# ---- proportions ------------------------------------------------------------
wilson <- function(x, n) {
  p <- ifelse(n > 0, x / n, NA_real_)
  den <- 1 + Z^2 / n
  ctr <- (p + Z^2 / (2 * n)) / den
  hw  <- Z * sqrt(p * (1 - p) / n + Z^2 / (4 * n^2)) / den
  list(p = p, lo = pmax(0, ctr - hw), hi = pmin(1, ctr + hw))
}
# Newcombe hybrid-Wilson CI for p2 - p1
newcombe <- function(x1, n1, x2, n2) {
  a <- wilson(x1, n1); b <- wilson(x2, n2)
  d <- b$p - a$p
  lo <- d - sqrt((b$p - b$lo)^2 + (a$hi - a$p)^2)
  hi <- d + sqrt((b$hi - b$p)^2 + (a$p - a$lo)^2)
  list(d = d, lo = lo, hi = hi)
}
ztest_p <- function(x1, n1, x2, n2) {
  p1 <- x1 / n1; p2 <- x2 / n2; pp <- (x1 + x2) / (n1 + n2)
  se <- sqrt(pp * (1 - pp) * (1 / n1 + 1 / n2))
  2 * pnorm(-abs((p2 - p1) / se))
}
cohen_h <- function(p1, p2) 2 * asin(sqrt(p2)) - 2 * asin(sqrt(p1))

# weighted proportion with Kish effective n (used for IPW)
wprop <- function(y, w) {
  ok <- !is.na(y); y <- y[ok]; w <- w[ok]
  p <- sum(w * y) / sum(w); neff <- sum(w)^2 / sum(w^2)
  ci <- wilson(p * neff, neff)
  list(p = p, lo = ci$lo, hi = ci$hi, neff = neff, n = length(y))
}

# ---- covariates --------------------------------------------------------------
REGION_SHORT <- c("Europe & Central Asia" = "Europe & C. Asia", "North America" = "North America",
  "East Asia & Pacific" = "East Asia & Pacific", "South Asia" = "South Asia",
  "Latin America & Caribbean" = "Latin America & Carib.",
  "Middle East, North Africa, Afghanistan & Pakistan" = "MENA, Afg. & Pakistan",
  "Sub-Saharan Africa" = "Sub-Saharan Africa")
EXP_LEVELS <- c("0-4 yrs", "5-9 yrs", "10-19 yrs", "20+ yrs")
COVS <- c("exp_band", "role_f", "region_f", "org_f")

fmiss <- function(x, lev = NULL) {
  x <- as.character(x); x[is.na(x)] <- "Missing"
  if (is.null(lev)) lev <- c(sort(setdiff(unique(x), "Missing")), "Missing")
  factor(x, levels = unique(c(lev, "Missing")))
}

load_data <- function() {
  H <- as.data.table(read_parquet(file.path(ROOT, "data_clean", "ai_harmonised.parquet")))
  H[, age_chr := as.character(age_band)]
  H[, adult := !is.na(age_chr) & !(age_chr %in% c("Under 18", "Prefer not to say"))]
  H[, exp_chr := fcase(is.na(years_code), NA_character_, years_code < 5, EXP_LEVELS[1],
                       years_code < 10, EXP_LEVELS[2], years_code < 20, EXP_LEVELS[3],
                       default = EXP_LEVELS[4])]
  H[, exp_band := fmiss(exp_chr, EXP_LEVELS)]
  H[, role_f   := fmiss(role_family, c("Developer / software engineer", "Data / AI / analytics",
                     "Ops / infra / security / support", "Management / exec / product",
                     "Research / education", "Student", "Other"))]
  H[, region_s := unname(REGION_SHORT[region])]
  H[, region_f := fmiss(region_s, unname(REGION_SHORT))]
  H[, org_f    := fmiss(org_size, c("Just me", "2-19", "20-99", "100-499", "500-999",
                     "1,000-4,999", "5,000-9,999", "10,000+", "Don't know"))]
  H[, age_f    := fmiss(age_chr, c("18-24", "25-34", "35-44", "45-54", "55-64", "65+"))]
  H[, emp_f    := fmiss(employment_status)]
  H[, edu_f    := fmiss(education)]
  H[, remote_f := fmiss(remote_work)]
  # populations
  H[, elig_all := is_professional_dev & adult & !qc_exclude]          # before AISelect dropout
  H[, P1 := elig_all & in_default_base]
  H[, P2 := P1 & ai_user %in% TRUE]
  H[, P3 := P1 & ai_use_status %in% c("Using", "Plan to use")]
  # outcomes
  H[, y_use      := ai_use_status %in% "Using"]
  H[, y_plan     := ai_use_status %in% "Plan to use"]
  H[, y_fav      := ai_sent_favorable]
  H[, y_fav_ex   := fifelse(is.na(ai_sent_5), NA, ai_sent_5 >= 4)]
  H[, y_trust    := fifelse(is.na(ai_trust_5), NA, ai_trust_5 >= 4)]
  H[, y_distrust := fifelse(is.na(ai_trust_5), NA, ai_trust_5 <= 2)]
  H[, y_complex  := fifelse(is.na(ai_complex_5), NA, ai_complex_5 >= 4)]
  H[, y_threat   := fifelse(is.na(ai_threat), NA, ai_threat == "Yes")]
  H[]
}

# ---- raw proportion table ----------------------------------------------------
raw_props <- function(d, y, by) {
  r <- d[!is.na(get(y)), .(x = sum(get(y)), n = .N), by = by]
  ci <- wilson(r$x, r$n)
  r[, `:=`(pct = 100 * ci$p, lo = 100 * ci$lo, hi = 100 * ci$hi)]
  r[]
}

# ---- model-based marginal standardisation (g-computation) ----------------------
agg_binom <- function(d, y, vars) d[!is.na(get(y)), .(s = sum(get(y)), n = .N), by = vars]

fit_binom <- function(ag, rhs) glm(as.formula(paste("cbind(s, n - s) ~", rhs)), binomial, data = droplevels(ag))

# target: data.table of covariate patterns with weight column w
# settings: data.table of override columns (one row per scenario)
gcomp <- function(fit, target, settings, nsim = 2000) {
  b <- coef(fit); ok <- !is.na(b)
  V <- vcov(fit)[ok, ok, drop = FALSE]
  Bs <- mvrnorm(nsim, b[ok], V)
  tt <- delete.response(terms(fit))
  pts <- numeric(nrow(settings)); dr <- matrix(NA_real_, nsim, nrow(settings))
  for (i in seq_len(nrow(settings))) {
    nd <- copy(target)
    for (v in names(settings)) set(nd, j = v, value = settings[[v]][i])
    for (v in names(fit$xlevels)) set(nd, j = v, value = factor(as.character(nd[[v]]), levels = fit$xlevels[[v]]))
    keep <- complete.cases(nd[, names(fit$xlevels), with = FALSE])
    nd <- nd[keep]
    X <- model.matrix(tt, model.frame(tt, nd, xlev = fit$xlevels))[, ok, drop = FALSE]
    w <- nd$w / sum(nd$w)
    pts[i] <- sum(w * plogis(X %*% b[ok]))
    dr[, i] <- colSums(w * plogis(X %*% t(Bs)))
  }
  list(point = pts, draws = dr)
}
# year contrasts (2023->2024, 2024->2025, 2023->2025) as odds ratios from yearf2024/yearf2025 coefs
or_contr <- function(b, V, outcome, model) {
  b <- b[c("yearf2024", "yearf2025")]; V <- as.matrix(V)[names(b), names(b)]
  L <- rbind(c(1, 0), c(-1, 1), c(0, 1))
  est <- drop(L %*% b); se <- sqrt(diag(L %*% V %*% t(L)))
  data.table(outcome = outcome, contrast = c("2023->2024", "2024->2025", "2023->2025"),
             OR = exp(est), lo = exp(est - Z * se), hi = exp(est + Z * se),
             p = 2 * pnorm(-abs(est / se)), model = model)
}
sim_ci <- function(dr) c(lo = unname(quantile(dr, .025)), hi = unname(quantile(dr, .975)))
sim_p  <- function(dr, point) 2 * pnorm(-abs(point / sd(dr)))
