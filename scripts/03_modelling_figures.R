#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 03_modelling_figures.R  (modelling stream)
# Reads ONLY aggregated tables in outputs/modelling/tables/ and draws the
# stream's figures (ggplot2) + an alt-text manifest.
#   "C:\Program Files\R\R-4.6.2\bin\Rscript.exe" scripts/03_modelling_figures.R
# Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., ODbL 1.0.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales) })

get_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1) return(normalizePath(file.path(dirname(f), ".."), winslash = "/"))
  normalizePath(".", winslash = "/")
}
ROOT <- get_root()
TAB  <- file.path(ROOT, "outputs", "modelling", "tables")
FIG  <- file.path(ROOT, "outputs", "modelling", "figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
rd <- function(f) fread(file.path(TAB, f))
run <- rd("run_metadata.csv")
CAP <- sprintf("Data: Stack Overflow Developer Survey 2023-2026 (Stack Exchange Inc., ODbL 1.0). Unweighted, self-selected.\nExploratory deterministic %.0f%% subsample; metric CIs condition on fitted models; %d driver refits (descriptive ranges only).",
               100 * run$sample_fraction, run$stability_refits)

OUTC <- c(fav = "AI favourability (users)", trust = "Trust in AI accuracy (users, 2023-25)",
          trust26 = "Broad trust, 2026 conditional scale", use = "AI-use status (2023-25)")
SCH <- c(temporal_2324to25 = "Temporal: train 2023-24, test 2025",
         groupcv_country = "Grouped CV by country",
         temporal_232425to26 = "Series break: train 2023-25, test 2026")
MOD <- c(baseline = "Naive baseline", logit = "Regularised logistic", rf = "Random forest",
         xgb = "XGBoost", lgbm = "LightGBM", ensemble = "Calibrated ensemble",
         logit_recal = "Logistic (recalibrated)", lgbm_recal = "LightGBM (recalibrated)",
         ensemble_vs_recal = "Ensemble vs recalibrated logistic")
PAL <- c("Naive baseline" = "grey60", "Regularised logistic" = "#1b4f72", "Random forest" = "#7d6608",
         "XGBoost" = "#b03a2e", "LightGBM" = "#d35400", "Calibrated ensemble" = "#6c3483",
         "Logistic (recalibrated)" = "#5dade2", "LightGBM (recalibrated)" = "#f0b27a",
         "Ensemble vs recalibrated logistic" = "#6c3483")
theme_set(theme_minimal(base_size = 11) +
          theme(plot.title.position = "plot", plot.title = element_text(face = "bold"),
                panel.grid.minor = element_blank(), legend.position = "bottom",
                plot.caption = element_text(size = 8, colour = "grey40", hjust = 0)))
alt <- list()
save <- function(p, name, w, h, alt_text) {
  ggsave(file.path(FIG, name), p, width = w, height = h, dpi = 200, bg = "white")
  alt[[length(alt) + 1]] <<- data.table(file = paste0("figures/", name), alt_text = alt_text)
}

met <- rd("model_metrics.csv"); dif <- rd("model_diff_vs_logit.csv")
cb  <- rd("calibration_bins.csv"); st <- rd("driver_stability_bootstrap.csv")
yr  <- rd("driver_stability_years.csv"); pdp <- rd("partial_dependence.csv"); sub <- rd("subgroup_audit.csv")

# ---- Fig 1: difference vs logistic (AUC and relative log-loss) with 95% CIs ----------
d1 <- rbind(dif[vs == "logit" & feature_set == "D" & model %in% c("baseline", "rf", "xgb", "lgbm")],
            dif[vs == "logit_recal" & feature_set == "D" & model == "ensemble"][, model := "ensemble_vs_recal"])
d1[, outcome_l := factor(OUTC[outcome], levels = OUTC)]
d1[, scheme_l := factor(SCH[scheme], levels = SCH)]
d1[, model_l := factor(MOD[model], levels = rev(MOD))]
l1 <- rbind(d1[, .(outcome_l, scheme_l, model_l, metric = "Delta AUC (higher = better)", est = d_auc, lo = d_auc_lo, hi = d_auc_hi)],
            d1[, .(outcome_l, scheme_l, model_l, metric = "Delta log-loss, % (lower = better)", est = 100 * d_log_loss_rel,
                   lo = 100 * d_log_loss_rel_lo, hi = 100 * d_log_loss_rel_hi)])
l1 <- l1[model_l != "Naive baseline" | metric != "Delta AUC (higher = better)"]
ref <- data.table(metric = c("Delta AUC (higher = better)", "Delta AUC (higher = better)",
                             "Delta log-loss, % (lower = better)", "Delta log-loss, % (lower = better)"),
                  x = c(-0.01, 0.01, -1, 1))
p1 <- ggplot(l1, aes(est, model_l, colour = model_l)) +
  geom_rect(data = ref[c(1, 3)], inherit.aes = FALSE, aes(xmin = x, xmax = -x, ymin = -Inf, ymax = Inf),
            fill = "grey92", colour = NA) +
  geom_vline(xintercept = 0, colour = "grey30") +
  geom_pointrange(aes(xmin = lo, xmax = hi), size = 0.3) +
  facet_grid(outcome_l + scheme_l ~ metric, scales = "free_x", labeller = label_wrap_gen(28)) +
  scale_colour_manual(values = PAL, guide = "none") +
  labs(title = "Complex models vs regularised logistic regression (same features, same splits)",
       subtitle = "Paired fixed-prediction bootstrap 95% CIs (country-cluster resampling for grouped CV). Ensemble vs equally recalibrated logistic.\nGrey band = analyst-selected exploratory thresholds (|dAUC| < 0.01, |dLL| < 1%); not preregistered or multiplicity-adjusted.",
       x = NULL, y = NULL, caption = CAP) +
  theme(strip.text.y = element_text(angle = 0, hjust = 0, size = 8))
save(p1, "fig1_model_vs_logit_differences.png", 11, 9.5,
     "Exploratory forest plot on a deterministic subsample. Points and conditional bootstrap intervals compare random forest, XGBoost and LightGBM against logistic, and the calibrated ensemble against recalibrated logistic. Grey bands are analyst-selected thresholds, not registered hypotheses.")

# ---- Fig 2: calibration curves on the temporal test year --------------------------------
c2 <- cb[scheme == "temporal_2324to25" & feature_set == "D" & outcome %in% c("fav", "trust") &
         model %in% c("logit", "rf", "lgbm", "ensemble")]
c2[, model_l := factor(MOD[model], levels = MOD)]; c2[, outcome_l := factor(OUTC[outcome], levels = OUTC)]
p2 <- ggplot(c2, aes(mean_pred, observed, colour = model_l)) +
  geom_abline(linetype = 2, colour = "grey50") +
  geom_errorbar(aes(ymin = obs_lo, ymax = obs_hi), width = 0, alpha = 0.5) +
  geom_line() + geom_point(size = 1.2) +
  facet_wrap(~outcome_l, scales = "free") +
  scale_colour_manual(values = PAL, name = NULL) +
  scale_x_continuous(labels = percent) + scale_y_continuous(labels = percent) +
  labs(title = "Calibration on the unseen 2025 survey (models trained on 2023-24)",
       subtitle = "Quantile bins (ties kept together); whiskers = Wilson 95% CI of observed share. Dashed = perfect calibration.",
       x = "Mean predicted probability", y = "Observed share", caption = CAP)
save(p2, "fig2_calibration_temporal.png", 10, 5.2,
     "Calibration plots for favourability and trust on test year 2025. Each decile compares mean prediction with observed share and a Wilson interval. The dashed diagonal marks perfect calibration; calibration labels came only from held-out pre-2025 rows.")

# ---- Fig 3: feature sets (leakage check) --------------------------------------------------
m3 <- met[scheme == "temporal_2324to25" & outcome %in% c("fav", "trust") & model %in% c("logit", "lgbm")]
m3[, fs_l := factor(c(D = "D: demographics / context", B = "B: + AI-usage tasks",
                      E = "E: + other AI attitudes (leakage-prone)")[feature_set],
                    levels = c("D: demographics / context", "B: + AI-usage tasks", "E: + other AI attitudes (leakage-prone)"))]
m3[, model_l := factor(MOD[model], levels = MOD)]; m3[, outcome_l := factor(OUTC[outcome], levels = OUTC)]
p3 <- ggplot(m3, aes(fs_l, auc, colour = model_l)) +
  geom_hline(yintercept = 0.5, linetype = 3, colour = "grey50") +
  geom_pointrange(aes(ymin = auc_lo, ymax = auc_hi), position = position_dodge(width = 0.4)) +
  facet_wrap(~outcome_l) + scale_colour_manual(values = PAL, name = NULL) +
  scale_x_discrete(labels = label_wrap(16)) +
  labs(title = "Feature-set sensitivity: context, AI tasks, and sibling attitude items",
       subtitle = "Test AUC (2025) with conditional bootstrap CIs. B/E are contemporaneous correlates, not deployable prospective predictors.",
       x = NULL, y = "AUC (test year 2025)", caption = CAP)
save(p3, "fig3_feature_sets_leakage.png", 10, 5.2,
     "Dot plot comparing held-out AUC for logistic and LightGBM under D context-only, B adding AI tasks, and E adding sibling attitudes. B and E are leakage-prone contemporaneous sensitivity analyses, not prospective models.")

# ---- Fig 4: top drivers with bootstrap stability --------------------------------------------
s4 <- st[outcome %in% c("fav", "trust")]
s4[, outcome_l := factor(OUTC[outcome], levels = OUTC)]; s4[, model_l := factor(MOD[model], levels = MOD)]
ord <- s4[model == "lgbm", .(m = mean(mean_abs_shap)), by = label][order(m), label]
s4[, label := factor(label, levels = ord)]
s4[, lx := max(shap_hi) * 1.04, by = outcome]
p4 <- ggplot(s4, aes(mean_abs_shap, label, colour = model_l)) +
  geom_pointrange(aes(xmin = shap_lo, xmax = shap_hi), position = position_dodge(width = 0.5), size = 0.3) +
  geom_text(data = s4[model == "lgbm"], aes(x = lx, label = sprintf("top-3 in %.1f%%", 100 * p_top3)),
            hjust = 0, size = 2.6, colour = "grey30") +
  facet_wrap(~outcome_l, scales = "free_x") + scale_colour_manual(values = PAL, name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.3))) +
  labs(title = "Top drivers (mean |SHAP|, log-odds) and their stability across bootstrap refits",
       subtitle = sprintf("Context-only; ranges = 2.5-97.5 percentiles over only %d fixed-tuning bootstrap refits, NOT confidence intervals.\nLabel = share ranking top-3 (LightGBM). Linear contributions and TreeSHAP use different background conventions; not causal.", run$stability_refits),
       x = "Mean |SHAP| (log-odds)", y = NULL, caption = CAP)
