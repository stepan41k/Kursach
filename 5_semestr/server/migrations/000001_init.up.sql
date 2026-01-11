CREATE TYPE user_role_type AS ENUM ('admin', 'manager', 'client');
CREATE TYPE contract_status AS ENUM ('draft', 'active', 'closed', 'defaulted');
CREATE TYPE operation_type AS ENUM ('issue', 'scheduled_payment', 'early_repayment', 'penalty');

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO roles (name, description) VALUES 
('admin', 'Полный доступ к системе'),
('manager', 'Управление продуктами и одобрение кредитов'),
('client', 'Клиент банка');

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    role_id INT NOT NULL REFERENCES roles(id),
    login VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE employees (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE REFERENCES users(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    position VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100)
);

CREATE TABLE clients (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    passport_series VARCHAR(4) NOT NULL,
    passport_number VARCHAR(6) NOT NULL,
    passport_issued_by TEXT,
    date_of_birth DATE NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (passport_series, passport_number)
);

CREATE TABLE credit_products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    min_amount NUMERIC(15, 2) NOT NULL,
    max_amount NUMERIC(15, 2) NOT NULL,
    min_term_months INT NOT NULL,
    max_term_months INT NOT NULL,
    interest_rate NUMERIC(5, 2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE loan_contracts (
    id BIGSERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    client_id BIGINT NOT NULL REFERENCES clients(id),
    product_id INT NOT NULL REFERENCES credit_products(id),
    approved_by_employee_id BIGINT REFERENCES employees(id),
    balance NUMERIC(15, 2) NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    interest_rate NUMERIC(5, 2) NOT NULL,
    term_months INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status contract_status DEFAULT 'draft',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);

CREATE TABLE repayment_schedule (
    id BIGSERIAL PRIMARY KEY,
    contract_id BIGINT NOT NULL REFERENCES loan_contracts(id) ON DELETE CASCADE,
    payment_date DATE NOT NULL,
    payment_amount NUMERIC(15, 2) NOT NULL,
    principal_amount NUMERIC(15, 2) NOT NULL,
    interest_amount NUMERIC(15, 2) NOT NULL,
    remaining_balance NUMERIC(15, 2) NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    paid_at TIMESTAMPTZ
);

CREATE TABLE operations (
    id BIGSERIAL PRIMARY KEY,
    contract_id BIGINT NOT NULL REFERENCES loan_contracts(id),
    employee_id BIGINT REFERENCES employees(id),
    operation_type operation_type NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    operation_date TIMESTAMPTZ DEFAULT NOW(),
    description TEXT
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    action_type VARCHAR(50) NOT NULL,
    entity_name VARCHAR(50) NOT NULL,
    entity_id BIGINT,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_clients_passport ON clients(passport_series, passport_number);
CREATE INDEX idx_clients_last_name ON clients(last_name);
CREATE INDEX idx_contracts_client ON loan_contracts(client_id);
CREATE INDEX idx_schedule_contract ON repayment_schedule(contract_id);
CREATE INDEX idx_operations_contract ON operations(contract_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);

INSERT INTO credit_products (name, min_amount, max_amount, min_term_months, max_term_months, interest_rate, is_active)
VALUES 
('Потребительский "Легкий"', 10000, 500000, 3, 36, 18.5, true),
('Автокредит "Драйв"', 300000, 5000000, 12, 60, 12.0, true),
('Потребительский "На любые цели"', 30000, 5000000, 3, 60, 18.9, true),
('Ипотека "Семейная"', 1000000, 50000000, 120, 360, 6.0, true),
('Автокредит "Движение"', 500000, 10000000, 12, 84, 13.5, true),
('Кредитная карта "100 дней"', 10000, 300000, 12, 24, 29.9, true),
('Рефинансирование', 300000, 3000000, 12, 60, 15.0, true)
ON CONFLICT DO NOTHING;


INSERT INTO users (role_id, login, password_hash, is_active)
SELECT id, 'admin', 'secret', true FROM roles WHERE name = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO users (role_id, login, password_hash, is_active)
SELECT id, 'manager', 'secret', true FROM roles WHERE name = 'manager'
ON CONFLICT DO NOTHING;

INSERT INTO employees (user_id, first_name, last_name, position)
SELECT id, 'Иван', 'Иванов', 'Старший менеджер' FROM users WHERE login = 'manager'
ON CONFLICT DO NOTHING;

INSERT INTO employees (user_id, first_name, last_name, position)
SELECT id, 'Сергей', 'Админов', 'Администратор' FROM users WHERE login = 'admin'
ON CONFLICT DO NOTHING;


-- Расчет ежемесячного аннуитетного платежа
CREATE OR REPLACE FUNCTION calculate_annuity_payment(
    p_amount NUMERIC, 
    p_rate_year NUMERIC, 
    p_term_months INT
) RETURNS NUMERIC AS $$
DECLARE
    v_rate_month NUMERIC;
BEGIN
    v_rate_month := (p_rate_year / 100) / 12;
    RETURN ROUND(p_amount * (v_rate_month * POWER(1 + v_rate_month, p_term_months)) / 
           (POWER(1 + v_rate_month, p_term_months) - 1), 2);
END;
$$ LANGUAGE plpgsql;

-- Процедура генерации графика платежей
CREATE OR REPLACE PROCEDURE generate_repayment_schedule(p_contract_id BIGINT) AS $$
DECLARE
    v_amount NUMERIC;
    v_rate_year NUMERIC;
    v_term INT;
    v_start_date DATE;
    v_monthly_payment NUMERIC;
    v_remaining_balance NUMERIC;
    v_interest_payment NUMERIC;
    v_principal_payment NUMERIC;
    v_current_date DATE;
BEGIN
    -- Получаем данные договора
    SELECT amount, interest_rate, term_months, start_date 
    INTO v_amount, v_rate_year, v_term, v_start_date
    FROM loan_contracts WHERE id = p_contract_id;

    v_monthly_payment := calculate_annuity_payment(v_amount, v_rate_year, v_term);
    v_remaining_balance := v_amount;
    v_current_date := v_start_date;

    FOR i IN 1..v_term LOOP
        v_current_date := v_current_date + INTERVAL '1 month';
        v_interest_payment := ROUND(v_remaining_balance * (v_rate_year / 100 / 12), 2);
        v_principal_payment := v_monthly_payment - v_interest_payment;
        
        -- В последний месяц корректируем остаток
        IF i = v_term THEN
            v_principal_payment := v_remaining_balance;
            v_monthly_payment := v_principal_payment + v_interest_payment;
        END IF;

        v_remaining_balance := v_remaining_balance - v_principal_payment;

        INSERT INTO repayment_schedule (contract_id, payment_date, payment_amount, principal_amount, interest_amount, remaining_balance)
        VALUES (p_contract_id, v_current_date, v_monthly_payment, v_principal_payment, v_interest_payment, v_remaining_balance);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Процедура открытия кредита
CREATE OR REPLACE PROCEDURE open_loan_contract(
    p_client_id BIGINT,
    p_product_id INT,
    p_employee_id BIGINT,
    p_amount NUMERIC,
    p_term_months INT
) AS $$
DECLARE
    v_contract_id BIGINT;
    v_contract_num VARCHAR(50);
    v_rate NUMERIC;
BEGIN
    -- Валидация условий продукта
    SELECT interest_rate INTO v_rate FROM credit_products WHERE id = p_product_id AND is_active = true;
    
    v_contract_num := 'D-' || to_char(NOW(), 'YYYYMMDD') || '-' || nextval('loan_contracts_id_seq');

    INSERT INTO loan_contracts (
        contract_number, client_id, product_id, approved_by_employee_id, 
        amount, interest_rate, term_months, start_date, end_date, status
    ) VALUES (
        v_contract_num, p_client_id, p_product_id, p_employee_id,
        p_amount, v_rate, p_term_months, CURRENT_DATE, CURRENT_DATE + (p_term_months || ' months')::INTERVAL, 'active'
    ) RETURNING id INTO v_contract_id;

    -- Логируем выдачу
    INSERT INTO operations (contract_id, employee_id, operation_type, amount, description)
    VALUES (v_contract_id, p_employee_id, 'issue', p_amount, 'Выдача кредитных средств');

    -- Генерируем график
    CALL generate_repayment_schedule(v_contract_id);
END;
$$ LANGUAGE plpgsql;

-- Процедура гашения (планового)
CREATE OR REPLACE PROCEDURE process_payment(
    p_contract_id BIGINT,
    p_amount NUMERIC
) AS $$
BEGIN
    -- Помечаем ближайший неоплаченный платеж как оплаченный
    UPDATE repayment_schedule
    SET is_paid = true, paid_at = NOW()
    WHERE id = (
        SELECT id FROM repayment_schedule 
        WHERE contract_id = p_contract_id AND is_paid = false 
        ORDER BY payment_date ASC LIMIT 1
    );

    INSERT INTO operations (contract_id, operation_type, amount, description)
    VALUES (p_contract_id, 'scheduled_payment', p_amount, 'Плановый платеж');

    -- Если все оплачено, закрываем договор
    IF NOT EXISTS (SELECT 1 FROM repayment_schedule WHERE contract_id = p_contract_id AND is_paid = false) THEN
        UPDATE loan_contracts SET status = 'closed', closed_at = NOW() WHERE id = p_contract_id;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- Представление для формирования Бланка кредитного договора
CREATE OR REPLACE VIEW view_contract_document AS
SELECT 
    lc.contract_number,
    lc.created_at::DATE as contract_date,
    c.last_name || ' ' || c.first_name || ' ' || COALESCE(c.middle_name, '') as client_fio,
    c.passport_series || ' ' || c.passport_number as passport,
    c.address,
    cp.name as product_name,
    lc.amount,
    lc.interest_rate,
    lc.term_months,
    lc.end_date as maturity_date
FROM loan_contracts lc
JOIN clients c ON lc.client_id = c.id
JOIN credit_products cp ON lc.product_id = cp.id;

-- Представление для менеджера: Список задолженностей
CREATE OR REPLACE VIEW view_overdue_payments AS
SELECT 
    c.last_name || ' ' || c.first_name as client_name,
    lc.contract_number,
    rs.payment_date,
    rs.payment_amount,
    CURRENT_DATE - rs.payment_date as days_overdue
FROM repayment_schedule rs
JOIN loan_contracts lc ON rs.contract_id = lc.id
JOIN clients c ON lc.client_id = c.id
WHERE rs.payment_date < CURRENT_DATE AND rs.is_paid = false;

-- Триггер для автоматического логирования изменений (Аудит)
CREATE OR REPLACE FUNCTION fn_audit_log() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action_type, entity_name, entity_id, old_values, new_values)
    VALUES (
        NULL, -- Здесь можно брать ID текущего сессионного пользователя
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE WHEN TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN row_to_json(OLD)::JSONB ELSE NULL END,
        CASE WHEN TG_OP = 'UPDATE' OR TG_OP = 'INSERT' THEN row_to_json(NEW)::JSONB ELSE NULL END
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_clients
AFTER INSERT OR UPDATE OR DELETE ON clients
FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

CREATE TRIGGER trg_audit_contracts
AFTER INSERT OR UPDATE OR DELETE ON loan_contracts
FOR EACH ROW EXECUTE FUNCTION fn_audit_log();


-- 1. Создаем физические роли в БД (если их нет)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'bank_admin') THEN
        CREATE ROLE bank_admin;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'bank_manager') THEN
        CREATE ROLE bank_manager;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'bank_client') THEN
        CREATE ROLE bank_client;
    END IF;
END $$;

-- 2. Настройка прав для Менеджера
GRANT SELECT, INSERT, UPDATE ON clients TO bank_manager;
GRANT SELECT, INSERT ON loan_contracts TO bank_manager;
GRANT SELECT ON repayment_schedule TO bank_manager;
GRANT SELECT ON view_contract_document TO bank_manager;
GRANT SELECT ON view_overdue_payments TO bank_manager;
GRANT EXECUTE ON PROCEDURE open_loan_contract TO bank_manager;
GRANT EXECUTE ON PROCEDURE process_payment TO bank_manager;

-- 3. Настройка прав для Клиента (только чтение своих данных через View)
-- Для полной реализации RLS (Row Level Security) используется:
ALTER TABLE loan_contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY client_own_contracts ON loan_contracts
    FOR SELECT
    USING (client_id IN (SELECT id FROM clients WHERE user_id = CAST(current_setting('app.current_user_id') AS BIGINT)));

-- 4. Настройка прав для Админа
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bank_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bank_admin;