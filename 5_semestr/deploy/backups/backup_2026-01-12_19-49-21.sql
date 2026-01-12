--
-- PostgreSQL database dump
--

\restrict jOz4Sxv7lJVCxqYmQ0jcQpL0PUua2aZthL18TJlVp4kzVoaTdOLcxi6DH3mkbSm

-- Dumped from database version 15.15
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: contract_status; Type: TYPE; Schema: public; Owner: user
--

CREATE TYPE public.contract_status AS ENUM (
    'draft',
    'active',
    'closed',
    'defaulted'
);


ALTER TYPE public.contract_status OWNER TO "user";

--
-- Name: operation_type; Type: TYPE; Schema: public; Owner: user
--

CREATE TYPE public.operation_type AS ENUM (
    'issue',
    'scheduled_payment',
    'early_repayment',
    'penalty'
);


ALTER TYPE public.operation_type OWNER TO "user";

--
-- Name: user_role_type; Type: TYPE; Schema: public; Owner: user
--

CREATE TYPE public.user_role_type AS ENUM (
    'admin',
    'manager',
    'client'
);


ALTER TYPE public.user_role_type OWNER TO "user";

--
-- Name: calculate_annuity_payment(numeric, numeric, integer); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.calculate_annuity_payment(p_amount numeric, p_rate_year numeric, p_term_months integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rate_month NUMERIC;
BEGIN
    v_rate_month := (p_rate_year / 100) / 12;
    RETURN ROUND(p_amount * (v_rate_month * POWER(1 + v_rate_month, p_term_months)) / 
           (POWER(1 + v_rate_month, p_term_months) - 1), 2);
END;
$$;


ALTER FUNCTION public.calculate_annuity_payment(p_amount numeric, p_rate_year numeric, p_term_months integer) OWNER TO "user";

--
-- Name: check_client_creditworthiness(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.check_client_creditworthiness() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.check_client_creditworthiness() OWNER TO "user";

--
-- Name: fn_audit_log(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_audit_log() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_audit_log() OWNER TO "user";

--
-- Name: fn_calculate_annuity(numeric, numeric, integer); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_calculate_annuity(p_amount numeric, p_rate numeric, p_months integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_calculate_annuity(p_amount numeric, p_rate numeric, p_months integer) OWNER TO "user";

--
-- Name: fn_get_active_products(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_active_products() RETURNS TABLE(id integer, name character varying, min_amount numeric, max_amount numeric, min_term_months integer, max_term_months integer, interest_rate numeric, is_active boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_active_products() OWNER TO "user";

--
-- Name: fn_get_all_clients(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_all_clients() RETURNS TABLE(id bigint, first_name character varying, last_name character varying, middle_name character varying, passport_series character varying, passport_number character varying, passport_issued_by text, date_of_birth date, address text, phone character varying, email character varying, created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_all_clients() OWNER TO "user";

--
-- Name: fn_get_all_employees(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_all_employees() RETURNS TABLE(id bigint, first_name character varying, last_name character varying, "position" character varying, login character varying, role_name character varying)
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


ALTER FUNCTION public.fn_get_all_employees() OWNER TO "user";

--
-- Name: fn_get_all_loans(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_all_loans() RETURNS TABLE(id bigint, contract_number character varying, amount numeric, status character varying, start_date date, interest_rate numeric, term_months integer, balance numeric, client_name text, product_name character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_all_loans() OWNER TO "user";

--
-- Name: fn_get_audit_logs(character varying, character varying); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_audit_logs(p_action character varying DEFAULT NULL::character varying, p_from_date character varying DEFAULT NULL::character varying) RETURNS TABLE(id bigint, action_type character varying, entity_name character varying, entity_id bigint, created_at timestamp with time zone, new_values jsonb, login character varying, first_name character varying, last_name character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_audit_logs(p_action character varying, p_from_date character varying) OWNER TO "user";

--
-- Name: fn_get_client_loans(bigint); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_client_loans(p_user_id bigint) RETURNS TABLE(id bigint, contract_number character varying, amount numeric, status character varying, start_date date, balance numeric, product_name character varying, paid_months bigint, total_months bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_client_loans(p_user_id bigint) OWNER TO "user";

--
-- Name: fn_get_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_dashboard_stats() RETURNS json
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (SELECT stats_json FROM mv_dashboard_cache LIMIT 1);
END;
$$;


ALTER FUNCTION public.fn_get_dashboard_stats() OWNER TO "user";

--
-- Name: fn_get_financial_report(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_financial_report() RETURNS TABLE(month_year text, total_issued numeric, total_repaid numeric, net_cash_flow numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.month_year,
        v.total_issued,
        v.total_repaid,
        v.net_cash_flow
    FROM v_monthly_financials v;
END;
$$;


ALTER FUNCTION public.fn_get_financial_report() OWNER TO "user";

--
-- Name: fn_get_loan_operations(bigint); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_loan_operations(p_contract_id bigint) RETURNS TABLE(operation_type character varying, amount numeric, operation_date timestamp with time zone, description text)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_loan_operations(p_contract_id bigint) OWNER TO "user";

--
-- Name: fn_get_repayment_schedule(bigint); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_repayment_schedule(p_contract_id bigint) RETURNS TABLE(id bigint, payment_date date, payment_amount numeric, principal_amount numeric, interest_amount numeric, remaining_balance numeric, is_paid boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_repayment_schedule(p_contract_id bigint) OWNER TO "user";

--
-- Name: fn_get_user_by_login(character varying); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_get_user_by_login(p_login character varying) RETURNS TABLE(user_id bigint, password_hash character varying, role_name character varying, first_name character varying, last_name character varying, email character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_get_user_by_login(p_login character varying) OWNER TO "user";

--
-- Name: fn_refresh_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.fn_refresh_dashboard_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_dashboard_cache;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.fn_refresh_dashboard_stats() OWNER TO "user";

--
-- Name: generate_repayment_schedule(bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.generate_repayment_schedule(IN p_contract_id bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER PROCEDURE public.generate_repayment_schedule(IN p_contract_id bigint) OWNER TO "user";

--
-- Name: open_loan_contract(bigint, integer, bigint, numeric, integer); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.open_loan_contract(IN p_client_id bigint, IN p_product_id integer, IN p_employee_id bigint, IN p_amount numeric, IN p_term_months integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_contract_id BIGINT;
    v_contract_num VARCHAR(50);
    v_rate NUMERIC;
BEGIN
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
$$;


ALTER PROCEDURE public.open_loan_contract(IN p_client_id bigint, IN p_product_id integer, IN p_employee_id bigint, IN p_amount numeric, IN p_term_months integer) OWNER TO "user";

--
-- Name: prevent_change_history(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION public.prevent_change_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Безопасность: Изменение или удаление исторических записей операций ЗАПРЕЩЕНО!';
END;
$$;


ALTER FUNCTION public.prevent_change_history() OWNER TO "user";

--
-- Name: process_payment(bigint, numeric); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.process_payment(IN p_contract_id bigint, IN p_amount numeric)
    LANGUAGE plpgsql
    AS $$
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

    IF NOT EXISTS (SELECT 1 FROM repayment_schedule WHERE contract_id = p_contract_id AND is_paid = false) THEN
        UPDATE loan_contracts SET status = 'closed', closed_at = NOW() WHERE id = p_contract_id;
    END IF;
END;
$$;


ALTER PROCEDURE public.process_payment(IN p_contract_id bigint, IN p_amount numeric) OWNER TO "user";

--
-- Name: sp_audit_log(bigint, character varying, character varying, bigint, jsonb); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_audit_log(IN p_user_id bigint, IN p_action character varying, IN p_entity character varying, IN p_entity_id bigint, IN p_details jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO audit_logs (user_id, action_type, entity_name, entity_id, new_values, created_at)
    VALUES (p_user_id, p_action, p_entity, p_entity_id, p_details, NOW());
END;
$$;


ALTER PROCEDURE public.sp_audit_log(IN p_user_id bigint, IN p_action character varying, IN p_entity character varying, IN p_entity_id bigint, IN p_details jsonb) OWNER TO "user";

--
-- Name: sp_create_client(character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_create_client(IN p_login character varying, IN p_password character varying, IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_passport_series character varying, IN p_passport_number character varying, IN p_passport_issued character varying, IN p_dob character varying, IN p_address character varying, IN p_phone character varying, IN p_email character varying, INOUT p_client_id bigint DEFAULT NULL::bigint)
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


ALTER PROCEDURE public.sp_create_client(IN p_login character varying, IN p_password character varying, IN p_first_name character varying, IN p_last_name character varying, IN p_middle_name character varying, IN p_passport_series character varying, IN p_passport_number character varying, IN p_passport_issued character varying, IN p_dob character varying, IN p_address character varying, IN p_phone character varying, IN p_email character varying, INOUT p_client_id bigint) OWNER TO "user";

--
-- Name: sp_early_repayment(bigint, bigint, numeric); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_early_repayment(IN p_contract_id bigint, IN p_user_id bigint, INOUT p_paid_amount numeric DEFAULT 0)
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


ALTER PROCEDURE public.sp_early_repayment(IN p_contract_id bigint, IN p_user_id bigint, INOUT p_paid_amount numeric) OWNER TO "user";

--
-- Name: sp_issue_loan(bigint, integer, numeric, integer, bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_issue_loan(IN p_client_id bigint, IN p_product_id integer, IN p_amount numeric, IN p_term_months integer, IN p_employee_id bigint)
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


ALTER PROCEDURE public.sp_issue_loan(IN p_client_id bigint, IN p_product_id integer, IN p_amount numeric, IN p_term_months integer, IN p_employee_id bigint) OWNER TO "user";

--
-- Name: sp_issue_loan(bigint, integer, numeric, integer, bigint, bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_issue_loan(IN p_client_id bigint, IN p_product_id integer, IN p_amount numeric, IN p_term_months integer, IN p_employee_id bigint, INOUT p_new_id bigint DEFAULT NULL::bigint)
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
    VALUES (p_new_id, p_employee_id, 'issue', p_amount, '');
END;
$$;


ALTER PROCEDURE public.sp_issue_loan(IN p_client_id bigint, IN p_product_id integer, IN p_amount numeric, IN p_term_months integer, IN p_employee_id bigint, INOUT p_new_id bigint) OWNER TO "user";

--
-- Name: sp_make_payment(bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_make_payment(IN p_schedule_id bigint)
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
    VALUES (v_contract_id, 'scheduled_payment', v_payment_amount, 'Здесь можно добавит способ оплаты');

    IF v_new_balance <= 0 THEN
        UPDATE loan_contracts 
        SET status = 'closed', closed_at = NOW(), balance = 0 
        WHERE id = v_contract_id;
    END IF;
END;
$$;


ALTER PROCEDURE public.sp_make_payment(IN p_schedule_id bigint) OWNER TO "user";

--
-- Name: sp_register_employee(character varying, character varying, character varying, character varying, character varying, character varying, bigint); Type: PROCEDURE; Schema: public; Owner: user
--

CREATE PROCEDURE public.sp_register_employee(IN p_login character varying, IN p_password character varying, IN p_first_name character varying, IN p_last_name character varying, IN p_position character varying, IN p_email character varying, INOUT p_user_id bigint DEFAULT NULL::bigint)
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


ALTER PROCEDURE public.sp_register_employee(IN p_login character varying, IN p_password character varying, IN p_first_name character varying, IN p_last_name character varying, IN p_position character varying, IN p_email character varying, INOUT p_user_id bigint) OWNER TO "user";

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    user_id bigint,
    action_type character varying(50) NOT NULL,
    entity_name character varying(50) NOT NULL,
    entity_id bigint,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.audit_logs OWNER TO "user";

--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_id_seq OWNER TO "user";

--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: clients; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.clients (
    id bigint NOT NULL,
    user_id bigint,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    middle_name character varying(100),
    passport_series character varying(4) NOT NULL,
    passport_number character varying(6) NOT NULL,
    passport_issued_by text,
    date_of_birth date NOT NULL,
    address text NOT NULL,
    phone character varying(20) NOT NULL,
    email character varying(100),
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_client_adult CHECK ((date_of_birth <= (CURRENT_DATE - '18 years'::interval)))
);


ALTER TABLE public.clients OWNER TO "user";

--
-- Name: clients_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clients_id_seq OWNER TO "user";

--
-- Name: clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;


--
-- Name: credit_products; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.credit_products (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    min_amount numeric(15,2) NOT NULL,
    max_amount numeric(15,2) NOT NULL,
    min_term_months integer NOT NULL,
    max_term_months integer NOT NULL,
    interest_rate numeric(5,2) NOT NULL,
    is_active boolean DEFAULT true
);


ALTER TABLE public.credit_products OWNER TO "user";

--
-- Name: credit_products_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.credit_products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.credit_products_id_seq OWNER TO "user";

--
-- Name: credit_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.credit_products_id_seq OWNED BY public.credit_products.id;


--
-- Name: employees; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.employees (
    id bigint NOT NULL,
    user_id bigint,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    middle_name character varying(100),
    "position" character varying(100),
    phone character varying(20),
    email character varying(100)
);


ALTER TABLE public.employees OWNER TO "user";

--
-- Name: employees_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.employees_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_id_seq OWNER TO "user";

--
-- Name: employees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.employees_id_seq OWNED BY public.employees.id;


--
-- Name: loan_contracts; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.loan_contracts (
    id bigint NOT NULL,
    contract_number character varying(50) NOT NULL,
    client_id bigint NOT NULL,
    product_id integer NOT NULL,
    approved_by_employee_id bigint,
    balance numeric(15,2) NOT NULL,
    amount numeric(15,2) NOT NULL,
    interest_rate numeric(5,2) NOT NULL,
    term_months integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status public.contract_status DEFAULT 'draft'::public.contract_status,
    created_at timestamp with time zone DEFAULT now(),
    closed_at timestamp with time zone,
    CONSTRAINT chk_interest_rate_valid CHECK (((interest_rate >= (0)::numeric) AND (interest_rate <= (1000)::numeric))),
    CONSTRAINT chk_loan_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT chk_loan_balance_non_negative CHECK ((balance >= (0)::numeric))
);


ALTER TABLE public.loan_contracts OWNER TO "user";

--
-- Name: loan_contracts_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.loan_contracts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.loan_contracts_id_seq OWNER TO "user";

--
-- Name: loan_contracts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.loan_contracts_id_seq OWNED BY public.loan_contracts.id;


--
-- Name: operations; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.operations (
    id bigint NOT NULL,
    contract_id bigint NOT NULL,
    employee_id bigint,
    operation_type public.operation_type NOT NULL,
    amount numeric(15,2) NOT NULL,
    operation_date timestamp with time zone DEFAULT now(),
    description text
);


ALTER TABLE public.operations OWNER TO "user";

--
-- Name: mv_dashboard_cache; Type: MATERIALIZED VIEW; Schema: public; Owner: user
--

CREATE MATERIALIZED VIEW public.mv_dashboard_cache AS
 WITH issued AS (
         SELECT COALESCE(sum(loan_contracts.amount), (0)::numeric) AS total
           FROM public.loan_contracts
          WHERE (loan_contracts.status <> 'draft'::public.contract_status)
        ), repaid AS (
         SELECT COALESCE(sum(operations.amount), (0)::numeric) AS total
           FROM public.operations
          WHERE (operations.operation_type = ANY (ARRAY['scheduled_payment'::public.operation_type, 'early_repayment'::public.operation_type]))
        ), dist AS (
         SELECT json_agg(row_to_json(t.*)) AS data
           FROM ( SELECT cp.name AS label,
                    count(lc.id) AS value
                   FROM (public.loan_contracts lc
                     JOIN public.credit_products cp ON ((lc.product_id = cp.id)))
                  GROUP BY cp.name) t
        )
 SELECT 1 AS id,
    json_build_object('totalIssued', ( SELECT issued.total
           FROM issued), 'totalRepaid', ( SELECT repaid.total
           FROM repaid), 'distribution', COALESCE(( SELECT dist.data
           FROM dist), '[]'::json)) AS stats_json
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.mv_dashboard_cache OWNER TO "user";

--
-- Name: operations_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.operations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operations_id_seq OWNER TO "user";

--
-- Name: operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.operations_id_seq OWNED BY public.operations.id;


--
-- Name: repayment_schedule; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.repayment_schedule (
    id bigint NOT NULL,
    contract_id bigint NOT NULL,
    payment_date date NOT NULL,
    payment_amount numeric(15,2) NOT NULL,
    principal_amount numeric(15,2) NOT NULL,
    interest_amount numeric(15,2) NOT NULL,
    remaining_balance numeric(15,2) NOT NULL,
    is_paid boolean DEFAULT false,
    paid_at timestamp with time zone
);


ALTER TABLE public.repayment_schedule OWNER TO "user";

--
-- Name: repayment_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.repayment_schedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.repayment_schedule_id_seq OWNER TO "user";

--
-- Name: repayment_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.repayment_schedule_id_seq OWNED BY public.repayment_schedule.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text
);


ALTER TABLE public.roles OWNER TO "user";

--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO "user";

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    dirty boolean NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO "user";

--
-- Name: users; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    role_id integer NOT NULL,
    login character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.users OWNER TO "user";

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO "user";

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: v_contract_progress; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.v_contract_progress AS
SELECT
    NULL::bigint AS contract_id,
    NULL::character varying(50) AS contract_number,
    NULL::bigint AS client_id,
    NULL::numeric(15,2) AS amount,
    NULL::numeric(15,2) AS balance,
    NULL::public.contract_status AS status,
    NULL::date AS start_date,
    NULL::timestamp with time zone AS created_at,
    NULL::character varying(100) AS product_name,
    NULL::bigint AS total_payments,
    NULL::bigint AS paid_payments,
    NULL::numeric AS total_paid_money;


ALTER VIEW public.v_contract_progress OWNER TO "user";

--
-- Name: v_loan_dossier; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.v_loan_dossier AS
 SELECT lc.id AS contract_id,
    lc.contract_number,
    (((((c.last_name)::text || ' '::text) || (c.first_name)::text) || ' '::text) || (COALESCE(c.middle_name, ''::character varying))::text) AS client_name,
    (((c.passport_series)::text || ' '::text) || (c.passport_number)::text) AS passport,
    c.phone,
    cp.name AS product_name,
    lc.interest_rate,
    lc.term_months,
    lc.amount AS issued_amount,
    lc.balance AS remaining_debt,
    (lc.amount - lc.balance) AS total_paid_body,
    round((((lc.amount - lc.balance) / lc.amount) * (100)::numeric), 1) AS progress_percent,
    lc.status,
    lc.start_date,
    lc.end_date,
    lc.created_at,
    (((e.last_name)::text || ' '::text) || (e.first_name)::text) AS manager_name
   FROM (((public.loan_contracts lc
     JOIN public.clients c ON ((lc.client_id = c.id)))
     JOIN public.credit_products cp ON ((lc.product_id = cp.id)))
     LEFT JOIN public.employees e ON ((lc.approved_by_employee_id = e.user_id)));


ALTER VIEW public.v_loan_dossier OWNER TO "user";

--
-- Name: v_monthly_financials; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.v_monthly_financials AS
 SELECT to_char(operations.operation_date, 'YYYY-MM'::text) AS month_year,
    sum(
        CASE
            WHEN (operations.operation_type = 'issue'::public.operation_type) THEN operations.amount
            ELSE (0)::numeric
        END) AS total_issued,
    sum(
        CASE
            WHEN (operations.operation_type = ANY (ARRAY['scheduled_payment'::public.operation_type, 'early_repayment'::public.operation_type])) THEN operations.amount
            ELSE (0)::numeric
        END) AS total_repaid,
    sum(
        CASE
            WHEN (operations.operation_type = ANY (ARRAY['scheduled_payment'::public.operation_type, 'early_repayment'::public.operation_type])) THEN operations.amount
            ELSE (- operations.amount)
        END) AS net_cash_flow,
    count(*) AS operations_count
   FROM public.operations
  GROUP BY (to_char(operations.operation_date, 'YYYY-MM'::text))
  ORDER BY (to_char(operations.operation_date, 'YYYY-MM'::text)) DESC;


ALTER VIEW public.v_monthly_financials OWNER TO "user";

--
-- Name: v_user_complete_profile; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.v_user_complete_profile AS
 SELECT u.id AS user_id,
    u.login,
    u.password_hash,
    u.is_active,
    r.name AS role_name,
    (COALESCE(e.first_name, c.first_name))::character varying AS first_name,
    (COALESCE(e.last_name, c.last_name))::character varying AS last_name,
    (COALESCE(e.email, c.email))::character varying AS email,
    c.id AS client_id,
    e.id AS employee_id
   FROM (((public.users u
     JOIN public.roles r ON ((u.role_id = r.id)))
     LEFT JOIN public.employees e ON ((u.id = e.user_id)))
     LEFT JOIN public.clients c ON ((u.id = c.user_id)));


ALTER VIEW public.v_user_complete_profile OWNER TO "user";

--
-- Name: view_contract_document; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.view_contract_document AS
 SELECT lc.contract_number,
    (lc.created_at)::date AS contract_date,
    (((((c.last_name)::text || ' '::text) || (c.first_name)::text) || ' '::text) || (COALESCE(c.middle_name, ''::character varying))::text) AS client_fio,
    (((c.passport_series)::text || ' '::text) || (c.passport_number)::text) AS passport,
    c.address,
    cp.name AS product_name,
    lc.amount,
    lc.interest_rate,
    lc.term_months,
    lc.end_date AS maturity_date
   FROM ((public.loan_contracts lc
     JOIN public.clients c ON ((lc.client_id = c.id)))
     JOIN public.credit_products cp ON ((lc.product_id = cp.id)));


ALTER VIEW public.view_contract_document OWNER TO "user";

--
-- Name: view_overdue_payments; Type: VIEW; Schema: public; Owner: user
--

CREATE VIEW public.view_overdue_payments AS
 SELECT (((c.last_name)::text || ' '::text) || (c.first_name)::text) AS client_name,
    lc.contract_number,
    rs.payment_date,
    rs.payment_amount,
    (CURRENT_DATE - rs.payment_date) AS days_overdue
   FROM ((public.repayment_schedule rs
     JOIN public.loan_contracts lc ON ((rs.contract_id = lc.id)))
     JOIN public.clients c ON ((lc.client_id = c.id)))
  WHERE ((rs.payment_date < CURRENT_DATE) AND (rs.is_paid = false));


ALTER VIEW public.view_overdue_payments OWNER TO "user";

--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: clients id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);


--
-- Name: credit_products id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.credit_products ALTER COLUMN id SET DEFAULT nextval('public.credit_products_id_seq'::regclass);


--
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- Name: loan_contracts id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts ALTER COLUMN id SET DEFAULT nextval('public.loan_contracts_id_seq'::regclass);


--
-- Name: operations id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.operations ALTER COLUMN id SET DEFAULT nextval('public.operations_id_seq'::regclass);


--
-- Name: repayment_schedule id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.repayment_schedule ALTER COLUMN id SET DEFAULT nextval('public.repayment_schedule_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.audit_logs (id, user_id, action_type, entity_name, entity_id, old_values, new_values, ip_address, created_at) FROM stdin;
1	\N	INSERT	clients	1	\N	{"id": 1, "email": "stepan.raspopov27@gmail.com", "phone": "89218321222", "address": "", "user_id": 3, "last_name": "Распопов", "created_at": "2026-01-12T19:42:55.773922+00:00", "first_name": "Степан", "middle_name": "", "date_of_birth": "2000-12-20", "passport_number": "321323", "passport_series": "2313", "passport_issued_by": "ewqeqwewqe"}	\N	2026-01-12 19:42:55.773922+00
2	1	CREATE_CLIENT	clients	1	\N	{"name": "Распопов Степан", "login": "Uk7fBoUf"}	\N	2026-01-12 19:42:55.773922+00
3	1	TOOK_LOAN	loan_contracts	1	\N	{"type": "via_stored_procedure", "amount": "4000000.00"}	\N	2026-01-12 19:43:33.780756+00
4	3	PAYMENT	repayment_schedule	1	\N	{"amount": "168332.92", "method": "via_stored_procedure"}	\N	2026-01-12 19:44:33.365454+00
5	3	PAYMENT	repayment_schedule	2	\N	{"amount": "168332.92", "method": "via_stored_procedure"}	\N	2026-01-12 19:44:36.334382+00
6	3	PAYMENT	repayment_schedule	3	\N	{"amount": "168332.92", "method": "via_stored_procedure"}	\N	2026-01-12 19:45:03.767667+00
7	3	EARLY_REPAYMENT	loan_contracts	1	\N	{"amount": "3678998.13", "method": "via_stored_procedure"}	\N	2026-01-12 19:45:15.306735+00
8	1	TOOK_LOAN	loan_contracts	2	\N	{"type": "via_stored_procedure", "amount": "4000000.00"}	\N	2026-01-12 19:48:04.953204+00
\.


--
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.clients (id, user_id, first_name, last_name, middle_name, passport_series, passport_number, passport_issued_by, date_of_birth, address, phone, email, created_at) FROM stdin;
1	3	Степан	Распопов		2313	321323	ewqeqwewqe	2000-12-20		89218321222	stepan.raspopov27@gmail.com	2026-01-12 19:42:55.773922+00
\.


--
-- Data for Name: credit_products; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.credit_products (id, name, min_amount, max_amount, min_term_months, max_term_months, interest_rate, is_active) FROM stdin;
1	Потребительский "Легкий"	10000.00	500000.00	3	36	18.50	t
2	Автокредит "Драйв"	300000.00	5000000.00	12	60	12.00	t
3	Потребительский "На любые цели"	30000.00	5000000.00	3	60	18.90	t
4	Ипотека "Семейная"	1000000.00	50000000.00	120	360	6.00	t
5	Автокредит "Движение"	500000.00	10000000.00	12	84	13.50	t
6	Кредитная карта "100 дней"	10000.00	300000.00	12	24	29.90	t
7	Рефинансирование	300000.00	3000000.00	12	60	15.00	t
\.


--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.employees (id, user_id, first_name, last_name, middle_name, "position", phone, email) FROM stdin;
1	2	Иван	Иванов	\N	Старший менеджер	\N	\N
2	1	Сергей	Админов	\N	Администратор	\N	\N
\.


--
-- Data for Name: loan_contracts; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.loan_contracts (id, contract_number, client_id, product_id, approved_by_employee_id, balance, amount, interest_rate, term_months, start_date, end_date, status, created_at, closed_at) FROM stdin;
1	LN-1768247014-1	1	3	1	0.00	4000000.00	18.90	30	2026-01-12	2028-07-12	closed	2026-01-12 19:43:33.780756+00	2026-01-12 19:45:15.306735+00
2	LN-1768247285-1	1	2	1	4000000.00	4000000.00	12.00	48	2026-01-12	2030-01-12	active	2026-01-12 19:48:04.953204+00	\N
\.


--
-- Data for Name: operations; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.operations (id, contract_id, employee_id, operation_type, amount, operation_date, description) FROM stdin;
1	1	1	issue	4000000.00	2026-01-12 19:43:33.780756+00	
2	1	\N	scheduled_payment	168332.92	2026-01-12 19:44:33.365454+00	Здесь можно добавит способ оплаты
3	1	\N	scheduled_payment	168332.92	2026-01-12 19:44:36.334382+00	Здесь можно добавит способ оплаты
4	1	\N	scheduled_payment	168332.92	2026-01-12 19:45:03.767667+00	Здесь можно добавит способ оплаты
5	1	\N	early_repayment	3678998.13	2026-01-12 19:45:15.306735+00	Полное досрочное погашение (SP)
6	2	1	issue	4000000.00	2026-01-12 19:48:04.953204+00	
\.


--
-- Data for Name: repayment_schedule; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.repayment_schedule (id, contract_id, payment_date, payment_amount, principal_amount, interest_amount, remaining_balance, is_paid, paid_at) FROM stdin;
1	1	2026-02-12	168332.92	105332.92	63000.00	3894667.08	t	2026-01-12 19:44:33.365454+00
2	1	2026-03-12	168332.92	106991.91	61341.01	3787675.17	t	2026-01-12 19:44:36.334382+00
3	1	2026-04-12	168332.92	108677.04	59655.88	3678998.13	t	2026-01-12 19:45:03.767667+00
31	2	2026-02-12	105335.34	65335.34	40000.00	3934664.66	f	\N
32	2	2026-03-12	105335.34	65988.69	39346.65	3868675.97	f	\N
33	2	2026-04-12	105335.34	66648.58	38686.76	3802027.39	f	\N
34	2	2026-05-12	105335.34	67315.07	38020.27	3734712.32	f	\N
35	2	2026-06-12	105335.34	67988.22	37347.12	3666724.10	f	\N
36	2	2026-07-12	105335.34	68668.10	36667.24	3598056.00	f	\N
37	2	2026-08-12	105335.34	69354.78	35980.56	3528701.22	f	\N
38	2	2026-09-12	105335.34	70048.33	35287.01	3458652.89	f	\N
39	2	2026-10-12	105335.34	70748.81	34586.53	3387904.08	f	\N
40	2	2026-11-12	105335.34	71456.30	33879.04	3316447.78	f	\N
41	2	2026-12-12	105335.34	72170.86	33164.48	3244276.92	f	\N
42	2	2027-01-12	105335.34	72892.57	32442.77	3171384.35	f	\N
43	2	2027-02-12	105335.34	73621.50	31713.84	3097762.85	f	\N
44	2	2027-03-12	105335.34	74357.71	30977.63	3023405.14	f	\N
45	2	2027-04-12	105335.34	75101.29	30234.05	2948303.85	f	\N
46	2	2027-05-12	105335.34	75852.30	29483.04	2872451.55	f	\N
47	2	2027-06-12	105335.34	76610.82	28724.52	2795840.73	f	\N
48	2	2027-07-12	105335.34	77376.93	27958.41	2718463.80	f	\N
49	2	2027-08-12	105335.34	78150.70	27184.64	2640313.10	f	\N
50	2	2027-09-12	105335.34	78932.21	26403.13	2561380.89	f	\N
51	2	2027-10-12	105335.34	79721.53	25613.81	2481659.36	f	\N
52	2	2027-11-12	105335.34	80518.75	24816.59	2401140.61	f	\N
53	2	2027-12-12	105335.34	81323.93	24011.41	2319816.68	f	\N
54	2	2028-01-12	105335.34	82137.17	23198.17	2237679.51	f	\N
55	2	2028-02-12	105335.34	82958.54	22376.80	2154720.97	f	\N
56	2	2028-03-12	105335.34	83788.13	21547.21	2070932.84	f	\N
57	2	2028-04-12	105335.34	84626.01	20709.33	1986306.83	f	\N
58	2	2028-05-12	105335.34	85472.27	19863.07	1900834.56	f	\N
59	2	2028-06-12	105335.34	86326.99	19008.35	1814507.57	f	\N
60	2	2028-07-12	105335.34	87190.26	18145.08	1727317.31	f	\N
61	2	2028-08-12	105335.34	88062.17	17273.17	1639255.14	f	\N
62	2	2028-09-12	105335.34	88942.79	16392.55	1550312.35	f	\N
63	2	2028-10-12	105335.34	89832.22	15503.12	1460480.13	f	\N
64	2	2028-11-12	105335.34	90730.54	14604.80	1369749.59	f	\N
65	2	2028-12-12	105335.34	91637.84	13697.50	1278111.75	f	\N
66	2	2029-01-12	105335.34	92554.22	12781.12	1185557.53	f	\N
67	2	2029-02-12	105335.34	93479.76	11855.58	1092077.77	f	\N
68	2	2029-03-12	105335.34	94414.56	10920.78	997663.21	f	\N
69	2	2029-04-12	105335.34	95358.71	9976.63	902304.50	f	\N
70	2	2029-05-12	105335.34	96312.29	9023.05	805992.21	f	\N
71	2	2029-06-12	105335.34	97275.42	8059.92	708716.79	f	\N
72	2	2029-07-12	105335.34	98248.17	7087.17	610468.62	f	\N
73	2	2029-08-12	105335.34	99230.65	6104.69	511237.97	f	\N
74	2	2029-09-12	105335.34	100222.96	5112.38	411015.01	f	\N
75	2	2029-10-12	105335.34	101225.19	4110.15	309789.82	f	\N
76	2	2029-11-12	105335.34	102237.44	3097.90	207552.38	f	\N
77	2	2029-12-12	105335.34	103259.82	2075.52	104292.56	f	\N
78	2	2030-01-12	105335.49	104292.56	1042.93	0.00	f	\N
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.roles (id, name, description) FROM stdin;
1	admin	Полный доступ к системе
2	manager	Управление продуктами и одобрение кредитов
3	client	Клиент банка
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.schema_migrations (version, dirty) FROM stdin;
1	f
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.users (id, role_id, login, password_hash, is_active, created_at) FROM stdin;
1	1	admin	secret	t	2026-01-12 19:42:31.697663+00
2	2	manager	secret	t	2026-01-12 19:42:31.697663+00
3	3	Uk7fBoUf	DID0oZ0V	t	2026-01-12 19:42:55.773922+00
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 8, true);


--
-- Name: clients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.clients_id_seq', 1, true);


--
-- Name: credit_products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.credit_products_id_seq', 7, true);


--
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.employees_id_seq', 2, true);


--
-- Name: loan_contracts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.loan_contracts_id_seq', 2, true);


--
-- Name: operations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.operations_id_seq', 6, true);


--
-- Name: repayment_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.repayment_schedule_id_seq', 78, true);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.roles_id_seq', 3, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.users_id_seq', 3, true);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: clients clients_passport_series_passport_number_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_passport_series_passport_number_key UNIQUE (passport_series, passport_number);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: credit_products credit_products_name_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.credit_products
    ADD CONSTRAINT credit_products_name_key UNIQUE (name);


--
-- Name: credit_products credit_products_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.credit_products
    ADD CONSTRAINT credit_products_pkey PRIMARY KEY (id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: employees employees_user_id_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_key UNIQUE (user_id);


--
-- Name: loan_contracts loan_contracts_contract_number_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts
    ADD CONSTRAINT loan_contracts_contract_number_key UNIQUE (contract_number);


--
-- Name: loan_contracts loan_contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts
    ADD CONSTRAINT loan_contracts_pkey PRIMARY KEY (id);


--
-- Name: operations operations_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.operations
    ADD CONSTRAINT operations_pkey PRIMARY KEY (id);


--
-- Name: repayment_schedule repayment_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.repayment_schedule
    ADD CONSTRAINT repayment_schedule_pkey PRIMARY KEY (id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: users users_login_key; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_login_key UNIQUE (login);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_user; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_audit_user ON public.audit_logs USING btree (user_id);


--
-- Name: idx_clients_last_name; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_clients_last_name ON public.clients USING btree (last_name);


--
-- Name: idx_clients_passport; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_clients_passport ON public.clients USING btree (passport_series, passport_number);


--
-- Name: idx_contracts_client; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_contracts_client ON public.loan_contracts USING btree (client_id);


--
-- Name: idx_mv_dashboard_cache; Type: INDEX; Schema: public; Owner: user
--

CREATE UNIQUE INDEX idx_mv_dashboard_cache ON public.mv_dashboard_cache USING btree (id);


--
-- Name: idx_operations_contract; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_operations_contract ON public.operations USING btree (contract_id);


--
-- Name: idx_schedule_contract; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_schedule_contract ON public.repayment_schedule USING btree (contract_id);


--
-- Name: v_contract_progress _RETURN; Type: RULE; Schema: public; Owner: user
--

CREATE OR REPLACE VIEW public.v_contract_progress AS
 SELECT lc.id AS contract_id,
    lc.contract_number,
    lc.client_id,
    lc.amount,
    lc.balance,
    lc.status,
    lc.start_date,
    lc.created_at,
    cp.name AS product_name,
    count(rs.id) AS total_payments,
    count(rs.id) FILTER (WHERE (rs.is_paid = true)) AS paid_payments,
    COALESCE(sum(rs.payment_amount) FILTER (WHERE (rs.is_paid = true)), (0)::numeric) AS total_paid_money
   FROM ((public.loan_contracts lc
     JOIN public.credit_products cp ON ((lc.product_id = cp.id)))
     LEFT JOIN public.repayment_schedule rs ON ((lc.id = rs.contract_id)))
  GROUP BY lc.id, cp.name;


--
-- Name: clients trg_audit_clients; Type: TRIGGER; Schema: public; Owner: user
--

CREATE TRIGGER trg_audit_clients AFTER INSERT OR DELETE OR UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();


--
-- Name: loan_contracts trg_check_debts_before_loan; Type: TRIGGER; Schema: public; Owner: user
--

CREATE TRIGGER trg_check_debts_before_loan BEFORE INSERT ON public.loan_contracts FOR EACH ROW EXECUTE FUNCTION public.check_client_creditworthiness();


--
-- Name: operations trg_immutable_operations; Type: TRIGGER; Schema: public; Owner: user
--

CREATE TRIGGER trg_immutable_operations BEFORE DELETE OR UPDATE ON public.operations FOR EACH ROW EXECUTE FUNCTION public.prevent_change_history();


--
-- Name: loan_contracts trg_refresh_stats_loans; Type: TRIGGER; Schema: public; Owner: user
--

CREATE TRIGGER trg_refresh_stats_loans AFTER INSERT OR DELETE OR UPDATE ON public.loan_contracts FOR EACH STATEMENT EXECUTE FUNCTION public.fn_refresh_dashboard_stats();


--
-- Name: operations trg_refresh_stats_ops; Type: TRIGGER; Schema: public; Owner: user
--

CREATE TRIGGER trg_refresh_stats_ops AFTER INSERT OR DELETE OR UPDATE ON public.operations FOR EACH STATEMENT EXECUTE FUNCTION public.fn_refresh_dashboard_stats();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: clients clients_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: employees employees_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: loan_contracts loan_contracts_approved_by_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts
    ADD CONSTRAINT loan_contracts_approved_by_employee_id_fkey FOREIGN KEY (approved_by_employee_id) REFERENCES public.employees(id);


--
-- Name: loan_contracts loan_contracts_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts
    ADD CONSTRAINT loan_contracts_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: loan_contracts loan_contracts_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.loan_contracts
    ADD CONSTRAINT loan_contracts_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.credit_products(id);


--
-- Name: operations operations_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.operations
    ADD CONSTRAINT operations_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.loan_contracts(id);


--
-- Name: operations operations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.operations
    ADD CONSTRAINT operations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id);


--
-- Name: repayment_schedule repayment_schedule_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.repayment_schedule
    ADD CONSTRAINT repayment_schedule_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.loan_contracts(id) ON DELETE CASCADE;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: loan_contracts client_own_contracts; Type: POLICY; Schema: public; Owner: user
--

CREATE POLICY client_own_contracts ON public.loan_contracts FOR SELECT USING ((client_id IN ( SELECT clients.id
   FROM public.clients
  WHERE (clients.user_id = (current_setting('app.current_user_id'::text))::bigint))));


--
-- Name: loan_contracts; Type: ROW SECURITY; Schema: public; Owner: user
--

ALTER TABLE public.loan_contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: PROCEDURE open_loan_contract(IN p_client_id bigint, IN p_product_id integer, IN p_employee_id bigint, IN p_amount numeric, IN p_term_months integer); Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON PROCEDURE public.open_loan_contract(IN p_client_id bigint, IN p_product_id integer, IN p_employee_id bigint, IN p_amount numeric, IN p_term_months integer) TO bank_manager;


--
-- Name: PROCEDURE process_payment(IN p_contract_id bigint, IN p_amount numeric); Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON PROCEDURE public.process_payment(IN p_contract_id bigint, IN p_amount numeric) TO bank_manager;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.audit_logs TO bank_admin;


--
-- Name: SEQUENCE audit_logs_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.audit_logs_id_seq TO bank_admin;


--
-- Name: TABLE clients; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.clients TO bank_manager;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.clients TO bank_admin;


--
-- Name: SEQUENCE clients_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.clients_id_seq TO bank_admin;


--
-- Name: TABLE credit_products; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.credit_products TO bank_admin;


--
-- Name: SEQUENCE credit_products_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.credit_products_id_seq TO bank_admin;


--
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.employees TO bank_admin;


--
-- Name: SEQUENCE employees_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.employees_id_seq TO bank_admin;


--
-- Name: TABLE loan_contracts; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT ON TABLE public.loan_contracts TO bank_manager;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.loan_contracts TO bank_admin;


--
-- Name: SEQUENCE loan_contracts_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.loan_contracts_id_seq TO bank_admin;


--
-- Name: TABLE operations; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.operations TO bank_admin;


--
-- Name: SEQUENCE operations_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.operations_id_seq TO bank_admin;


--
-- Name: TABLE repayment_schedule; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT ON TABLE public.repayment_schedule TO bank_manager;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.repayment_schedule TO bank_admin;


--
-- Name: SEQUENCE repayment_schedule_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.repayment_schedule_id_seq TO bank_admin;


--
-- Name: TABLE roles; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.roles TO bank_admin;


--
-- Name: SEQUENCE roles_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.roles_id_seq TO bank_admin;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.schema_migrations TO bank_admin;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.users TO bank_admin;


--
-- Name: SEQUENCE users_id_seq; Type: ACL; Schema: public; Owner: user
--

GRANT ALL ON SEQUENCE public.users_id_seq TO bank_admin;


--
-- Name: TABLE view_contract_document; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT ON TABLE public.view_contract_document TO bank_manager;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.view_contract_document TO bank_admin;


--
-- Name: TABLE view_overdue_payments; Type: ACL; Schema: public; Owner: user
--

GRANT SELECT ON TABLE public.view_overdue_payments TO bank_manager;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.view_overdue_payments TO bank_admin;


--
-- Name: mv_dashboard_cache; Type: MATERIALIZED VIEW DATA; Schema: public; Owner: user
--

REFRESH MATERIALIZED VIEW public.mv_dashboard_cache;


--
-- PostgreSQL database dump complete
--

\unrestrict jOz4Sxv7lJVCxqYmQ0jcQpL0PUua2aZthL18TJlVp4kzVoaTdOLcxi6DH3mkbSm

