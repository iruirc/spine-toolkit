#!/usr/bin/env bash
set -euo pipefail

# Checks workflows/*.js against the workflow-orchestration contract:
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
#   - every agent() call carries one tuning(<role>, <kind>) beside its agentType, on the role that
#     agentType reads, of the kind conventions/stage-dispatch.md → Model and effort gives its label;
#     no literal model or effort anywhere
#   - every script's prelude block equals workflow-src/prelude.js (a script cannot import, so
#     scripts/sync-workflow-prelude.sh copies the source into each one; this keeps hand edits out)
#   - none of the sandbox-forbidden globals, and no worktree isolation (decision D5)
#   - every schema an agent() call passes is measured in the script's own scope, with every stage
#     skipped, and fails over the 4096 characters Claude Code starts unreviewed in auto mode

cd "$(dirname "$0")/.."

# This lint is an independent CI gate: exiting 0 over a renamed or emptied
# workflows/ reports success for the one state that removes every check below.
[ -d workflows ] || { echo "no workflows/ directory — the scripts this lints are gone"; exit 1; }

py=0
python3 - <<'PY' || py=$?
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
    ('quick', 'Done'), ('epic', 'Execute'), ('review', 'Auto-move'),
}

# conventions/stage-dispatch.md → Model and effort: the calls whose work the script's own prompt
# defines. Every other dispatch is a stage call.
KIND_OF_LABEL = (
    (r'\$\{stage\.toLowerCase\(\)\}:read-plan', 'mechanical'),
    (r'execute:read-steps', 'mechanical'),
    (r'execute:tick:\$\{st\.step_id\}', 'mechanical'),
    (r'done:read-branch', 'mechanical'),
    (r'auto-move', 'mechanical'),
    (r'done', 'done'),
    (r'walkthrough', 'walkthrough'),
    (r'walkthrough:revise', 'walkthrough'),
    (r'walkthrough:patch', 'walkthrough'),
    (r'walkthrough:check', 'light'),
    (r'security:triage', 'light'),
    (r'manual-checks:check', 'light'),
    (r'artifact:check', 'light'),
)

# Dispatches whose kind is the kind of the stage that wrote their file, as label → (identifier, the
# one line that sets it). The identifier stands where a literal kind would; the line is what the lint
# holds instead, so the kind cannot drift away from the writing stage unseen.
VARIABLE_KIND = {
    'artifact:revise': ('kind', "const kind = stage === 'Done' ? 'done' : 'stage'"),
}

# Dispatches whose role is a variable, as (agentType expression, tuning role expression). An unlisted
# variable form is a violation, so no dispatch slips past the role check.
VARIABLE_DISPATCH = {
    ('A.agents[role]', 'role'),
    ('agentType', 'WALKTHROUGH_AGENT'),
    ('agentType', 'REPORT_AGENT'),
    ('l.agentType', 'l.role'),
    ('A.agents[ROLE_OF[picked]]', 'ROLE_OF[picked]'),
    ('agentType', 'role'),
}

ROLE_STRINGS = (
    r"tuning\('([a-z]+)'",
    r"readPlan\('[A-Za-z]+',\s*'([a-z]+)'\)",
)
ROLE_MAP = r"\{\s*code:\s*'([a-z]+)',\s*test:\s*'([a-z]+)'\s*\}"


def role_strings(text):
    """Roles a dispatch reaches by name rather than through an A.agents read."""
    found = [r for pattern in ROLE_STRINGS for r in re.findall(pattern, text)]
    return found + [r for pair in re.findall(ROLE_MAP, text) for r in pair]

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

PRELUDE_SOURCE = 'workflow-src/prelude.js'
PRELUDE_BLOCK = r'^// ── prelude ─.*?^// ── end prelude ─.*?$'
# scripts/agent-metrics.sh's recover_from_prompt() parses this exact line out of an agent's
# transcript to recover task/profile/stage when no state file exists yet.
TASK_ID_LINE = r'Task id: \$\{[^}]*\} — profile \$\{[^}]*\}, stage \$\{[^}]*\}\.'

