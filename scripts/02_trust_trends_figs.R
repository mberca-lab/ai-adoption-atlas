#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 02_trust_trends_figs.R
# Figures (PNG + alt-text manifest) and site_data/trust_trends.json, built ONLY
# from the aggregate tables written by 02_trust_trends.R.
# =============================================================================
local({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  source(file.path(if (length(f)) dirname(f) else "scripts", "02_trust_trends_lib.R"))
}, envir = globalenv())
suppressPackageStartupMessages({ library(ggplot2); library(jsonlite); library(scales) })
rt <- function(n) fread(file.path(TAB, paste0(n, ".csv")))

CAP <- paste0("Data: Stack Overflow Developer Survey 2023-2026 (Stack Exchange Inc., ODbL 1.0). Unweighted, self-selected sample; ",
              "95% CIs ignore self-selection. Stated sentiment, not behaviour.")
OK <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9", "#000000")
th <- theme_minimal(base_size = 12) + theme(plot.title = element_text(face = "bold", size = 14),
  plot.caption = element_text(size = 8, colour = "grey35", hjust = 0), legend.position = "bottom",
  panel.grid.minor = element_blank(), plot.title.position = "plot", plot.caption.position = "plot",
  strip.text.y = element_text(angle = 0, hjust = 0, face = "bold"))
brk <- list(geom_vline(xintercept = 2025.5, linetype = "dashed", colour = "grey40"),
            annotate("text", x = 2025.55, y = Inf, label = "series break:\n2026 question changed", hjust = 0, vjust = 1.2,
                     size = 3, colour = "grey30"),
            scale_x_continuous(breaks = 2023:2026, limits = c(2022.8, 2026.6)))
manifest <- list()
save_fig <- function(p, file, title, alt, src, w = 9, h = 5.6) {
  if (!is.null(p$labels$subtitle)) p$labels$subtitle <- paste(unlist(lapply(strsplit(p$labels$subtitle, "\n")[[1]],
    function(l) strwrap(l, width = round(12.5 * w)))), collapse = "\n")
  ggsave(file.path(FIG, file), p + labs(caption = CAP) + th, width = w, height = h, dpi = 200, bg = "white")
  manifest[[length(manifest) + 1]] <<- data.table(file = file, title = title, alt_text = alt, source_tables = src)
  msg("  %s", file)
}
f1 <- function(x) formatC(x, format = "f", digits = 1)

raw <- rt("t01_raw_by_year"); std <- rt("t06_standardised_by_year"); comp <- rt("t17_completion_and_adoption_bounds")
LAB <- c(use = "Use AI tools (all pro devs)", plan = "Plan to use (all pro devs)", fav = "Favourable (users)",
         trust = "Trust accuracy (users)", distrust = "Distrust accuracy (users)")

# ---- F1 adoption ---------------------------------------------------------------
d <- raw[outcome %in% c("use", "plan") & !(outcome == "plan" & year == 2026)]
d[, lab := LAB[outcome]]
s <- std[outcome == "use"]; b <- comp[year >= 2024]
p <- ggplot(d, aes(year, pct, colour = lab)) +
  geom_linerange(data = b, aes(x = year + 0.12, ymin = use_lower_pct, ymax = use_upper_pct), inherit.aes = FALSE,
                 colour = "grey60", linewidth = 2.2, alpha = .6) +
  geom_line(data = d[year <= 2025], linewidth = 1) + geom_pointrange(aes(ymin = lo, ymax = hi), size = .5) +
  geom_point(data = s, aes(year - 0.12, std_pct), inherit.aes = FALSE, shape = 5, size = 2.4, colour = OK[1]) +
  geom_text(data = d, aes(label = paste0(f1(pct), "%")), vjust = -1.1, size = 3.3, show.legend = FALSE) +
  brk + scale_colour_manual(values = setNames(OK[1:2], LAB[c("use", "plan")]), name = NULL) + scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(title = "Professional developers' AI use rose from 44% to 81% (2023-2025)",
       subtitle = "Share of professional developers using / planning to use AI tools. Diamonds = standardised to a fixed role/experience/region/org-size mix;\ngrey bars = worst/best-case bounds if respondents who quit before the AI question were all non-users / all users.",
       x = NULL, y = "% of professional developers")
