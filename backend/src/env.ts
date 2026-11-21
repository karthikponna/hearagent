import type { Store } from "./db";

/** Bindings from wrangler.jsonc plus secrets set with `wrangler secret put`. */
export interface AppEnv {
  APP_URL_SCHEME: string;
  OPENAI_MODEL: string;
  ELEVENLABS_MODEL: string;
  ELEVENLABS_VOICE_ID: string;
  DODO_ENVIRONMENT: string;
  PUBLIC_URL: string;
  MOCK_PROVIDERS: string;
  /** https://<project-ref>.supabase.co */
  SUPABASE_URL: string;

  // Secrets
  /** Supabase secret key (sb_secret_…) or legacy service_role key. Never ships in the app. */
  SUPABASE_SECRET_KEY: string;
  OPENAI_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  DODO_API_KEY: string;
  DODO_WEBHOOK_SECRET: string;
}

export interface User {
  id: string;
  email: string;
  name: string;
}

export type AppContext = { Bindings: AppEnv; Variables: { user: User; store: Store } };