def check_task_id_line(path, block):
    if not re.search(TASK_ID_LINE, block):
        violations.append(
            f'{path}: prelude lost the `Task id: ... — profile ..., stage ....` line that '
            'scripts/agent-metrics.sh\'s recover_from_prompt() depends on'
        )

source_prelude = None
if os.path.isfile(PRELUDE_SOURCE):
    pre = re.search(PRELUDE_BLOCK, open(PRELUDE_SOURCE, encoding='utf-8').read(), flags=re.M | re.S)
    if pre:
        source_prelude = pre.group(0)
        check_task_id_line(PRELUDE_SOURCE, source_prelude)
if source_prelude is None:
    violations.append(
        f'{PRELUDE_SOURCE}: missing — the source every workflows/profile-*.js prelude is generated from'
    )

preludes = {}
files = sorted(f for f in os.listdir('workflows') if f.endswith('.js'))
if len(files) < 8:
    print(f'workflows/ holds {len(files)} script(s), expected the eight profiles')
    sys.exit(1)

for fname in files:
    path = f'workflows/{fname}'
    raw = open(path, encoding='utf-8').read()
    src = strip_comments(raw)

    pre = re.search(PRELUDE_BLOCK, raw, flags=re.M | re.S)
    if pre:
        preludes[fname] = pre.group(0)
        check_task_id_line(path, pre.group(0))
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

    # meta.phases[].agent is free prose over role words ("security lens, then architect",
    # "developer / tester"), so a role is recognized by word-boundary match against the
    # vocabulary rather than by a naming pattern.
    named = set()
    for spec in agents_by_phase.values():
        named.update(roles_in(spec))

    # Every A.agents.<role> in the script, wherever it appears — a per-phase agent reaches
    # runPhases inside a { code, test } map, and that is the copy most likely to be forgotten.
    # lens('<role>') is the other dispatch site: a named-but-non-writing role resolved through
    # the prelude's best-effort helper instead of a direct A.agents.<role> read.
    dispatched = set(re.findall(r'A\.agents\.(\w+)', src)) | set(re.findall(r"lens\('([a-z]+)'\)", src))
    dispatched |= set(role_strings(src))

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
        for role in role_strings(line):
            if role not in gated.get(stage, ()):
                violations.append(
                    f'{path}: role "{role}" dispatched in stage "{stage}" is not gated — '
                    f"the stage's need() or lens() has to name that role"
                )

    # All three JS string forms: a literal in the two the check did not read is
    # exactly as dispatched as one in the third.
    for _q, literal in re.findall(r"agentType:\s*(['\"`])([^'\"`]*)\1", src):
        violations.append(f'{path}: agentType is the string literal \'{literal}\' — must resolve through A.agents.<role>')

    # A dispatch's option line is the agentType line with a label on it or on one of the three lines
    # above; the Diagnose lens objects carry agentType and no label, and are not dispatches.
    # Comments blanked rather than stripped (unlike src), so these line numbers match the file.
    lines = re.sub(r'(?m)^[ \t]*//.*$', '', raw).split('\n')
    dispatches = []
    for i, line in enumerate(lines):
        at = re.search(r'\bagentType\b(?:\s*:\s*([^,}]+?))?\s*[,}]', line)
        if not at or re.search(r'\bconst agentType\b', line):
            continue
        labelled = [lines[j] for j in range(max(0, i - 3), i + 1) if 'label:' in lines[j]]
        if not labelled:
            continue
        lab = re.search(r"label:\s*(['`])(.*?)\1", labelled[-1])
        dispatches.append((i + 1, (at.group(1) or 'agentType').strip(), lab.group(2) if lab else '?', line))

    calls = len(re.findall(r'\bagent\(', src))
    if calls != len(dispatches):
        violations.append(f'{path}: {calls} agent() call(s) but {len(dispatches)} dispatch option line(s) — every call names a label within three lines above its agentType')

    for kw in sorted(set(re.findall(r"\b(model|effort):\s*['\"`]", src))):
        violations.append(f'{path}: literal `{kw}:` — a dispatch takes its model and effort only from tuning()')

    lens_role = dict(re.findall(r"^\s*const (\w+) = lens\('([a-z]+)'\)", raw, flags=re.M))
    for n, expr, label, line in dispatches:
        # A kind is a quoted literal; a bare identifier parses apart so that only VARIABLE_KIND may use one.
        tunings = re.findall(r"\.\.\.tuning\(\s*([^,]+?)\s*,\s*(?:'([a-z]+)'|([A-Za-z_]\w*))\s*\)", line)
        if len(tunings) != 1:
            violations.append(f"{path}:{n}: dispatch '{label}' carries {len(tunings)} tuning() call(s) beside its agentType, expected exactly one")
            continue
        role_expr, literal, bare = tunings[0]
        kind = literal or bare
        direct = re.fullmatch(r'A\.agents\.(\w+)', expr)
        read = direct.group(1) if direct else lens_role.get(expr)
        if read:
            if role_expr != f"'{read}'":
                violations.append(f"{path}:{n}: dispatch '{label}' reads role {read} in agentType but tunes for {role_expr}")
        elif (expr, role_expr) not in VARIABLE_DISPATCH:
            violations.append(f"{path}:{n}: dispatch '{label}' pairs agentType {expr} with tuning role {role_expr}, a variable form lint-workflows.sh does not list")
        if label in VARIABLE_KIND:
            ident, setter = VARIABLE_KIND[label]
            if bare != ident:
                violations.append(f"{path}:{n}: dispatch '{label}' is tuned {kind}; conventions/stage-dispatch.md → Model and effort makes it the writing stage's kind, through {ident}")
            elif not re.search(rf'^\s*{re.escape(setter)}\s*$', raw, flags=re.M):
                violations.append(f"{path}:{n}: dispatch '{label}' takes its kind from {ident}, which is no longer set by `{setter}`")
            continue
        if bare:
            violations.append(f"{path}:{n}: dispatch '{label}' is tuned by the identifier {bare}; its kind has to be a quoted literal")
            continue
        expected = next((k for pattern, k in KIND_OF_LABEL if re.fullmatch(pattern, label)), 'stage')
        if kind != expected:
            violations.append(f"{path}:{n}: dispatch '{label}' is tuned {kind}; conventions/stage-dispatch.md → Model and effort makes it {expected}")

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

