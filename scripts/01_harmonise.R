#!/usr/bin/env Rscript
# =============================================================================
# AI Adoption Atlas -- 01_harmonise.R
#
# Builds a respondent-level, cross-year harmonised table of demographics and
# AI-related items from the PUBLIC Stack Overflow Developer Survey 2023-2026.
#
#   Input : data_raw/  (official files, NOT committed; see docs/DATA_NOTES.md)
#   Output: data_clean/ai_harmonised.parquet   (gitignored)
#           data_clean/ai_harmonised.csv       (gitignored)
#           docs/tables/*.csv                  (aggregate profiling tables only)
#
# Run from anywhere:
#   "C:\Program Files\R\R-4.6.2\bin\Rscript.exe" scripts/01_harmonise.R
# Set env var SKIP_HASH=1 to skip SHA-256 verification of raw files.
#
# Data: Stack Overflow Developer Survey, Stack Exchange Inc., ODbL 1.0
# (https://opendatacommons.org/licenses/odbl/1-0/). Do not redistribute raw data.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(countrycode)
  library(digest)
})

# ---- 0. Paths ---------------------------------------------------------------
get_root <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 1) return(normalizePath(file.path(dirname(f), ".."), winslash = "/"))
  normalizePath(".", winslash = "/")
}
ROOT    <- get_root()
RAW     <- file.path(ROOT, "data_raw")
CLEAN   <- file.path(ROOT, "data_clean")
TABLES  <- file.path(ROOT, "docs", "tables")
dir.create(CLEAN,  showWarnings = FALSE, recursive = TRUE)
dir.create(TABLES, showWarnings = FALSE, recursive = TRUE)
msg <- function(...) cat(sprintf(...), "\n", sep = "")

# ---- 1. Raw file registry (verified against official Git LFS pointers) -------
# SHA-256 values come from the LFS pointer files at
# https://github.com/StackExchange/Survey/tree/main/packages/archive/<year>
RAWFILES <- data.table(
  year    = 2023:2026,
  results = c("2023_results.csv", "2024_results.csv", "2025_results.csv",
              "2026_survey_results_public.csv"),
  schema  = c("2023_schema.csv", "2024_schema.csv", "2025_schema.csv",
              "2026_survey_results_schema.csv"),
  sha256  = c("828874a3cf0fa1bbb4c3da6a87e5822b8563bbc04b21f9869479480dbcff410c",
              "7f2c2dbf6989d00b80a7351de4bb3af4b52b21cc52d5c947891bbc4f4e5cbe49",
              "2d1f65308877282edfb4470520eabbc08cb499118432a3dcec6a66c086aa2baa",
              "ad520b4d5d71f240141e63f0d6f81a3b1898cbdc69efe9ea985496533b15fc2c"),
  n_rows  = c(89184L, 65437L, 49191L, 30903L),
  n_cols  = c(84L, 114L, 172L, 212L),
  # columns that only exist in that year's questionnaire (year fingerprint)
  signature = list(c("Q120", "AIDevHaveWorkedWith", "AINextVery similar"),
                   c("Check", "AISearchDevHaveWorkedWith", "AIEthics", "AIChallenges"),
                   c("AIAgents", "AIFrustration", "AIToolCurrently mostly AI"),
                   c("CodeMain", "AISentiment", "AITrust", "AICodeAgentHaveWorkedWith"))
)

# ---- 2. Helpers ---------------------------------------------------------------
norm_txt <- function(x) {
  x <- gsub("\u2019|\u2018", "'", x)        # curly -> straight apostrophes
  x <- gsub("[[:space:]]+", " ", x)
  x <- trimws(x)
  x[x %in% c("", "NA")] <- NA_character_
  x
}

# strict recode: every non-missing input value must be in the map
recode_strict <- function(x, map, var, year) {
  bad <- unique(x[!is.na(x) & !(x %in% names(map))])
  if (length(bad)) stop(sprintf("[%d] %s: unmapped values: %s", year, var,
                                paste(shQuote(bad), collapse = ", ")))
  unname(map[x])
}

# does a semicolon-separated multi-select contain ANY of the given options?
has_opt <- function(x, opts) {
  res <- rep(NA, length(x))
  ok  <- !is.na(x)
  if (!any(ok)) return(res)
  sp  <- strsplit(x[ok], ";", fixed = TRUE)
  res[ok] <- vapply(sp, function(v) any(trimws(v) %in% opts), logical(1))
  res
}

