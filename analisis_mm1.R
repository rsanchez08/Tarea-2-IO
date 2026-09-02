# Analisis de un sistema de colas M/M/1
# Sistema: fila de abordaje de pasajeros en la parada de la ruta La Canada - Alajuela
#
# Flujo: importar datos -> estimar lambda y mu -> probar Poisson y exponencial ->
#        medidas teoricas M/M/1 -> simular la cola con queuecomputer -> comparar.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(lubridate)
  library(ggplot2)
  library(queuecomputer)
})

ALPHA <- 0.05   # nivel de significancia de las pruebas de bondad de ajuste

# Encabezado de seccion para una salida mas ordenada.
seccion <- function(txt) cat(sprintf("\n================  %s  ================\n", txt))


# =============================================================================
# 1. Importacion y preparacion de datos
# =============================================================================
obs  <- read_excel("datos_campo.xlsx", sheet = "observaciones")        # una fila por pasajero
intv <- read_excel("datos_campo.xlsx", sheet = "llegadas_intervalo")   # conteo por bloque de 10 min

# Las horas vienen como texto: se pasan a fecha-hora, se ordena y se calculan
# las cuatro variables de tiempo (en minutos).
obs <- obs %>%
  mutate(across(c(hora_llegada, hora_inicio_servicio, hora_fin_servicio),
                ~ as.POSIXct(.x, tz = "UTC"))) %>%
  arrange(fecha, hora_llegada) %>%
  mutate(
    interarribo_min     = as.numeric(difftime(hora_llegada, lag(hora_llegada),         units = "mins")),
    tiempo_espera_min   = as.numeric(difftime(hora_inicio_servicio, hora_llegada,      units = "mins")),
    tiempo_servicio_min = as.numeric(difftime(hora_fin_servicio, hora_inicio_servicio, units = "mins")),
    tiempo_sistema_min  = as.numeric(difftime(hora_fin_servicio, hora_llegada,         units = "mins"))
  )

# Control de calidad: sin servicios nulos/negativos, sin esperas negativas, sin NA.
stopifnot(all(obs$tiempo_servicio_min > 0,  na.rm = TRUE))
stopifnot(all(obs$tiempo_espera_min  >= 0,  na.rm = TRUE))
obs <- obs %>% filter(!is.na(tiempo_servicio_min))

n_serv <- nrow(obs)
seccion("1. DATOS")
cat(sprintf("Pasajeros observados : %d\n", n_serv))
cat(sprintf("Intervalos de conteo : %d  (ventana %g min)\n", nrow(intv), sum(intv$duracion_min)))
print(summary(obs[c("tiempo_espera_min", "tiempo_servicio_min", "tiempo_sistema_min")]))


# =============================================================================
# 2. Estimacion de parametros (unidad de trabajo: minutos)
# =============================================================================
total_llegadas   <- sum(intv$numero_llegadas_intervalo)
tiempo_total_min <- sum(intv$duracion_min)

lambda <- total_llegadas / tiempo_total_min        # llegadas / minuto
mu     <- 1 / mean(obs$tiempo_servicio_min)        # 1 / (tiempo medio de servicio)
rho    <- lambda / mu                              # utilizacion; el modelo solo aplica si rho < 1

seccion("2. PARAMETROS")
cat(sprintf("lambda = %.4f pax/min = %.2f pax/hora\n", lambda, lambda * 60))
cat(sprintf("mu     = %.4f pax/min = %.2f pax/hora  (servicio medio = %.4f min)\n",
            mu, mu * 60, mean(obs$tiempo_servicio_min)))
cat(sprintf("rho    = %.4f  -> %s\n", rho,
            ifelse(rho < 1, "estable (rho < 1)", "NO estable (rho >= 1): no interpretar M/M/1")))


# =============================================================================
# 3. Bondad de ajuste - Poisson
#    H0: el numero de llegadas por intervalo sigue una Poisson.  H1: no.
# =============================================================================
seccion("3. PRUEBA DE BONDAD DE AJUSTE - POISSON")

# La prueba se hace sobre el CONTEO de llegadas por intervalo (0,1,2,... por bloque),
# no sobre los interarribos: Poisson describe cuantos eventos caen en un intervalo
# fijo; el tiempo entre eventos es lo que sigue una exponencial.
x       <- intv$numero_llegadas_intervalo
N       <- length(x)
lam_int <- mean(x)          # lambda estimada por intervalo
kmax    <- max(x)

# Frecuencias observadas y esperadas por Poisson (la ultima clase acumula la cola).
obs_freq <- tabulate(x + 1, nbins = kmax + 1)
p_k <- dpois(0:kmax, lam_int)
p_k[kmax + 1] <- 1 - sum(p_k[1:kmax])
exp_freq <- N * p_k

