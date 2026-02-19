```
## Si una vez alguien se queja de que han accedido al cephXX pero al leer una data ticket se les queda pillado o se les queda congelada la pantalla
## Si pasa esto hay que revisar:

cd /sys/kernel/debug/ceph/XXXXXXXXXXXXXXXXXXXXXXX

## Esta ruta depende de que CEPHXX esta mirando, para comprobar en que CEPH se necesita mirar, revisar el CEPH en cuestyo con un

ceph -s
## Aqui aparece una ID que es unico en cada CEPH

cd /sys/kernel/debug/ceph/XXXXXXXXXXXXXXXXXXXXXXX/
## Aqui dentro hay varios ficheros donde mirar, el primero hay que mirar el fichero con el nombre

mds_sessions
## Si aqui dentro aparece algo numero con un estado que no sea

open

## hay un fallo en los MDS de ese CEPH, hay que conectarse a ese CEPH en cuestion y ejecutar el comanod

ceph mds fail X

## Hasta que este balanceado los MDS y en active todos.

## Si miras este fichero y todo esta bien, hay que mirar los ficheros

osdc
## aqui podremos encontrar o el osd que se ha quedado pillado

# O
mdsc
## aqui podremos encontrar el mds o el proceso donde se ha quedado pillado el CEPH en cuestion