# numeric years: "Less than 1 year" -> 0 ; "More than 50 years" -> 51 (later top-coded to 50)
parse_years <- function(x) {
  y <- suppressWarnings(as.numeric(x))
  y[x %in% "Less than 1 year"]   <- 0
  y[x %in% "More than 50 years"] <- 51
  y
}

col_or_na <- function(d, col) if (col %in% names(d)) d[[col]] else rep(NA_character_, nrow(d))
paste_cols <- function(d, cols) {
  do.call(paste, c(lapply(cols, function(cn) { v <- col_or_na(d, cn); fifelse(is.na(v), "", v) }), sep = ";"))
}
any_answered <- function(d, cols) Reduce(`|`, lapply(cols, function(cn) !is.na(col_or_na(d, cn))))

# ---- 3. Shared value maps -----------------------------------------------------
MAP_AGE <- c("Under 18 years old" = "Under 18", "18-24 years old" = "18-24",
             "25-34 years old" = "25-34", "35-44 years old" = "35-44",
             "45-54 years old" = "45-54", "55-64 years old" = "55-64",
             "65 years or older" = "65+", "Prefer not to say" = "Prefer not to say")
AGE_UPPER <- c("Under 18" = 17, "18-24" = 24, "25-34" = 34, "35-44" = 44,
               "45-54" = 54, "55-64" = 64, "65+" = 100, "Prefer not to say" = NA)

MAP_DEVSTATUS <- c(
  "I am a developer by profession" = "Professional developer",
  "I am not primarily a developer, but I write code sometimes as part of my work/studies" = "Codes as part of work/studies",
  "I am learning to code" = "Learning to code",
  "I code primarily as a hobby" = "Hobbyist",
  "I used to be a developer by profession, but no longer am" = "Former developer",
  "None of these" = "None of these",
  "I work with developers or my work supports developers but am not a developer by profession" = "Supports developers (non-developer)",
  # 2026 CodeMain (different question; see codebook)
  "I create code as a primary part of my job" = "Professional developer",
  "I create code occasionally" = "Codes occasionally (2026)",
  "I manage or support people who create code" = "Supports developers (non-developer)",
  "I review/maintain code but rarely create it" = "Reviews/maintains code (2026)",
  "I do not create code" = "Does not create code (2026)")

MAP_EMP_SINGLE <- c("Employed" = "Employed",
                    "Independent contractor, freelancer, or self-employed" = "Independent/self-employed",
                    "Student" = "Student", "Not employed" = "Not employed",
                    "Retired" = "Retired", "I prefer not to say" = "Prefer not to say")

MAP_REMOTE <- c("Remote" = "Remote", "In-person" = "In-person",
                "Hybrid (some remote, some in-person)" = "Hybrid",
                "Hybrid (some remote, leans heavy to in-person)" = "Hybrid",
                "Hybrid (some in-person, leans heavy to flexibility)" = "Hybrid",
                "Your choice (very flexible, you can come in when you want or just as needed)" = "Hybrid")

MAP_EDU <- c(
  "Primary/elementary school" = "Primary",
  "Secondary school (e.g. American high school, German Realschule or Gymnasium, etc.)" = "Secondary",
  "Some college/university study without earning a degree" = "Some college, no degree",
  "Associate degree (A.A., A.S., etc.)" = "Associate",
  "Bachelor's degree (B.A., B.S., B.Eng., etc.)" = "Bachelor's",
  "Master's degree (M.A., M.S., M.Eng., MBA, etc.)" = "Master's",
  "Professional degree (JD, MD, Ph.D, Ed.D, etc.)" = "Professional/doctoral",
  "Something else" = "Other", "Other (please specify):" = "Other",
  "Other, please specify" = "Other")

MAP_ORG <- c(
  "Just me - I am a freelancer, sole proprietor, etc." = "Just me",
  "2 to 9 employees" = "2-19", "10 to 19 employees" = "2-19",
  "Less than 20 employees" = "2-19",
  "20 to 99 employees" = "20-99", "100 to 499 employees" = "100-499",
  "500 to 999 employees" = "500-999", "1,000 to 4,999 employees" = "1,000-4,999",
  "5,000 to 9,999 employees" = "5,000-9,999", "10,000 or more employees" = "10,000+",
  "I don't know" = "Don't know")

