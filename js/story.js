/* =============================================================================
   AI, in Practice — NARRATIVE COPY
   -----------------------------------------------------------------------------
   All prose lives here. Never type a finding's number into this file: use a
   {{placeholder}}. Placeholders are filled from Atlas.data.facts (see
   js/data.js -> deriveFacts) or, for chart-local labels, from values the chart
   computes from data. Missing facts render as "—" and log a console warning.

   Available facts (all derived from site/data/*.json):
     years_span, n_respondents, n_years
     use_2023 … use_2026, plan_2023 … plan_2025      (share of developers, %)
     trust_2023 … trust_2025, distrust_2023 … distrust_2025, fav_2023 … fav_2026
     use_change, trust_change, distrust_change, fav_change   (pp, 2023→2025)
     use_dir, trust_dir, distrust_dir, fav_dir               ("rose"/"fell"/"held steady")
     gap_2023, gap_2025                                       (use − trust, pp)
     exp_gap_2023, exp_gap_2025, exp_gap_change, exp_gap_dir ("widened"/"narrowed"/…)
     exp_young, exp_old                                       (band labels)
     auc_logit, auc_best, best_model, d_auc, d_auc_ci, margin_auc, verdict, model_outcome
     top_driver
     n_segments, largest_segment, largest_share
     n_tools, top_pair, top_lift, basket_label
   Inline HTML (<em>, <strong>) is allowed in copy; values are HTML-escaped.
   ========================================================================== */
