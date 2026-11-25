"""Compare the java_properties module with java.util.Properties on generated configs.

Usage: python3 differential.py <work directory>. Needs java 11 or later on PATH.
"""

import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "plugins", "modules"))

from java_properties import MalformedEscapeError, escape_value, read_value  # noqa: E402

FRAGMENTS = [
    "password_secret = first",
    "password_secret = second",
    "password_secret:third",
    "password_secret\tfourth",
    "password_secret",
    "\\",
    "  \\",
    "",
    "   ",
    "# password_secret = commented",
    "! password_secret = commented",
    "# comment \\",
    "other = value\\",
    "password\\",
    "_secret = joined",
    "word_secret = joined",
    "pass\\u0077ord_secret = escaped key",
    "password_secret = a\\\\",
    "password_secret = tail\\",
    "password_secret = \\u00e9\\t\\q",
    "password_secret = \\ud83d\\ude00 pair",
    "password_secret = \\ud800 lone",
    "password_secret = café",
    "=: value",
    "other = malformed \\u12zz",
]
ENDINGS = ["\n", "\r\n", "\r"]
CHARACTERS = "ab \\\t\n\r\f=:#!é中\U0001f600𐀀"


def utf16_units(value):
    encoded = value.encode("utf-16-be", "surrogatepass")
    return "".join("%02x%02x" % (encoded[i], encoded[i + 1]) for i in range(0, len(encoded), 2))


def main():
    work = sys.argv[1]
    os.makedirs(work, exist_ok=True)
    rnd = random.Random(151)
    expected = {}
    for number in range(3000):
        name = "case%05d" % number
        if number % 3 == 0:
            secret = "".join(rnd.choice(CHARACTERS) for _position in range(rnd.randint(1, 16)))
            data = ("password_secret = " + escape_value(secret) + "\n").encode("ascii")
            expected[name] = utf16_units(secret)
        else:
            lines = [rnd.choice(FRAGMENTS) + rnd.choice(ENDINGS) for _line in range(rnd.randint(1, 8))]
            text = "".join(lines)
            if rnd.random() < 0.3:
                text = text.rstrip("\r\n")
            data = text.encode("utf-8", "surrogatepass")
            try:
                value = read_value(data.decode("latin-1"), "password_secret")
                expected[name] = "null" if value is None else utf16_units(value)
            except MalformedEscapeError:
                expected[name] = "malformed"
        with open(os.path.join(work, name), "wb") as case:
            case.write(data)

    source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ReadProperties.java")
    output = subprocess.run(["java", source, work], check=True, capture_output=True, text=True).stdout
    rows = [line.split(" ", 1) for line in output.splitlines()]
    names = [row[0] for row in rows]
    if sorted(names) != sorted(expected) or len(set(names)) != len(names):
        print("Java returned %d rows for %d cases, or rows that do not match the cases" % (len(rows), len(expected)))
        sys.exit(1)
    mismatches = 0
    for name, java_value in rows:
        if java_value != expected[name]:
            mismatches += 1
            with open(os.path.join(work, name), "rb") as case:
                print("%s: Java %s, module %s, input %r" % (name, java_value, expected[name], case.read()))
    print("%d cases, %d mismatches" % (len(expected), mismatches))
    sys.exit(1 if mismatches else 0)


if __name__ == "__main__":
    main()
