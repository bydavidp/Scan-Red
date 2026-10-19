from __future__ import annotations

import json
from pathlib import Path

from scan_red.exporters import HEADERS, export_csv, export_json
from scan_red.models import Device


def _device() -> Device:
    return Device(
        ip="192.168.1.10",
        mac="AA-BB-CC-DD-EE-FF",
        nombre="PC-David",
        fabricante="ACME",
        estado="Activo",
        ms=5,
        primera_vez="2026-01-01T10:00:00+00:00",
        ultimo_visto="2026-01-01T10:05:00+00:00",
        cambio="NUEVO",
        puertos_abiertos=[80, 443],
    )


def test_export_csv(tmp_path: Path) -> None:
    path = tmp_path / "reporte.csv"
    export_csv([_device()], path)

    text = path.read_text(encoding="utf-8-sig")
    assert ",".join(HEADERS) in text
    assert "192.168.1.10" in text
    assert "NUEVO" in text
    assert "80,443" in text


def test_export_json(tmp_path: Path) -> None:
    path = tmp_path / "reporte.json"
    export_json([_device()], path)

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert len(payload) == 1
    assert payload[0]["ip"] == "192.168.1.10"
    assert payload[0]["puertos_abiertos"] == [80, 443]
    assert payload[0]["fabricante"] == "ACME"
