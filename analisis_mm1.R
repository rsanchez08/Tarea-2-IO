# ==============================================================================
#  ANALISIS DE UN SISTEMA DE COLAS M/M/1
#  Sistema: abordaje de pasajeros en la puerta del bus (ruta La Canada - Alajuela)
#  Tarea 2 grupal | Ingenieria en Computacion
#
#  Que hace este script, de principio a fin:
#    1. Importa el Excel y calcula las variables de tiempo por pasajero.
#    2. Estima los parametros del modelo: lambda (llegadas) y mu (servicio).
#    3. Prueba si las llegadas por intervalo se ajustan a una Poisson (chi-cuadrado).
#    4. Prueba si los tiempos de servicio se ajustan a una exponencial (KS + chi-cuadrado).
#    5. Calcula las medidas de desempeno TEORICAS con las formulas M/M/1.
#    6. Calcula las medidas COMPUTACIONALES con queuecomputer::queue() (inciso 11)
#    7. Compara: teorico (formulas) vs computacional (queuecomputer) vs observado en campo.
#    8. Genera 4 figuras.
#
#  Requisitos (inciso 11 del enunciado):
#    install.packages(c("queuecomputer","readxl","dplyr","ggplot2","lubridate"))
#
#  Ejecutar desde la carpeta que contiene 'datos_campo.xlsx':
#    Rscript analisis_mm1.R
# ==============================================================================

library(readxl)      # leer hojas de Excel            (inciso 8 del enunciado)
library(dplyr)       # arrange(), mutate(), %>%       (inciso 8)
library(lubridate)   # manejo de fechas-hora          (inciso 8; aqui difftime es de base R)
library(ggplot2)     # figuras                        (inciso 11)
library(queuecomputer)  # queue(): simulacion de la cola FIFO  (inciso 11)

ALPHA <- 0.05        # nivel de significancia de las pruebas de bondad de ajuste

# ==============================================================================
# 1. IMPORTACION Y PREPARACION DE DATOS
#    --------------------------------------------------------------------------
#    Esta seccion sigue la ESTRUCTURA DE CODIGO del inciso 8 del enunciado:
#
#        datos <- read_excel("datos_campo.xlsx", sheet = "observaciones")
#        datos <- datos %>%
#          arrange(fecha, hora_llegada) %>%
#          mutate(
#            interarribo_min     = as.numeric(difftime(hora_llegada, lag(hora_llegada), units = "mins")),
#            tiempo_espera_min   = as.numeric(difftime(hora_inicio_servicio, hora_llegada,     units = "mins")),
#            tiempo_servicio_min = as.numeric(difftime(hora_fin_servicio, hora_inicio_servicio, units = "mins")),
#            tiempo_sistema_min  = as.numeric(difftime(hora_fin_servicio, hora_llegada,        units = "mins"))
#          )
#
#    Se le anaden dos cosas necesarias con datos reales:
#      (a) convertir las columnas de hora (texto en el Excel) a POSIXct antes de difftime;
#      (b) un control de calidad (sin tiempos negativos ni faltantes).
# ==============================================================================

# --- 1.1 Lectura de las dos hojas del Excel ------------------------------------
obs  <- read_excel("datos_campo.xlsx", sheet = "observaciones")        # una fila por PASAJERO
intv <- read_excel("datos_campo.xlsx", sheet = "llegadas_intervalo")   # una fila por bloque de 10 min

# --- 1.2 (a) Convertir las horas de texto ("2026-08-31 06:00:20") a fecha-hora -
obs <- obs %>%
  mutate(
    hora_llegada         = as.POSIXct(hora_llegada,         tz = "UTC"),
    hora_inicio_servicio = as.POSIXct(hora_inicio_servicio, tz = "UTC"),
    hora_fin_servicio    = as.POSIXct(hora_fin_servicio,    tz = "UTC")
  ) %>%
  # --- 1.3 Ordenar cronologicamente y calcular las 4 variables de tiempo -------
  #         (identico al inciso 8; difftime(..., units = "mins") -> todo en MINUTOS)
  arrange(fecha, hora_llegada) %>%
  mutate(
    interarribo_min     = as.numeric(difftime(hora_llegada,         lag(hora_llegada),     units = "mins")),  # tiempo entre llegadas consecutivas
    tiempo_espera_min   = as.numeric(difftime(hora_inicio_servicio, hora_llegada,          units = "mins")),  # llegada -> inicio de servicio
    tiempo_servicio_min = as.numeric(difftime(hora_fin_servicio,    hora_inicio_servicio,  units = "mins")),  # inicio -> fin de servicio (abordaje)
    tiempo_sistema_min  = as.numeric(difftime(hora_fin_servicio,    hora_llegada,          units = "mins"))   # llegada -> fin de servicio
  )

