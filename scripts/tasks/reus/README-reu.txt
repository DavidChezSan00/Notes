Notas rápidas sobre scripts de reuniones (+reu)

- Ubicación: Documentos/scripts/tasks/reus/
- Scripts:
  - reunew → reu-helper.sh: crea reunión. Pide título, fecha (día/mes/año con valores por defecto del día actual), proyecto (por defecto 'Reunion'), nota opcional. Añade tags +meeting +reu. Due se guarda en Taskwarrior.
  - reulist → reu-list.sh: lista reuniones (tag +reu) con columnas Date/Project/Description, sin ID. Notas se muestran indentadas. Formato de fecha dd/mm/yyyy calculado en local (convierte due con Z desde UTC a hora local).
  - reumod → reu-mod.sh: muestra reuniones con color; permite cambiar descripción, proyecto (Enter mantiene, '-' quita), y fecha. Usa el list_json ya obtenido para leer el due actual; al aplicar, siempre re-aplica tags +meeting +reu. Si la fecha nueva coincide en UTC con la existente, Taskwarrior puede responder "Modified 0 tasks".
  - reudel → reu-del.sh: lista reuniones con color y borra la seleccionada (delete sobre ID).

- Integración con task-daily.sh:
  - Las tareas con tag +reu no se muestran en la tabla principal ni en el resumen.
  - Solo aparecen en la sección “Reuniones” si la due, convertida a local, coincide con la fecha de hoy.

- Detalles de fechas:
  - Se parsean formatos Taskwarrior: %Y%m%dT%H%M%SZ (UTC), %Y-%m-%d, %Y%m%d.
  - Para valores con Z se hace tz=UTC → local; la visualización es dd/mm/yyyy.
  - Diferencias UTC/local pueden hacer que un due 09/12 23:00Z se muestre como 10/12 local.

- Autocompletado/alias:
  - Alias en ~/.bashrc: reunew, reulist, reumod, reudel apuntan a scripts en reus/.
  - El completion general sigue funcionando (se basa en los alias).

- Ocultación en tasklist/task-daily:
  - Se ocultan todas las tareas con tag +reu (no solo el proyecto) en listados normales de tareas.

- Consejos:
  - Si Taskwarrior muestra "Modified 0 tasks" al cambiar fecha, verifica que el due nuevo sea diferente en UTC al existente.
  - Para asignar color, el proyecto de la reunión puede ser cualquiera; los mapeados en common_task.py incluyen Windows, Synology, Chocolatey, Network, Ansible, Reunion, etc., y los nuevos usan paleta determinista.
