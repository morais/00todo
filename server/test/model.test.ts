import { describe, expect, it } from "vitest";
import { ProjectInput, ProjectPatch, ProjectWithTasksInput, TaskInput, TaskPatch, inView, projectInView, type Project, type Task } from "../src/model";
import { dateInZone, timeInZone } from "../src/api";

const sample: Task = {
  id: "task", title: "Buy milk", notes: "", projectId: null,
  startDate: null, startTime: null, dueDate: null, completedAt: null,
  sortOrder: 0, createdAt: "2026-09-27T12:00:00Z", updatedAt: "2026-09-27T12:00:00Z",
};
const sampleProject: Project = {
  id: "project", name: "Shopping", notes: "", startDate: null, startTime: null, dueDate: null,
  completedAt: null, sortOrder: 0,
  createdAt: "2026-09-27T12:00:00Z", updatedAt: "2026-09-27T12:00:00Z",
};

describe("task visibility", () => {
  it("hides a future start from Available even when due earlier", () => {
    const task = { ...sample, startDate: "2026-10-01", dueDate: "2026-09-28" };
    expect(inView(task, "available", "2026-09-27")).toBe(false);
    expect(inView(task, "upcoming", "2026-09-27")).toBe(true);
    expect(inView(task, "available", "2026-10-01")).toBe(true);
  });

  it("keeps same-day timed starts Upcoming until their start time", () => {
    const timed = { ...sample, startDate: "2026-09-29", startTime: "14:30" };
    expect(inView(timed, "available", "2026-09-29", null, null, "14:29")).toBe(false);
    expect(inView(timed, "upcoming", "2026-09-29", null, null, "14:29")).toBe(true);
    expect(inView(timed, "available", "2026-09-29", null, null, "14:30")).toBe(true);
    expect(inView({ ...timed, startTime: null }, "available", "2026-09-29", null, null, "00:00")).toBe(true);
  });

  it("honors a parent's timed start for subtasks", () => {
    expect(inView(sample, "available", "2026-09-29", "2026-09-29", null, "09:59", "10:00")).toBe(false);
    expect(inView(sample, "available", "2026-09-29", "2026-09-29", null, "10:00", "10:00")).toBe(true);
    const project = { ...sampleProject, startDate: "2026-09-29", startTime: "10:00" };
    expect(projectInView(project, "upcoming", "2026-09-29", "09:59")).toBe(true);
    expect(projectInView(project, "available", "2026-09-29", "10:00")).toBe(true);
  });

  it("keeps due dates independent of start dates", () => {
    expect(inView({ ...sample, dueDate: "2026-10-01" }, "available", "2026-09-27")).toBe(true);
    expect(inView({ ...sample, completedAt: "2026-09-27T13:00:00Z" }, "completed", "2026-09-27")).toBe(true);
  });

  it("hides tasks whose parent project starts in the future", () => {
    expect(inView(sample, "available", "2026-09-27", "2026-10-01")).toBe(false);
    expect(inView(sample, "upcoming", "2026-09-27", "2026-10-01")).toBe(true);
    expect(inView(sample, "available", "2026-10-01", "2026-10-01")).toBe(true);
  });

  it("hides future projects from Available without treating due as start", () => {
    const future = { ...sampleProject, startDate: "2026-10-01", dueDate: "2026-09-28" };
    expect(projectInView(future, "available", "2026-09-27")).toBe(false);
    expect(projectInView(future, "upcoming", "2026-09-27")).toBe(true);
    expect(projectInView(future, "available", "2026-10-01")).toBe(true);
    expect(projectInView({ ...sampleProject, dueDate: "2026-10-01" }, "available", "2026-09-27")).toBe(true);
  });

  it("puts completed projects in Completed and hides their open subtasks", () => {
    const completed = { ...sampleProject, completedAt: "2026-09-28T10:00:00Z" };
    expect(projectInView(completed, "available", "2026-09-28")).toBe(false);
    expect(projectInView(completed, "completed", "2026-09-28")).toBe(true);
    expect(inView(sample, "available", "2026-09-28", null, completed.completedAt)).toBe(false);
  });

  it("validates project dates and keeps partial updates partial", () => {
    expect(ProjectInput.safeParse({ name: "Shopping", startDate: "2026-02-30" }).success).toBe(false);
    expect(ProjectInput.parse({ name: "Shopping", notes: "Groceries", sortOrder: 2 })).toMatchObject({
      name: "Shopping", notes: "Groceries", sortOrder: 2, startDate: null, startTime: null, dueDate: null,
    });
    expect(ProjectPatch.parse({ dueDate: null })).toEqual({ dueDate: null });
    expect(ProjectPatch.parse({ completed: true })).toEqual({ completed: true });
  });

  it("rejects impossible calendar dates", () => {
    expect(TaskInput.safeParse({ title: "x", startDate: "2026-02-30" }).success).toBe(false);
    expect(TaskInput.safeParse({ title: "x", startDate: "2026-09-29", startTime: "24:00" }).success).toBe(false);
    expect(TaskInput.parse({ title: "x", startDate: "2026-09-29", startTime: "09:30" }).startTime).toBe("09:30");
  });

  it("validates an entire project and subtask batch before writing", () => {
    expect(ProjectWithTasksInput.parse({ project: { name: "Shopping" }, tasks: [{ title: "Milk" }] }))
      .toMatchObject({ project: { name: "Shopping" }, tasks: [{ title: "Milk" }] });
    expect(ProjectWithTasksInput.safeParse({ project: { name: "Shopping" }, tasks: [{ title: "" }] }).success).toBe(false);
    expect(ProjectWithTasksInput.safeParse({ project: { name: "Shopping" }, tasks: [{ title: "Milk", projectId: "wrong" }] }).success).toBe(false);
    expect(ProjectWithTasksInput.safeParse({ project: { name: "Shopping" }, tasks: Array(51).fill({ title: "Milk" }) }).success).toBe(false);
  });

  it("accepts client-generated IDs for retryable offline creates", () => {
    const projectId = "ad65215a-1eb4-4a5e-89bd-c9704afedeb1";
    const taskId = "cdd4081e-1592-4753-90bd-657144253251";
    expect(ProjectInput.parse({ id: projectId, name: "Shopping" }).id).toBe(projectId);
    expect(TaskInput.parse({ id: taskId, title: "Milk" }).id).toBe(taskId);
    expect(ProjectWithTasksInput.parse({ project: { id: projectId, name: "Shopping" },
      tasks: [{ id: taskId, title: "Milk" }] }).tasks[0].id).toBe(taskId);
    expect(TaskInput.safeParse({ id: "not-a-uuid", title: "Milk" }).success).toBe(false);
  });

  it("does not fill omitted fields in a partial update", () => {
    expect(TaskPatch.parse({ completed: true })).toEqual({ completed: true });
  });

  it("uses the configured time zone for the default calendar day", () => {
    expect(dateInZone(new Date("2026-09-27T23:30:00Z"), "Europe/Lisbon")).toBe("2026-09-28");
    expect(timeInZone(new Date("2026-09-27T23:30:00Z"), "Europe/Lisbon")).toBe("00:30");
  });
});
