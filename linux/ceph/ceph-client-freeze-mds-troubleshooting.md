# Ceph client freeze al abrir data ticket (MDS troubleshooting)

## Sintoma
Un usuario reporta que al acceder a `cephXX` y abrir una data ticket, la pantalla se queda congelada o bloqueada.

## Objetivo
Identificar si el bloqueo viene de sesiones MDS, OSD o cliente MDS en el Ceph afectado.

## Pasos
- Identificar el Ceph afectado y obtener su ID unica con `ceph -s`.
- Entrar en debugfs del cliente Ceph correspondiente con `cd /sys/kernel/debug/ceph/<ID_UNICA_CEPH>/`.
- Revisar sesiones MDS con `cat mds_sessions`.

## Interpretacion de `mds_sessions`
- Si aparece algun estado distinto de `open`, hay fallo en MDS.
- Si todo esta en `open`, revisar `osdc` y `mdsc`.

## Accion si hay fallo MDS
Conectarse al Ceph afectado y marcar el MDS con problema para failover con `ceph mds fail <RANK_O_ID>`.

Repetir hasta que los MDS queden balanceados y en estado `active`.

## Si `mds_sessions` esta correcto
- Revisar `cat osdc`.
- Revisar `cat mdsc`.

- `osdc`: puede mostrar OSD atascado.
- `mdsc`: puede mostrar el MDS/proceso donde se queda pillado el cliente.
