#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 04_segments_rules.R   (stream B: AI-tool co-use baskets)
#
# Association rules (Apriori, arules) on AI-tool "have worked with" baskets WITHIN
# a year (tool lists are NOT comparable across years). Main years: 2025, 2026;
# 2023/2024 baskets are profiled for suitability and mined for completeness.
#   B23  2023  AISearchHaveWorkedWith + AIDevHaveWorkedWith (search/chat + dev assistants)
#   B24  2024  AISearchDevHaveWorkedWith
#   B25M 2025  AIModelsHaveWorkedWith (model families, "M:") + AI-native IDEs from DevEnvs ("IDE:")
#   B25A 2025  AIAgentExternal (asked ONLY of AI-agent users)
#   B26  2026  AICodeAgentHaveWorkedWith ("Agent:") + LLMHaveWorkedWith ("LLM:")
# Rules: supp >= 1% (and count >= 30), conf >= 0.25, lift >= 1.2, maxlen 3 (<= 2 tools in LHS;
# maxlen 4 is excluded from this bounded recovery), Fisher exact test (Bonferroni,
# alpha .01), non-redundant (improvement > 0). "Reportable" rules additionally need
# improvement >= 0.05 when LHS has 2 items (the multi-item antecedent must add >= 5 pp of
# confidence over every sub-rule; otherwise the rule is just the pairwise association).
# Recovery budget (exploratory, not preregistered): bootstrap (B=200) marginal
# lift intervals, three split pairs, min-support 1/2/3%; one worker.
# Baseline comparison: pairwise phi / lift / Fisher (BH).
# Outputs (aggregates only; n<30 suppressed): outputs/segments/rules_*.csv, pairwise_*.csv
# =============================================================================

a <- commandArgs(trailingOnly = FALSE)
here <- dirname(sub("^--file=", "", a[grepl("^--file=", a)]))
source(file.path(here, "04_segments_utils.R"))
suppressPackageStartupMessages({ library(arules); library(poLCA) })

PAR <- list(supp = 0.01, conf = 0.25, lift = 1.2, maxlen = 3L, alpha = 0.01, min_improvement = 0.05,
            B = 200L, n_split = 3L, stable = 0.90, supp_grid = c(0.01, 0.02, 0.03))
set.seed(SEED)
t0 <- Sys.time()

H <- load_harmonised()
B <- H[in_default_base == TRUE]

# ---- 1. Build baskets from raw files (joined to the QC'd default base) ---------
RAWF <- c(`2023` = "2023_results.csv", `2024` = "2024_results.csv", `2025` = "2025_results.csv",
          `2026` = "2026_survey_results_public.csv")
read_raw <- function(y, cols) {
  d <- fread(file.path(ROOT, "data_raw", RAWF[[as.character(y)]]), colClasses = "character",
             na.strings = c("NA", ""), select = c("ResponseId", cols), showProgress = FALSE, encoding = "UTF-8")
  d[, response_id := as.integer(ResponseId)][, ResponseId := NULL]
  d[]
}
split_items <- function(x) lapply(strsplit(ifelse(is.na(x), "", x), ";", fixed = TRUE), function(v) trimws(v[v != ""]))

MODEL_SHORT <- c("openAI GPT (chatbot models)" = "OpenAI GPT", "Anthropic: Claude Sonnet" = "Claude Sonnet",
  "Gemini (Flash general purpose models)" = "Gemini Flash", "openAI Reasoning models" = "OpenAI reasoning",
  "openAI Image generating models" = "OpenAI image", "Gemini (Pro Reasoning models)" = "Gemini Pro",
  "DeepSeek (R- Reasoning models)" = "DeepSeek R", "Meta Llama (all models)" = "Llama",
  "DeepSeek (V- General purpose models)" = "DeepSeek V", "X Grok models" = "Grok",
  "Mistral AI models" = "Mistral", "Perplexity Sonar models" = "Perplexity Sonar",
  "Alibaba Cloud Qwen models" = "Qwen", "Microsoft Phi-4 models" = "Phi-4",
  "Amazon Titan models" = "Amazon Titan", "Cohere: Command A" = "Cohere Command",
  "Reka (Flash 3 or other Reka models)" = "Reka")
