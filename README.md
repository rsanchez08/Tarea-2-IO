# Tarea 2 – Análisis de un sistema de colas M/M/1 (R + `queuecomputer`)

**Sistema estudiado:** fila de abordaje de pasajeros en la parada de salida de la ruta de buses
**La Cañada → Alajuela** (31/08/2026, 06:00–08:30). Cliente = pasajero; servidor = la puerta del
bus (`Servidor 1`); servicio = abordar.

**Resultado en una línea:** λ ≈ 34 pax/h, μ ≈ 150 pax/h, ρ ≈ 0.23 (estable). Las llegadas **no**
son Poisson (llegan en lotes) y el servicio **no** es exponencial (casi constante). Las medidas
teóricas y las de `queuecomputer` dan una espera de segundos, pero **en campo el pasajero espera
≈ 5.6 min** — sobre todo *a que llegue su bus* (el M/M/1 no modela esas "vacaciones del servidor").

---

## Cómo reproducir

Requisitos: **R ≥ 4.0** y **Python 3** (solo para armar el Excel y las verificaciones).

```r
# R: instalar paquetes una sola vez
install.packages(c("queuecomputer", "readxl", "dplyr", "lubridate", "ggplot2"))
```

```bash
# 1. (opcional) reconstruir datos_campo.xlsx desde los datos de campo originales
python3 generar_datos.py

# 2. análisis completo (imprime todo y genera R_fig1..4_*.png)
Rscript analisis_mm1.R            # -> guardar la consola en R_salida.txt

# 3. (opcional) verificación independiente en Python
python3 analisis_referencia.py

# 4. (opcional) informe en HTML a partir del Markdown
python3 construir_html.py         # informe_tecnico.html  -> Imprimir a PDF
```

Todas las rutas son **relativas**: ejecutar desde la raíz del repositorio.

---

## Mapa de archivos

| Archivo | Qué es |
|---|---|
| `datos_85_pasajeros.xlsx` | **Datos de campo originales** del grupo (85 pasajeros, 13 buses). |
| `generar_datos.py` | Arma `datos_campo.xlsx` desde el original: fija `fecha` y `servidor`, forma las fecha-hora completas y deja las 4 variables de tiempo como **fórmulas de Excel**. |
| `datos_campo.xlsx` | Excel de trabajo. Hojas: `observaciones` (1 fila/pasajero, columnas L–O con fórmulas), `llegadas_intervalo` (15 bloques de 10 min), `resumen` (agregado por columna), `formulas` (documenta cada fórmula). |
| `datos_campo_observaciones.csv`, `datos_campo_llegadas_intervalo.csv` | Los mismos datos en CSV (respaldo para `analisis_referencia.py`). |
| **`analisis_mm1.R`** | **Script principal.** Importación (inciso 8), λ y μ (inciso 9), prueba de Poisson (10.1), prueba exponencial (10.2), teóricas M/M/1 (inciso 12), `queuecomputer::queue()` (inciso 11), comparación **teóricas / computacionales / campo**, y 4 figuras. Comentado bloque a bloque. |
| `R_salida.txt` | Salida de consola de `Rscript analisis_mm1.R` (anexo). |
| `R_fig1..4_*.png` | Figuras generadas por el script R. |
| `analisis_referencia.py` | Verificación independiente en Python de todos los números del informe. |
| `informe_tecnico.md` / `.html` | Informe técnico con las 23 secciones obligatorias. `construir_html.py` genera el `.html` (imprimir a PDF). |
| `construir_html.py` | Convierte `informe_tecnico.md` en HTML autocontenido (figuras incrustadas). |
| `guia_tarea.html` | Guía de estudio / defensa oral (material de apoyo, no es entregable). |

---

## Terminología (según el enunciado)

- **Teóricas** — de las fórmulas cerradas del M/M/1.
- **Computacionales** — obtenidas con `queuecomputer::queue()`.
- **Observadas en campo** — calculadas directamente del registro (Wq real, cola máxima, % que esperó).

---

## Pendiente del grupo

- [ ] Portada e integrantes en el informe.
- [ ] Declaración de responsabilidades individuales.
- [ ] Generar el PDF del informe desde `informe_tecnico.html`.
- [ ] Revisar la lista de verificación del enunciado.
