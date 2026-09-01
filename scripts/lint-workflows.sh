#!/usr/bin/env bash
set -euo pipefail

# Checks workflows/*.js against the contract in
# docs/superpowers/specs/2026-08-19-workflow-orchestration-design.md:
#
#   - meta is a literal with name, description, phases
#   - meta.name is profile-<x> and collides with no skill directory
#   - stage parity: every SKILL.md stage that names a role has a meta.phases entry, every
#     meta.phases entry names a stage that exists and owns it by the same role in the skill,
#     and the stages exempt from that are named in a list rather than by omission
#   - every phase names the agent that runs its stage, and that map agrees both with what the
#     script dispatches, in both directions, and with the script's own AGENT_OF copy
#   - every agentType is A.agents.<role>, never a string literal, and <role> is in the core
#     role vocabulary (core has no agents/ dir — a script names roles, not agents)
#   - every A.agents.<role> read inside a stage is gated by that stage's need() or lens():
#     the gate is what keeps an em dash out of subagent_type, and deleting one is invisible
#     to every other check here
#   - the prelude block is byte-identical in every script (a script cannot import,
#     so the shared skeleton is copied; this is what keeps the copies one thing)
#   - none of the sandbox-forbidden globals, and no worktree isolation (decision D5)

cd "$(dirname "$0")/.."

# This lint is an independent CI gate: exiting 0 over a renamed or emptied
# workflows/ reports success for the one state that removes every check below.
[ -d workflows ] || { echo "no workflows/ directory — the scripts this lints are gone"; exit 1; }

python3 - <<'PY'
import os, re, sys

# Mirrors scripts/lint-manifest.sh's ROLES — the vocabulary a platform's manifest and a
# workflow script's dispatch both draw from.
ROLES = 'architect developer tester reviewer refactorer validator security diagnostics init'.split()

# (profile, stage) pairs the role-parity checks skip, because Method B runs them in the main
# context: the script dispatches an agent only for want of a filesystem (REVIEW Auto-move, EPIC
# Execute) or writes the final report inline (the six Done stages). Listing them is what makes a
# stage bullet that LOST its `[role]` token a violation instead of a silent exemption.
INLINE_UNDER_METHOD_B = {
    ('bug', 'Done'), ('epic', 'Done'), ('feature', 'Done'),
    ('refactor', 'Done'), ('research', 'Done'), ('test', 'Done'),
    ('epic', 'Execute'), ('review', 'Auto-move'),
}

violations = []

def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    return re.sub(r'(?m)^\s*//.*$', '', src)

def roles_in(text):
    """The core roles a piece of prose names, matched whole-word."""
    return {role for role in ROLES if re.search(rf'\b{role}\b', text)}

def skill_stages(profile):
    """Stage bullets under '## 2. Stages' in the mirroring skill, and the roles each one owns.

    A stage names its owner as a bracketed role, `[architect]`. That token is the anchor: it
    separates a stage that owns work from one that mentions a role in passing, and dropping it
    turns the parity checks below into a silent no-op.
    """
    path = f'skills/workflow-{profile}/SKILL.md'
    if not os.path.exists(path):
        return None, None
    text = open(path, encoding='utf-8').read()
    m = re.search(r'^## 2\. Stages\s*$(.*?)(?=^## )', text, flags=re.M | re.S)
    if not m:
        return None, None
    stages, roles_of = [], {}
    for bullet in re.finditer(r'^- \*\*([^*]+)\*\*(.*?)(?=^- \*\*|\Z)', m.group(1), flags=re.M | re.S):
        name, body = bullet.group(1).strip(), bullet.group(2)
        stages.append(name)
        named = {role for role in ROLES if re.search(rf'\[{role}\]', body)}
        if named:
            roles_of[name] = named
    return stages, roles_of

preludes = {}
files = sorted(f for f in os.listdir('workflows') if f.endswith('.js'))
if len(files) < 7:
    print(f'workflows/ holds {len(files)} script(s), expected the seven profiles')
    sys.exit(1)

