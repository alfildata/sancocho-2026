# 10 — Skill out-of-sample + ablación: ¿qué insumos aportan valor predictivo real?
#
# Leave-one-election-out (LOO): para cada balotaje histórico calibramos en las OTRAS
# elecciones y predecimos la dejada afuera. Así separamos el AJUSTE in-sample del
# VALOR PREDICTIVO real — la única forma honesta de responder "¿el prior por
# transferencia aporta, o las encuestas solas predicen igual?". Correlación no es
# causalidad: una variable puede ajustar in-sample sin aportar fuera de muestra.
#
# Scoring propio (proper scoring rules), no solo error del punto:
#   - MAE (pp) del share A/(A+B)
#   - Brier y log-score sobre P(gana A)   [premian probabilidad calibrada]
#   - CRPS sobre el share                 [premia la distribución predictiva entera]
# Engine analítico = réplica del motor TS (runoff-model.ts), validado vs Stan en R/09.

logit <- function(p) log(p / (1 - p)); invlogit <- function(x) 1 / (1 + exp(-x))

# Posterior Normal-Normal sobre theta = log(pA/pB); cada encuesta entra como
# verosimilitud gaussiana en logit, con peso por n efectivo y decay temporal.
# extraShock = SD extra (logit) por error sistemático de pronóstico (calibrado LOO).
project <- function(impliedA, impliedB, polls, priorSd, halfLife = 14, surveyInflation = 9e-4, extraShock = 0) {
  mu <- log(impliedA / impliedB); prec <- 1 / priorSd^2; wsum <- mu * prec
  if (!is.null(polls)) for (i in seq_len(nrow(polls))) {
    hh <- polls$A[i] + polls$B[i]; if (hh <= 0 || polls$sample[i] <= 0) next
    pA <- polls$A[i] / hh; theta <- log(polls$A[i] / polls$B[i])
    nEff <- polls$sample[i] * hh / 100; v <- 1 / (nEff * pA * (1 - pA)) + surveyInflation
    w <- 0.5^(polls$d[i] / halfLife); prec <- prec + w / v; wsum <- wsum + (w / v) * theta
  }
  mL <- wsum / prec
  list(meanLogit = mL, sdLogit = sqrt(1 / prec + extraShock^2), mean = invlogit(mL))
}

# CRPS por muestras (Gneiting-Raftery); la suma doble vía orden para evitar O(n^2):
# CRPS = mean(|x-y|) - (1/n^2) * sum_i (2i - n - 1) * x_(i)
crps_samples <- function(x, y) {
  n <- length(x); xs <- sort(x)
  mean(abs(x - y)) - sum((2 * seq_len(n) - n - 1) * xs) / n^2
}

score_one <- function(pr, real, nsamp = 8000) {
  s <- invlogit(rnorm(nsamp, pr$meanLogit, pr$sdLogit))   # muestras del share A
  pwin <- mean(s > 0.5); win <- as.integer(real > 0.5)
  pw <- min(max(pwin, 1e-6), 1 - 1e-6)
  c(mae = 100 * abs(pr$mean - real),
    brier = (pwin - win)^2,
    logloss = -(win * log(pw) + (1 - win) * log(1 - pw)),
    crps = 100 * crps_samples(s, real),
    hit = as.numeric((pwin > 0.5) == (win == 1)))
}

# --- Datos históricos (A = ganador de 1a vuelta; real = share A/(A+B) sobre válidos) ---
# Caso duro 2022: el prior dio A por debajo de 50 y A (Petro) ganó. Caso 2014: el
# prior dio A arriba y A (Zuluaga) perdió. Tensión sana para el out-of-sample.
bt <- list(
  `2014` = list(impliedA = 47.85, impliedB = 52.15, real = 45.00 / (45.00 + 50.99),
    polls = data.frame(A = c(47, 37, 48.5, 38.5, 37.7, 49), B = c(45, 38, 47.7, 43.4, 41.9, 41),
                       sample = c(1996, 1672, 1200, 3215, 1200, 1784), d = c(19, 19, 12, 12, 11, 11))),
  `2018` = list(impliedA = 56.85, impliedB = 43.15, real = 53.98 / (53.98 + 41.81),
    polls = data.frame(A = c(55, 52, 57.2, 45.3, 46.2, 51, 52.5), B = c(35, 34, 37.3, 36.4, 40.2, 38, 36),
                       sample = c(1323, 1251, 1200, 1983, 1993, 1561, 3955), d = c(17, 13, 12, 12, 11, 9, 9))),
  `2022` = list(impliedA = 49.48, impliedB = 50.52, real = 50.44 / (50.44 + 47.31),
    polls = data.frame(A = c(39, 44.9, 41, 48.1, 47.5), B = c(41, 41, 42, 48.1, 50.2),
                       sample = c(2000, 1800, 1200, 1500, 4467), d = c(19, 16, 14, 13, 8)))
)
PSD <- 0.15        # prior_sd del combinado (ancla del prior por transferencia)
PSD_FLAT <- 10     # prior ~plano: dejan mandar las encuestas

variants <- c("prior_solo", "encuestas_solas", "combinado", "combinado+shock")

# forecastShock LOO: RMS de residuos logit del COMBINADO en las OTRAS elecciones
# (nunca usa la held-out para calibrarse -> honesto).
loo_shock <- function(holdout) {
  res <- c()
  for (yr in setdiff(names(bt), holdout)) {
    d <- bt[[yr]]; p <- project(d$impliedA, d$impliedB, d$polls, PSD)
    res <- c(res, logit(p$mean) - logit(d$real))
  }
  sqrt(mean(res^2))
}

set.seed(20260621)
acc <- list()
for (yr in names(bt)) {
  d <- bt[[yr]]; sh <- loo_shock(yr)
  preds <- list(
    prior_solo        = project(d$impliedA, d$impliedB, NULL,    PSD),
    encuestas_solas   = project(1, 1, d$polls, PSD_FLAT),               # prior neutro (mu=0)
    combinado         = project(d$impliedA, d$impliedB, d$polls, PSD),
    `combinado+shock` = project(d$impliedA, d$impliedB, d$polls, PSD, extraShock = sh)
  )
  for (v in variants) acc[[v]] <- rbind(acc[[v]], score_one(preds[[v]], d$real))
}

cat("\n== Skill LOO por variante (promedio sobre 2014/2018/2022; menor = mejor salvo hits) ==\n")
tab <- do.call(rbind, lapply(variants, function(v) {
  m <- colMeans(acc[[v]])
  data.frame(variante = v, MAE_pp = round(m["mae"], 2), Brier = round(m["brier"], 3),
             logloss = round(m["logloss"], 3), CRPS_pp = round(m["crps"], 2),
             hits = sprintf("%d/3", round(sum(acc[[v]][, "hit"]))))
}))
print(tab, row.names = FALSE)
cat("\nLectura: si 'combinado' no le gana a 'encuestas_solas' fuera de muestra, el prior\n",
    "por transferencia no aporta valor predictivo (solo ajuste in-sample). Con N=3 esto es\n",
    "indicativo; sumar 2010/1998 (y el reverso 1998, donde el 2do de 1a ganó) lo vuelve concluyente.\n", sep = "")