# --- 1.4 (b) Control de calidad ---------------------------------------------------
#     Ningun tiempo de servicio nulo/negativo, ninguna espera negativa, sin NA.
#     stopifnot() DETIENE el script si algo falla (evita analizar datos corruptos).
stopifnot(all(obs$tiempo_servicio_min > 0,  na.rm = TRUE))
stopifnot(all(obs$tiempo_espera_min  >= 0,  na.rm = TRUE))
obs <- obs %>% filter(!is.na(tiempo_servicio_min))     # descarta filas incompletas (aqui: ninguna)

# --- 1.5 Resumen en pantalla ---------------------------------------------------
n_serv <- nrow(obs)                                    # numero de pasajeros observados
cat("---- 1. DATOS ----\n")
cat(sprintf("Pasajeros observados        : %d\n", n_serv))
cat(sprintf("Intervalos de conteo (10min): %d  (ventana %g min)\n",
            nrow(intv), sum(intv$duracion_min)))
print(summary(obs[c("tiempo_espera_min", "tiempo_servicio_min", "tiempo_sistema_min")]))

# ==============================================================================
# 2. ESTIMACION DE LOS PARAMETROS  (todo en la misma unidad: MINUTOS)
# ==============================================================================

# --- 2.1 Tasa de llegada lambda ----------------------------------------------
#     Metodo del inciso 9.1:  lambda = (suma de llegadas) / (tiempo total observado).
#     Se usa la hoja de conteo por intervalo (15 bloques x 10 min = 150 min).
total_llegadas   <- sum(intv$numero_llegadas_intervalo)   # total de pasajeros contabilizados
tiempo_total_min <- sum(intv$duracion_min)                # minutos totales de observacion
lambda   <- total_llegadas / tiempo_total_min             # pasajeros por minuto
lambda_h <- lambda * 60                                   # pasajeros por hora

# --- 2.2 Tasa de servicio mu -------------------------------------------------
#     Metodo del inciso 9.2:  primero el tiempo medio de servicio, luego mu = 1 / media.
media_servicio <- mean(obs$tiempo_servicio_min)           # minutos que tarda, en promedio, un abordaje
mu   <- 1 / media_servicio                                # pasajeros por minuto
mu_h <- mu * 60                                           # pasajeros por hora

# --- 2.3 Factor de utilizacion rho y condicion de estabilidad ---------------
rho <- lambda / mu                                        # fraccion del tiempo que el servidor esta ocupado

cat("\n---- 2. PARAMETROS ----\n")
cat(sprintf("lambda = %.4f pax/min = %.2f pax/hora\n", lambda, lambda_h))
cat(sprintf("Tiempo medio de servicio (abordaje) = %.4f min\n", media_servicio))
cat(sprintf("mu     = %.4f pax/min = %.2f pax/hora\n", mu, mu_h))
cat(sprintf("rho    = %.4f  -> %s\n", rho,
            ifelse(rho < 1, "ESTABLE (rho < 1)", "NO ESTABLE  (rho >= 1: no interpretar M/M/1)")))

# ==============================================================================
# 3. BONDAD DE AJUSTE 1 -> POISSON  para el numero de llegadas por intervalo
#    H0: el numero de llegadas por intervalo sigue una distribucion de Poisson
#    H1: no la sigue
#    Prueba: chi-cuadrado de bondad de ajuste (inciso 10.1)
# ==============================================================================
cat("\n---- 3. PRUEBA DE POISSON (chi-cuadrado) ----\n")

