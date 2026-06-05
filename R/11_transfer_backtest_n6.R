# 11 — Backtest honesto del PRIOR por transferencia, N=6 (1994-2022).
#
# Consciente de inferencia ecológica: la transferencia POR bloque no es observable
# (solo vemos el agregado del balotaje); asignarla es un supuesto, no un dato. Por eso:
#   (a) usamos tasas a-priori DEFENDIBLES por categoría de bloque (endorsement + lean),
#       NO ajustadas a estas elecciones -> el prior es genuinamente fuera de muestra
#       (sin la fuga por hindsight del caveat #2 de R/10);
#   (b) la categoría se define por features OBSERVABLES antes del balotaje
#       (a quién endosó el líder del bloque, y su afinidad ideológica).
#
# Para el share A/(A+B) solo importa el DIFERENCIAL (pA - pB): la masa a blanco o de
# bloques neutros se cancela en el cociente. Eso vuelve el forecast robusto al manejo
# del blanco, y reduce el modelo a "¿cuánto se inclina netamente cada bloque?".
#
# A = ganador de 1a vuelta en todas las elecciones (convención).

logit <- function(p) log(p / (1 - p)); invlogit <- function(x) 1 / (1 + exp(-x))

# Tasas (pA, pB) por categoría. g_end < 1 a propósito: los endorsements NO transfieren
# completo (lección 2022, Fico->Hernández). lean más suave; neutral -> todo blanco.
rates_apriori <- list(
  end_A = c(.70, .10), end_B = c(.10, .70),
  lean_A = c(.50, .15), lean_B = c(.15, .50),
  neutral = c(0, 0)
)
# Misma forma con un techo de endorsement g (lean = 0.7*g): para el ajuste LOO ("alimento histórico").
rates_g <- function(g) list(
  end_A = c(g, .10), end_B = c(.10, g),
  lean_A = c(.7 * g, .15), lean_B = c(.15, .7 * g),
  neutral = c(0, 0)
)

predict_share <- function(e, rates) {
  iA <- e$baseA; iB <- e$baseB
  for (b in e$blocs) { r <- rates[[b$cat]]; iA <- iA + b$mass * r[1]; iB <- iB + b$mass * r[2] }
  iA / (iA + iB)
}

bl <- function(mass, cat) list(mass = mass, cat = cat)

# --- Dataset N=6 (resultados verificados vs Wikipedia; categorías = endorsements/leans documentados) ---
E <- list(
  list(yr = "1994", real = 50.57 / (50.57 + 48.45), baseA = 45.30, baseB = 44.98,
       blocs = list(bl(3.79, "lean_A"), bl(5.93, "neutral"))),
  list(yr = "1998", real = 46.58 / (46.58 + 50.34), baseA = 34.78, baseB = 34.37,           # reverso: A perdió
       blocs = list(bl(26.77, "lean_B"), bl(1.82, "lean_B"), bl(2.26, "neutral"))),
  list(yr = "2010", real = 69.13 / (69.13 + 27.47), baseA = 46.68, baseB = 21.51,           # landslide A
       blocs = list(bl(10.11, "end_A"), bl(6.13, "end_A"), bl(4.38, "end_A"), bl(9.14, "lean_B"), bl(0.52, "neutral"))),
  list(yr = "2014", real = 44.99 / (44.99 + 50.99), baseA = 29.28, baseB = 25.72,           # realineamiento: A perdió
       blocs = list(bl(15.52, "end_A"), bl(15.22, "lean_B"), bl(8.27, "lean_B"))),
  list(yr = "2018", real = 54.03 / (54.03 + 41.77), baseA = 39.36, baseB = 25.09,
       blocs = list(bl(23.78, "neutral"), bl(7.30, "lean_A"), bl(2.05, "neutral"))),
  list(yr = "2022", real = 50.42 / (50.42 + 47.35), baseA = 40.34, baseB = 28.17,           # endorsement no transfirió: A ganó
       blocs = list(bl(23.94, "end_B"), bl(4.18, "neutral"), bl(1.28, "lean_B"), bl(0.23, "lean_B")))
)

