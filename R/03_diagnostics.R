# 03 — Diagnósticos de convergencia y posterior predictive checks
# para los fits 2026. Escribe figuras en output/figures/.

source("R/config.R")
source("R/extract.R")
suppressWarnings(suppressMessages({
  library(cmdstanr)
  library(bayesplot)
  library(ggplot2)
}))

dir.create(file.path(CFG$paths$output, "figures"),
           showWarnings = FALSE, recursive = TRUE)

fig <- function(name) file.path(CFG$paths$output, "figures", name)

d2026 <- readRDS(file.path(CFG$paths$processed, "stan_data_2026.rds"))

for (variant in c("v1", "v3")) {
  fit <- readRDS(file.path(CFG$paths$output, "posterior",
                           sprintf("fit_2026_%s.rds", variant)))

  message(sprintf("\n=== Diagnósticos 2026 %s ===", toupper(variant)))
  cv <- convergence_ok(fit)
  message(sprintf("  R-hat máx: %.4f  | ESS-bulk mín: %.0f | ESS-tail mín: %.0f",
                  cv$max_rhat, cv$min_ess_bulk, cv$min_ess_tail))
  message(sprintf("  divergencias: %d | treedepth: %d | E-BFMI mín: %.3f",
                  cv$divergences, cv$max_treedepth, cv$ebfmi_min))
  message(sprintf("  CONVERGENCIA: %s", if (cv$pass) "OK" else "REVISAR"))

  print(convergence_table(fit))

  draws <- fit$draws(format = "draws_array")

  # Trace plots de los parámetros de nivel
  p_trace <- mcmc_trace(draws, regex_pars = "^alpha\\[") +
    ggtitle(sprintf("Trazas — alpha (2026 %s)", toupper(variant)))
  ggsave(fig(sprintf("trace_alpha_2026_%s.png", variant)), p_trace,
         width = 9, height = 6, dpi = 120)

  # Posterior predictive check sobre proporciones
  y_obs <- d2026[[variant]]$data$y
  n_obs <- rowSums(y_obs)
  cats  <- d2026[[variant]]$cat_cols

  y_rep <- fit$draws("y_rep", format = "draws_matrix")
  for (k in seq_along(cats)) {
    obs_prop <- y_obs[, k] / n_obs
    cols <- grep(sprintf("y_rep\\[\\d+,%d\\]$", k), colnames(y_rep))
    rep_mat <- y_rep[, cols, drop = FALSE]
    rep_prop <- sweep(rep_mat, 2, n_obs, "/")
    p_ppc <- ppc_dens_overlay(obs_prop, as.matrix(rep_prop)[1:200, , drop = FALSE]) +
      ggtitle(sprintf("PPC — %s (2026 %s)", cats[k], toupper(variant)))
    ggsave(fig(sprintf("ppc_%s_2026_%s.png", cats[k], variant)), p_ppc,
           width = 7, height = 4, dpi = 120)
  }
}

message("\n03_diagnostics — OK. Figuras en output/figures/")