save_fig(p, "f1_adoption.png", "AI adoption among professional developers, 2023-2026",
  sprintf("Line chart. Share of professional developers using AI tools rose from %s%% in 2023 to %s%% in 2024 and %s%% in 2025; 'plan to use' fell from %s%% to %s%%. 2026 (%s%%) is shown after a dashed series break because the question changed. Grey dropout bounds widen to %s-%s%% in 2025 and %s-%s%% in 2026.",
    f1(raw[outcome == "use" & year == 2023]$pct), f1(raw[outcome == "use" & year == 2024]$pct), f1(raw[outcome == "use" & year == 2025]$pct),
    f1(raw[outcome == "plan" & year == 2023]$pct), f1(raw[outcome == "plan" & year == 2025]$pct), f1(raw[outcome == "use" & year == 2026]$pct),
    f1(comp[year == 2025]$use_lower_pct), f1(comp[year == 2025]$use_upper_pct), f1(comp[year == 2026]$use_lower_pct), f1(comp[year == 2026]$use_upper_pct)),
  "t01_raw_by_year; t06_standardised_by_year; t17_completion_and_adoption_bounds")

# ---- F2 say vs do ----------------------------------------------------------------
d <- raw[outcome %in% c("use", "fav", "trust", "distrust")]; d[, lab := factor(LAB[outcome], levels = LAB[c("use", "fav", "trust", "distrust")])]
p <- ggplot(d, aes(year, pct, colour = lab)) + geom_line(data = d[year <= 2025], linewidth = 1.1) +
  geom_pointrange(aes(ymin = lo, ymax = hi), size = .45) +
  ggrepel::geom_text_repel(data = d[year %in% c(2023, 2025, 2026)], aes(label = f1(pct)), nudge_x = ifelse(d[year %in% c(2023, 2025, 2026)]$year == 2025, 0.18, -0.18), direction = "y", min.segment.length = Inf, size = 3.1, show.legend = FALSE, seed = 1) +
  brk + scale_colour_manual(values = OK[c(1, 3, 5, 2)], name = NULL) + scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  guides(colour = guide_legend(nrow = 2)) +
  labs(title = "Say vs do: use climbs while trust erodes", x = NULL, y = "%",
       subtitle = "Use = % of professional developers. Favourable / trust / distrust = % of current AI users (trust in the accuracy of AI output).\nTrust is not comparable in 2026 (new conditional-trust question), so no 2026 trust point is shown.")
save_fig(p, "f2_say_vs_do.png", "Use rises while favourability and trust fall",
  sprintf("Line chart 2023-2025 with 2026 after a series break. Use among professional developers: %s%% to %s%%. Among users, favourable: %s%% to %s%% (2026: %s%%); trust in accuracy: %s%% to %s%%; distrust: %s%% to %s%%. Distrust and trust are nearly equal by 2025.",
    f1(raw[outcome == "use" & year == 2023]$pct), f1(raw[outcome == "use" & year == 2025]$pct),
    f1(raw[outcome == "fav" & year == 2023]$pct), f1(raw[outcome == "fav" & year == 2025]$pct), f1(raw[outcome == "fav" & year == 2026]$pct),
    f1(raw[outcome == "trust" & year == 2023]$pct), f1(raw[outcome == "trust" & year == 2025]$pct),
    f1(raw[outcome == "distrust" & year == 2023]$pct), f1(raw[outcome == "distrust" & year == 2025]$pct)),
  "t01_raw_by_year")

