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

-- TRIGGERS

-- Trigger used to verify that there does not exists a divorce for this marriage
CREATE OR REPLACE FUNCTION verify_divorce_unique()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM divorces
        WHERE marriage_id = NEW.marriage_id
    ) THEN
        RAISE EXCEPTION 'Divorce already exists for this marriage';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_unique BEFORE INSERT ON divorces
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_unique();


-- Trigger used to verify that there does not exists an active marriage between two people
CREATE OR REPLACE FUNCTION verify_marriage_unique()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM marriages
        WHERE (person1 = NEW.person1 AND person2 = NEW.person2)
        OR (person1 = NEW.person2 AND person2 = NEW.person1)
    ) THEN
        RAISE EXCEPTION 'Marriage already exists between these people';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_marriage_unique BEFORE INSERT ON marriages
    FOR EACH ROW EXECUTE FUNCTION verify_marriage_unique();

-- Trigger used to verify that divorce date is after marriage date
CREATE OR REPLACE FUNCTION verify_divorce_date()
RETURNS TRIGGER AS $$
DECLARE
    v_marriage_date DATE;
BEGIN
    SELECT marriage_date INTO v_marriage_date
    FROM marriages
    WHERE id = NEW.marriage_id;

    IF v_marriage_date > NEW.divorce_date THEN
        RAISE EXCEPTION 'Divorce date is before marriage date';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_date BEFORE INSERT ON divorces
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_date();

-- Trigger used to verify that marriage certificate date is after marriage date
CREATE OR REPLACE FUNCTION verify_marriage_certificate_date()
RETURNS TRIGGER AS $$
DECLARE
    v_marriage_date DATE;
BEGIN
    SELECT marriage_date INTO v_marriage_date
    FROM marriages
    WHERE id = NEW.marriage_id;

    IF v_marriage_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Marriage certificate date is before marriage date';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_marriage_certificate_date BEFORE INSERT ON marriage_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_marriage_certificate_date();

-- Trigger used to verify that divorce certificate date is after divorce date
CREATE OR REPLACE FUNCTION verify_divorce_certificate_date()
RETURNS TRIGGER AS $$
DECLARE
    v_divorce_date DATE;
BEGIN
    SELECT divorce_date INTO v_divorce_date
    FROM divorces
    WHERE id = NEW.divorce_id;

    IF v_divorce_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Divorce certificate date is before divorce date';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_certificate_date BEFORE INSERT ON divorce_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_certificate_date();

-- EDUCATIONAL CERTIFICATES

-- Trigger used to verify that educational certificate date is after educational instance creation date
CREATE OR REPLACE FUNCTION verify_educational_certificate_date()
RETURNS TRIGGER AS $$
DECLARE
    v_educational_instance_date DATE;
BEGIN
    SELECT creation_date INTO v_educational_instance_date
    FROM educational_instances
    WHERE id = NEW.issuer;

    IF v_educational_instance_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Educational certificate date is before educational instance creation date';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_date();


-- Trigger used to check whether all prerequisites for educational certificate are met
CREATE OR REPLACE FUNCTION verify_educational_certificate_prerequisites()
RETURNS TRIGGER AS $$
DECLARE
    v_prerequisite_kind INTEGER;
BEGIN
    FOR v_prerequisite_kind IN (SELECT prerequirement FROM educational_certificetes_types WHERE kind = NEW.kind)
    LOOP
        IF v_prerequisite_kind IS NOT NULL 
        AND NOT EXISTS (
            SELECT 1
            FROM educational_certificates
            WHERE kind = v_prerequisite_kind AND holder = NEW.holder
        ) THEN
            RAISE EXCEPTION 'Prerequisite educational certificate does not exist';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_prerequisites BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_prerequisites();

-- Trigger used to check whether certificate was issued before the holder was born
CREATE OR REPLACE FUNCTION verify_educational_certificate_birth_date()
RETURNS TRIGGER AS $$
DECLARE
    v_birth_date DATE;
