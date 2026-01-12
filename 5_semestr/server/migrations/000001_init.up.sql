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

    INSERT INTO operations (contract_id, employee_id, operation_type, amount, description)
    VALUES (v_contract_id, p_employee_id, 'issue', p_amount, 'Выдача кредитных средств');

    CALL generate_repayment_schedule(v_contract_id);
END;
$$ LANGUAGE plpgsql;


-- Процедура гашения (планового)
CREATE OR REPLACE PROCEDURE process_payment(
    p_contract_id BIGINT,
    p_amount NUMERIC
) AS $$
BEGIN
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


CREATE OR REPLACE FUNCTION fn_audit_log() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action_type, entity_name, entity_id, old_values, new_values)
    VALUES (
        NULL,
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

-- CREATE TRIGGER trg_audit_contracts
-- AFTER INSERT OR UPDATE OR DELETE ON loan_contracts
-- FOR EACH ROW EXECUTE FUNCTION fn_audit_log();


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


ALTER TABLE clients 
ADD CONSTRAINT chk_client_adult 
CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years');


-- Сумма кредита > 0
ALTER TABLE loan_contracts 
ADD CONSTRAINT chk_loan_amount_positive 
CHECK (amount > 0);

-- Баланс не может быть отрицательным (защита от ошибок в расчетах)
ALTER TABLE loan_contracts 
ADD CONSTRAINT chk_loan_balance_non_negative 
CHECK (balance >= 0);

-- Ставка должна быть адекватной (от 0% до 1000%)
ALTER TABLE loan_contracts 
ADD CONSTRAINT chk_interest_rate_valid 
CHECK (interest_rate >= 0 AND interest_rate <= 1000);


-- ChangeHistory
CREATE OR REPLACE FUNCTION prevent_change_history()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Безопасность: Изменение или удаление исторических записей операций ЗАПРЕЩЕНО!';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_immutable_operations
BEFORE UPDATE OR DELETE ON operations
FOR EACH ROW
EXECUTE FUNCTION prevent_change_history();


CREATE OR REPLACE FUNCTION check_client_creditworthiness()
RETURNS TRIGGER AS $$
DECLARE
    bad_debt_count INT;
BEGIN
    SELECT COUNT(*) INTO bad_debt_count
    FROM repayment_schedule rs
    JOIN loan_contracts lc ON rs.contract_id = lc.id
    WHERE lc.client_id = NEW.client_id
      AND rs.is_paid = FALSE
      AND rs.payment_date < (CURRENT_DATE - INTERVAL '5 days');

    IF bad_debt_count > 0 THEN
        RAISE EXCEPTION 'ОТКАЗАНО: У клиента имеется непогашенная просроченная задолженность.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_debts_before_loan
BEFORE INSERT ON loan_contracts
FOR EACH ROW
EXECUTE FUNCTION check_client_creditworthiness();


CREATE OR REPLACE FUNCTION fn_calculate_annuity(
    p_amount NUMERIC, 
    p_rate NUMERIC, 
    p_months INT
) RETURNS NUMERIC AS $$
DECLARE
    v_monthly_rate NUMERIC;
    v_factor NUMERIC;
    v_annuity NUMERIC;
BEGIN
    v_monthly_rate := p_rate / 12 / 100;

    v_factor := POW(1 + v_monthly_rate, p_months);
    
    v_annuity := p_amount * (v_monthly_rate * v_factor) / (v_factor - 1);
    
    RETURN ROUND(v_annuity, 2);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE sp_issue_loan(
    p_client_id BIGINT,
    p_product_id INT,
    p_amount NUMERIC,
    p_term_months INT,
    p_employee_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_contract_id BIGINT;
    v_rate NUMERIC;
    v_annuity NUMERIC;
    v_balance NUMERIC;
    v_monthly_rate NUMERIC;
    v_interest_part NUMERIC;
    v_principal_part NUMERIC;
    v_current_date DATE := CURRENT_DATE;
    i INT;
BEGIN
    SELECT interest_rate INTO v_rate FROM credit_products WHERE id = p_product_id;
    
    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'Кредитный продукт не найден';
    END IF;

    v_annuity := fn_calculate_annuity(p_amount, v_rate, p_term_months);
    v_monthly_rate := v_rate / 12 / 100;
    v_balance := p_amount;

    INSERT INTO loan_contracts (
        contract_number, client_id, product_id, approved_by_employee_id, 
        amount, interest_rate, term_months, start_date, end_date, status, balance
    ) VALUES (
        'LN-' || CAST(EXTRACT(EPOCH FROM NOW()) AS BIGINT),
        p_client_id, p_product_id, p_employee_id,
        p_amount, v_rate, p_term_months, v_current_date, 
        v_current_date + (p_term_months || ' months')::INTERVAL, 
        'active', p_amount
    ) RETURNING id INTO v_contract_id;

    FOR i IN 1..p_term_months LOOP
        v_current_date := v_current_date + INTERVAL '1 month';
        
        v_interest_part := ROUND(v_balance * v_monthly_rate, 2);
        
        v_principal_part := v_annuity - v_interest_part;

        IF i = p_term_months OR v_principal_part > v_balance THEN
            v_principal_part := v_balance;
            v_annuity := v_principal_part + v_interest_part;
        END IF;

        v_balance := v_balance - v_principal_part;

        INSERT INTO repayment_schedule (
            contract_id, payment_date, payment_amount, 
            principal_amount, interest_amount, remaining_balance, is_paid
        ) VALUES (
            v_contract_id, v_current_date, v_annuity, 
            v_principal_part, v_interest_part, v_balance, FALSE
        );
    END LOOP;

    INSERT INTO operations (contract_id, employee_id, operation_type, amount, description)
    VALUES (v_contract_id, p_employee_id, 'issue', p_amount, 'Выдача кредита через процедуру БД');

END;
$$;


CREATE OR REPLACE PROCEDURE sp_make_payment(
    p_schedule_id BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_contract_id BIGINT;
    v_principal_amount NUMERIC;
    v_payment_amount NUMERIC;
    v_new_balance NUMERIC;
    v_is_paid BOOLEAN;
BEGIN
    SELECT contract_id, principal_amount, payment_amount, is_paid 
    INTO v_contract_id, v_principal_amount, v_payment_amount, v_is_paid
    FROM repayment_schedule 
    WHERE id = p_schedule_id;

    IF v_contract_id IS NULL THEN
        RAISE EXCEPTION 'Платеж не найден';
    END IF;

    IF v_is_paid THEN
        RAISE EXCEPTION 'Этот платеж уже оплачен';
    END IF;

    UPDATE repayment_schedule 
    SET is_paid = TRUE, paid_at = NOW() 
    WHERE id = p_schedule_id;

    UPDATE loan_contracts 
    SET balance = balance - v_principal_amount 
    WHERE id = v_contract_id
    RETURNING balance INTO v_new_balance;

    INSERT INTO operations (contract_id, operation_type, amount, description)
    VALUES (v_contract_id, 'scheduled_payment', v_payment_amount, 'Платеж через процедуру БД');

    IF v_new_balance <= 0 THEN
        UPDATE loan_contracts 
        SET status = 'closed', closed_at = NOW(), balance = 0 
        WHERE id = v_contract_id;
    END IF;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_issue_loan(
    p_client_id BIGINT,
    p_product_id INT,
    p_amount NUMERIC,
    p_term_months INT,
    p_employee_id BIGINT,
    INOUT p_new_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rate NUMERIC;
    v_annuity NUMERIC;
    v_balance NUMERIC;
    v_monthly_rate NUMERIC;
    v_interest_part NUMERIC;
    v_principal_part NUMERIC;
    v_current_date DATE := CURRENT_DATE;
    i INT;
BEGIN
    SELECT interest_rate INTO v_rate FROM credit_products WHERE id = p_product_id;
    
    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'Кредитный продукт не найден';
    END IF;

    v_monthly_rate := v_rate / 12 / 100;
    IF v_monthly_rate = 0 THEN
        v_annuity := p_amount / p_term_months;
    ELSE
        v_annuity := p_amount * (v_monthly_rate * POW(1 + v_monthly_rate, p_term_months)) / (POW(1 + v_monthly_rate, p_term_months) - 1);
    END IF;
    
    v_annuity := ROUND(v_annuity, 2);
    v_balance := p_amount;

    INSERT INTO loan_contracts (
        contract_number, client_id, product_id, approved_by_employee_id, 
        amount, interest_rate, term_months, start_date, end_date, status, balance
    ) VALUES (
        'LN-' || CAST(EXTRACT(EPOCH FROM NOW()) AS BIGINT) || '-' || p_client_id,
        p_client_id, p_product_id, p_employee_id,
        p_amount, v_rate, p_term_months, v_current_date, 
        v_current_date + (p_term_months || ' months')::INTERVAL, 
        'active', p_amount
    ) RETURNING id INTO p_new_id;

    FOR i IN 1..p_term_months LOOP
        v_current_date := v_current_date + INTERVAL '1 month';
        v_interest_part := ROUND(v_balance * v_monthly_rate, 2);
        v_principal_part := v_annuity - v_interest_part;

        IF i = p_term_months OR v_principal_part > v_balance THEN
            v_principal_part := v_balance;
            v_annuity := v_principal_part + v_interest_part;
        END IF;

        v_balance := v_balance - v_principal_part;

        INSERT INTO repayment_schedule (
            contract_id, payment_date, payment_amount, 
            principal_amount, interest_amount, remaining_balance, is_paid
        ) VALUES (
            p_new_id, v_current_date, v_annuity, 
            v_principal_part, v_interest_part, v_balance, FALSE
        );
    END LOOP;

    INSERT INTO operations (contract_id, employee_id, operation_type, amount, description)
    VALUES (p_new_id, p_employee_id, 'issue', p_amount, 'Выдача кредита (PL/pgSQL)');
END;
$$;


-- EarlyRepayement
CREATE OR REPLACE PROCEDURE sp_early_repayment(
    p_contract_id BIGINT,
    p_user_id BIGINT,
    INOUT p_paid_amount NUMERIC DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC;
    v_status VARCHAR;
    v_owner_id BIGINT;
BEGIN
    SELECT lc.balance, lc.status, cl.user_id 
    INTO v_balance, v_status, v_owner_id
    FROM loan_contracts lc
    JOIN clients cl ON lc.client_id = cl.id
    WHERE lc.id = p_contract_id;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Договор не найден';
    END IF;

    -- Проверка безопасности (IDOR)
    IF v_owner_id != p_user_id THEN
        RAISE EXCEPTION 'Доступ запрещен: это не ваш кредит';
    END IF;

    IF v_status = 'closed' THEN
        RAISE EXCEPTION 'Кредит уже закрыт';
    END IF;

    IF v_balance <= 0 THEN
        RAISE EXCEPTION 'Задолженность отсутствует';
    END IF;

    p_paid_amount := v_balance;

    UPDATE loan_contracts 
    SET balance = 0, status = 'closed', closed_at = NOW() 
    WHERE id = p_contract_id;

    DELETE FROM repayment_schedule 
    WHERE contract_id = p_contract_id AND is_paid = FALSE;

    INSERT INTO operations (contract_id, operation_type, amount, description, operation_date)
    VALUES (p_contract_id, 'early_repayment', v_balance, 'Полное досрочное погашение (SP)', NOW());

END;
$$;


-- GetClientsLoans
CREATE OR REPLACE FUNCTION fn_get_client_loans(p_user_id BIGINT)
RETURNS TABLE (
    id BIGINT,
    contract_number VARCHAR,
    amount NUMERIC,
    status VARCHAR,
    start_date DATE,
    balance NUMERIC,
    product_name VARCHAR,
    paid_months BIGINT,
    total_months BIGINT
) AS $$
DECLARE
    v_client_id BIGINT;
BEGIN
    SELECT c.id INTO v_client_id 
    FROM clients c 
    WHERE c.user_id = p_user_id;

    RETURN QUERY
    SELECT 
        v.contract_id,
        v.contract_number,
        v.amount,
        v.status::VARCHAR,
        v.start_date,
        v.balance,
        v.product_name,
        v.paid_payments,
        v.total_payments
    FROM v_contract_progress v
    WHERE v.client_id = v_client_id
    ORDER BY v.created_at DESC;
END;
$$ LANGUAGE plpgsql;


-- AuditProcedure
CREATE OR REPLACE PROCEDURE sp_audit_log(
    p_user_id BIGINT,
    p_action VARCHAR,
    p_entity VARCHAR,
    p_entity_id BIGINT,
    p_details JSONB
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action_type, entity_name, entity_id, new_values, created_at)
    VALUES (p_user_id, p_action, p_entity, p_entity_id, p_details, NOW());
END;
$$;


-- GetEmployees
CREATE OR REPLACE FUNCTION fn_get_all_employees()
RETURNS TABLE (
    id BIGINT,
    first_name VARCHAR,
    last_name VARCHAR,
    "position" VARCHAR,
    login VARCHAR,
    role_name VARCHAR
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id, 
        e.first_name, 
        e.last_name, 
        e.position, 
        u.login, 
        r.name::VARCHAR
    FROM employees e
    JOIN users u ON e.user_id = u.id
    JOIN roles r ON u.role_id = r.id
    ORDER BY e.id DESC;
END;
$$;


-- GetLoans
CREATE OR REPLACE FUNCTION fn_get_all_loans()
RETURNS TABLE (
    id BIGINT,
    contract_number VARCHAR,
    amount NUMERIC,
    status VARCHAR,
    start_date DATE,
    interest_rate NUMERIC,
    term_months INT,
    balance NUMERIC,
    client_name TEXT,
    product_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        vd.contract_id, 
        vd.contract_number, 
        vd.issued_amount, 
        vd.status::VARCHAR, 
        vd.start_date,
        vd.interest_rate,
        vd.term_months,
        vd.remaining_debt,
        vd.client_name::TEXT,
        vd.product_name
    FROM v_loan_dossier vd
    ORDER BY vd.created_at DESC;
END;
$$ LANGUAGE plpgsql;


-- CreateClient
CREATE OR REPLACE PROCEDURE sp_create_client(
    p_login VARCHAR,
    p_password VARCHAR,
    p_first_name VARCHAR,
    p_last_name VARCHAR,
    p_middle_name VARCHAR,
    p_passport_series VARCHAR,
    p_passport_number VARCHAR,
    p_passport_issued VARCHAR,
    p_dob VARCHAR,
    p_address VARCHAR,
    p_phone VARCHAR,
    p_email VARCHAR,
    INOUT p_client_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_id INT;
    v_user_id BIGINT;
    v_dob_date DATE;
BEGIN
    BEGIN
        v_dob_date := TO_DATE(p_dob, 'YYYY-MM-DD');
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Неверный формат даты рождения (YYYY-MM-DD)';
    END;

    SELECT id INTO v_role_id FROM roles WHERE name = 'client';
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Роль client не найдена';
    END IF;

    INSERT INTO users (role_id, login, password_hash, is_active)
    VALUES (v_role_id, p_login, p_password, true)
    RETURNING id INTO v_user_id;

    INSERT INTO clients (
        user_id, first_name, last_name, middle_name, 
        passport_series, passport_number, passport_issued_by, 
        date_of_birth, address, phone, email
    )
    VALUES (
        v_user_id, p_first_name, p_last_name, p_middle_name,
        p_passport_series, p_passport_number, p_passport_issued,
        v_dob_date, p_address, p_phone, p_email
    )
    RETURNING id INTO p_client_id;

EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Пользователь с таким логином или паспортом уже существует';
END;
$$;


CREATE OR REPLACE VIEW v_user_complete_profile AS
SELECT 
    u.id AS user_id,
    u.login,
    u.password_hash,
    u.is_active,
    r.name AS role_name,
    COALESCE(e.first_name, c.first_name)::VARCHAR AS first_name,
    COALESCE(e.last_name, c.last_name)::VARCHAR AS last_name,
    COALESCE(e.email, c.email)::VARCHAR AS email,
    -- ID специфичных сущностей
    c.id AS client_id,
    e.id AS employee_id
FROM users u
JOIN roles r ON u.role_id = r.id
LEFT JOIN employees e ON u.id = e.user_id
LEFT JOIN clients c ON u.id = c.user_id;


CREATE OR REPLACE VIEW v_contract_progress AS
SELECT 
    lc.id AS contract_id,
    lc.contract_number,
    lc.client_id,
    lc.amount,
    lc.balance,
    lc.status,
    lc.start_date,
    lc.created_at,
    cp.name AS product_name,
    -- Агрегация из графика платежей
    COUNT(rs.id) AS total_payments,
    COUNT(rs.id) FILTER (WHERE rs.is_paid = TRUE) AS paid_payments,
    COALESCE(SUM(rs.payment_amount) FILTER (WHERE rs.is_paid = TRUE), 0) AS total_paid_money
FROM loan_contracts lc
JOIN credit_products cp ON lc.product_id = cp.id
LEFT JOIN repayment_schedule rs ON lc.id = rs.contract_id
GROUP BY lc.id, cp.name;


-- GetUser
CREATE OR REPLACE FUNCTION fn_get_user_by_login(p_login VARCHAR)
RETURNS TABLE (
    user_id BIGINT,
    password_hash VARCHAR,
    role_name VARCHAR,
    first_name VARCHAR,
    last_name VARCHAR,
    email VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.user_id,
        v.password_hash,
        v.role_name,
        v.first_name,
        v.last_name,
        v.email
    FROM v_user_complete_profile v
    WHERE v.login = p_login AND v.is_active = TRUE;
END;
$$ LANGUAGE plpgsql;


-- GetLoans
CREATE OR REPLACE FUNCTION fn_get_loan_operations(p_contract_id BIGINT)
RETURNS TABLE (
    operation_type VARCHAR,
    amount NUMERIC,
    operation_date TIMESTAMPTZ,
    description TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.operation_type::VARCHAR,
        o.amount,
        o.operation_date,
        o.description
    FROM operations o
    WHERE o.contract_id = p_contract_id
    ORDER BY o.operation_date DESC;
END;
$$ LANGUAGE plpgsql;


-- GetSchedule
CREATE OR REPLACE FUNCTION fn_get_repayment_schedule(p_contract_id BIGINT)
RETURNS TABLE (
    id BIGINT,
    payment_date DATE,
    payment_amount NUMERIC,
    principal_amount NUMERIC,
    interest_amount NUMERIC,
    remaining_balance NUMERIC,
    is_paid BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rs.id,
        rs.payment_date,
        rs.payment_amount,
        rs.principal_amount,
        rs.interest_amount,
        rs.remaining_balance,
        rs.is_paid
    FROM repayment_schedule rs
    WHERE rs.contract_id = p_contract_id
    ORDER BY rs.payment_date ASC;
END;
$$ LANGUAGE plpgsql;


-- GetLogs
CREATE OR REPLACE FUNCTION fn_get_audit_logs(
    p_action VARCHAR DEFAULT NULL,
    p_from_date VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id BIGINT,
    action_type VARCHAR,
    entity_name VARCHAR,
    entity_id BIGINT,
    created_at TIMESTAMPTZ,
    new_values JSONB,
    login VARCHAR,
    first_name VARCHAR,
    last_name VARCHAR
) AS $$
DECLARE
    v_date_filter TIMESTAMPTZ;
BEGIN
    IF p_from_date IS NOT NULL AND p_from_date != '' THEN
        v_date_filter := p_from_date::TIMESTAMPTZ;
    END IF;

    RETURN QUERY
    SELECT 
        a.id, 
        a.action_type, 
        COALESCE(a.entity_name, 'system'),
        COALESCE(a.entity_id, 0),          
        a.created_at, 
        COALESCE(a.new_values, '{}'::jsonb), 
        u.login, 
        e.first_name, 
        e.last_name
    FROM audit_logs a
    LEFT JOIN users u ON a.user_id = u.id
    LEFT JOIN employees e ON u.id = e.user_id
    WHERE 
        (p_action IS NULL OR p_action = '' OR a.action_type = p_action)
        AND
        (v_date_filter IS NULL OR a.created_at >= v_date_filter)
    ORDER BY a.created_at DESC 
    LIMIT 50;
END;
$$ LANGUAGE plpgsql;


-- GetProducts
CREATE OR REPLACE FUNCTION fn_get_active_products()
RETURNS TABLE (
    id INT,
    name VARCHAR,
    min_amount NUMERIC,
    max_amount NUMERIC,
    min_term_months INT,
    max_term_months INT,
    interest_rate NUMERIC,
    is_active BOOLEAN
) AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        cp.id, 
        cp.name, 
        cp.min_amount, 
        cp.max_amount, 
        cp.min_term_months, 
        cp.max_term_months, 
        cp.interest_rate, 
        cp.is_active
    FROM credit_products cp
    WHERE cp.is_active = TRUE;
END;
$$ LANGUAGE plpgsql;


-- GetClients
CREATE OR REPLACE FUNCTION fn_get_all_clients()
RETURNS TABLE (
    id BIGINT,
    first_name VARCHAR,
    last_name VARCHAR,
    middle_name VARCHAR,
    passport_series VARCHAR,
    passport_number VARCHAR,
    passport_issued_by TEXT,
    date_of_birth DATE,
    address TEXT,
    phone VARCHAR,
    email VARCHAR,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        c.id, 
        c.first_name, 
        c.last_name, 
        c.middle_name,
        c.passport_series, 
        c.passport_number, 
        c.passport_issued_by,
        c.date_of_birth, 
        c.address, 
        c.phone, 
        c.email, 
        c.created_at
    FROM clients c
    ORDER BY c.id DESC;
END;
$$ LANGUAGE plpgsql;


-- RegisterHandler
CREATE OR REPLACE PROCEDURE sp_register_employee(
    p_login VARCHAR,
    p_password VARCHAR,
    p_first_name VARCHAR,
    p_last_name VARCHAR,
    p_position VARCHAR,
    p_email VARCHAR,
    INOUT p_user_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_id INT;
BEGIN
    SELECT id INTO v_role_id FROM roles WHERE name = 'manager';
    
    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Роль manager не найдена в БД';
    END IF;

    INSERT INTO users (role_id, login, password_hash, is_active)
    VALUES (v_role_id, p_login, p_password, TRUE)
    RETURNING id INTO p_user_id;

    INSERT INTO employees (user_id, first_name, last_name, position, email)
    VALUES (p_user_id, p_first_name, p_last_name, p_position, p_email);

EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Пользователь с таким логином уже существует';
END;
$$;


CREATE OR REPLACE VIEW v_monthly_financials AS
SELECT 
    TO_CHAR(operation_date, 'YYYY-MM') AS month_year,
    -- Сумма выдачи
    SUM(CASE WHEN operation_type = 'issue' THEN amount ELSE 0 END) AS total_issued,
    -- Сумма возвратов (платежи + досрочка)
    SUM(CASE WHEN operation_type IN ('scheduled_payment', 'early_repayment') THEN amount ELSE 0 END) AS total_repaid,
    -- Чистый денежный поток
    SUM(CASE WHEN operation_type IN ('scheduled_payment', 'early_repayment') THEN amount ELSE -amount END) AS net_cash_flow,
    COUNT(*) AS operations_count
FROM operations
GROUP BY TO_CHAR(operation_date, 'YYYY-MM')
ORDER BY month_year DESC;


CREATE OR REPLACE VIEW v_loan_dossier AS
SELECT 
    lc.id AS contract_id,
    lc.contract_number,
    -- Клиент
    c.last_name || ' ' || c.first_name || ' ' || COALESCE(c.middle_name, '') AS client_name,
    c.passport_series || ' ' || c.passport_number AS passport,
    c.phone,
    -- Продукт
    cp.name AS product_name,
    lc.interest_rate,
    lc.term_months, -- <--- ДОБАВИЛИ ЭТО ПОЛЕ
    -- Финансы
    lc.amount AS issued_amount,
    lc.balance AS remaining_debt,
    (lc.amount - lc.balance) AS total_paid_body,
    ROUND(((lc.amount - lc.balance) / lc.amount * 100), 1) AS progress_percent,
    -- Статус
    lc.status,
    lc.start_date,
    lc.end_date,
    lc.created_at, -- <--- ДОБАВИЛИ ДЛЯ СОРТИРОВКИ
    -- Менеджер
    e.last_name || ' ' || e.first_name AS manager_name
FROM loan_contracts lc
JOIN clients c ON lc.client_id = c.id
JOIN credit_products cp ON lc.product_id = cp.id
LEFT JOIN employees e ON lc.approved_by_employee_id = e.user_id;


CREATE OR REPLACE FUNCTION fn_get_financial_report()
RETURNS TABLE (
    month_year TEXT,
    total_issued NUMERIC,
    total_repaid NUMERIC,
    net_cash_flow NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.month_year,
        v.total_issued,
        v.total_repaid,
        v.net_cash_flow
    FROM v_monthly_financials v;
END;
$$ LANGUAGE plpgsql;


CREATE MATERIALIZED VIEW mv_dashboard_cache AS
WITH 
    -- Считаем выдачу
    issued AS (
        SELECT COALESCE(SUM(amount), 0) AS total 
        FROM loan_contracts 
        WHERE status != 'draft'
    ),
    -- Считаем возвраты
    repaid AS (
        SELECT COALESCE(SUM(amount), 0) AS total 
        FROM operations 
        WHERE operation_type IN ('scheduled_payment', 'early_repayment')
    ),
    -- Считаем распределение (диаграмма)
    dist AS (
        SELECT json_agg(row_to_json(t)) AS data FROM (
            SELECT cp.name AS "label", COUNT(lc.id) AS "value"
            FROM loan_contracts lc
            JOIN credit_products cp ON lc.product_id = cp.id
            GROUP BY cp.name
        ) t
    )
SELECT 
    1 AS id, -- Фиктивный ID для индекса
    json_build_object(
        'totalIssued', (SELECT total FROM issued),
        'totalRepaid', (SELECT total FROM repaid),
        'distribution', COALESCE((SELECT data FROM dist), '[]'::json)
    ) AS stats_json;

-- 3. Создаем УНИКАЛЬНЫЙ ИНДЕКС
-- Это обязательно, чтобы можно было обновлять представление без блокировки всей базы (CONCURRENTLY)
CREATE UNIQUE INDEX idx_mv_dashboard_cache ON mv_dashboard_cache (id);


CREATE OR REPLACE FUNCTION fn_refresh_dashboard_stats()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dashboard_cache;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_refresh_stats_loans
AFTER INSERT OR UPDATE OR DELETE ON loan_contracts
FOR EACH STATEMENT
EXECUTE FUNCTION fn_refresh_dashboard_stats();


CREATE TRIGGER trg_refresh_stats_ops
AFTER INSERT OR UPDATE OR DELETE ON operations
FOR EACH STATEMENT
EXECUTE FUNCTION fn_refresh_dashboard_stats();


CREATE OR REPLACE FUNCTION fn_get_dashboard_stats()
RETURNS JSON AS $$
BEGIN
    RETURN (SELECT stats_json FROM mv_dashboard_cache LIMIT 1);
END;
$$ LANGUAGE plpgsql;






-- CREATE OR REPLACE VIEW v_bad_debtors AS
-- SELECT 
--     c.id AS client_id,
--     c.last_name || ' ' || c.first_name || ' ' || COALESCE(c.middle_name, '') AS full_name,
--     c.phone,
--     c.email,
--     lc.contract_number,
--     rs.payment_date AS missed_date,
--     rs.payment_amount,
--     (CURRENT_DATE - rs.payment_date) AS days_overdue
-- FROM repayment_schedule rs
-- JOIN loan_contracts lc ON rs.contract_id = lc.id
-- JOIN clients c ON lc.client_id = c.id
-- WHERE rs.is_paid = FALSE 
--   AND rs.payment_date < CURRENT_DATE
--   AND lc.status = 'active';



-- CREATE OR REPLACE VIEW v_manager_kpi AS
-- SELECT 
--     e.id AS employee_id,
--     e.last_name || ' ' || e.first_name AS manager_name,
--     e.position,
--     COUNT(lc.id) AS loans_issued,
--     COALESCE(SUM(lc.amount), 0) AS total_amount_issued,
--     -- Средняя ставка по выданным кредитам
--     ROUND(AVG(lc.interest_rate), 2) AS avg_rate
-- FROM employees e
-- LEFT JOIN loan_contracts lc ON lc.approved_by_employee_id = e.user_id
-- GROUP BY e.id, e.last_name, e.first_name, e.position;


-- CREATE OR REPLACE VIEW v_portfolio_summary AS
-- SELECT 
--     (SELECT COUNT(*) FROM clients) AS total_clients,
--     (SELECT COUNT(*) FROM loan_contracts WHERE status = 'active') AS active_loans_count,
--     (SELECT COALESCE(SUM(balance), 0) FROM loan_contracts WHERE status = 'active') AS current_debt_load,
--     (SELECT COALESCE(SUM(amount), 0) FROM operations WHERE operation_type = 'issue') AS total_money_out,
--     (SELECT COALESCE(SUM(amount), 0) FROM operations WHERE operation_type IN ('scheduled_payment', 'early_repayment')) AS total_money_in;


-- CREATE OR REPLACE FUNCTION fn_get_client_stats(p_client_id BIGINT)
-- RETURNS TABLE (
--     total_loans BIGINT,
--     active_loans BIGINT,
--     total_debt NUMERIC
-- ) AS $$
-- BEGIN
--     RETURN QUERY
--     SELECT 
--         COUNT(*),
--         COUNT(*) FILTER (WHERE status = 'active'),
--         COALESCE(SUM(balance), 0)
--     FROM loan_contracts
--     WHERE client_id = p_client_id;
-- END;
-- $$ LANGUAGE plpgsql;