// summary.js <evroot> <evals.json> <samples> <ids...>: pass counts per eval and condition.
const fs = require("fs");
const [S, EV, N, ...ids] = process.argv.slice(2);
const evals = require(EV).evals.filter(e => ids.map(Number).includes(e.id));
let tot = { with: 0, without: 0, n: 0 }, trig = 0, runs = 0;
console.log("| eval | with skill | without |\n|---|---|---|");
for (const e of evals) {
  const r = { with: 0, without: 0 }, n = e.expectations.length * N;
  for (const c of ["with", "without"]) for (let k = 1; k <= N; k++) {
    try {
      const g = JSON.parse(fs.readFileSync(`${S}/out/${c}-${e.id}-${k}.grade.json`));
      r[c] += g.filter(x => x.pass).length;
      if (c === "with") { runs++; if (JSON.parse(fs.readFileSync(`${S}/out/${c}-${e.id}-${k}.meta.json`)).skill) trig++; }
    } catch { console.error(`missing grade: ${c}-${e.id}-${k}`); }
  }
  tot.with += r.with; tot.without += r.without; tot.n += n;
  console.log(`| ${e.id} | ${r.with}/${n} | ${r.without}/${n} |`);
}
console.log(`\nwith ${Math.round(100 * tot.with / tot.n)}%, without ${Math.round(100 * tot.without / tot.n)}%; skill invoked in ${trig}/${runs} with-skill runs`);
