# Declaración de uso de inteligencia artificial

*Concurso Recetas Electorales 2026 — el reglamento exige declarar explícitamente
el uso de herramientas de IA. Esta es esa declaración.*

## Herramientas utilizadas

- **Claude (Anthropic)** — modelo Claude Opus, vía **Claude Code** (CLI).
  Asistencia en el diseño del modelo y en la escritura del código R/Stan.
- **Gemini (Google)** — investigación y verificación de información.
- **Perplexity** — investigación y verificación de información.

## En qué se usó la IA

- **Investigación y verificación de información** — principalmente con
  **Gemini** y **Perplexity**: búsqueda de encuestas 2026, respaldos de
  bancada, contexto político y verificación cruzada contra fuentes oficiales
  (Registraduría) y prensa.
- **Diseño del modelo** — con **Claude Code**: apoyo en la arquitectura
  Dirichlet-Multinomial jerárquica, la parametrización no centrada de los
  *house effects* y el prior estructural por transferencia partido-por-partido.
- **Escritura del código** — con **Claude Code**: borradores del modelo Stan
  y del código R (preparación de datos, ajuste, diagnósticos, backtest,
  forecast, figuras), escritos de forma colaborativa con el equipo y revisados.
- **Backtest y redacción** — con **Claude Code**: apoyo en la validación
  histórica (2014/2018/2022) y en los borradores de documentación.

## Rol humano — dirección, escritura y auditoría

El proyecto fue **dirigido y auditado por el Equipo Alfil** en todo momento:

- **El código se escribió y auditó con el equipo.** El equipo dirigió el
  desarrollo, escribió y modificó código, y revisó y auditó el código
  producido con asistencia de IA antes de incorporarlo.
- **Las decisiones de modelado son humanas.** La arquitectura final, los
  supuestos, los criterios de inclusión/exclusión de encuestas y la validación
  fueron decididos y verificados por el equipo.
- **Los splits de transferencia son un análisis humano.** La tabla
  `data/raw/party_level_transfer.csv` se construyó caso por caso a partir del
  análisis cualitativo de bancadas del equipo — comportamiento de bancada,
  declaraciones de prensa, contexto e historial político. La IA solo la
  aplicó al modelo; no generó esos valores.
- **Los datos son reales y de fuentes oficiales.** Ningún dato fue inventado
  por la IA. Cada cifra es auditable contra su fuente (ver tabla abajo).

## El pronóstico no lo generó un modelo de lenguaje

El número que se envía al concurso **no fue producido directamente por un LLM**.
Es la salida de un modelo estadístico bayesiano (R + Stan) — un
Dirichlet-Multinomial jerárquico — cuyo código se desarrolló con asistencia de
IA bajo dirección y auditoría humana. Cualquiera puede re-ejecutar el modelo y
obtener el mismo resultado.

## Reproducibilidad

Todo el código es público y ejecutable. La semilla aleatoria está fijada
(`20260531`). Cualquier persona puede reproducir el posterior exacto siguiendo
las instrucciones del `README.md`.

## Datos: fuentes

| Insumo | Fuente |
|---|---|
| Encuestas 2026 (16 sondeos utilizables) | Firmas encuestadoras, vía prensa — links en `data/raw/encuestas2026.csv`. AtlasIntel excluida por sanción CNE (resolución CNE-E-DG-2026-014724, 2026-05-19) |
| Senado 2026 por partido | Escrutinio Registraduría, base de datos electoral del equipo |
| Transferencia partido→candidato | Análisis del equipo (PDF de bancadas + auditoría) |
| Resultados históricos 2014/2018/2022 | Registraduría Nacional, verificados voto-a-voto |