window.AtlasStory = {
  meta: {
    title: "AI, in Practice",
    edition: "Edition 01 · {{years_span}}",
    author: "Margarita Bermejo Cano",
    links: {
      repo: "https://github.com/mberca/ai-adoption-atlas",
      cv: "https://mberca.github.io/cv-margarita/",
      linkedin: "https://www.linkedin.com/in/margaritabermejocano/",
      sibling: "https://mberca.github.io/engagement-atlas/",
      survey: "https://survey.stackoverflow.co/",
      surveyArchive: "https://github.com/StackExchange/Survey",
      odbl: "https://opendatacommons.org/licenses/odbl/1-0/"
    }
  },

  nav: ["Intro", "The wave", "Paradox", "Experience", "Profiles", "Models", "Tools", "Limits"],

  hero: {
    kicker: "Stack Overflow Developer Survey · {{years_span}}",
    title: "AI, <em>in Practice.</em>",
    promise: "Developers are adopting AI at speed. Do they trust what they use?",
    note: "{{n_respondents}} professional-developer responses across four independent surveys. Each dot represents a share, not a tracked person. Scroll to follow the story.",
    cue: "Scroll to begin"
  },

  ch1: {
    label: "01 / The adoption wave",
    steps: {
      2023: {
        title: "In {{year}}, AI was still the <em>exception.</em>",
        body: "Each dot is a slice of professional developers who answered the survey. <strong>{{use}}</strong> said they were already using AI tools; another {{plan}} said they planned to."
      },
      2024: {
        title: "A year later, the colour <em>spreads.</em>",
        body: "By {{year}}, <strong>{{use}}</strong> were using AI tools, and {{plan}} still planned to."
      },
      2025: {
        title: "By {{year}}, using AI is the <em>default.</em>",
        body: "<strong>{{use}}</strong> now report using AI tools, {{use_change}} since 2023. Only {{plan}} are still planning."
      },
      2026: {
        title: "Then the question <em>changed.</em>",
        body: "In {{year}} the survey was redesigned: use of AI <em>at work</em>, a different routing, no “plan to” option. {{use}} answered yes, but the dots are hollow because this is a new series and is not joined to the trend."
      }
    },
    statLabel: "of professional respondents report using AI tools",
    legend: { use: "Uses AI", plan: "Plans to", none: "Neither / no", newSeries: "2026 · new question" },
    canvasLabel: "Unit chart. In {{year}}, {{use}} of developers used AI tools and {{plan}} planned to.",
    breakLabel: "Series break"
  },

  ch2: {
    label: "02 / The trust paradox",
    title: "Use climbs. <em>Trust doesn’t follow.</em>",
    dek: "Between 2023 and 2025, reported AI use among professional respondents {{use_dir}} from {{use_2023}} to {{use_2025}}. Over the same years, the share of professional AI users who trust its accuracy {{trust_dir}} from {{trust_2023}} to {{trust_2025}}.",
    howto: "Drag the scrubber (or focus it and use ← →) to read any year. Shaded ribbons are 95% confidence intervals.",
    gapLabel: "different populations",
    breakNote: "2026: new trust scale, not comparable",
    readoutGap: "Use − trust gap",
    callout: "Same denominator, clearer story: {{use_distrust_2023}} of professional respondents used AI while distrusting its accuracy in 2023. By 2025, it was {{use_distrust_2025}}."
  },

  ch3: {
    label: "03 / The experience gradient",
    title: "Does experience <em>change the verdict?</em>",
    dek: "More experienced AI users report less trust. These mix-adjusted estimates compare the newest ({{exp_young}}) with the most experienced ({{exp_old}}). The gap is {{exp_gap_2023}} in 2023 and {{exp_gap_2025}} in 2025, but there is no clear evidence of widening.",
    howto: "Each square of 100 dots is one group in one year. Filled dots show the share. Hover for confidence intervals.",
    gapLabel: "Gap, {{old}} minus {{young}}: <strong>{{gap}}</strong> in {{year}}"
  },

  ch4: {
    label: "04 / Who are the developers?",
    title: "One audience. <em>{{n_segments}} different profiles.</em>",
    dek: "A latent-class model groups 2025 AI users by sentiment, trust, perceived complex-task ability and job threat. The largest profile, <em>{{largest_segment}}</em>, has a model-estimated share of {{largest_share}}.",
    howto: "Hover or tab to an archetype to read its profile.",
    provisional: "Provisional: segment solution not final"
  },

  ch5: {
    label: "05 / What predicts trust?",
    title: "Does complexity <em>earn its place?</em>",
    dek: "Can a complex model beat a simple one on a later survey? The highest-AUC complex candidate reaches {{auc_best}}, against {{auc_logit}} for {{baseline_model}} (ΔAUC {{d_auc}}, 95% CI {{d_auc_ci}}). This is an exploratory selection, not a confirmed winner. The analyst-set benchmark for a useful gain is {{margin_auc}}.",
    verdictLead: "Verdict:",
    verdictNote: "Verdicts are the analysis team's labels and combine ΔAUC with relative log-loss, so a model can pass on calibration while its AUC gain stays inside the margin.",
    howto: "Switch outcome and feature set. The shaded band marks the gain that would justify a more complex model.",
    calibTitle: "Calibration: are the probabilities honest?",
    shapTitle: "Drivers: which inputs matter, and how stably?",
    shapNote: "Driver panels describe associations, not causes. SHAP magnitudes and bootstrap rank stability are different quantities; uncertainty is shown only where the export provides it."
  },

  ch6: {
    label: "06 / Tool constellations",
    title: "Tools travel in <em>constellations.</em>",
    dek: "Association rules (Apriori) find which tools respondents report having used together more often than independence would predict. Among the displayed {{basket_label}} pairs, the largest lift is <em>{{top_pair}}</em> ({{top_lift}}).",
    howto: "Hover, or Tab then Enter, to isolate a tool and its partners. Line weight shows lift. Esc clears the selection.",
    liftNote: "Lift compares co-reporting with independence; 1 means no association. It does not show simultaneous use or workflow integration. Networks show selected singleton rules; baskets and denominators differ by year."
  },

  ch7: {
    label: "07 / Honest limits",
    title: "Read this <em>before you quote anything.</em>",
    caveats: [
      { h: "A self-selected sample", p: "Respondents chose to take a long developer survey run by Stack Overflow. They are not a random sample of the world’s developers, so percentages describe respondents, not the profession." },
      { h: "Unweighted estimates", p: "No survey weights exist for this data. Composition shifts year to year (fewer respondents, a different mix of countries and roles), so we also show mix-adjusted (standardised) estimates where possible." },
      { h: "Associations, not causes", p: "Nothing here shows that experience <em>causes</em> distrust, or that a tool <em>causes</em> adoption. Model drivers describe patterns that help prediction, not levers." },
      { h: "Series breaks", p: "Question wording, routing and answer options changed between years. Comparisons are drawn only where items are comparable, and breaks are marked." },
      { h: "Dropout can change the story", p: "Only 76.9% of eligible professional respondents reached the AI question in 2025. Worst-case missing-response bounds allow no adoption increase from 2024 to 2025. Confidence intervals do not account for that selection bias." },
      { h: "Different people, not a panel", p: "The user pool grew while average trust fell. This does not show that the same people lost trust, or that individual planners converted. The 2026 redesign is shown separately, never as a connected trend." },
      { h: "Stated, not observed", p: "These are self-reports of use and sentiment, not telemetry. Saying you trust a tool is not the same as relying on it." }
    ],
    methodTitle: "Method in brief",
    method: [
      "Harmonised AI items across four survey waves with an item-level comparability verdict per year (codebook in the repo).",
      "Proportions with Wilson 95% intervals. Mix-adjusted trends use logistic g-computation over the pooled 2023–2025 covariate mix.",
      "Prediction: logistic regression against gradient boosting with temporal hold-out (train 2023–24, test 2025), bootstrap ΔAUC and calibration.",
      "Segments and tool baskets are exploratory, within-year analyses. Their populations and validation budgets differ from the professional-developer trends; see each chapter and the repository findings."
    ],
    sourcesTitle: "Data & attribution",
    attribution: "Data: Stack Overflow Developer Survey 2023–2026, Stack Exchange Inc., made available under the <a href=\"https://opendatacommons.org/licenses/odbl/1-0/\">Open Database License (ODbL) 1.0</a>. This site shows aggregates only; no respondent-level data is published here.",
    builtBy: "Designed, analysed and built by Margarita Bermejo Cano. No tracking, no cookies, no external requests."
  },

  badges: {
    fixture: "Illustrative data, not results",
    fixtureLong: "Some charts are showing DEV_FIXTURES: invented placeholder numbers used while analysis files are missing. Do not quote them.",
    chartFixture: "Illustrative data"
  }
};
