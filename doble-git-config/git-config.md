# GitHub dual-account setup (work + personal)

## Objetivo
Tener dos cuentas de GitHub en la misma CLI:
- Cuenta **work** para repos de trabajo.
- Cuenta **personal** para el repo `Notes` dentro de `Documentos/repos/personal/`.

La configuracion separa:
- **Identidad Git** (`user.name`, `user.email`) por ruta.
- **Autenticacion HTTP** (PAT) por host/repositorio cuando hace falta.

## Estructura final

### 1) Config global
Archivo: `/home/david/.gitconfig`

Contenido actual:

```ini
[credential]
	helper = store
[includeIf "gitdir:/home/david/Documentos/repos/IT-DevOps-Code/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/analyst-utils/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/ansible/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/at_rad_api/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/chocolatey/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/foreman/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/impacket/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/terraform-account-details/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/vdp-cli-python/"]
	path = /home/david/.gitconfig-work
[includeIf "gitdir:/home/david/Documentos/repos/personal/"]
	path = /home/david/.gitconfig-personal
```

Que hace:
- Usa `credential.helper=store` para guardar credenciales HTTP en `~/.git-credentials`.
- Aplica `~/.gitconfig-work` a los repos de trabajo listados.
- Aplica `~/.gitconfig-personal` a todo lo que cuelga de `Documentos/repos/personal/`.

### 2) Perfil work
Archivo: `/home/david/.gitconfig-work`

Contenido actual:

```ini
[user]
	email = david.sanchez@vexcelgroup.com
	name = DavidSanchez00
```

Que hace:
- Define identidad de commits para repos work.

### 3) Perfil personal
Archivo: `/home/david/.gitconfig-personal`

Contenido actual:

```ini
[user]
	name = DavidChezSan00
	email = davidchezsan00@gmail.com
```

Que hace:
- Define identidad de commits para repos personales.

### 4) Excepcion local solo para Notes
Archivo: `/home/david/Documentos/repos/personal/Notes/.git/config`

Valores locales activos:

```ini
credential.useHttpPath=true
credential.username=DavidChezSan00
```

Que hace:
- `credential.useHttpPath=true` obliga a diferenciar credenciales por **host+path**.
- `credential.username=DavidChezSan00` fuerza que `Notes` use el usuario personal.

Esto evita que Notes tome la credencial global de work.

### 5) Credenciales HTTP
Archivo: `/home/david/.git-credentials`

Ejemplo del estado actual (tokens ocultos):

```text
https://DavidChezSan00:***@github.com/DavidChezSan00/Notes.git
https://DavidSanchez00:***@github.com
```

Que hace:
- Credencial global para `github.com` -> cuenta work.
- Credencial especifica para `github.com/DavidChezSan00/Notes.git` -> cuenta personal.

## Pasos que se siguieron para llegar a esta configuracion

1. Se definieron identidades separadas usando `includeIf` por ruta.
2. Se movio la identidad work a `~/.gitconfig-work`.
3. Se creo `~/.gitconfig-personal` con nombre/email personales.
4. Se agrego include para `Documentos/repos/personal/`.
5. Se detecto error 403 en `Notes` por autenticacion con cuenta work.
6. Se fijo `origin` de `Notes` al repo personal (`DavidChezSan00/Notes.git`).
7. Se guardo credencial especifica de `Notes`.
8. Se activo en `Notes` `credential.useHttpPath=true` y `credential.username=DavidChezSan00`.
9. Se comprobo que `ansible` funciona con credencial work y `Notes` con personal.

## Comandos de verificacion

### Identidad efectiva en un repo work
```bash
git -C /home/david/Documentos/repos/ansible config --show-origin --get user.name
git -C /home/david/Documentos/repos/ansible config --show-origin --get user.email
```

### Identidad efectiva en Notes (personal)
```bash
git -C /home/david/Documentos/repos/personal/Notes config --show-origin --get user.name
git -C /home/david/Documentos/repos/personal/Notes config --show-origin --get user.email
```

### Reglas de credencial en Notes
```bash
git -C /home/david/Documentos/repos/personal/Notes config --local --get-regexp '^credential\.'
```

### Confirmar remotos
```bash
git -C /home/david/Documentos/repos/ansible remote -v
git -C /home/david/Documentos/repos/personal/Notes remote -v
```

## Comportamiento esperado
- En repos work: commits firmados con identidad work y push/pull con token work.
- En `Notes`: commits con identidad personal y push/pull con credencial personal del path de Notes.

## Mantenimiento rapido
- Si anades un repo work nuevo en `Documentos/repos/`, agrega su bloque `includeIf` a `~/.gitconfig` apuntando a `~/.gitconfig-work`.
- Si creas otro repo personal con credenciales separadas por path, habilita en ese repo:
  - `git config --local credential.useHttpPath true`
  - `git config --local credential.username <usuario_personal>`

## Seguridad
Los PAT usados durante esta configuracion se compartieron en texto plano durante la sesion. Recomendado:
1. Revocar ambos tokens en GitHub (`Settings -> Developer settings -> Personal access tokens`).
2. Crear nuevos tokens.
3. Actualizar `~/.git-credentials` con los nuevos valores.
