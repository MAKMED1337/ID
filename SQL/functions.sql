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