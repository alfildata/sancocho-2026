# Backtest — validación contra 2014 / 2018 / 2022

Antes de pronosticar 2026, el modelo se validó contra las tres primeras vueltas
presidenciales anteriores. Para cada año se usaron **solo datos previos al día
de elección** (encuestas de primera vuelta + resultado del Senado del mismo año).

- **V1** — solo encuestas.
- **V2** — encuestas + prior estructural del Senado (cada candidato hereda la
  cuota de votos de su lista al Senado del año).

La capa de bancadas (V3) no se backtestea: no existe un documento de respaldos
histórico equivalente al análisis cualitativo de bancadas realizado por el equipo Alfil en 2026.

## Resultados

Métrica del concurso: MSE sobre los 5 candidatos puntuados.

| Año | Variante | MSE | MAE | Cobertura 80% | Top-2 correcto |
|---|---|---:|---:|---:|:--:|
| 2014 | V1 | 0.00298 | 5.4 pp | 80 % | ✅ |
| 2014 | V2 | 0.00275 | 5.1 pp | 60 % | ✅ |
| 2018 | V1 | 0.00186 | 3.5 pp | 80 % | ✅ |
| 2018 | V2 | 0.00200 | 3.8 pp | 60 % | ✅ |
| 2022 | V1 | 0.00260 | 3.7 pp | 40 % | ❌ |
| 2022 | V2 | 0.00264 | 3.8 pp | 40 % | ❌ |

MSE promedio: **V1 ≈ 0.00248 · V2 ≈ 0.00246**.

## Lectura

### El motor de encuestas funciona
En 2014 y 2018 el modelo acertó los **dos finalistas**. El error medio por
candidato (MAE) es de 3.5–5.4 pp — el rango esperable para un pronóstico basado
en encuestas.

### El error dominante son las sorpresas de última semana
El mayor error de cada año es siempre un candidato que **subió en la última
semana**, cuando la ley colombiana ya prohíbe publicar encuestas:

| Año | Candidato | Predicho | Real | Error |
|---|---|---:|---:|---:|
| 2014 | Zuluaga | 22.0 % | 29.3 % | **−7.3 pp** |
| 2018 | Fajardo | 15.5 % | 23.8 % | **−8.3 pp** |
| 2022 | Hernández | 17.7 % | 28.2 % | **−10.4 pp** |

Ningún modelo basado en encuestas puede ver un salto que ocurre después del
último sondeo legal. En 2022 ese salto (Hernández) hizo que el modelo errara el
top-2. Es una limitación estructural del dato, no del método.

### V2 ≈ V1: el prior del Senado es marginal a nivel nacional
Con 30–48 encuestas por año, la verosimilitud domina; el prior estructural del
Senado mueve el resultado nacional muy poco (V2 y V1 empatan en MSE). Esto es
esperable y honesto: con suficientes encuestas, son las encuestas las que
mandan.

Para 2026 el prior estructural (V3) es mucho más sofisticado que el V2 del
backtest: usa la transferencia partido-por-partido construida a partir del
análisis cualitativo de bancadas. Esa capa **no tiene equivalente histórico** —
se valida en vivo el 31 de mayo.

### Calibración del error de forecast
El RMS de los residuos del backtest es **5.0 pp** por candidato. Los intervalos
del modelo se ensanchan con un shock de error de forecast (`fcast_logit_sd =
0.315`) calibrado para que su desvío predictivo iguale ese RMS. Con esa
calibración la cobertura al 80% es 80/80/40 % (2014/2018/2022): la baja
cobertura de 2022 es, otra vez, la sorpresa Hernández — un evento de cola que
un intervalo al 80% no está obligado a capturar. Con 15 puntos esta
calibración es de baja precisión — limitación de datos, documentada.

## Conclusión

El backtest valida el motor de encuestas (top-2 correcto salvo ante una
sorpresa de última semana) y muestra que el prior del Senado no degrada el
pronóstico nacional. El MSE histórico (~0.0025) es la referencia realista de lo
que un pronóstico de este tipo puede lograr. Para 2026 se envía **V3**, que
suma la capa de bancadas sobre este motor validado.