BEGIN
    SELECT date_of_birth INTO v_birth_date
    FROM people
    WHERE id = NEW.holder;

    IF v_birth_date > NEW.issue_date THEN
        RAISE EXCEPTION 'Educational certificate was issued before the holder was born';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_birth_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_birth_date();

-- Trigger used to ensure that educational certificate is not issued to a dead person
CREATE OR REPLACE FUNCTION verify_educational_certificate_death_date()
RETURNS TRIGGER AS $$
DECLARE
    v_death_date DATE;
BEGIN
    SELECT date_of_death INTO v_death_date
    FROM people
    WHERE id = NEW.holder;

    IF v_death_date IS NOT NULL THEN
        RAISE EXCEPTION 'Educational certificate is issued to a dead person';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_death_date BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_death_date();

-- Trigger used to ensure that educational certificate kind was issued by the educational instance of the same kind
CREATE OR REPLACE FUNCTION verify_educational_certificate_kind()
RETURNS TRIGGER AS $$
DECLARE
    v_instance_kind INTEGER;
BEGIN
    SELECT kind INTO v_instance_kind
    FROM educational_instances
    WHERE id = NEW.issuer;

    IF v_instance_kind <> NEW.kind THEN
        RAISE EXCEPTION 'Educational certificate kind does not match educational instance kind';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_kind BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_kind();

-- PASSPORTS

-- Trigger used to ensure that passport is not issued to a dead person
CREATE OR REPLACE FUNCTION verify_passport_death_date()
RETURNS TRIGGER AS $$
DECLARE
    v_death_date DATE;
BEGIN
    SELECT date_of_death INTO v_death_date
    FROM people
    WHERE id = NEW.passport_owner;

    IF v_death_date IS NOT NULL THEN
        RAISE EXCEPTION 'Passport is issued to a dead person';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_passport_death_date BEFORE INSERT ON passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_death_date();

CREATE TRIGGER verify_passport_death_date BEFORE UPDATE ON international_passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_death_date();

-- Trigger used to ensure that passport is not issued to a person with more than 1 active passport
CREATE OR REPLACE FUNCTION verify_passport_number()
RETURNS TRIGGER AS $$
DECLARE
    v_passport_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_passport_count
    FROM passports
    WHERE passport_owner = NEW.passport_owner
    AND issue_date <= NEW.issue_date
    AND (expiration_date IS NULL OR expiration_date >= NEW.issue_date)
    AND NOT passports.lost AND NOT passports.invalidated;

    IF v_passport_count >= 1 THEN
        RAISE EXCEPTION 'Person already has 1 active passports';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_passport_number BEFORE INSERT ON passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_number();


-- Trigger used to ensure that passport is not issued to a person with more than 2 active international passports
CREATE OR REPLACE FUNCTION verify_international_passport_number()
RETURNS TRIGGER AS $$
DECLARE
    v_passport_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_passport_count
    FROM international_passports
    WHERE passport_owner = NEW.passport_owner
    AND issue_date <= CURRENT_DATE
    AND (expiration_date IS NULL OR CURRENT_DATE >= NEW.issue_date)
    AND NOT passports.lost AND NOT passports.invalidated;

    IF v_passport_count >= 2 THEN
        RAISE EXCEPTION 'Person already has 2 active international passports';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_international_passport_number BEFORE INSERT ON international_passports
    FOR EACH ROW EXECUTE FUNCTION verify_international_passport_number();

-- VISAS

-- Trigger to ensure that visa is not issued to expired passport
CREATE OR REPLACE FUNCTION verify_visa_passport_expiration_date()
RETURNS TRIGGER AS $$
DECLARE
    v_passport_expiration_date DATE;
BEGIN
    SELECT expiration_date INTO v_passport_expiration_date
    FROM passports
    WHERE id = NEW.passport;

    IF v_passport_expiration_date < NEW.issue_date THEN
        RAISE EXCEPTION 'Visa is issued to expired passport';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;