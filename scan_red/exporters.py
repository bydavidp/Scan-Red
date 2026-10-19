"""Exportacion de resultados a CSV y JSON."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from .models import Device

HEADERS = [
    "IP",
    "MAC",
    "Nombre",
    "Fabricante",
    "Estado",
    "Ms",
    "PrimeraVez",
    "UltimoVisto",
    "Cambio",
    "PuertosAbiertos",
]


def _ports_text(device: Device) -> str:
    return ",".join(str(port) for port in device.puertos_abiertos)


def export_csv(devices: list[Device], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(HEADERS)
        for device in devices:
            writer.writerow(
                [
                    device.ip,
                    device.mac or "",
                    device.nombre or "",
                    device.fabricante or "",
                    device.estado,
                    device.ms if device.ms is not None else "",
                    device.primera_vez or "",
                    device.ultimo_visto or "",
                    device.cambio,
                    _ports_text(device),
                ]
            )


def export_json(devices: list[Device], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = [
        {
            "ip": device.ip,
            "mac": device.mac,
            "nombre": device.nombre,
            "fabricante": device.fabricante,
            "estado": device.estado,
            "ms": device.ms,
            "primera_vez": device.primera_vez,
            "ultimo_visto": device.ultimo_visto,
            "cambio": device.cambio,
            "puertos_abiertos": device.puertos_abiertos,
        }
        for device in devices
    ]
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
