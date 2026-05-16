# Modelo Sancocho — Pronóstico primera vuelta presidencial Colombia 2026

Receta para el concurso **Recetas Electorales 2026**. Pronostica la proporción
de votos válidos de los cinco candidatos puntuados en la primera vuelta del
**31 de mayo de 2026**: Iván Cepeda, Abelardo de la Espriella, Paloma Valencia,
Sergio Fajardo y Claudia López.

## Cocinero

**Receta:** Sancocho · **Cocinero:** Equipo Alfil — [alfil.co](https://alfil.co)

Receta preparada por **Equipo Alfil** para el concurso Recetas Electorales 2026.

**Quiénes la cocinaron**

- **Andrés Miguel Sampayo Navarro** —  Andrés Sampayo, Doctor en 
  Estudios Políticos e Internationales de la Universidad del Rosario
  [LinkedIn](https://www.linkedin.com/in/andr%C3%A9s-miguel-sampayo-navarro-44679656/) ·
  [X](https://x.com/asampayo)
- **John Andrés Martínez Callejas** — Asesor en asuntos normativos, análisis de
  datos y comunicación.
  [LinkedIn](https://www.linkedin.com/in/john-andres-m-17230b35/) ·
  [X](https://x.com/Megajuandres)
- **Santiago Espitia Patiño** — Ingeniero de software con énfasis en datos.
  [LinkedIn](https://www.linkedin.com/in/santiagoep)

**Alfil** · [alfil.co](https://alfil.co) · [LinkedIn](https://www.linkedin.com/in/alfildata) · [X](https://x.com/alfildata) · [Instagram](https://instagram.com/alfildata) · [TikTok](https://www.tiktok.com/@alfildata)

**Autorización.** Equipo Alfil autoriza expresamente a la organización del
concurso Recetas Electorales 2026 a publicar los ingredientes (datos), la
metodología y los resultados de esta receta.

## La receta en una frase

Un modelo bayesiano que **combina tres fuentes** — las **encuestas**, el **resultado del Senado 2026** y los **respaldos
de bancada**. Cada una aporta algo; el modelo las pondera
y las junta en una sola estimación del voto de cada candidato.

- 🐔 **Encuestas** — 19 mediciones de 4 firmas probabilísticas (Invamer, GAD3, Guarumo, CNC). La verosimilitud del modelo. AtlasIntel queda excluida por su metodología RDR digital no probabilística (cuestionada por el CNE bajo la Ley 2494/2025) — la corrida con AtlasIntel se reporta como sensibilidad. Cuatro firmas adicionales quedan excluidas por problemas metodológicos documentados (Cifras y Conceptos, W.A.A, Datexco, YanHaas).
- 🐄 **Senado 2026** — el voto efectivo del 8 de marzo, transferido partido por
  partido a los candidatos presidenciales (el prior estructural).
- 🐖 **Bancadas** — a quién apoya la dirigencia de cada partido (fija la
  *dirección* de cada transferencia).

## Cómo funciona

1. **Prior estructural.** Para cada uno de los 17 partidos con representación
   en el Senado 2026 se estima qué fracción de su voto se transfiere a cada
   candidato presidencial (`data/raw/party_level_transfer.csv`). Cada split se
   construyó **caso por caso**, a partir de un análisis cualitativo del
   partido: el comportamiento y los respaldos de su bancada, las declaraciones
   de prensa de sus dirigentes y precandidatos, los avales formales y el
   contexto e historial político de la colectividad. Repartimos el voto de 
   cada uno de los 17 partidos del Senado entre los 5 candidatos, sumamos todo 
   a nivel nacional, y ese total es el punto de partida del modelo.:
   Cepeda 45.0 % · Valencia 28.2 % · Espriella 24.4 % · Fajardo 1.4 % · López 1.0 % · Otros 0.0 %

2. **Verosimilitud.** Las 19 encuestas le dicen al modelo qué intención de voto
   mide la gente hoy, y corrigen el punto de partida hacia esa señal. Pero el
   modelo no toma las encuestas como verdad pura: aprende y ajusta tres cosas
   sobre la marcha:
   - **El sesgo de cada encuestadora** (*house effects*) — cada firma tiende a
     favorecer un poco a algún candidato; el modelo detecta ese sesgo y lo
     descuenta, para quedarse con la "encuestadora promedio".
   - **Cuánto confiar en las encuestas** (κ, la sobredispersión) — el modelo
     mide qué tan de acuerdo están las encuestas entre sí. Cuando se contradicen
     más de lo que sus tamaños de muestra explican — y en 2026 lo hacen — les
     baja el peso.
   - **La antigüedad de cada encuesta** (decaimiento temporal) — una encuesta
     pierde la mitad de su peso cada 25 días, así que el forecast refleja sobre
     todo los sondeos más recientes.

   En resumen: arrancamos del prior estructural y lo movemos hacia lo que dicen
   las encuestas, pero filtrando el sesgo de cada firma, descontando las que se
   contradicen entre sí y dándole más voz a las más frescas.

3. **Posterior.** Es el resultado del modelo: combina el punto de partida
   (paso 1) con la señal de las encuestas (paso 2) y entrega el pronóstico.
   Lo estima **para el día de la elección** —no para la fecha de la última
   encuesta— y **sin el sesgo de ninguna encuestadora en particular**. Y no
   devuelve un solo número por candidato, sino una **distribución de
   probabilidad**: el valor más probable más un rango de incertidumbre
   alrededor. De ahí salen los intervalos del forecast — por ejemplo, Cepeda
   40.9 %, con un 80 % de probabilidad de caer entre 30 % y 53 %.

## Estructura del repositorio

```
stan/sancocho_dm.stan           Modelo bayesiano jerárquico Dirichlet-Multinomial
R/config.R                      Parámetros (todo ajustable en un solo lugar)
R/helpers.R                     Datos, prior estructural y ejecución del modelo
R/extract.R                     Resumen del posterior
R/00_setup.R                    Instala toolchain + CmdStan
R/01_data_prep.R                CSV crudos -> stan_data
R/02_fit.R                      Compila y ajusta el forecast 2026 (V1, V3)
R/03_diagnostics.R              Convergencia + posterior predictive checks
R/04_backtest.R                 Validación contra 2014 / 2018 / 2022
R/05_forecast.R                 Tabla de submission + figura del forecast
R/06_sensitivity_atlasintel.R   Sensibilidad: forecast SIN vs CON AtlasIntel
data/raw/                       Insumos (encuestas, transferencia, Senado)
output/                         Resultados (forecast, backtest, figuras)
docs/                           Metodología y declaración de uso de IA
```

## Reproducir

Requisitos: R 4.4.x, Rtools 4.4, CmdStan ≥ 2.38 (ver `docs/methodology.md`).

```r
Rscript R/00_setup.R       # toolchain + CmdStan + smoke test
Rscript R/01_data_prep.R   # prepara los datos
Rscript R/02_fit.R         # ajusta el modelo 2026
Rscript R/03_diagnostics.R # diagnósticos de convergencia
Rscript R/04_backtest.R    # backtest histórico
Rscript R/05_forecast.R    # forecast final + CSV de submission
```

La semilla (`20260531`) está fijada; el posterior es reproducible.

## Variantes

| Variante | Fuentes | Uso |
|---|---|---|
| V1 | solo encuestas | línea base |
| V2 | encuestas + Senado | backtest histórico |
| V3 | encuestas + Senado + bancadas | **forecast 2026 (submission)** |

El backtest valida V1/V2 contra 2014/2018/2022. La capa de bancadas (V3) no
tiene equivalente histórico — se valida en vivo el 31 de mayo.

### Sensibilidad a AtlasIntel

El forecast de submission **excluye AtlasIntel** por su metodología
"Random Digital Recruitment" (RDR digital) — un sondeo online no
probabilístico que el CNE cuestionó (resolución CNE-E-DG-2026-014724,
2026-05-19) bajo la Ley 2494/2025. Aunque la cautelar quedó sin firmeza por
el recurso de reposición de Semana, la objeción técnica sobre la metodología
sigue pendiente de fondo, y mantenemos la exclusión por consistencia con el
criterio aplicado a otras firmas no probabilísticas (Datexco, W.A.A). Para
que la decisión sea auditable, `R/06_sensitivity_atlasintel.R` corre el
modelo V3 las dos formas y escribe dos CSVs en `output/`
(`atlasintel_sensitivity.csv` y `forecast_2026_con_atlasintel.csv`):

| Candidato | Sin AtlasIntel (oficial) | Con AtlasIntel |
|---|---:|---:|
| Iván Cepeda | 40.9 % | 40.3 % |
| Abelardo de la Espriella | 26.8 % | 27.9 % |
| Paloma Valencia | 17.5 % | 17.8 % |
| Sergio Fajardo | 2.6 % | 3.0 % |
| Claudia López | 2.1 % | 1.7 % |

La narrativa de fondo no cambia con o sin AtlasIntel: Cepeda mantiene el
liderazgo claro. El flag vive en `R/config.R` (`include_atlasintel`, `FALSE`
por defecto); para correr la sensibilidad CON AtlasIntel, usar la variable de
entorno `INCLUDE_ATLASINTEL=1` (sin editar el archivo).

## Resultados

- Forecast 2026: `output/forecast_2026.csv`
- Backtest: `output/backtest_summary.csv`
- Metodología completa: `docs/methodology.md`

## Declaración de uso de inteligencia artificial

El reglamento del concurso exige declarar el uso de herramientas de IA. El
detalle completo está en **[`docs/declaracion-ia.md`](docs/declaracion-ia.md)**.

Resumen del uso:

- **Claude (Anthropic), vía Claude Code** — asistencia en el diseño del modelo
  y en la escritura del código R/Stan.
- **Gemini (Google)** y **Perplexity** — investigación y verificación de
  información (encuestas, respaldos de bancada, contexto político).
- **Equipo Alfil** — dirigió el desarrollo, escribió y auditó el código, y
  tomó todas las decisiones de modelado, los supuestos políticos y la
  validación de resultados.

El pronóstico **no fue generado directamente por un modelo de lenguaje**: es la
salida de un modelo estadístico (R + Stan) cuyo código se desarrolló con
asistencia de IA, bajo dirección y auditoría humana. Los datos provienen de
fuentes oficiales y públicas verificadas.

## Licencia

MIT — ver `LICENSE`.