ROLE_DEV <- c("Developer, full-stack", "Developer, back-end", "Developer, front-end",
  "Developer, desktop or enterprise applications", "Developer, mobile",
  "Developer, embedded applications or devices", "Developer, game or graphics",
  "Developer, QA or test", "Developer, AI", "Developer, AI apps or physical AI",
  "Software engineer", "Architect, software or solutions", "Blockchain",
  "Developer Experience", "Hardware Engineer", "Hardware engineer")
ROLE_DATA <- c("Data scientist or machine learning specialist", "Engineer, data",
  "Data engineer", "Data or business analyst", "Data scientist", "AI/ML engineer",
  "Applied scientist", "Financial analyst or engineer")
ROLE_OPS <- c("DevOps specialist", "DevOps engineer or professional",
  "Engineer, site reliability", "Site reliability engineer", "Cloud infrastructure engineer",
  "System administrator", "Database administrator", "Database administrator or engineer",
  "Security professional", "Cybersecurity or InfoSec professional", "Platform engineer",
  "Support engineer or analyst",
  "Solutions engineer, implementation engineer, or forward-deployed engineer")
ROLE_MGMT <- c("Engineering manager", "Senior Executive (C-Suite, VP, etc.)",
  "Senior executive (C-suite, VP, etc.)", "Project manager", "Product manager",
  "Founder, technology or otherwise", "Founder or entrepreneur")
ROLE_RES <- c("Academic researcher", "Research & Development role", "Scientist",
  "Educator", "Educator or instructor")
ROLE_OTH <- c("Designer", "UX, Research Ops or UI design professional",
  "UX, research, or UI design professional", "Developer Advocate",
  "Developer advocate or developer relations professional",
  "Marketing or sales professional", "Marketing/Sales professional",
  "Technical writer or documentation professional", "Retired",
  "Other (please specify):", "Other")
mk <- function(v, lab) setNames(rep(lab, length(v)), v)
MAP_ROLE <- c(mk(ROLE_DEV, "Developer / software engineer"), mk(ROLE_DATA, "Data / AI / analytics"),
              mk(ROLE_OPS, "Ops / infra / security / support"), mk(ROLE_MGMT, "Management / exec / product"),
              mk(ROLE_RES, "Research / education"), mk("Student", "Student"), mk(ROLE_OTH, "Other"))

MAP_ICPM <- c("Individual contributor" = "Individual contributor",
              "Individual contributor in a senior or staff-level role" = "Individual contributor",
              "People manager" = "People manager",
              "Both people manager and individual contributor" = "Both (2026 only)")

MAP_SENT <- c("Very favorable" = 5, "Favorable" = 4, "Somewhat favorable" = 4,
              "Indifferent" = 3, "Neutral" = 3, "Unfavorable" = 2,
              "Somewhat unfavorable" = 2, "Very unfavorable" = 1,
              "Unsure" = NA, "Not sure" = NA)
MAP_TRUST <- c("Highly trust" = 5, "Somewhat trust" = 4, "Neither trust nor distrust" = 3,
               "Somewhat distrust" = 2, "Highly distrust" = 1)
MAP_COMPLEX <- c("Very well at handling complex tasks" = 5,
                 "Good, but not great at handling complex tasks" = 4,
                 "Neither good or bad at handling complex tasks" = 3,
                 "Bad at handling complex tasks" = 2,
                 "Very poor at handling complex tasks" = 1,
                 "I don't use AI tools for complex tasks / I don't know" = NA)
MAP_THREAT <- c("Yes" = "Yes", "No" = "No", "I'm not sure" = "Not sure")
FREQ_RANK <- c("Daily" = 3, "Weekly" = 2, "Monthly or Infrequent" = 1)

# AI-in-workflow task harmonisation: harmonised task -> answer options per year
TASKS <- list(
  writing_code  = list(y23 = "Writing code", y24 = "Writing code", y25 = "Writing code",
                       y26 = c("Generating code in a familiar area", "Generating code in an unfamiliar area")),
  debugging     = list(y23 = "Debugging and getting help", y24 = "Debugging and getting help",
                       y25 = "Debugging or fixing code",
                       y26 = "Debugging, troubleshooting, or refactoring code"),
  documenting   = list(y23 = "Documenting code", y24 = "Documenting code", y25 = "Documenting code",
                       y26 = "Writing documentation, comments, or knowledge base content"),
  testing       = list(y23 = "Testing code", y24 = "Testing code", y25 = "Testing code",
                       y26 = "Writing or improving tests"),
  learn_codebase= list(y23 = "Learning about a codebase", y24 = "Learning about a codebase",
                       y25 = "Learning about a codebase",
                       y26 = "Understanding or onboarding to a new codebase"),
  review_code   = list(y23 = "Committing and reviewing code", y24 = "Committing and reviewing code",
                       y25 = "Committing and reviewing code",
                       y26 = "Reviewing code, pull requests, or design decisions"),
  planning      = list(y23 = "Project planning", y24 = "Project planning", y25 = "Project planning",
                       y26 = "Writing tickets, requirements, plans, or project updates"),
  deployment    = list(y23 = "Deployment and monitoring", y24 = "Deployment and monitoring",
                       y25 = "Deployment and monitoring",
                       y26 = "Deploying, operating, or troubleshooting production systems"),
  search_answers= list(y23 = NULL, y24 = "Search for answers", y25 = "Search for answers", y26 = NULL)
)

