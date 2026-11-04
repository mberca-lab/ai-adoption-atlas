# AI codebook — Stack Overflow Developer Survey 2023–2026

Full item-level detail (exact columns, wording, options, who was asked, changes, verdict, harmonised
variable) is in [`codebook_ai.csv`](codebook_ai.csv). Routing evidence (share answering each AI item by
AI-use status, computed from the data) is in [`tables/ai_item_routing.csv`](tables/ai_item_routing.csv).

Verdict scale: **C** = comparable · **CC** = comparable with caveats · **NC** = not comparable · — = not asked.

## Concept × year matrix

| Concept | 2023 | 2024 | 2025 | 2026 | Verdict |
|---|---|---|---|---|---|
| AI use / intent | `AISelect` (Yes / plan / no) | `AISelect` (identical) | `AISelect` (Yes split daily/weekly/monthly) | `AISelect` **multi-select, at work, no "plan"** + `AIFreq_1..4` | 23↔24 **C**; 25 **CC**; 26 **NC** |
| Sentiment | `AISent` | `AISent` | `AISent` | `AISentiment` (relabelled 6-pt) | 23–25 **CC** (users only); 26 **CC** (series break) |
| Trust in accuracy | **`AIBen`** (names swapped!) | `AIAcc` | `AIAcc` | `AITrust` (conditional, non-ordinal) | 23–25 **CC** (users only); 26 **NC** |
| Complex-task handling | — | `AIComplex` | `AIComplex` (+opt-out) | `AIComplex` (+"or agents") | 24–26 **CC** |
| Job threat | — | `AIThreat` | `AIThreat` | — | 24↔25 **CC** |
| Benefits sought | **`AIAcc`** | `AIBen` (+1 option) | — | — | 23↔24 **CC** |
| AI in workflow tasks | `AITool{Currently Using,…}` 1-yr | same + 3 tasks | `AITool{Currently mostly/partially AI,…}` 3–5 yr | `AIWork{CurrentlyUse,…}` 19 new tasks | 23↔24 **CC**; 25 **CC**; 26 **NC** (directional map only) |
| Expected change | `AINext*` similarity | `AINext*` integration | — | — | **NC** |
| Named AI tools | `AISearch*`, `AIDev*` | `AISearchDev*` | `AIAgentExternal` (agent users), `AIModels*`, `DevEnvs` | `AICodeAgent*`, `LLM*`, `AIMem/Orch/Obs/NoCode/Automate*` | **NC** (23↔24 Copilot/ChatGPT **CC**) |
| AI agents | — | — | `AIAgents`, `AIAgentChange`, `AIAgent_Uses`, `AIAgentImpact*`, `AIAgentChallenges*`, tool lists | `AISelect` agents option, `KnowAgentDelegate`, `KnowAgentTrust` | **NC** |
| Challenges / problems | — | `AIChallenges`, `AIEthics` | `AIFrustration` | `Disruption`, `AIAvoid`, `AIImpact_*`, `AISat_*`, `JobEaseAI_*`, `JobDifficultyAI_*` | **NC** (different constructs) |
| Learning AI | — | — | `LearnCodeAI`, `AILearnHow` | `LearnAI`, `LearnAIHow` | 25↔26 **CC** (binary yes/no only) |
| Stack Overflow & AI | `SOAI` (text) | — | `SOFriction` | `SOChange` | **NC** |
| Org AI context | — | — | — | `AIUse`, `AITry`, `AIAdopt`, `AIToken`, `AICost`, `AICostPrompt`, `AIToolCount`, `AIToolSwitch`, `AIRetain`, `KnowledgeSourceAI`, `BuildToolAI`, `LanguagesUsedAI`, `AIDaily` | 2026 only |
| Open text | `AIOpen` | — | `AIOpen` (different prompt), `AIExplain` (vibe coding), `AIHuman` | — | **NC** |

## Who was asked (routing) — the single most important caveat

| Item | 2023 | 2024 | 2025 | 2026 |
|---|---|---|---|---|
| Sentiment | Yes + plan | Yes + plan | **Everyone** | Users only |
| Trust | Yes + plan | **Yes only** | **Everyone** | Users only |
| Complex | — | Yes only | Everyone | Users only |
| Threat | — | Yes + plan | Everyone | — |
| Workflow "currently" grid | Yes only | Yes only | Everyone (mostly users answer) | Users only |

Verified empirically: e.g. 2024 `AIAcc` answered by 99.4% of users, 0% of planners/non-users; 2025 `AIAcc`
answered by ~98% of every group. **Published toplines are therefore not like-for-like across years;
compare attitudes among current users (`ai_user == TRUE`) only.** Even then, the *definition* of
"user" changes in 2025 (frequency options) and 2026 (work-only, multi-select by tool type).

## Wording changes worth knowing

* 2023 column names `AIAcc` (benefits) and `AIBen` (trust) are **swapped** relative to 2024–2025 — schema
  text confirms. `01_harmonise.R` maps them by meaning, not by name.
* 2026 sentiment: "Favorable"→"Somewhat favorable", "Indifferent"→"Neutral", "Unsure"→"Not sure";
  question reframed as "attitude toward using AI tools **or agents** as part of your **work**".
* 2025 `AITool` horizon "next year" → "next 3–5 years"; grid changed to *mostly / partially / plan / don't plan*.
* 2026 `AIWork` horizon back to "next year", new 19-task list; harmonised mapping to 8 legacy tasks is
  approximate (e.g. two "Generating code…" tasks → `aiw_writing_code`).
* 2026 `AITrust` options describe *conditions* of trust (e.g. "I trust it when I can easily verify the
  output") — not a level scale; do not map to the 5-point trust variable.

## Demographics harmonisation (non-AI)

| Harmonised var | 2023 / 2024 source | 2025 source | 2026 source | Caveat |
|---|---|---|---|---|
| `dev_status`, `is_professional_dev` | `MainBranch` | `MainBranch` (+ "I work with developers…") | `CodeMain` ("create code as a primary part of my job") | 2026 is a different construct **[CC]** |
| `age_band` | `Age` | `Age` (no Under 18 in public file) | `Age` | **C** for 18+ |
| `employment_status` | `Employment` multi → priority rule | `Employment` single | `Employment` single | **CC** |
| `remote_work` | `RemoteWork` 3 levels | `RemoteWork` 5 levels | `WorkSetting` 5 levels | collapsed to Remote/Hybrid/In-person; "Your choice…"→Hybrid is a judgement **[VERIFY]** |
| `education` | `EdLevel` | `EdLevel` | `Education` | **C** |
| `role_family` | `DevType` | `DevType` | `Role` (41 options) | 7 families; **CC** |
| `org_size` | `OrgSize` (2–9, 10–19) | `OrgSize` ("Less than 20") | `OrgSize` | 2–19 merged; **CC** |
| `years_code` | `YearsCode` dropdown | `YearsCode` free number | `YearsCode` | top-coded 50; **CC** |
| `years_pro` | `YearsCodePro` | `WorkExp` (general work exp.) | `WorkExp` | **NC** 23/24 vs 25/26 |
| `country`, `region`, `continent` | `Country` | `Country` | `Country` | missingness 1.4/9.9/28/31% |
| `ic_or_pm` | `ICorPM` (subset) | `ICorPM` | `ICorPM` (4 levels) | **CC** |
| `comp_usd_yearly` | `ConvertedCompYearly` | same | same | FX date differs per year |
