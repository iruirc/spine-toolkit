# orchestrator — en

## error_no_task_id
Specify task number, e.g. `run 026` / `/spine-toolkit:task-run 026`.

## error_task_not_found
Task `{task_id}` not found in `Tasks/`.

## error_no_project_config
This project has no `CLAUDE-spine-toolkit.md`, so nothing says which platform serves it — and without a platform there is no agent to dispatch a stage to. Run `/setup` to attach the toolkit to this project (it also migrates a config left over from an earlier toolkit version), or the platform plugin's project-init entry point if the project itself does not exist yet. Then run the task again.

## error_no_platform_manifest
No platform manifest found. The project config names platform "{plugin}", but its manifest skill did not load. Install the platform plugin or fix ## Platform in the config.

## fallback_profile_question
Which profile? (1) FEATURE (2) BUG (3) REFACTOR (4) TEST (5) REVIEW (6) EPIC (7) RESEARCH

## confirm_dispatch
Profile: `{profile}`, mode: `{mode}`, stack: `{stack}`, start: `{start_stage}`. Correct?

## error_research_required
Stage `{stage}` requires `Research.md` first. Run Research, or use `--skip-research`.

## error_redo_no_artifact
Cannot `redo` `{stage}` — its artifact does not exist. Use `run --from {stage}` instead.

## stage_done_prompt
`{stage}` complete. Continue to next? [Yes / Edit / No]

## stage_done_prompt_with_questions
`{stage}` complete, but the artifact still has open questions:

{questions}

What now?

## stage_done_option_continue
Continue to next stage

## stage_done_option_resolve
Resolve open questions now

## stage_done_option_edit
Edit artifact manually

## stage_done_dialog_question
Question {n}/{total} — `{section}`: {text}

## stage_done_dialog_answer
Answer

## stage_done_dialog_defer
Defer (DEFERRED)

## stage_done_dialog_skip
Skip (return later)

## auq_stage_recovery_question
Stage `{invalid_stage}` is not part of profile `{profile}`. Allowed: {profile_stages_list}. Pick one:

## auq_stage_override_question
Pick a different starting stage for profile `{profile}`:

## auq_stage_recovery_recommended_suffix
(Recommended)

## auq_confirm_dispatch_pick_stage
No, pick a different stage

## error_stage_not_in_profile
`{invalid_stage}` is not a valid stage of profile `{profile}`. Allowed: {profile_stages_list}.

## confirm_dispatch_yes
Yes

## confirm_dispatch_cancel
Cancel

## auq_axis_ui_question
Which UI framework does this task use?

## auq_axis_async_question
Which async approach does this task use?

## auq_axis_di_question
Which Dependency Injection approach does this task use?

## auq_axis_architecture_question
Which architecture does this task use?

## auq_axis_baseline_question
Which platform baseline does this task target?

## auq_axis_tests_question
Which test framework does this task use?

## auq_axis_generic_question
Which value of `{axis}` does this task use?

## auq_research_agent_question
Which agent should run the Research stage?

## auq_research_agent_architect
Architect — feasibility, comparative analysis, domain investigation

## auq_research_agent_diagnostics
Diagnostics — audit, inventory, pattern hunt

## auq_research_agent_security
Security — OWASP, vulnerability, certificate pinning

## research_agent_diagnostics_keywords
audit; inventory; grep all

## research_agent_security_keywords
security; OWASP; vulnerability; certificate pinning

## research_experiment_announce
Experiment: the Research agent may change code on branch `{branch}`, build it and run the app. The branch is never merged.

## dispatch_method_a
Stages of the {profile} profile run through the workflow pipeline — the runtime holds the sequence, one agent per stage.

## dispatch_method_b
The Workflow tool is not available in this session, so the {profile} profile runs through its skill. Same stages and same agents; the sequence is held by the assistant rather than by code.

## stage_error_prompt
Stage {stage} returned an error: {reason}. The range stops here — a later stage would build on work that was never finished.

## stage_error_option_retry
Retry {stage}

## stage_error_option_stop
Stop and hand back control

## progress_open_header
{profile} {task_id} · {method} · {start} → {end} · Progress: {progress}

## progress_open_live_hint
Live progress — the /workflows view. Each dispatch below is a run of its own there, listed as `{workflow}`, newest on top.

## progress_open_live_ticker_note
Token panel — run `bash "{script}" --session {session}` in a second terminal pane.

## progress_open_method_b_live
Under Method B the host renders every agent call itself; the panel adds the token figures it does not show.

## progress_open_settings
Settings:

## progress_open_settings_rest
{count} more at their default

## progress_dispatch
{range} → new `{workflow}` run, the top row in /workflows.

## progress_stage_report
{stage} — {agent}

## progress_stage_artifact
Artifact: {path}

## progress_stage_verdict
Verdict: {verdict}