# ---- F3 paradox within subgroups ------------------------------------------------------
pr <- rt("t11_paradox_subgroup_contrasts"); pv <- rt("t11b_paradox_verdict_by_subgroup")
pr[, lab := factor(LAB[outcome], levels = LAB[c("use", "trust", "distrust")])]
pr <- merge(pr, pv[, .(dimension, level, paradox_holds)], by = c("dimension", "level"))
pr[, level2 := paste0(level, ifelse(paradox_holds, "", "  (trust fall n.s.)"))]
pr[, dimension := factor(dimension, levels = c("Experience (years coding)", "Role family", "Region"))]
p <- ggplot(pr, aes(diff_pp, level2, colour = lab)) + geom_vline(xintercept = 0, colour = "grey50") +
  geom_pointrange(aes(xmin = lo, xmax = hi), size = .3, position = position_dodge(width = .5)) +
  facet_grid(dimension ~ ., scales = "free_y", space = "free_y", labeller = labeller(dimension = label_wrap_gen(12))) + scale_colour_manual(values = OK[c(1, 5, 2)], name = NULL) +
  labs(title = "The paradox holds in most subgroups: use up, trust down, distrust up (2023 -> 2025)",
       subtitle = sprintf("Change in percentage points with 95%% Newcombe CIs; BH-adjusted across all %d tests.\nParadox (use up AND trust down, both significant) in %d of %d subgroups; distrust rose significantly in %d of %d.",
                          nrow(pr), sum(pv$paradox_holds), nrow(pv), sum(pv$distrust_rises), nrow(pv)),
       x = "Change 2023 -> 2025 (percentage points)", y = NULL) + theme(strip.text.y = element_text(angle = 0, hjust = 0))
save_fig(p, "f3_paradox_subgroups.png", "Use-trust paradox within experience, role and region subgroups",
  sprintf("Dot-and-whisker chart of 2023-to-2025 changes by subgroup. Use rose by %s to %s points in every subgroup; distrust rose significantly in %d of %d subgroups; trust fell significantly in %d of %d. Subgroups where the trust fall was not significant: %s.",
    f1(min(pr[outcome == "use"]$diff_pp)), f1(max(pr[outcome == "use"]$diff_pp)), sum(pv$distrust_rises), nrow(pv), sum(pv$paradox_holds), nrow(pv),
    paste(pv[paradox_holds == FALSE]$level, collapse = ", ")),
  "t11_paradox_subgroup_contrasts; t11b_paradox_verdict_by_subgroup", h = 7.5)

# ---- F4 experience gradient ------------------------------------------------------------
eg <- rt("t12_experience_gradient_levels"); wd <- rt("t13_experience_gradient_widening")
eg[, exp_band := factor(exp_band, levels = EXP_LEVELS)]
eg[, panel := factor(c(trust = "Trust accuracy", distrust = "Distrust accuracy", fav = "Favourable")[outcome],
                     levels = c("Trust accuracy", "Distrust accuracy", "Favourable"))]
eg[, yr := factor(ifelse(year == 2026, "2026 (series B)", as.character(year)))]
p <- ggplot(eg, aes(exp_band, std_pct, colour = yr, group = yr)) + geom_line(aes(linetype = year == 2026), linewidth = .9) +
  geom_pointrange(aes(ymin = lo, ymax = hi), size = .3) + facet_wrap(~panel, scales = "free_y") +
  scale_colour_manual(values = OK[c(6, 1, 2, 7)], name = NULL) + scale_linetype_manual(values = c(1, 2), guide = "none") +
  labs(title = "Senior developers trust AI output less - but the gap is not widening",
       subtitle = sprintf("Standardised %% of AI users (role/region/org mix held fixed). 20+ vs 0-4 years coding: trust gap %s pts (2023) vs %s (2025), widening %s [%s, %s];\ndistrust gap %s vs %s. Favourability: no gap 2023-25, but seniors more favourable in 2026 (+%s pts, series B).",
         f1(wd[outcome == "trust"]$gap_2023_pp), f1(wd[outcome == "trust"]$gap_2025_pp), f1(wd[outcome == "trust"]$widening_pp),
         f1(wd[outcome == "trust"]$widening_lo), f1(wd[outcome == "trust"]$widening_hi),
         f1(wd[outcome == "distrust"]$gap_2023_pp), f1(wd[outcome == "distrust"]$gap_2025_pp), f1(wd[outcome == "fav"]$gap_2026_seriesB_pp)),
       x = "Years coding", y = "% of AI users (standardised)")
