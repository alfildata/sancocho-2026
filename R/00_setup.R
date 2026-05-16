# 00 — Setup del entorno: paquetes R, toolchain y CmdStan.
# Idempotente: correr de nuevo no rompe nada.

options(repos = c(CRAN = "https://cloud.r-project.org"))

source("R/config.R")   # solo define CFG; no carga paquetes

# --- Paquetes R -------------------------------------------------------------

needed <- c("cmdstanr", "posterior", "bayesplot", "readr", "dplyr", "ggplot2")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing) > 0) {
  message("Instalando: ", paste(missing, collapse = ", "))
  if ("cmdstanr" %in% missing) {
    install.packages("cmdstanr",
      repos = c("https://stan-dev.r-universe.dev", getOption("repos")))
    missing <- setdiff(missing, "cmdstanr")
  }
  if (length(missing) > 0) install.packages(missing)
}

library(cmdstanr)

# --- CmdStan ----------------------------------------------------------------

# Si CMDSTAN está en el entorno y es válido, usarlo; si no, instalar.
cmdstan_env <- Sys.getenv("CMDSTAN")
if (nzchar(cmdstan_env) && dir.exists(cmdstan_env)) {
  set_cmdstan_path(cmdstan_env)
}

ok <- tryCatch({ cmdstan_version(); TRUE }, error = function(e) FALSE)

if (!ok) {
  message("CmdStan no encontrado — verificando toolchain e instalando...")
  check_cmdstan_toolchain(fix = TRUE)
  # Ruta corta para esquivar el límite de 260 caracteres de Windows.
  # install_cmdstan() exige que el directorio padre ya exista.
  dir.create("C:/cmdstan", showWarnings = FALSE, recursive = TRUE)
  install_cmdstan(dir = "C:/cmdstan", cores = 4, overwrite = FALSE)
  set_cmdstan_path(list.dirs("C:/cmdstan", recursive = FALSE)[1])
}

check_cmdstan_toolchain()
message("CmdStan ", cmdstan_version(), " en ", cmdstan_path())

# --- Smoke test -------------------------------------------------------------

smoke_file <- file.path(tempdir(), "smoke.stan")
writeLines(c(
  "data { int<lower=0> N; array[N] real y; }",
  "parameters { real mu; real<lower=0> sigma; }",
  "model { y ~ normal(mu, sigma); }"
), smoke_file)

smoke <- cmdstan_model(smoke_file, cpp_options = list(stan_threads = TRUE))
fit <- smoke$sample(
  data = list(N = 100, y = rnorm(100, 3, 2)),
  chains = 2, parallel_chains = 2, threads_per_chain = 1,
  iter_warmup = 500, iter_sampling = 500, refresh = 0, seed = CFG$seed
)
print(fit$summary())
message("\nSmoke test OK — toolchain saludable. Listo para el modelo Sancocho.")
