"""Whether the core a session runs is one its platform takes.

A version is one to three dot-separated numbers, padded with zeros: 3 is 3.0.0. A range is
comparisons separated by spaces, every one of which must hold: >=, >, <=, <, = and a version
(">=2.44.0 <3"). Anything else — a caret, an "||", a prerelease — reads as None, never as False:
a range nobody can read must not stop a run, so the caller treats None as "unknown".
"""
import json
import os
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


def _read_json(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def _installed(plugins, name, project_root):
    """The registry entry Claude Code loads `name` from: the one whose projectPath is this
    project, else the user-scoped one. None when the plugin is absent, recorded under more than
    one marketplace, or has neither entry."""
    keys = [k for k in plugins if k.split('@', 1)[0] == name]
    if len(keys) != 1 or not isinstance(plugins[keys[0]], list):
        return None
    entries = [e for e in plugins[keys[0]] if isinstance(e, dict)]
    here = os.path.realpath(project_root) if project_root else None
    for e in entries:
        if here and isinstance(e.get('projectPath'), str) and os.path.realpath(e['projectPath']) == here:
            return e
    for e in entries:
        if e.get('scope') == 'user' and not e.get('projectPath'):
            return e
    return None


def core_compat(core_root, platform, project_root, runtime, registry):
    """The session's core against the range of the platform its agents load from.

    status: unknown — not Claude Code, no platform, or something on the way does not read;
    incompatible — the core is outside the platform's spine-toolkit range; lag — inside it, but
    older than the installed core; ok — the rest. Codex is always unknown: its platform root is
    the folder of the skill it loaded, which this script, run before the manifest loads, cannot see.
    """
    own = _read_json(os.path.join(core_root, '.claude-plugin', 'plugin.json'))
    core = str(own.get('version') or '') if isinstance(own, dict) else ''
    out = dict(core=core, installed_core='', platform=platform or '', platform_version='', requires='',
               status='unknown')
    if runtime != 'claude-code' or not platform:
        return out
    reg = _read_json(registry)
    plugins = reg.get('plugins') if isinstance(reg, dict) else None
    if not isinstance(plugins, dict):
        return out
    mine = _installed(plugins, 'spine-toolkit', project_root)
    if mine:
        out['installed_core'] = str(mine.get('version') or '')
    entry = _installed(plugins, platform, project_root)
    path = entry.get('installPath') if entry else None
    manifest = _read_json(os.path.join(path, '.claude-plugin', 'plugin.json')) if isinstance(path, str) and path else None
    if not isinstance(manifest, dict):
        return out
    out['platform_version'] = str(manifest.get('version') or '')
    deps = manifest.get('dependencies') if isinstance(manifest.get('dependencies'), list) else []
    out['requires'] = next((str(d.get('version') or '') for d in deps
                            if isinstance(d, dict) and d.get('name') == 'spine-toolkit'), '')
    fits = in_range(core, out['requires'])
    if fits is None:
        return out
    if not fits:
        out['status'] = 'incompatible'
    elif parse_version(out['installed_core']) and parse_version(core) < parse_version(out['installed_core']):
        out['status'] = 'lag'
    else:
        out['status'] = 'ok'
    return out
