// Runs a profile script end to end with stubbed agents, replies keyed by dispatch label.
// Usage: node run-profile.js <script> <contract-json> <replies-json>  → {result, calls: [{label, phase, model, effort, prompt, schema}]}
// A reply keyed <label>#<n> answers only the n-th dispatch of that label; otherwise <label> answers every one.
// A key present with null answers null, as an agent that returned nothing; {"__throw": "<message>"} throws.
const fs = require('fs')
const [script, contract, replies] = process.argv.slice(2)
const R = JSON.parse(replies)
const calls = []
globalThis.agent = async (prompt, opts) => {
  calls.push({ label: opts.label, phase: opts.phase, model: opts.model, effort: opts.effort, prompt, schema: opts.schema })
  const n = calls.filter((c) => c.label === opts.label).length
  const key = [`${opts.label}#${n}`, opts.label].find((k) => Object.prototype.hasOwnProperty.call(R, k))
  const reply = key === undefined ? { ok: true, artifact_path: 'x', summary: 's', changed: false } : R[key]
  if (reply && typeof reply.__throw === 'string') throw new Error(reply.__throw)
  return reply
}
// A nested workflow answers from replies keyed workflow:<name>; unkeyed, it throws as the bare runtime would.
globalThis.workflow = async (name, args) => {
  const label = `workflow:${typeof name === 'string' ? name : name.scriptPath}`
  calls.push({ label, args })
  if (!R[label]) throw new Error('workflow is not defined')
  return R[label]
}
globalThis.parallel = async (fns) => Promise.all(fns.map((f) => f()))
const body = fs.readFileSync(script, 'utf8').replace(/^export const meta/m, 'const meta')
const run = new (Object.getPrototypeOf(async function () {}).constructor)('args', 'log', body)
run(JSON.parse(contract), () => {}).then((result) => console.log(JSON.stringify({ result, calls })))
