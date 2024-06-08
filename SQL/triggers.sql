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
    FOR v_prerequisite_kind IN (SELECT prerequirement FROM educational_certificates_types WHERE id = NEW.kind)
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
    IF NOT EXISTS (
        SELECT 1
        FROM educational_instances_types_relation
        WHERE instance_id = NEW.issuer
        AND type_id = NEW.kind
    ) THEN
        RAISE EXCEPTION 'Educational certificate kind was not issued by the educational instance of the same kind';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_kind BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_kind();

-- Trigger to ensure there is no cycle in the prerequisites
CREATE OR REPLACE FUNCTION check_for_cycle()
RETURNS TRIGGER AS $$
DECLARE
    visited_ids INTEGER[];
    current_id INTEGER;
    prereq_id INTEGER;
BEGIN
    visited_ids := ARRAY[NEW.id];
    current_id := NEW.id;

    LOOP
        SELECT prerequirement INTO prereq_id
        FROM educational_certificates_types
        WHERE id = current_id;

        IF prereq_id IS NULL THEN
            EXIT;
        END IF;

        IF prereq_id = ANY (visited_ids) THEN
            RAISE EXCEPTION 'Cycle detected involving id %', NEW.id;
        END IF;

        visited_ids := array_append(visited_ids, prereq_id);
        current_id := prereq_id;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_for_cycle BEFORE INSERT OR UPDATE ON educational_certificates_types
    FOR EACH ROW EXECUTE FUNCTION check_for_cycle();

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
    AND NOT international_passports.lost AND NOT international_passports.invalidated;

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

-- Trigger to ensure that marriage certificated is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_marriage_certificate_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'Marriage certificate' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Marriage certificate is issued by non-existing office';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_marriage_certificate_issuer BEFORE INSERT ON marriage_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_marriage_certificate_issuer();

-- Trigger to ensure that divorce certificated is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_divorce_certificate_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'divorce certificate' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Divorce certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_divorce_certificate_issuer BEFORE INSERT ON divorce_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_divorce_certificate_issuer();

-- Trigger to ensure that death certificate is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_death_certificate_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'death certificate' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Death certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_death_certificate_issuer BEFORE INSERT ON death_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_death_certificate_issuer();

-- Trigger to ensure that birth certificate is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_birth_certificate_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'birth certificate' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Birth certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_birth_certificate_issuer BEFORE INSERT ON birth_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_birth_certificate_issuer();

-- Trigger to ensure that passport is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_passport_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'passport' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Passport is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_passport_issuer BEFORE INSERT ON passports
    FOR EACH ROW EXECUTE FUNCTION verify_passport_issuer();

-- Trigger to ensure that international passport is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_international_passport_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'International passport' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'International passport is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_international_passport_issuer BEFORE INSERT ON international_passports
    FOR EACH ROW EXECUTE FUNCTION verify_international_passport_issuer();

-- Trigger to ensure that driver license is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_driver_license_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'driver license' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Driver license is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_driver_license_issuer BEFORE INSERT ON drivers_licences
    FOR EACH ROW EXECUTE FUNCTION verify_driver_license_issuer();

-- Trigger to ensure that visa is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_visa_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE document = 'Visa' -- CHANGE ACCORDING TO DATA IN FILE
    ) THEN
        RAISE EXCEPTION 'Visa is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_visa_issuer BEFORE INSERT ON visas
    FOR EACH ROW EXECUTE FUNCTION verify_visa_issuer();

-- Trigger to ensure that driver license is issued to a person above 16 years old
CREATE OR REPLACE FUNCTION verify_driver_license_age()
RETURNS TRIGGER AS $$
DECLARE
    v_birth_date DATE;
BEGIN
    SELECT date_of_birth INTO v_birth_date
    FROM people
    WHERE id = NEW.person;

    IF v_birth_date > NEW.issue_date - INTERVAL '16 years' THEN
        RAISE EXCEPTION 'Driver license is issued to a person below 16 years old';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_driver_license_age BEFORE INSERT ON drivers_licences
    FOR EACH ROW EXECUTE FUNCTION verify_driver_license_age();

-- Trigger to ensure that educational certificate is issued by the office with such authority
CREATE OR REPLACE FUNCTION verify_educational_certificate_issuer()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM educational_instances
        JOIN educational_instances_types_relation ON educational_instances.id = educational_instances_types_relation.instance_id
        WHERE educational_instances_types_relation.type_id = NEW.kind
    ) THEN
        RAISE EXCEPTION 'Educational certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER verify_educational_certificate_issuer BEFORE INSERT ON educational_certificates
    FOR EACH ROW EXECUTE FUNCTION verify_educational_certificate_issuer();