# ---- 4. Read + verify ---------------------------------------------------------
read_year <- function(i) {
  r <- RAWFILES[i]
  f <- file.path(RAW, r$results)
  if (!file.exists(f)) stop("Missing raw file: ", f)
  if (Sys.getenv("SKIP_HASH") != "1") {
    h <- digest(file = f, algo = "sha256")
    if (!identical(h, r$sha256))
      stop(sprintf("SHA-256 mismatch for %s (got %s): not the official %d release ",
                   r$results, h, r$year), "(e.g. truncated download). Re-download it.")
  }
  d <- fread(f, colClasses = "character", na.strings = c("NA", ""), encoding = "UTF-8",
             showProgress = FALSE)
  if (nrow(d) != r$n_rows || ncol(d) != r$n_cols)
    stop(sprintf("%s: expected %d x %d, got %d x %d", r$results, r$n_rows, r$n_cols, nrow(d), ncol(d)))
  if (!all(r$signature[[1]] %in% names(d)))
    stop(sprintf("%s: year-signature columns missing -> file is not the %d survey", r$results, r$year))
  for (j in names(d)) set(d, j = j, value = norm_txt(d[[j]]))
  msg("[%d] %s: %s rows x %d cols (verified)", r$year, r$results, format(nrow(d), big.mark = ","), ncol(d))
  d
}

