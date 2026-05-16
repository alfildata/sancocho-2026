# Funciones compartidas: lectura y normalización de datos, prior estructural
# y ejecución del modelo Stan. Sin estado global — todo entra y sale por
# argumentos.

suppressWarnings(suppressMessages({
  library(readr)
  library(dplyr)
}))

# --- Normalización de texto -------------------------------------------------

# Normaliza el nombre de encuestadora: quita el espacio de ancho cero (U+200B),
# los marcadores de nota al pie ([c], [d], ...) y unifica mayúsculas, para que
# "AtlasIntel" / "Atlasintel" / "CNC[c]​" no se cuenten como encuestadoras
# distintas.
normalize_pollster <- function(x) {
  x <- as.character(x)
  x <- gsub("​", "", x)            # espacio de ancho cero
  x <- gsub("\\[[a-z]\\]", "", x)       # marcadores de nota al pie
  x <- toupper(trimws(x))
  x
}

# --- Decaimiento temporal ---------------------------------------------------

# Peso (0,1] de una encuesta según su antigüedad respecto al día de elección.
# Vida media `half_life`: a esa distancia el peso es 0.5.
decay_weight <- function(poll_date, election_date, half_life) {
  days_before <- as.numeric(election_date - poll_date)
  0.5 ^ (days_before / half_life)
}

# --- Colapso de una encuesta a K categorías ---------------------------------

# Convierte un vector de porcentajes crudos (5 candidatos + "otros" agregado)
# en conteos enteros para la verosimilitud Dirichlet-Multinomial.
#
# raw_pct : named numeric, longitud K, porcentajes (NA tratado como 0).
# sample  : tamaño de muestra de intención de voto de la encuesta.
#
# Devuelve list(counts = int[K], n_eff = int, prop = num[K]).
# n_eff = respondentes que cayeron en alguna de las K categorías
#         (= sample * suma_de_porcentajes / 100). Los indecisos (ns/nr)
#         quedan fuera por construcción: no se reparten ni se imputan.
collapse_to_counts <- function(raw_pct, sample) {
  raw_pct[is.na(raw_pct)] <- 0
  sum6 <- sum(raw_pct)
  if (sum6 <= 0) stop("Encuesta con suma de porcentajes <= 0")
  prop <- raw_pct / sum6
  n_eff <- max(1L, round(sample * sum6 / 100))
  counts <- round(prop * n_eff)
  # Ajuste de redondeo: la suma de conteos debe igualar n_eff exacto.
  drift <- n_eff - sum(counts)
  if (drift != 0) {
    idx <- which.max(counts)              # absorbe el ajuste en la categoría mayor
    counts[idx] <- counts[idx] + drift
  }
  counts[counts < 0] <- 0
  list(counts = as.integer(counts), n_eff = as.integer(sum(counts)), prop = prop)
}

# --- Encuestas 2026 ---------------------------------------------------------

# Columnas de candidatos menores que se agregan a "otros" (todo lo que no es
# uno de los 5 puntuados). El voto en blanco va en "otros": cuenta como voto
# válido en el denominador del concurso pero no es un candidato puntuado.
MINOR_2026 <- c(
  "daniel_quintero", "roy_barreras", "juan_manuel_galan", "vicky_davila",
  "santiago_botero", "miguel_uribe_londono", "david_luna", "juan_carlos_pinzon",
  "juan_daniel_oviedo", "carlos_caicedo", "luis_gilberto_murillo",
  "enrique_penalosa", "clara_lopez", "otros", "blanco"
)

prep_encuestas_2026 <- function(cfg) {
  df <- read_csv(file.path(cfg$paths$raw, "encuestas2026.csv"),
                 show_col_types = FALSE)

  df <- df %>% filter(!(n %in% cfg$exclude_polls_2026))

  out <- lapply(seq_len(nrow(df)), function(i) {
    row <- df[i, ]
    raw6 <- c(
      cepeda    = row$ivan_cepeda,
      espriella = row$abelardo_de_la_espriella,
      valencia  = row$paloma_valencia,
      fajardo   = row$sergio_fajardo,
      lopez     = row$claudia_lopez,
      otros     = sum(as.numeric(row[MINOR_2026]), na.rm = TRUE)
    )
    sample <- if (!is.na(row$muestra_int_voto)) row$muestra_int_voto else row$muestra
    cc <- collapse_to_counts(raw6, sample)
    data.frame(
      n          = row$n,
      encuestadora = row$encuestadora,
      fecha      = as.Date(row$fecha),
      n_eff      = cc$n_eff,
      cepeda = cc$counts[1], espriella = cc$counts[2], valencia = cc$counts[3],
      fajardo = cc$counts[4], lopez = cc$counts[5], otros = cc$counts[6]
    )
  })
  bind_rows(out)
}

