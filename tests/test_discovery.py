from __future__ import annotations

import pytest

from scan_red.discovery import (
    ip_in_range,
    ip_sort_key,
    mac_to_oui,
    normalize_mac,
    parse_arp_table,
    validate_red,
)


def test_parse_arp_table_windows() -> None:
    sample = """\
Interface: 192.168.1.110 --- 0x5
  Internet Address      Physical Address      Type
  192.168.1.1           30-de-4b-72-54-75     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
  224.0.0.22            01-00-5e-00-00-16     static
"""
    table = parse_arp_table(sample)
    assert table == {"192.168.1.1": "30-DE-4B-72-54-75"}


def test_parse_arp_table_linux_ip_neigh() -> None:
    sample = """\
192.168.1.1 dev eth0 lladdr 30:de:4b:72:54:75 REACHABLE
192.168.1.9 dev eth0  FAILED
192.168.1.2 dev eth0 lladdr 3c:e3:6b:47:56:fa STALE
"""
    table = parse_arp_table(sample)
    assert table == {
        "192.168.1.1": "30-DE-4B-72-54-75",
        "192.168.1.2": "3C-E3-6B-47-56-FA",
    }


def test_parse_arp_table_dotted_mac() -> None:
    sample = "192.168.1.3 at 30de.4b72.5475 [ether] on eth0\n"
    assert parse_arp_table(sample) == {"192.168.1.3": "30-DE-4B-72-54-75"}


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("3c:e3:6b:47:56:fa", "3C-E3-6B-47-56-FA"),
        ("30de.4b72.5475", "30-DE-4B-72-54-75"),
        ("30-de-4b-72-54-75", "30-DE-4B-72-54-75"),
        ("no-es-mac", "NO-ES-MAC"),
    ],
)
def test_normalize_mac(raw: str, expected: str) -> None:
    assert normalize_mac(raw) == expected


def test_mac_to_oui() -> None:
    assert mac_to_oui("3C-E3-6B-47-56-FA") == "3CE36B"
    assert mac_to_oui("no-es-mac") is None


def test_ip_in_range_and_sort_key() -> None:
    assert ip_in_range("192.168.1.5", "192.168.1", 1, 10) is True
    assert ip_in_range("192.168.1.11", "192.168.1", 1, 10) is False
    assert ip_in_range("192.168.10.5", "192.168.1", 1, 10) is False
    assert ip_sort_key("192.168.1.10") > ip_sort_key("192.168.1.9")


@pytest.mark.parametrize(
    "red",
    ["192.168.1.1", "192.168", "192.168.256", "abc.def.ghi"],
)
def test_validate_red_rejects_invalid(red: str) -> None:
    with pytest.raises(ValueError):
        validate_red(red)


def test_validate_red_accepts_valid() -> None:
    assert validate_red("192.168.1") is None
    assert validate_red("10.0.0") is None
