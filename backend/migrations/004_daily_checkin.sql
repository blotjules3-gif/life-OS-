-- Migration 004: table daily_checkins pour le Score d'Énergie

CREATE TABLE IF NOT EXISTS daily_checkins (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    checkin_date    DATE NOT NULL,

    -- Sommeil (posé au réveil)
    sleep_quality   SMALLINT CHECK (sleep_quality BETWEEN 1 AND 5),
    sleep_hours     NUMERIC(4,1),

    -- État subjectif (posé au réveil)
    mood            SMALLINT CHECK (mood BETWEEN 1 AND 5),
    fatigue         SMALLINT CHECK (fatigue BETWEEN 1 AND 5),  -- 1=reposé, 5=épuisé

    -- Données du jour (remplies au fil de la journée)
    water_ml        INTEGER,
    habits_done     INTEGER,
    habits_total    INTEGER,
    sport_minutes   INTEGER,

    -- Score calculé et stocké (0-100)
    energy_score    SMALLINT CHECK (energy_score BETWEEN 0 AND 100),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (user_id, checkin_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_checkins_user_date
    ON daily_checkins (user_id, checkin_date DESC);
