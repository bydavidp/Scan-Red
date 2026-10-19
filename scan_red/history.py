"""Estado anterior: deteccion de nuevos, conocidos y desaparecidos.

El JSON se guarda con claves en snake_case (Python) y tambien en PascalCase
(IPs, PrimeraVez, ...) para que la version PowerShell en `legacy/` pueda
leerlo y escribir en el mismo archivo sin perder informacion.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import Device


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def device_key(device: Device) -> str:
    """La MAC es la identidad estable; si no hay, se usa la IP."""
    return device.mac or f"IP:{device.ip}"


def _ip_sort_key(ip: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in ip.split("."))
    except ValueError:
        return (999, 999, 999, 999)


def _first_value(info: dict[str, Any], *names: str) -> Any:
    for name in names:
        value = info.get(name)
        if value not in (None, ""):
            return value
    return None


def load_history(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if not isinstance(raw, dict):
        return {}
    return {str(key): value for key, value in raw.items() if isinstance(value, dict)}


def apply_history(
    devices: list[Device], history: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    """Marca NUEVO/Conocido y devuelve los dispositivos desaparecidos."""
    timestamp = now_iso()
    seen: set[str] = set()

    for device in devices:
        key = device_key(device)
        previous = history.get(key) or {}
        first_seen = _first_value(previous, "primera_vez", "PrimeraVez")

        if previous:
            device.cambio = "Conocido"
            device.primera_vez = first_seen or timestamp
        else:
            device.cambio = "NUEVO"
            device.primera_vez = timestamp
        device.ultimo_visto = timestamp
        seen.add(key)

    missing: list[dict[str, Any]] = []
    for key, info in history.items():
        if key in seen:
            continue

        ip_value = _first_value(info, "ip", "IP")
        if not ip_value:
            ips = info.get("IPs")
            if isinstance(ips, list) and ips:
                ip_value = ", ".join(str(ip) for ip in ips)

        missing.append(
            {
                "key": key,
                "ip": ip_value,
                "mac": _first_value(info, "mac", "MAC"),
                "nombre": _first_value(info, "nombre", "Nombre"),
                "fabricante": _first_value(info, "fabricante", "Fabricante"),
                "ultimo_visto": _first_value(info, "ultimo_visto", "UltimoVisto"),
            }
        )
    return missing


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def save_history(path: Path, devices: list[Device]) -> None:
    data: dict[str, dict[str, Any]] = {}

    for device in devices:
        key = device_key(device)
        entry = data.get(key)
        if entry is None:
            entry = {
                "ip": device.ip,
                "mac": device.mac,
                "nombre": device.nombre,
                "fabricante": device.fabricante,
                "primera_vez": device.primera_vez,
                "ultimo_visto": device.ultimo_visto,
                # Compatibilidad con la version PowerShell
                "IP": device.ip,
                "IPs": [],
                "MAC": device.mac,
                "Nombre": device.nombre or "",
                "Fabricante": device.fabricante or "",
                "PrimeraVez": device.primera_vez,
                "UltimoVisto": device.ultimo_visto,
            }
            data[key] = entry

        if device.ip not in entry["IPs"]:
            entry["IPs"].append(device.ip)
        entry["IPs"].sort(key=_ip_sort_key)
        entry["ip"] = entry["IPs"][0]
        entry["IP"] = entry["ip"]

        if not entry.get("primera_vez"):
            entry["primera_vez"] = device.primera_vez
        if not entry.get("PrimeraVez"):
            entry["PrimeraVez"] = entry.get("primera_vez")

        if device.nombre:
            entry["nombre"] = device.nombre
            entry["Nombre"] = device.nombre
        if device.fabricante:
            entry["fabricante"] = device.fabricante
            entry["Fabricante"] = device.fabricante

        entry["ultimo_visto"] = device.ultimo_visto or entry.get("ultimo_visto")
        entry["UltimoVisto"] = entry["ultimo_visto"]

    _atomic_write(path, json.dumps(data, indent=2, ensure_ascii=False))
