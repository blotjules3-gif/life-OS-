from __future__ import annotations

from app.models.db import DailyCheckin


def compute_energy_score(checkin: DailyCheckin) -> int:
    """Calcule le Score d'Énergie (0–100) à partir des données du check-in.

    Pondération :
        Sommeil qualité   30 pts  (sleep_quality 1–5)
        Sommeil durée     10 pts  (sleep_hours — 8h = parfait)
        Hydratation       20 pts  (water_ml / 2 500)
        Habitudes         20 pts  (habits_done / habits_total)
        Humeur            15 pts  (mood 1–5)
        Anti-fatigue       5 pts  (fatigue inversé 1–5)
    Total possible       100 pts
    """
    score = 0.0

    # Sommeil — qualité (0–30)
    if checkin.sleep_quality is not None:
        score += (checkin.sleep_quality / 5) * 30

    # Sommeil — durée (0–10, optimal à 8 h)
    if checkin.sleep_hours is not None:
        hours = float(checkin.sleep_hours)
        ratio = min(hours / 8.0, 1.0)
        score += ratio * 10

    # Hydratation (0–20, objectif 2 500 ml par défaut)
    if checkin.water_ml is not None:
        ratio = min(checkin.water_ml / 2500, 1.0)
        score += ratio * 20

    # Habitudes (0–20)
    if checkin.habits_total and checkin.habits_total > 0 and checkin.habits_done is not None:
        ratio = min(checkin.habits_done / checkin.habits_total, 1.0)
        score += ratio * 20

    # Humeur (0–15)
    if checkin.mood is not None:
        score += (checkin.mood / 5) * 15

    # Anti-fatigue (0–5, fatigue 1=reposé → 5 pts, fatigue 5=épuisé → 0 pt)
    if checkin.fatigue is not None:
        score += ((6 - checkin.fatigue) / 5) * 5

    return round(min(max(score, 0), 100))


def score_label(score: int) -> str:
    if score >= 85:
        return "Excellent"
    if score >= 70:
        return "Bon"
    if score >= 50:
        return "Correct"
    if score >= 30:
        return "Faible"
    return "Très faible"


def score_color(score: int) -> str:
    if score >= 85:
        return "#34C759"
    if score >= 70:
        return "#30D158"
    if score >= 50:
        return "#FF9F0A"
    if score >= 30:
        return "#FF6B35"
    return "#FF3B30"