save(p4, "fig4_drivers_bootstrap_stability.png", 11, 5.8,
     "Horizontal plot of mean absolute log-odds contributions for logistic and LightGBM. Whiskers are descriptive percentiles across a small number of fixed-tuning refits, not inferential confidence intervals. Top-three percentages describe these refits only.")

# ---- Fig 5: driver ranks across survey years ------------------------------------------------
y5 <- yr[model == "lgbm"]
y5[, outcome_l := factor(OUTC[outcome], levels = OUTC)]
ord5 <- y5[, .(m = mean(rank)), by = label][order(-m), label]; y5[, label := factor(label, levels = ord5)]
p5 <- ggplot(y5, aes(factor(year), label, fill = rank)) + geom_tile(colour = "white") +
  geom_text(aes(label = rank), size = 3) +
  facet_wrap(~outcome_l) + scale_fill_gradient(low = "#d35400", high = "#fbeee6", name = "Rank", trans = "reverse") +
  labs(title = "Do the same drivers matter every year? (LightGBM refit within each survey year)",
       subtitle = "Descriptive ranks (1 = most important); tuning inherited from the temporal experiment, not independently nested within year.\n2026 uses a re-worded sentiment item and new developer-status question.",
       x = NULL, y = NULL, caption = CAP)
save(p5, "fig5_driver_ranks_by_year.png", 10, 5.2,
     "Heatmap of feature importance ranks by survey year for favourability (2023-2026) and trust (2023-2025). Each cell shows the rank of the feature in a model fitted within that year, so stable rows indicate drivers that matter consistently.")

