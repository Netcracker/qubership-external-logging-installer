#!/usr/bin/python
# Copyright Qubership contributors
# SPDX-License-Identifier: Apache-2.0
"""Read and escape Java properties values as java.util.Properties does."""

from __future__ import absolute_import, division, print_function

__metaclass__ = type

DOCUMENTATION = r"""
module: java_properties
short_description: Read and escape values of Java properties files
description:
  - Reads the value of one key from a Java properties file, such as C(graylog.conf), as
    C(java.util.Properties.load(InputStream)) reads it. Lines may end in LF, CRLF, or CR, and the last definition wins.
  - Escapes a value so that C(java.util.Properties) reads it back unchanged from a C(key = value) line.
  - Set at least one of O(path), O(content), and O(escape). O(path) and O(content) are alternative sources to read
    O(key) from, and O(escape) can be set alone or with either of them. O(key) is always required.
  - Never changes the target.
  - The graylog role ships a copy of this module in its C(library) directory, so checkout runs find it too.
author:
  - Qubership contributors (@Netcracker)
options:
  key:
    description:
      - The key to read.
    type: str
    required: true
  path:
    description:
      - The properties file to read on the target. Its bytes are read as ISO 8859-1, as Java does.
      - When the file is missing, O(path) gives RV(exists=false) and RV(value=null).
    type: path
  content:
    description:
      - Properties text to read instead of a file.
      - The text is read as its UTF-8 bytes, as Java reads a file that holds this text in UTF-8.
    type: str
  escape:
    description:
      - A value to escape for a C(key = value) line.
      - Set C(no_log) on tasks that pass a secret in O(content) or O(escape). The module does not mask these options,
        because Ansible would then also mask return values that equal them.
    type: str
notes:
  - Supports check mode.
"""

EXAMPLES = r"""
- name: Read password_secret from graylog.conf
  qubership.observability.java_properties:
    path: /srv/graylog/config/graylog.conf
    key: password_secret
  register: graylog_config_secret
  no_log: true

- name: Escape a secret for graylog.conf
  qubership.observability.java_properties:
    key: password_secret
    escape: "{{ graylog_password_secret }}"
  register: graylog_escaped_secret
  no_log: true
"""

RETURN = r"""
exists:
  description: Whether O(path) exists.
  returned: when O(path) is set
  type: bool
value:
  description: The value of O(key), or V(null) when the key is absent or RV(error) is set.
  returned: when O(path) or O(content) is set
  type: str
error:
  description:
    - Why the value cannot be read, without the value. Java rejects a file with a malformed Unicode escape in any line,
      and Ansible cannot pass on a value with an unpaired UTF-16 surrogate.
  returned: when the value cannot be read
  type: str
escaped:
  description: O(escape) escaped for a C(key = value) line.
  returned: when O(escape) is set
  type: str
"""

import os  # noqa: E402 - Ansible modules import after their documentation blocks

from ansible.module_utils.basic import AnsibleModule  # noqa: E402

_WHITESPACE = " \t\f"
_LINE_BREAKS = "\r\n"
_ESCAPES = {"t": "\t", "n": "\n", "r": "\r", "f": "\f"}
_HEX_DIGITS = "0123456789abcdefABCDEF"


class MalformedEscapeError(ValueError):
    """A \\uxxxx escape lacks four hex digits, which java.util.Properties also rejects."""


def logical_lines(text):
    """Yield the logical lines of properties text, as java.util.Properties.LineReader does.

    Continuations are joined without the line break and the leading whitespace of the next
    line. A # or ! that starts a logical line, also after a continuation that added nothing,
    starts a comment, which ends at the next line break even after a backslash.
    """
    line = []
    skip_whitespace = True
    appended_line_begin = False
    preceding_backslash = False
    index = 0
    while index < len(text):
        char = text[index]
        index += 1
        if skip_whitespace:
            if char in _WHITESPACE:
                continue
            if not appended_line_begin and char in _LINE_BREAKS:
                continue
            skip_whitespace = False
            appended_line_begin = False
        if not line and char in "#!":
            while index < len(text) and text[index] not in _LINE_BREAKS:
                index += 1
            index += 1
            skip_whitespace = True
            continue
        if char not in _LINE_BREAKS:
            line.append(char)
            preceding_backslash = char == "\\" and not preceding_backslash
            continue
        if not line:
            skip_whitespace = True
            continue
        if preceding_backslash:
            line.pop()
            skip_whitespace = True
            appended_line_begin = True
            preceding_backslash = False
            if char == "\r" and text[index:index + 1] == "\n":
                index += 1
            continue
        yield "".join(line)
        line = []
        skip_whitespace = True
    if preceding_backslash:
        line.pop()
    if line:
        yield "".join(line)