## progress_stage_metrics
{tuning} · {out} out · {ctx} ctx · {tools} tools · {elapsed}

## progress_run_elapsed
Run finished in {elapsed}.

## progress_run_totals
{agents} agents · {out} out · {elapsed}

## progress_run_volume
{total} total · {cacheRead} cache-read · {cacheWrite} cache-write · {in} in

## dispatch_blocked_prompt
The Workflow tool is available and the {profile} profile has a workflow script, but {reason} stands in the way of starting it. Method B runs the same stages through the skill instead.

## dispatch_blocked_option_a
Run through the workflow (Method A)

## dispatch_blocked_option_b
Run through the skill (Method B)

## deviation_role_absent
No agent implements the `{role}` role on this platform, so stage {stage} runs here, in the main context.

## routing_project_init
Creating a project from scratch belongs to the platform plugin — run its project-init entry point (the agent it maps to the `init` role, usually behind its own slash command). The orchestrator drives tasks under `Tasks/`, not bootstrapping.

## scale_escalated
Scale raised to `full` at stage {stage}: {reason}. `[SCALE] = [full]` is now in `Task.md`; the remaining stages run at full depth.

## budget_over_limit
`{artifact}` runs to {actual} lines against a ceiling of {cap}. Trimming it to the ceiling without dropping a requirement.

## task_doc_anchor_missing
`{step}`: `{anchor}` in its `Task.md` is missing, empty or a bare dash. Sending it back to the architect to fill the anchor, or to write `— <reason>` where it does not apply.

## warn_budget_unrecognised
`{line}` in `[BUDGETS]` of `CLAUDE-spine-toolkit.md` names no artifact the budget lint knows, or its ceiling is not a positive whole number, so the default stays. The artifacts are `Task.md`, `Reproduce.md`, `Plan.md`, `Validation.md`, `Review.md` and `Done.md`.

## lang_mismatch
`{artifact}` → `{section}`: the prose is not in the project language (`{lang}`). Sending the file back to its author to rewrite that prose in `{lang}`, structure untouched.

## lang_mismatch_persists
`{artifact}` → `{section}` is still not in the project language after one rewrite. Leaving it as it is; the run carries on.

## lang_mismatch_unowned
`{artifact}` → `{section}`: the prose is not in the project language (`{lang}`). No role of this run writes that file, so it is not sent back and stays as it is.

## lang_readers_disagree
The language check measured the prose against `{measured}`, while this run writes in `{lang}`: the two readings of `[LANG]` disagree, so no file is sent back to be rewritten.

## warn_walkthrough_pre_depth
`on` is the pre-depth value, so it is read as `deep`: a glossary, the commit order and a section per commit, where `on` produced a summary and a log of one bullet per commit. A project's `on` still ends at `off` when this task's `scale` is `lite`, the gate sitting below the task's own field and above the project's. To keep the older shape, write `brief` in `[WALKTHROUGH]`, in `Task.md` or in `CLAUDE-spine-toolkit.md`.

## warn_walkthrough_unrecognised
`{value}` is not one of the three walkthrough depths, so it was skipped and the rest of the chain decides: `off` when this task's `scale` is `lite`, otherwise the project's `[WALKTHROUGH]` where it names one, and `deep` where nothing does. The depths are `brief`, `deep` and `off` — correct the value in `[WALKTHROUGH]`, in `Task.md` or in `CLAUDE-spine-toolkit.md`. The settings column above names the depth this run actually resolved to.

## warn_tuning_unrecognised
`{entry}` in {source} is not a key and value this run can use, so it was skipped and the next setting down applies. Model keys are `light`, `walkthrough` and the eight roles, with `opus`, `sonnet`, `haiku`, `fable` or `session`; effort keys are `walkthrough` and the eight roles, with `low`, `medium`, `high`, `xhigh`, `max` or `session`.

## warn_effort_method_b
The effort set for {roles} does not apply on this run: the profile runs through its skill, and a dispatch from a skill cannot carry an effort, so every stage runs at this session's effort. The model choices still apply.

## warn_driver_plugin_missing
Driver `{driver}` is the driver resolved for this run, but its manifest does not resolve — the
plugin is not installed. The stage that drives the app — Validation, or a RESEARCH experiment —
will hand its UI checks to you instead. Install the plugin, or write `[DRIVER] = [—]` in
`CLAUDE-spine-toolkit.md` to say so deliberately.

## warn_driver_server_missing
Driver `{driver}` is installed, but this session has no tool under any of the prefixes it
declares ({namespaces}) — its MCP server is not connected, or it is registered under a
different name. The stage that drives the app — Validation, or a RESEARCH experiment — will
hand its UI checks to you instead. Start the server, register it under one of those names, or
write `[DRIVER] = [—]` in `CLAUDE-spine-toolkit.md` to say so deliberately.
