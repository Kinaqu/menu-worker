PRAGMA defer_foreign_keys = on;

-- =========================================================
-- 1. HOUSEHOLDS / PROFILES
-- =========================================================

CREATE TABLE IF NOT EXISTS households (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS profiles (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE
);

-- =========================================================
-- 2. INGREDIENTS
-- =========================================================

CREATE TABLE IF NOT EXISTS ingredients (
  id INTEGER PRIMARY KEY,
  ingredient_key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  base_unit TEXT NOT NULL CHECK (base_unit IN ('g', 'ml', 'pcs', 'cans')),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ingredient_aliases (
  id INTEGER PRIMARY KEY,
  ingredient_id INTEGER NOT NULL,
  alias TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE
);

-- =========================================================
-- 3. MEAL TEMPLATES
-- =========================================================

CREATE TABLE IF NOT EXISTS meal_templates (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  description TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS meal_template_items (
  id INTEGER PRIMARY KEY,
  meal_template_id INTEGER NOT NULL,
  ingredient_id INTEGER NOT NULL,
  amount REAL NOT NULL CHECK (amount > 0),
  unit TEXT NOT NULL CHECK (unit IN ('g', 'ml', 'pcs', 'cans')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_optional INTEGER NOT NULL DEFAULT 0 CHECK (is_optional IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (meal_template_id) REFERENCES meal_templates(id) ON DELETE CASCADE,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT,
  UNIQUE (meal_template_id, ingredient_id)
);

-- =========================================================
-- 4. PLAN TEMPLATES (циклы 7/14/28 и т.д.)
-- =========================================================

CREATE TABLE IF NOT EXISTS plan_templates (
  id INTEGER PRIMARY KEY,
  household_id INTEGER,
  name TEXT NOT NULL,
  goal TEXT,
  cycle_days INTEGER NOT NULL CHECK (cycle_days >= 1 AND cycle_days <= 31),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'archived')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS plan_template_days (
  id INTEGER PRIMARY KEY,
  plan_template_id INTEGER NOT NULL,
  day_index INTEGER NOT NULL CHECK (day_index >= 1 AND day_index <= 31),
  label TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (plan_template_id) REFERENCES plan_templates(id) ON DELETE CASCADE,
  UNIQUE (plan_template_id, day_index)
);

CREATE TABLE IF NOT EXISTS plan_template_day_meals (
  id INTEGER PRIMARY KEY,
  plan_template_day_id INTEGER NOT NULL,
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  meal_template_id INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (plan_template_day_id) REFERENCES plan_template_days(id) ON DELETE CASCADE,
  FOREIGN KEY (meal_template_id) REFERENCES meal_templates(id) ON DELETE RESTRICT,
  UNIQUE (plan_template_day_id, meal_type, sort_order)
);

-- =========================================================
-- 5. PUBLISHED DAYS
-- Это "замороженный" рацион на конкретную дату.
-- Фронт читает только отсюда.
-- =========================================================

CREATE TABLE IF NOT EXISTS published_days (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  profile_id INTEGER NOT NULL,
  date TEXT NOT NULL, -- YYYY-MM-DD
  plan_template_id INTEGER,
  source_day_index INTEGER,
  status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'archived')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (plan_template_id) REFERENCES plan_templates(id) ON DELETE SET NULL,
  UNIQUE (profile_id, date)
);

CREATE TABLE IF NOT EXISTS published_day_meals (
  id INTEGER PRIMARY KEY,
  published_day_id INTEGER NOT NULL,
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  meal_template_id INTEGER,
  title_snapshot TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (published_day_id) REFERENCES published_days(id) ON DELETE CASCADE,
  FOREIGN KEY (meal_template_id) REFERENCES meal_templates(id) ON DELETE SET NULL,
  UNIQUE (published_day_id, meal_type, sort_order)
);

CREATE TABLE IF NOT EXISTS published_day_meal_items (
  id INTEGER PRIMARY KEY,
  published_day_meal_id INTEGER NOT NULL,
  ingredient_id INTEGER NOT NULL,
  ingredient_name_snapshot TEXT NOT NULL,
  ingredient_key_snapshot TEXT NOT NULL,
  amount REAL NOT NULL CHECK (amount > 0),
  unit TEXT NOT NULL CHECK (unit IN ('g', 'ml', 'pcs', 'cans')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (published_day_meal_id) REFERENCES published_day_meals(id) ON DELETE CASCADE,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT,
  UNIQUE (published_day_meal_id, ingredient_id)
);

-- =========================================================
-- 6. GROCERY LISTS
-- draft -> ready -> partially_applied -> applied / cancelled
-- =========================================================

CREATE TABLE IF NOT EXISTS grocery_lists (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  profile_id INTEGER,
  period_type TEXT NOT NULL CHECK (period_type IN ('week', 'month', 'custom')),
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ready', 'partially_applied', 'applied', 'cancelled')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  applied_at TEXT,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS grocery_list_items (
  id INTEGER PRIMARY KEY,
  grocery_list_id INTEGER NOT NULL,
  ingredient_id INTEGER NOT NULL,
  ingredient_name_snapshot TEXT NOT NULL,
  ingredient_key_snapshot TEXT NOT NULL,
  unit TEXT NOT NULL CHECK (unit IN ('g', 'ml', 'pcs', 'cans')),
  required_amount REAL NOT NULL CHECK (required_amount >= 0),
  stock_amount_snapshot REAL NOT NULL DEFAULT 0 CHECK (stock_amount_snapshot >= 0),
  to_buy_amount REAL NOT NULL DEFAULT 0 CHECK (to_buy_amount >= 0),
  purchased_amount REAL NOT NULL DEFAULT 0 CHECK (purchased_amount >= 0),
  is_checked INTEGER NOT NULL DEFAULT 0 CHECK (is_checked IN (0, 1)),
  is_applied INTEGER NOT NULL DEFAULT 0 CHECK (is_applied IN (0, 1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (grocery_list_id) REFERENCES grocery_lists(id) ON DELETE CASCADE,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT,
  UNIQUE (grocery_list_id, ingredient_id)
);

-- =========================================================
-- 7. STOCK
-- Текущий баланс на складе
-- =========================================================

CREATE TABLE IF NOT EXISTS stock_items (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  ingredient_id INTEGER NOT NULL,
  unit TEXT NOT NULL CHECK (unit IN ('g', 'ml', 'pcs', 'cans')),
  amount REAL NOT NULL DEFAULT 0 CHECK (amount >= 0),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT,
  UNIQUE (household_id, ingredient_id)
);

-- =========================================================
-- 8. STOCK MOVEMENTS (ledger / audit)
-- delta_amount:
--   +1000 = пришло на склад
--   -150  = списано со склада
-- =========================================================

CREATE TABLE IF NOT EXISTS stock_movements (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  ingredient_id INTEGER NOT NULL,
  unit TEXT NOT NULL CHECK (unit IN ('g', 'ml', 'pcs', 'cans')),
  delta_amount REAL NOT NULL CHECK (delta_amount != 0),
  movement_type TEXT NOT NULL CHECK (
    movement_type IN (
      'purchase_applied',
      'meal_consumed',
      'day_consumed',
      'manual_adjustment',
      'reset'
    )
  ),
  reference_type TEXT CHECK (
    reference_type IN (
      'grocery_list',
      'grocery_list_item',
      'published_day',
      'published_day_meal',
      'manual'
    )
  ),
  reference_id INTEGER,
  note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
  FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT
);

-- =========================================================
-- 9. CONSUMPTION EVENTS
-- Чтобы не списывать повторно один и тот же день / meal
-- =========================================================

CREATE TABLE IF NOT EXISTS meal_consumption_events (
  id INTEGER PRIMARY KEY,
  household_id INTEGER NOT NULL,
  profile_id INTEGER NOT NULL,
  published_day_id INTEGER NOT NULL,
  published_day_meal_id INTEGER,
  date TEXT NOT NULL,
  meal_type TEXT CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'applied', 'skipped')),
  applied_to_stock_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (published_day_id) REFERENCES published_days(id) ON DELETE CASCADE,
  FOREIGN KEY (published_day_meal_id) REFERENCES published_day_meals(id) ON DELETE CASCADE
);

-- Уникальность на уровне meal-события
CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_consumption_unique_meal
ON meal_consumption_events(profile_id, date, meal_type)
WHERE meal_type IS NOT NULL;

-- Уникальность на уровне "весь день списан"
CREATE UNIQUE INDEX IF NOT EXISTS idx_meal_consumption_unique_day
ON meal_consumption_events(profile_id, date)
WHERE meal_type IS NULL;

-- =========================================================
-- 10. IDEMPOTENCY
-- Для безопасных повторов write-endpoints
-- =========================================================

CREATE TABLE IF NOT EXISTS idempotency_keys (
  id INTEGER PRIMARY KEY,
  scope TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT,
  status TEXT NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing', 'completed', 'failed')),
  resource_type TEXT,
  resource_id INTEGER,
  response_payload TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT,
  UNIQUE (scope, idempotency_key)
);

-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_profiles_household_id
ON profiles(household_id);

CREATE INDEX IF NOT EXISTS idx_ingredients_key
ON ingredients(ingredient_key);

CREATE INDEX IF NOT EXISTS idx_meal_template_items_meal_template_id
ON meal_template_items(meal_template_id);

CREATE INDEX IF NOT EXISTS idx_plan_template_days_plan_template_id
ON plan_template_days(plan_template_id);

CREATE INDEX IF NOT EXISTS idx_plan_template_day_meals_plan_template_day_id
ON plan_template_day_meals(plan_template_day_id);

CREATE INDEX IF NOT EXISTS idx_published_days_profile_date
ON published_days(profile_id, date);

CREATE INDEX IF NOT EXISTS idx_published_days_household_date
ON published_days(household_id, date);

CREATE INDEX IF NOT EXISTS idx_published_day_meals_published_day_id
ON published_day_meals(published_day_id);

CREATE INDEX IF NOT EXISTS idx_published_day_meal_items_published_day_meal_id
ON published_day_meal_items(published_day_meal_id);

CREATE INDEX IF NOT EXISTS idx_grocery_lists_household_status_created_at
ON grocery_lists(household_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_grocery_list_items_grocery_list_id
ON grocery_list_items(grocery_list_id);

CREATE INDEX IF NOT EXISTS idx_stock_items_household_ingredient
ON stock_items(household_id, ingredient_id);

CREATE INDEX IF NOT EXISTS idx_stock_movements_household_created_at
ON stock_movements(household_id, created_at);

CREATE INDEX IF NOT EXISTS idx_stock_movements_ingredient_created_at
ON stock_movements(ingredient_id, created_at);

CREATE INDEX IF NOT EXISTS idx_idempotency_scope_key
ON idempotency_keys(scope, idempotency_key);

PRAGMA optimize;
PRAGMA defer_foreign_keys = off;