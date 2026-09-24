// Runs a profile script end to end with stubbed agents, replies keyed by dispatch label.
// Usage: node run-profile.js <script> <contract-json> <replies-json>  → {result, calls: [{label, prompt, schema}]}
const fs = require('fs')
const [script, contract, replies] = process.argv.slice(2)
const R = JSON.parse(replies)
const calls = []
globalThis.agent = async (prompt, opts) => {
  calls.push({ label: opts.label, prompt, schema: opts.schema })
  return R[opts.label] || { ok: true, artifact_path: 'x', summary: 's', changed: false }
}
globalThis.parallel = async (fns) => Promise.all(fns.map((f) => f()))
const body = fs.readFileSync(script, 'utf8').replace(/^export const meta/m, 'const meta')
const run = new (Object.getPrototypeOf(async function () {}).constructor)('args', 'log', body)
run(JSON.parse(contract), () => {}).then((result) => console.log(JSON.stringify({ result, calls })))
