import { z } from "zod";

export const deficiencyAssignmentSchema = z.object({
  deficiencyId: z.string().uuid(),
  ownerPositionId: z.string().uuid(),
  dueDate: z.coerce.date(),
});

export const dispatchWeeklyReportSchema = z.object({
  unitId: z.string().uuid(),
  weekStart: z.coerce.date(),
  assignments: z.array(deficiencyAssignmentSchema).min(1),
  notes: z.string().max(2000).optional(),
});

export type DispatchWeeklyReportInput = z.infer<typeof dispatchWeeklyReportSchema>;
