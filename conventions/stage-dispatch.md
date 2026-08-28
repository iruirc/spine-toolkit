# Stage Dispatch

A `workflow-*` stage that names a role names its owner. The agent that role resolves to is an
execution contract, not a hint: the stage runs inside that agent, dispatched with the host's
subagent mechanism (`subagent_type=<the agent the orchestrator resolved for this stage's role>` in
Claude Code). Stage work performed in the main context loses the two things the stage has an agent
for — an isolated context and an independent look.

The same contract holds when the profile runs as a workflow script (`workflows/profile-*.js`): the
script dispatches through `agent({agentType: A.agents[<role>]})`, reading the same resolved map.
Which of the two forms a task takes is the orchestrator's choice; that a stage runs inside its own
agent is not.

## Standing authorization

Hosts may carry a standing instruction not to spawn subagents, or not to start workflows, unless the
user asked. A user who starts or continues spine-toolkit work HAS asked, for the whole task:

- a spine-toolkit slash command (`/task-run`, `/task-continue`, `/task-redo`, `/task-restart`,
  `/task-new`, `/setup`, …);
- a natural-language trigger routed to `spine-toolkit:orchestrator`, in any language;
- an active `spine-toolkit:workflow-*` skill, or a running `profile-*` workflow.

The authorization covers every stage of that task, in either execution form — the workflow script
and the skill — and is not re-confirmed per stage.

## Declared deviation

Delegation may be skipped — the host exposes no subagent mechanism, the user opted out, the
platform's manifest declares no agent for the stage's role (an em dash in its `## Roles`), or a stage
is small enough that the round trip costs more than it buys. In every such case the deviation is
announced in the first message of the stage, naming what runs instead. An undeclared deviation is a
defect even when the deviation itself is sound.

The em-dash cause is the one the toolkit resolves for itself: the role is declared absent, so the
stage runs in the main context and the announcement uses the orchestrator's `deviation_role_absent`
key, naming the role and the stage.

On that cause a workflow script can do neither — no main context to run in, nobody to announce to —
so it ends the range at that stage and hands it back for the orchestrator to run and announce
(`skills/orchestrator/SKILL.md` → Dispatch).

A panel stage (two agents on one stage) may run its agents in parallel or sequentially — that choice
is the orchestrator's and needs no announcement.