AI_IDES <- c("Cursor", "Claude Code", "Windsurf", "Cline and/or Roo", "Aider", "Trae", "Lovable.dev", "Bolt")

BASKETS <- list()
b <- B[year == 2023, .(uid, response_id)]
r <- read_raw(2023, c("AISearchHaveWorkedWith", "AIDevHaveWorkedWith"))
b <- merge(b, r, by = "response_id")
b <- b[!is.na(AISearchHaveWorkedWith) | !is.na(AIDevHaveWorkedWith)]
BASKETS$B23 <- list(year = 2023, uid = b$uid, desc = "2023 AI search/chat + AI developer tools used (past year)",
  items = mapply(function(s, d) unique(c(s, d)), split_items(b$AISearchHaveWorkedWith), split_items(b$AIDevHaveWorkedWith), SIMPLIFY = FALSE))

b <- merge(B[year == 2024, .(uid, response_id)], read_raw(2024, "AISearchDevHaveWorkedWith"), by = "response_id")
b <- b[!is.na(AISearchDevHaveWorkedWith)]
BASKETS$B24 <- list(year = 2024, uid = b$uid, desc = "2024 AI search & developer tools used (past year)",
                    items = split_items(b$AISearchDevHaveWorkedWith))

r25 <- read_raw(2025, c("AIModelsHaveWorkedWith", "DevEnvsHaveWorkedWith", "AIAgentExternal", "LanguageHaveWorkedWith"))
b <- merge(B[year == 2025, .(uid, response_id)], r25, by = "response_id")
bm <- b[!is.na(AIModelsHaveWorkedWith) & !is.na(DevEnvsHaveWorkedWith)]
BASKETS$B25M <- list(year = 2025, uid = bm$uid,
  desc = "2025 AI model families used (past year) + AI-native IDEs/agents from the dev-environment list",
  items = mapply(function(m, d) c(prefix_items("M:", MODEL_SHORT[m]), prefix_items("IDE:", intersect(d, AI_IDES))),
                 split_items(bm$AIModelsHaveWorkedWith), split_items(bm$DevEnvsHaveWorkedWith), SIMPLIFY = FALSE))
stopifnot(!any(grepl("M:NA", unlist(BASKETS$B25M$items), fixed = TRUE)))
ba <- b[!is.na(AIAgentExternal)]
BASKETS$B25A <- list(year = 2025, uid = ba$uid, desc = "2025 external AI agent tools used (asked of AI-agent users only)",
                     items = split_items(ba$AIAgentExternal))

r26 <- read_raw(2026, c("AICodeAgentHaveWorkedWith", "LLMHaveWorkedWith", "LanguagesHaveWorkedWith"))
b <- merge(B[year == 2026, .(uid, response_id)], r26, by = "response_id")
b6 <- b[!is.na(AICodeAgentHaveWorkedWith) & !is.na(LLMHaveWorkedWith)]
BASKETS$B26 <- list(year = 2026, uid = b6$uid, desc = "2026 AI coding agents/assistants + LLM providers used (past year)",
  items = mapply(function(a, l) c(prefix_items("Agent:", a), prefix_items("LLM:", setdiff(l, "Other, please specify"))),
                 split_items(b6$AICodeAgentHaveWorkedWith), split_items(b6$LLMHaveWorkedWith), SIMPLIFY = FALSE))