# 2026 (forecast): A = Abelardo, B = Cepeda. Endorsements del simulador (Paloma/M.Uribe->Abelardo;
# Roy/Murillo/Caicedo->Cepeda, tentativos); centro sin pronunciamiento -> neutral.
E2026 <- list(yr = "2026", real = NA, baseA = 43.74, baseB = 40.90,
  blocs = list(bl(6.92, "end_A"), bl(0.12, "end_A"), bl(4.26, "neutral"), bl(0.95, "neutral"),
               bl(0.87, "neutral"), bl(0.22, "neutral"), bl(0.08, "neutral"),
               bl(0.05, "end_B"), bl(0.05, "end_B"), bl(0.05, "end_B"), bl(0.02, "neutral")))

dir_ok <- function(pred, real) (pred > 0.5) == (real > 0.5)

# --- Modelos out-of-sample: naive (split de 1a) vs prior_fixed vs prior_LOOfit ---
cat("\n== Predicción del share A/(A+B) por elección (out-of-sample) ==\n")
cat(sprintf("%-6s %7s | %-12s %-14s %-16s\n", "año", "real", "naive(1a)", "prior_fixed", "prior_LOOfit"))
res_fixed <- c(); res_naive <- c()
hit_naive <- hit_fixed <- hit_loo <- 0
for (i in seq_along(E)) {
  e <- E[[i]]
  naive <- e$baseA / (e$baseA + e$baseB)
  pf <- predict_share(e, rates_apriori)
  # LOO: ajusta g (techo endorsement) en las OTRAS 5 elecciones, predice esta.
  others <- E[-i]
  sse <- function(g) sum(sapply(others, function(o) (predict_share(o, rates_g(g)) - o$real)^2))
  g_hat <- optimize(sse, c(0.30, 0.97))$minimum
  pl <- predict_share(e, rates_g(g_hat))
  res_naive <- c(res_naive, naive - e$real); res_fixed <- c(res_fixed, pf - e$real)
  hit_naive <- hit_naive + dir_ok(naive, e$real); hit_fixed <- hit_fixed + dir_ok(pf, e$real); hit_loo <- hit_loo + dir_ok(pl, e$real)
  cat(sprintf("%-6s %6.1f%% | %5.1f%% (%+4.1f) %5.1f%% (%+4.1f) %5.1f%% (%+4.1f) g=%.2f\n",
              e$yr, 100*e$real, 100*naive, 100*(naive-e$real), 100*pf, 100*(pf-e$real), 100*pl, 100*(pl-e$real), g_hat))
}

mae <- function(r) round(mean(abs(r))*100, 2)
cat(sprintf("\nMAE (pp):   naive=%.2f   prior_fixed=%.2f\n", mae(res_naive), mae(res_fixed)))
cat(sprintf("Aciertos direccionales /6:   naive=%d   prior_fixed=%d   prior_LOOfit=%d\n", hit_naive, hit_fixed, hit_loo))

# --- forecastShock honesto: RMS de residuos logit del prior_fixed (N=6) + versión LOO ---
shock_n6 <- sqrt(mean((sapply(E, function(e) logit(predict_share(e, rates_apriori))) - sapply(E, function(e) logit(e$real)))^2))
loo_shocks <- sapply(seq_along(E), function(i) {
  others <- E[-i]
  sqrt(mean((sapply(others, function(o) logit(predict_share(o, rates_apriori))) - sapply(others, function(o) logit(o$real)))^2))
})
cat(sprintf("\nforecastShock (logit): N=6=%.3f   (R/09 con N=3 daba 0.090)\n", shock_n6))
cat(sprintf("forecastShock LOO promedio=%.3f  (rango %.3f-%.3f)\n", mean(loo_shocks), min(loo_shocks), max(loo_shocks)))

# --- 2026: prior + banda honesta con el shock N=6 ---
p26 <- predict_share(E2026, rates_apriori)
Z80 <- qnorm(0.9)
lo <- invlogit(logit(p26) - Z80 * shock_n6); hi <- invlogit(logit(p26) + Z80 * shock_n6)
cat(sprintf("\n== 2026 (Abelardo vs Cepeda), prior por transferencia ==\n"))
cat(sprintf("  share Abelardo = %.1f%%   banda 80%% honesta [%.1f - %.1f]   cruza 50: %s\n",
            100*p26, 100*lo, 100*hi, ifelse(lo < 0.5, "SÍ", "NO")))
cat("\n11_transfer_backtest_n6 — OK.\n")