save_fig(p, "f4_experience_gradient.png", "Experience gradient in trust, distrust and favourability",
  sprintf("Three-panel line chart by years of coding experience. In every year 2023-2025, developers with 20+ years trust AI accuracy less than those with 0-4 years (gap %s points in 2023, %s in 2025) and distrust it more (gap %s and %s); the gap did not widen significantly (interaction p = %s). Favourability shows no experience gap 2023-2025; in 2026 seniors are %s points more favourable.",
    f1(wd[outcome == "trust"]$gap_2023_pp), f1(wd[outcome == "trust"]$gap_2025_pp), f1(wd[outcome == "distrust"]$gap_2023_pp), f1(wd[outcome == "distrust"]$gap_2025_pp),
    formatC(wd[outcome == "trust"]$lr_interaction_p, digits = 2, format = "f"), f1(wd[outcome == "fav"]$gap_2026_seriesB_pp)),
  "t12_experience_gradient_levels; t13_experience_gradient_widening", w = 10.5)

# ---- F5 favourability by subgroup --------------------------------------------------------
sy <- rt("t10_subgroup_by_year")[outcome == "fav" & year %in% c(2023, 2025, 2026)]
sy <- sy[n >= 100]
sy[, yr := factor(ifelse(year == 2026, "2026 (series B)", as.character(year)), levels = c("2023", "2025", "2026 (series B)"))]
sy[, dimension := factor(dimension, levels = c("Age band", "Experience (years coding)", "Role family", "Region"))]
fs <- rt("t11c_favourability_subgroup_contrasts")
seg <- dcast(sy[year %in% c(2023, 2025)], dimension + level ~ year, value.var = "pct"); setnames(seg, c("dimension", "level", "a", "b"))
p <- ggplot(sy, aes(pct, level)) + geom_segment(data = seg, aes(x = a, xend = b, y = level, yend = level), colour = "grey70", linewidth = 1.2) +
  geom_point(aes(colour = yr, shape = yr), size = 2.4) + facet_grid(dimension ~ ., scales = "free_y", space = "free_y", labeller = labeller(dimension = label_wrap_gen(12))) +
  scale_colour_manual(values = OK[c(6, 1, 2)], name = NULL) + scale_shape_manual(values = c(16, 16, 17), name = NULL) +
  scale_x_continuous(labels = function(x) paste0(x, "%")) +
  labs(title = "Favourability among AI users fell in every subgroup", x = "% favourable (AI users)", y = NULL,
       subtitle = sprintf("2023 -> 2025 decline significant (BH) in %d of %d subgroups; range %s to %s points. 2026 uses relabelled options (series break).",
                          sum(fs$decline_sig), nrow(fs), f1(max(fs$diff_pp)), f1(min(fs$diff_pp)))) +
  theme(strip.text.y = element_text(angle = 0, hjust = 0))
save_fig(p, "f5_favourability_subgroups.png", "Favourability among AI users by age, experience, role and region",
  sprintf("Dumbbell chart of favourable share among AI users in 2023 and 2025 with 2026 triangles. Favourability fell significantly in all %d subgroups between 2023 and 2025, by %s (South Asia) to %s points; 2026 values are lower again but use a relabelled scale.",
    nrow(fs), f1(max(fs$diff_pp)), f1(min(fs$diff_pp))), "t10_subgroup_by_year; t11c_favourability_subgroup_contrasts", h = 8)

