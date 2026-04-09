-- Seed: 001_categories
-- Description: Hierarchical transaction category taxonomy.
--              3-level tree: root → primary → subcategory.
--              Designed to align with Plaid's personal_finance_category while
--              being human-friendly for UI display.
-- Run after: migrations 001–004

BEGIN;

-- ═══════════════════════════════════════════════════════════════════
-- ROOT CATEGORIES (level = 0)
-- ═══════════════════════════════════════════════════════════════════
INSERT INTO transaction_categories (slug, name, level, icon, color, is_income, is_transfer, sort_order)
VALUES
  ('income',          'Income',          0, '💰', '#22C55E', TRUE,  FALSE, 10),
  ('housing',         'Housing',         0, '🏠', '#6366F1', FALSE, FALSE, 20),
  ('transportation',  'Transportation',  0, '🚗', '#3B82F6', FALSE, FALSE, 30),
  ('food',            'Food & Dining',   0, '🍽️', '#F97316', FALSE, FALSE, 40),
  ('shopping',        'Shopping',        0, '🛍️', '#EC4899', FALSE, FALSE, 50),
  ('healthcare',      'Healthcare',      0, '🏥', '#14B8A6', FALSE, FALSE, 60),
  ('entertainment',   'Entertainment',   0, '🎬', '#A855F7', FALSE, FALSE, 70),
  ('personal_care',   'Personal Care',   0, '✂️', '#F43F5E', FALSE, FALSE, 80),
  ('education',       'Education',       0, '📚', '#0EA5E9', FALSE, FALSE, 90),
  ('financial',       'Financial',       0, '📊', '#84CC16', FALSE, FALSE, 100),
  ('business',        'Business',        0, '💼', '#64748B', FALSE, FALSE, 110),
  ('transfers',       'Transfers',       0, '↔️', '#94A3B8', FALSE, TRUE,  120),
  ('uncategorized',   'Uncategorized',   0, '❓', '#CBD5E1', FALSE, FALSE, 999)
ON CONFLICT (slug) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════
-- PRIMARY CATEGORIES (level = 1)
-- ═══════════════════════════════════════════════════════════════════

