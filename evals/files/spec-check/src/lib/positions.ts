import { db } from "./db";

/** Positions that apply to a unit: its own, plus those inherited from parent units. */
export async function resolveEffectiveFunctionPositions(unitId: string) {
  const chain = await db.unit.ancestors(unitId); // [unit, parent, grandparent, ...]
  const positions = await db.functionPosition.findMany({ where: { unitId: { in: chain.map((u) => u.id) } } });
  // nearest unit wins for each function
  const byFunction = new Map<string, (typeof positions)[number]>();
  for (const u of chain) for (const p of positions.filter((x) => x.unitId === u.id)) if (!byFunction.has(p.function)) byFunction.set(p.function, p);
  return [...byFunction.values()];
}
