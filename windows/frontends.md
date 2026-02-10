# Frontends

## Regedit ProfileList
Ruta:
```
Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList
```

Notas:
- Si un usuario tiene el escritorio remoto congelado o deja de entrar a la maquina, revisar esta ruta.
- En este caso va junto con los comandos de Chocolatey (son cosas diferentes, pero aqui se usan juntas).

## Chocolatey (junto al caso anterior)
```
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco source add -n=VDP -s "https://nexus.vdp-prod.local/repository/Chocolatey/" --priority=1 --allow-unofficial -y
```
