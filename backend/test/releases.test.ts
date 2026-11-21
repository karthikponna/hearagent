import { describe, expect, it } from "vitest";
import { LATEST } from "../src/releases";
import { harness } from "./helpers";

describe("release feed", () => {
  it("serves the latest release without signing in", async () => {
    const { call } = harness();
    const res = await call("/releases/latest");
    expect(res.status).toBe(200);
    const body = await res.json<typeof LATEST>();
    expect(body).toEqual(LATEST);
    expect(body.highlights.length).toBeGreaterThan(0);
  });
});
