# Chocolatey

## Agregar source interno (cuando falla instalacion de plataforma)
```
choco source add -n=VDP -s "https://nexus.vdp-prod.local/repository/Chocolatey/" --priority=1 --allow-unofficial -y
```

Notas:
- Origen interno para instalaciones de plataforma de Chocolatey.
