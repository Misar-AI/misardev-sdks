import { describe, it, expect, beforeAll } from "vitest";
import { AuthenticationError, MisarDev } from "../../typescript/src/index.js";

const SKIP = !process.env.INTEGRATION;

/**
 * Live checks against a real deployment. WRITES: creates a project and moves it
 * to the trash. Point MISARDEV_API_KEY (and MISARDEV_BASE_URL) at a
 * non-production environment.
 */
describe.skipIf(SKIP)("MisarDev integration tests", () => {
  let dev: MisarDev;

  beforeAll(() => {
    const apiKey = process.env.MISARDEV_API_KEY;
    if (!apiKey) throw new Error("MISARDEV_API_KEY required");
    dev = new MisarDev(apiKey);
  });

  it("lists projects", async () => {
    const resp = await dev.projects.list<{ projects: unknown[] }>();
    expect(Array.isArray(resp.projects)).toBe(true);
  });

  it("creates and deletes a project", async () => {
    const { project } = await dev.projects.create<{ project: { id: string } }>({
      name: `sdk-test-${Date.now()}`,
    });
    expect(project.id).toBeTruthy();
    await dev.projects.delete(project.id);
  });

  it("reads the plan behind the key", async () => {
    const plan = await dev.usage.plan<Record<string, unknown>>();
    expect(plan).toBeTruthy();
  });

  it("returns 401 for an invalid key", async () => {
    const bad = new MisarDev("mdk_invalid_key");
    await expect(bad.projects.list()).rejects.toBeInstanceOf(
      AuthenticationError,
    );
  });
});
