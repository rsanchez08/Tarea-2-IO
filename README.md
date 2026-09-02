# Tarea 2 — Análisis de un sistema de colas M/M/1 con R y `queuecomputer`

**Curso:** Investigación de Operaciones · **Carrera:** Ingeniería en Computación

Estudio de campo de un sistema real de **una cola y un solo servidor**, con estimación de
parámetros, pruebas de bondad de ajuste (Poisson y exponencial) y cálculo de las medidas de
desempeño del modelo **M/M/1**, implementado en **R** con el paquete **`queuecomputer`**.

---

## Sistema estudiado

**Fila de abordaje de pasajeros** en la parada de salida de la ruta de buses
**La Cañada → Alajuela**.

| | |
|---|---|
| Unidad que llega | el pasajero |
| Servidor (único) | la puerta del bus — `Servidor 1` |
| Servicio | abordar: subir, pagar/marcar el pasaje y avanzar |
| Disciplina | FIFO / FCFS |
| Observación | 31/08/2026, 06:00–08:30 (pico de la mañana), 150 min |
| Muestra | 85 pasajeros en 13 buses; conteo de llegadas en 15 bloques de 10 min |

---

## Contenido del repositorio

| Archivo | Descripción |
|---|---|
| **`analisis_mm1.R`** | Script único del análisis. Comentado bloque a bloque; se ejecuta de principio a fin sin pasos manuales. |
| **`datos_campo.xlsx`** | Datos de campo. Cuatro hojas: `observaciones`, `llegadas_intervalo`, `resumen`, `formulas` (ver más abajo). |

> El informe técnico (PDF), las figuras y los scripts auxiliares se mantienen fuera del
> repositorio para dejarlo mínimo y reproducible.

---

## Requisitos

- **R ≥ 4.0**
- Paquetes: `queuecomputer`, `readxl`, `dplyr`, `lubridate`, `ggplot2`

```r
install.packages(
  c("queuecomputer", "readxl", "dplyr", "lubridate", "ggplot2"),
  repos = "https://cloud.r-project.org"
)
```

---

## Cómo ejecutar el script

### 1. Obtener el proyecto

```bash
git clone https://github.com/rsanchez08/Tarea-2-IO.git
cd Tarea-2-IO
```

### 2. Ejecutar el análisis

Desde la **raíz del repositorio** (la ruta a `datos_campo.xlsx` es relativa):

```bash
Rscript analisis_mm1.R
```

Para guardar además la salida de consola en un archivo:

```bash
Rscript analisis_mm1.R | tee R_salida.txt        # macOS / Linux
Rscript analisis_mm1.R  > R_salida.txt 2>&1       # cualquier sistema
```

Alternativa desde **RStudio**: abrir el proyecto en la carpeta y ejecutar
`source("analisis_mm1.R")`.

### 3. Resultado

El script **imprime en consola** los 7 apartados del análisis (datos, parámetros, prueba de
Poisson, prueba exponencial, medidas teóricas, medidas computacionales y de campo, comparación) y
**genera 4 figuras** en la carpeta:

```
R_fig1_servicio_exponencial.png   histograma del tiempo de servicio + exponencial ajustada
R_fig2_poisson.png                llegadas por intervalo: observado vs. Poisson
R_fig3_cola_tiempo.png            nº de pasajeros en el sistema a lo largo de la sesión
R_fig4_comparacion.png            Lq, Ls, Wq, Ws: teóricas vs. computacionales vs. campo
```

---

## Qué hace el script (mapa de bloques ↔ enunciado)

| Bloque de `analisis_mm1.R` | Qué calcula | Inciso |
|---|---|---|
| **1. Importación y preparación** | `read_excel` → `arrange(fecha, hora_llegada)` → `mutate` de `interarribo_min`, `tiempo_espera_min`, `tiempo_servicio_min`, `tiempo_sistema_min` con `difftime(..., "mins")`. Conversión a `POSIXct` y control de calidad (`stopifnot`). | 8 |
| **2. Parámetros** | `λ = Σ llegadas / tiempo total`; `μ = 1 / (tiempo medio de servicio)`; `ρ = λ/μ` y verificación `ρ < 1`. Todo en minutos. | 9 |
| **3. Prueba de Poisson** | Sobre los **conteos por intervalo**: λ̂, frecuencias observadas y esperadas, agrupación si esperada < 5, χ², grados de libertad, valor p (α = 0.05), decisión + índice de dispersión. | 10.1 |
| **4. Prueba exponencial** | Sobre los tiempos de servicio: Kolmogórov–Smirnov + χ² con clases equiprobables; parámetro, estadístico, valor p, coeficiente de variación, decisión. | 10.2 |
| **5. Medidas teóricas M/M/1** | `P0 = 1 − ρ`, `Lq = λ²/[μ(μ−λ)]`, `Ls = λ/(μ−λ)`, `Wq = λ/[μ(μ−λ)]`, `Ws = 1/(μ−λ)`, y `P(Wq>5)`, `P(Ws>5)`. | 12 |
| **6. Medidas computacionales y de campo** | `arrivals <- cumsum(interarrival_times)` → `queue(arrivals, service, servers = 1)` → `mutate(tiempo_sistema, inicio_servicio, tiempo_espera)`. Además, las medidas **observadas directamente** en el registro (Wq, Ws, Lq, cola máxima, % que esperó, throughput). | 11 |
| **7. Comparación** | Tabla de tres columnas — **teóricas** (fórmulas) / **computacionales** (`queuecomputer`) / **observadas en campo** — con su interpretación. | 12 |
| **8. Figuras** | Las 4 figuras `R_fig*.png` con `ggplot2`. | — |

