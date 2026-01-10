--
-- PostgreSQL database dump
--

\restrict trhKhq9nl3k1OgppSUlaZMb75zrftCwcEjxt58R8cR663neLtTZdq8zBNgy6C43

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
    created_at timestamp with time zone DEFAULT now()
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
    amount numeric(15,2) NOT NULL,
    interest_rate numeric(5,2) NOT NULL,
    term_months integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status public.contract_status DEFAULT 'draft'::public.contract_status,
    created_at timestamp with time zone DEFAULT now(),
    closed_at timestamp with time zone
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
\.


--
-- Data for Name: clients; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.clients (id, user_id, first_name, last_name, middle_name, passport_series, passport_number, passport_issued_by, date_of_birth, address, phone, email, created_at) FROM stdin;
\.


--
-- Data for Name: credit_products; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.credit_products (id, name, min_amount, max_amount, min_term_months, max_term_months, interest_rate, is_active) FROM stdin;
1	Потребительский "Легкий"	10000.00	500000.00	3	36	18.50	t
2	Автокредит "Драйв"	300000.00	5000000.00	12	60	12.00	t
3	Ипотека "Семейная"	1000000.00	15000000.00	60	360	6.00	t
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

COPY public.loan_contracts (id, contract_number, client_id, product_id, approved_by_employee_id, amount, interest_rate, term_months, start_date, end_date, status, created_at, closed_at) FROM stdin;
\.


--
-- Data for Name: operations; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.operations (id, contract_id, employee_id, operation_type, amount, operation_date, description) FROM stdin;
\.


--
-- Data for Name: repayment_schedule; Type: TABLE DATA; Schema: public; Owner: user
--

COPY public.repayment_schedule (id, contract_id, payment_date, payment_amount, principal_amount, interest_amount, remaining_balance, is_paid, paid_at) FROM stdin;
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
1	1	admin	secret	t	2026-01-10 08:36:25.308348+00
2	2	manager	secret	t	2026-01-10 08:36:25.308348+00
\.


--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 1, false);


--
-- Name: clients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.clients_id_seq', 1, false);


--
-- Name: credit_products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.credit_products_id_seq', 3, true);


--
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.employees_id_seq', 2, true);


--
-- Name: loan_contracts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.loan_contracts_id_seq', 1, false);


--
-- Name: operations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.operations_id_seq', 1, false);


--
-- Name: repayment_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.repayment_schedule_id_seq', 1, false);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.roles_id_seq', 3, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('public.users_id_seq', 2, true);


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
-- Name: idx_operations_contract; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_operations_contract ON public.operations USING btree (contract_id);


--
-- Name: idx_schedule_contract; Type: INDEX; Schema: public; Owner: user
--

CREATE INDEX idx_schedule_contract ON public.repayment_schedule USING btree (contract_id);


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
-- PostgreSQL database dump complete
--

\unrestrict trhKhq9nl3k1OgppSUlaZMb75zrftCwcEjxt58R8cR663neLtTZdq8zBNgy6C43

