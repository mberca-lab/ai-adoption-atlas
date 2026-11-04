#!/usr/bin/env Rscript
# Recovery analysis: exploratory, NOT preregistered. See outputs/segments/FINDINGS.md.
# One worker; 2025 current users; K=1:4, four common attitude indicators.
a <- commandArgs(FALSE)
here <- dirname(sub("^--file=", "", a[grepl("^--file=", a)]))
source(file.path(here, "04_segments_utils.R"))
suppressPackageStartupMessages({library(poLCA); library(mclust)})
t0 <- Sys.time()
H <- load_harmonised()
B <- H[in_default_base == TRUE & year == 2025 & ai_user %in% TRUE]
code_indicators(B)
# Collapse adjacent sentiment tails, and preserve non-use/uncertainty for complexity.
B[, SENT3 := fcase(SENT6 %in% 1:2, 1L, SENT6 %in% c(3L,6L), 2L,
                   SENT6 %in% 4:5, 3L)]
IND_LABELS$SENT3 <- c("Favourable", "Neutral/unsure", "Unfavourable")
IND_NAMES["SENT3"] <- "Sentiment"
vars <- c("SENT3", "TRUST4", "CPLX5", "THREAT3")
Y <- B[, ..vars]
keep <- complete.cases(Y)
Y <- Y[keep]
population <- data.table(year=2025, default_users=nrow(B), complete_cases=nrow(Y),
                        excluded_missing=sum(!keep), indicators=paste(vars, collapse=";"))
fwrite(population, file.path(OUT,"lca_population.csv"))
# Fixed category schema must hold in every sample: poLCA silently renumbers gaps.
schema_ok <- function(d) all(vapply(vars, function(v)
  identical(sort(unique(d[[v]])), seq_len(length(IND_LABELS[[v]]))), logical(1)))
stopifnot(schema_ok(Y))
ref <- list(); rows <- list()
for (K in 1:4) {
  msg("Reference K=%d, n=%d", K, nrow(Y))
  m <- fit_lca(Y,K,4L,SEED+K,maxiter=1200)
  par <- strip_lca(m,vars)
  par <- permute_lca(par,order(-par$probs$SENT3[,1]))
  post <- lca_posterior(par,Y)
  stopifnot(max(abs(rowSums(post)-1)) < 1e-10)
  # Independent posterior implementation must agree with the package posterior.
  stopifnot(max(abs(sort(post[,1])-sort(m$posterior[,order(-m$probs$SENT3[,1])[1]]))) < 1e-6)
  ref[[K]] <- par
  rows[[K]] <- data.table(K=K,n=nrow(Y),BIC=par$bic,AIC=par$aic,
    entropy=rel_entropy(post),min_class_share=min(par$P),
    replicated_starts=if(K==1) NA_integer_ else sum(abs(par$attempts-max(par$attempts)) < .1),
    hit_maxiter=par$numiter>=1200)
  saveRDS(ref,file.path(CACHE,"lca_scoped_reference_params.rds"))
}
sel <- rbindlist(rows)
# BIC chooses the candidate within the bounded grid; assess candidate and smaller K.
# Three complementary split pairs and three bootstraps are diagnostics, NOT CIs.
stab <- list()
for (K in 2:4) {
  p <- ref[[K]]; modal <- max.col(lca_posterior(p,Y),ties.method="first")
  ari <- jac <- numeric(); bootari <- numeric()
  for (r in 1:3) {
    set.seed(SEED+100*K+r)
    h <- sample(nrow(Y)) <= nrow(Y)/2
    labs <- list()
    for (j in 1:3) {
      idx <- if(j==1) which(h) else if(j==2) which(!h) else sample.int(nrow(Y),nrow(Y),TRUE)
      stopifnot(schema_ok(Y[idx]))
      m <- fit_lca(Y[idx],K,2L,SEED+1000*K+10*r+j,maxiter=1200)
      q <- strip_lca(m,vars)
      labs[[j]] <- max.col(lca_posterior(q,Y),ties.method="first")
      jac <- rbind(jac,class_jaccard(modal,labs[[j]],K))
    }
    ari <- c(ari,adjustedRandIndex(labs[[1]],labs[[2]]))
    bootari <- c(bootari,adjustedRandIndex(modal,labs[[3]]))
  }
  stab[[length(stab)+1]] <- data.table(K=K,split_ari_mean=mean(ari),split_ari_min=min(ari),
    boot_ari_mean=mean(bootari),boot_ari_min=min(bootari),min_class_jaccard=min(colMeans(jac)),
    split_pairs=3L,boot_refits=3L)
  msg("K=%d stability ARI %.3f, minimum mean Jaccard %.3f",K,mean(ari),min(colMeans(jac)))
}
sel <- merge(sel,rbindlist(stab),by="K",all.x=TRUE)
sel[,eligible := K>1 & !hit_maxiter & min_class_share>=.05 & replicated_starts>=2 &
      split_ari_mean>=.75 & boot_ari_mean>=.75 & min_class_jaccard>=.75]
chosen <- if(any(sel$eligible,na.rm=TRUE)) sel[eligible==TRUE][which.min(BIC),K] else NA_integer_
sel[,chosen := !is.na(chosen) & K==chosen]
fwrite(sel,file.path(OUT,"lca_model_selection.csv"))
saveRDS(list(K=chosen,reference=ref,vars=vars,labels=IND_LABELS,
             population=population,selection=sel),
        file.path(CACHE,"lca_scoped_final_params.rds"))
fwrite(data.table(stage="lca",seconds=as.numeric(difftime(Sys.time(),t0,units="secs")),
                  workers=1L,reference_fits=4L,stability_fits=27L),
       file.path(OUT,"lca_runtime.csv"))
print(sel)
msg("Chosen K=%s; elapsed %.1f seconds",chosen,as.numeric(difftime(Sys.time(),t0,units="secs")))