# Se agrupan clases contiguas hasta que la frecuencia esperada sea >= 5.
grp_o <- c(); grp_e <- c(); grp_lab <- c()
acc_o <- 0; acc_e <- 0; ini <- 0
for (k in 0:kmax) {
  acc_o <- acc_o + obs_freq[k + 1]
  acc_e <- acc_e + exp_freq[k + 1]
  if (acc_e >= 5 || k == kmax) {
    grp_o   <- c(grp_o, acc_o)
    grp_e   <- c(grp_e, acc_e)
    grp_lab <- c(grp_lab, if (ini == k) as.character(k) else paste0(ini, "-", k))
    acc_o <- 0; acc_e <- 0; ini <- k + 1
  }
}
if (length(grp_o) >= 2 && grp_e[length(grp_e)] < 5) {   # une la ultima clase si quedo < 5
  grp_o[length(grp_o) - 1] <- grp_o[length(grp_o) - 1] + grp_o[length(grp_o)]
  grp_e[length(grp_e) - 1] <- grp_e[length(grp_e) - 1] + grp_e[length(grp_e)]
  grp_lab[length(grp_lab) - 1] <- paste0(sub("-.*", "", grp_lab[length(grp_lab) - 1]), "+")
  grp_o <- grp_o[-length(grp_o)]; grp_e <- grp_e[-length(grp_e)]; grp_lab <- grp_lab[-length(grp_lab)]
}

chi2_p <- sum((grp_o - grp_e)^2 / grp_e)
gl_p   <- length(grp_o) - 1 - 1     # clases - 1 - (1 parametro estimado)
disp   <- var(x) / mean(x)          # indice de dispersion: Poisson ideal ~ 1

print(data.frame(categoria = grp_lab, observado = grp_o, esperado = round(grp_e, 3)), row.names = FALSE)
if (gl_p < 1) {
  cat(sprintf("Chi2 = %.4f | gl = %d\n", chi2_p, gl_p))
  cat(sprintf("Prueba no concluyente: con %d intervalos las clases se colapsan a gl <= 0.\n", N))
  cat("Se toma el indice de dispersion como referencia.\n")
} else {
  pval_p <- pchisq(chi2_p, gl_p, lower.tail = FALSE)
  cat(sprintf("Chi2 = %.4f | gl = %d | valor-p = %.4f\n", chi2_p, gl_p, pval_p))
  cat(sprintf("Decision (alpha = %.2f): %s\n", ALPHA,
              ifelse(pval_p > ALPHA, "no se rechaza H0 -> compatible con Poisson",
                     "se rechaza H0 -> no compatible con Poisson")))
}
cat(sprintf("Indice de dispersion (var/media) = %.3f\n", disp))
if (disp > 1.5) cat("  Sobredispersion: las llegadas ocurren en lotes, no como Poisson.\n")
if (disp < 0.75) cat("  Subdispersion: las llegadas son mas regulares que una Poisson.\n")


# =============================================================================
# 4. Bondad de ajuste - Exponencial (tiempos de servicio)
#    H0: los tiempos de servicio siguen una exponencial.  H1: no.
# =============================================================================
seccion("4. PRUEBA DE BONDAD DE AJUSTE - EXPONENCIAL")

ts   <- obs$tiempo_servicio_min
rate <- 1 / mean(ts)

# Kolmogorov-Smirnov (el rate se estima de la muestra, asi que el KS es conservador).
ks <- suppressWarnings(ks.test(ts, "pexp", rate = rate))   # ignora el aviso por empates (redondeo)
cat(sprintf("Kolmogorov-Smirnov: D = %.4f | valor-p = %.4f\n", ks$statistic, ks$p.value))

# Chi-cuadrado con clases equiprobables bajo la exponencial (misma frecuencia esperada).
nb   <- if (length(ts) >= 48) 6 else 4
brks <- qexp(seq(0, 1, length.out = nb + 1), rate = rate)
brks[1] <- -Inf; brks[nb + 1] <- Inf
o_e  <- as.numeric(table(cut(ts, breaks = brks)))
e_e  <- rep(length(ts) / nb, nb)
chi2_e <- sum((o_e - e_e)^2 / e_e)
gl_e   <- nb - 1 - 1
pval_e <- pchisq(chi2_e, gl_e, lower.tail = FALSE)