# --- Encuestas históricas (backtest) ----------------------------------------

# Configuración por año: archivo, columnas de los 5 candidatos puntuados,
# columnas que se agregan a "otros", y filtro de primera vuelta.
HIST_SPEC <- list(
  "2014" = list(
    file = "encuestas2014.csv",
    date_col = "fecha", sample_col = "muestra",
    scored = c(santos = "santos", zuluaga = "zuluaga", penalosa = "penalosa",
               lopez = "lopez", ramirez = "ramirez"),
    minor = c("avella", "blanco"),
    pollster_col = "encuestadora"
  ),
  "2018" = list(
    file = "encuestas2018.csv",
    date_col = "fecha", sample_col = "muestra",
    scored = c(duque = "ivan_duque", petro = "gustavo_petro",
               fajardo = "sergio_fajardo", vargas = "german_vargas_lleras",
               delacalle = "humberto_delacalle"),
    minor = c("alejandro_ordonez", "juan_carlos_pinzon", "marta_lucia_ramirez",
              "piedad_cordoba", "rodrigo_londono", "carlos_caicedo",
              "otros", "blanco"),
    pollster_col = "encuestadora"
  ),
  "2022" = list(
    file = "encuestas2022.csv",
    date_col = "fecha", sample_col = "tamano_de_muestra",
    scored = c(petro = "gustavo_petro", hernandez = "rodolfo_hernandez",
               gutierrez = "federico_gutierrez", fajardo = "sergio_fajardo",
               betancourt = "ingrid_betancourt"),
    minor = c("enrique_gomez", "blanco"),
    pollster_col = "encuesta"
  )
)

# Prepara las encuestas de un año histórico. Filtra filas de segunda vuelta
# con una regla robusta (no por posición de fila): se descarta toda encuesta
# (a) posterior al día de elección o (b) que mide <3 de los 5 candidatos
# puntuados — las de 2da vuelta solo miden el head-to-head.
prep_encuestas_hist <- function(year, cfg, min_scored_nonNA = 3L) {
  spec <- HIST_SPEC[[year]]
  elec <- cfg$election_date[[year]]
  df <- read_csv(file.path(cfg$paths$raw, spec$file), show_col_types = FALSE)

  # 2014 trae columna `vuelta` explícita; los demás no.
  if (year == "2014" && "vuelta" %in% names(df)) {
    df <- df[df$vuelta == 1, ]
  }

  df$.fecha <- as.Date(df[[spec$date_col]])
  df <- df[!is.na(df$.fecha) & df$.fecha < elec, ]      # cutoff: antes de la elección

  scored_cols <- unname(spec$scored)
  n_nonNA <- rowSums(!is.na(df[, scored_cols, drop = FALSE]))
  df <- df[n_nonNA >= min_scored_nonNA, ]               # descarta head-to-heads de 2da vuelta

  out <- lapply(seq_len(nrow(df)), function(i) {
    row <- df[i, ]
    scored_vals <- as.numeric(row[scored_cols])
    minor_vals  <- suppressWarnings(as.numeric(row[spec$minor]))
    raw6 <- c(scored_vals, sum(minor_vals, na.rm = TRUE))
    names(raw6) <- c(names(spec$scored), "otros")
    sample <- as.numeric(row[[spec$sample_col]])
    if (is.na(sample) || sample <= 0) sample <- 1000   # fallback conservador
    cc <- collapse_to_counts(raw6, sample)
    res <- data.frame(
      encuestadora = normalize_pollster(row[[spec$pollster_col]]),
      fecha = row$.fecha,
      n_eff = cc$n_eff
    )
    for (k in seq_along(raw6)) res[[names(raw6)[k]]] <- cc$counts[k]
    res
  })
  bind_rows(out)
}

# --- Construcción del stan_data ---------------------------------------------

