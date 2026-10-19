from __future__ import annotations

import pytest

from scan_red.cli import build_parser, parse_ports


def test_parser_accepts_powershell_style_flags() -> None:
    args = build_parser().parse_args(
        [
            "-Red",
            "192.168.0",
            "-Inicio",
            "2",
            "-Fin",
            "10",
            "-TimeoutMs",
            "500",
            "-Carpeta",
            "C:\\Reportes",
            "-SinFabricante",
            "--autorizado",
        ]
    )
    assert args.red == "192.168.0"
    assert args.inicio == 2
    assert args.fin == 10
    assert args.timeout_ms == 500
    assert args.carpeta == "C:\\Reportes"
    assert args.sin_fabricante is True
    assert args.autorizado is True


def test_parser_accepts_port_options() -> None:
    args = build_parser().parse_args(
        ["--autorizado", "--puertos", "22,80", "--motor-puertos", "syn"]
    )
    assert args.puertos == "22,80"
    assert args.motor_puertos == "syn"


def test_parse_ports() -> None:
    assert parse_ports("80,443,80") == [80, 443]
    assert parse_ports("1-3") == [1, 2, 3]
    assert parse_ports("") == []


@pytest.mark.parametrize("text", ["0", "65536", "abc", "10-5"])
def test_parse_ports_rejects_invalid(text: str) -> None:
    with pytest.raises(ValueError):
        parse_ports(text)