# ---- F6 complexity ------------------------------------------------------------------------
cx <- raw[outcome == "complex_good"]; orr <- rt("t14_complexity_predicts_favourability")
cx <- merge(cx, orr[, .(year, OR_fav_per_point, olo = lo, ohi = hi)], by = "year")
p <- ggplot(cx, aes(year, pct)) + geom_col(fill = ifelse(cx$year == 2026, "grey65", OK[1]), width = .6) +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = .15) +
  geom_text(aes(label = paste0(f1(pct), "%")), vjust = -1.2, size = 3.5) +
  geom_text(aes(y = 4, label = sprintf("OR per +1 pt:\n%.2f [%.2f, %.2f]", OR_fav_per_point, olo, ohi)), colour = "white", size = 3, vjust = 0) +
  brk + scale_y_continuous(limits = c(0, 75), labels = function(x) paste0(x, "%")) +
  labs(title = "Perceived complex-task ability: small gain 2024-25; strongly tied to favourability",
       subtitle = "% of AI users rating AI good/very good at complex tasks (among those giving a rating). 2026 wording adds 'or agents' (series break).\nInside bars: adjusted odds ratio of being favourable per +1 point on the 5-point complexity rating, within year.",
       x = NULL, y = "% of raters")
save_fig(p, "f6_complexity.png", "Perceived complex-task capability and its link to favourability",
  sprintf("Bar chart. Share of AI users rating AI good or very good at complex tasks: %s%% (2024), %s%% (2025), %s%% (2026, changed wording). Within each year, each extra point on the complexity rating is associated with about %s-%s times the odds of being favourable.",
    f1(cx[year == 2024]$pct), f1(cx[year == 2025]$pct), f1(cx[year == 2026]$pct), sprintf("%.1f", min(orr$OR_fav_per_point)), sprintf("%.1f", max(orr$OR_fav_per_point))),
  "t01_raw_by_year; t14_complexity_predicts_favourability; t14b_complexity_contrast")

# ---- F7 job threat --------------------------------------------------------------------------
tt <- rt("t16_threat_2024_2025")
tl <- rbind(tt[, .(dimension, level, year = 2024L, pct = pct_from, n = n1)], tt[, .(dimension, level, year = 2025L, pct = pct_to, n = n2)])
ci <- wilson(tl$pct / 100 * tl$n, tl$n); tl[, `:=`(lo = 100 * ci$lo, hi = 100 * ci$hi)]
tt[, sig := ifelse(is.na(q_bh), p < .05, q_bh < .05)]
tl <- merge(tl, tt[, .(dimension, level, sig)], by = c("dimension", "level"))
tl[, level2 := paste0(level, ifelse(sig, "", " (n.s.)"))]
tl[, dimension := factor(dimension, levels = c("All", "Role family", "Region"))]
p <- ggplot(tl, aes(pct, level2, colour = factor(year))) + geom_line(aes(group = level2), colour = "grey70", linewidth = 1.1) +
  geom_pointrange(aes(xmin = lo, xmax = hi), size = .35) + facet_grid(dimension ~ ., scales = "free_y", space = "free_y", labeller = labeller(dimension = label_wrap_gen(12))) +
  scale_colour_manual(values = OK[c(6, 2)], name = NULL) + scale_x_continuous(labels = function(x) paste0(x, "%")) +
  labs(title = "Perceived job threat rose modestly, 2024 -> 2025",
       subtitle = sprintf("%% answering 'Yes, AI is a threat to my current job', professional developers who use or plan to use AI (only group asked both years).\nOverall %s%% -> %s%% (+%s pts [%s, %s]); (n.s.) = not significant after BH.",
         f1(tt[dimension == "All"]$pct_from), f1(tt[dimension == "All"]$pct_to), f1(tt[dimension == "All"]$diff_pp), f1(tt[dimension == "All"]$lo), f1(tt[dimension == "All"]$hi)),
       x = "% saying AI threatens their job", y = NULL) + theme(strip.text.y = element_text(angle = 0, hjust = 0))
