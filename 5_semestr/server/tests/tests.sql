DO $$
DECLARE
    v_manager_user_id BIGINT;
    v_manager_employee_id INT;
    
    v_client_id BIGINT;
    v_contract_id BIGINT;
    v_schedule_id BIGINT;
    v_balance_before BIGINT;
    v_balance_after BIGINT;
    v_is_paid BOOLEAN;
    v_count INT;
BEGIN
    RAISE NOTICE 'Start tests';

    CALL sp_register_employee(
        'test_manager'::VARCHAR, 'pass123'::VARCHAR, 'Руслан'::VARCHAR, 'Кривошеин'::VARCHAR, 'Стажер'::VARCHAR, 'manager@test.com'::VARCHAR,
        v_manager_user_id
    );

    RAISE NOTICE 'TEST 1: register_employee passed';

    SELECT id INTO v_manager_employee_id FROM employees WHERE user_id = v_manager_user_id;
    
    CALL sp_create_client(
        'test_client'::VARCHAR, 'pass'::VARCHAR, 'Иван'::VARCHAR, 'Распутин'::VARCHAR, 'И.'::VARCHAR, 
        '9999'::VARCHAR, '888777'::VARCHAR, 'XYZ'::VARCHAR, '2000-01-01'::VARCHAR, 'Ad'::VARCHAR, '895612462'::VARCHAR, 'cl@mail.com'::VARCHAR,
        v_client_id
    );

    RAISE NOTICE 'TEST 2: create_client passed';

    CALL sp_issue_loan(
        v_client_id, 
        1, 
        10000000::BIGINT, 
        12, 
        v_manager_employee_id,
        v_contract_id
    );

    RAISE NOTICE 'TEST 3: issue loan to client passed';
    
    RAISE NOTICE 'Tests passed successfully';

    ROLLBACK;

END $$;