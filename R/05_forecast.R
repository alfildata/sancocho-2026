# 05 — Forecast final 2026: tabla de submission + figura.
#
# El concurso puntúa con MSE. El estimador puntual que minimiza el error
# cuadrático esperado es la MEDIA del posterior — esa es la cifra que se
# envía. La mediana y los intervalos 50/80/95 se reportan como contexto.

source("R/config.R")
source("R/extract.R")
suppressWarnings(suppressMessages({
  library(ggplot2)
  library(dplyr)
}))

# Color de acento para el intervalo de credibilidad central (50%).
COLOR_IC50 <- "#6366F1"

fit_v3 <- readRDS(file.path(CFG$paths$output, "posterior", "fit_2026_v3.rds"))
fit_v1 <- readRDS(file.path(CFG$paths$output, "posterior", "fit_2026_v1.rds"))
cats   <- CFG$candidates_2026

set.seed(CFG$seed)   # reproducibilidad del shock de error de forecast

# --- Tabla de forecast (V3 = Sancocho, el modelo de submission) -------------
# Intervalos ensanchados con el error de forecast calibrado en el backtest.

fc <- forecast_summary(fit_v3, cats, fcast_logit_sd = CFG$fcast_logit_sd)
fc$candidato <- CAND_LABEL[fc$categoria]

# Comparación V1 vs V3 sobre los 5 candidatos puntuados
v1 <- forecast_summary(fit_v1, cats, fcast_logit_sd = CFG$fcast_logit_sd)[, c("categoria", "media")]
names(v1)[2] <- "media_v1"
fc <- left_join(fc, v1, by = "categoria")

scored <- fc[fc$categoria != "otros", ]

message("\n========== FORECAST 2026 — primera vuelta presidencial ==========")
message("Proporción de votos válidos · modelo Sancocho (V3)\n")
for (i in seq_len(nrow(scored))) {
  r <- scored[i, ]
  message(sprintf("  %-26s %.1f%%   [80%%: %.1f–%.1f]   (V1 solo encuestas: %.1f%%)",
                  r$candidato, r$media * 100, r$lo80 * 100, r$hi80 * 100,
                  r$media_v1 * 100))
}
message(sprintf("\n  %-26s %.1f%%", CAND_LABEL["otros"],
                fc$media[fc$categoria == "otros"] * 100))

# --- CSV de submission ------------------------------------------------------

submission <- data.frame(
  candidato            = CAND_LABEL[scored$categoria],
  proporcion_votos_validos = round(scored$media, 4),     # cifra enviada (media)
  mediana              = round(scored$mediana, 4),
  ic80_lo              = round(scored$lo80, 4),
  ic80_hi              = round(scored$hi80, 4),
  ic95_lo              = round(scored$lo95, 4),
  ic95_hi              = round(scored$hi95, 4)
)
write.csv(submission, file.path(CFG$paths$output, "forecast_2026.csv"),
          row.names = FALSE)
message("\nCSV de submission: ", file.path(CFG$paths$output, "forecast_2026.csv"))

# --- Figura: forecast con intervalos ----------------------------------------

plot_df <- scored
plot_df$candidato <- factor(plot_df$candidato,
                            levels = plot_df$candidato[order(plot_df$media)])

p <- ggplot(plot_df, aes(x = media, y = candidato)) +
  geom_linerange(aes(xmin = lo95, xmax = hi95), linewidth = 1, colour = "grey70") +
  geom_linerange(aes(xmin = lo80, xmax = hi80), linewidth = 2.4, colour = "grey45") +
  geom_linerange(aes(xmin = lo50, xmax = hi50), linewidth = 4, colour = COLOR_IC50) +
  geom_point(size = 3, colour = "black") +
  scale_x_continuous(labels = function(x) paste0(round(x * 100), "%")) +
  labs(title = "Forecast Sancocho — primera vuelta presidencial 2026",
       subtitle = "Proporción de votos válidos · intervalos de credibilidad 50/80/95%",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 13)

ggsave(file.path(CFG$paths$output, "figures", "forecast_2026.png"), p,
       width = 9, height = 5, dpi = 120)

message("05_forecast — OK.")
