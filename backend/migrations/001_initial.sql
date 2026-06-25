-- LifeOS Agent Backend — Initial Schema
-- Run with: psql $DATABASE_URL -f migrations/001_initial.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Users ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id     TEXT        UNIQUE NOT NULL,  -- iOS identifierForVendor
    name          TEXT,
    gender        TEXT CHECK (gender IN ('femme', 'homme', 'autre', NULL)),
    apns_token    TEXT,                          -- push notification token
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_device_id ON users(device_id);

-- ── Module configurations (personalization) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS module_configs (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_type   TEXT        NOT NULL,  -- 'sport', 'nutrition', 'finance', etc.
    config        JSONB       NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, module_type)
);
CREATE INDEX IF NOT EXISTS idx_module_configs_user ON module_configs(user_id);

-- ── Goals ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS goals (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_type     TEXT        NOT NULL,
    title           TEXT        NOT NULL,
    description     TEXT,
    target_value    NUMERIC,
    current_value   NUMERIC     NOT NULL DEFAULT 0,
    unit            TEXT,
    frequency       TEXT        CHECK (frequency IN ('daily', 'weekly', 'monthly', 'once')),
    priority        INTEGER     NOT NULL DEFAULT 1 CHECK (priority BETWEEN 1 AND 5),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    due_date        TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_goals_user_module ON goals(user_id, module_type);
CREATE INDEX IF NOT EXISTS idx_goals_active ON goals(user_id) WHERE is_active;

-- ── Conversations ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversations (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_type   TEXT,
    title         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id, created_at DESC);

-- ── Messages ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id   UUID        NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role              TEXT        NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
    content           TEXT        NOT NULL,
    tool_call         JSONB,      -- {tool, args} if role=assistant+tool call
    tool_result       JSONB,      -- result payload if role=tool
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at ASC);

-- ── Tool execution audit log ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tool_executions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID        REFERENCES conversations(id) ON DELETE SET NULL,
    tool_name       TEXT        NOT NULL,
    args            JSONB       NOT NULL,
    result          JSONB,
    status          TEXT        NOT NULL CHECK (status IN ('success', 'error', 'rejected', 'timeout')),
    error_message   TEXT,
    duration_ms     INTEGER,
    executed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tool_exec_user ON tool_executions(user_id, executed_at DESC);

-- ── Sport logs ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sport_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    workout_type    TEXT        NOT NULL,
    duration_minutes INTEGER,
    sets            INTEGER,
    reps            INTEGER,
    weight_kg       NUMERIC,
    distance_km     NUMERIC,
    calories_burned INTEGER,
    notes           TEXT,
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sport_logs_user ON sport_logs(user_id, logged_at DESC);

-- ── Nutrition logs ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nutrition_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    meal_name   TEXT        NOT NULL,
    meal_type   TEXT        CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    calories    INTEGER,
    protein_g   NUMERIC,
    carbs_g     NUMERIC,
    fat_g       NUMERIC,
    logged_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_nutrition_user ON nutrition_logs(user_id, logged_at DESC);

-- ── Mobility logs ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS mobility_logs (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    km_added          NUMERIC     NOT NULL,
    fuel_level_before NUMERIC     CHECK (fuel_level_before BETWEEN 0 AND 100),
    fuel_level_after  NUMERIC     CHECK (fuel_level_after BETWEEN 0 AND 100),
    vehicle_label     TEXT,
    notes             TEXT,
    logged_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_mobility_user ON mobility_logs(user_id, logged_at DESC);

-- ── Finance logs ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS finance_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    income          NUMERIC     NOT NULL DEFAULT 0,
    fixed_expenses  NUMERIC     NOT NULL DEFAULT 0,
    variable_expenses NUMERIC   NOT NULL DEFAULT 0,
    savings_goal    NUMERIC     NOT NULL DEFAULT 0,
    period_label    TEXT,       -- e.g. "juin 2026"
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_finance_user ON finance_logs(user_id, logged_at DESC);

-- ── Habit snapshots (for notification scheduling) ─────────────────────────────
CREATE TABLE IF NOT EXISTS habit_snapshots (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    module_type     TEXT        NOT NULL,
    snapshot        JSONB       NOT NULL,  -- weekly stats
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_habit_snap_user ON habit_snapshots(user_id, created_at DESC);

-- ── Scheduled notifications ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS scheduled_notifications (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT        NOT NULL,
    body            TEXT        NOT NULL,
    module_type     TEXT,
    deep_link       TEXT,       -- e.g. "lifeos://module/sport"
    scheduled_for   TIMESTAMPTZ NOT NULL,
    sent            BOOLEAN     NOT NULL DEFAULT FALSE,
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notif_pending ON scheduled_notifications(scheduled_for)
    WHERE NOT sent;

-- ── Auto-update updated_at ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY['users', 'module_configs', 'goals'])
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION update_updated_at()', t, t
        );
    END LOOP;
END $$;