---

## El archivo `datos_campo.xlsx`

| Hoja | Contenido |
|---|---|
| **`observaciones`** | Una fila por pasajero. Columnas de identificación y de hora (`hora_llegada`, `hora_inicio_servicio`, `hora_fin_servicio`, `hora_llegada_bus`, `hora_salida_bus`), `intervalo_observacion`, `numero_llegadas_intervalo`, `servidor`. Las 4 variables derivadas (`interarribo_min`, `tiempo_espera_min`, `tiempo_servicio_min`, `tiempo_sistema_min`) están como **fórmulas de Excel** sobre las columnas de hora (× 1440 para pasar días → minutos). |
| **`llegadas_intervalo`** | Vista normalizada del conteo: 15 bloques de 10 min (06:00–08:30) con `numero_llegadas_intervalo`. Es la que usa R para estimar λ y para la prueba de Poisson. |
| **`resumen`** | Suma, promedio, mínimo, máximo y desviación estándar de cada variable derivada y del conteo por intervalo. |
| **`formulas`** | Documenta cada una de las 4 fórmulas de la hoja `observaciones`. |

> En R, las 4 variables derivadas se **recalculan** con `difftime` a partir de las columnas de
> hora, de modo que el análisis no depende de que Excel recalcule las fórmulas.

---

## Resultados principales

| Parámetro | Valor |
|---|---|
| λ (llegada de pasajeros) | 0.567 pax/min = **34.0 pax/hora** |
| 1/μ (tiempo medio de abordaje) | **0.40 min** (24 s) |
| μ (tasa de servicio) | 2.50 pax/min = **150 pax/hora** |
| ρ = λ/μ | **0.227** → sistema estable (servidor libre 77 % del tiempo) |

**Pruebas de bondad de ajuste**

| Prueba | Resultado |
|---|---|
| Poisson (llegadas/intervalo) | **No respaldado.** Índice de dispersión = 2.54 (llegadas en lotes). La χ² no es concluyente con 15 intervalos. |
| Exponencial (tiempo de servicio) | **Rechazada.** KS D = 0.449, p ≈ 0; χ² p ≈ 0; CV = 0.32 (servicio casi constante). |

**Comparación de las medidas**

| Medida | Teórica (M/M/1) | Computacional (`queuecomputer`) | Observada en campo |
|---|---:|---:|---:|
| ρ | 0.227 | 0.227 | 0.227 |
| P₀ | 0.773 | 0.773 | 0.773 |
| Lq | 0.07 | 0.05 | **3.19** (máx. 15) |
| Ls | 0.29 | 0.28 | **3.41** |
| Wq | 0.12 min | 0.10 min | **5.62 min** |
| Ws | 0.52 min | 0.50 min | **6.02 min** |

**Interpretación.** Las fórmulas M/M/1 y `queuecomputer` solo captan la pequeña cola *en la
puerta* (segundos). La espera real —**5.6 min, y el 100 % de los pasajeros esperó**— es sobre todo
el tiempo que el pasajero aguarda **a que llegue su bus**: el modelo M/M/1 no representa esas
"vacaciones del servidor". La espera de campo coincide con la regla clásica de transporte,
**Wq ≈ mitad del intervalo entre buses** (headway medio ≈ 12 min → ≈ 6 min).

**Conclusión operativa.** El abordaje es rápido y con holgura (ρ ≈ 0.23); lo que determina la
espera del usuario es la **frecuencia de la ruta**. La única palanca real para reducirla es
**poner más buses** (reducir el headway).

---

## Reproducibilidad

- El script usa **rutas relativas** y se ejecuta de principio a fin sin pasos manuales.
- Los números de este README y del informe coinciden con la salida de `analisis_mm1.R`.
- Unidades consistentes en todo el análisis: **minutos**.
- No se copian resultados de QM‑Window ni de otro software.
