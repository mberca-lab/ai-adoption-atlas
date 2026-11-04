#!/usr/bin/env Rscript
# Export the scoped recovery analysis; run AFTER both LCA and rules scripts.
a <- commandArgs(FALSE)
here <- dirname(sub("^--file=", "", a[grepl("^--file=", a)]))
source(file.path(here,"04_segments_utils.R"))
suppressPackageStartupMessages(library(jsonlite))
F <- readRDS(file.path(CACHE,"lca_scoped_final_params.rds"))
IND_LABELS <- F$labels
IND_NAMES["SENT3"] <- "Sentiment"
classes <- list()
if (!is.na(F$K)) {
  par <- F$reference[[F$K]]
  B <- load_harmonised()[in_default_base==TRUE & year==2025 & ai_user %in% TRUE]
  code_indicators(B)
  B[,SENT3 := fcase(SENT6 %in% 1:2,1L,SENT6 %in% c(3L,6L),2L,SENT6 %in% 4:5,3L)]
  Y <- B[complete.cases(B[,F$vars,with=FALSE]),F$vars,with=FALSE]
  post <- lca_posterior(par,Y)
  modal <- max.col(post,ties.method="first")
  cnt <- tabulate(modal,F$K)
  labels <- vapply(seq_len(F$K),function(k) {
    sent <- c("Favourable","Neutral / unsure","Unfavourable")[which.max(par$probs$SENT3[k,])]
    paste0("Class ",k,": ",sent,", ",if(par$probs$TRUST4[k,1]>=.5) "trusting" else "cautious on accuracy")
  },character(1))
  prof <- profile_long(par,labels)
  fwrite(prof,file.path(OUT,"lca_profiles.csv"))
  sizes <- data.table(class_id=seq_len(F$K),class_name=labels,n_model=nrow(Y),
    share_model=par$P,n_modal=cnt,share_modal=cnt/nrow(Y),
    avepp=vapply(seq_len(F$K),function(k)mean(post[modal==k,k]),numeric(1)),
    share_lo=NA_real_,share_hi=NA_real_)
  fwrite(sizes,file.path(OUT,"lca_class_sizes.csv"))
  classes <- lapply(seq_len(F$K),function(k) {
    pp <- c("Favourable"=sum(par$probs$SENT3[k,1]),
            "Trusts accuracy"=par$probs$TRUST4[k,1],
            "Good / very good on complex tasks"=par$probs$CPLX5[k,1],
            "No job threat"=par$probs$THREAT3[k,1])
    list(id=k,label=labels[k],share=unname(par$P[k]),share_lo=NA_real_,share_hi=NA_real_,
         n=cnt[k],description=sprintf(
           "2025 current AI users: model-estimated %.0f%% favourable, %.0f%% trusting accuracy, %.0f%% rating complex-task ability good/very good. Exploratory attitude grouping, not a behaviour or career persona.",
           100*pp[1],100*pp[2],100*pp[3]),
         trust_pct=unname(100*pp[2]),fav_pct=unname(100*pp[1]),
         profile=lapply(seq_along(pp),function(j)list(label=names(pp)[j],value=unname(pp[j]))))
  })
}
rules <- fread(file.path(OUT,"rules_cooccurrence_all.csv"))
items <- fread(file.path(OUT,"rules_item_support.csv"))
suit <- fread(file.path(OUT,"rules_basket_suitability.csv"))
cmp <- fread(file.path(OUT,"rules_apriori_vs_pairwise.csv"))
net <- rules[stable==TRUE & reportable==TRUE & lhs_size==1]
# A network edge is a genuine pair. Never project a multi-item antecedent's lift
# onto its individual tools: that would misrepresent a conditional association.
setorder(net,basket,-leverage)
net[,pair_key := paste(pmin(lhs,rhs),pmax(lhs,rhs),sep="\001")]
net <- net[!duplicated(paste(basket,pair_key))]
net <- net[,head(.SD,40),by=basket]
network_fields <- c("basket","year","lhs","rhs","lift","lift_lo","lift_hi","support","confidence")
net[,`:=`(a=lhs,b=rhs)]
multi <- rules[stable==TRUE & reportable==TRUE & lhs_size==2]
multi <- multi[order(-leverage),head(.SD,20),by=basket]
meta <- list(status="final",fixture=FALSE,analysis="exploratory scoped recovery",
  population="2025 QC default-base current AI users, complete on four attitude indicators; tool baskets have separate year/question-specific denominators",
  analysis_note=sprintf("Final exploratory analysis: %s complete-case 2025 current AI users; four attitude indicators; K=1:4, four reference starts, three split pairs and three bootstraps per K>1 (two starts/refit), one worker/script. K=%s selected by minimum BIC among convergence/size/replication/stability-eligible fits, not a globally optimal taxonomy. Class-share intervals are unavailable (null). Rule lift intervals use 200 fixed-rule multinomial respondent-bootstrap draws, not selection-adjusted or simultaneous. Networks contain singleton rules only; higher-order rules remain separate.",
    F$population$complete_cases,F$K),
  n_lca=F$population$complete_cases,chosen_k=F$K,selection=as.data.frame(F$selection),
  uncertainty="Class-share intervals unavailable (null). Three bootstrap refits diagnose partition stability, not confidence intervals. Rule lift intervals: 200 multinomial respondent-bootstrap draws per rule; conditional on fixed rules, not simultaneous or selection-adjusted.",
  class_share_definition="Model mixing proportions; n is modal-assignment count and need not equal share * n_lca.",
  profile_definition="Model-conditional response probabilities, not observed modal-group percentages.",
  network="At most 40 stable singleton-antecedent associations per basket, ranked by leverage; duplicated directions collapsed. Multi-item rules are separate and must not be drawn as pair edges.",
  baskets=as.data.frame(suit),
  limitations=c("Nonprobability self-selected survey; no population representativeness or causality.",
    "Complete-case analysis may be biased by missing answers.",
    "K search truncated at four; no claim of globally optimal or unique taxonomy.",
    "Stability evaluated on the same full sample used for references; not held-out predictive replication.",
    "Three split pairs and three bootstraps per K are limited diagnostics.",
    "No cross-year latent-class replication or measurement-invariance test was completed.",
    "Exploratory thresholds were revised after interruption; not preregistered.",
    "Tool lists, eligibility and populations change by year; do not trend basket supports.",
    "Mixed 2025/2026 model+IDE/agent questions condition on both being answered; this enriches co-use.",
    "Binary have-worked-with answers do not establish simultaneous usage or workflow integration."))
