/** Bindings from wrangler.jsonc plus secrets set with `wrangler secret put`. */
export interface AppEnv {
  DB: D1Database;
  APP_URL_SCHEME: string;
  OPENAI_MODEL: string;
  ELEVENLABS_MODEL: string;
  ELEVENLABS_VOICE_ID: string;
  DODO_ENVIRONMENT: string;
  DODO_PRODUCT_ID: string;
  PUBLIC_URL: string;
  MOCK_PROVIDERS: string;

  // Secrets
  OPENAI_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  DODO_API_KEY: string;
  DODO_WEBHOOK_SECRET: string;
  /** Random string used to sign the OAuth state parameter. */
  STATE_SECRET: string;
}

export interface User {
  id: string;
  email: string;
  name: string;
}

export type AppContext = { Bindings: AppEnv; Variables: { user: User } };