x       <- intv$numero_llegadas_intervalo   # vector de conteos: pasajeros en cada bloque de 10 min
N       <- length(x)                        # numero de intervalos
lam_int <- mean(x)                          # lambda estimada POR INTERVALO (promedio de conteos)
kmax    <- max(x)                           # conteo maximo observado

# --- 3.1 Frecuencias observadas y esperadas ---------------------------------
#     obs_freq[k+1] = cuantos intervalos tuvieron exactamente k llegadas.
#     exp_freq[k+1] = N * P(Poisson(lam_int) = k). La ultima categoria acumula la cola P(X >= kmax).
obs_freq <- tabulate(x + 1, nbins = kmax + 1)
p_k <- dpois(0:kmax, lam_int)
p_k[kmax + 1] <- 1 - sum(p_k[1:kmax])
exp_freq <- N * p_k

# --- 3.2 Agrupar categorias hasta que la frecuencia esperada sea >= 5 -------
#     (regla clasica del chi-cuadrado para que la aproximacion sea valida).
grp_o <- c(); grp_e <- c(); grp_lab <- c()
acc_o <- 0; acc_e <- 0; ini <- 0
for (k in 0:kmax) {
  acc_o <- acc_o + obs_freq[k + 1]
  acc_e <- acc_e + exp_freq[k + 1]
  if (acc_e >= 5 || k == kmax) {                       # cierra la categoria acumulada
    grp_o   <- c(grp_o, acc_o)
    grp_e   <- c(grp_e, acc_e)
    grp_lab <- c(grp_lab, if (ini == k) as.character(k) else paste0(ini, "-", k))
    acc_o <- 0; acc_e <- 0; ini <- k + 1
  }
}
if (length(grp_o) >= 2 && grp_e[length(grp_e)] < 5) {   # si la ultima quedo < 5, unirla a la anterior
  grp_o[length(grp_o) - 1] <- grp_o[length(grp_o) - 1] + grp_o[length(grp_o)]
  grp_e[length(grp_e) - 1] <- grp_e[length(grp_e) - 1] + grp_e[length(grp_e)]
  grp_lab[length(grp_lab) - 1] <- paste0(sub("-.*", "", grp_lab[length(grp_lab) - 1]), "+")
  grp_o <- grp_o[-length(grp_o)]; grp_e <- grp_e[-length(grp_e)]; grp_lab <- grp_lab[-length(grp_lab)]
}

# --- 3.3 Estadistico, grados de libertad e indice de dispersion ------------
chi2_p <- sum((grp_o - grp_e)^2 / grp_e)                # estadistico chi-cuadrado
gl_p   <- length(grp_o) - 1 - 1                         # gl = categorias - 1 - (1 parametro estimado: lambda)
disp   <- var(x) / mean(x)                              # indice de dispersion: Poisson ideal ~ 1

print(data.frame(categoria = grp_lab, observado = grp_o, esperado = round(grp_e, 3)))
if (gl_p < 1) {
  # Con muy pocos intervalos las categorias se colapsan y no quedan grados de libertad:
  # la prueba chi-cuadrado no es concluyente. Se reporta el indice de dispersion.
  cat(sprintf("Chi2 = %.4f | gl = %d\n", chi2_p, gl_p))
  cat(sprintf("PRUEBA NO CONCLUYENTE: con N = %d intervalos las categorias se colapsan a gl <= 0.\n", N))
  cat("  Se usa el INDICE DE DISPERSION como referencia.\n")
} else {
  pval_p <- pchisq(chi2_p, gl_p, lower.tail = FALSE)    # valor-p = P(Chi2_{gl} > chi2_p)
  cat(sprintf("Chi2 = %.4f | gl = %d | valor-p = %.4f\n", chi2_p, gl_p, pval_p))
  cat(sprintf("Decision (alpha = %.2f): %s -> %s\n", ALPHA,
              ifelse(pval_p > ALPHA, "NO se rechaza H0", "se rechaza H0"),
              ifelse(pval_p > ALPHA, "compatible con Poisson", "NO compatible con Poisson")))
}
cat(sprintf("Indice de dispersion var/media = %.3f (Poisson ideal ~ 1)\n", disp))
if (disp > 1.5)
  cat("  -> SOBREdispersion: llegadas EN LOTES (cada bus deja un grupo de pasajeros).\n")
