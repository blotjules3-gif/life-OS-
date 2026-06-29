from __future__ import annotations

"""
All tool definitions in Mistral function-calling format.
Each tool is a dict with type=function and a function description + JSON schema.

RULES:
- Tools never perform calculations — they delegate to service layer.
- Finance tools NEVER produce buy/sell advice.
- Every tool has strict required/optional parameters.
"""

TOOL_DEFINITIONS: list[dict] = [

    # ── Meta / Personalization ─────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "get_module_config",
            "description": "Retrieve the current personalization configuration for a module.",
            "parameters": {
                "type": "object",
                "required": ["module"],
                "properties": {
                    "module": {
                        "type": "string",
                        "description": "Module name: sport | nutrition | finance | mobility | productivity | sleep | mind | learning",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "update_module_config",
            "description": "Save personalization settings for a module. Call this when the user expresses a preference or goal quantity (e.g. 'je veux m'entraîner 3x par semaine').",
            "parameters": {
                "type": "object",
                "required": ["module", "config"],
                "properties": {
                    "module": {"type": "string"},
                    "config": {
                        "type": "object",
                        "description": "Key-value config to merge into the module's current config.",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "list_goals",
            "description": "List user's goals for a module.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {
                    "module": {"type": "string"},
                    "active_only": {"type": "boolean", "default": True},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "create_goal",
            "description": "Create a new goal for the user in the current module.",
            "parameters": {
                "type": "object",
                "required": ["module", "title"],
                "properties": {
                    "module": {"type": "string"},
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "target_value": {"type": "number"},
                    "unit": {"type": "string"},
                    "frequency": {"type": "string", "enum": ["daily", "weekly", "monthly", "once"]},
                    "priority": {"type": "integer", "minimum": 1, "maximum": 5},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "delete_goal",
            "description": "Deactivate (soft-delete) a goal by its ID.",
            "parameters": {
                "type": "object",
                "required": ["goal_id"],
                "properties": {
                    "goal_id": {"type": "string", "format": "uuid"},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "create_todo",
            "description": "Create a to-do task in the user's app. Use when the user wants to add something to their task list.",
            "parameters": {
                "type": "object",
                "required": ["title"],
                "properties": {
                    "title": {"type": "string", "description": "Task title in French"},
                    "module": {"type": "string", "description": "Related module if applicable"},
                    "priority": {"type": "integer", "minimum": 1, "maximum": 5, "default": 2},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "schedule_followup",
            "description": "Schedule a follow-up notification to check in with the user. Use when the user commits to doing something (e.g. 'je vais courir demain').",
            "parameters": {
                "type": "object",
                "required": ["message", "delay_hours"],
                "properties": {
                    "message": {"type": "string", "description": "Follow-up message in French, max 80 chars"},
                    "delay_hours": {"type": "number", "minimum": 1, "maximum": 168, "description": "Hours until the follow-up"},
                    "module": {"type": "string"},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "get_user_context",
            "description": "Get a summary of the user's current module configurations and active goals. Call this when you need to understand the user's current state before giving advice.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {},
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "update_user_profile",
            "description": "Update the user's profile (name and/or gender). Call this as soon as you learn the user's name or gender during the interview.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {
                    "name": {"type": "string", "description": "User's first name"},
                    "gender": {
                        "type": "string",
                        "enum": ["homme", "femme", "autre"],
                        "description": "User's gender — determines if cycle questions are shown",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "remember_user_info",
            "description": "Save an important fact about the user that must be remembered in ALL future conversations. Call this as soon as you learn something significant: a health condition, a physical constraint, a strong preference, a recurring failure, a major life context. Do NOT call for trivial info.",
            "parameters": {
                "type": "object",
                "required": ["key", "value", "category"],
                "properties": {
                    "key": {
                        "type": "string",
                        "description": "Unique snake_case key for this fact. Ex: 'health_diabetes', 'hates_running', 'works_night_shift', 'has_back_pain', 'is_vegetarian'",
                    },
                    "value": {
                        "type": "string",
                        "description": "The fact to remember, in French, max 200 chars. Ex: 'Diabète de type 2 — surveiller les pics glycémiques, éviter le sucre rapide à jeun'",
                    },
                    "category": {
                        "type": "string",
                        "enum": ["health", "lifestyle", "preference", "constraint", "goal_context"],
                        "description": "Category of the fact",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "ask_clarification",
            "description": "Ask the user a clarifying question when the request is ambiguous. Use ONLY when you genuinely cannot proceed without more information.",
            "parameters": {
                "type": "object",
                "required": ["question"],
                "properties": {
                    "question": {"type": "string", "description": "The clarifying question in French."},
                    "options": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Optional list of choices to present to the user.",
                    },
                },
            },
        },
    },

    # ── Sport ──────────────────────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "log_workout",
            "description": "Log a completed workout session.",
            "parameters": {
                "type": "object",
                "required": ["workout_type", "duration_minutes"],
                "properties": {
                    "workout_type": {"type": "string", "description": "e.g. 'musculation', 'course', 'vélo', 'yoga'"},
                    "duration_minutes": {"type": "integer", "minimum": 1, "maximum": 600},
                    "sets": {"type": "integer", "minimum": 1},
                    "reps": {"type": "integer", "minimum": 1},
                    "weight_kg": {"type": "number", "minimum": 0},
                    "distance_km": {"type": "number", "minimum": 0},
                    "calories_burned": {"type": "integer", "minimum": 0},
                    "notes": {"type": "string"},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "analyze_sport_progress",
            "description": "Analyze the user's workout history over a period and return stats.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {
                    "days": {"type": "integer", "minimum": 1, "maximum": 365, "default": 30},
                },
            },
        },
    },

    # ── Nutrition ──────────────────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "add_meal",
            "description": "Log a meal with nutritional values.",
            "parameters": {
                "type": "object",
                "required": ["meal_name"],
                "properties": {
                    "meal_name": {"type": "string"},
                    "meal_type": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
                    "calories": {"type": "integer", "minimum": 0},
                    "protein_g": {"type": "number", "minimum": 0},
                    "carbs_g": {"type": "number", "minimum": 0},
                    "fat_g": {"type": "number", "minimum": 0},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "compute_calorie_balance",
            "description": "Compute today's calorie intake vs the user's goal.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {},
            },
        },
    },

    # ── Mobility ───────────────────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "add_km",
            "description": "Log kilometers driven.",
            "parameters": {
                "type": "object",
                "required": ["km_added"],
                "properties": {
                    "km_added": {"type": "number", "minimum": 0.1},
                    "fuel_level_before": {"type": "number", "minimum": 0, "maximum": 100},
                    "vehicle_label": {"type": "string"},
                    "notes": {"type": "string"},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "estimate_fuel_remaining",
            "description": "Estimate remaining fuel/range based on logged km and vehicle config.",
            "parameters": {
                "type": "object",
                "required": [],
                "properties": {},
            },
        },
    },

    # ── Habits ────────────────────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "create_habit",
            "description": (
                "Propose a new habit to track in the user's Habit Tracker. "
                "The habit starts as 'pending' — the user confirms it in the app. "
                "ONLY call after the user agrees to add a habit. "
                "For each module, propose ONE specific, actionable habit."
            ),
            "parameters": {
                "type": "object",
                "required": ["title", "module"],
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Habit name in French, short and actionable. Ex: '20 min de sport', 'Boire 2L d\'eau', '10 min de méditation'",
                    },
                    "module": {
                        "type": "string",
                        "description": "Module this habit belongs to: fitness | nutrition | sleep | mind | productivity | finance | learning | social | home | medical",
                    },
                },
            },
        },
    },

    # ── Module management ──────────────────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "add_module",
            "description": (
                "Add a new module to the user's active profile. "
                "ONLY call after the user has explicitly agreed to add it. "
                "Never add a module without clear confirmation."
            ),
            "parameters": {
                "type": "object",
                "required": ["module"],
                "properties": {
                    "module": {
                        "type": "string",
                        "description": "Module key: fitness | nutrition | sleep | finance | productivity | mind | learning | mobility | career | invest | social | home | admin | travel | cycle | looks | pets",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Brief reason why this module was added, in French",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "remove_module",
            "description": (
                "Remove a module from the user's active profile. "
                "Use when: (1) the module adds friction without value, "
                "(2) the user says they don't use it, "
                "(3) the habit is formed and the module is no longer needed. "
                "ONLY call after explicit user agreement."
            ),
            "parameters": {
                "type": "object",
                "required": ["module", "reason_type"],
                "properties": {
                    "module": {
                        "type": "string",
                        "description": "Module key to remove",
                    },
                    "reason_type": {
                        "type": "string",
                        "enum": ["too_constraining", "habit_formed", "not_relevant", "user_request"],
                        "description": "Why the module is being removed",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Brief explanation in French",
                    },
                },
            },
        },
    },

    # ── Life Challenges (heavy behaviour changes) ──────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "create_life_challenge",
            "description": (
                "Create a life challenge for a heavy, long-term behaviour change "
                "(drink more water, start sport, stop smoking, etc.). "
                "ONLY call this after the user has explicitly agreed to the proposed plan. "
                "Never create a challenge unilaterally — always propose first."
            ),
            "parameters": {
                "type": "object",
                "required": ["title", "challenge_type"],
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Short challenge title in French. Ex: 'Boire 8 verres d'eau par jour'",
                    },
                    "challenge_type": {
                        "type": "string",
                        "enum": ["water", "sport", "smoking", "nutrition", "sleep", "meditation", "custom"],
                        "description": "Category of the life challenge",
                    },
                    "daily_target": {
                        "type": "number",
                        "description": "Daily numeric target. Ex: 8 for 8 glasses, 30 for 30 min sport",
                    },
                    "unit": {
                        "type": "string",
                        "description": "Unit for the daily target. Ex: 'verres', 'minutes', 'séances', 'cigarettes restantes'",
                    },
                    "duration_days": {
                        "type": "integer",
                        "minimum": 7,
                        "maximum": 90,
                        "description": "Duration in days. 21 = 3 weeks habit formation, 30 = 1 month, 90 = 3 months",
                    },
                    "notes": {
                        "type": "string",
                        "description": "Optional strategy or first-step notes to store with the challenge",
                    },
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "check_in_challenge",
            "description": (
                "Mark today as completed for a life challenge and update the streak. "
                "Call when the user confirms they completed their daily challenge task. "
                "Use list_goals to find the challenge_id if not known."
            ),
            "parameters": {
                "type": "object",
                "required": ["challenge_id"],
                "properties": {
                    "challenge_id": {
                        "type": "string",
                        "format": "uuid",
                        "description": "ID of the challenge to check in",
                    },
                },
            },
        },
    },

    # ── Finance (STRICT SAFETY MODE) ──────────────────────────────────────────

    {
        "type": "function",
        "function": {
            "name": "analyze_cashflow",
            "description": "Analyze the user's income vs expenses. Returns balance and savings capacity. NEVER gives investment advice.",
            "parameters": {
                "type": "object",
                "required": ["income", "fixed_expenses", "variable_expenses"],
                "properties": {
                    "income": {"type": "number", "minimum": 0},
                    "fixed_expenses": {"type": "number", "minimum": 0},
                    "variable_expenses": {"type": "number", "minimum": 0},
                    "period_label": {"type": "string"},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "compute_investable_amount",
            "description": "Compute the investable amount after savings goal. Returns a number — not a recommendation.",
            "parameters": {
                "type": "object",
                "required": ["income", "total_expenses", "savings_goal_pct"],
                "properties": {
                    "income": {"type": "number", "minimum": 0},
                    "total_expenses": {"type": "number", "minimum": 0},
                    "savings_goal_pct": {"type": "number", "minimum": 0, "maximum": 100},
                },
            },
        },
    },

    {
        "type": "function",
        "function": {
            "name": "simulate_allocation",
            "description": "Show a theoretical allocation split by risk profile. This is a SIMULATION only — not financial advice. Never recommends specific assets.",
            "parameters": {
                "type": "object",
                "required": ["amount", "risk_profile"],
                "properties": {
                    "amount": {"type": "number", "minimum": 0},
                    "risk_profile": {
                        "type": "string",
                        "enum": ["conservative", "moderate", "aggressive"],
                    },
                },
            },
        },
    },
]


def get_tools_for_module(module: str | None) -> list[dict]:
    """Return only the tools relevant for a given module (+ always-available meta tools)."""
    meta_tools = {"get_module_config", "update_module_config", "list_goals", "create_goal", "delete_goal", "ask_clarification", "create_todo", "schedule_followup", "get_user_context", "update_user_profile", "remember_user_info", "create_life_challenge", "add_module", "remove_module", "check_in_challenge", "create_habit"}
    module_tool_map: dict[str, set[str]] = {
        "sport": {"log_workout", "analyze_sport_progress"},
        "nutrition": {"add_meal", "compute_calorie_balance"},
        "mobility": {"add_km", "estimate_fuel_remaining"},
        "finance": {"analyze_cashflow", "compute_investable_amount", "simulate_allocation"},
        "productivity": set(),
        "sleep": set(),
        "mind": set(),
        "learning": set(),
    }

    allowed_names = meta_tools.copy()
    if module and module in module_tool_map:
        allowed_names |= module_tool_map[module]

    if not module:
        allowed_names = {d["function"]["name"] for d in TOOL_DEFINITIONS}

    return [d for d in TOOL_DEFINITIONS if d["function"]["name"] in allowed_names]
