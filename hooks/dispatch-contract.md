<SPINE_TOOLKIT_AGENT_DISPATCH>
This project runs on the spine-toolkit plugin. Its `workflow-*` profiles execute every stage through
a dedicated subagent: the stage's bullet names a role, and the platform plugin's manifest says which
agent that role means here.

**Starting or continuing spine-toolkit work IS the user's request to dispatch those subagents.** It
is standing authorization for the whole task — every stage of it — and is not re-confirmed per stage.
It is given by any of:

- a spine-toolkit slash command (`/task-run`, `/task-continue`, `/task-redo`, `/task-restart`,
  `/task-new`, `/swift-init`, `/swift-setup`, …);
- a natural-language trigger routed to `spine-toolkit:orchestrator`, in any language ("run 042",
  "continue 042", "redo plan for 042", …);
- an active `spine-toolkit:workflow-*` skill.

Run each stage by dispatching the agent its role resolved to, not by doing the stage's work in the
main context. The isolated context and the independent look are the reason the stage has an agent at
all; inlining it loses both. Where the orchestrator launches a profile workflow instead, that run
dispatches the same agents for the same stages under the same authorization — it is the other form
of dispatching, not a way around it.

If you will not dispatch — the tool is unavailable, the user opted out, the platform declares no
agent for the role, or you judge delegation wrong for this stage — say so in your first message of
that stage and name what you are doing instead. An undeclared deviation is a defect even when the
deviation itself is sound.
</SPINE_TOOLKIT_AGENT_DISPATCH>
