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
('Ипотека "Семейная"', 1000000, 15000000, 60, 360, 6.0, true)
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