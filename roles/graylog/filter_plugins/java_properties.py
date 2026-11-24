# Copyright Qubership contributors
# SPDX-License-Identifier: Apache-2.0
"""Read and write values of Java properties files, such as graylog.conf, as java.util.Properties does."""

from __future__ import annotations

import re

from ansible.errors import AnsibleFilterError

_LINE_BREAK = re.compile(r"\r\n|\r|\n")
_WHITESPACE = " \t\f"
_SEPARATORS = "=:"
_ESCAPES = {"t": "\t", "n": "\n", "r": "\r", "f": "\f"}


def _logical_lines(text):
    """Yield the logical lines of a properties file, with continuations joined and comments dropped."""
    natural = _LINE_BREAK.split(text)
    index = 0
    while index < len(natural):
        line = natural[index].lstrip(_WHITESPACE)
        index += 1
        if not line or line[0] in "#!":
            continue
        # An odd number of trailing backslashes continues the line; the next line loses its leading whitespace.
        while (len(line) - len(line.rstrip("\\"))) % 2 == 1:
            line = line[:-1]
            if index >= len(natural):
                break
            line += natural[index].lstrip(_WHITESPACE)
            index += 1
        yield line


def _unescape(raw):
    result = []
    index = 0
    while index < len(raw):
        char = raw[index]
        index += 1
        if char != "\\":
            result.append(char)
            continue
        if index >= len(raw):
            break
        char = raw[index]
        index += 1
        if char == "u":
            digits = raw[index:index + 4]
            if len(digits) != 4 or not all(c in "0123456789abcdefABCDEF" for c in digits):
                raise AnsibleFilterError("Malformed \\uxxxx escape in a Java properties file")
            result.append(chr(int(digits, 16)))
            index += 4
        else:
            result.append(_ESCAPES.get(char, char))
    # Join \\uxxxx surrogate pairs into one character, as a Java string holds them.
    return "".join(result).encode("utf-16-le", "surrogatepass").decode("utf-16-le", "surrogatepass")


def _split(line):
    """Split a logical line into its raw key and raw value."""
    index = 0
    backslash = False
    while index < len(line):
        char = line[index]
        if not backslash and (char in _SEPARATORS or char in _WHITESPACE):
            break
        backslash = char == "\\" and not backslash
        index += 1
    key = line[:index]
    rest = line[index:].lstrip(_WHITESPACE)
    if rest[:1] in tuple(_SEPARATORS):
        rest = rest[1:].lstrip(_WHITESPACE)
    return key, rest


def java_properties_value(text, key):
    """Return the value that java.util.Properties reads for key from text, or None when the key is absent.

    The last definition wins. Line endings may be LF, CRLF, or CR.
    """
    found = None
    for line in _logical_lines(str(text)):
        raw_key, raw_value = _split(line)
        if _unescape(raw_key) == key:
            found = _unescape(raw_value)
    return found


def java_properties_escape(value):
    """Escape value so that java.util.Properties reads it back unchanged from a "key = value" line.

    Non-ASCII characters become \\uxxxx escapes, because Properties.load(InputStream) reads ISO 8859-1.
    """
    result = []
    for position, char in enumerate(str(value)):
        if char == "\\":
            result.append("\\\\")
        elif char in "\t\n\r\f":
            result.append("\\" + {"\t": "t", "\n": "n", "\r": "r", "\f": "f"}[char])
        elif char == " " and position == 0:
            result.append("\\ ")
        elif ord(char) < 0x20 or ord(char) > 0x7E:
            result.extend("\\u" + unit for unit in _utf16_units(char))
        else:
            result.append(char)
    return "".join(result)


def _utf16_units(char):
    encoded = char.encode("utf-16-be").hex().upper()
    return [encoded[i:i + 4] for i in range(0, len(encoded), 4)]


class FilterModule:
    """Java properties filters."""

    def filters(self):
        return {
            "java_properties_value": java_properties_value,
            "java_properties_escape": java_properties_escape,
        }
