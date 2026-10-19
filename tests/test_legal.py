from __future__ import annotations

import pytest

from scan_red.portscanner.legal import is_external_ip, require_authorization


@pytest.mark.parametrize(
    ("ip", "expected"),
    [
        ("8.8.8.8", True),
        ("1.1.1.1", True),
        ("192.168.1.10", False),
        ("10.0.0.1", False),
        ("172.16.5.4", False),
        ("100.64.0.1", False),
        ("127.0.0.1", False),
        ("169.254.1.1", False),
        ("198.18.0.1", False),
        ("203.0.113.10", False),
        ("0.0.0.0", False),
        ("no-es-una-ip", False),
    ],
)
def test_is_external_ip(ip: str, expected: bool) -> None:
    assert is_external_ip(ip) is expected


def test_require_authorization_blocks_without_flag() -> None:
    with pytest.raises(PermissionError):
        require_authorization(False)


def test_require_authorization_allows_with_flag() -> None:
    assert require_authorization(True) is None
