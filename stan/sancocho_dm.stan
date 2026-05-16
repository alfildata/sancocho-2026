// Sancocho — modelo bayesiano jerárquico Dirichlet-Multinomial
// Recetas Electorales 2026 · primera vuelta presidencial Colombia
//
// Estima el reparto de votos válidos sobre K categorías
// (candidatos puntuados + "otros"). Cada encuesta es una observación
// Dirichlet-Multinomial sobre una intención latente común; cada encuestadora
// tiene un sesgo propio (house effect) y las encuestas viejas pesan menos
// (decaimiento temporal exponencial sobre la verosimilitud).
//
// El prior estructural (transferencia partido-por-partido del Senado 2026
// + bancadas) entra como prior sobre el intercepto de día de elección.
//
// Tratamiento del tiempo: house effects + decaimiento temporal. El
// decaimiento ES el modelo temporal — no hay término de tendencia lineal.
// Una tendencia lineal extrapolaría la subida ene-abr de
// una carrera ya estabilizada (las encuestas de fines de abril están planas);
// el decaimiento, en cambio, estima el nivel reciente sin extrapolar.
//
// Identificación:
//   - El candidato K es la categoría de referencia (alpha[K] = 0).
//   - Los house effects se centran EXACTAMENTE (suma cero por candidato, por
//     construcción) -> alpha es el intercepto de la "encuestadora promedio".

data {
  int<lower=2> K;                       // categorías = candidatos puntuados + otros
  int<lower=1> N;                       // número de encuestas
  int<lower=1> J;                       // número de encuestadoras
  array[N, K] int<lower=0> y;           // conteos por categoría (muestra colapsada a K)
  array[N] int<lower=1, upper=J> pollster;
  vector<lower=0>[N] decay_weight;      // por encuesta, en (0,1]

  int<lower=0, upper=1> use_prior;      // 1 = usar prior estructural (V2/V3); 0 = solo encuestas (V1)
  vector[K] prior_logit;                // prior estructural en log-ratio vs "otros"; prior_logit[K] = 0
  vector<lower=0>[K] prior_sd;          // desvío del prior por candidato (ancho para Espriella)
}

transformed data {
  // El prior estructural se aplica sobre los log-ratios ENTRE candidatos
  // puntuados (referencia = candidato 1), NO sobre el nivel de "otros".
  // Motivo: la transferencia partido-por-partido informa el ORDEN relativo
  // de los 5 candidatos, pero no tiene nada confiable que decir sobre el
  // voto a candidatos menores + blanco ("otros"). Ese nivel lo fijan las
  // encuestas. Anclar "otros" desde el prior arrastraría a todos los
  // candidatos sin sustento.
  vector[K] prior_reldiff;              // log(prior_p[k] / prior_p[1])
  for (k in 1:K) prior_reldiff[k] = prior_logit[k] - prior_logit[1];
}

parameters {
  vector[K - 1] alpha_free;             // intercepto día-elección (referencia K fijada en 0)
  real log_kappa;                       // log de la concentración Dirichlet-Multinomial
  vector<lower=0>[K] sigma_house;       // desvío de los house effects por candidato
  matrix[K, J] z_house;                 // auxiliares estándar-normales (parametrización no centrada)
}

transformed parameters {
  vector[K] alpha = append_row(alpha_free, 0);
  real<lower=0> kappa = exp(log_kappa);
  matrix[K, J] delta;                   // house effects: delta[k, j], suma cero por fila
  for (k in 1:K) {
    row_vector[J] zc = z_house[k] - mean(z_house[k]);   // centrado exacto -> suma cero
    delta[k] = sigma_house[k] * zc;
  }
}

model {
  // --- Priors ---
  log_kappa   ~ normal(log(150), 1.2);  // prior débilmente informativo: los datos
                                        // estiman kappa (≈52 con 16 encuestas 2026 —
                                        // mucha sobredispersión entre encuestadoras)
  sigma_house ~ exponential(2);         // SD de house effects ~0.5 en escala log-odds
  to_vector(z_house) ~ std_normal();

  // Prior estructural: informa el orden relativo de los candidatos puntuados.
  // El nivel del candidato 1 vs "otros" lo fijan las encuestas (prior débil).
  if (use_prior == 1) {
    alpha_free[1] ~ normal(0, 3);                   // nivel candidato 1 vs otros: data-driven
    for (k in 2:(K - 1)) {
      target += normal_lpdf(alpha_free[k] - alpha_free[1]
                            | prior_reldiff[k], prior_sd[k]);
    }
  } else {
    alpha_free ~ normal(0, 3);          // V1: prior débil, manda la verosimilitud
  }

  // --- Verosimilitud ---
  for (n in 1:N) {
    vector[K] log_p = alpha + delta[, pollster[n]];
    log_p -= mean(log_p);               // higiene numérica antes del softmax
    vector[K] p = softmax(log_p);
    // Decaimiento temporal: las encuestas viejas pesan menos (tempering de la verosimilitud)
    target += decay_weight[n] * dirichlet_multinomial_lpmf(y[n] | kappa * p);
  }
}

generated quantities {
  vector[K] p_elec;                     // reparto de votos válidos el día de la elección
  array[N, K] int y_rep;                // réplicas para posterior predictive checks

  {
    vector[K] log_p = alpha;            // delta = 0 (encuestadora promedio)
    log_p -= mean(log_p);
    p_elec = softmax(log_p);
  }
  for (n in 1:N) {
    vector[K] log_p = alpha + delta[, pollster[n]];
    log_p -= mean(log_p);
    y_rep[n] = dirichlet_multinomial_rng(kappa * softmax(log_p), sum(y[n]));
  }
}
