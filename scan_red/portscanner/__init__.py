"""Escaneo de puertos TCP: motor connect y motor SYN opcional."""

from .connect import ConnectScanner
from .legal import is_external_ip, require_authorization
from .syn import SynScanner

__all__ = [
    "ConnectScanner",
    "SynScanner",
    "is_external_ip",
    "require_authorization",
]
