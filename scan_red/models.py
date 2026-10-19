"""Modelos de datos compartidos por Scan-Red."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

PortState = Literal["open", "closed", "filtered", "error"]


@dataclass(slots=True)
class Device:
    """Un dispositivo de la LAN, equivalente a una fila del CSV original."""

    ip: str
    mac: str | None = None
    nombre: str | None = None
    fabricante: str | None = None
    estado: str = "Activo"  # "Activo" | "Solo ARP"
    ms: int | None = None
    primera_vez: str | None = None
    ultimo_visto: str | None = None
    cambio: str = "Conocido"  # "NUEVO" | "Conocido" | "-"
    puertos_abiertos: list[int] = field(default_factory=list)


@dataclass(slots=True)
class PortResult:
    port: int
    state: PortState


@dataclass(slots=True)
class HostResult:
    ip: str
    tcp: list[PortResult] = field(default_factory=list)

    @property
    def open_ports(self) -> list[int]:
        return [p.port for p in self.tcp if p.state == "open"]
