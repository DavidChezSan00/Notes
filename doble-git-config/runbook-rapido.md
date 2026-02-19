# Runbook rapido - doble cuenta GitHub (work + personal)

## Archivos clave
- `~/.gitconfig`
- `~/.gitconfig-work`
- `~/.gitconfig-personal`
- `~/.git-credentials`
- `~/Documentos/repos/personal/Notes/.git/config`

## Como esta montado
- Repos work en `~/Documentos/repos/...` usan `~/.gitconfig-work` via `includeIf`.
- Repos personales en `~/Documentos/repos/personal/...` usan `~/.gitconfig-personal` via `includeIf`.
- `Notes` fuerza credencial personal con:
  - `credential.useHttpPath=true`
  - `credential.username=DavidChezSan00`
- `~/.git-credentials` guarda:
  - credencial global de work para `github.com`
  - credencial especifica personal para `github.com/DavidChezSan00/Notes.git`

## Verificacion rapida
```bash
git -C ~/Documentos/repos/ansible config --show-origin --get user.email
git -C ~/Documentos/repos/personal/Notes config --show-origin --get user.email
git -C ~/Documentos/repos/personal/Notes config --local --get-regexp '^credential\.'
```

## Si falla push en Notes (usa cuenta work por error)
```bash
git -C ~/Documentos/repos/personal/Notes config --local credential.useHttpPath true
git -C ~/Documentos/repos/personal/Notes config --local credential.username DavidChezSan00
```

## Si anades un repo work nuevo
- Agregar en `~/.gitconfig` un bloque `includeIf "gitdir:/ruta/repo/"` apuntando a `~/.gitconfig-work`.

## Seguridad
- Si un PAT se expone, revocarlo y crear uno nuevo.
- Actualizar `~/.git-credentials` con el nuevo token.
