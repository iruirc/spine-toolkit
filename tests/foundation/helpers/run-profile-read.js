// Runs a profile through run-profile.js and prints what a test reads from the result, in one node start.
// Usage: node run-profile-read.js <script> <contract-json> <replies-json> [<js-expression over o>...]
//   o is run-profile.js's output {result, calls}; each expression's value is printed as a string
//   (a non-string as JSON), the values separated by the ASCII record separator (0x1e).
// It leans on run-profile.js's argv order and its single console.log, so it lives beside it.
const [script, contract, replies, ...exprs] = process.argv.slice(2)
const emit = console.log
console.log = (s) => {
  console.log = emit
  const o = JSON.parse(s)
  emit(exprs.map((e) => { const v = eval(e); return typeof v === 'string' ? v : String(JSON.stringify(v)) }).join('\x1e'))
}
process.argv = [process.argv[0], __filename, script, contract, replies]
require('./run-profile.js')