if source_prelude is not None:
    for name in sorted(preludes):
        if preludes[name] != source_prelude:
            violations.append(
                f'workflows/{name}: prelude differs from {PRELUDE_SOURCE} — run scripts/sync-workflow-prelude.sh'
            )

for v in violations:
    print(v)

if violations:
    print()
    print(f'workflow lint failed: {len(violations)} violation(s)')
    sys.exit(1)

PY

# The schema sizes, in Node: a schema is a JavaScript expression over the script's own constants
# and the prelude's functions, and some grow with the contract. The Python block above stays silent
# on success, so the run prints one success line, and only when both blocks pass.
js=0
PY_STATUS=$py node - <<'JS' || js=$?
const fs = require('fs')

// Claude Code in auto permission mode does not start an agent whose output schema is longer than this:
// "output schema is over 4096 characters, too large to pass unreviewed in auto mode".
const HOST_SCHEMA_LIMIT = 4096
const SCHEMA_WARN = 3600

// The prelude's stage gate. Forcing it false runs every top-level declaration and no stage.
const RUNS_ANCHOR = 'return i >= startAt && i <= endAt'

// A setting that adds fields to a schema goes into the second contract, so its largest form is measured.
const AGENTS = Object.fromEntries('architect developer tester reviewer refactorer validator security diagnostics init'.split(' ').map((r) => [r, r]))
const BASE = { task_id: '1', task_dir: '/p/Tasks/ACTIVE/1-x', plugin_root: '/core', lang: 'en', mode: 'auto', agents: AGENTS }
const CONTRACTS = [BASE, { ...BASE, estimation: 'on', estimation_unit: 'both', research_experiment: 'on', scale: 'full' }]