# Arma la lista que consume el modelo Stan a partir de un data.frame de
# encuestas ya colapsado.
#
# polls          : data.frame con `encuestadora`, `fecha`, `n_eff` y K columnas
#                  de conteos (en `cat_cols`, la última es la referencia).
# cat_cols       : nombres de las K columnas de categorías, en orden.
# election_date  : Date.
# prior_logit    : vector K, prior estructural log-ratio (NULL si V1).
# prior_sd       : vector K-1 de desvíos del prior (NULL si V1).
# half_life      : vida media del decaimiento (días).
build_stan_data <- function(polls, cat_cols, election_date,
                             prior_logit = NULL, prior_sd = NULL,
                             half_life = 25) {
  K <- length(cat_cols)
  y <- as.matrix(polls[, cat_cols])
  storage.mode(y) <- "integer"

  pollster_f <- factor(polls$encuestadora)
  w <- decay_weight(polls$fecha, election_date, half_life)

  use_prior <- as.integer(!is.null(prior_logit))
  if (use_prior == 1) {
    stopifnot(length(prior_logit) == K, length(prior_sd) == K - 1)
    pl <- prior_logit
    psd <- c(prior_sd, 1.0)               # la referencia no se usa; relleno
  } else {
    pl  <- rep(0, K)
    psd <- rep(1, K)
  }

  # `data` contiene SOLO lo que el bloque data{} de Stan declara.
  # Los metadatos (niveles de encuestadora) viajan aparte.
  data <- list(
    K = K, N = nrow(polls), J = nlevels(pollster_f),
    y = y,
    pollster = as.integer(pollster_f),
    decay_weight = as.numeric(w),
    use_prior = use_prior,
    prior_logit = as.numeric(pl),
    prior_sd = as.numeric(psd)
  )
  list(
    data = data,
    pollster_levels = levels(pollster_f),
    cat_cols = cat_cols
  )
}

# Rollup nacional de la transferencia partido-por-partido. Lee el CSV de
# transferencia y reparte el voto del Senado 2026 de cada partido entre los
# candidatos según los splits del CSV. Devuelve proporciones (suma 1) en el
# orden de `candidates`.
structural_prior_rollup <- function(cfg, candidates) {
  transfer <- read_csv(file.path(cfg$paths$raw, "party_level_transfer.csv"),
                       show_col_types = FALSE)
  votos <- transfer$senado_2026_votos
  colSums(votos * as.matrix(transfer[, candidates]) / 100) / sum(votos)
}

# Calcula el prior estructural en escala log-ratio a partir de un vector de
# proporciones (suma 1). La última categoría es la referencia.
#
# Guard numérico (2026-05-20): las decisiones políticas del equipo pueden
# producir ceros en el rollup (en particular `otros = 0` cuando ningún split
# por partido asigna voto a candidatos menores + blanco). `log(0)` rompe.
# Reemplazamos los 0s por un epsilon ínfimo (1e-6) SOLO al construir los
# log-ratios — el CSV y el `rollup_prop` permanecen intactos. El modelo Stan
# solo usa diferencias `prior_logit[k] - prior_logit[1]` (= `log(p_k/p_cep)`)
# entre candidatos puntuados, donde el epsilon de "otros" se cancela. Para
# candidatos puntuados con rollup > 0 (todos los 5 en este forecast) el guard
# no toca su valor.
structural_prior_logit <- function(prop) {
  prop[prop == 0] <- 1e-6
  log(prop / prop[length(prop)])
}

# --- Ejecución del modelo Stan ----------------------------------------------

# Si la variable de entorno CMDSTAN apunta a una instalación válida, la usa
# como ruta de CmdStan; si no, deja la ruta que cmdstanr tenga configurada.
ensure_cmdstan_path <- function() {
  cmdstan_env <- Sys.getenv("CMDSTAN")
  if (nzchar(cmdstan_env) && dir.exists(cmdstan_env)) set_cmdstan_path(cmdstan_env)
}

# Ajusta el modelo Stan compilado `mod` sobre `stan_data` con los parámetros
# de muestreo de `cfg`. `refresh` controla solo la verbosidad de consola
# (cada cuántas iteraciones se imprime progreso); no afecta el resultado.
sample_model <- function(mod, stan_data, cfg, refresh = 0) {
  mod$sample(
    data            = stan_data,
    seed            = cfg$seed,
    chains          = cfg$chains,
    parallel_chains = cfg$parallel_chains,
    iter_warmup     = cfg$iter_warmup,
    iter_sampling   = cfg$iter_sampling,
    adapt_delta     = cfg$adapt_delta,
    max_treedepth   = cfg$max_treedepth,
    refresh         = refresh
  )
}
