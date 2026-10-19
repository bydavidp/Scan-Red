from __future__ import annotations

from pathlib import Path

from scan_red.history import apply_history, device_key, load_history, save_history
from scan_red.models import Device


def test_device_key_prefers_mac() -> None:
    assert device_key(Device(ip="192.168.1.5", mac="AA-BB-CC-DD-EE-FF")) == ("AA-BB-CC-DD-EE-FF")
    assert device_key(Device(ip="192.168.1.5")) == "IP:192.168.1.5"


def test_new_device_then_known_device(tmp_path: Path) -> None:
    history_path = tmp_path / "estado-anterior.json"

    first = Device(ip="192.168.1.10", mac="AA-BB-CC-DD-EE-FF", nombre="PC")
    missing = apply_history([first], {})
    assert missing == []
    assert first.cambio == "NUEVO"
    assert first.primera_vez
    save_history(history_path, [first])

    history = load_history(history_path)
    assert "AA-BB-CC-DD-EE-FF" in history
    # Formato compatible con la version PowerShell
    assert history["AA-BB-CC-DD-EE-FF"]["IPs"] == ["192.168.1.10"]
    assert history["AA-BB-CC-DD-EE-FF"]["PrimeraVez"] == first.primera_vez

    # Cambia de IP pero conserva la MAC: debe seguir siendo el mismo equipo.
    second = Device(ip="192.168.1.20", mac="AA-BB-CC-DD-EE-FF", nombre="PC")
    apply_history([second], history)
    assert second.cambio == "Conocido"
    assert second.primera_vez == first.primera_vez


def test_missing_devices_are_reported() -> None:
    history = {
        "11-22-33-44-55-66": {
            "ip": "192.168.1.50",
            "mac": "11-22-33-44-55-66",
            "nombre": "camara",
            "fabricante": "Dahua",
            "ultimo_visto": "2026-01-01T10:00:00+00:00",
        }
    }
    missing = apply_history([], history)
    assert len(missing) == 1
    assert missing[0]["ip"] == "192.168.1.50"
    assert missing[0]["fabricante"] == "Dahua"


def test_load_history_handles_missing_and_corrupt_files(tmp_path: Path) -> None:
    missing_path = tmp_path / "no-existe.json"
    assert load_history(missing_path) == {}

    corrupt = tmp_path / "corrupto.json"
    corrupt.write_text("{no es json", encoding="utf-8")
    assert load_history(corrupt) == {}

    not_a_dict = tmp_path / "lista.json"
    not_a_dict.write_text("[1, 2, 3]", encoding="utf-8")
    assert load_history(not_a_dict) == {}


def test_reads_powershell_style_state() -> None:
    history = {
        "3C-E3-6B-47-56-FA": {
            "IPs": ["192.168.1.105", "192.168.1.108"],
            "MAC": "3C-E3-6B-47-56-FA",
            "Nombre": "camara",
            "Fabricante": "Dahua",
            "PrimeraVez": "2026-01-01T10:00:00+00:00",
            "UltimoVisto": "2026-01-01T11:00:00+00:00",
        }
    }

    device = Device(ip="192.168.1.105", mac="3C-E3-6B-47-56-FA")
    missing = apply_history([device], history)
    assert missing == []
    assert device.cambio == "Conocido"
    assert device.primera_vez == "2026-01-01T10:00:00+00:00"

    missing = apply_history([], history)
    assert missing[0]["ip"] == "192.168.1.105, 192.168.1.108"


def test_save_history_merges_duplicate_macs(tmp_path: Path) -> None:
    path = tmp_path / "estado.json"
    devices = [
        Device(ip="192.168.1.108", mac="3C-E3-6B-47-56-FA"),
        Device(ip="192.168.1.105", mac="3C-E3-6B-47-56-FA"),
    ]
    apply_history(devices, {})
    save_history(path, devices)

    entry = load_history(path)["3C-E3-6B-47-56-FA"]
    assert entry["IPs"] == ["192.168.1.105", "192.168.1.108"]
    assert entry["ip"] == "192.168.1.105"