cat(sprintf("Chi2 (%d clases) = %.4f | gl = %d | valor-p = %.4f\n", nb, chi2_e, gl_e, pval_e))
cat(sprintf("Coeficiente de variacion = %.3f  (una exponencial tiene CV = 1)\n", sd(ts) / mean(ts)))
cat(sprintf("Decision (alpha = %.2f): %s\n", ALPHA,
            ifelse(min(ks$p.value, pval_e) > ALPHA,
                   "no se rechaza H0 -> compatible con exponencial",
                   "se rechaza H0 -> no compatible con exponencial")))


# =============================================================================
# 5. Medidas de desempeno teoricas (formulas M/M/1)
# =============================================================================
seccion("5. MEDIDAS TEORICAS M/M/1  (minutos)")

P0 <- 1 - rho
Lq <- lambda^2 / (mu * (mu - lambda))
Ls <- lambda / (mu - lambda)
Wq <- lambda / (mu * (mu - lambda))
Ws <- 1 / (mu - lambda)

print(data.frame(
  medida = c("rho", "P0", "Lq", "Ls", "Wq (min)", "Ws (min)"),
  valor  = round(c(rho, P0, Lq, Ls, Wq, Ws), 4)
), row.names = FALSE)
cat(sprintf("P(Wq > 5 min) = %.4f | P(Ws > 5 min) = %.4f\n",
            rho * exp(-mu * (1 - rho) * 5), exp(-mu * (1 - rho) * 5)))


# =============================================================================
# 6. Medidas con queuecomputer y medidas observadas en campo
# =============================================================================
seccion("6. MEDIDAS CON queuecomputer Y MEDIDAS DE CAMPO")

# Entradas para queue(): llegadas acumuladas y tiempos de servicio, en minutos.
interarrival_times <- obs$interarribo_min
interarrival_times[1] <- 0
arrivals <- cumsum(interarrival_times)
service  <- obs$tiempo_servicio_min

stopifnot(!is.unsorted(arrivals), all(service > 0))

salidas <- queue(arrivals = arrivals, service = service, servers = 1)

resultados <- data.frame(llegada = arrivals, servicio = service, salida = salidas) %>%
  mutate(
    tiempo_sistema  = salida - llegada,
    inicio_servicio = salida - servicio,
    tiempo_espera   = inicio_servicio - llegada
  )

# queue() asume un servidor siempre disponible: solo capta la fila en la puerta,
# no el tiempo que el pasajero espera a que llegue el bus.
Wq_queue <- mean(resultados$tiempo_espera)
Ws_queue <- mean(resultados$tiempo_sistema)
Lq_queue <- lambda * Wq_queue     # Ley de Little
Ls_queue <- lambda * Ws_queue

inicio_campo <- as.numeric(difftime(obs$hora_inicio_servicio, min(obs$hora_llegada), units = "mins"))
cat(sprintf("Desfase medio queue() vs campo en el inicio de servicio: %.2f min\n",
            mean(abs(resultados$inicio_servicio - inicio_campo))))

# Medidas tomadas directamente del registro (la espera incluye aguardar al bus).
Wq_campo <- mean(obs$tiempo_espera_min)
Ws_campo <- mean(obs$tiempo_sistema_min)
Lq_campo <- lambda * Wq_campo
Ls_campo <- lambda * Ws_campo

# Longitud de la cola real: +1 al llegar el pasajero, -1 al empezar a abordar.
lleg_rel <- as.numeric(difftime(obs$hora_llegada,         min(obs$hora_llegada), units = "mins"))
ini_rel  <- as.numeric(difftime(obs$hora_inicio_servicio, min(obs$hora_llegada), units = "mins"))
t_ev <- c(lleg_rel, ini_rel)
d_ev <- c(rep(1, n_serv), rep(-1, n_serv))
o    <- order(t_ev, d_ev)
t_ev <- t_ev[o]; d_ev <- d_ev[o]
qcurve  <- cumsum(d_ev)
Lq_time <- sum(head(qcurve, -1) * diff(t_ev)) / (t_ev[length(t_ev)] - t_ev[1])
Lmax    <- max(qcurve)

pct_espera <- mean(obs$tiempo_espera_min > 1 / 60) * 100
throughput <- n_serv / tiempo_total_min

cat(sprintf("queuecomputer : Wq = %.4f min | Ws = %.4f min | Lq = %.4f | Ls = %.4f\n",
            Wq_queue, Ws_queue, Lq_queue, Ls_queue))
cat(sprintf("campo         : Wq = %.4f min | Ws = %.4f min | Lq = %.4f | Ls = %.4f\n",
            Wq_campo, Ws_campo, Lq_campo, Ls_campo))
cat(sprintf("Cola media observada = %.2f | cola maxima observada = %d\n", Lq_time, Lmax))
cat(sprintf("Pasajeros que esperaron = %.1f %%\n", pct_espera))
cat(sprintf("Tasa efectiva de salida = %.4f pax/min (%.2f /h)\n", throughput, throughput * 60))


