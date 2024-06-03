CREATE OR REPLACE FUNCTION add_user(
    p_login VARCHAR(255),
    p_email VARCHAR(255),
    p_password VARCHAR(255)
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    INSERT INTO users (login, email, hashed_password)
    VALUES (p_login, p_email, crypt(p_password, get_salt('bf')))
    RETURNING id INTO v_user_id;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_in(
    p_login VARCHAR(255),
    p_password VARCHAR(255)
) RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
    FROM users
    WHERE login = p_login
    AND hashed_password = crypt(p_password, hashed_password);
    RETURN v_user_id;
END;