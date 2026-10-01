# PKNCA documentation and citation

Companion to [SKILL.md](../SKILL.md). Read these on demand, for behaviour the template and
the other reference pages do not cover (custom intervals, BLQ handling, imputation,
λz business rules). Tested with PKNCA 0.12.1; check `packageVersion("PKNCA")` and the
installed help pages before relying on anything version-specific.

- Package site (function reference + articles): https://humanpred.github.io/pknca/
- User Guide (book): https://humanpred.github.io/pknca-book/
- Source and issues: https://github.com/humanpred/pknca
- Vignettes (read on demand, `vignette(package = "PKNCA")` or online):
  - [Introduction and usage](https://humanpred.github.io/pknca/articles/v01-introduction-and-usage.html)
  - [Theophylline example](https://humanpred.github.io/pknca/articles/v02-example-theophylline.html) — the same dataset as the worked example (`examples/abc-111/data/pk-data.csv`)
  - [Selection of calculation intervals](https://humanpred.github.io/pknca/articles/v03-selection-of-calculation-intervals.html) — how to request/override interval parameters (`cl.obs`, `vz.obs`, custom windows)
  - [AUC calculation](https://humanpred.github.io/pknca/articles/v05-auc-calculation-with-PKNCA.html)
  - [Half-life calculation](https://humanpred.github.io/pknca/articles/v06-half-life-calculation.html) and [Tobit-regression half-life](https://humanpred.github.io/pknca/articles/v06-half-life-calculation-tobit.html) for BLQ-heavy terminal phases
  - [Unit assignment and conversion](https://humanpred.github.io/pknca/articles/v07-unit-conversion.html)
  - [Data imputation](https://humanpred.github.io/pknca/articles/v08-data-imputation.html)
  - [Options for controlling PKNCA](https://humanpred.github.io/pknca/articles/v40-options-for-controlling-PKNCA.html) — business-rule options (λz window rules, exclusions, summarization)
- Citation: Denney W, Duvvuri S, Buckeridge C (2015). "Simple, Automatic Noncompartmental Analysis: The PKNCA R Package." *J Pharmacokinet Pharmacodyn* 42(1):11–107. doi:10.1007/s10928-015-9432-2