# ---- 5. Per-year harmonisation ------------------------------------------------
harmonise_year <- function(d, year) {
  n  <- nrow(d)
  g  <- function(col) col_or_na(d, col)
  ys <- as.character(year)
  yr <- year   # scalar copy: inside out[...] 'year' resolves to the column
  body <- d[, setdiff(names(d), "ResponseId"), with = FALSE]

  out <- data.table(year = year, response_id = as.integer(d$ResponseId))
  out[, uid := sprintf("%d_%06d", year, response_id)]

  # --- QC flags -------------------------------------------------------------
  out[, n_items_answered := rowSums(!is.na(body))]
  out[, qc_exact_dup     := duplicated(body)]             # 2nd+ copies of identical rows
  out[, qc_low_content   := n_items_answered < 10]        # fewer than 10 non-missing items
  out[, qc_screened_out  := year == 2023 & g("MainBranch") %in% "None of these"]

  # --- Demographics -----------------------------------------------------------
  mb_col <- if (year == 2026) "CodeMain" else "MainBranch"
  out[, dev_status_raw := g(mb_col)]
  out[, dev_status := recode_strict(dev_status_raw, MAP_DEVSTATUS, mb_col, year)]
  out[, is_professional_dev := dev_status %in% "Professional developer"]

  out[, age_band := factor(recode_strict(g("Age"), MAP_AGE, "Age", year), levels = unname(MAP_AGE))]

  emp <- g("Employment")
  out[, employment_raw := emp]
  if (year %in% 2023:2024) {   # multi-select -> primary status by priority rule
    out[, employment_status := fcase(
      has_opt(emp, c("Employed, full-time", "Employed, part-time")) %in% TRUE, "Employed",
      has_opt(emp, "Independent contractor, freelancer, or self-employed") %in% TRUE, "Independent/self-employed",
      has_opt(emp, c("Student, full-time", "Student, part-time")) %in% TRUE, "Student",
      has_opt(emp, c("Not employed, but looking for work", "Not employed, and not looking for work")) %in% TRUE, "Not employed",
      has_opt(emp, "Retired") %in% TRUE, "Retired",
      has_opt(emp, "I prefer not to say") %in% TRUE, "Prefer not to say",
      default = NA_character_)]
    out[, employment_multi := grepl(";", emp, fixed = TRUE)]
  } else {
    out[, employment_status := recode_strict(emp, MAP_EMP_SINGLE, "Employment", year)]
    out[, employment_multi := FALSE]
  }

  rw <- g(if (year == 2026) "WorkSetting" else "RemoteWork")
  out[, remote_work_raw := rw]
  out[, remote_work := recode_strict(rw, MAP_REMOTE, "RemoteWork", year)]

  ed <- g(if (year == 2026) "Education" else "EdLevel")
  out[, education := recode_strict(ed, MAP_EDU, "EdLevel", year)]

  rl <- g(if (year == 2026) "Role" else "DevType")
  out[, role_raw := rl]
  out[, role_family := recode_strict(rl, MAP_ROLE, "DevType/Role", year)]

  out[, org_size := recode_strict(g("OrgSize"), MAP_ORG, "OrgSize", year)]

  yc <- parse_years(g("YearsCode"))
  if (year %in% 2023:2024) {
    yp <- parse_years(g("YearsCodePro")); yp_src <- "YearsCodePro"
  } else {
    yp <- parse_years(g("WorkExp"));      yp_src <- "WorkExp"
  }
  up <- unname(AGE_UPPER[as.character(out$age_band)])
  out[, qc_years_implausible := (!is.na(yc) & !is.na(up) & yc > up - 4) |
                                (!is.na(yp) & !is.na(up) & yp > up - 12) |
                                (!is.na(yc) & yc > 60) | (!is.na(yp) & yp > 60)]
  out[, years_code := pmin(yc, 50)]           # top-coded at 50 ("50+")
  out[, years_pro  := pmin(yp, 50)]
  out[, years_pro_source := yp_src]

  ct <- g("Country")
  ct[ct %in% "The former Yugoslav Republic of Macedonia"] <- "Republic of North Macedonia"
  out[, country := ct]

  out[, ic_or_pm := recode_strict(g("ICorPM"), MAP_ICPM, "ICorPM", year)]
  out[, industry_raw := g("Industry")]
  out[, comp_usd_yearly := suppressWarnings(as.numeric(g("ConvertedCompYearly")))]

  # --- AI: use / intent -------------------------------------------------------
  sel <- g("AISelect")
  out[, ai_select_raw := sel]
  if (year %in% 2023:2025) {
    out[, ai_use_status := fcase(grepl("^Yes", sel), "Using",
                                 sel %in% "No, but I plan to soon", "Plan to use",
                                 sel %in% "No, and I don't plan to", "Not using, no plans",
                                 default = NA_character_)]
    if (any(!is.na(sel) & is.na(out$ai_use_status))) stop("[", year, "] unmapped AISelect")
    out[, qc_ai_inconsistent := FALSE]
  } else {
    tool_opts <- c("AI coding assistants or coding agents", "General-purpose AI chat tools",
                   "AI agents or automated workflows", "Internal AI tools built by my company")
    uses <- has_opt(sel, tool_opts) %in% TRUE; none <- has_opt(sel, "I don't use AI tools") %in% TRUE
    out[, ai_use_status := fcase(uses, "Using", none, "Not using (no plan option)", default = NA_character_)]
    out[, qc_ai_inconsistent := uses & none]
    out[, ai_type_coding_assistant := has_opt(sel, "AI coding assistants or coding agents")]
    out[, ai_type_chat            := has_opt(sel, "General-purpose AI chat tools")]
    out[, ai_type_agents          := has_opt(sel, "AI agents or automated workflows")]
    out[, ai_type_internal        := has_opt(sel, "Internal AI tools built by my company")]
  }
  out[, ai_user := ai_use_status %in% "Using"]
  out[is.na(ai_use_status), ai_user := NA]

  # frequency of use (2025: from AISelect; 2026: highest frequency across AIFreq_1..4)
  if (year == 2025) {
    out[, ai_use_freq := fcase(sel %in% "Yes, I use AI tools daily", "Daily",
                               sel %in% "Yes, I use AI tools weekly", "Weekly",
                               sel %in% "Yes, I use AI tools monthly or infrequently", "Monthly or infrequent",
                               default = NA_character_)]
  } else if (year == 2026) {
    fr <- sapply(paste0("AIFreq_", 1:4), function(cn) unname(FREQ_RANK[g(cn)]))
    mx <- apply(fr, 1, function(v) if (all(is.na(v))) NA_integer_ else as.integer(max(v, na.rm = TRUE)))
    out[, ai_use_freq := c("Monthly or infrequent", "Weekly", "Daily")[mx]]
    out[, ai_daily_hours_raw := g("AIDaily")]
  }

  # --- AI: sentiment, trust, complexity, threat -------------------------------
  s_raw <- g(if (year == 2026) "AISentiment" else "AISent")
  chk <- s_raw[!is.na(s_raw) & !(s_raw %in% names(MAP_SENT))]
  if (length(chk)) stop("[", year, "] unmapped sentiment: ", paste(unique(chk), collapse = "|"))
  out[, ai_sent_raw := s_raw]
  out[, ai_sent_5 := unname(MAP_SENT[s_raw])]
  out[, ai_sent_unsure := s_raw %in% c("Unsure", "Not sure")]
  out[, ai_sent_favorable := fifelse(is.na(s_raw), NA, ai_sent_5 %in% 4:5)]

  tr_col <- switch(ys, "2023" = "AIBen", "2024" = "AIAcc", "2025" = "AIAcc", "2026" = "AITrust")
  tr <- g(tr_col)
  out[, ai_trust_raw := tr]
  out[, ai_trust_source := tr_col]
  if (year <= 2025) {
    out[, ai_trust_5 := recode_strict(tr, MAP_TRUST, tr_col, year)]
    out[, ai_trust_any := fifelse(is.na(tr), NA, ai_trust_5 >= 4)]
  } else {
    out[, ai_trust_5 := NA_real_]           # 2026 uses a different, non-ordinal scale
    out[, ai_trust_any := NA]
  }

  cx <- g("AIComplex")
  out[, ai_complex_raw := cx]
  if (year >= 2024) out[, ai_complex_5 := recode_strict(cx, MAP_COMPLEX, "AIComplex", year)] else out[, ai_complex_5 := NA_real_]

  out[, ai_threat := if (yr %in% 2024:2025) recode_strict(g("AIThreat"), MAP_THREAT, "AIThreat", year) else NA_character_]

  # --- AI: benefits / challenges / frustrations (raw multi-selects) -----------
  out[, ai_benefits_raw    := switch(ys, "2023" = g("AIAcc"), "2024" = g("AIBen"), rep(NA_character_, n))]
  out[, ai_challenges_raw  := if (yr == 2024) g("AIChallenges") else NA_character_]
  out[, ai_ethics_raw      := if (yr == 2024) g("AIEthics") else NA_character_]
  out[, ai_frustration_raw := if (yr == 2025) g("AIFrustration") else NA_character_]
  out[, ai_disruption_raw  := if (yr == 2026) g("Disruption") else NA_character_]

  # --- AI: agents ------------------------------------------------------------
  if (year == 2025) {
    ag <- g("AIAgents")
    out[, ai_agents_raw := ag]
    out[, ai_agent_user := fifelse(is.na(ag), NA, grepl("^Yes", ag))]
    out[, qc_ai_inconsistent := sel %in% "No, and I don't plan to" & grepl("^Yes", ag)]
    out[, ai_agent_change_raw := g("AIAgentChange")]
  } else if (year == 2026) {
    out[, ai_agent_user := ai_type_agents]
  }

  # --- AI: learning ------------------------------------------------------------
  la <- switch(ys, "2025" = g("LearnCodeAI"), "2026" = g("LearnAI"), rep(NA_character_, n))
  out[, ai_learned_raw := la]
  out[, ai_learned_past_year := fifelse(is.na(la), NA, grepl("^Yes", la))]

  # --- AI: workflow tasks currently using AI for --------------------------------
  wf <- switch(ys,
    "2023" = list(cur = "AIToolCurrently Using", all = c("AIToolCurrently Using", "AIToolInterested in Using", "AIToolNot interested in Using")),
    "2024" = list(cur = "AIToolCurrently Using", all = c("AIToolCurrently Using", "AIToolInterested in Using", "AIToolNot interested in Using")),
    "2025" = list(cur = c("AIToolCurrently mostly AI", "AIToolCurrently partially AI"),
                  all = grep("^AITool", names(d), value = TRUE)),
    "2026" = list(cur = "AIWorkCurrentlyUse",
                  all = c("AIWorkCurrentlyUse", "AIWorkExpectMore", "AIWorkExpectLess", "AIWorkDoNotPlanToUse", "AIWorkNotInWorkflow")))
  answered_wf <- any_answered(d, wf$all)
  cur_str <- paste_cols(d, wf$cur)
  out[, ai_workflow_answered := answered_wf]
  out[, ai_workflow_current_raw := fifelse(answered_wf, cur_str, NA_character_)]
  yk <- paste0("y", substr(ys, 3, 4))
  for (tk in names(TASKS)) {
    opts <- TASKS[[tk]][[yk]]
    v <- if (is.null(opts)) rep(NA, n) else fifelse(answered_wf, has_opt(cur_str, opts) %in% TRUE, NA)
    set(out, j = paste0("aiw_", tk), value = v)
  }

  # --- AI: named tools (sources differ by year; see codebook) ----------------------
  tool_src <- switch(ys,
    "2023" = c("AISearchHaveWorkedWith", "AIDevHaveWorkedWith"),
    "2024" = "AISearchDevHaveWorkedWith",
    "2025" = "AIAgentExternal",                 # asked only of AI-agent users
    "2026" = "AICodeAgentHaveWorkedWith")
  tl <- paste_cols(d, tool_src); tl_ans <- any_answered(d, tool_src)
  out[, ai_tools_used_raw := fifelse(tl_ans, tl, NA_character_)]
  out[, ai_tools_source := paste(tool_src, collapse = "+")]
  out[, ai_tool_github_copilot := fifelse(tl_ans, has_opt(tl, "GitHub Copilot") %in% TRUE, NA)]
  out[, ai_tool_chatgpt := if (yr <= 2025) fifelse(tl_ans, has_opt(tl, "ChatGPT") %in% TRUE, NA) else NA]
  out[, ai_tool_claude  := if (yr == 2023) NA else fifelse(tl_ans, has_opt(tl, c("Claude", "Claude Code")) %in% TRUE, NA)]

  # --- Other year-specific AI items kept raw ---------------------------------------
  out[, so_ai_friction_raw := if (yr == 2025) g("SOFriction") else NA_character_]
  out[, so_ai_change_raw   := if (yr == 2026) g("SOChange") else NA_character_]
  out[, ai_avoid_raw       := if (yr == 2026) g("AIAvoid") else NA_character_]
  out[, ai_org_use_raw     := if (yr == 2026) g("AIUse") else NA_character_]

  # --- Straight-lining (informative only, NOT used to exclude) ---------------------
  sl <- function(cols, exclude = character()) {
    m <- as.matrix(d[, ..cols])
    apply(m, 1, function(v) { v <- v[!is.na(v)]
      length(v) == length(cols) && length(unique(v)) == 1 && !(v[1] %in% exclude) })
  }
  out[, qc_straightline := switch(ys,
    "2023" = sl(paste0("Knowledge_", 1:8)),
    "2024" = sl(paste0("Knowledge_", 1:9)),
    "2025" = rep(NA, n),          # no row-level Likert grid in the public 2025 file
    "2026" = sl(paste0("AIImpact_", 1:7), exclude = "Not applicable") | sl(paste0("AISat_", 1:7)))]

  out[, qc_exclude := qc_exact_dup | qc_low_content | qc_screened_out]
  out[]
}

