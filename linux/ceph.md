SI el reporte diario de CEPH, aaprece en rojo pero el "ceph-s", da OK y el "ceph fs status" tamb esta bien, hay que ver si despues del "ceph fs status"
hay algo como esto
[osd_mclock_profile]
Good value: balanced
Actual value: high_recovery_ops
Impact: Incorrect QoS scheduling. May cause unbalanced I/O prioritization affecting client performance.

si aparece algo asi, es que esta aplicado un perfil, en este caso, este perfil prioriza las actividades de backfill
esto se suele aplicar cuando se ha reemplazado un disco fallido o se ha añadido un nodo.

La clave para poder quitar este profile activo, es que en el "ceph -s" no aparezcan ni PGs en displaced ni en degraded

si esto se cumple, hay que ejecutar los siguientes comandos:
ceph config rm osd <nombre del perfil aplicado>, en este caso "osd_mclock_profile"
