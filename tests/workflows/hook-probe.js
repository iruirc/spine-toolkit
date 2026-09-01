export const meta = {
  name: 'hook-probe',
  description: 'Probe: does SubagentStart fire for a runtime-spawned agent?',
  whenToUse: 'Run by hand while implementing the progress-visibility plan. Not a profile.',
  phases: [{ title: 'Probe', detail: 'one trivial agent', agent: 'fixture-architect' }],
}

const r = await agent('Reply with the single word: pong. Read nothing, write nothing.', {
  label: 'hook-probe',
  phase: 'Probe',
  agentType: 'fixture-platform:fixture-architect',
})

return { spawned: true, reply: r }