-- Income
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, TRUE, sort_order
FROM (VALUES
  ('income_salary',      'Salary & Wages',      '💵', 10),
  ('income_freelance',   'Freelance & Contract', '🖥️', 20),
  ('income_investments', 'Investments',          '📈', 30),
  ('income_rental',      'Rental Income',        '🏘️', 40),
  ('income_refunds',     'Refunds & Returns',    '↩️', 50),
  ('income_other',       'Other Income',         '💡', 60)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'income'
ON CONFLICT (slug) DO NOTHING;

-- Housing
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('housing_mortgage',    'Mortgage',               '🏦', 10),
  ('housing_rent',        'Rent',                   '🔑', 20),
  ('housing_utilities',   'Utilities',              '⚡', 30),
  ('housing_insurance',   'Home Insurance',         '🛡️', 40),
  ('housing_maintenance', 'Maintenance & Repairs',  '🔧', 50),
  ('housing_internet',    'Internet & Cable',       '📡', 60),
  ('housing_phone',       'Phone',                  '📱', 70)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'housing'
ON CONFLICT (slug) DO NOTHING;

-- Transportation
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('transport_car_payment', 'Car Payment',        '🚘', 10),
  ('transport_gas',         'Gas & Fuel',         '⛽', 20),
  ('transport_parking',     'Parking & Tolls',    '🅿️', 30),
  ('transport_rideshare',   'Rideshare & Taxi',   '🚕', 40),
  ('transport_transit',     'Public Transit',     '🚇', 50),
  ('transport_insurance',   'Auto Insurance',     '🛡️', 60),
  ('transport_maintenance', 'Auto Maintenance',   '🔧', 70),
  ('transport_flights',     'Flights',            '✈️', 80)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'transportation'
ON CONFLICT (slug) DO NOTHING;

-- Food & Dining
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('food_groceries',  'Groceries',          '🛒', 10),
  ('food_restaurant', 'Restaurants',        '🍴', 20),
  ('food_fast_food',  'Fast Food',          '🍔', 30),
  ('food_coffee',     'Coffee & Cafes',     '☕', 40),
  ('food_delivery',   'Food Delivery',      '🛵', 50),
  ('food_alcohol',    'Bars & Alcohol',     '🍺', 60)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'food'
ON CONFLICT (slug) DO NOTHING;

-- Shopping
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('shopping_clothing',     'Clothing & Apparel', '👕', 10),
  ('shopping_electronics',  'Electronics',        '💻', 20),
  ('shopping_home',         'Home & Garden',      '🌿', 30),
  ('shopping_sports',       'Sports & Outdoors',  '⚽', 40),
  ('shopping_gifts',        'Gifts & Occasions',  '🎁', 50),
  ('shopping_general',      'General Merchandise','🏪', 60),
  ('shopping_online',       'Online Shopping',    '📦', 70)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'shopping'
ON CONFLICT (slug) DO NOTHING;

-- Healthcare
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('health_medical',    'Doctor & Medical',   '👨‍⚕️', 10),
  ('health_dental',     'Dental',             '🦷', 20),
  ('health_vision',     'Vision & Optometry', '👁️', 30),
  ('health_pharmacy',   'Pharmacy',           '💊', 40),
  ('health_insurance',  'Health Insurance',   '🛡️', 50),
  ('health_mental',     'Mental Health',      '🧠', 60),
  ('health_fitness',    'Fitness & Gym',      '🏋️', 70)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'healthcare'
ON CONFLICT (slug) DO NOTHING;

-- Entertainment
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('ent_streaming',   'Streaming Services', '📺', 10),
  ('ent_movies',      'Movies & Theater',   '🎥', 20),
  ('ent_events',      'Events & Concerts',  '🎤', 30),
  ('ent_gaming',      'Gaming',             '🎮', 40),
  ('ent_hobbies',     'Hobbies',            '🎨', 50),
  ('ent_travel',      'Travel & Hotels',    '🏨', 60),
  ('ent_books',       'Books & Music',      '📖', 70)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'entertainment'
ON CONFLICT (slug) DO NOTHING;

-- Personal Care
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('care_salon',     'Hair & Salon',         '💇', 10),
  ('care_beauty',    'Beauty & Cosmetics',   '💄', 20),
  ('care_laundry',   'Laundry & Dry Clean',  '👔', 30),
  ('care_other',     'Other Personal Care',  '🪥', 40)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'personal_care'
ON CONFLICT (slug) DO NOTHING;

-- Education
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('edu_tuition',    'Tuition & Fees',    '🎓', 10),
  ('edu_books',      'Books & Supplies',  '📚', 20),
  ('edu_courses',    'Online Courses',    '💡', 30),
  ('edu_student_loan','Student Loans',    '🏦', 40)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'education'
ON CONFLICT (slug) DO NOTHING;

-- Financial
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('fin_credit_card',   'Credit Card Payments', '💳', 10),
  ('fin_loan',          'Loan Payments',        '🏦', 20),
  ('fin_savings',       'Savings',              '🐷', 30),
  ('fin_investments',   'Investment Purchases',  '📈', 40),
  ('fin_fees',          'Bank Fees & Charges',  '💸', 50),
  ('fin_insurance_life','Life Insurance',       '🛡️', 60),
  ('fin_taxes',         'Taxes',                '🧾', 70)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'financial'
ON CONFLICT (slug) DO NOTHING;

-- Business
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_income, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, FALSE, sort_order
FROM (VALUES
  ('biz_software',      'Software & Subscriptions', '🖥️', 10),
  ('biz_office',        'Office Supplies',           '🗂️', 20),
  ('biz_professional',  'Professional Services',     '⚖️', 30),
  ('biz_advertising',   'Advertising & Marketing',   '📣', 40),
  ('biz_travel',        'Business Travel',           '✈️', 50),
  ('biz_meals',         'Business Meals',            '🍽️', 60)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'business'
ON CONFLICT (slug) DO NOTHING;

-- Transfers
INSERT INTO transaction_categories (slug, name, level, parent_id, icon, color, is_transfer, sort_order)
SELECT slug, name, 1, p.id, icon, p.color, TRUE, sort_order
FROM (VALUES
  ('transfer_account',  'Account Transfer',   '↔️', 10),
  ('transfer_atm',      'ATM Withdrawal',     '🏧', 20),
  ('transfer_zelle',    'Zelle / Venmo',      '📲', 30),
  ('transfer_paypal',   'PayPal',             '🅿️', 40),
  ('transfer_check',    'Check',              '📝', 50)
) AS v(slug, name, icon, sort_order)
JOIN transaction_categories p ON p.slug = 'transfers'
ON CONFLICT (slug) DO NOTHING;

COMMIT;