# ---- Fig 6: partial dependence -----------------------------------------------------------
p6d <- pdp[outcome %in% c("fav", "trust") & feature %in% c("years_code", "age_band", "role_family", "region")]
p6d[, outcome_l := factor(OUTC[outcome], levels = OUTC)]; p6d[, model_l := factor(MOD[model], levels = MOD)]
yc <- p6d[feature == "years_code"]; yc[, x := as.numeric(value)]
pa <- ggplot(yc, aes(x, mean_pred, colour = model_l)) + geom_line(linewidth = 0.9) +
  facet_wrap(~outcome_l, scales = "free_y") + scale_colour_manual(values = PAL, name = NULL) +
  scale_y_continuous(labels = percent) +
  labs(title = "Partial dependence on years of coding (models trained 2023-24; other features held at observed 2025 values)",
       subtitle = "Average predicted probability if everyone had the given years of coding. Descriptive of the model, not a causal effect.",
       x = "Years coding", y = "Mean predicted probability", caption = CAP)
save(pa, "fig6_partial_dependence_experience.png", 10, 4.6,
     "Line chart of model partial dependence on years coding for logistic and LightGBM, averaged over test-set covariates. These hypothetical replacements can violate correlations with age and role; curves are descriptive, not causal.")

# ---- Fig 7: subgroup audit ---------------------------------------------------------------
s7 <- sub[dimension %in% c("exp_band", "region", "role_family")]
s7[, dim_l := c(exp_band = "Experience", region = "Region", role_family = "Role family")[dimension]]
s7[, outcome_l := factor(OUTC[outcome], levels = OUTC)]
s7[, grp := paste0(group, " (n=", format(n, big.mark = ","), ")")]
p7 <- ggplot(s7, aes(auc_logit, reorder(grp, auc_logit))) +
  geom_vline(xintercept = 0.5, linetype = 3, colour = "grey50") +
  geom_errorbar(aes(xmin = auc_logit_lo, xmax = auc_logit_hi), width = 0, orientation = "y", colour = PAL[["Regularised logistic"]], alpha = 0.6) +
  geom_point(colour = PAL[["Regularised logistic"]]) +
  geom_point(aes(x = auc_lgbm), colour = PAL[["LightGBM"]], shape = 17) +
  facet_grid(dim_l ~ outcome_l, scales = "free_y", space = "free_y") +
  labs(title = "Subgroup performance audit (test year 2025)",
       subtitle = "AUC within each subgroup: circles = logistic (95% bootstrap CI), triangles = LightGBM. Groups with n < 100 suppressed.",
       x = "Within-group AUC", y = NULL, caption = CAP) + theme(axis.text.y = element_text(size = 7))
