#!/usr/bin/env bash
# Autocompletado para task-helper y aliases (tasklist, tasknew, etc).

_task_helper_complete() {
  local cur base cmd
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  base="${COMP_WORDS[0]}"

  case "$base" in
    tasklist) cmd="list" ;;
    taskclosed) cmd="closed" ;;
    tasknew) cmd="create" ;;
    taskdel) cmd="delete" ;;
    taskmod) cmd="modify" ;;
    reulist) cmd="reulist" ;;
    *) cmd="${COMP_WORDS[1]:-}" ;;
  esac

  # Completar subcomandos si se invoca el script directamente
  if [[ "$base" == "task-helper.sh" || "$base" == *"/task-helper.sh" ]]; then
    if [[ $COMP_CWORD -eq 1 ]]; then
      COMPREPLY=( $(compgen -W "create list closed delete modify" -- "$cur") )
      return 0
    fi
  fi

  # Completar proyectos para tasklist/reulist/tasknew o para "task-helper.sh list"
  if [[ "$cmd" == "list" || "$cmd" == "closed" || "$cmd" == "reulist" || "$cmd" == "create" ]]; then
    # Alias tasklist/reulist: primer argumento es el proyecto
    if [[ ("$base" == "tasklist" || "$base" == "taskclosed" || "$base" == "reulist" || "$base" == "tasknew") && $COMP_CWORD -eq 1 ]]; then
      :
    # Script directo: segundo argumento es el proyecto
    elif [[ "$base" == "task-helper.sh" || "$base" == *"/task-helper.sh" ]]; then
      if [[ $COMP_CWORD -ne 2 ]]; then
        return 0
      fi
    else
      return 0
    fi
    local projs
    projs=$(task _projects 2>/dev/null | sed '/^$/d')
    projs="$projs"$'\n'"Windows"$'\n'"Synology"$'\n'"Network"$'\n'"Ansible"$'\n'"Chocolatey"$'\n'"AWS"
    COMPREPLY=( $(compgen -W "$projs" -- "$cur") )
    return 0
  fi

  return 0
}

complete -F _task_helper_complete task-helper.sh
complete -F _task_helper_complete ~/Documentos/scripts/tasks/task-helper.sh
complete -F _task_helper_complete tasknew tasklist taskclosed taskdel taskmod
complete -F _task_helper_complete reunew reumod reudel reulist