def split_line(line):
    """Split a logical line into its raw key and raw value."""
    index = 0
    backslash = False
    while index < len(line):
        char = line[index]
        if not backslash and (char in "=:" or char in _WHITESPACE):
            break
        backslash = char == "\\" and not backslash
        index += 1
    rest = line[index:].lstrip(_WHITESPACE)
    if rest[:1] in ("=", ":"):
        rest = rest[1:].lstrip(_WHITESPACE)
    return line[:index], rest


def unescape(raw):
    """Apply Java properties escapes. The result keeps the UTF-16 code units that Java holds."""
    units = []
    index = 0
    while index < len(raw):
        char = raw[index]
        index += 1
        if char != "\\":
            units.append(char)
            continue
        if index >= len(raw):
            break
        char = raw[index]
        index += 1
        if char == "u":
            digits = raw[index:index + 4]
            if len(digits) != 4 or any(digit not in _HEX_DIGITS for digit in digits):
                raise MalformedEscapeError()
            units.append(chr(int(digits, 16)))
            index += 4
        else:
            units.append(_ESCAPES.get(char, char))
    # Join surrogate pairs into one character and keep unpaired surrogates as they are.
    return "".join(units).encode("utf-16-le", "surrogatepass").decode("utf-16-le", "surrogatepass")


def read_value(text, key):
    """Return the value that java.util.Properties reads for key from text, or None.

    Like Java, it unescapes every key and value, so a malformed escape anywhere raises
    MalformedEscapeError.
    """
    found = None
    for line in logical_lines(text):
        raw_key, raw_value = split_line(line)
        value = unescape(raw_value)
        if unescape(raw_key) == key:
            found = value
    return found


def has_unpaired_surrogate(value):
    """Tell whether value holds a UTF-16 surrogate without its pair, which Ansible cannot return."""
    return any("\ud800" <= char <= "\udfff" for char in value)


def escape_value(value):
    """Escape value so that java.util.Properties reads it back unchanged from a "key = value" line.

    Characters outside printable ASCII become \\uxxxx escapes of their UTF-16 code units, so the
    result is ASCII and reads the same in any encoding.
    """
    result = []
    for position, char in enumerate(value):
        if char == "\\":
            result.append("\\\\")
        elif char in "\t\n\r\f":
            result.append("\\" + "tnrf"["\t\n\r\f".index(char)])
        elif char == " " and position == 0:
            result.append("\\ ")
        elif " " <= char <= "~":
            result.append(char)
        else:
            encoded = char.encode("utf-16-be", "surrogatepass")
            for offset in range(0, len(encoded), 2):
                unit = encoded[offset] << 8 | encoded[offset + 1]
                result.append("\\u%04X" % unit)
    return "".join(result)


def main():
    module = AnsibleModule(
        argument_spec={
            "key": {"type": "str", "required": True, "no_log": False},
            "path": {"type": "path"},
            # Not no_log: Ansible would then mask return values equal to them, such as an escaped value that needs
            # no escapes. Tasks that pass secrets set no_log instead.
            "content": {"type": "str", "no_log": False},
            "escape": {"type": "str", "no_log": False},
        },
        mutually_exclusive=[("path", "content")],
        required_one_of=[("path", "content", "escape")],
        supports_check_mode=True,
    )
    params = module.params
    result = {"changed": False}

    text = None
    source = "content"
    if params["path"] is not None:
        source = params["path"]
        result["exists"] = os.path.exists(source)
        if result["exists"]:
            try:
                with open(source, "rb") as config:
                    text = config.read().decode("latin-1")
            except OSError as error:
                module.fail_json(msg="Cannot read %s: %s" % (source, error.strerror), **result)
    elif params["content"] is not None:
        text = params["content"].encode("utf-8", "surrogatepass").decode("latin-1")

    # Report a value that cannot be read in error instead of failing, so that a task with no_log can show why.
    if params["path"] is not None or params["content"] is not None:
        result["value"] = None
        try:
            value = None if text is None else read_value(text, params["key"])
        except MalformedEscapeError:
            result["error"] = "%s has a malformed \\uxxxx escape, so Java cannot read it." % source
        else:
            if value is not None and has_unpaired_surrogate(value):
                result["error"] = (
                    "The value of %s in %s has an unpaired \\uD800-\\uDFFF escape, which Ansible cannot pass on."
                    % (params["key"], source)
                )
            else:
                result["value"] = value

    if params["escape"] is not None:
        result["escaped"] = escape_value(params["escape"])

    module.exit_json(**result)


if __name__ == "__main__":
    main()