# ---- vendor map: flags expected same-vendor rules (e.g. OpenAI GPT -> OpenAI reasoning)
vendor_of <- function(item) {
  x <- tolower(sub("^(M|IDE|Agent|LLM):", "", item))
  fcase(grepl("openai|chatgpt|codex|^gpt", x), "OpenAI", grepl("anthropic|claude", x), "Anthropic",
        grepl("google|gemini|bard|antigravity|jules", x), "Google",
        grepl("microsoft|github copilot|phi-4|bing|intellicode", x), "Microsoft",
        grepl("deepseek", x), "DeepSeek", grepl("^meta|llama", x), "Meta", grepl("mistral", x), "Mistral",
        grepl("grok|xai", x), "xAI", grepl("amazon|codewhisperer|titan|q developer", x), "Amazon",
        grepl("qwen|alibaba", x), "Alibaba", grepl("perplexity", x), "Perplexity",
        grepl("jetbrains", x), "JetBrains", grepl("cody|sourcegraph", x), "Sourcegraph",
        default = NA_character_)
}
same_vendor <- function(lhs_items, rhs_item) {
  v <- vendor_of(rhs_item); !is.na(v) && v %in% vendor_of(lhs_items)
}

# ---- 2. Basket profile & suitability ---------------------------------------------
suit <- rbindlist(lapply(names(BASKETS), function(k) {
  bk <- BASKETS[[k]]; sz <- lengths(bk$items); its <- table(unlist(bk$items))
  data.table(basket = k, year = bk$year, description = bk$desc, n_baskets = length(sz),
             n_empty = sum(sz == 0), n_distinct_items = length(its),
             n_items_supp_ge_1pct = sum(its / length(sz) >= 0.01),
             mean_size = mean(sz), median_size = median(sz), share_size_ge2 = mean(sz >= 2),
             share_size_ge3 = mean(sz >= 3), top_item = names(its)[which.max(its)],
             top_item_support = max(its) / length(sz))
}))
# Exploratory suitability screen (NOT preregistered): >= 1,000 baskets, >= 60% with 2+ items,
# >= 8 items with support >= 1%, and the most common item in < 90% of baskets.
suit[, suitable := n_baskets >= 1000 & share_size_ge2 >= 0.6 & n_items_supp_ge_1pct >= 8 & top_item_support < 0.9]
suit[, verdict := fifelse(suitable, "suitable",
  paste0("limited: ", fifelse(share_size_ge2 < 0.6, "many single-item baskets; ", ""),
         fifelse(top_item_support >= 0.9, "one tool dominates; ", ""),
         fifelse(n_items_supp_ge_1pct < 8, "few items >= 1% support; ", "")))]
fwrite(suit, file.path(OUT, "rules_basket_suitability.csv"))
print(suit[, .(basket, n_baskets, n_distinct_items, n_items_supp_ge_1pct, mean_size = round(mean_size, 2),
               share_size_ge2 = round(share_size_ge2, 3), top_item, top_item_support = round(top_item_support, 3), verdict)])

for (k in names(BASKETS)) {
  stopifnot(!any(grepl("^(M|IDE|Agent|LLM):$", unlist(BASKETS[[k]]$items))))
  ne <- lengths(BASKETS[[k]]$items) > 0
  BASKETS[[k]]$uid <- BASKETS[[k]]$uid[ne]; BASKETS[[k]]$items <- BASKETS[[k]]$items[ne]
}
TR <- lapply(BASKETS, function(bk) as(bk$items, "transactions"))

item_sup <- rbindlist(lapply(names(TR), function(k) {
  f <- itemFrequency(TR[[k]], type = "absolute"); n <- length(TR[[k]])
  w <- wilson(f, n)
  data.table(basket = k, year = BASKETS[[k]]$year, item = names(f), vendor = vendor_of(names(f)), n_baskets = n,
             count = as.integer(f), support = w$p, support_lo = w$lo, support_hi = w$hi)
}))
item_sup[count < MIN_CELL, `:=`(count = NA_integer_, support = NA_real_, support_lo = NA_real_, support_hi = NA_real_)]
setorder(item_sup, basket, -support)
fwrite(item_sup, file.path(OUT, "rules_item_support.csv"))

