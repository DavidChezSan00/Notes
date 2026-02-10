#!/usr/bin/env python3
"""
Helpers compartidos para scripts de Taskwarrior (colores, padding ANSI y dedupe).
"""

import re
from typing import Dict, Iterable, List, Tuple

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

# Colores consistentes entre scripts
BLUE = "\033[34m"
BLUE_SYNOLOGY = "\033[38;5;27m"
GREEN_PROJ = "\033[32m"
AMBER_NETWORK = "\033[38;5;103m"
GREEN_STATE = "\033[38;5;70m"
ORANGE = "\033[38;5;208m"
RESET = "\033[0m"

DESC_COLOR_WINDOWS = "\033[38;5;81m"
DESC_COLOR_SYNOLOGY = "\033[38;5;39m"
DESC_COLOR_CHOCO = "\033[38;5;77m"
DESC_COLOR_NETWORK = AMBER_NETWORK
DESC_COLOR_ANSIBLE = "\033[38;5;178m"
DESC_COLOR_REUNION = "\033[38;5;213m"
DESC_COLOR_AWS = "\033[38;5;202m"

# Paleta para proyectos no mapeados de forma determinista
PALETTE = [
    "\033[38;5;33m",  # azul cyan
    "\033[38;5;64m",  # verde suave
    "\033[38;5;214m",  # naranja
    "\033[38;5;135m",  # magenta
    "\033[38;5;39m",  # azul brillante
    "\033[38;5;142m",  # oliva suave
    "\033[38;5;172m",  # ámbar
    "\033[38;5;201m",  # fucsia
    "\033[38;5;75m",  # azul verdoso
    "\033[38;5;108m",  # verde lima
]


def pad_ansi(text: str, width: int) -> str:
    """Pad a string to width accounting for ANSI sequences."""
    visible = ANSI_RE.sub("", text)
    pad_len = max(0, width - len(visible))
    return text + (" " * pad_len)


def trim_pad_ansi(text: str, width: int) -> str:
    """Recorta texto ANSI-aware a 'width' visibles, añade '…' si recorta y hace padding."""
    visible = ANSI_RE.sub("", text)
    if len(visible) <= width:
        return pad_ansi(text, width)
    target = max(1, width - 1)  # dejar hueco para la elipsis
    out: List[str] = []
    vcount = 0
    i = 0
    while i < len(text) and vcount < target:
        if text[i] == "\x1b":
            end = text.find("m", i)
            if end == -1:
                break
            out.append(text[i : end + 1])
            i = end + 1
            continue
        out.append(text[i])
        vcount += 1
        i += 1
    out.append("…")
    trimmed = "".join(out)
    return pad_ansi(trimmed, width)


def sort_key(task: Dict) -> Tuple:
    return (task.get("imask", 0), task.get("entry") or "", task.get("uuid") or "")


def series_key(task: Dict) -> Tuple:
    proj = (task.get("project") or "").strip().lower()
    desc = (task.get("description") or "").strip().lower()
    if task.get("rtype"):
        return ("recur", proj, desc)
    return ("single", task.get("uuid") or "", proj, desc)


def dedupe_best(tasks: Iterable[Dict]) -> List[Dict]:
    """Queda con la instancia más cercana por serie (recurrente o única)."""
    best_per_series: Dict[Tuple, Dict] = {}
    for task in tasks:
        key = series_key(task)
        if key not in best_per_series or sort_key(task) < sort_key(best_per_series[key]):
            best_per_series[key] = task
    return list(best_per_series.values())


def palette_color(proj_lower: str) -> str:
    """Devuelve un color determinista de la paleta para proyectos nuevos."""
    if not proj_lower:
        return ""
    idx = sum(ord(c) for c in proj_lower) % len(PALETTE)
    return PALETTE[idx]


def project_display(proj_raw: str) -> Tuple[str, str]:
    """Devuelve (texto proyecto coloreado, color descripción)."""
    proj_lower = (proj_raw or "").lower()
    if proj_lower == "windows":
        return f"{BLUE}Windows{RESET}", DESC_COLOR_WINDOWS
    if proj_lower == "synology":
        return f"{BLUE_SYNOLOGY}Synology{RESET}", DESC_COLOR_SYNOLOGY
    if proj_lower == "chocolatey":
        return f"{GREEN_PROJ}Chocolatey{RESET}", DESC_COLOR_CHOCO
    if proj_lower == "network":
        return f"{AMBER_NETWORK}Network{RESET}", DESC_COLOR_NETWORK
    if proj_lower == "ansible":
        return f"{DESC_COLOR_ANSIBLE}Ansible{RESET}", DESC_COLOR_ANSIBLE
    if proj_lower == "reunion":
        return f"{DESC_COLOR_REUNION}Reunion{RESET}", DESC_COLOR_REUNION
    if proj_lower == "aws":
        return f"{DESC_COLOR_AWS}AWS{RESET}", DESC_COLOR_AWS

    color = palette_color(proj_lower)
    if color:
        return f"{color}{proj_raw}{RESET}", color
    return proj_raw or "", ""
