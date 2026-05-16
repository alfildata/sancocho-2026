# 01 — Preparación de datos: de los CSV crudos a los stan_data del modelo.
# Salida: archivos RDS en data/processed/, uno por (año × variante).
#
#   Variantes:
#     V1  = solo encuestas (prior plano)
#     V3  = encuestas + prior estructural Sancocho (Senado 2026 + bancadas)
#   El prior estructural histórico (backtest V2) se construye en 04_backtest.R.

source("R/config.R")
source("R/helpers.R")

dir.create(CFG$paths$processed, showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# 2026 — el forecast del concurso
# ============================================================================

polls_2026 <- prep_encuestas_2026(CFG)
cat_2026   <- CFG$candidates_2026
elec_2026  <- CFG$election_date[["2026"]]

message(sprintf("Encuestas 2026 utilizables: %d (de 26; excluidas: %s)",
                nrow(polls_2026), paste(CFG$exclude_polls_2026, collapse = ", ")))
message(sprintf("  Encuestadoras: %s",
                paste(sort(unique(polls_2026$encuestadora)), collapse = ", ")))

# --- Prior estructural: rollup de la transferencia partido-por-partido ------

rollup_prop <- structural_prior_rollup(CFG, CFG$candidates_2026)

message("\nPrior estructural (rollup party-level transfer):")
print(round(rollup_prop * 100, 2))

# Chequeo de sanidad contra el rollup documentado (docs/methodology.md §3).
# Valores literales de la decisión del equipo (2026-05-20): el rollup
# refleja los splits exactos del CSV. El cero en `otros` es esperado y
# se neutraliza con un guard mínimo en `structural_prior_logit` (helpers.R).
expected <- c(cepeda = 0.4501, espriella = 0.2439, valencia = 0.2822,
              fajardo = 0.0137, lopez = 0.0101, otros = 0.0000)
if (max(abs(rollup_prop - expected)) > 0.005) {
  warning("El rollup difiere >0.5pp del valor documentado en §3 — revisar.")
}

prior_logit_2026 <- structural_prior_logit(rollup_prop)
prior_sd_2026    <- CFG$prior_sd_2026[c("cepeda", "espriella", "valencia",
                                        "fajardo", "lopez")]

# --- V1: solo encuestas ------------------------------------------------------

sd_2026_v1 <- build_stan_data(
  polls_2026, cat_2026, elec_2026,
  prior_logit = NULL, prior_sd = NULL,
  half_life = CFG$decay_half_life_days
)

# --- V3: encuestas + prior estructural Sancocho -----------------------------

sd_2026_v3 <- build_stan_data(
  polls_2026, cat_2026, elec_2026,
  prior_logit = prior_logit_2026, prior_sd = prior_sd_2026,
  half_life = CFG$decay_half_life_days
)

saveRDS(list(polls = polls_2026, rollup_prop = rollup_prop,
             prior_logit = prior_logit_2026, prior_sd = prior_sd_2026,
             v1 = sd_2026_v1, v3 = sd_2026_v3),
        file.path(CFG$paths$processed, "stan_data_2026.rds"))

# ============================================================================
# Histórico — backtest V1 (solo encuestas)
# ============================================================================

for (yr in c("2014", "2018", "2022")) {
  polls <- prep_encuestas_hist(yr, CFG)
  spec  <- HIST_SPEC[[yr]]
  cats  <- c(names(spec$scored), "otros")
  elec  <- CFG$election_date[[yr]]

  sd_v1 <- build_stan_data(polls, cats, elec,
                           prior_logit = NULL, prior_sd = NULL,
                           half_life = CFG$decay_half_life_days)

  saveRDS(list(polls = polls, cats = cats, election_date = elec, v1 = sd_v1),
          file.path(CFG$paths$processed, sprintf("stan_data_%s.rds", yr)))

  message(sprintf("Backtest %s: %d encuestas 1ra vuelta, %d encuestadoras, candidatos: %s",
                  yr, nrow(polls), sd_v1$data$J, paste(cats, collapse = ", ")))
}

message("\n01_data_prep — OK. Archivos en ", CFG$paths$processed, "/")
