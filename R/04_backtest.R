# 04 — Backtest contra 2014 / 2018 / 2022.
#
#   V1 = solo encuestas (prior plano)
#   V2 = encuestas + prior estructural Senado (cada candidato hereda la cuota
#        de su lista al Senado del mismo año)
#
# La capa de bancadas (ingrediente 3 del Sancocho) NO se backtestea: no hay
# documento de respaldos histórico equivalente al PDF de Sampayo. V3 corre
# solo para 2026.
#
# Además: CALIBRA el error de forecast. El posterior del modelo solo captura
# incertidumbre de muestreo; los residuos del backtest miden el error real
# encuesta-vs-resultado. Se elige `fcast_logit_sd` igualando el desvío
# predictivo al RMS de esos residuos — calibración por momento, no por
# cobertura (ver el bloque "Calibración del error de forecast" abajo).

source("R/config.R")
source("R/helpers.R")
source("R/extract.R")
suppressWarnings(suppressMessages(library(cmdstanr)))

set.seed(CFG$seed)
ensure_cmdstan_path()

mod <- cmdstan_model(CFG$paths$stan)

# --- Ajuste de los 6 modelos (3 años x V1/V2) -------------------------------

fits <- list()
for (yr in c("2014", "2018", "2022")) {
  message(sprintf("Ajustando backtest %s ...", yr))
  d <- readRDS(file.path(CFG$paths$processed, sprintf("stan_data_%s.rds", yr)))

  prior_prop  <- CFG$senado_prior_backtest[[yr]][d$cats]
  prior_logit <- structural_prior_logit(prior_prop)
  prior_sd    <- CFG$prior_sd_backtest[[yr]][d$cats[d$cats != "otros"]]
  sd_v2 <- build_stan_data(d$polls, d$cats, d$election_date,
                           prior_logit = prior_logit, prior_sd = prior_sd,
                           half_life = CFG$decay_half_life_days)

  fits[[yr]] <- list(
    cats = d$cats, truth = CFG$ground_truth[[yr]],
    v1 = sample_model(mod, d$v1$data, CFG), v2 = sample_model(mod, sd_v2$data, CFG)
  )
}

# --- Puntuación de un fit (MSE/MAE/cobertura/top-2) --------------------------

score_fit <- function(fit, cats, truth, fcast_sd) {
  pe <- forecast_summary(fit, cats, fcast_logit_sd = fcast_sd)
  scored  <- pe[pe$categoria != "otros", ]
  truth_v <- truth[scored$categoria]
  err     <- scored$media - truth_v
  in_ci   <- truth_v >= scored$lo80 & truth_v <= scored$hi80

  list(
    mse = mean(err^2), mae = mean(abs(err)), coverage = mean(in_ci),
    top2 = setequal(scored$categoria[order(scored$media, decreasing = TRUE)][1:2],
                    scored$categoria[order(truth_v, decreasing = TRUE)][1:2]),
    table = data.frame(candidato = scored$categoria,
                       pred = scored$media, truth = truth_v, error = err,
                       lo80 = scored$lo80, hi80 = scored$hi80, en_ic80 = in_ci)
  )
}

# --- Calibración del error de forecast --------------------------------------
# Se elige fcast_logit_sd para que el desvío predictivo medio de p_elec iguale
# el RMS de los residuos del backtest (error real encuesta-vs-resultado).
# Se calibra por momento (RMS), no por cobertura: con 15 puntos y 3 outliers de
# "sorpresa de última semana", forzar 80% de cobertura sobre-infla los
# intervalos. Igualar el segundo momento da intervalos cuyo ancho refleja la
# magnitud histórica del error sin absorber por completo los outliers.

resid <- unlist(lapply(names(fits), function(yr) {
  score_fit(fits[[yr]]$v1, fits[[yr]]$cats, fits[[yr]]$truth, 0)$table$error
}))
target_rms <- sqrt(mean(resid^2))

grid <- seq(0, 0.45, by = 0.005)
pred_sd_at <- function(sd) {
  v <- unlist(lapply(names(fits), function(yr) {
    cats <- fits[[yr]]$cats
    P <- pelec_draws(fits[[yr]]$v1, length(cats), sd)
    apply(P[, cats != "otros", drop = FALSE], 2, sd)
  }))
  mean(v)
}
psd_grid <- vapply(grid, pred_sd_at, numeric(1))
fcast_sd <- grid[which.min(abs(psd_grid - target_rms))]

message(sprintf("\nRMS de los residuos del backtest: %.4f", target_rms))
message(sprintf("Error de forecast calibrado: fcast_logit_sd = %.3f", fcast_sd))
message(sprintf("  SD predictivo medio a ese valor: %.4f", pred_sd_at(fcast_sd)))

# --- Puntuación final con el error de forecast calibrado --------------------

results <- list()
for (yr in names(fits)) {
  f <- fits[[yr]]
  results[[yr]] <- list(
    v1 = score_fit(f$v1, f$cats, f$truth, fcast_sd),
    v2 = score_fit(f$v2, f$cats, f$truth, fcast_sd)
  )
  message(sprintf("\n=== BACKTEST %s ===", yr))
  for (v in c("v1", "v2")) {
    r <- results[[yr]][[v]]
    message(sprintf("  %s  MSE=%.5f  MAE=%.4f  cobertura80=%.0f%%  top2=%s",
                    toupper(v), r$mse, r$mae, 100 * r$coverage, r$top2))
  }
}

summary_df <- do.call(rbind, lapply(names(results), function(yr) {
  r <- results[[yr]]
  data.frame(anio = yr, variante = c("V1", "V2"),
             mse = c(r$v1$mse, r$v2$mse), mae = c(r$v1$mae, r$v2$mae),
             cobertura80 = c(r$v1$coverage, r$v2$coverage),
             top2_ok = c(r$v1$top2, r$v2$top2))
}))
write.csv(summary_df, file.path(CFG$paths$output, "backtest_summary.csv"),
          row.names = FALSE)
saveRDS(list(results = results, fcast_sd = fcast_sd,
             target_rms = target_rms, psd_grid = psd_grid, grid = grid),
        file.path(CFG$paths$processed, "backtest_results.rds"))

message("\n===== RESUMEN BACKTEST =====")
print(summary_df, row.names = FALSE)
message(sprintf("\nfcast_logit_sd calibrado = %.2f  ->  ponelo en CFG$fcast_logit_sd",
                fcast_sd))
message("04_backtest — OK.")
