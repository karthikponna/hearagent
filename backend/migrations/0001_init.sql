CREATE TABLE users (
  id TEXT PRIMARY KEY,
  google_sub TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX users_email ON users(email);

-- Long-lived app sessions. Only a SHA-256 hash of the token is stored.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id);

-- One-time codes handed to the app after Google sign-in (PKCE-protected).
CREATE TABLE login_codes (
  code_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_challenge TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE TABLE plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  price_cents INTEGER NOT NULL,
  -- 1 credit = 1 spoken character.
  monthly_credits INTEGER NOT NULL,
  dodo_product_id TEXT UNIQUE
);
INSERT INTO plans (id, name, price_cents, monthly_credits, dodo_product_id)
VALUES ('starter', 'Pro', 1900, 150000, NULL);

CREATE TABLE subscriptions (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  dodo_subscription_id TEXT UNIQUE,
  dodo_customer_id TEXT,
  plan_id TEXT NOT NULL REFERENCES plans(id),
  status TEXT NOT NULL,
  period_start INTEGER,
  period_end INTEGER,
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
  credits_total INTEGER NOT NULL DEFAULT 0,
  credits_used INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);

-- Webhook ids already processed, so retries are applied once.
CREATE TABLE webhook_events (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  received_at INTEGER NOT NULL
);
