"""Salvaguardas de uso y clasificacion de direcciones IP."""

from __future__ import annotations

import ipaddress

_NON_EXTERNAL = tuple(
    ipaddress.ip_network(net)
    for net in (
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.168.0.0/16",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",
        "240.0.0.0/4",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
        "ff00::/8",
    )
)


def is_external_ip(ip: str) -> bool:
    """True solo si la IP es publica/enrutable en Internet."""
    try:
        obj = ipaddress.ip_address(ip)
    except ValueError:
        return False

    if (
        obj.is_private
        or obj.is_loopback
        or obj.is_link_local
        or obj.is_multicast
        or obj.is_reserved
        or obj.is_unspecified
    ):
        return False

    return not any(obj in net for net in _NON_EXTERNAL if net.version == obj.version)


def require_authorization(authorized: bool) -> None:
    """Exige confirmacion explicita antes de escanear."""
    if not authorized:
        raise PermissionError(
            "Debes pasar --autorizado confirmando que administras la red "
            "o tienes permiso escrito. Ver README > Aviso de uso."
        )
