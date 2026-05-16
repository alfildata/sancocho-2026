# Extracción y resumen del posterior. Compartido por diagnósticos,
# backtest y forecast.

suppressWarnings(suppressMessages({
  library(posterior)
  library(dplyr)
}))

# --- Error de forecast ------------------------------------------------------
#
# Las encuestas tienen un error sistemático encuesta-vs-resultado que NO es
# muestreo: cambios de última semana (en Colombia la ley prohíbe publicar
# encuestas los 7 días previos), efectos de campaña, modelos de participación.
# El posterior del modelo solo captura la incertidumbre de muestreo + la
# sobredispersión; subestima la incertidumbre real del día de elección.
#
# `fcast_logit_sd` es un shock gaussiano sobre el intercepto (escala log-odds)
# que se suma en cada draw del posterior. Su magnitud se CALIBRA en
# 04_backtest.R igualando el desvío predictivo de p_elec al RMS de los
# residuos del backtest — calibración por momento, no por cobertura. Con esa
# magnitud los intervalos al 80% cubren ~67% empíricamente (ver config.R y
# methodology.md §4.2): las sorpresas de última semana son de cola pesada.

# Draws de p_elec a partir de alpha, con error de forecast opcional.
# Devuelve matriz [draws x K].
pelec_draws <- function(fit, K, fcast_logit_sd = 0) {
  a <- fit$draws("alpha", format = "draws_matrix")
  a <- matrix(as.numeric(a), ncol = K)
  if (fcast_logit_sd > 0) {
    # Shock por candidato; la referencia K queda fija (columna K = 0).
    eps <- matrix(rnorm(nrow(a) * (K - 1), 0, fcast_logit_sd),
                  nrow(a), K - 1)
    a[, seq_len(K - 1)] <- a[, seq_len(K - 1)] + eps
  }
  a <- a - apply(a, 1, max)            # estabilidad numérica del softmax
  e <- exp(a)
  e / rowSums(e)
}

# Resumen de p_elec: media + mediana + intervalos 50/80/95 por categoría.
# `fcast_logit_sd > 0` ensancha los intervalos con el error de forecast.
forecast_summary <- function(fit, cat_cols, fcast_logit_sd = 0) {
  K <- length(cat_cols)
  P <- pelec_draws(fit, K, fcast_logit_sd)
  qs <- c(0.025, 0.10, 0.25, 0.50, 0.75, 0.90, 0.975)
  out <- lapply(seq_len(K), function(k) {
    v <- P[, k]
    q <- quantile(v, qs, names = FALSE)
    data.frame(
      categoria = cat_cols[k],
      media = mean(v), mediana = q[4],
      lo95 = q[1], lo80 = q[2], lo50 = q[3],
      hi50 = q[5], hi80 = q[6], hi95 = q[7]
    )
  })
  bind_rows(out)
}

# Tabla de convergencia: R-hat, ESS bulk/tail para los parámetros clave.
convergence_table <- function(fit, pars = c("p_elec", "alpha",
                                            "kappa", "sigma_house")) {
  fit$summary(variables = pars, "rhat", "ess_bulk", "ess_tail")
}

# Chequeo binario de convergencia contra los umbrales 2026.
convergence_ok <- function(fit) {
  s <- fit$summary(variables = c("p_elec", "alpha", "kappa",
                                 "sigma_house", "delta"),
                   "rhat", "ess_bulk", "ess_tail")
  diag <- fit$diagnostic_summary()
  list(
    max_rhat      = max(s$rhat, na.rm = TRUE),
    min_ess_bulk  = min(s$ess_bulk, na.rm = TRUE),
    min_ess_tail  = min(s$ess_tail, na.rm = TRUE),
    divergences   = sum(diag$num_divergent),
    max_treedepth = sum(diag$num_max_treedepth),
    ebfmi_min     = min(diag$ebfmi, na.rm = TRUE),
    pass = max(s$rhat, na.rm = TRUE) < 1.01 &&
           min(s$ess_bulk, na.rm = TRUE) >= 400 &&
           sum(diag$num_divergent) == 0
  )
}