save_fig(p, "f7_job_threat.png", "Perceived job threat 2024 vs 2025 by role and region",
  sprintf("Dumbbell chart. Share of professional AI users/planners who see AI as a threat to their job rose from %s%% to %s%%. Largest rises: %s. Changes not significant after BH: %s.",
    f1(tt[dimension == "All"]$pct_from), f1(tt[dimension == "All"]$pct_to),
    paste(head(tt[dimension != "All"][order(-diff_pp)], 3)[, sprintf("%s +%s", level, f1(diff_pp))], collapse = "; "),
    paste(tt[sig == FALSE]$level, collapse = ", ")),
  "t16_threat_2024_2025", h = 6.8)

# ---- F8 sensitivity --------------------------------------------------------------------------
se <- rt("t21_sensitivity_contrasts")[scale == "pp" & contrast != "2023->2025"]
se[, lab := factor(LAB[outcome], levels = LAB[c("use", "fav", "trust", "distrust")])]
se[, method := factor(method, levels = rev(c("raw (default base)", "standardised (g-computation)", "S1a include QC-excluded", "S1b strict QC",
  "S2b IPW (completion propensity)", "S5 fav excl. Unsure", "S2a Manski bounds (dropout)", "S2a Manski bounds (item non-response)")))]
p <- ggplot(se, aes(y = method, colour = contrast)) + geom_vline(xintercept = 0, colour = "grey50") +
  geom_linerange(data = se[is.na(estimate)], aes(xmin = lo, xmax = hi), linewidth = 3, alpha = .35, position = position_dodge(.6)) +
  geom_pointrange(data = se[!is.na(estimate)], aes(x = estimate, xmin = lo, xmax = hi), size = .3, position = position_dodge(.6)) +
  facet_wrap(~lab, scales = "free_x", nrow = 1) + scale_colour_manual(values = OK[c(1, 2)], name = NULL) +
  labs(title = "Sensitivity: direction of every year-on-year change survives QC, standardisation and weighting",
       subtitle = "Year-on-year change (percentage points). Thick translucent bars = Manski worst/best-case bounds (no point estimate).\nThe 2024 -> 2025 adoption rise is NOT identified under worst-case dropout (bounds include 0).",
       x = "Change (percentage points)", y = NULL)
vd <- rt("t22_robustness_verdicts")
save_fig(p, "f8_sensitivity.png", "Sensitivity of year-on-year changes to QC, standardisation, weighting and missing-data bounds",
  sprintf("Forest plot of year-on-year changes for use, favourability, trust and distrust under raw, standardised, QC-inclusive, strict-QC, completion-weighted and Manski-bound analyses. All point estimates keep the same sign. Manski bounds exclude zero for all contrasts except adoption 2024 to 2025 (%s to %s points).",
    f1(vd[outcome == "use" & contrast == "2024->2025"]$manski_lo), f1(vd[outcome == "use" & contrast == "2024->2025"]$manski_hi)),
  "t21_sensitivity_contrasts; t22_robustness_verdicts", w = 12, h = 5.4)

fwrite(rbindlist(manifest), file.path(FIG, "figures_manifest.csv"))

# =============================================================================
# site_data/trust_trends.json (aggregates only)
# =============================================================================
ser <- function(name, desc, labels, values, lo, hi, n, group = "A", unit = "%") list(name = name, description = desc,
  series_group = group, unit = unit, labels = I(as.character(labels)), values = I(round(values, 1)),
  ci_low = I(round(lo, 1)), ci_high = I(round(hi, 1)), n = I(as.integer(n)))
S <- list()
for (oc in c("use", "plan", "fav", "trust", "distrust", "complex_good", "threat_yes")) {
  for (g in c("A", "B")) {
    r <- raw[outcome == oc & (if (g == "A") year <= 2025 else year == 2026)]
    if (oc == "plan" && g == "B") next
    if (nrow(r)) S[[length(S) + 1]] <- ser(paste0(oc, "_raw_", ifelse(g == "A", paste0(min(r$year), "_2025"), "2026")),
      paste(r$population[1], oc, "- unweighted % with Wilson CI", ifelse(g == "B", "(2026 series break; not comparable to A)", "")),
      r$year, r$pct, r$lo, r$hi, r$n, g)
  }
}
addAB <- function(nm, desc, r, val) for (g in c("A", "B")) { rr <- r[if (g == "A") year <= 2025 else year == 2026]
  if (nrow(rr)) S[[length(S) + 1]] <<- ser(paste0(nm, ifelse(g == "A", paste0("_", min(rr$year), "_2025"), "_2026")),
    paste(desc, ifelse(g == "B", "(2026 series B: same standardisation mix but question/definitions changed; not comparable to A)", "")),
    rr$year, rr[[val]], rr$lo, rr$hi, rep(NA, nrow(rr)), g) }
