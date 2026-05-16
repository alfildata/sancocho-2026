# 02 — Compilación del modelo y ajuste del forecast 2026 (V1 y V3).
# Guarda los objetos fit en output/posterior/ (gitignored).

source("R/config.R")
source("R/helpers.R")
suppressWarnings(suppressMessages(library(cmdstanr)))

ensure_cmdstan_path()

dir.create(file.path(CFG$paths$output, "posterior"),
           showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(CFG$paths$output, "sessions"),
           showWarnings = FALSE, recursive = TRUE)

# --- Compilación (una sola vez; cmdstanr cachea por hash) -------------------

mod <- cmdstan_model(CFG$paths$stan)
message("Modelo compilado: ", mod$exe_file())

# --- Función de ajuste reutilizable -----------------------------------------

fit_model <- function(stan_data, label) {
  message(sprintf("\n=== Ajustando %s (N=%d encuestas, J=%d encuestadoras, K=%d) ===",
                  label, stan_data$N, stan_data$J, stan_data$K))
  fit <- sample_model(mod, stan_data, CFG, refresh = 500)
  diag <- fit$diagnostic_summary()
  message(sprintf("  divergencias: %d | treedepth excedido: %d",
                  sum(diag$num_divergent), sum(diag$num_max_treedepth)))
  fit
}

# --- 2026: V1 (solo encuestas) y V3 (+ prior estructural Sancocho) ----------

d2026 <- readRDS(file.path(CFG$paths$processed, "stan_data_2026.rds"))

fit_v1 <- fit_model(d2026$v1$data, "2026 V1 — solo encuestas")
fit_v3 <- fit_model(d2026$v3$data, "2026 V3 — Sancocho (encuestas + Senado + bancadas)")

fit_v1$save_object(file.path(CFG$paths$output, "posterior", "fit_2026_v1.rds"))
fit_v3$save_object(file.path(CFG$paths$output, "posterior", "fit_2026_v3.rds"))

# --- Snapshot de sesión (reproducibilidad) ----------------------------------

sess_file <- file.path(CFG$paths$output, "sessions",
                       format(Sys.time(), "%Y%m%d_%H%M%S.txt"))
capture.output(sessionInfo(), file = sess_file)
cat("\nCmdStan: ", cmdstan_version(), "\n", file = sess_file, append = TRUE)

message("\n02_fit — OK. Fits en output/posterior/")
