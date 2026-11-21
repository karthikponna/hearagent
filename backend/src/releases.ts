import { Hono } from "hono";
import type { AppContext } from "./env";

export interface Release {
  /** Matches the app's CFBundleShortVersionString. */
  version: string;
  /** Matches CFBundleVersion; compared to decide whether an update exists. */
  build: number;
  /** Where "Download update" takes people. */
  url: string;
  published_at: string;
  highlights: { title: string; detail: string }[];
}

/** The newest build. Bump this when a new DMG is uploaded. */
export const LATEST: Release = {
  version: "0.3.0",
  build: 3,
  url: "https://hearagent.app/download",
  published_at: "2026-11-21",
  highlights: [
    { title: "Three themes", detail: "Settings → Appearance switches the dashboard between Classic, Blue and Plum." },
    { title: "Usage you can scrub", detail: "Spend and daily tokens are line charts now; hover any day to read it." },
    { title: "Pick your narrator", detail: "Choose George, Alice or Brian and set the speaking speed on the Narrator page." },
    { title: "A quicker notch", detail: "It opens straight out of the camera and shows both 5-hour windows next to refresh." },
  ],
};

export const releases = new Hono<AppContext>();

releases.get("/latest", (c) => {
  c.header("Cache-Control", "public, max-age=300");
  return c.json(LATEST);
});