save(p7, "fig7_subgroup_audit.png", 10, 9,
     "Within-subgroup AUC on the 2025 test set by experience, region and role. Logistic circles show conditional bootstrap intervals; LightGBM triangles show point estimates. Groups below 100 rows are suppressed. This is not a fairness certification.")

fwrite(rbindlist(alt), file.path(FIG, "alt_text_manifest.csv"))
sources <- list.files(TAB, pattern = "\\.csv$", full.names = TRUE)
fwrite(data.table(file = basename(sources), md5 = unname(tools::md5sum(sources))),
       file.path(FIG, "source_table_hashes.csv"))
pngs <- list.files(FIG, pattern = "\\.png$", full.names = TRUE)
fwrite(data.table(file = basename(pngs), md5 = unname(tools::md5sum(pngs))),
       file.path(FIG, "figure_hashes.csv"))
si <- file.path(ROOT, "outputs", "modelling", "SESSION_INFO.txt")
prior <- readLines(si, warn = FALSE)
marker <- which(prior == "[R figures]")
if (length(marker)) writeLines(prior[seq_len(marker[1] - 1L)], si)
cat("\n[R figures]\n", R.version.string, "\n", sprintf("data.table %s\nggplot2 %s\nscales %s\n",
    packageVersion("data.table"), packageVersion("ggplot2"), packageVersion("scales")), file = si, append = TRUE, sep = "")
cat("figures written:", length(alt), "\n")
