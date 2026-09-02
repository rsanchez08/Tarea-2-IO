"""
analisis_referencia.py  -  verificacion en Python de los numeros del informe.
Datos del grupo: 85 pasajeros, parada La Canada -> Alajuela, 2026-08-31.
Compara TRES cosas:
  (T) medidas teoricas M/M/1
  (Q) medidas que produce queuecomputer::queue()  (servidor M/M/1 siempre disponible)
  (C) medidas observadas DIRECTAMENTE en el registro de campo
"""
import numpy as np, pandas as pd
from scipy import stats

obs = pd.read_csv("datos_campo_observaciones.csv",
                  parse_dates=["hora_llegada", "hora_inicio_servicio", "hora_fin_servicio"])
intv = pd.read_csv("datos_campo_llegadas_intervalo.csv")
obs = obs.sort_values("hora_llegada").reset_index(drop=True)

ia  = obs.hora_llegada.diff().dt.total_seconds() / 60
esp = (obs.hora_inicio_servicio - obs.hora_llegada).dt.total_seconds() / 60      # incluye la espera del BUS
srv = (obs.hora_fin_servicio - obs.hora_inicio_servicio).dt.total_seconds() / 60
sis = (obs.hora_fin_servicio - obs.hora_llegada).dt.total_seconds() / 60

print("=" * 62, "\n1. DATOS\n", "=" * 62, sep="")
print(f"pasajeros = {len(obs)} | buses = {obs.id_bus.nunique()} | intervalos = {len(intv)} (10 min)")
print(f"interarribo:  media {ia.mean():.3f}  sd {ia.std(ddof=1):.3f}  max {ia.max():.2f}")
print(f"espera:       media {esp.mean():.4f}  sd {esp.std(ddof=1):.4f}  min {esp.min():.2f}  max {esp.max():.2f}")
print(f"servicio:     media {srv.mean():.4f}  sd {srv.std(ddof=1):.4f}  min {srv.min():.2f}  max {srv.max():.2f}  CV {srv.std(ddof=1)/srv.mean():.3f}")
print(f"sistema:      media {sis.mean():.4f}  sd {sis.std(ddof=1):.4f}  max {sis.max():.2f}")

print("\n" + "=" * 62, "\n2. PARAMETROS (minutos)\n", "=" * 62, sep="")
Tobs = intv.duracion_min.sum()
lam = intv.numero_llegadas_intervalo.sum() / Tobs
mu = 1 / srv.mean()
rho = lam / mu
print(f"lambda = {lam:.5f} pax/min = {lam*60:.2f} pax/h   ({intv.numero_llegadas_intervalo.sum()} pax / {Tobs} min)")
print(f"servicio medio = {srv.mean():.5f} min -> mu = {mu:.5f} pax/min = {mu*60:.2f} pax/h")
print(f"rho = {rho:.5f}  -> {'ESTABLE' if rho < 1 else 'NO ESTABLE'}")

print("\n" + "=" * 62, "\n3. POISSON (pasajeros por intervalo de 10 min, N=15)\n", "=" * 62, sep="")
x = intv.numero_llegadas_intervalo.to_numpy()
print(f"lambda por intervalo = {x.mean():.4f}   frecuencias: " +
      "  ".join(f"{k}->{int((x==k).sum())}" for k in range(x.max()+1) if (x==k).any()))
print(f"indice de dispersion var/media = {x.var(ddof=0)/x.mean():.3f} (pobl) / {x.var(ddof=1)/x.mean():.3f} (muestral)  [Poisson=1]")
print("  -> sobredispersion: llegadas EN LOTES (un grupo de pasajeros por bus).")

print("\n" + "=" * 62, "\n4. EXPONENCIAL (tiempo de servicio, n=85)\n", "=" * 62, sep="")
ts = srv.to_numpy(); rate = 1 / ts.mean()
ks = stats.kstest(ts, "expon", args=(0, ts.mean()))
print(f"rate = {rate:.4f}   CV = {ts.std(ddof=1)/ts.mean():.3f}   KS: D = {ks.statistic:.4f}  p = {ks.pvalue:.3g}")
nb = 6
q = stats.expon.ppf(np.linspace(0, 1, nb + 1), scale=ts.mean()); q[0], q[-1] = -np.inf, np.inf
oe = np.histogram(ts, bins=q)[0].astype(float); ee = np.full(nb, len(ts) / nb)
c2 = ((oe - ee) ** 2 / ee).sum()
print(f"chi2 ({nb} clases) = {c2:.2f} | gl = {nb-2} | p = {stats.chi2.sf(c2, nb-2):.3g}")
print("  -> servicio casi constante (CV bajo): NO es exponencial.")

print("\n" + "=" * 62, "\n5. MEDIDAS: (T) teorico M/M/1  vs  (Q) queue()  vs  (C) campo\n", "=" * 62, sep="")
# (T) teoricas
P0 = 1 - rho
LqT = lam**2 / (mu*(mu-lam)); LsT = lam/(mu-lam); WqT = lam/(mu*(mu-lam)); WsT = 1/(mu-lam)

# (Q) queuecomputer: servidor SIEMPRE disponible, FIFO
a = (obs.hora_llegada - obs.hora_llegada.min()).dt.total_seconds().to_numpy()/60
s = ts.copy()
ini = np.zeros(len(a)); fin = np.zeros(len(a)); libre = 0.0
for i in range(len(a)):
    ini[i] = max(a[i], libre); fin[i] = ini[i] + s[i]; libre = fin[i]
WqQ = (ini - a).mean(); WsQ = (fin - a).mean()
LqQ = lam * WqQ; LsQ = lam * WsQ

# (C) campo: lo que realmente se observo
WqC = esp.mean(); WsC = sis.mean()
LqC = lam * WqC; LsC = lam * WsC

tab = pd.DataFrame({
    "medida":       ["rho", "P0", "Lq", "Ls", "Wq (min)", "Ws (min)"],
    "T_teorico":    [rho, P0, LqT, LsT, WqT, WsT],
    "Q_queue":      [len(obs)/Tobs/mu, P0, LqQ, LsQ, WqQ, WsQ],
    "C_campo":      [rho, P0, LqC, LsC, WqC, WsC],
})
print(tab.round(4).to_string(index=False))
print(f"\nqueue():  {(ini-a>1/60).sum()} de {len(a)} pasajeros esperaron ; cola max (temporal) = ", end="")
tev = np.concatenate([a, ini]); dev = np.concatenate([np.ones(len(a)), -np.ones(len(a))])
o = np.lexsort((dev, tev)); print(int(np.cumsum(dev[o]).max()))
print(f"campo:    {(esp>1/60).sum()} de {len(esp)} pasajeros esperaron (>1s) ; espera media {WqC:.2f} min")
print(f"\nDESFASE queue() vs campo en inicio_servicio: media {np.mean(np.abs(ini - (obs.hora_inicio_servicio-obs.hora_llegada.min()).dt.total_seconds().to_numpy()/60)):.2f} min")
print("  -> queue() (servidor siempre activo) NO reproduce la espera por el bus; por eso Wq_Q << Wq_C.")
