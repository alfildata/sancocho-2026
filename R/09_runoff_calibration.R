# 09 — Calibración de incertidumbre del forecast de 2da vuelta.
#
# El motor (PR #298) da una banda 80% para 2026 que NO cruza 50: el posterior solo
# captura muestreo + house effect, no el error sistemático encuesta-vs-resultado.
# Igual que 04_backtest.R calibra fcast_logit_sd para 1ra vuelta, acá derivamos el
# SHOCK DE PRONÓSTICO de balotaje desde los residuos del backtest 2014/2018/2022 y
# vemos su efecto en la banda 2026 — para que exprese la lección-2022 (el favorito
# puede no transferir completo; un cruce a 50 debe quedar dentro del intervalo).

logit <- function(p) log(p / (1 - p))
invlogit <- function(x) 1 / (1 + exp(-x))
Z80 <- qnorm(0.9)  # 1.2816

# Réplica analítica del motor TS (runoff-model.ts): posterior Normal-Normal sobre
# theta = log(pA/pB). extraShock = SD extra (logit) por error de pronóstico.
projectRunoff <- function(baseA, baseB, toA, toB, polls, priorSd, halfLife, surveyInflation, extraShock = 0) {
  impliedA <- baseA + sum(toA)
  impliedB <- baseB + sum(toB)
  mu <- log(impliedA / impliedB)
  precPost <- 1 / priorSd^2
  wsum <- mu * precPost
  if (!is.null(polls)) for (i in seq_len(nrow(polls))) {
    hh <- polls$A[i] + polls$B[i]
    if (hh <= 0 || polls$sample[i] <= 0) next
    pA <- polls$A[i] / hh
    theta <- log(polls$A[i] / polls$B[i])
    nEff <- polls$sample[i] * hh / 100
    v <- 1 / (nEff * pA * (1 - pA)) + surveyInflation
    w <- 0.5^(polls$d[i] / halfLife)
    precPost <- precPost + w / v
    wsum <- wsum + (w / v) * theta
  }
  meanLogit <- wsum / precPost
  sdLogit <- sqrt(1 / precPost + extraShock^2)
  list(mean = invlogit(meanLogit), lo = invlogit(meanLogit - Z80 * sdLogit),
       hi = invlogit(meanLogit + Z80 * sdLogit), meanLogit = meanLogit, sdLogit = sdLogit)
}

PRIORSD <- 0.15; HALFLIFE <- 14; SURVEY <- 0.0009

# --- Backtest: residuos modelo-vs-real (escala logit) ------------------------
bt <- list(
  list(yr = "2014", baseA = 29.28, baseB = 25.72, impliedA = 47.85, impliedB = 52.15, real = 0.469,
       polls = data.frame(A = c(47,37,48.5,38.5,37.7,49), B = c(45,38,47.7,43.4,41.9,41),
                          sample = c(1996,1672,1200,3215,1200,1784), d = c(19,19,12,12,11,11))),
  list(yr = "2018", baseA = 39.14, baseB = 25.08, impliedA = 56.85, impliedB = 43.15, real = 0.564,
       polls = data.frame(A = c(55,52,57.2,45.3,46.2,51,52.5), B = c(35,34,37.3,36.4,40.2,38,36),
                          sample = c(1323,1251,1200,1983,1993,1561,3955), d = c(17,13,12,12,11,9,9))),
  list(yr = "2022", baseA = 40.34, baseB = 28.17, impliedA = 49.48, impliedB = 50.52, real = 0.516,
       polls = data.frame(A = c(39,44.9,41,48.1,47.5), B = c(41,41,42,48.1,50.2),
                          sample = c(2000,1800,1200,1500,4467), d = c(19,16,14,13,8)))
)

resid_logit <- c()
cat("\n== Backtest: modelo vs real (share A/(A+B)) ==\n")
for (c0 in bt) {
  r <- projectRunoff(c0$baseA, c0$baseB, c0$impliedA - c0$baseA, c0$impliedB - c0$baseB,
                     c0$polls, PRIORSD, HALFLIFE, SURVEY)
  res <- logit(r$mean) - logit(c0$real)
  resid_logit <- c(resid_logit, res)
  cat(sprintf("  %s: modelo %.3f  real %.3f  resid(logit) %+.3f\n", c0$yr, r$mean, c0$real, res))
}
shock <- sqrt(mean(resid_logit^2))   # RMS de los residuos en logit = shock de pronóstico
cat(sprintf("\nShock de pronóstico (RMS residuos, logit) = %.3f\n", shock))

# --- 2026: banda actual vs banda honesta (con shock) -------------------------
toA26 <- c(5.26,0.81,0.11,0.26,0.19,0,0)
toB26 <- c(0.42,1.02,0.31,0.17,0.08,0.04,0.01)
poll26 <- data.frame(A = 50.3, B = 42.6, sample = 2030, d = 19)

now  <- projectRunoff(43.74, 40.90, toA26, toB26, poll26, PRIORSD, HALFLIFE, SURVEY, extraShock = 0)
hon  <- projectRunoff(43.74, 40.90, toA26, toB26, poll26, PRIORSD, HALFLIFE, SURVEY, extraShock = shock)

cat("\n== Forecast 2026 (share Abelardo) ==\n")
cat(sprintf("  Actual (sin shock):  %.1f%%  [%.1f-%.1f]  cruza 50: %s\n",
            100*now$mean, 100*now$lo, 100*now$hi, ifelse(now$lo < 0.5, "SÍ", "NO")))
cat(sprintf("  Honesto (con shock): %.1f%%  [%.1f-%.1f]  cruza 50: %s\n",
            100*hon$mean, 100*hon$lo, 100*hon$hi, ifelse(hon$lo < 0.5, "SÍ", "NO")))

# priorSd equivalente que reproduce el SD honesto SIN agregar un parámetro nuevo
# (para los consumidores que solo exponen priorSd): inflar priorSd hasta igualar sdLogit.
target_sd <- hon$sdLogit
f <- function(ps) projectRunoff(43.74,40.90,toA26,toB26,poll26,ps,HALFLIFE,SURVEY)$sdLogit - target_sd
priorSd_eq <- tryCatch(uniroot(f, c(0.05, 2))$root, error = function(e) NA)
cat(sprintf("\nForecastShock recomendado = %.3f (logit)\n", shock))
cat(sprintf("priorSd equivalente (si no se agrega forecastShock al motor) = %.3f\n", priorSd_eq))

out <- data.frame(
  param = c("forecastShockLogit","priorSd_actual","priorSd_equivalente","share2026_mean","lo80_honesto","hi80_honesto"),
  valor = round(c(shock, PRIORSD, priorSd_eq, hon$mean, hon$lo, hon$hi), 4)
)
write.csv(out, file.path("output","runoff_calibration.csv"), row.names = FALSE)
cat("\n09_runoff_calibration — OK. CSV: output/runoff_calibration.csv\n")
