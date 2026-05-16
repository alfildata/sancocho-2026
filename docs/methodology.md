# Metodología — Modelo Sancocho

Pronóstico de la primera vuelta presidencial de Colombia (31 de mayo de 2026)
para el concurso Recetas Electorales. Este documento describe el modelo,
los datos, los supuestos y las limitaciones.

## 1. El estimando

El concurso puntúa la **proporción de votos válidos** de cinco candidatos:

> Proporción_i = Votos_i / (Votos totales − Votos nulos)

Votos válidos = votos a candidatos + voto en blanco. El modelo estima un
símplex de **K = 6 categorías**: los 5 candidatos puntuados (Cepeda, Espriella,
Valencia, Fajardo, López) + **"otros"** (los demás candidatos + voto en blanco).
Las 5 componentes puntuadas son directamente la proporción de votos válidos
pedida por el concurso. La métrica del concurso es el **error cuadrático medio
(MSE)** sobre los 5 candidatos.

## 2. Las tres fuentes

| Fuente | Rol en el modelo |
|---|---|
| **Encuestas** (19 mediciones, 4 firmas probabilísticas) | Verosimilitud — actualizan el prior. AtlasIntel excluida por metodología RDR no probabilística (ver §6) |
| **Senado 2026** (voto del 8 de marzo) | Materia prima del prior estructural |
| **Bancadas** (Análisis cualitativo + auditoría) | Dirección de la transferencia partido→candidato |

## 3. El prior estructural

El Senado 2026 fue un voto por **partidos**; la presidencial es por **personas**.
Para cada uno de los 17 partidos con representación en el Senado 2026
(`data/raw/party_level_transfer.csv`) se estima qué fracción de su voto se
transfiere a cada candidato presidencial.

Cada split se construyó **caso por caso**, a partir de un análisis cualitativo
del partido: el comportamiento y los respaldos de su bancada, las declaraciones
de prensa de sus dirigentes y precandidatos, los avales formales y el contexto
e historial político de la colectividad. Cada una de las 17 filas refleja una
lectura política específica, no una calibración automática. El modelo usa un
único split nacional por partido.

El *rollup* nacional de esas 17 transferencias es el prior estructural:

| Candidato | Prior estructural |
|---|---:|
| Cepeda | 45.01 % |
| Valencia | 28.22 % |
| Espriella | 24.39 % |
| Fajardo | 1.37 % |
| López | 1.01 % |
| Otros | 0.00 % |

**Cómo entra el prior.** El prior estructural se aplica sobre los **log-ratios
entre candidatos puntuados** (referencia = candidato 1, Cepeda), **no** sobre
el nivel absoluto de "otros". El prior informa el **orden relativo** entre
Cepeda, Espriella, Valencia, Fajardo y López; las encuestas fijan el **nivel**.

## 4. El modelo bayesiano

Modelo **bayesiano jerárquico Dirichlet-Multinomial** (`stan/sancocho_dm.stan`).

Cada encuesta *n* aporta un vector de conteos `y[n]` sobre las K categorías
(la muestra de intención de voto colapsada a 6 categorías; los indecisos
quedan fuera). La verosimilitud:

```
y[n] ~ DirichletMultinomial( kappa · softmax(alpha + delta[encuestadora]) )
```

- **alpha** — intercepto latente, el reparto de votos el día de elección.
  Sobre él va el prior estructural (§3).
- **delta** — *house effect* de cada encuestadora, parametrización no centrada,
  centrado exacto suma-cero por candidato → alpha es el intercepto de la
  "encuestadora promedio".
- **kappa** — concentración Dirichlet-Multinomial (sobredispersión encuesta a
  encuesta más allá del muestreo). Prior log-normal **débilmente informativo**
  (`normal(log 150, 1.2)`): los datos estiman kappa sin que el prior pelee.
  El posterior 2026 da kappa ≈ 80 (IC 90 % 46–133) — las 19 encuestas se
  dispersan más de lo que sus tamaños muestrales sugieren (house
  effects, metodologías, 6 meses de campaña). Por eso cada encuesta aporta
  ~80 observaciones efectivas, no su muestra nominal — esto hace al modelo
  robusto a la heterogeneidad en cómo las firmas reportan indecisos.

### 4.1 Decaimiento temporal

Las encuestas viejas pesan menos: la contribución de la encuesta *n* a la
verosimilitud se multiplica por `decay_weight[n] = 0.5 ^ (días_antes / 25)`.
Una encuesta de hace 7 semanas pesa ~13 % de una reciente.

**No hay término de tendencia lineal.** Una tendencia extrapolaría la subida
enero-abril de una carrera que ya se estabilizó (las encuestas de fines de
abril están planas). El decaimiento estima el nivel reciente sin extrapolar.

### 4.2 Error de forecast

El posterior del modelo solo captura la incertidumbre de **muestreo**. El
error real **encuesta-vs-resultado** es mayor: cambios de última semana (en
Colombia la ley prohíbe publicar encuestas los 7 días previos), efectos de
campaña, participación. El backtest mide ese error: RMS ≈ 5 pp por candidato.

Los intervalos reportados incorporan un **shock de error de forecast**
(`fcast_logit_sd = 0.315`, escala log-odds), calibrado por `04_backtest.R` vía
grid search para que el desvío predictivo total (posterior base ⊕ shock)
iguale el RMS de los residuos del backtest. Sin él, los intervalos serían
honestos solo respecto del muestreo y groseramente sobre-confiados.

