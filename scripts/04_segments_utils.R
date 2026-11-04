# =============================================================================
# AI Adoption Atlas -- 04_segments_utils.R
# Shared helpers for the segmentation stream (04_segments_*.R).
# Only aggregated outputs are written (outputs/segments/, site_data/segments.json).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

get_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1) return(normalizePath(file.path(dirname(f), ".."), winslash = "/"))
  normalizePath(".", winslash = "/")
}
ROOT  <- get_root()
OUT   <- file.path(ROOT, "outputs", "segments")
FIG   <- file.path(OUT, "figures")
CACHE <- file.path(OUT, "_model_params")   # model PARAMETERS only (no respondent rows)
SITE  <- file.path(ROOT, "site_data")
for (p in c(OUT, FIG, CACHE, SITE)) dir.create(p, showWarnings = FALSE, recursive = TRUE)
msg <- function(...) cat(sprintf(...), "\n", sep = "")
prefix_items <- function(prefix, x) if (length(x)) paste0(prefix, x) else character()

MIN_CELL <- 30L   # disclosure / precision rule: suppress any cell with n < 30
SEED     <- 20261104L

# ---- Wilson score interval ---------------------------------------------------
wilson <- function(x, n, z = 1.959964) {
  len <- max(length(x),length(n))
  x <- rep_len(x,len); n <- rep_len(n,len)
  p <- ifelse(n > 0, x / n, NA_real_)
  den <- 1 + z^2 / n
  ctr <- (p + z^2 / (2 * n)) / den
  hw  <- z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den
  list(p = p, lo = pmax(0, ctr - hw), hi = pmin(1, ctr + hw))
}

# ---- Load harmonised table ---------------------------------------------------
load_harmonised <- function() {
  f <- file.path(ROOT, "data_clean", "ai_harmonised.parquet")
  if (!file.exists(f)) stop("Run scripts/01_harmonise.R first (missing ", f, ")")
  as.data.table(read_parquet(f))
}

exp_band <- function(y) cut(y, c(-Inf, 4, 9, 19, Inf), labels = c("0-4 yrs", "5-9 yrs", "10-19 yrs", "20+ yrs"))

# ---- LCA indicator coding (integers 1..K; NA = not answered) -----------------
# Category labels are kept in IND_LABELS so profiles can be written out readably.
IND_LABELS <- list(
  USE5   = c("Daily", "Weekly", "Monthly/infrequent", "Plan to use", "No use, no plans"),
  SENT6  = c("Very favourable", "Favourable", "Indifferent/neutral", "Unfavourable", "Very unfavourable", "Unsure"),
  TRUST4 = c("Trust (highly/somewhat)", "Neither", "Somewhat distrust", "Highly distrust"),
  CPLX5  = c("Good/very good", "Neither", "Bad", "Very poor", "Don't use for complex/don't know"),
  THREAT3= c("No threat", "Not sure", "Threat"),
  AGENT4 = c("Uses agents", "Autocomplete/copilot mode only", "Plans agents", "No agents, no plans"),
  WF4    = c("0 tasks", "1-2 tasks", "3-5 tasks", "6+ tasks"),
  FREQ3  = c("Daily", "Weekly", "Monthly/infrequent"),
  TRUST26= c("Trust incl. important decisions", "Trust many tasks, not important decisions",
             "Trust when easy to verify", "Low-risk tasks only", "Do not trust for most tasks"),
  AGENT2 = c("Uses AI agents/automated workflows", "No agents")
)
IND_NAMES <- c(USE5 = "AI use", SENT6 = "Sentiment", TRUST4 = "Trust in accuracy",
               CPLX5 = "Complex-task ability", THREAT3 = "Job threat", AGENT4 = "AI agents",
               WF4 = "Workflow tasks using AI", FREQ3 = "AI use frequency",
               TRUST26 = "Trust (2026 conditional)", AGENT2 = "Agents (2026)")

code_indicators <- function(D) {
  wf_cols <- grep("^aiw_", names(D), value = TRUE)
  wf_n <- rowSums(as.matrix(D[, ..wf_cols]), na.rm = TRUE)
  wf_n[!(D$ai_workflow_answered %in% TRUE)] <- NA
  D[, `:=`(
    USE5 = fcase(ai_use_freq == "Daily", 1L, ai_use_freq == "Weekly", 2L,
                 ai_use_freq == "Monthly or infrequent", 3L,
                 ai_use_status == "Plan to use", 4L, ai_use_status == "Not using, no plans", 5L),
    SENT6 = fcase(ai_sent_raw == "Very favorable", 1L,
                  ai_sent_raw %in% c("Favorable", "Somewhat favorable"), 2L,
                  ai_sent_raw %in% c("Indifferent", "Neutral"), 3L,
                  ai_sent_raw %in% c("Unfavorable", "Somewhat unfavorable"), 4L,
                  ai_sent_raw == "Very unfavorable", 5L,
                  ai_sent_raw %in% c("Unsure", "Not sure"), 6L),
    TRUST4 = fcase(ai_trust_5 >= 4, 1L, ai_trust_5 == 3, 2L, ai_trust_5 == 2, 3L, ai_trust_5 == 1, 4L),
    CPLX5 = fcase(ai_complex_5 >= 4, 1L, ai_complex_5 == 3, 2L, ai_complex_5 == 2, 3L,
                  ai_complex_5 == 1, 4L, !is.na(ai_complex_raw), 5L),
    THREAT3 = fcase(ai_threat == "No", 1L, ai_threat == "Not sure", 2L, ai_threat == "Yes", 3L),
    AGENT4 = fcase(grepl("^Yes", ai_agents_raw), 1L,
                   grepl("copilot/autocomplete", ai_agents_raw), 2L,
                   ai_agents_raw == "No, but I plan to", 3L,
                   ai_agents_raw == "No, and I don't plan to", 4L),
    WF4 = fcase(wf_n == 0, 1L, wf_n <= 2, 2L, wf_n <= 5, 3L, wf_n >= 6, 4L),
    FREQ3 = fcase(ai_use_freq == "Daily", 1L, ai_use_freq == "Weekly", 2L,
                  ai_use_freq == "Monthly or infrequent", 3L),
    TRUST26 = fcase(grepl("including important", ai_trust_raw), 1L,
                    grepl("not important", ai_trust_raw), 2L,
                    grepl("easily verify", ai_trust_raw), 3L,
                    grepl("low-risk", ai_trust_raw), 4L,
                    grepl("do not trust it for most", ai_trust_raw), 5L),
    AGENT2 = fcase(ai_type_agents %in% TRUE, 1L, ai_use_status == "Using", 2L)
  )]
  D[year != 2026, `:=`(TRUST26 = NA_integer_, AGENT2 = NA_integer_)]
  D[year != 2025, `:=`(AGENT4 = NA_integer_)]
  invisible(D)
}

