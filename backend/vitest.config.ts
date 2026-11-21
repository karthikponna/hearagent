import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          // Pinned so a developer's local .dev.vars cannot change test behaviour.
          MOCK_PROVIDERS: "0",
          SUPABASE_URL: "https://project.supabase.test",
          SUPABASE_SECRET_KEY: "sb_secret_test",
          OPENAI_API_KEY: "sk-test",
          ELEVENLABS_API_KEY: "el-test",
          DODO_API_KEY: "dodo-test",
          DODO_WEBHOOK_SECRET: `whsec_${Buffer.from("webhook-signing-key").toString("base64")}`,
          PUBLIC_URL: "https://api.hearagent.test",
        },
      },
    }),
  ],
});
