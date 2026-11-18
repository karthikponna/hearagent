import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            // Pinned so a developer's local .dev.vars cannot change test behaviour.
            MOCK_PROVIDERS: "0",
            GOOGLE_CLIENT_ID: "test-client.apps.googleusercontent.com",
            GOOGLE_CLIENT_SECRET: "google-secret",
            STATE_SECRET: "state-secret",
            OPENAI_API_KEY: "sk-test",
            ELEVENLABS_API_KEY: "el-test",
            DODO_API_KEY: "dodo-test",
            DODO_WEBHOOK_SECRET: `whsec_${Buffer.from("webhook-signing-key").toString("base64")}`,
            DODO_PRODUCT_ID: "pdt_starter",
            PUBLIC_URL: "https://api.hearagent.test",
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/setup.ts"] },
  };
});
