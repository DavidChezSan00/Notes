# Ceph en rojo con `ceph -s` OK y `ceph fs status` OK (perfil mclock activo)

## Sintoma
El reporte diario de Ceph aparece en rojo, pero:
- `ceph -s` sale OK.
- `ceph fs status` tambien sale correcto.

## Que revisar
Despues de ejecutar `ceph fs status`, comprobar si aparece un bloque como este:
> [osd_mclock_profile]  
> Good value: balanced  
> Actual value: high_recovery_ops  
> Impact: Incorrect QoS scheduling. May cause unbalanced I/O prioritization affecting client performance.

## Interpretacion
Si aparece ese aviso, hay un perfil mclock activo (por ejemplo `high_recovery_ops`) que prioriza tareas de recovery/backfill.

Esto suele ocurrir cuando:
- se reemplaza un disco fallido
- se anade un nodo nuevo

## Condicion previa para quitar el perfil
Antes de retirarlo, validar que en `ceph -s` no haya PGs:
- `degraded`
- `displaced`

## Accion correctiva
Quitar la clave del perfil activo con `ceph config rm osd osd_mclock_profile`.

## Verificacion
- Ejecutar de nuevo `ceph -s`.
- Revisar `ceph fs status`.
- Confirmar que ya no aparece el aviso de perfil activo no deseado.