for (oc in unique(std$outcome)) addAB(paste0(oc, "_standardised"),
  "Standardised (g-computation) to pooled 2023-2025 role/experience/region/org-size mix; n not applicable", std[outcome == oc], "std_pct")
ud <- rt("t02_use_while_distrusting_P1")
S[[length(S) + 1]] <- ser("use_while_distrusting_share_of_pros", "% of all professional developers who use AI AND distrust its accuracy",
  ud$year, ud$pct_use_distrust, ud$lo, ud$hi, ud$n)
for (oc in c("trust", "distrust", "fav")) for (e in EXP_LEVELS)
  addAB(paste0(oc, "_by_experience_", gsub("\\+", "plus", gsub("[^0-9+]+", "_", sub(" yrs", "", e)))),
    paste("Standardised", oc, "among AI users with", e, "coding"), eg[outcome == oc & exp_band == e], "std_pct")
for (oc in c("use", "trust", "distrust")) { r <- pr[outcome == oc]
  S[[length(S) + 1]] <- ser(paste0("paradox_change_2023_2025_", oc), paste("Change 2023->2025 in", oc, "(pp) by subgroup (dimension: level); Newcombe CI"),
    paste0(r$dimension, ": ", r$level), r$diff_pp, r$lo, r$hi, r$n2, unit = "pp") }
r <- tt
S[[length(S) + 1]] <- ser("threat_change_2024_2025", "Change 2024->2025 in % seeing AI as job threat (pros using/planning AI), pp",
  paste0(r$dimension, ": ", r$level), r$diff_pp, r$lo, r$hi, r$n2, unit = "pp")
uf <- rt("t23b_2025_by_use_frequency")
for (oc in c("trust", "distrust", "fav")) { r <- uf[outcome == oc]
  S[[length(S) + 1]] <- ser(paste0(oc, "_by_use_frequency_2025"), paste("2025 AI users:", oc, "% by self-reported use frequency (Wilson CI); cross-sectional association"),
    r$ai_use_freq, r$pct, r$lo, r$hi, r$n) }
t26 <- rt("t05_aitrust_2026_options_users")
S[[length(S) + 1]] <- ser("aitrust_2026_conditions", "2026 only: conditions under which users trust AI (multi-select; not comparable to 2023-25 trust)",
  t26$opt, t26$pct, t26$lo, t26$hi, t26$n, "B")
js <- list(dataset = "trust_trends", generated = format(Sys.time(), "%Y-%m-%d"),
  attribution = "Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., licensed under ODbL 1.0 (https://opendatacommons.org/licenses/odbl/1-0/; https://survey.stackoverflow.co/).",
  caveats = c("Unweighted, self-selected sample of Stack Overflow-engaged developers; not population estimates.",
              "Associations only; stated sentiment, not observed behaviour.",
              "2026 is a separate series (question wording/definition changed); never connect 2026 to 2023-2025 with a line.",
              "Attitude items (favourable, trust, complexity) are among current AI users only; user definition changes in 2025 and 2026.",
              "Heavy late-survey dropout in 2025-2026; CIs ignore self-selection and dropout (see Manski bounds in FINDINGS.md)."),
  series = S)
write_json(js, file.path(SITE, "trust_trends.json"), auto_unbox = TRUE, pretty = TRUE, na = "null", digits = NA)
msg("Wrote %d figures, manifest, and site_data/trust_trends.json (%d series)", length(manifest), length(S))
