-- Migration 003 — Challenge last check-in tracking
ALTER TABLE life_challenges ADD COLUMN IF NOT EXISTS last_checkin_at TIMESTAMPTZ;
