CREATE TYPE user_role_type AS ENUM ('admin', 'manager', 'operator', 'security');
CREATE TYPE contract_status AS ENUM ('draft', 'active', 'closed', 'defaulted');
CREATE TYPE operation_type AS ENUM ('issue', 'scheduled_payment', 'early_repayment', 'penalty');

#2. Роли 
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO roles (name, description) VALUES 
('admin', 'Полный доступ к системе'),
('manager', 'Управление продуктами и одобрение кредитов'),
('operator', 'Работа с клиентами и платежами'),
('security', 'Просмотр логов и аудита');

#3. Пользователи
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    role_id INT NOT NULL REFERENCES roles(id),
    login VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL, -- Храним только хэш!
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

#4. Работники
CREATE TABLE employees (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE REFERENCES users(id), -- Может быть NULL, если работник уволен, но запись нужна
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    position VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100)
);

#5. Клиенты (Физические лица)
CREATE TABLE clients (
    id BIGSERIAL PRIMARY KEY,
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
    UNIQUE (passport_series, passport_number) -- Уникальность паспорта
);

-- 6. Кредитные продукты (Виды кредитов)
CREATE TABLE credit_products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE, -- "Ипотека", "Потребительский"
    min_amount NUMERIC(15, 2) NOT NULL,
    max_amount NUMERIC(15, 2) NOT NULL,
    min_term_months INT NOT NULL,
    max_term_months INT NOT NULL,
    interest_rate NUMERIC(5, 2) NOT NULL, -- Процентная ставка (годовых)
    is_active BOOLEAN DEFAULT TRUE
);

-- 7. Кредитные договоры
CREATE TABLE loan_contracts (
    id BIGSERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL UNIQUE, -- Номер договора для печати
    client_id BIGINT NOT NULL REFERENCES clients(id),
    product_id INT NOT NULL REFERENCES credit_products(id),
    approved_by_employee_id BIGINT REFERENCES employees(id), -- Кто одобрил
    
    amount NUMERIC(15, 2) NOT NULL, -- Сумма кредита
    interest_rate NUMERIC(5, 2) NOT NULL, -- Фиксируем ставку на момент подписания!
    term_months INT NOT NULL,
    
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    
    status contract_status DEFAULT 'draft',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);

-- 8. График гашения (Плановые платежи)
CREATE TABLE repayment_schedule (
    id BIGSERIAL PRIMARY KEY,
    contract_id BIGINT NOT NULL REFERENCES loan_contracts(id) ON DELETE CASCADE,
    payment_date DATE NOT NULL,
    
    payment_amount NUMERIC(15, 2) NOT NULL, -- Общая сумма платежа
    principal_amount NUMERIC(15, 2) NOT NULL, -- Часть основного долга
    interest_amount NUMERIC(15, 2) NOT NULL, -- Часть процентов
    remaining_balance NUMERIC(15, 2) NOT NULL, -- Остаток долга после платежа
    
    is_paid BOOLEAN DEFAULT FALSE,
    paid_at TIMESTAMPTZ
);

-- 9. Операции (Реальное движение средств)
CREATE TABLE operations (
    id BIGSERIAL PRIMARY KEY,
    contract_id BIGINT NOT NULL REFERENCES loan_contracts(id),
    employee_id BIGINT REFERENCES employees(id), -- Кто провел операцию
    
    operation_type operation_type NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    operation_date TIMESTAMPTZ DEFAULT NOW(),
    
    description TEXT -- Например "Досрочное погашение"
);

-- 10. Логирование действий (Audit Log)
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id), -- Может быть NULL, если действие системное
    action_type VARCHAR(50) NOT NULL, -- INSERT, UPDATE, DELETE, LOGIN
    entity_name VARCHAR(50) NOT NULL, -- Название таблицы (clients, contracts...)
    entity_id BIGINT, -- ID записи
    
    old_values JSONB, -- Что было (Postgres JSONB идеально подходит)
    new_values JSONB, -- Что стало
    
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Индексы для ускорения поиска
CREATE INDEX idx_clients_passport ON clients(passport_series, passport_number);
CREATE INDEX idx_clients_last_name ON clients(last_name);
CREATE INDEX idx_contracts_client ON loan_contracts(client_id);
CREATE INDEX idx_schedule_contract ON repayment_schedule(contract_id);
CREATE INDEX idx_operations_contract ON operations(contract_id);
CREATE INDEX idx_audit_user ON audit_logs(user_id);