# ---- LCA helpers --------------------------------------------------------------
lca_formula <- function(vars) as.formula(paste0("cbind(", paste(vars, collapse = ","), ") ~ 1"))

fit_lca <- function(Y, K, nrep, seed, maxiter = 1200) {
  set.seed(seed)
  m <- poLCA::poLCA(lca_formula(names(Y)), as.data.frame(Y), nclass = K, nrep = nrep,
                    maxiter = maxiter, na.rm = FALSE, verbose = FALSE, calc.se = FALSE)
  m
}

strip_lca <- function(m, vars) {
  list(K = length(m$P), P = m$P, probs = m$probs, llik = m$llik, npar = m$npar,
       N = m$N, Nobs = m$Nobs, bic = m$bic, aic = m$aic, attempts = m$attempts,
       numiter = m$numiter, maxiter = if (is.null(m$maxiter)) 1200L else m$maxiter, vars = vars)
}

lca_posterior <- function(par, Y) {
  y <- as.matrix(as.data.table(Y)[, par$vars, with = FALSE])
  lp <- matrix(log(pmax(par$P, 1e-300)), nrow(y), par$K, byrow = TRUE)
  for (j in seq_along(par$vars)) {
    p <- par$probs[[par$vars[j]]]
    ok <- !is.na(y[, j]) & y[, j] > 0
    if (any(y[ok, j] > ncol(p))) stop("Category absent from fitted model")
    if (any(ok)) lp[ok, ] <- lp[ok, , drop = FALSE] +
      t(log(pmax(p[, y[ok, j], drop = FALSE], 1e-300)))
  }
  pp <- exp(lp - apply(lp, 1, max))
  pp / rowSums(pp)
}

rel_entropy <- function(post) {
  K <- ncol(post); if (K < 2) return(NA_real_)
  p <- pmax(post, 1e-300)
  1 - sum(-post * log(p)) / (nrow(post) * log(K))
}

# permute class order of a stripped model
permute_lca <- function(par, ord) {
  par$P <- par$P[ord]
  par$probs <- lapply(par$probs, function(m) m[ord, , drop = FALSE])
  par
}

# maximum Jaccard of each reference class with any class of a comparison partition
class_jaccard <- function(ref, cmp, K) {
  sapply(seq_len(K), function(k) {
    a <- ref == k
    if (!any(a)) return(NA_real_)
    max(sapply(unique(cmp), function(j) { b <- cmp == j; sum(a & b) / sum(a | b) }))
  })
}

# all permutations (for matching classes across models, K <= 7)
perms <- function(v) {
  if (length(v) <= 1) return(list(v))
  out <- list()
  for (i in seq_along(v)) for (p in perms(v[-i])) out[[length(out) + 1]] <- c(v[i], p)
  out
}

# best matching of classes of par_b to par_a by item-response probabilities (min total L1)
match_classes <- function(par_a, par_b) {
  K <- par_a$K
  D <- matrix(0, K, K)
  for (v in par_a$vars) D <- D + as.matrix(dist(rbind(par_a$probs[[v]], par_b$probs[[v]]), "manhattan"))[1:K, K + 1:K]
  pp <- perms(seq_len(K))
  cost <- sapply(pp, function(p) sum(D[cbind(seq_len(K), p)]))
  best <- pp[[which.min(cost)]]
  list(perm = best, mean_tvd = sum(D[cbind(seq_len(K), best)]) / (2 * K * length(par_a$vars)))
}

# profile table: long format of item-response probabilities
profile_long <- function(par, class_names = NULL) {
  if (is.null(class_names)) class_names <- paste0("Class ", seq_len(par$K))
  rbindlist(lapply(par$vars, function(v) {
    pr <- par$probs[[v]]
    lab <- IND_LABELS[[v]][seq_len(ncol(pr))]
    rbindlist(lapply(seq_len(par$K), function(k)
      data.table(class_id = k, class_name = class_names[k], indicator = v,
                 indicator_label = IND_NAMES[[v]], category_id = seq_len(ncol(pr)),
                 category = lab, prob = as.numeric(pr[k, ]))))
  }))
}
