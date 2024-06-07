CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Function definitions

-- Function used to create new user with given login, email and password. On success returns user id, otherwise raises exception
CREATE OR REPLACE FUNCTION add_user(
    p_id bigint,
    p_login VARCHAR,
    p_password VARCHAR
) RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM accounts
        WHERE login = p_login
    ) THEN
        RAISE EXCEPTION 'User with given login already exists';
    END IF;

    INSERT INTO accounts (id, login, hashed_password)
    VALUES (p_id, p_login, crypt(p_password, gen_salt('bf')))
    RETURNING id INTO v_user_id;
    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function used to log in user with given login and password. On success returns user id, otherwise returns NULL
CREATE OR REPLACE FUNCTION login(
    p_login VARCHAR(255),
    p_password VARCHAR(255)
) RETURNS INTEGER AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
    FROM accounts
    WHERE login = p_login
    AND hashed_password = crypt(p_password, hashed_password);
    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function that returns list of offices the given id is administrator at
CREATE OR REPLACE FUNCTION get_administrated_offices(
    p_administrator_id INTEGER
) RETURNS TABLE (
    id INTEGER,
    office_type VARCHAR,
    country VARCHAR,
    city VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT offices.id, offices.office_type, offices.country, office.city
    FROM offices
    JOIN administrators ON offices.id = administrators.office_id
    WHERE administrators.user_id = p_administrator_id;
END;
$$ LANGUAGE plpgsql;

-- Return all documents type that could be issued by the given office
CREATE OR REPLACE FUNCTION get_issued_documents_types(
    p_office_id INTEGER
) RETURNS TABLE (
    id INTEGER,
    document VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT documents_types.id, documents_types.document
    FROM documents_types
    JOIN office_kinds_documents ON documents_types.id = office_kinds_documents.document_id
    JOIN office_kinds ON office_kinds_documents.kind_id = offices_kinds.kind
    JOIN offices_kinds_relations ON office_kinds.kind = offices_kinds_relations.kind_id
    WHERE offices_kinds_relations.office_id = p_office_id;
END;
$$ LANGUAGE plpgsql;
