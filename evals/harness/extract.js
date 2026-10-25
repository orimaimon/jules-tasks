// extract.js <jsonl> -> {result, skill, tools, cost, turns, ms}
const fs = require("fs");
const lines = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean).map(l => { try { return JSON.parse(l) } catch { return {} } });
const tools = []; let res = {};
for (const m of lines) {
  if (m.type === "assistant") for (const c of m.message.content) if (c.type === "tool_use") tools.push(c.name + (c.name === "Skill" ? ":" + c.input.skill : ""));
  if (m.type === "result") res = m;
}
console.log(JSON.stringify({ result: res.result || "", skill: tools.some(t => t === "Skill:jules-tasks"), tools, cost: res.total_cost_usd, turns: res.num_turns, ms: res.duration_ms }));