# ---- 6. Run --------------------------------------------------------------------
raw <- lapply(seq_len(nrow(RAWFILES)), read_year)
names(raw) <- RAWFILES$year
H <- rbindlist(lapply(seq_along(raw), function(i) harmonise_year(raw[[i]], RAWFILES$year[i])),
               use.names = TRUE, fill = TRUE)

# region (World Bank 7 regions) + continent; survey-specific names handled explicitly
H[, region := countrycode(country, "country.name", "region", warn = FALSE,
                          custom_match = c("Kosovo" = "Europe & Central Asia", "Nomadic" = NA))]
H[, continent := countrycode(country, "country.name", "continent", warn = FALSE,
                             custom_match = c("Kosovo" = "Europe", "Nomadic" = NA))]
unmatched <- H[!is.na(country) & is.na(region), unique(country)]
if (length(unmatched)) msg("NOTE: countries without region: %s", paste(unmatched, collapse = "; "))

# Default analysis base: not excluded by QC and answered the AI-use question
H[, in_default_base := !qc_exclude & !is.na(ai_use_status)]

front <- c("uid", "year", "response_id", "in_default_base", "qc_exclude", "qc_exact_dup",
           "qc_low_content", "qc_screened_out", "qc_years_implausible", "qc_ai_inconsistent",
           "qc_straightline", "n_items_answered")