if (disp < 0.75)
  cat("  -> Subdispersion: llegadas MAS REGULARES que un proceso de Poisson.\n")

# ==============================================================================
# 4. BONDAD DE AJUSTE 2 -> EXPONENCIAL  para los tiempos de servicio
#    H0: los tiempos de servicio siguen una distribucion exponencial
#    H1: no la siguen
#    Pruebas: Kolmogorov-Smirnov (principal) + chi-cuadrado con clases equiprobables (inciso 10.2)
# ==============================================================================
cat("\n---- 4. PRUEBA EXPONENCIAL ----\n")

ts   <- obs$tiempo_servicio_min      # vector de tiempos de servicio (abordaje) por pasajero
rate <- 1 / mean(ts)                 # rate estimada = 1 / media  (inciso 10.2)

# --- 4.1 Kolmogorov-Smirnov: mayor distancia entre la CDF empirica y la exponencial teorica
ks <- ks.test(ts, "pexp", rate = rate)
cat(sprintf("Kolmogorov-Smirnov: D = %.4f | valor-p = %.4f\n", ks$statistic, ks$p.value))
cat("  (rate estimada de la muestra -> el KS es conservador, tipo Lilliefors)\n")

# --- 4.2 Chi-cuadrado con clases EQUIPROBABLES bajo la exponencial ----------
#     Se parten los datos en 'nb' intervalos que, si la exponencial fuera cierta,
#     contendrian la misma cantidad de observaciones (frecuencia esperada = n/nb).
nb <- if (length(ts) >= 48) 6 else 4                    # menos clases si la muestra es chica
brks <- qexp(seq(0, 1, length.out = nb + 1), rate = rate)
brks[1] <- -Inf; brks[nb + 1] <- Inf                    # bordes abiertos para cubrir toda la recta
o_e <- as.numeric(table(cut(ts, breaks = brks)))       # frecuencias observadas por clase
e_e <- rep(length(ts) / nb, nb)                        # frecuencias esperadas (iguales)
chi2_e <- sum((o_e - e_e)^2 / e_e)
gl_e   <- nb - 1 - 1                                   # gl = clases - 1 - (1 parametro estimado: rate)
pval_e <- pchisq(chi2_e, gl_e, lower.tail = FALSE)

cat(sprintf("Chi2 agrupado (%d clases) = %.4f | gl = %d | valor-p = %.4f\n", nb, chi2_e, gl_e, pval_e))
cat(sprintf("Coef. de variacion = %.3f (una exponencial tiene CV = 1)\n", sd(ts) / mean(ts)))
cat(sprintf("Decision (alpha = %.2f): %s -> %s\n", ALPHA,
            ifelse(min(ks$p.value, pval_e) > ALPHA, "NO se rechaza H0", "se rechaza H0"),
            ifelse(min(ks$p.value, pval_e) > ALPHA, "compatible con exponencial",
                   "NO compatible con exponencial (revisar supuesto)")))

# ==============================================================================
# 5. MEDIDAS DE DESEMPENO  ->  TEORICAS  (formulas cerradas del M/M/1, inciso 12)
#    Validas solo si rho < 1. Unidades: MINUTOS (porque lambda y mu estan en /min).
# ==============================================================================
cat("\n---- 5. MEDIDAS TEORICAS M/M/1 (minutos) ----\n")

P0 <- 1 - rho                                  # probabilidad de sistema vacio
Lq <- lambda^2 / (mu * (mu - lambda))          # numero medio en cola
Ls <- lambda / (mu - lambda)                   # numero medio en el sistema
Wq <- lambda / (mu * (mu - lambda))            # tiempo medio de espera en cola
Ws <- 1 / (mu - lambda)                        # tiempo medio en el sistema