**Caveat de cobertura.** El backtest tiene 15 puntos (3 elecciones × 5
candidatos); con tan pocos datos la calibración es de baja precisión. Las
variantes V1 cubren el 80 % nominal en 10/15 casos (~67 %) — dentro del ruido
de muestreo de 15 puntos, pero el modelo puede quedar algo sobreconfiado en
las colas (sorpresas de última semana, de cola pesada). Es una limitación de
datos, no un error corregible: solo más elecciones históricas la cerrarían.

## 5. Variantes

| Variante | Fuentes | Uso |
|---|---|---|
| **V1** | solo encuestas | línea base / sensibilidad |
| **V2** | encuestas + Senado | backtest histórico |
| **V3** | encuestas + Senado + bancadas | **forecast 2026 (submission)** |

## 6. Datos

### 6.1 Encuestas 2026

30 mediciones recolectadas (encuestas probabilísticas + sondeos no probabilísticos); **19 encuestas usadas** en el forecast de submission. Excluidos:

**Exclusiones permanentes (problemas metodológicos):**
- **n=1 Cifras y Conceptos** — metodología "lotes" (bloques ideológicos), no
  comparable con intención de voto estándar.
- **n=4 W.A.A** — autofinanciada y cuestionada por metodología; además no midió
  a Valencia ni a López.
- **n=5 Datexco** — muestreo no probabilístico (panel Pulso País); además no
  midió a Fajardo ni a López.
- **n=11 YanHaas** — midió solo la Gran Consulta, no la primera vuelta.

**AtlasIntel (n=6, 10, 15, 17, 21, 25, 27) — 7 oleadas:** la firma usa
"Random Digital Recruitment" (RDR), una metodología online no probabilística.
El CNE dictó cautelar (resolución CNE-E-DG-2026-014724, 2026-05-19) por
presunto incumplimiento de la Ley 2494/2025; la cautelar quedó SIN FIRMEZA
por el recurso de reposición de Semana, pero la objeción técnica sobre la
metodología RDR sigue pendiente de fondo. El forecast de submission la
**excluye** por consistencia con el criterio metodológico aplicado a otras
firmas con muestreo no probabilístico (Datexco, W.A.A). La corrida con
AtlasIntel se reporta como sensibilidad (§6.2).

### 6.2 Sensibilidad a AtlasIntel

La exclusión de AtlasIntel es la decisión más discutible del dataset, así que
se reporta de forma explícita. `R/config.R` tiene un flag `include_atlasintel`
(`FALSE` por defecto; override por entorno `INCLUDE_ATLASINTEL=1` para correr
la sensibilidad con AtlasIntel), y `R/06_sensitivity_atlasintel.R` corre el
modelo V3 las dos formas:

| Candidato | Sin AtlasIntel (oficial) | Con AtlasIntel | Δ |
|---|---:|---:|---:|
| Iván Cepeda | 40.9 % | 40.3 % | −0.6 pp |
| Abelardo de la Espriella | 26.8 % | 27.9 % | +1.1 pp |
| Paloma Valencia | 17.5 % | 17.8 % | +0.2 pp |
| Sergio Fajardo | 2.6 % | 3.0 % | +0.5 pp |
| Claudia López | 2.1 % | 1.7 % | −0.4 pp |

La narrativa de fondo no cambia con o sin AtlasIntel: Cepeda mantiene el
liderazgo claro. Salidas: `output/atlasintel_sensitivity.csv` (comparación
SIN vs CON) y `output/forecast_2026_con_atlasintel.csv` (la variante CON con
intervalos completos; no es el número de submission).

### 6.3 Backtest

Resultados oficiales Registraduría de 2014/2018/2022, verificados voto-a-voto.
Las encuestas históricas se filtran a primera vuelta (se descartan las filas de
segunda vuelta, no marcadas en los archivos 2018/2022).

## 7. Limitaciones

1. **Sorpresas de última semana.** El mayor error del backtest siempre es un
   candidato que sube en la última semana, cuando ya no hay encuestas legales:
   Zuluaga 2014 (+7 pp), Fajardo 2018 (+8.5 pp), Hernández 2022 (+10.6 pp).
   Ningún modelo basado en encuestas puede ver eso. Los intervalos lo reflejan;
   la estimación puntual no puede.
2. **La capa de bancadas no tiene backtest.** No existe un PDF de respaldos
   histórico equivalente al de Sampayo para 2014/2018/2022. V3 (la receta
   completa) se valida en vivo el 31 de mayo.
3. **Pronóstico nacional.** Las encuestas son nacionales y el modelo Stan
   es nacional. El modelo usa un único split nacional por partido; el
   pronóstico no se desagrega por región.
4. **Splits party-level — juicio cualitativo.** La tabla de transferencia
   (`data/raw/party_level_transfer.csv`) es un análisis cualitativo experto
   (bancadas, prensa, contexto político), no un ajuste data-driven, y no
   tiene validación histórica — se valida en vivo el 31 de mayo.

## 8. Reproducibilidad

- Semilla fija (`20260531`) en R y en CmdStan.
- `renv.lock` fija las versiones de los paquetes R.
- CmdStan 2.38 (ver `R/00_setup.R`).
- Toda figura va con un `sessionInfo()` en `output/sessions/`.

## 9. Entorno

R 4.4.2 · Rtools 4.4 · CmdStan 2.38 · cmdstanr 0.9. Instalación automatizada en
`R/00_setup.R`. Detalle del setup en `docs/` y en el onboarding del equipo.