# ---- 3. Rule mining pipeline -------------------------------------------------------
mine <- function(tr, supp = PAR$supp, conf = PAR$conf, lift = PAR$lift, maxlen = PAR$maxlen,
                 signif = TRUE, appearance = NULL) {
  n <- length(tr)
  supp <- max(supp, MIN_CELL / n)
  rl <- suppressWarnings(apriori(tr, parameter = list(supp = supp, conf = conf, minlen = 2, maxlen = maxlen, target = "rules"),
                                 appearance = appearance, control = list(verbose = FALSE)))
  if (length(rl) == 0) return(rl)
  rl <- rl[quality(rl)$lift >= lift]
  if (length(rl) == 0) return(rl)
  if (signif) rl <- rl[is.significant(rl, tr, method = "fisher", alpha = PAR$alpha, adjust = "bonferroni")]
  if (length(rl) == 0) return(rl)
  rl[!is.redundant(rl, measure = "confidence")]
}
rule_key <- function(rl) labels(rl)

rules_tbl <- function(rl, tr, k) {
  q <- quality(rl)
  im <- interestMeasure(rl, c("leverage", "conviction", "improvement", "phi"), transactions = tr)
  L <- as(lhs(rl), "list"); R <- unlist(as(rhs(rl), "list"))
  X <- as(tr, "matrix")
  # Measure improvement against ALL proper sub-antecedents, not just rules
  # surviving pruning; otherwise an absent sub-rule spuriously inflates it.
  im$improvement <- vapply(seq_along(L), function(i) {
    ll <- L[[i]]; rhs_present <- X[,R[i]]
    subsets <- list(character())
    if(length(ll)>1) subsets <- c(subsets,lapply(ll,function(x) x))
    subconf <- vapply(subsets,function(ss) {
      hit <- if(length(ss)) rowSums(X[,ss,drop=FALSE])==length(ss) else rep(TRUE,nrow(X))
      mean(rhs_present[hit])
    },numeric(1))
    q$confidence[i]-max(subconf)
  },numeric(1))
  data.table(basket = k, year = BASKETS[[k]]$year, n_baskets = length(tr), rule = labels(rl),
             lhs = sapply(L, paste, collapse = " + "), rhs = R, lhs_size = lengths(L),
             count = q$count, support = q$support, confidence = q$confidence, coverage = q$coverage,
             lift = q$lift, leverage = im$leverage, conviction = im$conviction,
             improvement = im$improvement, phi = im$phi,
             same_vendor = mapply(same_vendor, L, R))
}

boot_stability <- function(rl, tr, B = PAR$B) {
  n <- length(tr); X <- as(tr,"matrix")
  L <- as(lhs(rl),"list"); R <- unlist(as(rhs(rl),"list"))
  rbindlist(lapply(seq_along(L),function(i) {
    aa <- rowSums(X[,L[[i]],drop=FALSE])==length(L[[i]])
    bb <- X[,R[i]]
    cells <- c(sum(aa & bb),sum(aa & !bb),sum(!aa & bb),sum(!aa & !bb))
    # Exact respondent-bootstrap marginal distribution of this 2x2 table.
    # Each rule uses its own multinomial draws; not a simultaneous interval.
    z <- rmultinom(B,n,cells/n)
    supp <- z[1,]/n; conf <- z[1,]/(z[1,]+z[2,])
    lift <- z[1,]*n/((z[1,]+z[2,])*(z[1,]+z[3,]))
    data.table(boot_stability=mean(supp>=PAR$supp & z[1,]>=MIN_CELL &
               conf>=PAR$conf & lift>=PAR$lift,na.rm=TRUE),
               lift_lo=unname(quantile(lift,.025,na.rm=TRUE)),
               lift_hi=unname(quantile(lift,.975,na.rm=TRUE)))
  }))
}