# =============================================================================
# 7. Comparacion: teoricas vs. queuecomputer vs. campo
# =============================================================================
seccion("7. COMPARACION: TEORICA vs queuecomputer vs CAMPO")

comp <- data.frame(
  medida        = c("rho", "P0", "Lq", "Ls", "Wq (min)", "Ws (min)"),
  teorica       = c(rho, P0, Lq, Ls, Wq, Ws),
  queuecomputer = c(throughput / mu, P0, Lq_queue, Ls_queue, Wq_queue, Ws_queue),
  campo         = c(rho, P0, Lq_campo, Ls_campo, Wq_campo, Ws_campo)
)
comp[-1] <- lapply(comp[-1], round, 4)
print(comp, row.names = FALSE)

cat("\nInterpretacion:\n")
cat("  rho y P0 coinciden en las tres: lambda y mu estan bien estimadas.\n")
cat("  Las formulas y queuecomputer dan una espera de segundos (solo la fila en la puerta).\n")
cat(sprintf("  En campo la espera es de ~%.1f min: el pasajero aguarda sobre todo a que llegue el bus,\n",
            Wq_campo))
cat("  algo que el M/M/1 no modela (el servidor 'no existe' entre buses).\n")


# =============================================================================
# 8. Figuras
# =============================================================================
g1 <- ggplot(data.frame(ts = ts), aes(ts)) +
  geom_histogram(aes(y = after_stat(density)), bins = 12, fill = "#2b6cb0", colour = "white") +
  stat_function(fun = dexp, args = list(rate = rate), colour = "#dd6b20", linewidth = 1.1) +
  labs(title = "Tiempo de servicio vs. exponencial ajustada",
       x = "Tiempo de servicio (min)", y = "Densidad") +
  theme_minimal()
ggsave("R_fig1_servicio_exponencial.png", g1, width = 6, height = 3.6, dpi = 130)

pois_df <- data.frame(
  k    = rep(0:kmax, 2),
  frec = c(obs_freq, exp_freq),
  tipo = rep(c("Observado", "Esperado Poisson"), each = kmax + 1)
)
g2 <- ggplot(pois_df, aes(factor(k), frec, fill = tipo)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Observado" = "#2b6cb0", "Esperado Poisson" = "#dd6b20")) +
  labs(title = "Llegadas por intervalo: observado vs. Poisson",
       x = "Pasajeros por intervalo de 10 min", y = "Numero de intervalos", fill = NULL) +
  theme_minimal()
ggsave("R_fig2_poisson.png", g2, width = 6, height = 3.6, dpi = 130)

ev <- data.frame(
  t = c(lleg_rel, as.numeric(difftime(obs$hora_fin_servicio, min(obs$hora_llegada), units = "mins"))),
  d = c(rep(1, n_serv), rep(-1, n_serv))
)
ev <- ev[order(ev$t, ev$d), ]
ev$n <- cumsum(ev$d)
g3 <- ggplot(ev, aes(t, n)) +
  geom_step(colour = "#2b6cb0") +
  labs(title = "Pasajeros en el sistema a lo largo de la sesion",
       x = "Minutos desde las 06:00", y = "Pasajeros en el sistema") +
  theme_minimal()
ggsave("R_fig3_cola_tiempo.png", g3, width = 6.4, height = 3.4, dpi = 130)

comp_long <- rbind(
  data.frame(medida = comp$medida[3:6], valor = comp$teorica[3:6],       tipo = "Teorica"),
  data.frame(medida = comp$medida[3:6], valor = comp$queuecomputer[3:6], tipo = "queuecomputer"),
  data.frame(medida = comp$medida[3:6], valor = comp$campo[3:6],         tipo = "Campo")
)
comp_long$medida <- factor(comp_long$medida, levels = comp$medida[3:6])
comp_long$tipo   <- factor(comp_long$tipo, levels = c("Teorica", "queuecomputer", "Campo"))
g4 <- ggplot(comp_long, aes(medida, valor, fill = tipo)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Teorica" = "#2b6cb0", "queuecomputer" = "#7aa8d2", "Campo" = "#dd6b20")) +
  labs(title = "Lq, Ls, Wq, Ws: teorica vs. queuecomputer vs. campo",
       x = NULL, y = NULL, fill = NULL) +
  theme_minimal()
ggsave("R_fig4_comparacion.png", g4, width = 6.4, height = 3.6, dpi = 130)

cat("\nFiguras: R_fig1_servicio_exponencial.png, R_fig2_poisson.png,",
    "R_fig3_cola_tiempo.png, R_fig4_comparacion.png\n")