write_json(list(meta=meta,classes=classes,
  rules=as.data.frame(net[,c(network_fields,"a","b"),with=FALSE]),
  items=as.data.frame(items[!is.na(support),.(item,vendor,support,basket,year)]),
  multi_item_rules=as.data.frame(multi[,c(network_fields,"improvement"),with=FALSE])),
  file.path(SITE,"segments.json"),pretty=TRUE,auto_unbox=TRUE,na="null",null="null",digits=7)
timings <- rbindlist(lapply(c("lca_runtime.csv","rules_runtime.csv"),function(x)fread(file.path(OUT,x))),fill=TRUE)
line <- function(...) paste0(sprintf(...),"\n")
text <- c("# Segmentation and tool co-use — final exploratory recovery\n",
  "## Status and scope\n",
  line("Completed on public Stack Overflow survey data. Selected K: %s. LCA sample: %s complete-case 2025 current AI users out of %s eligible current users (%s excluded for missing indicators).",
       ifelse(is.na(F$K),"none — no stable segmentation",F$K),
       F$population$complete_cases,F$population$default_users,F$population$excluded_missing),
  "This is an exploratory descriptive analysis, **not preregistered** and not representative of all developers. Classes are attitudes, not fabricated behavioural archetypes. Sentiment (favourable / neutral-or-unsure / unfavourable), trust (4), complex-task ability (5 including non-use/uncertainty), and job threat (3) define the measurement model.\n",
  "## Recovery deviations and model selection\n",
  "The interrupted plan requested 629 fits on 12 workers and produced no fit cache. It was abandoned. Recovery uses one worker per script (maximum two concurrent), K=1:4, four reference starts, and two starts for each of three split pairs plus three bootstraps per K>1: 31 fit calls, 70 nominal EM starts, maximum 1,200 iterations/start. Complete cases avoid treating missing categories as answers. Every resample must preserve all coded categories. No cross-year replication, broad all-respondent model, attribute-rule search, or measurement-invariance claim is made.\n",
  "Eligible K>1 must have no reference iteration-cap hit, class proportions >=5%, at least two best log-likelihood starts within 0.1, mean split ARI >=0.75, mean bootstrap ARI >=0.75, and minimum class mean Jaccard >=0.75. Choose minimum BIC among eligible models. These judgement thresholds and bounded grid are exploratory revisions made during recovery. The selected model need not minimize BIC among unstable candidates or outside this grid. Diagnostics use full-sample classification by resampled fits, not held-out performance. Conditional-independence assumptions may split continuous attitude gradients into classes; no claim of natural immutable types.\n",
  "Selection diagnostics: `lca_model_selection.csv`; all class response probabilities: `lca_profiles.csv`; model proportions versus modal counts: `lca_class_sizes.csv`. Class intervals are null: three bootstrap refits cannot support defensible percentile confidence intervals. Survey sampling uncertainty and model-selection uncertainty are not quantified.\n",
  "## Observed attitude groups\n",
  if(length(classes)) paste(vapply(classes,function(x)line(
    "- %s: model share %.1f%%; modal n=%s; favourable %.1f%%; trusts accuracy %.1f%%.",
    x$label,100*x$share,x$n,x$fav_pct,x$trust_pct),character(1)),collapse="") else
    "No candidate met the stability/size/convergence gates; no archetypes are asserted.\n",
  "These probabilities describe different dimensions: favourable sentiment does not imply trusting accuracy. Profiles, not demographics or inferred career stages, define the labels. Entropy is reported in the selection CSV: modal assignments remain uncertain even when partitions are stable across resampling. Class shares sum to one by the fitted mixture, not by survey weighting.\n",
  "## Bugs corrected\n",
  "- `paste0` on empty IDE/LLM lists created phantom prefix-only items (notably `IDE:` in 9,496 old 2025 baskets); use an explicit empty-list-safe prefix helper.\n",
  "- Wilson helper used scalar `ifelse(n > 0, ...)` with vector counts, recycling the first item's support across a basket. Explicit vector broadcasting now preserves each count/denominator and its own interval; regression tests check this.\n",
  "- Prior stored bootstrap lifts had identical lower/upper endpoints. Fresh intervals now come from direct multinomial resampling of each rule's respondent 2x2 table, not reused arules quality slots. This is equivalent marginally to respondent resampling for a fixed rule, but not a joint bootstrap across rules.\n",
  "- Multi-antecedent improvement is recomputed against every singleton sub-antecedent and the empty baseline, not just surviving pruned rules. No unsupported 3-item antecedents remain.\n",
  "- Posterior probabilities are computed explicitly in log space, marginalising missing items, and checked against poLCA's fitted posterior. This avoids brittle package helper assumptions and handles one-row inputs correctly. Category schemas are checked to prevent silent recoding gaps.\n",
  "## Basket suitability and denominators\n",
  "Each basket uses QC default-base respondents answering its question(s); unanswered is not treated as non-use. 2025 agent-tools is conditional on agent-user question routing. 2025 model+IDE and 2026 agent+LLM baskets require both lists answered; do not compare supports across these populations. Model/provider selections and IDE usage are different constructs. They describe repertoire overlap, not simultaneous workflow integration.\n",
  "Exploratory suitability screen: >=1,000 baskets; >=60% with 2+ items; >=8 items at 1% support; top item <90% support. Failure is a caution, not evidence that associations are absent.\n",
  paste(vapply(seq_len(nrow(suit)),function(i)line("- %s (%s): n=%s, mean items=%.2f, 2+ items=%.1f%%, top support=%.1f%%; %s.",
    suit$basket[i],suit$year[i],suit$n_baskets[i],suit$mean_size[i],100*suit$share_size_ge2[i],
    100*suit$top_item_support[i],suit$verdict[i]),character(1)),collapse=""),
  "## Apriori versus a pairwise baseline\n",
  "Apriori is bounded to total rule length 3 (at most two antecedent items), support >=1% and count >=30, confidence >=25%, lift >=1.2, Fisher Bonferroni alpha .01 within each filtered mining call, confidence-nonredundant. Stable means bootstrap threshold retention >=90% and presence in both halves for >=80% of three split pairs (thus all three pairs). Reportable multi-item rules must improve confidence by >=5 percentage points over every proper sub-rule. These are exploratory screening thresholds, not confirmatory inference; bootstrap retention does not repeat significance/pruning. Lift intervals are conditional fixed-rule 95% percentile bootstrap intervals, not multiplicity- or selection-adjusted population intervals.\n",
  "Pairwise baseline tests all pairs of items each with >=1% support using phi, lift and Fisher/BH; positive significance threshold q<.001. Pairs with joint count<30 have association metrics suppressed and are omitted from the aggregate output. Rule direction is conditional prevalence, not temporal ordering. Same-vendor effects may reflect ecosystems or overlapping labels.\n",
  paste(vapply(seq_len(nrow(cmp)),function(i)line("- %s: %s pairwise tests; %s stable/reportable Apriori rules, of which %s have a two-item antecedent adding >=5pp.",
     cmp$basket[i],cmp$n_pairs_tested[i],cmp$n_rules_reportable_stable[i],
     cmp$n_rules_lhs2_stable_improv_ge_0.05[i]),character(1)),collapse=""),
  "Apriori adds qualifying conditional combinations beyond a pairwise graph, but more rules are not inherently more insight. The primary graph therefore uses genuine singleton rules only, ranked by absolute leverage (maximum 40 undirected pairs/basket). Multi-item combinations remain separate in `multi_item_rules`; never project their lift onto constituent pair edges. Review full counts in `rules_apriori_vs_pairwise.csv` and support sensitivity (1%, 2%, 3%) before selecting a public example. No predictive or causal superiority was established. Dense mixed-question baskets can produce many nested combinations mechanically.\n",
  paste(vapply(c("B25M","B26"),function(b) {
    ex <- multi[basket==b][1]
    if(is.na(ex$lift)) return("")
    line("- Illustrative highest-leverage qualifying combination in %s: {%s} => {%s}; support %.1f%%, confidence %.1f%%, lift %.2f, improvement over strongest proper sub-rule %.1fpp. Selected post hoc, not an independent validation.",
      b,ex$lhs,ex$rhs,100*ex$support,100*ex$confidence,ex$lift,100*ex$improvement)
  },character(1)),collapse=""),
  "## Runtime and reproduction\n",
  "Run from the repository root in PowerShell, with R packages arrow, data.table, poLCA, mclust, arules and jsonlite installed:\n",
  "```powershell\n& 'C:\\Program Files\\R\\R-4.6.2\\bin\\Rscript.exe' scripts\\04_segments_lca.R\n& 'C:\\Program Files\\R\\R-4.6.2\\bin\\Rscript.exe' scripts\\04_segments_rules.R\n& 'C:\\Program Files\\R\\R-4.6.2\\bin\\Rscript.exe' scripts\\04_segments_lca_profiles.R\n& 'C:\\Program Files\\R\\R-4.6.2\\bin\\Rscript.exe' scripts\\04_segments_verify.R\n```\n",
  paste(vapply(seq_len(nrow(timings)),function(i)line("- %s: %.1f seconds; %s worker.",timings$stage[i],timings$seconds[i],timings$workers[i]),character(1)),collapse=""),
  "Seed: 20261104 with deterministic per-fit offsets. Inputs are local gitignored `data_clean/ai_harmonised.parquet` and raw year CSVs. Model caches contain parameters only, no respondent rows. Exported CSV/JSON are aggregates. Old broad-fit caches and attribute-rule outputs are not part of this final analysis.\n",
  "## References\n",
  "- Linzer & Lewis (2011), poLCA, Journal of Statistical Software 42(10), https://doi.org/10.18637/jss.v042.i10\n",
  "- Hennig (2007), Cluster-wise assessment of cluster stability, Computational Statistics & Data Analysis 52, https://doi.org/10.1016/j.csda.2006.11.025 (Jaccard is a heuristic diagnostic, not proof of truth).\n",
  "- Stack Overflow annual developer survey public files; source provenance and QC definitions are documented by the project's harmonisation pipeline.\n")
writeLines(text,file.path(OUT,"FINDINGS.md"))
pkgs <- c("arrow","data.table","poLCA","mclust","arules","jsonlite")
writeLines(c(capture.output(sessionInfo()),"",
  vapply(pkgs,function(p)paste(p,as.character(packageVersion(p))),character(1))),
  file.path(OUT,"session_info.txt"))
msg("Exported %d classes, %d genuine network pairs, %d multi-item examples",length(classes),nrow(net),nrow(multi))