ALL <- list(); SENS <- list(); SPLIT <- list(); PAIR <- list(); CMP <- list()
for (k in names(TR)) {
  tr <- TR[[k]]; n <- length(tr)
  msg("[%s] mining %d baskets ...", k, n)
  rl <- mine(tr)
  if (length(rl) == 0) { msg("  no rules"); next }
  dt <- rules_tbl(rl, tr, k)
  set.seed(SEED + match(k, names(TR)))
  dt <- cbind(dt, boot_stability(rl, tr))
  # split-half: re-mine on each half independently; rule found in BOTH halves?
  sp <- sapply(seq_len(PAR$n_split), function(s) {
    h <- sample(n) <= n / 2
    k1 <- rule_key(mine(tr[h])); k2 <- rule_key(mine(tr[!h]))
    c(jacc = length(intersect(k1, k2)) / max(1, length(union(k1, k2))), dt$rule %in% intersect(k1, k2))
  })
  dt[, splithalf_replication := rowMeans(sp[-1, , drop = FALSE])]
  SPLIT[[k]] <- data.table(basket = k, split = seq_len(PAR$n_split), ruleset_jaccard = sp[1, ])
  dt[, stable := boot_stability >= PAR$stable & splithalf_replication >= 0.8]
  dt[, reportable := lhs_size == 1 | improvement >= PAR$min_improvement]
  ALL[[k]] <- dt
  # min-support (and maxlen) sensitivity: do the conclusions depend on the threshold?
  top_lift <- head(dt[reportable == TRUE][order(-lift)], 20)$rule
  top_lev  <- head(dt[reportable == TRUE][order(-leverage)], 20)$rule
  jac <- function(a, b) length(intersect(a, b)) / max(1, length(union(a, b)))
  grid <- data.table(s = PAR$supp_grid, ml = PAR$maxlen)
  SENS[[k]] <- rbindlist(lapply(seq_len(nrow(grid)), function(g) {
    s <- grid$s[g]; ml <- grid$ml[g]
    r2 <- mine(tr, supp = s, maxlen = ml)
    d2 <- if (length(r2)) rules_tbl(r2, tr, k)[lhs_size == 1 | improvement >= PAR$min_improvement] else
      data.table(rule = character(), lift = numeric(), leverage = numeric(), lhs_size = integer())
    data.table(basket = k, min_support = s, maxlen = ml, effective_min_count = ceiling(max(s, MIN_CELL / n) * n),
               n_rules_reportable = nrow(d2), n_rules_lhs_ge2 = sum(d2$lhs_size >= 2),
               top20_lift_jaccard_vs_baseline = jac(head(d2[order(-lift)], 20)$rule, top_lift),
               top20_leverage_jaccard_vs_baseline = jac(head(d2[order(-leverage)], 20)$rule, top_lev),
               baseline_stable_rules_retained = mean(dt[stable & reportable]$rule %in% d2$rule))
  }))
  # pairwise baseline: all pairs of items with support >= 1%
  X <- as(tr, "matrix") * 1L
  X <- X[, colMeans(X) >= PAR$supp, drop = FALSE]
  cs <- colSums(X); co <- crossprod(X)
  pr <- which(upper.tri(co), arr.ind = TRUE)
  a11 <- co[pr]; na <- cs[pr[, 1]]; nb <- cs[pr[, 2]]
  a10 <- na - a11; a01 <- nb - a11; a00 <- n - a11 - a10 - a01
  phi <- (a11 * a00 - a10 * a01) / sqrt(as.numeric(na) * nb * (n - na) * (n - nb))
  pv <- mapply(function(w, x, y, z) fisher.test(matrix(c(w, x, y, z), 2))$p.value, a11, a10, a01, a00)
  P <- data.table(basket = k, year = BASKETS[[k]]$year, n_baskets = n,
                  item_a = colnames(co)[pr[, 1]], item_b = colnames(co)[pr[, 2]],
                  count_ab = a11, support_ab = a11 / n, lift = a11 * n / (as.numeric(na) * nb),
                  leverage = a11 / n - (na / n) * (nb / n), phi = phi, p_fisher = pv)
  P[, q_bh := p.adjust(p_fisher, "BH")]
  P[, same_vendor := mapply(function(x, y) { v <- vendor_of(x); !is.na(v) && v == vendor_of(y) }, item_a, item_b)]
  P[, `:=`(sig_positive = q_bh < 0.001 & phi > 0, sig_negative = q_bh < 0.001 & phi < 0)]
  P[count_ab < MIN_CELL, `:=`(count_ab = NA_integer_, support_ab = NA_real_, lift = NA_real_,
                              leverage = NA_real_, phi = NA_real_)]
  PAIR[[k]] <- P
  # what does Apriori add beyond pairs?
  d2 <- dt[lhs_size == 1]; d3 <- dt[lhs_size >= 2]; rp <- dt[reportable == TRUE]
  pair_keys <- P[sig_positive == TRUE & phi >= 0.05, paste(pmin(item_a, item_b), pmax(item_a, item_b))]
  d2_keys <- unique(d2[, paste(pmin(lhs, rhs), pmax(lhs, rhs))])
  CMP[[k]] <- data.table(basket = k, n_rules_nonredundant = nrow(dt), n_rules_stable = sum(dt$stable),
    n_rules_reportable = nrow(rp), n_rules_reportable_stable = sum(rp$stable),
    n_rules_reportable_stable_not_same_vendor = sum(rp$stable & !rp$same_vendor),
    n_pairs_tested = nrow(P), n_pairs_sig_positive = sum(P$sig_positive), n_pairs_sig_negative = sum(P$sig_negative),
    n_pairs_phi_ge_0.1 = sum(P$phi >= 0.1, na.rm = TRUE),
    n_rules_lhs1 = nrow(d2), n_rules_lhs2 = nrow(d3),
    share_lhs2_with_improvement_ge_0.05 = if (nrow(d3)) mean(d3$improvement >= PAR$min_improvement) else NA_real_,
    n_rules_lhs2_stable_improv_ge_0.05 = sum(d3$stable & d3$improvement >= PAR$min_improvement),
    median_improvement_lhs2 = if (nrow(d3)) median(d3$improvement) else NA_real_,
    share_2item_rules_also_phi_pairs = mean(d2_keys %in% pair_keys),
    spearman_lift_phi_2item = if (nrow(d2) > 2) cor(d2$lift, d2$phi, method = "spearman") else NA_real_,
    top20_overlap_lift_vs_leverage = length(intersect(head(rp[order(-lift)], 20)$rule, head(rp[order(-leverage)], 20)$rule)) / 20,
    top20_overlap_lift_vs_conviction = length(intersect(head(rp[order(-lift)], 20)$rule, head(rp[order(-conviction)], 20)$rule)) / 20,
    share_rules_same_vendor = mean(rp$same_vendor))
}
RULES <- rbindlist(ALL)
setorder(RULES, basket, -lift)
fwrite(RULES[count >= MIN_CELL], file.path(OUT, "rules_cooccurrence_all.csv"))
fwrite(rbindlist(SENS), file.path(OUT, "rules_minsupport_sensitivity.csv"))
fwrite(rbindlist(SPLIT)[, .(ruleset_jaccard_mean = mean(ruleset_jaccard), ruleset_jaccard_min = min(ruleset_jaccard),
                             ruleset_jaccard_max = max(ruleset_jaccard)), by = basket],
       file.path(OUT, "rules_splithalf_summary.csv"))
fwrite(rbindlist(PAIR)[!is.na(count_ab)], file.path(OUT, "pairwise_cooccurrence_phi.csv"))
fwrite(rbindlist(CMP), file.path(OUT, "rules_apriori_vs_pairwise.csv"))
print(rbindlist(SENS)); print(rbindlist(CMP))

# Attribute-rule search is excluded from the bounded recovery budget.
saveRDS(list(PAR = PAR), file.path(CACHE, "rules_params.rds"))
fwrite(data.table(stage="rules",seconds=as.numeric(difftime(Sys.time(),t0,units="secs")),
                  workers=1L,bootstrap_draws_per_rule=PAR$B,split_pairs=PAR$n_split),
       file.path(OUT,"rules_runtime.csv"))
msg("Done.")
