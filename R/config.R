# Configuración central del modelo Sancocho.
# Todo parámetro ajustable vive acá — ningún número mágico disperso por los scripts.

CFG <- list(

  # --- Reproducibilidad ---
  seed = 20260531L,                       # fecha de la elección como semilla

  # --- Fechas de elección (primera vuelta) ---
  election_date = list(
    "2014" = as.Date("2014-05-25"),
    "2018" = as.Date("2018-05-27"),
    "2022" = as.Date("2022-05-29"),
    "2026" = as.Date("2026-05-31")
  ),

  # --- Candidatos puntuados 2026 (orden fijo; "otros" es la referencia) ---
  candidates_2026 = c("cepeda", "espriella", "valencia", "fajardo", "lopez", "otros"),

  # --- Muestreo MCMC ---
  chains          = 4L,
  parallel_chains = 4L,
  iter_warmup     = 1500L,
  iter_sampling   = 2000L,
  adapt_delta     = 0.99,
  max_treedepth   = 12L,

  # --- Decaimiento temporal de las encuestas ---
  # Peso = 0.5 ^ (días_antes_de_elección / half_life_days).
  # half_life 25 días: una encuesta de hace 25 días pesa la mitad; una de hace
  # ~7 semanas (~50 días, 2 half-lives) pesa ~25% de una reciente.
  decay_half_life_days = 25,

  # --- Error de forecast (shock log-odds del día de elección) ---
  # Calibrado por 04_backtest.R = RMS de los residuos (escala logit) del
  # backtest 2014/2018/2022. Captura el error sistemático encuesta-vs-resultado
  # (sorpresas de última semana). NO garantiza cobertura 80%: con esos residuos
  # los intervalos al 80% cubren ~67% empíricamente — las sorpresas de última
  # semana son de cola pesada y el modelo queda algo sobreconfiado en las colas.
  # FRÁGIL: hardcodeado acá. Si cambian datos o modelo del backtest, recomputar
  # = RMS de los residuos logit (ver 04_backtest.R y backtest-summary.md).
  # Valor 2026-05-21: prior de kappa ensanchado -> backtest recalibró a 0.315.
  fcast_logit_sd = 0.315,

  # --- Prior estructural: desvío por candidato (escala log-ratio vs "otros") ---
  # Ancho para Espriella a propósito: su voto anti-sistema es más volátil que
  # el de los candidatos tradicionales. El SD ancho deja que las encuestas
  # manden sobre su nivel sin que el prior pelee. NO inflamos la MEDIA del
  # prior — ensanchamos su varianza.
  prior_sd_2026 = c(
    cepeda    = 0.35,
    espriella = 0.90,
    valencia  = 0.35,
    fajardo   = 0.50,
    lopez     = 0.50
  ),

  # --- Encuestas 2026 a excluir (ver docs/methodology.md §6.1) ---
  # Exclusiones PERMANENTES — problemas metodológicos, no negociables:
  #   n=1  Cifras y Conceptos: metodología "lotes" (bloques ideológicos).
  #   n=4  W.A.A: autofinanciada, cuestionada; no midió Valencia ni López.
  #   n=5  Datexco: no probabilístico; no midió Fajardo ni López.
  #   n=11 YanHaas: midió solo la Gran Consulta, no primera vuelta.
  exclude_polls_base = c(1L, 4L, 5L, 11L),

  # AtlasIntel — 7 oleadas (n=6, 10, 15, 17, 21, 25, 27). La firma usa
  # "Random Digital Recruitment" (RDR), una metodología online no
  # probabilística. El CNE dictó cautelar (CNE-E-DG-2026-014724, 19-may-2026,
  # magistrada Márquez) por presunto incumplimiento de la Ley 2494/2025; la
  # cautelar quedó sin firmeza por el recurso de reposición de Semana, pero
  # la objeción técnica sobre RDR sigue pendiente de fondo. Decisión del
  # equipo (2026-05-23): EXCLUIR del forecast oficial por consistencia con el
  # criterio metodológico aplicado a otras firmas no probabilísticas
  # (Datexco, W.A.A). La corrida CON AtlasIntel se reporta como sensibilidad
  # vía R/06_sensitivity_atlasintel.R.
  atlasintel_polls = c(6L, 10L, 15L, 17L, 21L, 25L, 27L),

  # Flag de inclusión de AtlasIntel. FALSE por defecto: el forecast de
  # submission NO usa datos AtlasIntel. La corrida CON AtlasIntel se reporta
  # como sensibilidad vía R/06_sensitivity_atlasintel.R. Override por entorno:
  # INCLUDE_ATLASINTEL=1 fuerza la inclusión sin editar este archivo.
  include_atlasintel = FALSE,

  # --- Prior estructural del backtest V2 (Senado histórico) -------------------
  # Cada candidato hereda la cuota de votos válidos de su lista/coalición al
  # Senado del mismo año. Fuente: DB Alfil (electoral.vote_records, Senado,
  # escrutinio oficial Registraduría). Denominador = votos de listas + blanco
  # (excluye nulos y tarjetas no marcadas), igual que el concurso.
  #
  # Caveat documentado en backtest-summary.md: un prior basado en el Senado NO
  # puede "ver" a un candidato anti-sistema sin lista propia — Hernández 2022,
  # Betancourt 2022, y en buena parte Petro 2018. En esos casos el gap lo
  # cierran las encuestas.
  senado_prior_backtest = list(
    "2014" = c(santos = 0.1862, zuluaga = 0.1735, ramirez = 0.1620,
               penalosa = 0.0465, lopez = 0.0444, otros = 0.3874),
    "2018" = c(duque = 0.1586, petro = 0.0329, fajardo = 0.0931,
               vargas = 0.1358, delacalle = 0.1211, otros = 0.4585),
    "2022" = c(petro = 0.1666, hernandez = 0.0100, gutierrez = 0.2527,
               fajardo = 0.1133, betancourt = 0.0050, otros = 0.4524)
  ),

  # Desvío del prior V2 del backtest (escala log-ratio). Ancho en general —
  # el prior es un ancla suave; con 20-40 encuestas mandan las encuestas.
  # Extra ancho para candidatos sin lista al Senado (no se les puede anclar).
  prior_sd_backtest = list(
    "2014" = c(santos = 0.6, zuluaga = 0.6, ramirez = 0.6,
               penalosa = 0.7, lopez = 0.7),
    "2018" = c(duque = 0.6, petro = 1.2, fajardo = 0.7,
               vargas = 0.7, delacalle = 0.9),
    "2022" = c(petro = 0.6, hernandez = 1.3, gutierrez = 0.7,
               fajardo = 0.7, betancourt = 1.0)
  ),

  # --- Ground truth histórico (% de votos válidos, primera vuelta) ------------
  # Resultados oficiales Registraduría, verificados voto-a-voto contra dos
  # fuentes independientes (Wikipedia/Registraduría + DB Alfil).
  ground_truth = list(
    "2014" = c(santos = 0.2572, zuluaga = 0.2928, penalosa = 0.0827,
               lopez = 0.1522, ramirez = 0.1552),
    "2018" = c(duque = 0.3936, petro = 0.2509, fajardo = 0.2378,
               vargas = 0.0730, delacalle = 0.0205),
    "2022" = c(petro = 0.4034, hernandez = 0.2817, gutierrez = 0.2394,
               fajardo = 0.0418, betancourt = 0.0007)
  ),

  paths = list(
    raw       = "data/raw",
    processed = "data/processed",
    stan      = "stan/sancocho_dm.stan",
    output    = "output"
  )
)

