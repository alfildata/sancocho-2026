# 07 — Sancocho 2da vuelta (runoff). Spike exploratorio (follow-up del modelo de 1a vuelta).
#
# Reusa el motor Stan (stan/sancocho_dm.stan, K genérico) para el head-to-head A vs B.
# La "pista de 1a vuelta" entra como PRIOR ESTRUCTURAL sobre log(pB/pA), exactamente
# donde en 1a vuelta entraba el rollup Senado+bancadas. K=3: (A, B, blanco).
#   A = ganador de la 1a vuelta ; B = segundo ; blanco = referencia.
# Métrica: share A/(A+B) (define el ganador, robusto a cómo cada firma reporta blanco).
#
# Datos: verificados por el workflow sancocho-runoff-spike (ground truths Registraduría,
# encuestas de balotaje repo+web, transferencias de eliminados con endorsements).
# Backtest 2014/2018/2022 (conocemos el resultado real) + forecast 2026.

source("R/config.R")
source("R/helpers.R")
source("R/extract.R")
suppressWarnings(suppressMessages(library(cmdstanr)))

set.seed(CFG$seed)
ensure_cmdstan_path()
mod <- cmdstan_model(CFG$paths$stan)

# Muestreo más liviano para el spike (K=3, pocas encuestas).
CFGR <- CFG
CFGR$iter_warmup   <- 1000L
CFGR$iter_sampling <- 1000L

RUNOFF_HALF_LIFE <- 14   # campaña de balotaje corta (~3 semanas) -> decae más rápido que 1a (25d)
SD_GRID <- c(0.08, 0.20, 0.40)   # ancla del prior en log-ratio: chico=prior manda, grande=encuestas mandan

NAMES <- list(
  "2014" = c(A = "Zuluaga",  B = "Santos"),
  "2018" = c(A = "Duque",    B = "Petro"),
  "2022" = c(A = "Petro",    B = "Hernandez"),
  "2026" = c(A = "Abelardo", B = "Cepeda")
)
ELEC2 <- list("2014" = as.Date("2014-06-15"), "2018" = as.Date("2018-06-17"),
              "2022" = as.Date("2022-06-19"), "2026" = as.Date("2026-06-21"))

# impliedPrior sobre A+B (modelo de transferencia del workflow)
PRIOR <- list("2014" = c(A = 47.85, B = 52.15), "2018" = c(A = 56.85, B = 43.15),
              "2022" = c(A = 49.48, B = 50.52), "2026" = c(A = 53.97, B = 46.03))

# ground truth: share A/(A+B) sobre votos válidos (Registraduría, verificado)
TRUTH <- list("2014" = 45.00 / (45.00 + 50.99), "2018" = 53.98 / (53.98 + 41.81),
              "2022" = 50.44 / (50.44 + 47.31), "2026" = NA_real_)

# Encuestas de balotaje POST-1a vuelta. A = ganador de 1a.
polls <- list()
polls[["2014"]] <- data.frame(
  pollster = c("CNC","Cifras","Invamer","Cifras","Datexco","Ipsos"),
  fecha = as.Date(c("2014-05-27","2014-05-27","2014-06-03","2014-06-03","2014-06-04","2014-06-04")),
  A = c(47,37,48.5,38.5,37.7,49), B = c(45,38,47.7,43.4,41.9,41),
  blanco = c(8,15,3.7,11.7,13.8,10), n = c(1996,1672,1200,3215,1200,1784))
polls[["2018"]] <- data.frame(
  pollster = c("CNC","YanHaas","Invamer","Cifras","Datexco","CNC","Guarumo"),
  fecha = as.Date(c("2018-05-31","2018-06-04","2018-06-05","2018-06-05","2018-06-06","2018-06-08","2018-06-08")),
  A = c(55,52,57.2,45.3,46.2,51,52.5), B = c(35,34,37.3,36.4,40.2,38,36),
  blanco = c(10,14,5.5,18.3,13.6,11,11.5), n = c(1323,1251,1200,1983,1993,1561,3955))
polls[["2022"]] <- data.frame(
  pollster = c("CNC","CNC","Yanhaas","GAD3","AtlasIntel"),
  fecha = as.Date(c("2022-05-31","2022-06-03","2022-06-05","2022-06-06","2022-06-11")),
  A = c(39,44.9,41,48.1,47.5), B = c(41,41,42,48.1,50.2),
  blanco = c(7,5,8,4,2.4), n = c(2000,1800,1200,1500,4467))
polls[["2026"]] <- data.frame(  # única encuesta de balotaje con campo POST-1a (Atlas 1-2 jun)
  pollster = c("AtlasIntel"), fecha = as.Date(c("2026-06-02")),
  A = c(50.3), B = c(42.6), blanco = c(3.7), n = c(2030))

# Hipotéticos de balotaje PRE-1a vuelta 2026 (oleadas finales ~mayo) — variante con decay.
polls2026_pre <- data.frame(
  pollster = c("AtlasIntel_pre","Invamer","Guarumo","CNC","TEMPO"),
  fecha = as.Date(c("2026-05-20","2026-05-17","2026-05-15","2026-05-19","2026-05-16")),
  A = c(50,45.3,43.6,43.6,36), B = c(41.3,52.4,40,40.9,43.2),
  blanco = c(8.8,2.3,16.4,10.3,11.7), n = c(4531,2160,3787,2202,1860))