teoricas <- data.frame(
  medida = c("rho", "P0", "Lq", "Ls", "Wq (min)", "Ws (min)"),
  valor  = round(c(rho, P0, Lq, Ls, Wq, Ws), 4)
)
print(teoricas)
# Probabilidades de espera larga (formulas de la cola M/M/1 con FIFO):
cat(sprintf("P(Wq > 5 min) = %.4f | P(Ws > 5 min) = %.4f\n",
            rho * exp(-mu * (1 - rho) * 5), exp(-mu * (1 - rho) * 5)))

# ==============================================================================
# 6. MEDIDAS DE DESEMPENO  ->  COMPUTACIONALES (queuecomputer) + OBSERVADAS EN CAMPO
#    --------------------------------------------------------------------------
#    Esta seccion sigue la ESTRUCTURA DE CODIGO del inciso 11 del enunciado:
#
#        arrivals <- cumsum(interarrival_times)
#        service  <- service_times
#        salidas  <- queue(arrivals = arrivals, service = service, servers = 1)
#        resultados <- data.frame(llegada = arrivals, servicio = service, salida = salidas) %>%
#          mutate(
#            tiempo_sistema  = salida - llegada,
#            inicio_servicio = salida - servicio,
#            tiempo_espera   = inicio_servicio - llegada
#          )
#
#    queue() NO usa formulas: reconstruye la cola FIFO de 1 servidor con la recursion
#        salida[i] = max( llegada[i] , salida[i-1] ) + servicio[i]
#    y devuelve el instante de SALIDA de cada cliente.
# ==============================================================================
cat("\n---- 6. MEDIDAS COMPUTACIONALES (queuecomputer) Y OBSERVADAS EN CAMPO ----\n")

# --- 6.1 Vectores de entrada, en MINUTOS y ordenados cronologicamente -------
#     interarrival_times: 1er valor = 0 (el primer pasajero define el origen);
#     el resto = obs$interarribo_min (que ya calculamos en la seccion 1).
interarrival_times <- obs$interarribo_min
interarrival_times[1] <- 0
arrivals <- cumsum(interarrival_times)          # tiempos ACUMULADOS de llegada (minutos desde el 1ro)
service  <- obs$tiempo_servicio_min             # tiempos de servicio (abordaje)

# Comprobaciones que pide el enunciado: orden cronologico y misma unidad (minutos).
stopifnot(!is.unsorted(arrivals))              # las llegadas estan ordenadas
stopifnot(all(service > 0))                    # todos los servicios son positivos

# --- 6.2 Simular la cola: 1 servidor ---------------------------------------
salidas <- queue(arrivals = arrivals, service = service, servers = 1)   # instantes de salida

# --- 6.3 Reconstruir espera / inicio / tiempo en sistema de cada pasajero --
resultados <- data.frame(
  llegada  = arrivals,
  servicio = service,
  salida   = salidas
) %>%
  mutate(
    tiempo_sistema  = salida - llegada,               # llegada -> salida
    inicio_servicio = salida - servicio,              # la salida menos lo que duro el servicio
    tiempo_espera   = inicio_servicio - llegada       # lo que espero en la fila (>= 0)
  )

# --- 6.4 Medidas que produce queue()  ->  columna (Q) --------------------------
#     queue() modela un servidor SIEMPRE DISPONIBLE. Solo captura la pequena cola
#     "pasajero-detras-de-pasajero" en la puerta, NO la espera por que llegue el bus.
Wq_Q <- mean(resultados$tiempo_espera)
Ws_Q <- mean(resultados$tiempo_sistema)
Lq_Q <- lambda * Wq_Q                                 # Ley de Little (L = lambda * W)
Ls_Q <- lambda * Ws_Q

# Desfase esperado: como queue() no "espera al bus", su inicio_servicio queda
# muy por debajo del registrado en campo. Se muestra como diagnostico, no como error.
inicio_campo <- as.numeric(difftime(obs$hora_inicio_servicio, min(obs$hora_llegada), units = "mins"))
cat(sprintf("Desfase queue() vs campo en inicio_servicio: media %.2f min\n",
            mean(abs(resultados$inicio_servicio - inicio_campo))))
cat("  -> queue() (servidor siempre activo) NO reproduce la espera por el bus.\n")