# --- Exclusión efectiva de encuestas 2026 (derivada del flag) ---------------
# El resto del código consume `CFG$exclude_polls_2026`. Se deriva de:
#   exclude_polls_base  — exclusiones permanentes (metodología)
#   atlasintel_polls    — las 7 oleadas de AtlasIntel
#   include_atlasintel  — flag (FALSE por defecto → submission sin AtlasIntel)
# Override por entorno: INCLUDE_ATLASINTEL=1 fuerza la inclusión sin editar
# este archivo (lo usa R/06_sensitivity_atlasintel.R para la corrida CON).
if (identical(Sys.getenv("INCLUDE_ATLASINTEL"), "1")) {
  CFG$include_atlasintel <- TRUE
}
CFG$exclude_polls_2026 <- if (CFG$include_atlasintel) {
  sort(CFG$exclude_polls_base)
} else {
  sort(c(CFG$exclude_polls_base, CFG$atlasintel_polls))
}

# --- Etiquetas de presentación de los candidatos 2026 -----------------------
# Nombres legibles para tablas, figuras y mensajes de consola.
CAND_LABEL <- c(
  cepeda    = "Iván Cepeda",
  espriella = "Abelardo de la Espriella",
  valencia  = "Paloma Valencia",
  fajardo   = "Sergio Fajardo",
  lopez     = "Claudia López",
  otros     = "Otros + voto en blanco"
)
