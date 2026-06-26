-- LifeOS Agent Backend — Life Challenges & user_notes column
-- Run with: psql -U lifeos -d lifeos_agent -f migrations/002_life_challenges.sql

-- Add user_notes column if it doesn't exist (added in previous session)
ALTER TABLE users ADD COLUMN IF NOT EXISTS user_notes JSONB NOT NULL DEFAULT '{}';

-- Life challenges table for heavy behaviour changes
CREATE TABLE IF NOT EXISTS life_challenges (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           TEXT        NOT NULL,
    challenge_type  VARCHAR(30) NOT NULL,   -- water, sport, smoking, meditation, nutrition, sleep, custom
    daily_target    NUMERIC,
    unit            TEXT,
    duration_days   INTEGER,
    streak_days     INTEGER     NOT NULL DEFAULT 0,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    notes           TEXT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_life_challenges_user ON life_challenges(user_id);
CREATE INDEX IF NOT EXISTS idx_life_challenges_active ON life_challenges(user_id, is_active);