build_runoff <- function(pl, elec, priorAB = NULL, sd_dial = NULL, half_life = RUNOFF_HALF_LIFE) {
  cats <- c("A","B","blanco")
  rows <- lapply(seq_len(nrow(pl)), function(i) {
    cc <- collapse_to_counts(c(A = pl$A[i], B = pl$B[i], blanco = pl$blanco[i]), pl$n[i])
    data.frame(encuestadora = pl$pollster[i], fecha = pl$fecha[i], n_eff = cc$n_eff,
               A = cc$counts[1], B = cc$counts[2], blanco = cc$counts[3])
  })
  polls_df <- do.call(rbind, rows)
  if (is.null(priorAB)) {
    build_stan_data(polls_df, cats, elec, prior_logit = NULL, prior_sd = NULL, half_life = half_life)
  } else {
    prop <- c(priorAB[["A"]], priorAB[["B"]], 5); prop <- prop / sum(prop)
    build_stan_data(polls_df, cats, elec, prior_logit = structural_prior_logit(prop),
                    prior_sd = c(99, sd_dial), half_life = half_life)   # solo prior_sd[2] se usa (ancla log(B/A))
  }
}

share_summary <- function(fit) {
  P <- pelec_draws(fit, 3, 0)
  s <- P[, 1] / (P[, 1] + P[, 2])
  c(mean = mean(s), lo = quantile(s, .1, names = FALSE), hi = quantile(s, .9, names = FALSE))
}

rows_out <- list()
emit <- function(yr, metodo, shareA, lo = NA, hi = NA) {
  err <- if (!is.na(TRUTH[[yr]])) abs(shareA - 100 * TRUTH[[yr]]) else NA
  rows_out[[length(rows_out) + 1]] <<- data.frame(anio = yr, metodo = metodo,
      share_A = round(shareA, 1), lo80 = round(lo, 1), hi80 = round(hi, 1), err_pp = round(err, 2))
}

for (yr in c("2014","2018","2022","2026")) {
  nm <- NAMES[[yr]]
  message(sprintf("\n========== %s   A=%s  vs  B=%s ==========", yr, nm[["A"]], nm[["B"]]))

  message(sprintf("  PRIOR-SOLO (transferencias 1a vuelta):  A = %.1f%%", PRIOR[[yr]][["A"]]))
  emit(yr, "prior_solo", PRIOR[[yr]][["A"]])

  f0 <- sample_model(mod, build_runoff(polls[[yr]], ELEC2[[yr]])$data, CFGR)
  s0 <- share_summary(f0)
  message(sprintf("  ENCUESTAS-SOLO (balotaje post-1a):      A = %.1f%%  [%.1f-%.1f]",
                  100*s0[["mean"]], 100*s0[["lo"]], 100*s0[["hi"]]))
  emit(yr, "encuestas_solo", 100*s0[["mean"]], 100*s0[["lo"]], 100*s0[["hi"]])

  for (sd in SD_GRID) {
    fc <- sample_model(mod, build_runoff(polls[[yr]], ELEC2[[yr]], PRIOR[[yr]], sd)$data, CFGR)
    sc <- share_summary(fc)
    message(sprintf("  COMBINADO  prior_sd=%.2f:                A = %.1f%%  [%.1f-%.1f]",
                    sd, 100*sc[["mean"]], 100*sc[["lo"]], 100*sc[["hi"]]))
    emit(yr, sprintf("combinado_sd%.2f", sd), 100*sc[["mean"]], 100*sc[["lo"]], 100*sc[["hi"]])
  }

  if (!is.na(TRUTH[[yr]]))
    message(sprintf("  >>> REAL:                               A = %.1f%%", 100*TRUTH[[yr]]))
}

# 2026: variante combinando encuestas pre (con decay) + post
message("\n========== 2026 variante: prior + (Atlas post + hipotéticos pre con decay) ==========")
pl_all <- rbind(polls[["2026"]], polls2026_pre)
for (sd in SD_GRID) {
  fc <- sample_model(mod, build_runoff(pl_all, ELEC2[["2026"]], PRIOR[["2026"]], sd)$data, CFGR)
  sc <- share_summary(fc)
  message(sprintf("  COMBINADO+pre  prior_sd=%.2f:            A(Abelardo) = %.1f%%  [%.1f-%.1f]",
                  sd, 100*sc[["mean"]], 100*sc[["lo"]], 100*sc[["hi"]]))
  emit("2026", sprintf("comb_pre_sd%.2f", sd), 100*sc[["mean"]], 100*sc[["lo"]], 100*sc[["hi"]])
}

summary_df <- do.call(rbind, rows_out)
write.csv(summary_df, file.path(CFG$paths$output, "runoff_spike.csv"), row.names = FALSE)
message("\n===== RESUMEN (share A/(A+B)) =====")
print(summary_df, row.names = FALSE)
message("\n07_runoff — OK. CSV: output/runoff_spike.csv")
