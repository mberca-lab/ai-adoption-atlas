#!/usr/bin/env Rscript
a <- commandArgs(FALSE)
here <- dirname(sub("^--file=", "", a[grepl("^--file=", a)]))
source(file.path(here,"04_segments_utils.R"))
suppressPackageStartupMessages(library(jsonlite))
stopifnot(identical(prefix_items("IDE:",character()),character()),
          identical(prefix_items("IDE:","Cursor"),"IDE:Cursor"))
w <- wilson(c(10,80),100)
stopifnot(max(abs(w$p-c(.1,.8)))<1e-12,w$lo[1]<.1,w$hi[2]>.8,
          is.na(wilson(0,0)$p))
toy <- list(K=2L,P=c(.4,.6),vars=c("a","b"),
  probs=list(a=matrix(c(.9,.1,0,.2,.3,.5),2,byrow=TRUE),
             b=matrix(c(.8,.2,.1,.9),2,byrow=TRUE)))
y <- data.table(a=c(1L,3L,NA_integer_),b=c(2L,NA_integer_,NA_integer_))
p <- lca_posterior(toy,y)
stopifnot(max(abs(rowSums(p)-1))<1e-12,
  abs(p[1,1]-(.4*.9*.2)/(.4*.9*.2+.6*.2*.9))<1e-12,
  p[2,2]>.999999,max(abs(p[3,]-toy$P))<1e-12,
  identical(dim(lca_posterior(toy,y[1])),c(1L,2L)))
j <- fromJSON(file.path(SITE,"segments.json"),simplifyVector=FALSE)
stopifnot(j$meta$status=="final",!j$meta$fixture)
if(length(j$classes)) {
  stopifnot(abs(sum(vapply(j$classes,`[[`,numeric(1),"share"))-1)<1e-6,
    sum(vapply(j$classes,`[[`,numeric(1),"n"))==j$meta$n_lca,
    all(vapply(j$classes,function(x)is.null(x$share_lo)&&is.null(x$share_hi),logical(1))),
    all(vapply(j$classes,function(x)x$trust_pct>=0&&x$trust_pct<=100,logical(1))))
  prof <- fread(file.path(OUT,"lca_profiles.csv"))
  stopifnot(max(abs(prof[,sum(prob),by=.(class_id,indicator)]$V1-1))<1e-6)
  sel <- fread(file.path(OUT,"lca_model_selection.csv"))
  stopifnot(sel[chosen==TRUE,.N]==1L,sel[chosen==TRUE,eligible],
            !sel[chosen==TRUE,hit_maxiter])
}
r <- fread(file.path(OUT,"rules_cooccurrence_all.csv"))
it <- fread(file.path(OUT,"rules_item_support.csv"))
stopifnot(!any(grepl("^(M|IDE|Agent|LLM):$",it$item)),
  max(abs(it[!is.na(count),support-count/n_baskets]))<1e-12,
  all(r$lhs_size<=2),all(r$count>=30),all(r$lift_lo<r$lift_hi),
  max(abs(r$support-r$confidence*r$coverage))<1e-10,
  all(r$boot_stability>=0&r$boot_stability<=1),
  all(r[reportable==TRUE & lhs_size==2,improvement]>=.05))
rhs_rate <- it$support[match(paste(r$basket,r$rhs),paste(it$basket,it$item))]
stopifnot(!anyNA(rhs_rate),max(abs(r$confidence/r$lift-rhs_rate))<1e-10)
for(edge in j$rules) {
  found <- r[basket==edge$basket & lhs==edge$lhs & rhs==edge$rhs]
  stopifnot(nrow(found)==1L,found$lhs_size==1L,found$stable,found$reportable,
            abs(found$lift-edge$lift)<1e-6)
}
s <- fread(file.path(OUT,"rules_basket_suitability.csv"))
stopifnot(identical(s$suitable,s$n_baskets>=1000&s$share_size_ge2>=.6&
                     s$n_items_supp_ge_1pct>=8&s$top_item_support<.9))
writeLines(c("PASS: missing-item / single-row posterior; empty-prefix regression;",
 "class probability normalization, selection gates and null intervals;",
 "fresh bootstrap ranges, bounded antecedents, basket suitability;",
 "JSON genuine pair-edge provenance and fractions."),
 file.path(OUT,"validation.txt"))
msg("PASS: segmentation regression and aggregate export validation (%d rules, %d classes).",nrow(r),length(j$classes))