setcolorder(H, c(front, setdiff(names(H), front)))

write_parquet(H, file.path(CLEAN, "ai_harmonised.parquet"))
fwrite(H, file.path(CLEAN, "ai_harmonised.csv"))
msg("Wrote %s rows x %d cols -> data_clean/ai_harmonised.{parquet,csv}",
    format(nrow(H), big.mark = ","), ncol(H))

# ---- 7. Aggregate profiling tables (aggregates only; safe to commit) -----------
pct <- function(x) round(100 * mean(x, na.rm = TRUE), 1)

prof <- H[, .(rows = .N,
              exact_dup = sum(qc_exact_dup), low_content = sum(qc_low_content),
              screened_out = sum(qc_screened_out), excluded = sum(qc_exclude),
              years_implausible = sum(qc_years_implausible, na.rm = TRUE),
              ai_inconsistent = sum(qc_ai_inconsistent, na.rm = TRUE),
              straightline_flag = sum(qc_straightline, na.rm = TRUE),
              under18 = sum(age_band %in% "Under 18"),
              ai_select_answered = sum(!is.na(ai_use_status)),
              default_base = sum(in_default_base),
              median_items_answered = as.double(median(n_items_answered))), by = year]
fwrite(prof, file.path(TABLES, "profile_qc_by_year.csv"))

