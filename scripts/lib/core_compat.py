"""Whether the core a session runs is one its platform takes.

A version is one to three dot-separated numbers, padded with zeros: 3 is 3.0.0. A range is
comparisons separated by spaces, every one of which must hold: >=, >, <=, <, = and a version
(">=2.44.0 <3"). Anything else — a caret, an "||", a prerelease — reads as None, never as False:
a range nobody can read must not stop a run, so the caller treats None as "unknown".
"""
import re

_VERSION = re.compile(r'^\d+(\.\d+){0,2}$')
_TOKEN = re.compile(r'^(>=|<=|>|<|=)(.+)$')


def parse_version(text):
    """(major, minor, patch), or None for anything that is not one to three numbers."""
    text = str(text or '').strip()
    if not _VERSION.match(text):
        return None
    parts = [int(p) for p in text.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def in_range(version, spec):
    """True or False when both read; None when either does not."""
    v = parse_version(version)
    tokens = str(spec or '').split()
    if v is None or not tokens:
        return None
    ok = True
    for token in tokens:
        m = _TOKEN.match(token)
        bound = parse_version(m.group(2)) if m else None
        if bound is None:
            return None
        op = m.group(1)
        ok = ok and {'>=': v >= bound, '<=': v <= bound, '>': v > bound, '<': v < bound, '=': v == bound}[op]
    return ok