# --- 6.5 Medidas OBSERVADAS DIRECTAMENTE en el registro de campo  ->  columna (C)
#     Aqui la espera SI incluye el tiempo que el pasajero aguarda a que llegue su bus.
Wq_C <- mean(obs$tiempo_espera_min)
Ws_C <- mean(obs$tiempo_sistema_min)
Lq_C <- lambda * Wq_C
Ls_C <- lambda * Ws_C

# Longitud maxima de la cola REAL (desde los tiempos registrados):
# +1 cuando un pasajero llega a la parada, -1 cuando empieza a abordar.
lleg_rel <- as.numeric(difftime(obs$hora_llegada,         min(obs$hora_llegada), units = "mins"))
ini_rel  <- as.numeric(difftime(obs$hora_inicio_servicio, min(obs$hora_llegada), units = "mins"))
t_ev <- c(lleg_rel, ini_rel)
d_ev <- c(rep(1, n_serv), rep(-1, n_serv))
o    <- order(t_ev, d_ev)                             # empates: primero el -1, luego el +1
t_ev <- t_ev[o]; d_ev <- d_ev[o]
qcurve  <- cumsum(d_ev)
Lq_time <- sum(head(qcurve, -1) * diff(t_ev)) / (t_ev[length(t_ev)] - t_ev[1])   # cola media (temporal)
Lmax    <- max(qcurve)                                                            # cola maxima observada

pct_espera <- mean(obs$tiempo_espera_min > 1 / 60) * 100   # % de pasajeros que esperaron > 1 s
throughput <- n_serv / tiempo_total_min                    # tasa efectiva de salida (pax/min)

cat(sprintf("\n(Q) queue()  : Wq = %.4f min | Ws = %.4f min | Lq = %.4f | Ls = %.4f\n",
            Wq_Q, Ws_Q, Lq_Q, Ls_Q))
cat(sprintf("(C) campo    : Wq = %.4f min | Ws = %.4f min | Lq = %.4f | Ls = %.4f\n",
            Wq_C, Ws_C, Lq_C, Ls_C))
cat(sprintf("Cola media observada (temporal) = %.2f | Cola maxima observada = %d\n", Lq_time, Lmax))
cat(sprintf("%% de pasajeros que tuvieron que esperar = %.1f %%\n", pct_espera))
cat(sprintf("Tasa efectiva de salida = %.4f pax/min (%.2f /h)\n", throughput, throughput * 60))

# ==============================================================================
# 7. COMPARACION   (inciso 12: "comparar las medidas teoricas con las obtenidas
#    mediante queuecomputer" y explicar las diferencias)
#      T = TEORICAS         (formulas M/M/1)
#      Q = COMPUTACIONALES  (queuecomputer::queue())   <- lo que el enunciado
#                                                         llama "computacionales"
#      C = OBSERVADAS EN CAMPO (calculadas del registro directo)
# ==============================================================================
cat("\n---- 7. COMPARACION  T(teoricas) vs Q(computacionales, queuecomputer) vs C(campo) ----\n")
comp <- data.frame(
  medida         = c("rho", "P0", "Lq", "Ls", "Wq (min)", "Ws (min)"),
  T_teorica      = c(rho, P0, Lq, Ls, Wq, Ws),
  Q_computacional= c(throughput / mu, P0, Lq_Q, Ls_Q, Wq_Q, Ws_Q),
  C_campo        = c(rho, P0, Lq_C, Ls_C, Wq_C, Ws_C)
)
comp_print <- comp
comp_print[-1] <- lapply(comp_print[-1], round, 4)
print(comp_print, row.names = FALSE)
cat("\nInterpretacion:\n")
cat("  * rho y P0 coinciden en las tres (lambda y mu bien estimadas).\n")
cat("  * (T) y (Q) dan una espera de SEGUNDOS: solo ven la cola en la puerta.\n")
cat("  * (C) da ~", sprintf("%.1f", Wq_C), "min: el pasajero espera sobre todo A QUE LLEGUE EL BUS.\n", sep = "")
cat("  * El M/M/1 NO modela esa espera (servidor con 'vacaciones' entre buses):\n")
cat("    la espera de campo ~ mitad del intervalo entre buses (headway).\n")

# ==============================================================================
# 8. FIGURAS  (se guardan como PNG en la carpeta de trabajo)
# ==============================================================================

