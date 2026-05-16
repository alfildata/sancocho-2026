# 06 — Análisis de sensibilidad: forecast V3 SIN vs CON AtlasIntel.
#
# Decisión del equipo (2026-05-23): excluir AtlasIntel del forecast oficial
# por consistencia con el criterio metodológico aplicado a otras firmas con
# muestreo no probabilístico (Datexco, W.A.A). El CNE dictó cautelar sobre
# AtlasIntel (CNE-E-DG-2026-014724) por presunto incumplimiento de la
# Ley 2494/2025; la cautelar quedó sin firmeza por el recurso de Semana,
# pero la objeción técnica sobre RDR sigue pendiente. Este script corre el
# modelo V3 las dos formas y reporta la diferencia.
#
# La corrida SIN AtlasIntel es la oficial (idéntica a 05_forecast.R).
# La corrida CON AtlasIntel suma las 7 oleadas de AtlasIntel.
#
# Salidas: output/atlasintel_sensitivity.csv (comparación SIN vs CON) y
#          output/forecast_2026_con_atlasintel.csv (variante CON, con intervalos).

source("R/config.R")
source("R/helpers.R")
source("R/extract.R")
suppressWarnings(suppressMessages(library(cmdstanr)))

ensure_cmdstan_path()

set.seed(CFG$seed)

# --- Prior estructural (idéntico en ambas variantes) ------------------------

rollup_prop <- structural_prior_rollup(CFG, CFG$candidates_2026)
prior_logit <- structural_prior_logit(rollup_prop)
prior_sd    <- CFG$prior_sd_2026[c("cepeda", "espriella", "valencia",
                                   "fajardo", "lopez")]

cat_2026  <- CFG$candidates_2026
elec_2026 <- CFG$election_date[["2026"]]

# --- Construir stan_data V3 para un set de exclusiones dado -----------------

make_v3 <- function(exclude_set) {
  cfg <- CFG
  cfg$exclude_polls_2026 <- sort(exclude_set)
  polls <- prep_encuestas_2026(cfg)
  sd <- build_stan_data(polls, cat_2026, elec_2026,
                        prior_logit = prior_logit, prior_sd = prior_sd,
                        half_life = CFG$decay_half_life_days)
  list(polls = polls, sd = sd)
}

excl_sin <- sort(c(CFG$exclude_polls_base, CFG$atlasintel_polls))  # oficial
excl_con <- sort(CFG$exclude_polls_base)                          # incluye AtlasIntel

v3_sin <- make_v3(excl_sin)
v3_con <- make_v3(excl_con)

message(sprintf("SIN AtlasIntel (oficial): %d encuestas, %d encuestadoras",
                v3_sin$sd$data$N, v3_sin$sd$data$J))
message(sprintf("CON AtlasIntel:           %d encuestas, %d encuestadoras",
                v3_con$sd$data$N, v3_con$sd$data$J))

# --- Ajustar el modelo las dos veces ----------------------------------------

mod <- cmdstan_model(CFG$paths$stan)

fit_sin <- sample_model(mod, v3_sin$sd$data, CFG)
fit_con <- sample_model(mod, v3_con$sd$data, CFG)

div_sin <- sum(fit_sin$diagnostic_summary()$num_divergent)
div_con <- sum(fit_con$diagnostic_summary()$num_divergent)
message(sprintf("Divergencias — sin: %d | con: %d", div_sin, div_con))

# --- Resumir y comparar -----------------------------------------------------

sum_sin <- forecast_summary(fit_sin, cat_2026, fcast_logit_sd = CFG$fcast_logit_sd)
sum_con <- forecast_summary(fit_con, cat_2026, fcast_logit_sd = CFG$fcast_logit_sd)

scored <- cat_2026[cat_2026 != "otros"]

cmp <- data.frame(
  candidato      = CAND_LABEL[scored],
  sin_atlasintel = round(sum_sin$media[match(scored, sum_sin$categoria)], 4),
  con_atlasintel = round(sum_con$media[match(scored, sum_con$categoria)], 4)
)
cmp$delta_pp <- round((cmp$con_atlasintel - cmp$sin_atlasintel) * 100, 2)

write.csv(cmp, file.path(CFG$paths$output, "atlasintel_sensitivity.csv"),
          row.names = FALSE)

# --- Forecast completo CON AtlasIntel (sensibilidad, mismo formato) ---------
# Para tener la variante con AtlasIntel con intervalos, no solo el punto.
# NO es el número oficial — la submission es forecast_2026.csv (sin AtlasIntel).
sc_con <- sum_con[match(scored, sum_con$categoria), ]
forecast_con <- data.frame(
  candidato                = CAND_LABEL[scored],
  proporcion_votos_validos = round(sc_con$media, 4),
  mediana                  = round(sc_con$mediana, 4),
  ic80_lo                  = round(sc_con$lo80, 4),
  ic80_hi                  = round(sc_con$hi80, 4),
  ic95_lo                  = round(sc_con$lo95, 4),
  ic95_hi                  = round(sc_con$hi95, 4)
)
write.csv(forecast_con,
          file.path(CFG$paths$output, "forecast_2026_con_atlasintel.csv"),
          row.names = FALSE)

message("\n===== SENSIBILIDAD AtlasIntel — forecast V3 (% voto válido) =====")
message("(oficial = SIN AtlasIntel; CON = sensibilidad con las 7 oleadas)\n")
for (i in seq_len(nrow(cmp))) {
  r <- cmp[i, ]
  message(sprintf("  %-26s  sin %5.1f%%   con %5.1f%%   Δ %+.1f pp",
                  r$candidato, r$sin_atlasintel * 100,
                  r$con_atlasintel * 100, r$delta_pp))
}
message("\nCSV comparación: ", file.path(CFG$paths$output, "atlasintel_sensitivity.csv"))
message("CSV forecast con AtlasIntel: ",
        file.path(CFG$paths$output, "forecast_2026_con_atlasintel.csv"))
message("06_sensitivity_atlasintel — OK.")
