# Comandos generales

## Permisos (ACL)
```
setfacl -R --set-file=permisos.facl /ruta/al/directorio
```
Notas:
- En todos los FS (segun nota original).

## LVM (extender volumen)
```
lvextend -L +XXXG /dev/ubuntu-vg/docker-lv
resize2fs /dev/mapper/ubuntu--vg-docker--lv
```

## LVM (revisar espacio)
```
vgs
```