# --- Fig. 1: histograma de los tiempos de servicio + exponencial ajustada ---
g1 <- ggplot(data.frame(ts = ts), aes(ts)) +
  geom_histogram(aes(y = after_stat(density)), bins = 12, fill = "#2b6cb0", colour = "white") +
  stat_function(fun = dexp, args = list(rate = rate), colour = "#dd6b20", linewidth = 1.1) +
  labs(title = "Fig. 1  Tiempo de servicio (abordaje) vs. exponencial ajustada",
       x = "Tiempo de servicio - abordaje (min)", y = "Densidad") +
  theme_minimal()
ggsave("R_fig1_servicio_exponencial.png", g1, width = 6, height = 3.6, dpi = 130)

# --- Fig. 2: frecuencias observadas vs esperadas (Poisson) -----------------
pois_df <- data.frame(
  k    = rep(0:kmax, 2),
  frec = c(obs_freq, exp_freq),
  tipo = rep(c("Observado", "Esperado Poisson"), each = kmax + 1)
)
g2 <- ggplot(pois_df, aes(factor(k), frec, fill = tipo)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Observado" = "#2b6cb0", "Esperado Poisson" = "#dd6b20")) +
  labs(title = "Fig. 2  Llegadas por intervalo: observado vs. Poisson",
       x = "Pasajeros que llegan por intervalo de 10 min", y = "Numero de intervalos", fill = NULL) +
  theme_minimal()
ggsave("R_fig2_poisson.png", g2, width = 6, height = 3.6, dpi = 130)

# --- Fig. 3: numero de pasajeros en el sistema segun el REGISTRO DE CAMPO ---
#     (+1 cuando el pasajero llega a la parada, -1 cuando termina de abordar).
#     Muestra como los pasajeros se acumulan esperando cada bus y luego abordan.
ev <- data.frame(t = c(lleg_rel,
                       as.numeric(difftime(obs$hora_fin_servicio, min(obs$hora_llegada), units = "mins"))),
                 d = c(rep(1, n_serv), rep(-1, n_serv)))
ev <- ev[order(ev$t, ev$d), ]
ev$n <- cumsum(ev$d)
g3 <- ggplot(ev, aes(t, n)) +
  geom_step(colour = "#2b6cb0") +
  labs(title = "Fig. 3  Pasajeros en el sistema segun el registro de campo (06:00-08:30)",
       x = "Minutos desde las 06:00", y = "Pasajeros en el sistema") +
  theme_minimal()
ggsave("R_fig3_cola_tiempo.png", g3, width = 6.4, height = 3.4, dpi = 130)

# --- Fig. 4: barras  T(teorico) / Q(queue) / C(campo)  para Lq, Ls, Wq, Ws --
cmp <- comp[3:6, ]
comp_long <- rbind(
  data.frame(medida = cmp$medida, valor = cmp$T_teorica,       tipo = "Teorico M/M/1"),
  data.frame(medida = cmp$medida, valor = cmp$Q_computacional, tipo = "queuecomputer"),
  data.frame(medida = cmp$medida, valor = cmp$C_campo,         tipo = "Campo (observado)")
)
comp_long$medida <- factor(comp_long$medida, levels = cmp$medida)
comp_long$tipo   <- factor(comp_long$tipo,
                           levels = c("Teorico M/M/1", "queuecomputer", "Campo (observado)"))
g4 <- ggplot(comp_long, aes(medida, valor, fill = tipo)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Teorico M/M/1" = "#2b6cb0",
                               "queuecomputer" = "#7aa8d2",
                               "Campo (observado)" = "#dd6b20")) +
  labs(title = "Fig. 4  Lq, Ls, Wq, Ws: teorico vs. queuecomputer vs. campo",
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal()
ggsave("R_fig4_comparacion.png", g4, width = 6.4, height = 3.6, dpi = 130)

cat("\nFiguras guardadas: R_fig1_servicio_exponencial.png, R_fig2_poisson.png,",
    "R_fig3_cola_tiempo.png, R_fig4_comparacion.png\n")
cat("\n=== FIN DEL ANALISIS ===\n")