// Where the expression starting at i ends: the first comma or unmatched closer outside brackets and quotes.
const exprEnd = (s, i) => {
  let depth = 0
  for (let j = i; j < s.length; j++) {
    const c = s[j]
    if (c === "'" || c === '"' || c === '`') {
      for (j++; j < s.length && s[j] !== c; j++) if (s[j] === '\\') j++
      continue
    }
    if ('{(['.includes(c)) depth++
    else if ('})]'.includes(c)) { if (!depth) return j; depth-- }
    else if (c === ',' && !depth) return j
  }
  return s.length
}

// Every schema: key with its line, the label of its agent() call and its expression.
const schemaExprs = (src) =>
  [...src.matchAll(/\bschema: /g)].map((m) => {
    const at = m.index + m[0].length
    const before = src.slice(0, m.index)
    const call = before.lastIndexOf('agent(')
    const lab = before.slice(call).match(/label: ('[^']*'|"[^"]*"|`[^`]*`)(?![\s\S]*label: )/)
    return { line: before.split('\n').length, label: lab ? lab[1].slice(1, -1) : '?', expr: src.slice(at, exprEnd(src, at)).trim() }
  })

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
globalThis.agent = async () => null
globalThis.workflow = async () => { throw new Error('workflow is not defined') }
globalThis.parallel = async (fns) => Promise.all(fns.map((f) => f()))

;(async () => {
  const files = fs.readdirSync('workflows').filter((f) => /^profile-.*\.js$/.test(f)).sort()
  const violations = []
  const warnings = []
  for (const f of files) {
    const path = `workflows/${f}`
    const src = fs.readFileSync(path, 'utf8')
    if (src.split(RUNS_ANCHOR).length !== 2) {
      violations.push(`${path}: lint-workflows.sh cannot find runs() in the prelude to skip every stage — update its anchor`)
      continue
    }
    const exprs = schemaExprs(src)
    const body = 'function __probe(e) { return eval(e) }\nglobalThis.__probe = __probe\n' +
      src.replace(/^export const meta/m, 'const meta').replace(RUNS_ANCHOR, 'return false')
    const size = new Map()
    const error = new Map()
    let ran = true
    for (const contract of CONTRACTS) {
      try {
        await new AsyncFunction('args', 'log', body)(contract, () => {})
      } catch (e) {
        violations.push(`${path}: lint-workflows.sh could not run the script with every stage skipped (${e.message})`)
        ran = false
        break
      }
      for (const x of exprs) {
        try {
          const v = globalThis.__probe(`(${x.expr})`)
          if (!v || typeof v !== 'object') throw new Error('not an object')
          size.set(x, Math.max(size.get(x) || 0, JSON.stringify(v).length))
        } catch (e) {
          if (!error.has(x)) error.set(x, e.message)
        }
      }
    }
    if (!ran) continue
    for (const x of exprs) {
      const where = `${path}:${x.line}: dispatch '${x.label}'`
      if (error.has(x)) violations.push(`${where} has a schema lint-workflows.sh cannot measure (${error.get(x)}) — define it where the script's top level can see it`)
      else if (size.get(x) > HOST_SCHEMA_LIMIT) violations.push(`${where} has a ${size.get(x)}-character schema, over the ${HOST_SCHEMA_LIMIT} Claude Code starts unreviewed in auto mode — shorten it`)
      else if (size.get(x) >= SCHEMA_WARN) warnings.push(`warning: ${where} has a ${size.get(x)}-character schema, ${HOST_SCHEMA_LIMIT - size.get(x)} under the ${HOST_SCHEMA_LIMIT} auto-mode limit`)
    }
  }
  for (const w of warnings) console.log(w)
  for (const v of violations) console.log(v)
  if (violations.length) {
    console.log(`\nschema lint failed: ${violations.length} violation(s)`)
    process.exit(1)
  }
  if (process.env.PY_STATUS === '0') {
    console.log(`workflow lint passed: ${files.length} script(s), stages in sync with their skills, every dispatch gated and tuned, preludes match workflow-src/prelude.js, every schema under ${HOST_SCHEMA_LIMIT} characters`)
  }
})().catch((e) => { console.log(`schema lint crashed: ${e.stack}`); process.exit(1) })
JS

exit $(( py || js ))