raw_prof <- rbindlist(lapply(names(raw), function(y) {
  d <- raw[[y]]; b <- d[, -"ResponseId"]
  data.table(year = as.integer(y), n_rows = nrow(d), n_cols = ncol(d),
             cell_missing_pct = round(100 * mean(is.na(as.matrix(b))), 1),
             cols_over_50pct_missing = sum(colMeans(is.na(b)) > 0.5),
             countries = uniqueN(na.omit(d$Country)))
}))
fwrite(raw_prof, file.path(TABLES, "profile_raw_by_year.csv"))

colmiss <- rbindlist(lapply(names(raw), function(y) {
  d <- raw[[y]]; data.table(year = as.integer(y), column = names(d),
                            pct_missing = round(100 * colMeans(is.na(d)), 1))
}))
fwrite(colmiss, file.path(TABLES, "missingness_by_column.csv"))

# routing evidence: share answering each AI item, by AI-use status
route_items <- list(
  "2023" = c("AISent", "AIBen", "AIAcc", "AIToolCurrently Using", "AIDevHaveWorkedWith", "AISearchHaveWorkedWith"),
  "2024" = c("AISent", "AIAcc", "AIBen", "AIComplex", "AIThreat", "AIChallenges", "AIEthics", "AIToolCurrently Using", "AISearchDevHaveWorkedWith"),
  "2025" = c("AISent", "AIAcc", "AIComplex", "AIThreat", "AIAgents", "AIFrustration", "AIAgentExternal", "AIToolCurrently partially AI"),
  "2026" = c("AISentiment", "AITrust", "AIComplex", "AIWorkCurrentlyUse", "AICodeAgentHaveWorkedWith", "Disruption", "AIAvoid"))
routing <- rbindlist(lapply(names(route_items), function(y) {
  d <- raw[[y]]; hh <- H[year == as.integer(y)]
  keep <- !hh$qc_exclude
  st <- fifelse(is.na(hh$ai_use_status), "(AISelect missing)", hh$ai_use_status)
  rbindlist(lapply(route_items[[y]], function(it)
    data.table(year = as.integer(y), item = it, ai_use_status = st[keep], answered = !is.na(d[[it]][keep]))[
      , .(n = .N, pct_answered = pct(answered)), by = .(year, item, ai_use_status)]))
}))
fwrite(routing, file.path(TABLES, "ai_item_routing.csv"))

# headline comparability check (default base, adults; unweighted)
base <- H[in_default_base & !(age_band %in% c("Under 18", "Prefer not to say"))]
head_tbl <- base[, .(n = .N,
  pct_using = pct(ai_use_status == "Using"),
  pct_plan  = pct(ai_use_status == "Plan to use"),
  users_n = sum(ai_user),
  users_favorable_pct = pct(ai_sent_favorable[ai_user]),
  users_trust_pct     = pct(ai_trust_any[ai_user]),
  users_distrust_pct  = pct((ai_trust_5 <= 2)[ai_user]),
  users_complex_good_pct = pct((ai_complex_5 >= 4)[ai_user & !is.na(ai_complex_raw)])),
  by = .(year, is_professional_dev)][order(-is_professional_dev, year)]
fwrite(head_tbl, file.path(TABLES, "headline_check_unweighted.csv"))

print(prof); print(raw_prof); print(head_tbl)
msg("Done.")
