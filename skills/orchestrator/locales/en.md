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
Live progress of the running workflow — the /workflows view.

## progress_open_live_ticker_note
Token panel — run `bash "{script}" --session {session}` in a second terminal pane.

## progress_open_method_b_live
Under Method B the host renders every agent call itself; the panel adds the token figures it does not show.

## progress_stage_report
{stage} — {agent}

## progress_stage_artifact
Artifact: {path}

## progress_stage_verdict
Verdict: {verdict}

## progress_stage_metrics
{model} · {out} out · {ctx} ctx · {tools} tools · {elapsed}

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
