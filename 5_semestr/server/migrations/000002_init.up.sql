DROP FUNCTION IF EXISTS fn_get_all_employees();

CREATE OR REPLACE FUNCTION fn_get_all_employees()
RETURNS TABLE (
    id INT, 
    first_name VARCHAR,
    last_name VARCHAR,
    "position" VARCHAR,
    login VARCHAR,
    role_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.id::INT,
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
$$ LANGUAGE plpgsql;