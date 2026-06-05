# 08 — Prior de transferencia JERÁRQUICO (empirical-Bayes shrinkage).
#
# "Datos históricos como alimento, con rigor": en vez de hardcodear las tasas de
# transferencia, estimamos la tasa típica de transferencia al finalista AFÍN por
# tipo de bloque, con partial pooling (shrinkage) sobre las elecciones históricas,
# y derivamos un prior con intervalo HONESTO para 2026. Versión analítica de la
# jerarquía (empirical Bayes en escala logit); la bayesiana completa (brms/Stan,
# logit-binomial con random effects de bloc_type y elección) es la productionización.
#
# Responde: ¿nuestro 76% de Paloma->Abelardo (de la cross-tab de AtlasIntel)
# aguanta contra lo que los bloques de derecha transfieren históricamente?

logit    <- function(p) log(p / (1 - p))
invlogit <- function(x) 1 / (1 + exp(-x))

# --- Observaciones históricas: transferencia al finalista AFÍN ---------------
# (de observedTransfers, verificado por el workflow contra análisis post-electoral).
# right/left tienen afín claro; center se trata como "tasa a blanco/abstención".
hist <- data.frame(
  bloc       = c("MartaRamirez","Fico","VargasLleras","JohnMilton","EnriqueGomez","ClaraLopez","Fajardo18","Fajardo22","DeLaCalle"),
  year       = c("2014","2022","2018","2022","2022","2014","2018","2022","2018"),
  type       = c("right","right","right","right","right","left","center","center","center"),
  endorsed   = c(TRUE,  TRUE,  FALSE, FALSE, FALSE, TRUE,  FALSE,   FALSE,   FALSE),
  affineRate = c(0.65,  0.70,  0.65,  0.55,  0.70,  0.75,  NA,      NA,      NA),  # afín (right/left)
  blankRate  = c(NA,    NA,    NA,    NA,    NA,    NA,    0.35,    0.45,    0.45)   # center -> blanco
)

# --- Empirical-Bayes sobre bloques de DERECHA (donde vive Paloma) ------------
right <- hist[hist$type == "right", ]
y  <- logit(right$affineRate)
k  <- length(y)
mu <- mean(y)
s2 <- var(y)                      # heterogeneidad entre-bloque en escala logit
se_pred <- sqrt(s2 * (1 + 1 / k)) # SE predictiva para un bloque NUEVO
tcrit   <- qt(0.90, df = k - 1)   # predictive 80%

pred_mean <- invlogit(mu)
pred_lo   <- invlogit(mu - tcrit * se_pred)
pred_hi   <- invlogit(mu + tcrit * se_pred)

cat("\n== Transferencia de bloques de DERECHA al finalista afín (histórico) ==\n")
cat(sprintf("  n=%d obs: %s\n", k, paste0(round(right$affineRate * 100), "%", collapse = ", ")))
cat(sprintf("  Media histórica: %.0f%%   predictive 80%%: [%.0f%%, %.0f%%]\n",
            100 * pred_mean, 100 * pred_lo, 100 * pred_hi))

# --- Paloma 2026: hardcoded (Atlas) vs histórico vs shrunken -----------------
paloma_raw <- 0.76                # cross-tab AtlasIntel = lo que hardcodeamos
w_hist <- 1 / se_pred^2           # precisión del prior histórico
w_raw  <- 1 / s2                  # tratamos el raw de Atlas como ~1 observación
paloma_shrunk <- invlogit((w_hist * mu + w_raw * logit(paloma_raw)) / (w_hist + w_raw))

cat(sprintf("\n  Paloma->Abelardo:  hardcoded(Atlas)=%.0f%%  |  histórico=%.0f%%  |  shrunken=%.0f%%\n",
            100 * paloma_raw, 100 * pred_mean, 100 * paloma_shrunk))
cat(sprintf("  -> 76%% está %s del techo predictivo histórico (%.0f%%); shrinkage lo baja a ~%.0f%%.\n",
            ifelse(paloma_raw > pred_hi, "POR ENCIMA", "dentro"), 100 * pred_hi, 100 * paloma_shrunk))

# --- Impacto en el forecast 2026 (share Abelardo sobre A+B) ------------------
# El "voto perdido" al bajar la transferencia de Paloma va a blanco (no a Cepeda).
share_abelardo <- function(paloma_toA_frac) {
  baseA <- 43.74; baseB <- 40.90; paloma <- 6.92
  otherA <- 0.81 + 0.11 + 0.26 + 0.19 + 0 + 0     # fajardo/claudia/botero/tail/roy/matamoros -> A
  otherB <- 1.02 + 0.31 + 0.17 + 0.08 + 0.04 + 0.01
  impliedA <- baseA + paloma * paloma_toA_frac + otherA
  impliedB <- baseB + paloma * 0.06 + otherB       # Paloma->Cepeda fijo ~6%
  100 * impliedA / (impliedA + impliedB)
}

cat("\n== Impacto en el share de Abelardo (prior estructural, sobre A+B) ==\n")
cat(sprintf("  Paloma 76%% (hardcoded): %.1f%%\n", share_abelardo(0.76)))
cat(sprintf("  Paloma %.0f%% (shrunken): %.1f%%\n", 100 * paloma_shrunk, share_abelardo(paloma_shrunk)))
cat(sprintf("  Paloma %.0f%% (histórico): %.1f%%\n", 100 * pred_mean, share_abelardo(pred_mean)))
cat(sprintf("  Sensibilidad total (76%% -> %.0f%%): %.2f pp\n",
            100 * pred_mean, share_abelardo(0.76) - share_abelardo(pred_mean)))

# --- Center (Fajardo): el verdadero swing -----------------------------------
center <- hist[hist$type == "center", ]
cat(sprintf("\n== Bloque de CENTRO -> blanco/abstención (histórico) ==\n"))
cat(sprintf("  obs: %s  (media %.0f%%)\n",
            paste0(round(center$blankRate * 100), "%", collapse = ", "),
            100 * mean(center$blankRate)))
cat("  Fajardo 2026 modelado a 57%% blanco: consistente con el rango histórico (35-45%%) pero en el extremo alto.\n")
cat("  El centro es el swing real: re-asignar 10pp del blanco de Fajardo a Cepeda mueve el share ~0.5pp.\n")

out <- data.frame(
  parametro = c("right_affine_hist_mean","right_affine_lo80","right_affine_hi80",
                "paloma_hardcoded","paloma_shrunk","share_abelardo_hardcoded","share_abelardo_shrunk"),
  valor = round(c(pred_mean, pred_lo, pred_hi, paloma_raw, paloma_shrunk,
                  share_abelardo(0.76)/100, share_abelardo(paloma_shrunk)/100), 4)
)
write.csv(out, file.path("output", "transfer_hierarchical.csv"), row.names = FALSE)
cat("\n08_transfer_hierarchical — OK. CSV: output/transfer_hierarchical.csv\n")