for fname in files:
    path = f'workflows/{fname}'
    raw = open(path, encoding='utf-8').read()
    src = strip_comments(raw)

    pre = re.search(r'^// ── prelude ─.*?^// ── end prelude ─.*?$', raw, flags=re.M | re.S)
    if pre:
        preludes[fname] = pre.group(0)
        # scripts/agent-metrics.sh's recover_from_prompt() parses this exact line out of
        # an agent's transcript to recover task/profile/stage when no state file exists yet.
        if not re.search(r'Task id: \$\{[^}]*\} — profile \$\{[^}]*\}, stage \$\{[^}]*\}\.', pre.group(0)):
            violations.append(
                f'{path}: prelude lost the `Task id: ... — profile ..., stage ....` line that '
                'scripts/agent-metrics.sh\'s recover_from_prompt() depends on'
            )
    else:
        violations.append(f'{path}: no prelude block — expected `// ── prelude ─` … `// ── end prelude ─`')

    meta = re.search(r'export const meta\s*=\s*\{(.*?)^\}', raw, flags=re.M | re.S)
    if not meta:
        violations.append(f'{path}: no `export const meta = {{ … }}` literal')
        continue
    block = meta.group(1)

    name = re.search(r"\bname:\s*'([^']+)'", block)
    if not name:
        violations.append(f'{path}: meta has no name')
        continue
    name = name.group(1)

    for field in ('description', 'whenToUse'):
        if not re.search(rf"\b{field}:\s*'", block) and not re.search(rf"\b{field}:\s*$", block, flags=re.M):
            violations.append(f'{path}: meta has no {field}')

    if not name.startswith('profile-'):
        violations.append(f'{path}: meta.name "{name}" must start with "profile-"')
        continue
    profile = name[len('profile-'):]

    if os.path.isdir(f'skills/{name}'):
        violations.append(f'{path}: meta.name "{name}" collides with skills/{name}')

    if f'{profile}.js' != fname and f'profile-{profile}.js' != fname:
        violations.append(f'{path}: filename does not match meta.name "{name}"')

    titles = re.findall(r"title:\s*'([^']+)'", block)
    if not titles:
        violations.append(f'{path}: meta.phases is empty or unparsable')

    agents_by_phase = dict(re.findall(r"title:\s*'([^']+)'[^}]*?agent:\s*'([^']+)'", block))
    for title in titles:
        if title not in agents_by_phase:
            violations.append(f'{path}: meta.phases entry "{title}" has no agent field')

    # meta.phases[].agent is now free prose over role words ("security lens, then architect",
    # "developer / tester") rather than swift-<agent> tokens, so a role is recognized by
    # word-boundary match against the vocabulary rather than by a naming pattern.
    named = set()
    for spec in agents_by_phase.values():
        named.update(roles_in(spec))

    # Every A.agents.<role> in the script, wherever it appears — a per-phase agent reaches
    # runPhases inside a { code, test } map, and that is the copy most likely to be forgotten.
    # lens('<role>') is the other dispatch site: a named-but-non-writing role resolved through
    # the prelude's best-effort helper instead of a direct A.agents.<role> read.
    dispatched = set(re.findall(r'A\.agents\.(\w+)', src)) | set(re.findall(r"lens\('([a-z]+)'\)", src))

    # A.agents[<ident>] form: <ident> is either a bare-role constant (WALKTHROUGH_AGENT) or an
    # object literal mapping a catalog name to a role (profile-research.js's ROLE_OF). Either
    # way its declared value(s) are roles the script dispatches, same as the dot form.
    for ident in set(re.findall(r'A\.agents\[(\w+)', src)):
        m = re.search(rf"^const {ident} = '([a-z]+)'", raw, flags=re.M)
        if m:
            dispatched.add(m.group(1))
            continue
        m = re.search(rf'^const {ident} = \{{([^}}]*)\}}', raw, flags=re.M)
        if m:
            dispatched.update(re.findall(r":\s*'([a-z]+)'", m.group(1)))

    for role in sorted(dispatched):
        if role not in ROLES:
            violations.append(f'{path}: A.agents.{role} — "{role}" is not a core role ({", ".join(ROLES)})')

    for role in sorted(named - dispatched):
        violations.append(f'{path}: meta.phases names role "{role}", which the script never dispatches')
    for role in sorted(dispatched - named):
        violations.append(f'{path}: dispatches role "{role}" but no meta.phases entry mentions it')

    # Deleting a stage's need() call leaves every other check above green and ships a
    # stage that dispatches subagent_type='—' the moment a platform declares that role
    # absent. The gate is the only thing between the two, so it is checked where it is
    # used: inside the stage block, before the read.
    body = raw.split('// ── end prelude')[-1]
    gated, stage = {}, None
    for line in body.split('\n'):
        if line.lstrip().startswith('//'):
            continue
        m = re.search(r"runs\('([A-Za-z-]+)'\)", line)
        if m and re.match(r'\s*(\}\s*else\s*)?if\s*\(', line):
            stage = m.group(1)
        for nm in re.finditer(r"need\('([A-Za-z-]+)'((?:\s*,\s*'[a-z]+')+)\)", line):
            gated.setdefault(nm.group(1), set()).update(re.findall(r"'([a-z]+)'", nm.group(2)))
        for lm in re.finditer(r"lens\('([a-z]+)'\)", line):
            gated.setdefault(stage, set()).add(lm.group(1))
        for role in re.findall(r'A\.agents\.(\w+)', line):
            if role not in gated.get(stage, ()):
                violations.append(
                    f'{path}: A.agents.{role} in stage "{stage}" is not gated — '
                    f"the stage's need() or lens() has to name that role"
                )

    # All three JS string forms: a literal in the two the check did not read is
    # exactly as dispatched as one in the third.
    for _q, literal in re.findall(r"agentType:\s*(['\"`])([^'\"`]*)\1", src):
        violations.append(f'{path}: agentType is the string literal \'{literal}\' — must resolve through A.agents.<role>')

    # meta is parsed before the run and is not a binding inside the sandbox, so the prelude reads a
    # per-file AGENT_OF copy instead. Two copies only stay one map if something compares them.
    copy = re.search(r'^const AGENT_OF = \{(.*?)^\}', raw, flags=re.M | re.S)
    if not copy:
        violations.append(f'{path}: no `const AGENT_OF` — the prelude reads it, meta being invisible to the body')
    else:
        pairs = dict(re.findall(r"^\s*'?([\w-]+)'?:\s*'([^']*)'", copy.group(1), flags=re.M))
        drift = sorted(k for k in set(pairs) | set(agents_by_phase) if pairs.get(k) != agents_by_phase.get(k))
        if drift:
            violations.append(f'{path}: AGENT_OF and meta.phases[].agent disagree on: {", ".join(drift)}')

    stages, roles_of = skill_stages(profile)
    if stages is None:
        violations.append(f'{path}: no mirroring skills/workflow-{profile}/SKILL.md with a "## 2. Stages" section')
    else:
        skill = f'skills/workflow-{profile}/SKILL.md'
        exempt = {stage for prof, stage in INLINE_UNDER_METHOD_B if prof == profile}
        for stale in sorted(s for s in exempt if s not in stages):
            violations.append(f'{path}: INLINE_UNDER_METHOD_B exempts "{stale}", which is not a stage of {skill}')
        for missing in [s for s in roles_of if s not in titles]:
            violations.append(f'{path}: stage "{missing}" names a role in {skill} but has no meta.phases entry')
        for invented in [t for t in titles if t not in stages]:
            violations.append(f'{path}: meta.phases has "{invented}", which is not a stage of the {profile.upper()} profile')
        # The anchor cannot be its own scope key: without this, deleting a stage's `[role]` token
        # drops it out of every check below and the lint stays green.
        for unowned in [t for t in titles if t in stages and t not in roles_of and t not in exempt]:
            violations.append(f'{path}: stage "{unowned}" has a meta.phases entry but names no `[role]` in {skill} — restore the token, or add the stage to INLINE_UNDER_METHOD_B')
        # Stage-level parity, the direction the two lists above cannot see: a stage present on both
        # sides whose owner was changed on one of them only.
        for title in [t for t in titles if t in roles_of]:
            for role in sorted(roles_in(agents_by_phase.get(title, '')) - roles_of[title]):
                violations.append(f'{path}: meta.phases["{title}"] is owned by role "{role}", which {skill} does not name for that stage')

    for token, why in (
        ('Date.now(', 'rejected by the workflow validator'),
        ('Math.random(', 'rejected by the workflow validator'),
        ('new Date(', 'rejected by the workflow validator'),
        ('import(', 'the script sandbox loads no modules'),
        ('isolation:', 'decision D5 — worktrees branch from the default branch, not the task branch'),
    ):
        if token in src:
            violations.append(f'{path}: contains `{token}` — {why}')

if len(preludes) > 1:
    reference_name = sorted(preludes)[0]
    reference = preludes[reference_name]
    for name in sorted(preludes):
        if preludes[name] != reference:
            violations.append(
                f'workflows/{name}: prelude differs from workflows/{reference_name}. '
                'The skeleton is copied because a workflow script cannot import; the copies have to stay one text.'
            )

for v in violations:
    print(v)

if violations:
    print()
    print(f'workflow lint failed: {len(violations)} violation(s)')
    sys.exit(1)

print(f'workflow lint passed: {len(files)} script(s), stages in sync with their skills, every dispatch gated, preludes identical')
PY
