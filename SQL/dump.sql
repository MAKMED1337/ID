--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3 (Debian 16.3-1.pgdg120+1)
-- Dumped by pg_dump version 16.3 (Debian 16.3-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: add_user(bigint, character varying, character varying); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.add_user(p_id bigint, p_login character varying, p_password character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.add_user(p_id bigint, p_login character varying, p_password character varying) OWNER TO admin;

--
-- Name: check_for_cycle(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.check_for_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.check_for_cycle() OWNER TO admin;

--
-- Name: get_administrated_offices(integer); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.get_administrated_offices(p_administrator_id integer) RETURNS TABLE(id integer, country character varying, city character varying, name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT offices.id, offices.country, offices.city, offices.name
    FROM offices
    JOIN administrators ON offices.id = administrators.office_id
    WHERE administrators.user_id = p_administrator_id;
END;
$$;


ALTER FUNCTION public.get_administrated_offices(p_administrator_id integer) OWNER TO admin;

--
-- Name: get_issued_documents_types(integer); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.get_issued_documents_types(p_office_id integer) RETURNS TABLE(id integer, document character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT document_types.id, document_types.document
    FROM document_types
    JOIN office_kinds_documents ON document_types.id = office_kinds_documents.document_id
    JOIN offices_kinds ON office_kinds_documents.kind_id = offices_kinds.kind
    JOIN offices_kinds_relations ON offices_kinds.kind = offices_kinds_relations.kind_id
    WHERE offices_kinds_relations.office_id = p_office_id;
END;
$$;


ALTER FUNCTION public.get_issued_documents_types(p_office_id integer) OWNER TO admin;

--
-- Name: login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.login(p_login character varying, p_password character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    SELECT id INTO v_user_id
    FROM accounts
    WHERE login = p_login
    AND hashed_password = crypt(p_password, hashed_password);
    RETURN v_user_id;
END;
$$;


ALTER FUNCTION public.login(p_login character varying, p_password character varying) OWNER TO admin;

--
-- Name: verify_birth_certificate_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_birth_certificate_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 4 -- BIRTH CERTIFICATE
    ) THEN
        RAISE EXCEPTION 'Birth certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_birth_certificate_issuer() OWNER TO admin;

--
-- Name: verify_birth_certificate_parents(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_birth_certificate_parents() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (NEW.father IS NOT NULL AND NEW.father = NEW.person)
    OR (NEW.mother IS NOT NULL AND NEW.mother = NEW.person) THEN
        RAISE EXCEPTION 'Father or mother is equal to child in birth certificate';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_birth_certificate_parents() OWNER TO admin;

--
-- Name: verify_birth_certificate_parents_cycle(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_birth_certificate_parents_cycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    visited_ids INTEGER[];
    current_id INTEGER;
    father_id INTEGER;
    mother_id INTEGER;
BEGIN
    visited_ids := ARRAY[NEW.person];
    current_id := NEW.person;

    LOOP
        SELECT father, mother INTO father_id, mother_id
        FROM birth_certificates
        WHERE person = current_id;

        IF father_id IS NULL AND mother_id IS NULL THEN
            EXIT;
        END IF;

        IF father_id IS NOT NULL AND father_id = ANY (visited_ids) THEN
            RAISE EXCEPTION 'Cycle detected involving father in birth certificate';
        END IF;

        IF mother_id IS NOT NULL AND mother_id = ANY (visited_ids) THEN
            RAISE EXCEPTION 'Cycle detected involving mother in birth certificate';
        END IF;

        IF father_id IS NOT NULL THEN
            visited_ids := array_append(visited_ids, father_id);
            current_id := father_id;
        ELSE
            visited_ids := array_append(visited_ids, mother_id);
            current_id := mother_id;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_birth_certificate_parents_cycle() OWNER TO admin;

--
-- Name: verify_certificate_issue_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_certificate_issue_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.issue_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'Certificate is issued in the future';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_certificate_issue_date() OWNER TO admin;

--
-- Name: verify_death_certificate_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_death_certificate_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 5 -- DEATH CERTIFICATE
    ) THEN
        RAISE EXCEPTION 'Death certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_death_certificate_issuer() OWNER TO admin;

--
-- Name: verify_divorce_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_divorce_certificate_date() OWNER TO admin;

--
-- Name: verify_divorce_certificate_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_certificate_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 6 -- DIVORCE CERTIFICATE
    ) THEN
        RAISE EXCEPTION 'Divorce certificate is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_divorce_certificate_issuer() OWNER TO admin;

--
-- Name: verify_divorce_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_divorce_date() OWNER TO admin;

--
-- Name: verify_divorce_unique(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_divorce_unique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_divorce_unique() OWNER TO admin;

--
-- Name: verify_driver_license_age(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_driver_license_age() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_driver_license_age() OWNER TO admin;

--
-- Name: verify_driver_license_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_driver_license_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 7 -- DRIVER LICENSE
    ) THEN
        RAISE EXCEPTION 'Driver license is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_driver_license_issuer() OWNER TO admin;

--
-- Name: verify_educational_certificate_birth_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_birth_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_birth_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_death_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_death_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_death_date() OWNER TO admin;

--
-- Name: verify_educational_certificate_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_issuer() OWNER TO admin;

--
-- Name: verify_educational_certificate_kind(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_kind() OWNER TO admin;

--
-- Name: verify_educational_certificate_prerequisites(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_educational_certificate_prerequisites() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_educational_certificate_prerequisites() OWNER TO admin;

--
-- Name: verify_international_passport_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_international_passport_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 1 -- INTERNATIONAL PASSPORT
    ) THEN
        RAISE EXCEPTION 'International passport is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_international_passport_issuer() OWNER TO admin;

--
-- Name: verify_international_passport_number(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_international_passport_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_international_passport_number() OWNER TO admin;

--
-- Name: verify_marriage_certificate_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_marriage_certificate_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_marriage_certificate_date() OWNER TO admin;

--
-- Name: verify_marriage_certificate_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_marriage_certificate_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 2 -- MARRIAGE CERTIFICATE
    ) THEN
        RAISE EXCEPTION 'Marriage certificate is issued by non-existing office';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_marriage_certificate_issuer() OWNER TO admin;

--
-- Name: verify_marriage_unique(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_marriage_unique() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_marriage_unique() OWNER TO admin;

--
-- Name: verify_passport_death_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_passport_death_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_passport_death_date() OWNER TO admin;

--
-- Name: verify_passport_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_passport_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.issuer)
        WHERE id = 8 -- PASSPORT
    ) THEN
        RAISE EXCEPTION 'Passport is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_passport_issuer() OWNER TO admin;

--
-- Name: verify_passport_number(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_passport_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_passport_number() OWNER TO admin;

--
-- Name: verify_visa_issuer(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_visa_issuer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM get_issued_documents_types(NEW.inner_issuer)
        WHERE id = 3 -- VISA 
    ) THEN
        RAISE EXCEPTION 'Visa is issued by office without enough authority';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.verify_visa_issuer() OWNER TO admin;

--
-- Name: verify_visa_passport_expiration_date(); Type: FUNCTION; Schema: public; Owner: admin
--

CREATE FUNCTION public.verify_visa_passport_expiration_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.verify_visa_passport_expiration_date() OWNER TO admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    login character varying NOT NULL,
    hashed_password character varying(200) NOT NULL
);


ALTER TABLE public.accounts OWNER TO admin;

--
-- Name: administrators; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.administrators (
    user_id bigint NOT NULL,
    office_id integer NOT NULL
);


ALTER TABLE public.administrators OWNER TO admin;

--
-- Name: birth_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.birth_certificates (
    id bigint NOT NULL,
    father bigint,
    mother bigint,
    person bigint NOT NULL,
    issuer integer NOT NULL,
    country_of_birth character varying(100),
    city_of_birth character varying(100),
    issue_date date
);


ALTER TABLE public.birth_certificates OWNER TO admin;

--
-- Name: people; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.people (
    id bigint NOT NULL,
    date_of_birth date DEFAULT CURRENT_DATE NOT NULL,
    date_of_death date,
    name character varying(100) NOT NULL,
    surname character varying(100) NOT NULL
);


ALTER TABLE public.people OWNER TO admin;

--
-- Name: birth_certificates_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.birth_certificates_view AS
 SELECT id,
    person,
    ( SELECT people.name
           FROM public.people
          WHERE (people.id = birth_cert.person)) AS "Person's Name",
    ( SELECT people.date_of_birth
           FROM public.people
          WHERE (people.id = birth_cert.person)) AS "Date of Birth",
    city_of_birth AS "City of Birth",
    country_of_birth AS "Country of Birth",
    ( SELECT people.name
           FROM public.people
          WHERE (people.id = birth_cert.father)) AS "Father's Name",
    ( SELECT people.name
           FROM public.people
          WHERE (people.id = birth_cert.mother)) AS "Mother's Name",
    ( SELECT birth_certificates.issue_date
           FROM public.birth_certificates
          WHERE (birth_certificates.id = birth_cert.id)) AS "Date of Issue"
   FROM public.birth_certificates birth_cert
  ORDER BY country_of_birth DESC;


ALTER VIEW public.birth_certificates_view OWNER TO admin;

--
-- Name: cities; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.cities (
    id integer NOT NULL,
    country character varying(100) NOT NULL,
    city character varying(100) NOT NULL
);


ALTER TABLE public.cities OWNER TO admin;

--
-- Name: countries; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.countries (
    country character varying NOT NULL,
    id integer NOT NULL
);


ALTER TABLE public.countries OWNER TO admin;

--
-- Name: death_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.death_certificates (
    id bigint NOT NULL,
    issuer integer NOT NULL,
    person bigint NOT NULL,
    issue_date date NOT NULL
);


ALTER TABLE public.death_certificates OWNER TO admin;

--
-- Name: death_certificates_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.death_certificates_view AS
 SELECT id AS "ID",
    person AS "Person ID",
    ( SELECT people.name
           FROM public.people
          WHERE (people.id = death_cert.person)) AS "Name",
    ( SELECT people.surname
           FROM public.people
          WHERE (people.id = death_cert.person)) AS "Surname",
    ( SELECT people.date_of_death
           FROM public.people
          WHERE (people.id = death_cert.person)) AS "Date of Death",
    issue_date AS "Date of Issue"
   FROM public.death_certificates death_cert
  ORDER BY issue_date DESC;


ALTER VIEW public.death_certificates_view OWNER TO admin;

--
-- Name: divorce_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.divorce_certificates (
    id bigint NOT NULL,
    divorce_id bigint NOT NULL,
    issue_date date NOT NULL,
    issuer integer NOT NULL
);


ALTER TABLE public.divorce_certificates OWNER TO admin;

--
-- Name: divorces; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.divorces (
    id bigint NOT NULL,
    marriage_id bigint NOT NULL,
    divorce_date date NOT NULL
);


ALTER TABLE public.divorces OWNER TO admin;

--
-- Name: marriages; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.marriages (
    id bigint NOT NULL,
    person1 bigint NOT NULL,
    person2 bigint NOT NULL,
    marriage_date date NOT NULL,
    CONSTRAINT cns_marriage_certificates_different_people CHECK ((person1 <> person2))
);


ALTER TABLE public.marriages OWNER TO admin;

--
-- Name: divorce_certificates_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.divorce_certificates_view AS
 SELECT id AS "ID",
    divorce_id AS "Divorce ID",
    ( SELECT divorces.marriage_id
           FROM public.divorces
          WHERE (divorces.id = div_cert.divorce_id)) AS "Marriage ID",
    ( SELECT marriages.person1
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS "First Person",
    ( SELECT marriages.person2
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS "Second Person",
    ( SELECT marriages.marriage_date
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS "Date of Marriage",
    ( SELECT divorces.divorce_date
           FROM public.divorces
          WHERE (divorces.id = div_cert.divorce_id)) AS divorce_date,
    issue_date AS "Date of Issue",
    issuer AS "Issuer"
   FROM public.divorce_certificates div_cert
  ORDER BY issue_date DESC;


ALTER VIEW public.divorce_certificates_view OWNER TO admin;

--
-- Name: document_types; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.document_types (
    id integer NOT NULL,
    document character varying NOT NULL
);


ALTER TABLE public.document_types OWNER TO admin;

--
-- Name: drivers_licences; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.drivers_licences (
    id bigint NOT NULL,
    type character varying(3) NOT NULL,
    person bigint NOT NULL,
    issuer integer NOT NULL,
    issue_date date NOT NULL,
    expiration_date date NOT NULL
);


ALTER TABLE public.drivers_licences OWNER TO admin;

--
-- Name: drivers_licences_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.drivers_licences_view AS
 SELECT id AS "ID",
    person AS "Person ID",
    type AS "Type",
    ( SELECT people.name
           FROM public.people
          WHERE (people.id = drivers_licence.person)) AS "Name",
    ( SELECT people.surname
           FROM public.people
          WHERE (people.id = drivers_licence.person)) AS "Surname",
    ( SELECT people.date_of_birth
           FROM public.people
          WHERE (people.id = drivers_licence.person)) AS "Date of Birth",
    issue_date AS "Date of Issue",
    expiration_date AS "Expiration Date"
   FROM public.drivers_licences drivers_licence
  ORDER BY issue_date DESC;


ALTER VIEW public.drivers_licences_view OWNER TO admin;

--
-- Name: educational_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_certificates (
    id bigint NOT NULL,
    issuer integer NOT NULL,
    holder bigint NOT NULL,
    issue_date date NOT NULL,
    kind integer NOT NULL
);


ALTER TABLE public.educational_certificates OWNER TO admin;

--
-- Name: educational_certificates_types; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_certificates_types (
    id integer NOT NULL,
    name character varying NOT NULL,
    prerequirement integer
);


ALTER TABLE public.educational_certificates_types OWNER TO admin;

--
-- Name: educational_certificates_types_id_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.educational_certificates_types_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.educational_certificates_types_id_seq OWNER TO admin;

--
-- Name: educational_certificates_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: admin
--

ALTER SEQUENCE public.educational_certificates_types_id_seq OWNED BY public.educational_certificates_types.id;


--
-- Name: educational_instances; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_instances (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    address character varying(200) NOT NULL,
    creation_date date NOT NULL,
    closure_date date,
    country character varying NOT NULL,
    city character varying NOT NULL
);


ALTER TABLE public.educational_instances OWNER TO admin;

--
-- Name: educational_certificates_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.educational_certificates_view AS
 SELECT id,
    holder,
    ( SELECT educational_certificates_types.name
           FROM public.educational_certificates_types
          WHERE (educational_certificates_types.id = edu_cert.kind)) AS "Level of Education",
    ( SELECT educational_instances.name
           FROM public.educational_instances
          WHERE (educational_instances.id = edu_cert.issuer)) AS "Issuer Instance",
    issue_date AS "Date of Issue"
   FROM public.educational_certificates edu_cert
  ORDER BY issue_date DESC;


ALTER VIEW public.educational_certificates_view OWNER TO admin;

--
-- Name: educational_instances_types_relation; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.educational_instances_types_relation (
    instance_id integer NOT NULL,
    type_id integer NOT NULL
);


ALTER TABLE public.educational_instances_types_relation OWNER TO admin;

--
-- Name: international_passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.international_passports (
    id bigint NOT NULL,
    original_name character varying(100) NOT NULL,
    original_surname character varying(100) NOT NULL,
    en_name character varying(100) NOT NULL,
    en_surname character varying(100) NOT NULL,
    issuer integer NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    expiration_date date NOT NULL,
    sex character(1) NOT NULL,
    passport_owner bigint NOT NULL,
    country character varying NOT NULL,
    lost boolean DEFAULT false NOT NULL,
    invalidated boolean DEFAULT false NOT NULL,
    series character(2) NOT NULL,
    CONSTRAINT cns_international_passports_sex CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])))
);


ALTER TABLE public.international_passports OWNER TO admin;

--
-- Name: marriage_certificates; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.marriage_certificates (
    id bigint NOT NULL,
    marriage_id bigint NOT NULL,
    issuer integer NOT NULL,
    issue_date date NOT NULL
);


ALTER TABLE public.marriage_certificates OWNER TO admin;

--
-- Name: marriage_certificates_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.marriage_certificates_view AS
 SELECT id AS "ID",
    marriage_id AS "Marriage ID",
    ( SELECT marriages.person1
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS "First Person",
    ( SELECT marriages.person2
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS "Second Person",
    ( SELECT marriages.marriage_date
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS "Date of Marriage",
    issuer AS "Issuer",
    issue_date AS "Date of Issue"
   FROM public.marriage_certificates mar_cert
  ORDER BY issue_date DESC;


ALTER VIEW public.marriage_certificates_view OWNER TO admin;

--
-- Name: office_kinds_documents; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.office_kinds_documents (
    document_id integer NOT NULL,
    kind_id integer NOT NULL
);


ALTER TABLE public.office_kinds_documents OWNER TO admin;

--
-- Name: offices; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices (
    id integer NOT NULL,
    name character varying NOT NULL,
    country character varying NOT NULL,
    address character varying(200) NOT NULL,
    city character varying NOT NULL
);


ALTER TABLE public.offices OWNER TO admin;

--
-- Name: offices_kinds; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices_kinds (
    kind integer NOT NULL,
    description character varying(100) NOT NULL
);


ALTER TABLE public.offices_kinds OWNER TO admin;

--
-- Name: offices_kinds_relations; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.offices_kinds_relations (
    office_id integer NOT NULL,
    kind_id integer NOT NULL
);


ALTER TABLE public.offices_kinds_relations OWNER TO admin;

--
-- Name: passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.passports (
    id bigint NOT NULL,
    original_surname character varying(100) NOT NULL,
    original_name character varying(100) NOT NULL,
    en_name character varying(100) NOT NULL,
    en_surname character varying(100) NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    expiration_date date NOT NULL,
    sex character(1) NOT NULL,
    issuer integer NOT NULL,
    passport_owner bigint NOT NULL,
    lost boolean DEFAULT false NOT NULL,
    invalidated boolean DEFAULT false NOT NULL,
    CONSTRAINT cns_passports_issue_expiry CHECK ((issue_date < expiration_date)),
    CONSTRAINT cns_passports_sex CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])))
);


ALTER TABLE public.passports OWNER TO admin;

--
-- Name: pet_passports; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.pet_passports (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    pet_owner bigint NOT NULL,
    issuer integer NOT NULL,
    date_of_birth date NOT NULL,
    species character varying NOT NULL
);


ALTER TABLE public.pet_passports OWNER TO admin;

--
-- Name: visa_categories; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.visa_categories (
    type integer NOT NULL,
    description character varying(100),
    working_permit boolean NOT NULL,
    residence_permit boolean NOT NULL,
    duration interval NOT NULL,
    country character varying NOT NULL
);


ALTER TABLE public.visa_categories OWNER TO admin;

--
-- Name: visas; Type: TABLE; Schema: public; Owner: admin
--

CREATE TABLE public.visas (
    id bigint NOT NULL,
    type integer NOT NULL,
    passport bigint NOT NULL,
    issue_date date NOT NULL,
    inner_issuer integer NOT NULL,
    country character varying NOT NULL
);


ALTER TABLE public.visas OWNER TO admin;

--
-- Name: visa_view; Type: VIEW; Schema: public; Owner: admin
--

CREATE VIEW public.visa_view AS
 SELECT id AS "ID",
    ( SELECT ((international_passports.series)::text || international_passports.id)
           FROM public.international_passports
          WHERE (international_passports.id = visa.passport)) AS "Passport ID",
    ( SELECT visa_categories.description
           FROM public.visa_categories
          WHERE ((visa_categories.type = visa.type) AND ((visa_categories.country)::text = (visa.country)::text))) AS "Visa Category",
    issue_date AS "Date of Issue",
    (issue_date + ( SELECT visa_categories.duration
           FROM public.visa_categories
          WHERE ((visa_categories.type = visa.type) AND ((visa_categories.country)::text = (visa.country)::text)))) AS "Expiration Date"
   FROM public.visas visa
  ORDER BY issue_date DESC;


ALTER VIEW public.visa_view OWNER TO admin;

--
-- Name: educational_certificates_types id; Type: DEFAULT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates_types ALTER COLUMN id SET DEFAULT nextval('public.educational_certificates_types_id_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.accounts (id, login, hashed_password) FROM stdin;
1	user1	$2a$06$jrjAWh3Zlhk4jBGx3wI6B.8M0BLnQd.ZCviFyETxkSZcXmDC11FMS
2	user2	$2a$06$aQSVDOWlYCO1JP5UCUka6u5rTviFydYnW6TBfvTrzAB948H3Rltga
3	user3	$2a$06$R0xGZoW6FUVxfM.EfgfMhO5CtAq1Jz1FXaUnQldccOoLr9xAftDLC
4	user4	$2a$06$kfNEv.oHhWa87CJnCKgRQueIyTIrWvcvWu6T0.0kx7Ef3iViYXf2.
5	user5	$2a$06$0tr0Dvpy0YbM4dvvnXKW5OqbMxutcFTgCigDjrGX.sYbO9oQ9xpza
6	user6	$2a$06$va5s0GxIi8GLmvoZcWJcdeeqmq7YSv.3bboChCV1UhOx8yTlv/Wgi
7	user7	$2a$06$xUn1aA7.Trb.LiEKrMwNTOkrftI358Jajuo1p/4W4qBOgfk72SMWC
8	user8	$2a$06$wJjGm2nDJNZjyo02hYMmJOUw6HP662RMcdypqFbOk1C9kfiXiXVz2
9	user9	$2a$06$4RdSS6gtj0v6o5QKtyfnbecRbGCa.Eg8fcmwrsOffc0tbSAhiURZa
10	user10	$2a$06$D.Xk93bQ4w73my//cbrFFu5ObozkhJoDBlcCwnZn3AJ.NT5EA3epq
11	user11	$2a$06$2v5lv8tsDcteTU2525zKcOpOyJiKeQSqOC.6LNVL8rlK/SdSiZMO.
12	user12	$2a$06$G65bN0c7obNYngQvFQRgKu80nroSBWOnf.3ppfA6K7JZVoR9u9jLO
13	user13	$2a$06$QfkYKM/4dgXfVE0kPLijLOYiXpQMyHBJa402ZoiuTjTdKpH6L5QxW
14	user14	$2a$06$yN.x1jGhF7FPZLfcqtM8U.4yo5ETo/5Mwo9bjtvgWCK2kmP7msVyu
15	user15	$2a$06$Pb9ak53ru1h6JPOXNq2bpuwVTzurEXFtzc.65UGBu9VK0MIxz1USO
16	user16	$2a$06$TWDjoy1XzfWAL3qmhT9a0.9f0y7H6EF6.ISpZ.ms5fjetHoeJ0.uK
17	user17	$2a$06$u7L5P9tEmJy/V9sF1UBBUu4.TxACHSEEWmGMBjUx2EVCnJXJ0nR2G
18	user18	$2a$06$9zua8Oh/J7A8udQkev8A7.zlRXJm5N3Vjwt89y0qxOxG873ci7vW6
19	user19	$2a$06$wgJmLFZ0Y5NX4PKIMIj5C.b7tuAnLIPFhSZ5xxv.t.qezKtIYEKea
20	user20	$2a$06$fI.85tLaDd4YG1dX.YmKi.OzQz15PDfPjGD62CT/kprTWbZ5tHZg.
21	user21	$2a$06$WWJzuZcqTm3owq4iBVf2uu4Dz0g2f.3rb9PZTzW.xI03nJt.3JMFC
22	user22	$2a$06$HDk2Jdg76Oewms6Dm6ORCeyDUoZwS8fkt2wQZwoM9YcY5t/FsIb..
23	user23	$2a$06$VJlPdU2K.whEYf4CCcmH/Ot/tA9gVoxDjjyZJkUrfr6XqdSmosWNi
24	user24	$2a$06$FwkN8aJmk2aTlixoHwR2N.qI6UhMmttBzvBVqjOg7PXOP2siv20Lm
25	user25	$2a$06$tS9UJElDO.0Wp0SsStIMJOGpiv9Kh29WeKOkKKKws2mhJG9mbqlfO
26	user26	$2a$06$hE3PCBhEUbDyRBMTN6q1YOSN/hAh1h3TDsOWYJwjl5GNYAH2jSuPe
27	user27	$2a$06$dxA4q3bFXUKVrMeIROeCyegl7XWJ7577dqeDV2gOYTUXN1HTzcnBq
28	user28	$2a$06$XGIcjBNOqTTSM6rJzcTRtO.YZPuvgRBKCn7kmOckKggvNrlcipyMC
29	user29	$2a$06$D5sloTJFVELmKwC658/ROerQLuaf7D9R4RNFNVMaMntmTvvLhd1vK
30	user30	$2a$06$xxxVikVvNKxmRvD0ycEC6.QwCsGrwN1K5PnfrKn7y1QHdG31xKaxO
31	user31	$2a$06$9NlwNyx1WNrxwrRvRkLa.ek54P6xYZ.txlVzzCq7qZI/latVLcAgC
32	user32	$2a$06$zqtm8.IaN/dyTfvdwBiyhu4Sz2ypymtqex2iyO0QjfFhIu4WrUdFK
33	user33	$2a$06$WSYcEzAKATXOpkV6O.L0jeo.MGDL6CQlyL81E67IspypYw/AfkoqC
34	user34	$2a$06$ctUycz5kZQ5D.pHnqjLUZuWY3wKdFoR9qOS6w9JnIKVRrXgTSKHUm
35	user35	$2a$06$crts7qHs69bWdcD/TnwAa.rybSaqjQSzd7nAwFtxLoOMBqqH1UncG
36	user36	$2a$06$z8AyfGStRygE.BjbLgwxlOkKfslfu2DVjsdOTIhXS9HQ.slAgdmiO
37	user37	$2a$06$aHMsrYdUnzxIH1/5fXrfvOLyxwKTZXzlnwirhmmC6/cmoc9sZ9lci
38	user38	$2a$06$8nvgnkFIEhnsieTh5DP74OVCPUXua22VJucqZ06qKOkUtLMFl.ENm
39	user39	$2a$06$HGOtDDsmAOD2X99PS.zcLeWUYPn0kU3zAeA3VpUvBNuUDjNjypjI2
40	user40	$2a$06$7tw5zWqKpj.4bzB4TagPTulmtN1lSOiVlBSUClvnnUuO0BmXevS/2
41	user41	$2a$06$.yNc3X3GiDv4BfQHaBH0b.sCc55jm0wf9zS2K9GRXcXB2UostTfuS
42	user42	$2a$06$7Jx.YivNXvNkp5.FMnZ8z.SgVpCIP.KnCF585/Sehwn2wZmK/Ejrq
43	user43	$2a$06$RraROwJ7tBrKs.fNQaAV1Opz8bwTFPHIeOUHkf6d.Fhg1wfJ0yMle
44	user44	$2a$06$sZmIwYvzHLYLBlXTXey3pO4KrpNBuQ9h7nXPXGDFwqE/sMv0VvSY.
45	user45	$2a$06$StMlUxsFmPHT5631Ffsv7uqn2yEPO19rpzDO7p0slCmK9fj76QoPu
46	user46	$2a$06$CnbyOsbNlUgBoyv3aLIS3OIL8SzbKDfc/50X5tBzGwS/y6pnM7Gi6
47	user47	$2a$06$tYxNQsUyKSR30uKwYhTd6e2un/yMZ88HKZZyRxS5gDsGiP9VRkuIy
48	user48	$2a$06$RqX0ih3BrFngF0D9Lzlf3OjYV2/cZVomRm0u6GWGIJjbcYJWFq/ky
49	user49	$2a$06$eKzoV.py0JjXUBLkh7RsTOFi8YtVyX6Om2Srine33HvlFcmC3Z6km
50	user50	$2a$06$uMpVbdxWVjz3M34VF/Y4dOzU5pjPn2IATmJuJG0tiPgVFJ2LQEF16
51	user51	$2a$06$NE3xLJrjtKazv4g1i0dnweiMIcAfsGyG5VATqPLQd5h/wuHiF15gi
52	user52	$2a$06$fa4JeksIC0umt2kFvPGcG.8grATUEyfdP8jSnGEMvmL5Jp4bubhya
53	user53	$2a$06$e7Sy5idhomU3fPWx3Jq5ZeFUhQxStntXJH3eVrWy3wDwQjW1XuTl.
54	user54	$2a$06$Yw0SzEwGGt7qsg3pnVQd1.mejO3cLNhCzdt2XpGaizmc3PIW/S.aO
55	user55	$2a$06$CXoL8NRok/tUkdhb9bLxJuzXYz4i/FVoEWBGSFJ/elQZrrh/snmEO
56	user56	$2a$06$iLLwHXFDAYh48Jl0uZJ5YO2mdElgbxwpv0rEY94GVwuQQ.Y58M10e
57	user57	$2a$06$pv6BIoSlGbz8bwpO6UAWCOEWKTeDvq/8mX3JOosMKwezHwi.gIWcu
58	user58	$2a$06$9Fs.pk/kMGLVrpoBku6mqeUdARx0t29ShfyTCPK5uw02duEJgwezq
59	user59	$2a$06$png4bws8mKp4h1kAvE7.eOY.ez/wdlWAq87E6oTy0f1WrFXkOuhj6
60	user60	$2a$06$uEFpAOtpyVxtZ8ttg1tGQOorWHL.D8G43jBc78HH58fPIyQUQblYi
61	user61	$2a$06$Ob3yl3hyscxCfvuFKgg5cOseVa98DO/SwcclfI86mj/M3Df/SlFV.
62	user62	$2a$06$onXDcf0FxwrV33vyC/DrIOF9aXnxjfyiNB0znPsSNSCgv00lCbiKi
63	user63	$2a$06$Fi3DMET9Q53vmefO8f2o.OXPZ9zglZqc4ls/zvFgUVprCUFedYzBy
64	user64	$2a$06$Rv6ACctaa0T65qry08kbeexTyvcm.hxtPjDlxIEtXaTIQ/o.4PEyq
65	user65	$2a$06$.Qv.a4gUcm2qV.JCq2OER.CyM8VTIDEnVkN2txFP3.rHFWZ/brrna
66	user66	$2a$06$dWIemupbBPussCPc70Xbv.Q/DrWAz.XoVnMvov6mQ1wH3UQOAiqaK
67	user67	$2a$06$ftegamxWc3yjzrrTjK/gceiwkWxc5xhM2FAe.lIGy2cfgxR5VsHDy
68	user68	$2a$06$ng9Ai734F3GzeFc0pH2ceOruyRnfaSib/FOSwwq3qzjBHKMzM9Wqm
69	user69	$2a$06$9a3RPQylzqXrWpOxI9TRyObtVmXve9e29.bogaPG0PK49A5EKRHfu
70	user70	$2a$06$gPmkt4bqIXoEl.UvSGcSwOUFhAlJJ24olJXrDqEnG9kkmu9TIwJxW
71	user71	$2a$06$4cOI0AB4ZasdsoXHCUJFe.4SXWj4RClq7nJNQpXimR1ytNwLDjapO
72	user72	$2a$06$qL222KjPTmWVCUEdM50u2OAQYfcoh5WTD.CULiWUD5WRUIHZk1stm
73	user73	$2a$06$KTvfmSfrDTxGoMd3fWAFLeg7JmzRe/GwSatGAvtb48WEJLGkg47E6
74	user74	$2a$06$q8S30yt2zacVXSkJKJRaUuMcB5IB.kelA9JxVwwx2NFeGhttLw3re
75	user75	$2a$06$n1L2wF1pt.EKSqS8./2Ne.PcCIEsZnF1SNl2aK7HrwQgFUZmNcn6a
76	user76	$2a$06$JTcewS.va3EwOcTis.8M9eknXVhXl7Zegj1lR4xgaiRgWl.RmXZmu
77	user77	$2a$06$6Chb7eNmkWOuifewRPafGuwGa/4T17dFMqTFa4yS2T78NKSGot0f2
78	user78	$2a$06$cRHS1/pfz8ob9k.VNHgvmeTnwmLVoxbMReO6j8N7FeIFcTe42cP.G
79	user79	$2a$06$xdbbUi9gpxVHtTLnbviPQ.U0GnJYj5.lL8Tmqsp5hKws30C2VsmqC
80	user80	$2a$06$uNDReBsnR1JCkxBl4HvlPOcL1DnE5YUB6nPof1qT0ymLYNtmsa4fG
81	user81	$2a$06$XyIt7ouHvufZ7L9V294D1.oqMYHTZi.x0GY14537NTiNBIo2crJcW
82	user82	$2a$06$wQm86D0dUpKGpQ7p7gctKOGu2KBDo1CkggFu1Uf8cX28qvXzcJHr.
83	user83	$2a$06$7tJZpFNRJhS7YgL3DLSDQuWW6n90glq4pXVqFLc1CpfEoxtx0UNXe
84	user84	$2a$06$GoaHScRSQARyoVuwbl2jYuNLEhbQb6b9srS/JrTwFTVjB12qgEIuu
85	user85	$2a$06$8vjgZdfeyWQXVmy/Uz6ysOSs2Dclj5kd/e5er13K4roSadVHKyMvq
86	user86	$2a$06$wNtO.ns8caXt1YFel8duIe3m7FXV1XX8PMR.OeFc4wrPQB1OzDI.6
87	user87	$2a$06$KuQmYpscJcKuRAIT4pIOienHmrMjSjsmoisSVLUjZEuZLbvEzOCRW
88	user88	$2a$06$yPFvJuN8adpyn6E7/VrnieOsuI2gmKtQWTiE4NSWDOsQlhCeANoc2
89	user89	$2a$06$VPR7BELPoRIWT9RKr65joO2/Ys6zziCpnHzvGE/XeY/VesxUw8ZzW
90	user90	$2a$06$sr266agfsalJP0BQmG7HJOleSxNZbF7YaY1tqVLHJdn2aK5CPWOiW
91	user91	$2a$06$.IcYtNvVmDDLy7xvkk8nK.weaRXew1pGppw3EtOFVbUUFFGX5aQ3q
92	user92	$2a$06$JWt8JVrwfqOrRWvrX/E5Uuf.BrQzQdHliF.f5eb/g0JQ5Lsjw9pb.
93	user93	$2a$06$EbXIz56991Qyx8p8x3wC1euhjFkCqvXeZCrVF4PVEIBBzDmJUqDrq
94	user94	$2a$06$bke2NyPNgN3yrKTv8EbtS.GmiE6WIHt4QVJzlOOhKaOAAiH9p4yzy
95	user95	$2a$06$QpMwy4o3ejMss4IH8M5WC.TK02YQA8Z5I3kEGjy7k3ErW4y7OHsjO
96	user96	$2a$06$0x/wu./Jaw.cV4kBPYatXeftn6Zxa.lvmzHzNybu3a02lM4ijXwci
97	user97	$2a$06$yQCUvDQ8qVfDBsPtKb61Tu2JJCtrbNWDSIwQ/1qtv9lldxGYJBNJW
98	user98	$2a$06$lnICXbbJH2zJ2rJt4SMoWOzr7kixLxZcLHrltwRtM2ya.zvC4QazC
99	user99	$2a$06$4.kwzok4kBpUfueWrO5uUe0Zu8UY67X8P3//1WA4HdUY0O8DuAavW
100	user100	$2a$06$tSqnDT0KyFdJ4Jr9.T1j3OM5Rnb7FIdawf6P4CcAsyPO4GnQ.Jpum
101	user101	$2a$06$DfJtnwbSHIhzx/59PC4Psuhcq3fxZ5/GaE94Ov5qOytz0/zIRhLDm
102	user102	$2a$06$RwNI5WvrWEa8qFlCjnqqbu0KNJ5Y7ujbH3PkzStH.tbc.bU8qsWBy
103	user103	$2a$06$vq81RE4E3Clu4ARISY4XnOBG2eAi4beRxSRzi7WI.uKJHobvysb9W
104	user104	$2a$06$xHgRF2qFlZvzdnjHkEEtZecqc2Na48UBMiw49p3VsTxn4kuQvBbRG
105	user105	$2a$06$dGajay2CzIpG5to.JTyDf.t.3aRITk1B8GfCBhg3yloD.2osh9BvG
106	user106	$2a$06$nTO5Ww0HYGM/e/RR.XiS1upxMY1xC/KMSSSwi.C0ByeGCniVj0gFG
107	user107	$2a$06$JRIIPI1vVJ51i5YLbbBpq.FudQr6LuyY.A3JzzH5pNhojpGAMeq3y
108	user108	$2a$06$8wLP2eyTv0aPcVoHuSuhu.tBC5HHnMuyEs6cxIZdB9dVveokqMsp6
109	user109	$2a$06$cZYV9ZvGSaN8wY.HYFcwKudfNnbeCcXt0y1ZfHVezNQZV1DNmGLKu
110	user110	$2a$06$xvG00dVZx7AgcLDrPYo8CuM8PLrK.wS2cQMMYEJAOwtJQEcg.eTnK
111	user111	$2a$06$GV8dxG3VEQH7OYQSkdRR0O1MWeZmWG/3JNvJhs67Btm4P.ZbktRIG
112	user112	$2a$06$0/Lg1gqfuCOIgjPvZrhEUeF/Xb4I0KAMXHv15Wd1zPYqxIjN7GKyS
113	user113	$2a$06$Es5cjywfOlcHHfKzMPXpfeiIsHucBr07GwQlMpeCX745V1evQA4gC
114	user114	$2a$06$65.FLOSSnTH/5HYNGb.zRuGCvZYRZVK/JF5NPvsVZI0lwvUYOuF7m
115	user115	$2a$06$oVG12nmOkeDQtllC0zd6feVaVHSeTCJK5GfZSymSJaP/c.Da7ykrG
116	user116	$2a$06$ejiX3hig0y/SAosop/s1Wu0jl/1udFJsqVpqnOdzRBDXNLQrNjO9q
117	user117	$2a$06$NEU18HL4SN6sQN3CpU/fxOQQeZY3TwM3idKCEt2Nnlb5Ih0qow/wW
118	user118	$2a$06$NuZDYDYywIucRVUgl.fCC.eB2VoGBivjaEW8gBz7Xz0SIEduypPP2
119	user119	$2a$06$DBYGHlB.7I94Fva1.thXHuh1fPudEx6FOwopwTVEn9V01lVHwlDtq
120	user120	$2a$06$Q1rAdwFJe.AmTeVx54JUxeh06.yAv27IV4NKniUWrqvheNG.35QYK
121	user121	$2a$06$rpKZZ3EXIZVP1QJiHIUpPuTuvm2k4fasHM.qhj3lvPHX5Vbpx7pHm
122	user122	$2a$06$kLG1Ey5PLnatB6Q5odO2YuyDr2JAdToIX8Mfcqmw9lkcprnfMgXmm
123	user123	$2a$06$BzzbPE63noijiTpxdSC39OzojZuDwnRuXkxRvc6yRrx/o9cCgc96W
124	user124	$2a$06$u3pymzrqT8h5IYI4blFxJ.eMu2NXKbEHxCEgXY8HY45dPRJAMKv/K
125	user125	$2a$06$znvuaFekgzPPXFXs1I.LIex/q9wAJSSHGgOQK6WQywOZo7jXJrg6i
126	user126	$2a$06$dBGl.4DZ7mjqK5G01VYP1euz.1dCDLDg85/475oQQB4PtTbJ6Y05O
127	user127	$2a$06$D5eD52ISW1fh1mMjl.37ueRuTq8o0qTz2YaP73T37l/rHxBRF2l.a
128	user128	$2a$06$gM1Md/ubFQigEGOQMkqZwu8AQH8VsMei3H2yFaaAB32lRYSHgaayO
129	user129	$2a$06$KFBLJGNnAP5UQn2OzcWCOeRZcprBXQW6NC75A3MmxBGXe8QX37KPS
130	user130	$2a$06$BMLFu7XpXZA2R0WCwj2ChueSDdYCWkGueCajVI8/IxwasRzYEPj5u
131	user131	$2a$06$y7d5ftSOTYL.vHD5p2J5cOnCapUhgHdXb92fokXFP2C.4.3qAcc66
132	user132	$2a$06$iyU93JW40yoKRykq/QV9r.gKckA5ztq09pk3AM3xU1Q.JaI11Et1u
133	user133	$2a$06$gh6uAarZ1f1x1Gc13CGs1e6Hl0Ur9GnLX/Sn0FKFcjT.RdU8S70Ey
134	user134	$2a$06$aQhyzSNSoJUa6V9MYjeQYukRfgy7ex2baPSIXI//yDxx2W5wpVmg6
135	user135	$2a$06$.dVRJrrsJIJosaJtDq4DFORnqBUQ/W.DqR7Q9v3CogCqF87BEnNj6
136	user136	$2a$06$ci9WLm0LGq80zqqDeG2r3uc4Wa9DF0yWZkJQRroys89nh0kZpts4K
137	user137	$2a$06$kw03GDEjz27hUeYCvoYDoO8WMq7fcDSXS30zXt6jJPMSfoCCgnGp2
138	user138	$2a$06$q61lHsFly6f6dl4wy0eoAunoDeAKyt6Q5a0YQshpFO7ul5PKf/XKm
139	user139	$2a$06$/nHlpdML4JCON1EL7fYsAuLw74VRc.w1cB1zPCcUp8OaqwS3.JpY2
140	user140	$2a$06$oBLqiCWsJBzCpqokH5DYL.Er2ZVx2mPgA/qv.4MnRiUHeH/z7rzY2
141	user141	$2a$06$3ilIr7.c141.WoC0WNyHJ.qyMDENuUxp1vDtFI4QYZvqA8LTZuTW2
142	user142	$2a$06$/z4zNNsCs1Vet2Fj/cfSq.XApL21nU6sICY3L1ReCQ5ddMscJCmt6
143	user143	$2a$06$Fk5DZhtyLQDYjuovDhgnJOtNl2DU1HiTpSjMfihd4y212TM/OEDRG
144	user144	$2a$06$bzOMpSqMNaMmSdlYNf.V/OUtVqCRH.3WhhBWontIx7Rid1ggUz.tG
145	user145	$2a$06$zlSEtRNP2CVw5OHe3jH/VO9a.FPA1LWSKFPajexqxUGd.hR9i6yDm
146	user146	$2a$06$qDBfaPNSmhKcLbodjIV.Pe7mU4JyoTh/j7SucM1iPdc2Rnc5eLvi2
147	user147	$2a$06$ZcwxaDeNcLgpICyNn8c5xeIIBDlG0Nn9PnEqMYtmdfkaJwsSPJ5e2
148	user148	$2a$06$kCG..bp/wqFjPYNdE9ktzuCJ2fYyYhfa74YDUP.WRiK6qVHcqlIqW
149	user149	$2a$06$WZfKgNphwCZ6jjIiwbqfo.Vu/r4b1Jv8PwOSJ2giMJxGBAHdFj1fe
150	user150	$2a$06$TyK.HUpYSHCXKgmd8KoGue9E31Lds/O8kb16psnshJuYB6gW5cg5K
151	user151	$2a$06$eC3jAHRSWHn.Xj6NCqja3OSoKZ6s9Vo3mThmLLLEh94lso75Xk/LC
152	user152	$2a$06$SUHF2.Xt7MhXI/DH25htg.UsTT5Ly94TJSBlU621diKCc2VwBEiiO
153	user153	$2a$06$M4Hihjg5idwS7Nz.kF6lDe9QccncStUDKxY/SGuRvirrBPhBZ1732
154	user154	$2a$06$jg6HxtU91G1Ojc0W0ZtYPeux8mYsGMHp/2H8d7gO3Vxkd6kzjg4LG
155	user155	$2a$06$uGcThUXO9rP1agSCDngP6udap.KqkMZTS6FFeN4wIttbe8/moE6qe
156	user156	$2a$06$6Id735ZvwVzsmNxjt181qenInibO6ZgBZpIB6WLtNCWnNzAvCo5Ue
157	user157	$2a$06$W1Rr2LPsTdLxG1YgTrY.5.uFSsKBbz21lW/7k1Mom2q39hO/gxfze
158	user158	$2a$06$I/7JxzA24oaEJTo3Z7GeeOQ7lzYSQTXt593gN.s9AEGhtL3rCnBJ2
159	user159	$2a$06$X5/0RGbKatU92OYbJkyd7.wlTCTaxa5wjVPfoV10fIfkosY.t9nXS
160	user160	$2a$06$FZGp5tn7yGbT/pSpLmjkKu4yx8JUwI7S4MR4ZLHdGIMLVQXX6ZXlW
161	user161	$2a$06$ylux3iZLopMTm5Tt3H5N8eeigqjdpaL1PlXV62EGJqju0T1JM4BE.
162	user162	$2a$06$J.c2bulZKN42691HxPMGtOC68pYJNquPurhIG9Yt7s6FUQX2oWRAy
163	user163	$2a$06$E6yc1xv1O4rXOKtV8/qGOO/VeosUM9064sQzSzb85OATtrddRYAvS
164	user164	$2a$06$AYq3gCzf36hvlB.TEuKv..93xMu69CUr0aa/goP6Jzt.IEapEsHqe
165	user165	$2a$06$eGuW7OTJU0lG3JX51gk7seWR7FdW9FkZDBeBDw/gFefNxsoDdJsU6
166	user166	$2a$06$PuNu4y3f2qkBs0KKBeD.6esKmiI.OKsQUbIn75.gLWR64W0Mj.d.u
167	user167	$2a$06$oFl6jXjgmd9PII/Gy1cTC.GNxTn7MY/YQwr36sidi3Aulre9nFuXe
168	user168	$2a$06$TgwPNDUGZrMxCv1fIc9ZLu9HgCXM2dF0peymhnQJLC90TosiVZuKi
169	user169	$2a$06$7GDgHDKFIrX/Nr9jYki9hO/8o5yqzPFUXAD..Dr8oWyUvgwMqUSwO
170	user170	$2a$06$skuxs/0jmZaZnbHOev1jpO6ikvFJcI7.gvtU9Vk60tnyNCC54Tad2
171	user171	$2a$06$cBSIWcs6suC3Nmy8oYO69.atej880oFkJS4KuIDsSqttyjA7PqDQ2
172	user172	$2a$06$l9mB54F6YpWzVd7/CCB7aO2XFGZ7at2Vi6h7h1Iq6NZ30SbeQPCyW
173	user173	$2a$06$/ZOJqGbCSCybiqrhjJ.TPu2IwhO2Z.jCz0hxcfJv69DVXmZ8cNZVi
174	user174	$2a$06$Jt8GpX0v.pA2NaBfMsf6sOyky8qm.8QPmQgH4sO/Posqpbsd7mfrO
175	user175	$2a$06$olMmkMa6PD/tTQbYZydJuudtvc/pOinJ8527.mc9TAfcJ3tBPgx7G
176	user176	$2a$06$yYaCb8ejPoxySR5BCWXequvAT8VoCXD9FoTYoaVa5pNHt2bazqw8q
177	user177	$2a$06$gmiBdeS7QKiSTe4gB0EiUesIyG4mD.FUFI879gcJeDyYbYVLJH8zu
178	user178	$2a$06$ZQ3gFtb4R9h9qAet3Fq4Decp8fIk5Tg6ufSicULb.GqQHRp4gcuCm
179	user179	$2a$06$Z9prohekTjZLMD82/ekjSOkGlG0xV3tLXEcJiBLT.4KWuEId/jXUG
180	user180	$2a$06$boaxpVggQTOJSxlbodRE0evotqVIZ4otVcg9BxBZsFvTzGLtm3fFW
181	user181	$2a$06$B9FZxW5Q2L7m/kO0TCiR1eIGCQBjTQG7.L8EYSK7JPQas4dDr.9/q
182	user182	$2a$06$mFZxQVY2mlUGJDkHOudgd.5QPdhnNfeyl4L6QiZqZHYZaRb36mCwK
183	user183	$2a$06$fOEF4Ghc20nMqZF2khkKsusHE9VZGwTasIrMgKfkeVj4z9s9U9THy
184	user184	$2a$06$0CdWGRCWfJBhd0/zJKIqjeJvMzywYC1FqL.iSkyIPuroShXjzm1j6
185	user185	$2a$06$FeNCtvNpSHsp3BCVjnYPROo5ue.wD4Q8sIvyh3Aunx2GJ04r0p7gO
186	user186	$2a$06$UYHaLxmqa.Rqd2IrEDTUt.6Wz73tB47QQ/gr2pSqFXG8DovZlzyp2
187	user187	$2a$06$3B.xZmhu53dyyE6eXsPv0upC5Qh0Qf8rvKb0pK3ZYdY6O4HnVt4h2
188	user188	$2a$06$aHEP/dG5/TxHQkc3YyRFX.8ue3ho1gL2tnLuP/WLxEzfxNu53VB1a
189	user189	$2a$06$PkUmMZ/I7t54v0QTXifynuPNx95Rou4B7s8wQe5GDlvYjeOkp49gC
190	user190	$2a$06$6gaxGTK3xzrUEsT9PQnqeeO88k5YNlC457Prb.mSTuO5qFetlAm42
191	user191	$2a$06$nq7eLONEktcByyXaFEgtBeFRz6eCtuas8BC0AdrYb2ot29etwT1iG
192	user192	$2a$06$K4.ezhW7W8SnnY8MBlRfoODjMbIdiyIhkrqZp6H34jyIim6NnUoYC
193	user193	$2a$06$g/t2Xs52dJNYE3gqjzC5/.SLx8r2atXEEETOUxQ6uB9N1XH1m7y6e
194	user194	$2a$06$DKrnHnuhKLs/DgB9YcW3Ee/A3V/dIiW1lqTEBv/UI3mXr60C8ltD6
195	user195	$2a$06$erk5.iepDDPFU2PYtGTElerjPh7.UZrsNeIICa/ZtoTYkM2u9/cKO
196	user196	$2a$06$knXaOB4OPqwhi4aArEmMjeGrmTu9z0KrsTGVdqDcDEFqjlXlJArky
197	user197	$2a$06$4JKy/H643bB547xO8Bp1jeFNWUW1R4GvtcDG2dpfCVGMmwhP5qO.S
198	user198	$2a$06$6kHcFNsxO5JXDs9qFiQ9KuNo30gmB1Hr2aKL8t.dKiwh5sdJ2abvW
199	user199	$2a$06$t87iSXuuJpRwwR1Xkz5FZuGht68vGZAZ2nJyVqflQ3zXd6M1BD/Yq
200	user200	$2a$06$M.MtZWnD5xoknZXU3BcQDuFQYNRNkvaHQDmidqkqxfbYCgky/qqny
201	user201	$2a$06$aJRoT.FDvDFwCl5zrnlOAeqWe5A1K7bdJrFXPIg.B3PnvANjnqLay
202	user202	$2a$06$xVKUr2idgL9C2uXK5dBF4OG.UpzCVoupduCeSXbxI1hYgsbRgbAHu
203	user203	$2a$06$4PbGtoa9O3sE8iGIzMvjWOgHhsPRSX.myvGFHfgRiW..ErPUldh1K
204	user204	$2a$06$5SYZNQjLjvvlv41D/8D/ZO712Xkni1jUgzgIMatErPqQZrq5Ojs4K
205	user205	$2a$06$Quzz/WnsnjAlgtuc9/smWOku3YYGbS.bWAPE8at76VGdqic.tyl76
206	user206	$2a$06$AgmlaSMle4q1nrG3IaHr/uj4p2AIrqtHaxkLj8qiP6fHwzuKU7B1a
207	user207	$2a$06$w9dxCSUj7VvLay7iUPWPTuIqAh9qwYSV2Wbwb8cVqN46UCx0KQqWK
208	user208	$2a$06$YxQowHhx6YMufEp9wumxmeSUIpI5KaaTKLI1YxxSLcM5v0FNQHgUy
209	user209	$2a$06$BLBCY./YlZn64RK7Fx7Jr.FB/ygM9ezC.XhDXs8eQ8FQVUFuNAwHO
210	user210	$2a$06$bEuT1omvtRnBJPDTuaubYOMk1k.bHL6C22xmcc/glEGFV/ZMU7SdG
211	user211	$2a$06$0pKnQCqViww.9CBoutViZ.cSfx0wUkVutdE5XeMAb0z./Eb9RyHZ.
212	user212	$2a$06$A.OPg4ACxz3XtO9fXkzA/OloHg3o7bgDXbf.H//.GDU9R/gBue3b6
213	user213	$2a$06$Ld51CQKJO6gImEMAsHZ8v.uB6XWnJ0L67bbyTWEZDdXOZwsWT6RoK
214	user214	$2a$06$zxF3GRb5Y/f1HjU1epxDGuQXlNDYLWHwC6ugWKuYoibkJOJ44ddla
215	user215	$2a$06$mGs7Tc.p767DrBcPU997aebqTvjKxx5jvfl.EldCTHky8oo.MC5ae
216	user216	$2a$06$/srpyBThMSKpG3ZfvsLH/.U7w7w/KcM/LZFfjwJrT.xmly0FLN/Pi
217	user217	$2a$06$Zf/b3s78qa1tj0fG6IfJlur8DfR7mGlbu.C1KNflEqddz1XUTT5h.
218	user218	$2a$06$jXG8SdfRpJvvgwxcqWR0Z.PMiTbzIU1STcDDLnTy0Hsu5u.3uZ2JS
219	user219	$2a$06$NgaV4/5pURhaEyixKq4boe.bRsD8JULtlUUjh5oYp2LCkmVLPN9iG
220	user220	$2a$06$IFgfB4XEyfVvXgoU2NiyseVDspdh5aFUZ93R0M8eWr./FyxMq/SLq
221	user221	$2a$06$DOdOOY1QiZig2uS5IArzMerIdFoUC78eCTyoWIp06.e.gfTfTgQ2y
222	user222	$2a$06$kNWLb0c82s1cpaxEimdPw.LSoKF5DIP9Blw3SDALuwTQeNwsghTCG
223	user223	$2a$06$ifszCsN0o1ncrVkXbzZa6uvLyS00ykxaIoEABqh3kBveEXhIX8MV.
224	user224	$2a$06$PDqEU6flPiydCqrCAlvn/uqEQLJvCToA2mzFrqOp/t2tWiV8u27qS
225	user225	$2a$06$LM2Ih1lazD2BKSALP.Jiuu3i2kCfHCvn84M5gAhdDXQW/kpy/vvzG
226	user226	$2a$06$BkrPItf/4p.LrxUQzOxGAus9BpqoMV/iPEw09KrXuefhSEBDDDSbC
227	user227	$2a$06$6bfYJSzm4av8S8Vnw.i7C.4b/sGAZBwnQSWcCVZKgWa763YHwrOnW
228	user228	$2a$06$/dk/EMp59xHgpu3dMDmk5.42m33n3BDdREx2AaUrCV5vvz9.N3UfS
229	user229	$2a$06$rLFLn66mtmGyM2BeEEUsYeVwpyE3z611zL4uwkkOMWSBNTgZYTtIa
230	user230	$2a$06$FC4mUGZNYfG3.6z8h1pyVOIR2ydDBhhn6d5Ay0HtUSuUrU834ulN.
231	user231	$2a$06$.2avowZqlCbw0blPH9oZ3OJO6StLY0pGODMgKfPS77r0/AC1phaqm
232	user232	$2a$06$CkGLiePHez.1BaSPh34mpu4vTCPJnPU9VVQkhamtb4LZedYsPIDl6
233	user233	$2a$06$0xIkgLxii/G1K0TBYrwhWOxK9/Xl8Kr5nrfkiSMJ/YMOOaYBjpz0a
234	user234	$2a$06$htOI66Bhgtxyn4MmR7sT3.UjrXoNiJDf9KVxHxwC5kNFkX5y04wma
235	user235	$2a$06$reMs4mDGyJm2IyKp5Hszlul3uD4RDrJVSYAhPmle0e3d1vwuwLE2m
236	user236	$2a$06$tnvF2jz.tLqPDJ1LqCQF4.Ck3PnK2XhwIyjLqYtoBdsM2I3xoqid6
237	user237	$2a$06$l9l37X9BGkUGAboNMJvkZuKC4FmOPG9CfVd/8U1pYs/3x/PuTd2IK
238	user238	$2a$06$nyprJU2N1nCRyToJiakIUOkgW7U15A29Rhw.58jjDWgaM.wIVfCIm
239	user239	$2a$06$r4VWi07bV7dCwZe1rf5OK.EILtUkuqUE4rrltgxDT.i2ONUYiWPFu
240	user240	$2a$06$oM3ntfUyVgBS5wtu3m4.pebZvzgikzPc5J95P/EWO.GC.JcFLvn2e
241	user241	$2a$06$lgi6pcSQvRtGd6Ao.M81CuoWKPj0JddkzCkgS.8Nq3c.aet/lP5Ou
242	user242	$2a$06$PaMdqmyDxMyExhIH919qyOi591rf1xnHGm4hqr/ljSVdDclLSEVU.
243	user243	$2a$06$6h5/PUKiwB.zjVWGBAhMAOsHFBrJOnXyUWQxYyCIt3HSjedUJlQk.
244	user244	$2a$06$le08WDs4KAqID70vGppBTOZWqYSgSZAOtyU8nS3LUURlC54BCcUaC
245	user245	$2a$06$unuByh50DNt2nZHDlqArV.nYZbvYoOf8xMvRzAPV6MY8bKhEGDCce
246	user246	$2a$06$dyPKTc1jbV6nqEAsovHwfe.PyTrZm.eY6PjfLeeO.VHxsHXL0/bnG
247	user247	$2a$06$kP7dLFcj7rL4MbNYK0/p4.AZTAKcD2WECYfF70znjyZxHMLYvxBjq
248	user248	$2a$06$R7K/I6eYVAiqOQjKYWBXpO7MaWbX9sO69GqsQmlenchxbby5yAAM2
249	user249	$2a$06$y7YeWtVRytUujh5LHfy7AuTKTb5140m6VJnLLlwB2fCVYejt0EM8O
250	user250	$2a$06$In.DETj.2svs9jisY8bIxOpHkv77jNguGGiE8/CnE8NAfr1hFqIF6
251	user251	$2a$06$mK9s.1Jjgh5cNQtO6UYNl.5rUtTNtOBOLGETKC8Gzwr5NapnCzSjS
252	user252	$2a$06$VxsHE8j18VDXJPeIh8YifuTOqn18WoNAcCpgk.ofRZo0C87rcyJdi
253	user253	$2a$06$A0lQABeHFtOYbZ7YcDHiLOTkwBI74KyMGErB9omTNmstUhPcyKdVS
254	user254	$2a$06$viCCMhoBFzUhl7o.qZ5UQOTsa8zijpJUuTar3RokK0GobWDgKyc7a
255	user255	$2a$06$z/U8M7b0IQnRU9l83GmeQOE.lxBQaZJ3hto3iTdOpAuo/cNKY/PCu
256	user256	$2a$06$NL06lhMii7QEhlHgexe2AuwTgUMWDH/ocxcWXj60.Eh96oaws6oIO
257	user257	$2a$06$lQb5x81M/ddBDM7jOsCBAO/7DKhWYt7oHjGjCoTkEUUZjoPr/lASe
258	user258	$2a$06$hzBrEiTClnZvEi.4nKk4F.EGdrXA.VrvkNv5EpBXGmvi.wYjnHl9W
259	user259	$2a$06$JllnfSgEQ0PbZmpQ6RgFS.qi/XJcy8OdvcSqTpWYCiN8GWKanQf7S
260	user260	$2a$06$JNHu5qRjIbHiDS9YCmq2a.ND3ZhaemA8Qsgt4TTSfEBMKXefUo3jq
261	user261	$2a$06$pAttqc8cBi0Et2NuXeY.AOpwz434o.a/8Or1ExEV.hRK0bH7GQ0cS
262	user262	$2a$06$qATL1QXbaRo4/fQXw0snI.Ohc6va6hmgHnvtTEfLitbpTo2MLfSFi
263	user263	$2a$06$BAwJNtud7ElDMh5MvdlBRusrzbrMlyMfV0.pBgoaNqTN7h7OQ5Swi
264	user264	$2a$06$ncn4NoIxPicotxdXQgpIUeA9CPC1fDGXP1BRdmemOceitS/NUmlDi
265	user265	$2a$06$x4vZbUYHTeALP71a9fQVb.6GSv1EzImPAEIXh4NM5dkvcLCgp5Fi2
266	user266	$2a$06$.KvjmyfhDuVbBQLgHbOzOOSzE5a8q5R1z94/CWnAI7YCd4r3MjU3O
267	user267	$2a$06$l70Qy70dbaMJwV.CqhvgN.DwFFjdrHUrj/cYyCrsaRS/nn3ZOV2Va
268	user268	$2a$06$kESlNfUlI5VJ67FMI0ehhuHIge6qJ01gGIiWA5f20SEe.oiX1.xCu
269	user269	$2a$06$l.YaJx34oTspRGXllZZMAukdC5z82EX1HVR32TCu2eD1Yoy7/vaue
270	user270	$2a$06$EDdWlp44cMrXDLgMnZz65eAgsMH2zN5CMRcbTRj2o526m/AzlvfMm
271	user271	$2a$06$hFtQQyynJwAOBxkTKE7BLeKIARiG/lUv5LhZKL9iRnLPOaKyDIH/W
272	user272	$2a$06$/3ShTiObFamVGkFZkkPyDehalJeRFcpo4.v9WAjmkKev3vis.THou
273	user273	$2a$06$cr6FG2puAdHHmjvwaDN2tu.DyDzZKVhaeVQGqit439pl4f1HBpIya
274	user274	$2a$06$q.oTgsJSBG8vJOprQ.0xveJoU3yUq0JBRhVvmBFz7k3lLAcE7zqpK
275	user275	$2a$06$NcQvSfQ.WORB5tY/QuVXjOTYpffBlDyGGw9fuZEeEeAtzDyKwqVxC
276	user276	$2a$06$PLhsdhee8UV5t3fX46WFTuKW0UBRqs3AMDZGYEL7NHzWCmeGy96iK
277	user277	$2a$06$rmCTTMdFwtMFvSUvzenVKeNfAt9vaftcodXvF1cb2oR3xEDaKl076
278	user278	$2a$06$MHajOyygpiQzUUKhxvoEC.6/h14D6Z7AqqcDNmvGx6u40R.PwbR4W
279	user279	$2a$06$zNeNm1ECEL5maX22lHPXQOyxlnNpCh1qCwZS8MDV73IcPpUOYVFYa
280	user280	$2a$06$PRae7FSezalWui0p2A6JF.o1S/AnzU1H/xjJhV2Q8r7VS85nUqXMq
281	user281	$2a$06$O5ovnAMmPQeAAzwpyHKgvuV//ouPQuJzE6EBBxbOGBwu/7AVQjw/i
282	user282	$2a$06$pkJU46OgeIcb3E0AouX9re2FHgrdoh/S9sFUREcUhiKeti3/UALoG
283	user283	$2a$06$b.DR/pYrRDKWlV7oormF6eH9YU8Luz3ZkQPa2jXNPULoMLvJrn7by
284	user284	$2a$06$rYfJpqsyXxBO1TIaxwlMV.VPuNefmzbFol2c0.Rr/kLWhmD0VQHRS
285	user285	$2a$06$fVt5fcexrYFyLGc25MSU1.gSrHPbTbGT6/udGQ4UHbFYwPtrfVa4G
286	user286	$2a$06$XfM2003plpYvo7.jZ7Ja1ORJSGSIyB6PJ4lYUhcMKCp7isE6asodW
287	user287	$2a$06$2z0KCrl0fcLudsw8dXJOu.NQeXCRC3YkUnOv/nqAC8uIXol596eHW
288	user288	$2a$06$kq2Q2ZcvNMsMSc6wjIb8iuXafT52HsdCK90frjI9TJ6.ydi.qt5FK
289	user289	$2a$06$CG37a9Rqqt3BrdGc0HuAtedD2vfuTJkKLryo5ZA8F3AjHj8H.7wau
290	user290	$2a$06$lrSxfVz1pwvHyC87deBSHeHKYGUymUGGRurMiFwR/woSn2RKAZEY2
291	user291	$2a$06$C/eE59oKY4c50Ip5FWFh/etJlAWY7QlxyB4uCR4A95eXMhAMeAVCO
292	user292	$2a$06$F.RGZU92dJlNP9jIxeGmp.1Elqjni/0XanCcw15mqXxNfY3O8HOI2
293	user293	$2a$06$JZwbNuNXg4gZQsh/hnULKujdi4Ir9cqk.DbK7IuTNkBv7KA.mzAsW
294	user294	$2a$06$KWks5b2ku1Gi8d.km70afuvxZVgxuG1fNp7bhMSwEkXruPDj6XXnW
295	user295	$2a$06$JwCG6PbtNuso4XZiep1rK.gwneiv7TKuiTUXdgt/tKiptDIF5MFKq
296	user296	$2a$06$4LJjvDZs8QPEDhwW8OI98OEBbIHwO2N.S4SYQIG.3bKb32rZLgL0O
297	user297	$2a$06$M7WH2NMwxtAEghLujYQomu3iG.2lWy8qFkvGMEBa.uxxn8bBNMY8.
298	user298	$2a$06$V3fS5MCau7iwpzcNMiGNsOn1bg.JBiXYM1BEVkohvPIFoR6vGLX7e
299	user299	$2a$06$jhs4oL5HXFFfdlxHAeclpudxi5hLk3DfiLAeef/Y4cfB1uqWtxO/C
300	user300	$2a$06$roC.87zda3Q9Ay.Y9.fOA.of9Qwagi1QoY3BXqrFjoQiBeqabHgqy
301	user301	$2a$06$V0Mzprnz9BL4wTCHQmChL.AynCnND01OlYg6RTEdBfT6gAlBLlFBq
302	user302	$2a$06$JEwKABUWlsoIV8VAUwzewuEVZbblL6X2Lx8OjOAs1mmSFmABONF5C
303	user303	$2a$06$Gd0Ehtk0RYRXyY4qX6tIvOgMUhFGpkW5XkVXfJWtJzjbjEp6o/7Be
304	user304	$2a$06$RdPZ2uAlS1KeLk1f7Ml.FOTOErAce8iqmSntMBgDG1jTTxhtr/qJu
305	user305	$2a$06$ZEuYLjLMaSy/o1FwwcIZ8u//vSns7gIgkIFPgMPhUzx6y9FfXdtSW
306	user306	$2a$06$92TfLvbnDOzzj5yOY7ajOOZCPhQULDdvxtweznmPbqn26bmbdk.se
307	user307	$2a$06$gyq/HQHDxp.7Ywpf.w3R4uUI03sxZCa.42/eYsRXVGpixkZ3DqNRm
308	user308	$2a$06$IscyXTpRS52mGxrhOk6MKOuJzX/kQoF5gr5zdjt83eQRqvtjezKs2
309	user309	$2a$06$ec61qEMDHP2/3evRON5woOBMDFbSDrZuGU135uHazaLXf9yM11kKS
310	user310	$2a$06$7n5JeedylckQ0O/ICMlhNu6Kw2x0ZqtFkICZ7FbhmJ7VXCakdi3S2
311	user311	$2a$06$g4jmUVYK/3p73ONrOqoqvel22XsLjB.aTGCQSsUM5ZM5Q92RdnKQW
312	user312	$2a$06$wFHjUuGeUObuVQjTpa8u8.Jw2BzqOR9ZqwjztU8ANblpXf89rt7Zy
313	user313	$2a$06$9vie46BR/k5q83rhG9fOuejy/jcCo3CyZ418c1TSoz1QQRgfJ4QlW
314	user314	$2a$06$06i.Zb3QYmxFlCNdV1LCjOeWNtGFV0tXw7A6rvGS2GZCNCVkgcpZm
315	user315	$2a$06$HGEmrhVVU/zclA3t3tlBvO/8gHTYrBC6LW4DPBX.SyezTlRKRCPFy
316	user316	$2a$06$e6A3g4V0Fdv4fCcACHB8qu4R6Xq/97aGNW7.NEXMKKnXeTf7BE1US
317	user317	$2a$06$YrGuJUN5ICLBCK/1W1s.a.mQcMJd0Mn5c2ZXukdMyQ9hIknOmXtvu
318	user318	$2a$06$CTmRjgKMpplPESw/4NvnROnh21kCz6xVI3z3SBJyToDaFfenoZWX.
319	user319	$2a$06$hpae5PYKw3qPbYRmZhWHde4ntUJl4Pn2fxGcOcNSK/Wnc2RaCQ4P.
320	user320	$2a$06$U5iDZXqtzxCEYAuo4LT9q.Eo9zu.6op4r39O6PORIjBKIds4swfaK
321	user321	$2a$06$4l483V.F5UH14GE20/KBi.VR/62t9N3Hfk.R0CFCRe/VG03964Gm2
322	user322	$2a$06$8crCacdjiN4UKZG66r2Y9.tzhIZARMcZy6z9FeBj97q5PQ0v2CrCq
323	user323	$2a$06$cjLgqAp7fXzDXh6WT1nQJOUtmACYqNF8gd/I0blUhjGOKpx1bq40e
324	user324	$2a$06$A1bcHZ//Yb/t5McXCaZGWOgjIaqoERKe76TVz5hC8xtW1bpxZFn.G
325	user325	$2a$06$Z6c8cj.75s0P8LcL5FrP9ehO.0kw7PR6QETvqwj1Uu5WwcCc9jXLW
326	user326	$2a$06$yh7zUg41a6QCpyPic0q8de8h5T.fls.wPatCIifuzTHxSartY7PCK
327	user327	$2a$06$9gzJTdh73YZ2wJSVLTL51e.LPSjdbEoMlJdAQpp9kj6XQvMmJe.tu
328	user328	$2a$06$2Ma.lSStFUVu9BY6pXqEI.akrV4kKUR.Zadl2UuBs/TrQE8XZyn36
329	user329	$2a$06$ZXbYRYFPEZi4pnfcwkldFekc23IXYVg0RRhCg800s6xSlgHmxEM4y
330	user330	$2a$06$MZQMAyP9tVFhwzYkt4oTDe49EgLzi7LgzKIvS.IuNrQuipeiSxWyy
331	user331	$2a$06$jPyc.EhN3b1aPlLzCaWSLeJmc2OHEmqRcMOkWMUA39QV6QfilGTQu
332	user332	$2a$06$x3A.3CK4JAjyQrjXr2bSbuTbYmMz0CbGqbF8dnznqzkVaZ4TU5zEa
333	user333	$2a$06$56FpSNSsAx3aj8BoMIqFNOjpvArSyHpo10FoHDwcKVlp2kWiYvWjW
334	user334	$2a$06$F5Pl5LstcsYz3gT1h/Q3guCh21D1D.ae8aiarUoKuUJ4KgCgFkC.6
335	user335	$2a$06$FZd0q27fUFmCeLAzvlygROYGok7xZ3zzs9nxQ3gEXetifSUITPDFG
336	user336	$2a$06$aSsSX7ykeMa8AhdJZ80bzuKpcMto2OAXx8rMUxiPX4FdKGD7ZUaPO
337	user337	$2a$06$IlfWFHzmNrO7RW881W7NFuhJT83n5eqO2p9yg0R13qatlXqp9FrDa
338	user338	$2a$06$hcGABZLKWG32dcCZ3uiVfu2qFoRvi4CNYbOcb9FfDPMnQugJqAgZi
339	user339	$2a$06$YS6zEHwPl22aWOj7vl7in.F30GZ4NpFfZv.T3WEJLph7h6PpnNUam
340	user340	$2a$06$85KM7bUOxPVHxWSMgnhbk.4FxbjwrtENcOvCDVurtbHacgVgKRGui
341	user341	$2a$06$NJU/H4hetW.Fp3nWVEI11uwsuyE5mGNXP4mCHj3x//CB.PV.9lDXa
342	user342	$2a$06$0ztLtspTA2P.UJF.fFMfy.dPAcd6n7v4gigYBsCF8W1HGfHD02HB6
343	user343	$2a$06$aVbuvWeKyS0Z8BwgbWlR6OB3LXZHkYzI1eNK2Z/Q9PRtsVpF1dx6.
344	user344	$2a$06$4XxSwndB6rLT75N6JXmOq.AfZ7ofzWsTxnrvNoW0UQ7LkwHXTm4ly
345	user345	$2a$06$PS8KmqecW26xhgjsOEzBIuGxRnQxJct3fAJDdfv/d/aiDa76UDYSO
346	user346	$2a$06$w6vTHGCRY.O7KWPBKvcIXO4kBDVii36BXnmL4z2R9MtyBLfqNMPpW
347	user347	$2a$06$fqgCPqGud7FL78Dhdf3RKOslFCKtfPIMJKCfPnNNLJwrvEuPY8F9y
348	user348	$2a$06$V8H8XoEBao8mnHkQHUqcEOcAT8METl4SmRCIyNHoTOKFAsU1jGej.
349	user349	$2a$06$/VyKZqEqrB9i5og6yxLDbuINkQnvVNTjwxzr6JtGbOnd2a6fKQy1C
350	user350	$2a$06$h5OEdZ43xYNHR/Iqhu5NaebiK4nSGClyWpDB.nbDEsm4sK/JiFkS2
351	user351	$2a$06$qhpQY4.1wS7v4AbXHn2XZ.LV9b9B/ivurmo8755ZVJb9t.nUtYPiu
352	user352	$2a$06$HHej.5waMT9pn4RuY.oogegGB.p2sLlLqM3L5qsKQ2SBjkluzuLHS
353	user353	$2a$06$aIe7fmZRuvEs1NV1boEes.xYjUo1YqoSQCxv4.Stcpd4F5EtxdIDS
354	user354	$2a$06$/3a7muq4hkQzhJXQcN8iQeIMsSpQd5CUSBlJYzH8hS/MUNq4vFnzq
355	user355	$2a$06$2fr0nc2uzeFcWv/d0x1UGejZgOyslIGssQxtlrp2HuVXi0paehm2y
356	user356	$2a$06$aCfrWrxUPlhNnPzMCNsLxOsADzIG58txSc.Nife1d7k7DPYlBtNsm
357	user357	$2a$06$6/zp1d74AwMiDxFIoekIrup217mhQktJ2NuJd8nDxfV6Wi8W9OAKy
358	user358	$2a$06$uzbn7RpUiTw34aIox0UIX.2pbAMZZBv82fznHAhz/.a2YOfZyWGq2
359	user359	$2a$06$CgPFXy/k0MEnoVYI5FqR5e4QyVBL9emNn/2pB2HdKdA8gFVl/Qk3K
360	user360	$2a$06$LKCA.DDpJJ/HWHaUKyvB/uW4U6y/6Rv3VZqTKiznjm98Kg3usyEhm
361	user361	$2a$06$1NH3QUHVf0njFcsXfvY8D.epkhm2R8uzDwhhid5i9SQhFwJ2sgT8a
362	user362	$2a$06$33YK80VBNhwa9xmvzGnAqelDU0/2qLnPr6KEBfefghSZgJCeeAsq.
363	user363	$2a$06$Ap/bkh5xd8fcfiUIf1/4TO1mZi5tcfgaX8ss4iiC6g.Da3JrgLZ2q
364	user364	$2a$06$9gPqRQYFY9HEbCsv26gJ7e5Y6m3tTeXRr9QNlSux9MI80f6kSToNG
365	user365	$2a$06$19GKQ45B1TPDWDGj5KkcQeuXXpx8gmpb99E.8RAIrIh1FmQk1yqKq
366	user366	$2a$06$pw2.UaYk4BI8dstvWidI0OGrv9qMKfOnMo1p1RD6pHhYUM7saGLmm
367	user367	$2a$06$BPYqX32E1iEZMwNXdq6wS.f2xfpkVaVqmINldVMMZsbvhrRcO6JIK
368	user368	$2a$06$Q/NG/cFg/RacpUbzD/x.O.95HcjIkH/WhhyxYkNAqSneUrUJQINH6
369	user369	$2a$06$8autYIxxsRpUGrj86KzC4e4nk/dBdcJO2M7gP0QqmWqY2jR5pbJVe
370	user370	$2a$06$WT6/TQK9ZdLyrvxo3fgSEudqI1XM/gSv.ayhvx0kdfg3a4kMjAa1W
371	user371	$2a$06$1d2/Lty7woeW/kXDCNCZkeaR56mwA6qXDfFMy3IGcRk4u4r8Zf3X6
372	user372	$2a$06$91UKTnrnj/qcNC3T5qPMtOMWBE99aR.hwdI0n5LwasBh5YGDVYyd2
373	user373	$2a$06$LBSyB84QtfoBw5GvazHITOSckwj4a/gAMKhXKu0YUf1dHIMHAoDHu
374	user374	$2a$06$90G7Ll7MxVKRgxwZbce.CO80e0uh3/fhZDS6VNaBtomZQBxY8tXOq
375	user375	$2a$06$u8bZx8MnCgEaLExq9iJRTOAINMJI3yW/5wHv8shGFqoNtwQ0O5up.
376	user376	$2a$06$.cAK65GGovGuWF2s7y5jrOfZmNoOEC3b7W6MgPJcpLFc5jax9tF2K
377	user377	$2a$06$3gCg.78lW8hrKho4OybhhujzTrFLRQYO7Jc2AlZg1CvtwasoLTrQ.
378	user378	$2a$06$rqTkVNS5O8qU.Qx6m0aDNOfnRbgEiqfoU4lwowWHLRA4z6JMSL6mW
379	user379	$2a$06$uWm3N18f2FBhVEiJsKaPeuEURawh0Qx/D8Df4ubFnRd6EOZBIc2/G
380	user380	$2a$06$R4k1MIU0VkTpojpRHpjKBuhEpAWIomMk3X1rOz5StMrz0XwywKDaC
381	user381	$2a$06$OZ4MMe74ak/1qCcz/FeHjuI2L.LOF/9gyyFTlB0aTImzMH0Vp.pXm
382	user382	$2a$06$NN7a.q.emU9pJOoR8PLwGer0KzZaUAz1hNMuAR3CwgQKT5A3VCIYS
383	user383	$2a$06$w11PUhWJ8/kXQBpD.41/rO0B8mb3XURyGsjnG6xY5rX2bSW4y4E7C
384	user384	$2a$06$S9kLbfC8hrLU05D8FO1Tq.cDR0uNhNqwIy1hrQCBu1U8Nq3dkDNDG
385	user385	$2a$06$nuh9l9Ve32KIw705N3zcwOI8rz7.LcMbDrXs7mBjd/CLTQ6RPY3mG
386	user386	$2a$06$IaLKXEG7VL7oQMuYbBZSzO.bcQcmRietsiWytvOyJPXnhe4xVRm5.
387	user387	$2a$06$BZm.89GK8leoOUvFCBhFYO.D5QCBduZgzI.Kj6WkJEEsSsMWVLR1.
388	user388	$2a$06$LWiSjTpEgm7HK6yBbe9PO.whpAv4QnoKgVbgKfFRtnmWyzJHNlp5.
389	user389	$2a$06$0E6w6SFZlTiMYcOJjW7DRuF1L4sIZs7q0peLfBUCX04FYqX2ebryy
390	user390	$2a$06$aYKhXgK0CKEoSQAxB0JEdOnaWB3sCZ4BXPrIZXRS5sX3sLqe147S6
391	user391	$2a$06$LEpDkAc0SyBF7r9KtcUWZOBSgJrE8LGq.a7t9oJnjtzNjQoHdzIKa
392	user392	$2a$06$mpZJVZ1IzZOLJLXkg7j0b..8z1Hi.LIIMWGvj3aQrCXBA6t8F30Wy
393	user393	$2a$06$gnzVnNS.JRR/vjAq2Ec7YOT9XtGx3dR2Dt38wVFyvBdydnSg7T7eG
394	user394	$2a$06$dsKqoT1SmTC4wqdiPVhuFu7sEMYedh4u9zyh1/NQZ7.gbpILZBqUS
395	user395	$2a$06$Ov9nTk6YMYyqQ443hZdVveSN6wnFCF/PNRyrZ9DAb4Rd.CMCXP0wi
396	user396	$2a$06$1X3YlD6IIcTPVLR4IaA6SuywJ/1X7vImB4uSe9hx2r6/tGwzjwcAm
397	user397	$2a$06$hncdlbMwENtuujgZBEUM0OprTKgwLE/QWiTRgdkDxRJLHTIQrC8Zi
398	user398	$2a$06$mcm4gkPFogVgZP3xEIm.AeDJRXVpFeE43YC0ZxH1zMgt5j2ueUBhS
399	user399	$2a$06$Krn4qz.HwYmAF59m8ykLVe09fV4um7rSsU3Mh2BC1/u/uzr2T0Wvq
400	user400	$2a$06$V8SfpmZ7c4P5QpocFTlaF.hSYqBm3VPcUdbgK1JanXZVnrUaT6Hde
401	user401	$2a$06$B7ESYzCkRw/J8N2Zt/VxDuV7W7spCpHXUIhYzsDQMk1.LpcqVbw5q
402	user402	$2a$06$lnBo4Kf511Rf1Ez9brY0ReiJ2vCmU4UCFoS7MwYGVPlgt8opQ/hAK
403	user403	$2a$06$ub7l5uxDbEKmkuRywn30uOgnsZlm9YIJlrHADvfvQmxW14vwwV79i
404	user404	$2a$06$Z4hJ67nm7xs6jLvrzA2fgO6R0t35r/0ROZNGb58YTD7NTd7F76X5.
405	user405	$2a$06$D8B14H00IUGziz4dE3q7h..Q9pR..7twvTR/aGhJP94q.T/oEnChu
406	user406	$2a$06$RbuCX/bMx1F2VK..qBQL9.njNPuNTcMbVBCVwQvkIuQ26EWtoFuTi
407	user407	$2a$06$MCFw4TD/W20AyOqjw.TQCeGF1uZ7zaOmqjyyj.NY.r0mvdSrOF8Am
408	user408	$2a$06$MYlwhbNRei8jbnQgA9VcOeaIUrh47KeCbOeVAFY5dkC.BTwXm/UMG
409	user409	$2a$06$Gk/F6lIxfTTcN1.b/exNEOpqNgX7/MBK9BobxrPEs2vuKlYUh.pe2
410	user410	$2a$06$YevOBzlQry6SIe9V3sZwzOHIwOQYA1TBfjP5T33g0D03DBFh5C5o6
411	user411	$2a$06$YaN69cVCGD0TkmYC3jI4j.WzilKZDCR7UemG9RxBLPY5IOaax15VC
412	user412	$2a$06$rLQNosA5bEOPRs1nTmtR1O/dv0T/4kZVLJ8ruhfzPhUx82j8kzywC
413	user413	$2a$06$x5viepF4iop7PLuJLRe0jOlbsdFT3GYzQ539J1yU179j1eauwyv/y
414	user414	$2a$06$Hr29x5/F/T3mAGMN8/gPx.nAuBgRJrYrUKQj.8hfq4gfbiQ1UNf2e
415	user415	$2a$06$inYt8aH4wDDgIywbM5upGeLGRefZBGVa/bdgA87APeLOZAJlYGV8a
416	user416	$2a$06$ufpQPyP9kaiGV6ngy52rEuHUEbeoKRLi2Fq/u5dXKcHUk1DxbleB.
417	user417	$2a$06$rAAw.WuLIOpWQEY90mVnYOYubao294zkW.keKjVahXr6ardKGrKwS
418	user418	$2a$06$OnDGV4Ar6unSb/onBYoftunqHbdePlaSeqQn1xTP6YPodSMsipDGa
419	user419	$2a$06$52VilkFLW0YJtqpw0mQUPOKS61AWzmQ6rmfESfg1a7qSoHkvl.HKu
420	user420	$2a$06$0HGJo5.NJ/vrz6C0d3W0jOMonZ6zc6iusdXzCzGVlnWbFt7zeJCje
421	user421	$2a$06$XxDRMXkCUpZM4XpWdA1xRuL0ApAwYzuEZIXBgwh.qGk.n.HMTm/62
422	user422	$2a$06$go0uBzkS34PrUIbASCGkk.2i/0YDKYbCcJ0a1q2ajb5TdIfT6huRa
423	user423	$2a$06$xO2siZYMsivgXoJ.byqx9eMjxPtGR8S9C8VU1sSDPVSsNiyhegAb.
424	user424	$2a$06$cBbfli3TmjaK2yJAKUnjZ.qNuekafhmFydUNj0.Utt3v4XGAgE8F.
425	user425	$2a$06$EJcnQVa9UIrS3Y7b4iBoQeN6WMuX8U2hUVScvM/hM0t3I58rB6//W
426	user426	$2a$06$enp5LdCRsLZ4tKath6N2.ONYTPxEbmvrW7jzFrjkMWsB6NUj0RKVa
427	user427	$2a$06$aJJa9sWhtMbxrbg9vbn7KeKVK0lktOzHHwYTFj0KriJiO3BYEUdSa
428	user428	$2a$06$2E78x8kd3oxloj2YZx1bR.13hesGuRUPpWkUUxh.gh6V3g.Jr5ZB2
429	user429	$2a$06$XJF3hWhXHL02LU8ptbs.FOYagOg4a4.xo8ZKQOXBzeO8xJcrSta32
430	user430	$2a$06$6/pYuAs8CIVaF26/8Dl/i.0q.VST2UAInR10PiHH1BlNQR.l/ChDK
431	user431	$2a$06$t33myLzonRBoYamfHw9EXu4Twp4sPfn04KzsCdxU.nFo95Glf/2Zy
432	user432	$2a$06$BlrpJrFlpVlDg6.WZjEy/u5IJGaMr6B1lxiwvLMzNICd2f5mLVtXC
433	user433	$2a$06$GnWlpzh3AjLnW6t9Y/x.ZesCsvCYf5P7iu1XdhN1LwfDiqvPlIYRe
434	user434	$2a$06$T5JL3s75XLyqTRpFClTk9eLT1AygdVxQugkTigbITuNnhnSKJCmQ6
435	user435	$2a$06$BPJ2/Mhil2IuNVPqatBX9O3GoQZxCfYifetrsoB/S75lE9gTwUF8W
436	user436	$2a$06$XXTCZvjUTRRuTv5qT.6NTeR8pTvvq0Ex3HYuuqCmV0NOuF45HHPju
437	user437	$2a$06$sx.0Q0y89BxIuygEJigFaOvMhLtfoJuhj8G8EeHPiJ9pUMqYtmpvq
438	user438	$2a$06$9Op.UtvWDth4j09CJYSeHOKy.m8Xgo8zT0NbV75846rIhjEROK2j6
439	user439	$2a$06$L85VYHcCtMohmFjVu3tb4.Npd71l.lIJR3u6cG1gvJMNp5LLMS39.
440	user440	$2a$06$dFfrhzsl9EkhA68a8C9nnuYFRPxrI0DiKX.Gm2wc5wLa4b82i6T8W
441	user441	$2a$06$Kjf74ZpQNpylYfJ59KmfDuoekrOdLOmAqVieLCEByyZpvlLONAUw.
442	user442	$2a$06$QXHSXwwQ8nQ8enm2qLcnwuBQSFWpY/UB3b.Dh/vv51X8atQD2LTha
443	user443	$2a$06$SkgQx8HnXXP6VjG51rRY.umkX63Pn4E/9FFMjjUG.rQPMfCrWLiby
444	user444	$2a$06$k8GOWfr7.HoxdhA3qG9aYeus2EOq8iWytNcEPcArZ8.NKTU6qbuHW
445	user445	$2a$06$Uo0yQCtiAOstChB1wMuHoON.CFEKZQeOddgfnuYcs89P9OIZqflhi
446	user446	$2a$06$sfGf0.bsltjY9jbbod6WV.rZEKGUrOC2aLFWfmLNNtRLmxsCs/UQG
447	user447	$2a$06$NcGjPk7VM0CyFdjso0r6gOZimvBQaNUYbn34LS57E2eTK6jj7UAde
448	user448	$2a$06$El4iV2oHGqviLFHKGoNVb.MLZOZwRBu1HNTIIQ/HKK0TstYeHbszO
449	user449	$2a$06$Gsb.hKVn0FcfkNSToW/hzuyyI/rVwZgC4BjO34uOOIuefC7dP2h5y
450	user450	$2a$06$XH1NyhCr1t0r2Qm/cRedWu5kIljlSjLDjFmRaxb6uEYEhjAdfkjQa
451	user451	$2a$06$wh1XtywaNJ/he8E4wvXdmumYG1dytGqcVGONuTpHvOdIQP2ZMzf2u
452	user452	$2a$06$4UkcxT2y42Bu0XqXi2go3uTcWK4kD7Kz9em8ouFvrUx4LH24cJwsq
453	user453	$2a$06$.xazHleSJDVUngPWLHnMJuFAdS2lmRFftvIoKJMHAyh6P9.0UNpVy
454	user454	$2a$06$bYprB1D0IAJWLX704aXyEeqBsevrUn83j6MvEbHOYbkHeNDk4ygni
455	user455	$2a$06$D/exbcntYKt7ulKNiDDmzu4K8carbyFAdtWnDssFG/7swqSVYW8bi
456	user456	$2a$06$mijiemu/YZzx3HJYgeVKx.Exfqx/K9CQ5sCZ8nqeSfri3JUibc70C
457	user457	$2a$06$c72XHJ9Nb8dvu8tLLk6lA.QX1uTXtn.mJFw2ttzo5rEG4eIugxV2i
458	user458	$2a$06$M0PopXstzZvs.nEbQwKWeuAlPlrVdTKe4KGilVaWVmT.D4R1Xx3ie
459	user459	$2a$06$tfzLQlFZaFqq4KqoqwRaOOUO3.C/6NuHVJwH3q5lJ8yvbOLS0SLkO
460	user460	$2a$06$6Is6LdPm.yGdJkPm3zpQKuz4FF897Lu/DRsIQKajBl3xLZt6/sfRm
461	user461	$2a$06$BUTjvtahwTddVYNe0aTRjeWGLSK2b7Qw9O1WOb7OlymtEa.81z5rq
462	user462	$2a$06$f5vl8CHkTsDOZP00sFNFpuscElIi21NehTFG3S977gnR5UUlBiZf2
463	user463	$2a$06$EHnqlzbo6xntr5RQKBSdr.fURBapCRYIUlcMfDtjSK4dMucGv14zO
464	user464	$2a$06$5HLPhmXNFjSy8CkhLWkIsOjMFfQM9Fy9Iq6wteA0C1IbSB1rS4ihW
465	user465	$2a$06$nFGC5r46fAKYixBl7iZj7.h6.0gcMRddu8Agzoufzc5UaFK898VWe
466	user466	$2a$06$IRCzf1eujGaDt6h1ZatP0uppftkCYWD0yLy6rQ58sCwKYBjqbbcMC
467	user467	$2a$06$jI3fmrVUNBmVjvmD3rwdHucFH2urrkyH8SJM/M.jHBBbKpj8yaB.y
468	user468	$2a$06$I63Ga.4Bk0ZeNobnydBH3.MYC7O4Ua/OCYaFFC1v1V8WDYMfnlhzG
469	user469	$2a$06$z5XY83pAQCsx9.y7VNNYSe1.N0l.N8M/PHM3qZzo6jvCmm9CzT136
470	user470	$2a$06$LCiIoC5Tyqyo7tvbAbF3ze4NqHlRL.tITAGZmgelyMHF63HILeXRa
471	user471	$2a$06$8ny9RgA89UQJWj5q5Hkua.sdIvwd1Rly8JD.F5VtrU48P7z9c7yCa
472	user472	$2a$06$tY5E7EjTjSslgvtG04VkOexLDgKdH1mk39Lmh7wC9.baxJlu/DBVu
473	user473	$2a$06$EJ.FLRQCrurzYRPDIkv5cu482O.KaDUANy1oHP8DKtMt4aahhcJCC
474	user474	$2a$06$F1ASEeTswa/jb1wJNY3RU.5tVPEKXLXBHjec4k6AS4JnArsWkwibi
475	user475	$2a$06$tk4bLy6MsGfdm6Xj8Yixv.1Xm7CjSwYZ8LhehAytgAqDapLOKtj/e
476	user476	$2a$06$Js7QaiXrN/CEz/sKybSJF.HsUqEFoSrUNY3pIUzjkVn2NykFa69Ci
477	user477	$2a$06$tRN73B6t1lesfv6VIVSx2.sepW6OC7bFiY0QQFV9YpCDLgz7d1XMu
478	user478	$2a$06$DvLWRCMRaQhk//dNcHUNBeZkdf5A21DkWYDSNuFEJSH.zwVVLEZqu
479	user479	$2a$06$GAzH6xmNJSKRUgg95X2wduO3Y6VX2sBti9ifO/8fL32EdmWzQrFOu
480	user480	$2a$06$43CuhYKyqvQmlNmSR4NdX.OihJVts/suIRto3o8lZd1yV6AogEzSm
481	user481	$2a$06$zohr9FHwKOdgaBkXBznCaebh57knjT7m7cvCEmdOre6aL9myayg6C
482	user482	$2a$06$EMC8Uk9fcUic6tNJrVZGSuwV.1rkF3FB4YnG.FSs.AX3D.KtyUxse
483	user483	$2a$06$yOw4ejmxJ7kSaMp3a.DWZuu1Mrstf6ADeYbU4yvJNb2e07mqlXQlK
484	user484	$2a$06$XFIw1USTNvP.t2i4mxCs2.4WpGNaPpwKoPeKtX7kWDqbwyhXjnQF2
485	user485	$2a$06$3fC9fM50eWPk62LTCfc.2OO5VjajNj8hmajonHlU2FmvColoolVAK
486	user486	$2a$06$lhyQHC7UMEDlYIPvuOzah.xyI/I/vu1mTfjmhxnT8dsHlcUcfevgy
487	user487	$2a$06$erL2XezV6zrUuv3.LTHoPOEUTU1qCQGwWDrn9vs6N5lWS3CoQ8Dxy
488	user488	$2a$06$MHBtBz6mWFUXM6MXrRoLF.9dZ9l15jxEBi/0/dPrtRlq.pkg6QCSm
489	user489	$2a$06$fVBWnbGPB0kY/75si9/TI.9qzEg.lcQELOO9cEMaY4VHILQoINDUu
490	user490	$2a$06$NEWVkNczDLiyxm1XTN4u0OyQQxHWnTTd7RddJj9Q0SwMEOAVEOJZC
491	user491	$2a$06$w2cg52tYAayrfPQF33iahOgjguhrMONQ/nqmDrHP/3979L4PD9Gtm
492	user492	$2a$06$vc14X3mun7edVy69zsCZnuQMonviN/GHbxxuatlOTUnG/Pfup0d9e
493	user493	$2a$06$UOr4uAF/UjvHsVYY.3/1o.ua7F.Jd8BPEvtGmgb8P3pg5szYS1QbO
494	user494	$2a$06$WrpBJHiIodo42uSi.JfmmuuKydqi0ypE3tcU8hYi0A.tEYgrxrE/a
495	user495	$2a$06$1NZZJig8NlTqbWL06oUSd.wvbtt4VV2fjO8i3.77jNpJtv7zcFTs6
496	user496	$2a$06$nHQHAhMWVUF.ACJoyTig8OSSnf.0o608sgS7EI4qexu1XdToYrOLq
497	user497	$2a$06$56fpYhkGtua5I5UHWxaeMeSzWYY.7bAR7VBhEkuDqrxza.WzDEUpa
498	user498	$2a$06$AxeP2LiHwQvJiSu69P/u6eClnYAgjgy0sUYy5hPEqUOBTcpuWnCHS
499	user499	$2a$06$AEuGGnR5ipHZbJwshyNfZuGxIluII5FyriQAGyi93b/nz7dPmHAOW
500	user500	$2a$06$qpCjKF4leTcatACXUD9/bO7qqLcEiDxZSQRBRTMEi418jksPI0QTK
\.


--
-- Data for Name: administrators; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.administrators (user_id, office_id) FROM stdin;
359	73
145	1174
67	529
288	474
3	1185
138	869
107	291
195	1062
60	720
484	545
235	1222
363	261
437	916
102	1182
27	1103
365	293
468	902
76	898
126	578
405	495
38	58
478	56
217	735
80	852
336	1188
310	604
305	521
289	499
114	637
16	128
266	457
211	66
130	2
46	1091
88	452
157	393
37	601
160	751
85	564
40	282
155	364
344	227
381	888
219	465
427	819
313	194
215	837
248	390
367	221
444	814
73	926
9	722
41	1167
460	776
33	147
108	1154
459	16
318	402
111	226
162	1249
324	37
269	1129
382	19
8	1119
152	1239
190	199
321	299
23	1017
350	217
260	193
113	472
317	408
91	774
96	196
87	432
179	70
392	103
61	556
90	213
52	877
320	483
267	723
7	544
176	297
243	277
497	789
244	657
395	35
24	603
446	1238
115	636
2	796
56	301
473	36
301	1071
137	161
192	573
328	984
197	623
306	1186
475	1157
188	581
414	1200
424	476
208	38
455	790
184	906
272	1160
387	401
15	136
312	540
385	627
\.


--
-- Data for Name: birth_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.birth_certificates (id, father, mother, person, issuer, country_of_birth, city_of_birth, issue_date) FROM stdin;
1	2	3	1	679	Nicaragua	Chinandega	1990-09-11
2	4	5	2	221	Liechtenstein	Vaduz	1965-02-08
3	6	7	3	1221	Albania	Elbasan	1965-04-11
4	8	9	4	633	Russia	Kaspiysk	1940-08-01
5	10	11	5	977	Palau	Melekeok	1940-03-25
6	12	13	6	538	Belarus	Pastavy	1940-04-15
7	14	15	7	1095	Mayotte	Dzaoudzi	1940-12-01
8	16	17	8	708	Bahamas	Freeport	1915-01-18
9	18	19	9	6	Madagascar	Antsohimbondrona	1915-01-28
10	20	21	10	1164	Swaziland	Lobamba	1915-09-09
11	22	23	11	1239	Jordan	Mafraq	1915-05-09
12	24	25	12	824	Senegal	Bignona	1915-12-25
13	26	27	13	420	Honduras	Potrerillos	1915-01-26
14	28	29	14	301	Cambodia	Sihanoukville	1915-04-02
15	30	31	15	789	Bhutan	Tsirang	1915-09-04
16	32	33	16	448	Belgium	Zaventem	1890-09-11
17	34	35	17	1070	Burundi	Bururi	1890-07-08
18	36	37	18	721	Curacao	Willemstad	1890-03-02
19	38	39	19	53	Iraq	Baghdad	1890-08-21
20	40	41	20	43	Finland	Lieto	1890-09-06
21	42	43	21	1126	Egypt	Toukh	1890-05-26
22	44	45	22	668	Nauru	Yaren	1890-10-13
23	46	47	23	836	Mauritania	Atar	1890-12-04
24	48	49	24	260	Monaco	Monaco	1890-03-09
25	50	51	25	1233	Azerbaijan	Yelenendorf	1890-02-10
26	52	53	26	563	Suriname	Lelydorp	1890-10-11
27	54	55	27	527	Malaysia	Simanggang	1890-09-14
28	56	57	28	283	Malaysia	Kulim	1890-12-21
29	58	59	29	988	Slovakia	Bardejov	1890-09-06
30	60	61	30	422	Ukraine	Piatykhatky	1890-04-16
31	62	63	31	243	Armenia	Hrazdan	1890-12-24
32	64	65	32	561	Uganda	Kabale	1865-03-17
33	66	67	33	285	Barbados	Bridgetown	1865-01-13
34	68	69	34	300	Laos	Phonsavan	1865-09-03
35	70	71	35	1046	Latvia	Valmiera	1865-04-26
36	72	73	36	1170	Maldives	Male	1865-11-11
37	74	75	37	217	Honduras	Tegucigalpa	1865-06-24
38	76	77	38	710	Israel	Ofaqim	1865-02-03
39	78	79	39	94	Bermuda	Hamilton	1865-09-19
40	80	81	40	1228	Burundi	Kayanza	1865-12-05
41	82	83	41	584	Panama	Chepo	1865-07-04
42	84	85	42	1094	Guyana	Linden	1865-11-08
43	86	87	43	662	Ecuador	Montalvo	1865-05-24
44	88	89	44	85	Moldova	Ungheni	1865-07-19
45	90	91	45	962	Bolivia	Trinidad	1865-09-15
46	92	93	46	26	Dominica	Roseau	1865-08-06
47	94	95	47	1218	Tajikistan	Norak	1865-07-01
48	96	97	48	398	Niger	Mayahi	1865-07-25
49	98	99	49	598	Moldova	Ungheni	1865-10-07
50	100	101	50	569	Afghanistan	Kabul	1865-11-20
51	102	103	51	1119	Tunisia	Monastir	1865-07-25
52	104	105	52	741	Georgia	Khashuri	1865-06-09
53	106	107	53	651	Pakistan	Kunri	1865-05-15
54	108	109	54	435	Brunei	Seria	1865-11-10
55	110	111	55	348	Germany	Oranienburg	1865-02-25
56	112	113	56	1001	Croatia	Zadar	1865-11-20
57	114	115	57	465	Belarus	Mazyr	1865-08-23
58	116	117	58	730	Jordan	Russeifa	1865-08-26
59	118	119	59	590	Pakistan	Digri	1865-12-01
60	120	121	60	361	Kiribati	Tarawa	1865-07-22
61	122	123	61	495	Mongolia	Hovd	1865-06-25
62	124	125	62	169	Macao	Macau	1865-04-27
63	126	127	63	279	Cameroon	Penja	1865-12-03
64	128	129	64	466	Mozambique	Macia	1840-05-09
65	130	131	65	726	Poland	Jawor	1840-07-01
66	132	133	66	840	Kazakhstan	Saryaghash	1840-04-02
67	134	135	67	751	Russia	Kovdor	1840-04-06
68	136	137	68	211	Singapore	Singapore	1840-12-12
69	138	139	69	813	Belize	Belmopan	1840-10-05
70	140	141	70	791	Panama	Pedregal	1840-02-07
71	142	143	71	1091	Honduras	Juticalpa	1840-05-26
72	144	145	72	603	Somalia	Afgooye	1840-05-19
73	146	147	73	29	Benin	Ouidah	1840-04-02
74	148	149	74	1099	Mauritania	Atar	1840-04-23
75	150	151	75	323	Chile	Arauco	1840-09-18
76	152	153	76	1194	Qatar	Doha	1840-05-10
77	154	155	77	1186	Azerbaijan	Baku	1840-01-06
78	156	157	78	448	Pakistan	Loralai	1840-01-27
79	158	159	79	42	Ethiopia	Mekele	1840-01-02
80	160	161	80	740	Malaysia	Miri	1840-04-06
81	162	163	81	866	Colombia	Lorica	1840-06-12
82	164	165	82	922	Niue	Alofi	1840-02-21
83	166	167	83	1000	Egypt	Zagazig	1840-04-26
84	168	169	84	578	China	Gushu	1840-11-09
85	170	171	85	232	Finland	Pirkkala	1840-03-27
86	172	173	86	454	Kazakhstan	Astana	1840-06-07
87	174	175	87	1177	Ghana	Achiaman	1840-02-27
88	176	177	88	374	Tanzania	Mugumu	1840-06-07
89	178	179	89	780	Niger	Tessaoua	1840-09-21
90	180	181	90	1096	Kyrgyzstan	Isfana	1840-09-02
91	182	183	91	754	Ireland	Dublin	1840-07-06
92	184	185	92	258	Germany	Holzwickede	1840-12-11
93	186	187	93	693	Taiwan	Lugu	1840-12-23
402	\N	\N	402	562	Haiti	Carrefour	1790-04-08
94	188	189	94	368	Japan	Shiroishi	1840-08-10
95	190	191	95	577	Tunisia	Akouda	1840-03-26
96	192	193	96	17	Burundi	Ruyigi	1840-08-07
97	194	195	97	1189	Ireland	Luimneach	1840-06-25
98	196	197	98	633	Kazakhstan	Abay	1840-07-19
99	198	199	99	420	Mexico	Huatabampo	1840-02-04
100	200	201	100	974	Niger	Agadez	1840-07-16
101	202	203	101	664	Guatemala	Chinautla	1840-02-19
102	204	205	102	398	Armenia	Ejmiatsin	1840-01-23
103	206	207	103	1217	Singapore	Singapore	1840-02-02
104	208	209	104	799	Bangladesh	Narsingdi	1840-09-11
105	210	211	105	639	Jamaica	Portmore	1840-10-11
106	212	213	106	610	Jamaica	Mandeville	1840-08-25
107	214	215	107	203	Guinea	Camayenne	1840-07-18
108	216	217	108	392	Guatemala	Tiquisate	1840-04-14
109	218	219	109	518	Spain	Alicante	1840-02-03
110	220	221	110	27	Italy	Siena	1840-09-03
111	222	223	111	58	Iraq	Kufa	1840-08-07
112	224	225	112	692	Greenland	Nuuk	1840-07-09
113	226	227	113	662	Tunisia	Monastir	1840-07-09
114	228	229	114	136	Burundi	Rutana	1840-04-23
115	230	231	115	888	Curacao	Willemstad	1840-03-24
116	232	233	116	442	Pitcairn	Adamstown	1840-10-16
117	234	235	117	885	Niger	Dogondoutchi	1840-12-04
118	236	237	118	296	Honduras	Tegucigalpa	1840-06-08
119	238	239	119	538	Moldova	Soroca	1840-02-15
120	240	241	120	696	Barbados	Bridgetown	1840-09-11
121	242	243	121	933	Iceland	Akureyri	1840-09-22
122	244	245	122	859	Italy	Monterotondo	1840-02-22
123	246	247	123	1143	Lesotho	Quthing	1840-05-15
124	248	249	124	577	Colombia	Aguazul	1840-04-22
125	250	251	125	874	Laos	Vientiane	1840-06-06
126	252	253	126	656	Monaco	Monaco	1840-12-04
127	254	255	127	995	Burundi	Muyinga	1840-11-21
128	256	257	128	694	Niger	Matamey	1815-11-08
129	258	259	129	160	Togo	Kara	1815-05-09
130	260	261	130	1234	Gabon	Franceville	1815-09-07
131	262	263	131	1230	Tuvalu	Funafuti	1815-01-07
132	264	265	132	165	Thailand	Ratchaburi	1815-01-28
133	266	267	133	355	Nigeria	Gummi	1815-02-04
134	268	269	134	319	Pitcairn	Adamstown	1815-11-02
135	270	271	135	396	Togo	Bassar	1815-09-27
136	272	273	136	839	Uruguay	Florida	1815-03-20
137	274	275	137	243	Ireland	Kilkenny	1815-09-06
138	276	277	138	915	Kenya	Molo	1815-09-22
139	278	279	139	259	France	Toulouse	1815-12-20
140	280	281	140	1117	Rwanda	Gisenyi	1815-08-23
141	282	283	141	667	Angola	Cuito	1815-02-12
142	284	285	142	757	Argentina	Coronda	1815-01-15
143	286	287	143	790	Mauritius	Curepipe	1815-03-11
144	288	289	144	649	Denmark	Nyborg	1815-09-06
145	290	291	145	112	Benin	Parakou	1815-05-13
146	292	293	146	493	China	Guixi	1815-07-28
147	294	295	147	719	Djibouti	Obock	1815-11-12
148	296	297	148	813	Lebanon	Tyre	1815-04-25
149	298	299	149	146	Pakistan	Mailsi	1815-11-12
150	300	301	150	670	Uganda	Paidha	1815-01-21
151	302	303	151	1052	Azerbaijan	Mingelchaur	1815-07-05
152	304	305	152	1125	Kyrgyzstan	Kant	1815-12-28
153	306	307	153	1080	Greenland	Nuuk	1815-04-25
154	308	309	154	859	Brazil	Ipubi	1815-11-26
155	310	311	155	229	Madagascar	Ambarakaraka	1815-06-07
156	312	313	156	611	Gambia	Farafenni	1815-09-07
157	314	315	157	845	Tuvalu	Funafuti	1815-11-26
158	316	317	158	717	Pakistan	Johi	1815-06-17
159	318	319	159	942	Japan	Okunoya	1815-08-20
160	320	321	160	480	Libya	Ghat	1815-02-24
161	322	323	161	660	Finland	Haukipudas	1815-04-21
162	324	325	162	1140	Pakistan	Gwadar	1815-01-24
163	326	327	163	1105	Japan	Kanoya	1815-09-22
164	328	329	164	708	Vietnam	Hanoi	1815-04-22
165	330	331	165	627	Mozambique	Manjacaze	1815-03-20
166	332	333	166	557	Mongolia	Uliastay	1815-10-18
167	334	335	167	1126	Latvia	Valmiera	1815-01-03
168	336	337	168	965	Belgium	Geraardsbergen	1815-06-17
169	338	339	169	800	Venezuela	Charallave	1815-05-22
170	340	341	170	415	Myanmar	Yangon	1815-04-16
171	342	343	171	734	Morocco	Guercif	1815-02-15
172	344	345	172	976	Benin	Banikoara	1815-04-19
173	346	347	173	1015	Ecuador	Cuenca	1815-12-23
174	348	349	174	983	Argentina	Dolores	1815-01-21
175	350	351	175	104	Dominica	Roseau	1815-04-10
176	352	353	176	181	Monaco	Monaco	1815-07-19
177	354	355	177	450	Jordan	Amman	1815-10-22
178	356	357	178	430	Poland	Police	1815-07-09
179	358	359	179	917	Canada	Cambridge	1815-03-25
180	360	361	180	11	Greece	Vrilissia	1815-02-20
181	362	363	181	757	Japan	Wakuya	1815-06-19
182	364	365	182	828	Angola	Lucapa	1815-01-01
183	366	367	183	369	Macedonia	Kamenjane	1815-07-16
184	368	369	184	505	Vietnam	Hanoi	1815-12-06
185	370	371	185	1209	Cambodia	Kampot	1815-12-12
186	372	373	186	272	France	Montivilliers	1815-02-01
187	374	375	187	633	Indonesia	Abepura	1815-10-13
188	376	377	188	469	Chile	Cabrero	1815-02-07
189	378	379	189	325	Algeria	Cheraga	1815-02-26
190	380	381	190	234	Bahamas	Freeport	1815-07-15
191	382	383	191	679	Tuvalu	Funafuti	1815-01-12
192	384	385	192	562	Namibia	Grootfontein	1815-06-17
193	386	387	193	1108	Tanzania	Kidodi	1815-01-27
194	388	389	194	590	Turkey	Fethiye	1815-05-17
195	390	391	195	969	Kiribati	Tarawa	1815-06-13
196	392	393	196	944	Malaysia	Ipoh	1815-02-18
197	394	395	197	234	Australia	Randwick	1815-11-18
198	396	397	198	1225	Libya	Mizdah	1815-09-14
199	398	399	199	115	Nigeria	Okigwe	1815-07-28
200	400	401	200	378	Belize	Belmopan	1815-09-17
201	402	403	201	135	Australia	Langwarrin	1815-09-02
202	404	405	202	138	Zimbabwe	Gweru	1815-06-15
203	406	407	203	258	Monaco	Monaco	1815-06-20
204	408	409	204	763	Tajikistan	Khorugh	1815-10-21
205	410	411	205	1003	Chad	Benoy	1815-08-19
206	412	413	206	1240	Ireland	Lucan	1815-04-23
207	414	415	207	481	Uzbekistan	Payshanba	1815-07-22
208	416	417	208	584	Bahrain	Sitrah	1815-04-01
209	418	419	209	1225	Guyana	Georgetown	1815-08-20
210	420	421	210	547	China	Yanjiang	1815-12-24
211	422	423	211	81	Greenland	Nuuk	1815-10-12
212	424	425	212	1233	Gibraltar	Gibraltar	1815-12-09
213	426	427	213	451	Tuvalu	Funafuti	1815-09-02
214	428	429	214	1018	Indonesia	Boyolangu	1815-10-21
215	430	431	215	449	Lebanon	Baalbek	1815-02-17
216	432	433	216	338	Guyana	Linden	1815-10-01
217	434	435	217	864	Belarus	Dzyarzhynsk	1815-12-18
218	436	437	218	384	Nicaragua	Managua	1815-10-07
219	438	439	219	265	Nauru	Yaren	1815-05-03
220	440	441	220	648	Vietnam	Vinh	1815-08-05
221	442	443	221	332	Norway	Kristiansand	1815-09-03
222	444	445	222	1052	Argentina	Fontana	1815-06-12
223	446	447	223	687	Myanmar	Syriam	1815-11-12
224	448	449	224	526	Albania	Tirana	1815-09-10
225	450	451	225	680	Burundi	Kayanza	1815-01-04
226	452	453	226	1144	Guatemala	Cuilapa	1815-09-01
227	454	455	227	1047	Iran	Qeshm	1815-09-11
228	456	457	228	111	Botswana	Janeng	1815-02-01
229	458	459	229	301	Cyprus	Protaras	1815-05-21
230	460	461	230	92	Italy	Triggiano	1815-07-11
231	462	463	231	1047	Lithuania	Taurage	1815-10-17
232	464	465	232	94	Greece	Athens	1815-10-04
233	466	467	233	1046	Mexico	Salamanca	1815-05-06
234	468	469	234	1119	Cuba	Florencia	1815-04-16
235	470	471	235	985	Belarus	Kobryn	1815-01-11
236	472	473	236	277	Ethiopia	Sebeta	1815-12-26
237	474	475	237	1166	Montserrat	Plymouth	1815-02-04
238	476	477	238	437	Bulgaria	Plovdiv	1815-08-20
239	478	479	239	663	Peru	Chulucanas	1815-04-17
240	480	481	240	1158	Uruguay	Dolores	1815-08-09
241	482	483	241	1196	Jordan	Mafraq	1815-06-11
242	484	485	242	961	Denmark	Viborg	1815-10-06
243	486	487	243	967	Switzerland	Zug	1815-08-06
244	488	489	244	845	Kenya	Nairobi	1815-08-01
245	490	491	245	915	Curacao	Willemstad	1815-03-02
246	492	493	246	901	Comoros	Moutsamoudou	1815-02-20
247	494	495	247	787	Slovenia	Ptuj	1815-12-05
248	496	497	248	89	Tanzania	Tanga	1815-03-14
249	498	499	249	12	Chad	Massakory	1815-08-12
250	500	\N	250	463	Albania	Elbasan	1815-04-06
251	\N	\N	251	335	Kenya	Eldoret	1815-12-07
252	\N	\N	252	662	Serbia	Valjevo	1815-11-24
253	\N	\N	253	814	Dominica	Roseau	1815-10-07
254	\N	\N	254	206	Niger	Magaria	1815-05-14
255	\N	\N	255	313	Austria	Linz	1815-12-10
256	\N	\N	256	1234	Bermuda	Hamilton	1790-12-17
257	\N	\N	257	639	Austria	Klosterneuburg	1790-08-03
258	\N	\N	258	538	Israel	Netivot	1790-11-28
259	\N	\N	259	191	Taiwan	Banqiao	1790-08-08
260	\N	\N	260	611	Swaziland	Lobamba	1790-04-03
261	\N	\N	261	492	Mauritania	Kiffa	1790-05-10
262	\N	\N	262	794	Ghana	Nkawkaw	1790-07-10
263	\N	\N	263	1174	Sweden	Kristianstad	1790-07-14
264	\N	\N	264	60	Pakistan	Taunsa	1790-02-09
265	\N	\N	265	765	Iceland	Akureyri	1790-08-12
266	\N	\N	266	692	Gambia	Bakau	1790-07-22
267	\N	\N	267	309	Kenya	Voi	1790-03-19
268	\N	\N	268	1170	Cameroon	Tonga	1790-06-15
269	\N	\N	269	441	Bhutan	Thimphu	1790-04-11
270	\N	\N	270	833	Ecuador	Riobamba	1790-05-10
271	\N	\N	271	1110	Afghanistan	Ghormach	1790-12-26
272	\N	\N	272	521	Mexico	Cardenas	1790-06-07
273	\N	\N	273	350	Yemen	Aden	1790-02-24
274	\N	\N	274	447	Niue	Alofi	1790-02-06
275	\N	\N	275	422	Malaysia	Ranau	1790-08-17
276	\N	\N	276	659	Malaysia	Tampin	1790-10-23
277	\N	\N	277	132	Guinea	Kissidougou	1790-07-11
278	\N	\N	278	1076	Moldova	Cahul	1790-11-25
279	\N	\N	279	124	Taiwan	Keelung	1790-12-19
280	\N	\N	280	203	Thailand	Trat	1790-01-04
281	\N	\N	281	72	Malawi	Lilongwe	1790-01-18
282	\N	\N	282	324	China	Taozhuang	1790-08-22
283	\N	\N	283	350	Kiribati	Tarawa	1790-01-07
284	\N	\N	284	217	Mali	Sagalo	1790-04-24
285	\N	\N	285	165	Greenland	Nuuk	1790-06-10
286	\N	\N	286	477	Brazil	Oliveira	1790-08-19
287	\N	\N	287	1111	India	Aruppukkottai	1790-12-02
288	\N	\N	288	1119	Afghanistan	Taloqan	1790-10-09
289	\N	\N	289	901	Kenya	Muhoroni	1790-08-13
290	\N	\N	290	704	Nicaragua	Bluefields	1790-06-25
291	\N	\N	291	597	Somalia	Beledweyne	1790-11-07
292	\N	\N	292	877	Madagascar	Faratsiho	1790-09-15
293	\N	\N	293	1097	Latvia	Tukums	1790-07-16
294	\N	\N	294	43	Bahrain	Manama	1790-05-19
295	\N	\N	295	54	Gambia	Sukuta	1790-07-20
296	\N	\N	296	716	Angola	Menongue	1790-02-12
297	\N	\N	297	68	China	Taizhou	1790-01-19
298	\N	\N	298	915	Tanzania	Mugumu	1790-02-06
299	\N	\N	299	480	Austria	Wolfsberg	1790-06-05
300	\N	\N	300	1023	Iran	Sirjan	1790-06-28
301	\N	\N	301	851	Zimbabwe	Shurugwi	1790-03-10
302	\N	\N	302	955	Hungary	Szolnok	1790-04-02
303	\N	\N	303	1164	Guatemala	Mazatenango	1790-12-12
304	\N	\N	304	272	Kenya	Kilifi	1790-04-26
305	\N	\N	305	3	Lebanon	Beirut	1790-09-28
306	\N	\N	306	1150	Nigeria	Jos	1790-01-25
307	\N	\N	307	1026	Mexico	Toluca	1790-12-20
308	\N	\N	308	965	Turkmenistan	Gazojak	1790-02-03
309	\N	\N	309	74	Canada	Victoriaville	1790-04-11
310	\N	\N	310	1046	Kazakhstan	Atyrau	1790-06-28
311	\N	\N	311	344	Tajikistan	Danghara	1790-11-03
312	\N	\N	312	871	Mauritania	Zouerate	1790-05-04
313	\N	\N	313	589	Uzbekistan	Chirchiq	1790-02-25
314	\N	\N	314	877	Guatemala	Mixco	1790-02-14
315	\N	\N	315	1150	Nepal	Hetauda	1790-01-24
316	\N	\N	316	882	Bulgaria	Kardzhali	1790-06-06
317	\N	\N	317	33	Iceland	Akureyri	1790-05-02
318	\N	\N	318	1154	Yemen	Ibb	1790-09-07
319	\N	\N	319	840	Djibouti	Obock	1790-07-01
320	\N	\N	320	732	Niger	Madaoua	1790-10-14
321	\N	\N	321	964	Botswana	Kanye	1790-04-04
322	\N	\N	322	26	Hungary	Eger	1790-11-15
323	\N	\N	323	309	France	Osny	1790-06-09
324	\N	\N	324	463	Hungary	Szombathely	1790-12-05
325	\N	\N	325	77	Israel	Tiberias	1790-11-23
326	\N	\N	326	152	Brazil	Barreiros	1790-02-10
327	\N	\N	327	881	Albania	Berat	1790-05-15
328	\N	\N	328	448	Pakistan	Hyderabad	1790-05-20
329	\N	\N	329	297	Namibia	Oshakati	1790-05-17
330	\N	\N	330	1199	Denmark	Esbjerg	1790-03-11
331	\N	\N	331	450	Moldova	Orhei	1790-02-15
332	\N	\N	332	1203	Iceland	Akureyri	1790-10-02
333	\N	\N	333	700	Tunisia	Kebili	1790-08-04
334	\N	\N	334	726	Bolivia	Tupiza	1790-10-09
335	\N	\N	335	813	France	Lens	1790-01-15
336	\N	\N	336	832	Jordan	Jarash	1790-09-21
337	\N	\N	337	777	Madagascar	Ikalamavony	1790-10-28
338	\N	\N	338	227	Oman	Khasab	1790-08-14
339	\N	\N	339	340	Botswana	Mahalapye	1790-01-24
340	\N	\N	340	1119	Niue	Alofi	1790-04-19
341	\N	\N	341	418	Barbados	Bridgetown	1790-05-19
342	\N	\N	342	436	Niger	Dakoro	1790-08-05
343	\N	\N	343	605	Armenia	Gavarr	1790-04-26
344	\N	\N	344	1142	Cameroon	Foumban	1790-05-13
345	\N	\N	345	345	Niue	Alofi	1790-10-13
346	\N	\N	346	1219	Mongolia	Erdenet	1790-10-07
347	\N	\N	347	995	Argentina	Caucete	1790-09-15
348	\N	\N	348	660	Seychelles	Victoria	1790-04-22
349	\N	\N	349	131	India	Afzalgarh	1790-10-11
350	\N	\N	350	638	Tunisia	Metlaoui	1790-07-24
351	\N	\N	351	864	Lithuania	Palanga	1790-12-14
352	\N	\N	352	855	Belize	Belmopan	1790-11-11
353	\N	\N	353	1119	Kosovo	Gjilan	1790-08-07
354	\N	\N	354	240	Tunisia	Tataouine	1790-07-09
355	\N	\N	355	271	Nicaragua	Nagarote	1790-09-17
356	\N	\N	356	1110	Tajikistan	Chkalov	1790-11-13
357	\N	\N	357	1233	Turkey	Kestel	1790-04-27
358	\N	\N	358	526	Romania	Giurgiu	1790-05-14
359	\N	\N	359	402	Lithuania	Alytus	1790-09-15
360	\N	\N	360	523	Qatar	Doha	1790-12-01
361	\N	\N	361	381	Armenia	Armavir	1790-09-10
362	\N	\N	362	296	Nauru	Yaren	1790-03-21
363	\N	\N	363	750	Oman	Seeb	1790-07-26
364	\N	\N	364	1052	Bhutan	Phuntsholing	1790-03-04
365	\N	\N	365	553	Bermuda	Hamilton	1790-04-16
366	\N	\N	366	739	Panama	Pacora	1790-12-19
367	\N	\N	367	985	Russia	Klimovsk	1790-12-04
368	\N	\N	368	279	Montserrat	Brades	1790-10-16
369	\N	\N	369	382	Tunisia	Siliana	1790-12-03
370	\N	\N	370	1202	Bahrain	Sitrah	1790-04-28
371	\N	\N	371	455	Armenia	Masis	1790-11-16
372	\N	\N	372	564	Tanzania	Kidodi	1790-11-10
373	\N	\N	373	730	Georgia	Samtredia	1790-03-07
374	\N	\N	374	1057	Slovenia	Maribor	1790-08-03
375	\N	\N	375	787	Venezuela	Chivacoa	1790-07-19
376	\N	\N	376	605	Bahamas	Lucaya	1790-11-28
377	\N	\N	377	1072	Montserrat	Brades	1790-03-15
378	\N	\N	378	190	Nigeria	Ibi	1790-09-02
379	\N	\N	379	391	Malta	Birkirkara	1790-07-11
380	\N	\N	380	638	Nigeria	Ekpoma	1790-12-17
381	\N	\N	381	487	Georgia	Kobuleti	1790-08-19
382	\N	\N	382	527	Maldives	Male	1790-01-27
383	\N	\N	383	676	Benin	Ouidah	1790-08-18
384	\N	\N	384	789	Senegal	Pourham	1790-11-23
385	\N	\N	385	258	Lesotho	Mafeteng	1790-01-13
386	\N	\N	386	587	Samoa	Apia	1790-02-26
387	\N	\N	387	240	Oman	Muscat	1790-03-19
388	\N	\N	388	833	Comoros	Moroni	1790-02-22
389	\N	\N	389	1187	Belize	Belmopan	1790-09-02
390	\N	\N	390	923	India	Rameswaram	1790-12-23
391	\N	\N	391	941	Lebanon	Sidon	1790-09-08
392	\N	\N	392	757	Laos	Phonsavan	1790-03-03
393	\N	\N	393	545	Italy	Velletri	1790-05-05
394	\N	\N	394	201	Luxembourg	Luxembourg	1790-08-20
395	\N	\N	395	956	Venezuela	Caucaguita	1790-10-11
396	\N	\N	396	1078	Colombia	Tunja	1790-03-18
397	\N	\N	397	1147	Norway	Haugesund	1790-12-02
398	\N	\N	398	670	Zambia	Mansa	1790-07-04
399	\N	\N	399	899	Brunei	Seria	1790-11-24
400	\N	\N	400	1028	Aruba	Angochi	1790-04-07
401	\N	\N	401	589	Pitcairn	Adamstown	1790-11-06
403	\N	\N	403	1002	Samoa	Apia	1790-11-23
404	\N	\N	404	5	Venezuela	Maracaibo	1790-09-25
405	\N	\N	405	876	Taiwan	Puli	1790-12-09
406	\N	\N	406	876	Liechtenstein	Vaduz	1790-09-26
407	\N	\N	407	1150	Lesotho	Mafeteng	1790-11-17
408	\N	\N	408	248	Guatemala	Esquipulas	1790-12-01
409	\N	\N	409	335	Bhutan	Phuntsholing	1790-04-07
410	\N	\N	410	1203	Australia	Coburg	1790-03-16
411	\N	\N	411	656	Tanzania	Isaka	1790-05-04
412	\N	\N	412	727	Pitcairn	Adamstown	1790-03-18
413	\N	\N	413	995	Venezuela	Tucupita	1790-05-21
414	\N	\N	414	584	Mali	Sagalo	1790-05-08
415	\N	\N	415	323	Germany	Gartenstadt	1790-09-19
416	\N	\N	416	565	Ukraine	Vyshhorod	1790-10-05
417	\N	\N	417	657	Kosovo	Podujeva	1790-04-22
418	\N	\N	418	669	Greece	Chios	1790-01-08
419	\N	\N	419	887	Senegal	Matam	1790-07-19
420	\N	\N	420	1063	Cuba	Boyeros	1790-12-27
421	\N	\N	421	893	Belarus	Pastavy	1790-12-16
422	\N	\N	422	751	Germany	Velbert	1790-09-23
423	\N	\N	423	1141	Nepal	Nepalgunj	1790-09-23
424	\N	\N	424	40	Uzbekistan	Showot	1790-05-17
425	\N	\N	425	967	Ecuador	Machala	1790-06-14
426	\N	\N	426	1063	Finland	Pirkkala	1790-07-10
427	\N	\N	427	1219	Belize	Belmopan	1790-08-12
428	\N	\N	428	27	Croatia	Split	1790-03-21
429	\N	\N	429	490	Nigeria	Lalupon	1790-08-17
430	\N	\N	430	280	Ecuador	Cuenca	1790-08-18
431	\N	\N	431	444	Turkmenistan	Seydi	1790-04-28
432	\N	\N	432	579	Canada	Dorval	1790-01-01
433	\N	\N	433	553	Liberia	Greenville	1790-01-01
434	\N	\N	434	155	Panama	Veracruz	1790-07-11
435	\N	\N	435	927	Togo	Badou	1790-06-06
436	\N	\N	436	387	Paraguay	Limpio	1790-09-24
437	\N	\N	437	799	Bangladesh	Tungi	1790-02-01
438	\N	\N	438	1217	Somalia	Buurhakaba	1790-05-17
439	\N	\N	439	596	Latvia	Ventspils	1790-01-13
440	\N	\N	440	730	Finland	Sibbo	1790-07-13
441	\N	\N	441	510	Gabon	Moanda	1790-07-26
442	\N	\N	442	360	Montenegro	Pljevlja	1790-03-24
443	\N	\N	443	547	Barbados	Bridgetown	1790-05-17
444	\N	\N	444	1187	Morocco	Guelmim	1790-10-24
445	\N	\N	445	37	Sweden	Landskrona	1790-01-15
446	\N	\N	446	982	Bahamas	Freeport	1790-11-21
447	\N	\N	447	1218	Liechtenstein	Vaduz	1790-11-08
448	\N	\N	448	300	Zimbabwe	Zvishavane	1790-06-11
449	\N	\N	449	963	Namibia	Swakopmund	1790-09-02
450	\N	\N	450	925	Guyana	Georgetown	1790-03-19
451	\N	\N	451	735	China	Wucheng	1790-10-12
452	\N	\N	452	664	Finland	Lohja	1790-06-09
453	\N	\N	453	1041	Syria	Aleppo	1790-10-04
454	\N	\N	454	1246	Yemen	Ataq	1790-03-10
455	\N	\N	455	899	Suriname	Lelydorp	1790-11-10
456	\N	\N	456	578	Chile	Victoria	1790-01-18
457	\N	\N	457	355	Serbia	Trstenik	1790-07-03
458	\N	\N	458	144	Myanmar	Yangon	1790-05-27
459	\N	\N	459	959	Mayotte	Koungou	1790-09-03
460	\N	\N	460	590	Norway	Molde	1790-11-01
461	\N	\N	461	763	France	Frontignan	1790-01-11
462	\N	\N	462	1225	Tajikistan	Yovon	1790-09-08
463	\N	\N	463	942	Oman	Rustaq	1790-01-28
464	\N	\N	464	638	Poland	Krakow	1790-08-14
465	\N	\N	465	250	Ethiopia	Gondar	1790-05-01
466	\N	\N	466	589	Australia	Mosman	1790-01-21
467	\N	\N	467	1033	Canada	Courtenay	1790-07-03
468	\N	\N	468	143	Estonia	Tartu	1790-11-28
469	\N	\N	469	553	Jamaica	Portmore	1790-04-22
470	\N	\N	470	398	Tajikistan	Tursunzoda	1790-06-24
471	\N	\N	471	54	Slovenia	Velenje	1790-12-01
472	\N	\N	472	411	Nicaragua	Camoapa	1790-06-11
473	\N	\N	473	762	Indonesia	Kutoarjo	1790-09-09
474	\N	\N	474	42	Pakistan	Talamba	1790-01-16
475	\N	\N	475	469	Chad	Kelo	1790-05-06
476	\N	\N	476	1040	India	Narauli	1790-09-26
477	\N	\N	477	133	Gibraltar	Gibraltar	1790-12-25
478	\N	\N	478	101	Greenland	Nuuk	1790-06-26
479	\N	\N	479	607	Tanzania	Kilosa	1790-01-06
480	\N	\N	480	335	Guinea	Kindia	1790-10-21
481	\N	\N	481	657	India	Chennai	1790-02-19
482	\N	\N	482	529	Luxembourg	Luxembourg	1790-06-09
483	\N	\N	483	1108	Panama	Chepo	1790-04-01
484	\N	\N	484	649	Bahamas	Lucaya	1790-01-10
485	\N	\N	485	955	Cyprus	Larnaca	1790-01-05
486	\N	\N	486	1225	Ecuador	Quito	1790-02-11
487	\N	\N	487	970	Estonia	Rakvere	1790-09-19
488	\N	\N	488	591	Hungary	Hatvan	1790-12-21
489	\N	\N	489	809	Liechtenstein	Vaduz	1790-11-28
490	\N	\N	490	612	Moldova	Cahul	1790-06-27
491	\N	\N	491	352	Colombia	Turbaco	1790-09-21
492	\N	\N	492	350	Eritrea	Barentu	1790-09-03
493	\N	\N	493	72	Nepal	Malangwa	1790-06-24
494	\N	\N	494	378	Turkey	Marmaris	1790-04-09
495	\N	\N	495	132	Kiribati	Tarawa	1790-06-12
496	\N	\N	496	728	Belarus	Vawkavysk	1790-09-08
497	\N	\N	497	169	Turkey	Adana	1790-10-18
498	\N	\N	498	962	Liberia	Bensonville	1790-06-06
499	\N	\N	499	94	Zambia	Ndola	1790-05-28
500	\N	\N	500	578	Thailand	Trat	1790-01-21
\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.cities (id, country, city) FROM stdin;
1	Afghanistan	Balkh
2	Afghanistan	Charikar
3	Afghanistan	Farah
4	Afghanistan	Fayzabad
5	Afghanistan	Gereshk
6	Afghanistan	Ghazni
7	Afghanistan	Ghormach
8	Afghanistan	Kabul
9	Afghanistan	Karukh
10	Afghanistan	Khanabad
11	Afghanistan	Khulm
12	Afghanistan	Kunduz
13	Afghanistan	Kushk
14	Afghanistan	Maymana
15	Afghanistan	Shahrak
16	Afghanistan	Taloqan
17	Afghanistan	Zaranj
18	Albania	Berat
19	Albania	Burrel
20	Albania	Elbasan
21	Albania	Fier
22	Albania	Tirana
23	Algeria	Adrar
24	Algeria	Aflou
25	Algeria	Akbou
26	Algeria	Algiers
27	Algeria	Amizour
28	Algeria	Annaba
29	Algeria	Aoulef
30	Algeria	Arbatache
31	Algeria	Arhribs
32	Algeria	Arris
33	Algeria	Azazga
34	Algeria	Azzaba
35	Algeria	Baraki
36	Algeria	Barbacha
37	Algeria	Barika
38	Algeria	Batna
39	Algeria	Bensekrane
40	Algeria	Berrahal
41	Algeria	Berriane
42	Algeria	Berrouaghia
43	Algeria	Besbes
44	Algeria	Birine
45	Algeria	Birkhadem
46	Algeria	Biskra
47	Algeria	Blida
48	Algeria	Boghni
49	Algeria	Boudjima
50	Algeria	Boudouaou
51	Algeria	Boufarik
52	Algeria	Bougaa
53	Algeria	Bougara
54	Algeria	Bouinan
55	Algeria	Boukadir
56	Algeria	Boumerdas
57	Algeria	Brezina
58	Algeria	Charef
59	Algeria	Chebli
60	Algeria	Chemini
61	Algeria	Cheraga
62	Algeria	Cheria
63	Algeria	Chetouane
64	Algeria	Chiffa
65	Algeria	Chlef
66	Algeria	Chorfa
67	Algeria	Constantine
68	Algeria	Debila
69	Algeria	Dellys
70	Algeria	Djamaa
71	Algeria	Djelfa
72	Algeria	Djidiouia
73	Algeria	Douera
74	Algeria	Drean
75	Algeria	Feraoun
76	Algeria	Freha
77	Algeria	Frenda
78	Algeria	Guelma
79	Algeria	Hadjout
80	Algeria	Hammamet
81	Algeria	Hennaya
82	Algeria	Ighram
83	Algeria	Isser
84	Algeria	Jijel
85	Algeria	Kerkera
86	Algeria	Khenchela
87	Algeria	Kolea
88	Algeria	Laghouat
89	Algeria	Lakhdaria
90	Algeria	Lardjem
91	Algeria	Makouda
92	Algeria	Mansourah
93	Algeria	Mascara
94	Algeria	Mazouna
95	Algeria	Meftah
96	Algeria	Megarine
97	Algeria	Mehdia
98	Algeria	Mekla
99	Algeria	Melouza
100	Algeria	Merouana
101	Algeria	Meskiana
102	Algeria	Messaad
103	Algeria	Mila
104	Algeria	Mostaganem
105	Algeria	Naciria
106	Algeria	Nedroma
107	Algeria	Oran
108	Algeria	Ouargla
109	Algeria	Reggane
110	Algeria	Reguiba
111	Algeria	Relizane
112	Algeria	Remchi
113	Algeria	Robbah
114	Algeria	Rouached
115	Algeria	Rouiba
116	Algeria	Rouissat
117	Algeria	Saoula
118	Algeria	Sebdou
119	Algeria	Seddouk
120	Algeria	Sedrata
121	Algeria	Sfizef
122	Algeria	Sig
123	Algeria	Skikda
124	Algeria	Sougueur
125	Algeria	Souma
126	Algeria	Tamalous
127	Algeria	Tamanrasset
128	Algeria	Tebesbest
129	Algeria	Telerghma
130	Algeria	Thenia
131	Algeria	Tiaret
132	Algeria	Timimoun
133	Algeria	Timizart
134	Algeria	Tindouf
135	Algeria	Tipasa
136	Algeria	Tirmitine
137	Algeria	Tissemsilt
138	Algeria	Tlemcen
139	Algeria	Tolga
140	Algeria	Touggourt
141	Algeria	Zemoura
142	Algeria	Zeralda
143	Angola	Benguela
144	Angola	Cabinda
145	Angola	Caluquembe
146	Angola	Camacupa
147	Angola	Catabola
148	Angola	Catumbela
149	Angola	Caxito
150	Angola	Cuito
151	Angola	Huambo
152	Angola	Lobito
153	Angola	Longonjo
154	Angola	Luanda
155	Angola	Luau
156	Angola	Lubango
157	Angola	Lucapa
158	Angola	Luena
159	Angola	Malanje
160	Angola	Menongue
161	Angola	Namibe
162	Angola	Nzeto
163	Angola	Saurimo
164	Angola	Soio
165	Angola	Sumbe
166	Argentina	Aguilares
167	Argentina	Alderetes
168	Argentina	Allen
169	Argentina	Arroyito
170	Argentina	Avellaneda
171	Argentina	Azul
172	Argentina	Barranqueras
173	Argentina	Campana
174	Argentina	Casilda
175	Argentina	Castelli
176	Argentina	Catriel
177	Argentina	Caucete
178	Argentina	Centenario
179	Argentina	Chacabuco
180	Argentina	Charata
181	Argentina	Chilecito
182	Argentina	Chimbas
183	Argentina	Chivilcoy
184	Argentina	Cipolletti
185	Argentina	Colegiales
186	Argentina	Concordia
187	Argentina	Coronda
188	Argentina	Corrientes
189	Argentina	Crespo
190	Argentina	Diamante
191	Argentina	Dolores
192	Argentina	Embalse
193	Argentina	Esperanza
194	Argentina	Esquel
195	Argentina	Esquina
196	Argentina	Federal
197	Argentina	Firmat
198	Argentina	Fontana
199	Argentina	Formosa
200	Argentina	Goya
201	Argentina	Gualeguay
202	Argentina	Laboulaye
203	Argentina	Lincoln
204	Argentina	Machagai
205	Argentina	Mendoza
206	Argentina	Mercedes
207	Argentina	Montecarlo
208	Argentina	Monteros
209	Argentina	Morteros
210	Argentina	Necochea
211	Argentina	Pergamino
212	Argentina	Plottier
213	Argentina	Pocito
214	Argentina	Pontevedra
215	Argentina	Posadas
216	Argentina	Quilmes
217	Argentina	Quitilipi
218	Argentina	Rafaela
219	Argentina	Rawson
220	Argentina	Reconquista
221	Argentina	Resistencia
222	Argentina	Retiro
223	Argentina	Rosario
224	Argentina	Rufino
225	Argentina	Saladas
226	Argentina	Salta
227	Argentina	Sunchales
228	Argentina	Tandil
229	Argentina	Tartagal
230	Argentina	Tigre
231	Argentina	Trelew
232	Argentina	Unquillo
233	Argentina	Ushuaia
234	Argentina	Vera
235	Argentina	Victoria
236	Argentina	Viedma
237	Argentina	Villaguay
238	Argentina	Zapala
239	Armenia	Abovyan
240	Armenia	Ararat
241	Armenia	Armavir
242	Armenia	Artashat
243	Armenia	Ashtarak
244	Armenia	Ejmiatsin
245	Armenia	Gavarr
246	Armenia	Goris
247	Armenia	Gyumri
248	Armenia	Hrazdan
249	Armenia	Kapan
250	Armenia	Masis
251	Armenia	Sevan
252	Armenia	Spitak
253	Armenia	Vanadzor
254	Armenia	Yerevan
255	Aruba	Angochi
256	Aruba	Babijn
257	Aruba	Oranjestad
258	Australia	Adelaide
259	Australia	Albany
260	Australia	Albury
261	Australia	Armadale
262	Australia	Armidale
263	Australia	Ashfield
264	Australia	Auburn
265	Australia	Ballarat
266	Australia	Bankstown
267	Australia	Bathurst
268	Australia	Bendigo
269	Australia	Berwick
270	Australia	Blacktown
271	Australia	Booval
272	Australia	Boronia
273	Australia	Brisbane
274	Australia	Brunswick
275	Australia	Buderim
276	Australia	Bunbury
277	Australia	Bundaberg
278	Australia	Bundoora
279	Australia	Burnie
280	Australia	Busselton
281	Australia	Caboolture
282	Australia	Cairns
283	Australia	Caloundra
284	Australia	Camberwell
285	Australia	Canberra
286	Australia	Carindale
287	Australia	Caringbah
288	Australia	Carlingford
289	Australia	Carnegie
290	Australia	Cessnock
291	Australia	Cheltenham
292	Australia	Clayton
293	Australia	Coburg
294	Australia	Craigieburn
295	Australia	Cranbourne
296	Australia	Cronulla
297	Australia	Dandenong
298	Australia	Darwin
299	Australia	Devonport
300	Australia	Doncaster
301	Australia	Dubbo
302	Australia	Earlwood
303	Australia	Echuca
304	Australia	Eltham
305	Australia	Engadine
306	Australia	Epping
307	Australia	Essendon
308	Australia	Forster
309	Australia	Frankston
310	Australia	Fremantle
311	Australia	Gawler
312	Australia	Geelong
313	Australia	Geraldton
314	Australia	Gladstone
315	Australia	Glenferrie
316	Australia	Glenroy
317	Australia	Gosnells
318	Australia	Goulburn
319	Australia	Granville
320	Australia	Greensborough
321	Australia	Griffith
322	Australia	Hillside
323	Australia	Hobart
324	Australia	Hornsby
325	Australia	Kalgoorlie
326	Australia	Katoomba
327	Australia	Kew
328	Australia	Keysborough
329	Australia	Kwinana
330	Australia	Lalor
331	Australia	Langwarrin
332	Australia	Lara
333	Australia	Launceston
334	Australia	Lilydale
335	Australia	Lismore
336	Australia	Liverpool
337	Australia	Mackay
338	Australia	Maitland
339	Australia	Mandurah
340	Australia	Maroubra
341	Australia	Marrickville
342	Australia	Maryborough
343	Australia	Melbourne
344	Australia	Melton
345	Australia	Mildura
346	Australia	Moe
347	Australia	Morayfield
348	Australia	Mornington
349	Australia	Mosman
350	Australia	Mulgrave
351	Australia	Narangba
352	Australia	Nerang
353	Australia	Newcastle
354	Australia	Northcote
355	Australia	Nowra
356	Australia	Orange
357	Australia	Palmerston
358	Australia	Paramatta
359	Australia	Perth
360	Australia	Preston
361	Australia	Prospect
362	Australia	Queanbeyan
363	Australia	Randwick
364	Australia	Reservoir
365	Australia	Richmond
366	Australia	Rockhampton
367	Australia	Rockingham
368	Australia	Rowville
369	Australia	Seaford
370	Australia	Shepparton
371	Australia	Southport
372	Australia	Springvale
373	Australia	Sunbury
374	Australia	Sunnybank
375	Australia	Sydney
376	Australia	Tamworth
377	Australia	Taree
378	Australia	Tarneit
379	Australia	Thomastown
380	Australia	Thornbury
381	Australia	Thornlie
382	Australia	Toowoomba
383	Australia	Townsville
384	Australia	Traralgon
385	Australia	Umina
386	Australia	Wangaratta
387	Australia	Warrnambool
388	Australia	Werribee
389	Australia	Whyalla
390	Australia	Willetton
391	Australia	Wodonga
392	Australia	Wollongong
393	Australia	Woodridge
394	Austria	Amstetten
395	Austria	Ansfelden
396	Austria	Baden
397	Austria	Bregenz
398	Austria	Dornbirn
399	Austria	Feldkirch
400	Austria	Graz
401	Austria	Hallein
402	Austria	Innsbruck
403	Austria	Kapfenberg
404	Austria	Klosterneuburg
405	Austria	Kufstein
406	Austria	Leoben
407	Austria	Leonding
408	Austria	Linz
409	Austria	Lustenau
410	Austria	Salzburg
411	Austria	Schwechat
412	Austria	Steyr
413	Austria	Ternitz
414	Austria	Traiskirchen
415	Austria	Traun
416	Austria	Vienna
417	Austria	Villach
418	Austria	Wels
419	Austria	Wolfsberg
420	Azerbaijan	Agdzhabedy
421	Azerbaijan	Aghsu
422	Azerbaijan	Amirdzhan
423	Azerbaijan	Astara
424	Azerbaijan	Baku
425	Azerbaijan	Barda
426	Azerbaijan	Beylagan
427	Azerbaijan	Bilajari
428	Azerbaijan	Buzovna
429	Azerbaijan	Divichibazar
430	Azerbaijan	Dzhalilabad
431	Azerbaijan	Fizuli
432	Azerbaijan	Ganja
433	Azerbaijan	Geoktschai
434	Azerbaijan	Imishli
435	Azerbaijan	Khirdalan
436	Azerbaijan	Kyurdarmir
437	Azerbaijan	Lankaran
438	Azerbaijan	Mardakan
439	Azerbaijan	Mingelchaur
440	Azerbaijan	Nakhchivan
441	Azerbaijan	Pushkino
442	Azerbaijan	Qazax
443	Azerbaijan	Quba
444	Azerbaijan	Qusar
445	Azerbaijan	Sabirabad
446	Azerbaijan	Salyan
447	Azerbaijan	Shamakhi
448	Azerbaijan	Shamkhor
449	Azerbaijan	Sheki
450	Azerbaijan	Shushi
451	Azerbaijan	Terter
452	Azerbaijan	Ujar
453	Azerbaijan	Xankandi
454	Azerbaijan	Yelenendorf
455	Azerbaijan	Yevlakh
456	Azerbaijan	Zabrat
457	Azerbaijan	Zaqatala
458	Bahamas	Freeport
459	Bahamas	Lucaya
460	Bahamas	Nassau
461	Bahrain	Manama
462	Bahrain	Sitrah
463	Bangladesh	Azimpur
464	Bangladesh	Badarganj
465	Bangladesh	Baniachang
466	Bangladesh	Bera
467	Bangladesh	Bhola
468	Bangladesh	Bogra
469	Bangladesh	Chittagong
470	Bangladesh	Comilla
471	Bangladesh	Dhaka
472	Bangladesh	Fatikchari
473	Bangladesh	Feni
474	Bangladesh	Gafargaon
475	Bangladesh	Gaurnadi
476	Bangladesh	Habiganj
477	Bangladesh	Ishurdi
478	Bangladesh	Jessore
479	Bangladesh	Kesabpur
480	Bangladesh	Khagrachhari
481	Bangladesh	Khulna
482	Bangladesh	Kishorganj
483	Bangladesh	Kushtia
484	Bangladesh	Lalmanirhat
485	Bangladesh	Manikchari
486	Bangladesh	Mathba
487	Bangladesh	Mehendiganj
488	Bangladesh	Morrelgonj
489	Bangladesh	Mymensingh
490	Bangladesh	Nageswari
491	Bangladesh	Narail
492	Bangladesh	Narsingdi
493	Bangladesh	Netrakona
494	Bangladesh	Paltan
495	Bangladesh	Panchagarh
496	Bangladesh	Parbatipur
497	Bangladesh	Patiya
498	Bangladesh	Phultala
499	Bangladesh	Pirojpur
500	Bangladesh	Rangpur
501	Bangladesh	Saidpur
502	Bangladesh	Sakhipur
503	Bangladesh	Sarankhola
504	Bangladesh	Sherpur
505	Bangladesh	Shibganj
506	Bangladesh	Sylhet
507	Bangladesh	Tungi
508	Barbados	Bridgetown
509	Belarus	Asipovichy
510	Belarus	Babruysk
511	Belarus	Baranovichi
512	Belarus	Brest
513	Belarus	Byaroza
514	Belarus	Bykhaw
515	Belarus	Dobrush
516	Belarus	Dzyarzhynsk
517	Belarus	Gomel
518	Belarus	Hlybokaye
519	Belarus	Horki
520	Belarus	Hrodna
521	Belarus	Ivatsevichy
522	Belarus	Kalinkavichy
523	Belarus	Kalodzishchy
524	Belarus	Kobryn
525	Belarus	Krychaw
526	Belarus	Lida
527	Belarus	Luninyets
528	Belarus	Mahilyow
529	Belarus	Maladzyechna
530	Belarus	Malinovka
531	Belarus	Masty
532	Belarus	Mazyr
533	Belarus	Minsk
534	Belarus	Navahrudak
535	Belarus	Navapolatsk
536	Belarus	Orsha
537	Belarus	Pastavy
538	Belarus	Pinsk
539	Belarus	Polatsk
540	Belarus	Pruzhany
541	Belarus	Rahachow
542	Belarus	Rechytsa
543	Belarus	Salihorsk
544	Belarus	Shchuchin
545	Belarus	Slonim
546	Belarus	Slutsk
547	Belarus	Stowbtsy
548	Belarus	Svyetlahorsk
549	Belarus	Vawkavysk
550	Belarus	Vilyeyka
551	Belarus	Vitebsk
552	Belarus	Zhlobin
553	Belgium	Aalst
554	Belgium	Aalter
555	Belgium	Aarschot
556	Belgium	Andenne
557	Belgium	Ans
558	Belgium	Antwerpen
559	Belgium	Arlon
560	Belgium	Asse
561	Belgium	Ath
562	Belgium	Balen
563	Belgium	Beerse
564	Belgium	Beersel
565	Belgium	Beringen
566	Belgium	Beveren
567	Belgium	Bilzen
568	Belgium	Binche
569	Belgium	Blankenberge
570	Belgium	Boom
571	Belgium	Bornem
572	Belgium	Boussu
573	Belgium	Brasschaat
574	Belgium	Brecht
575	Belgium	Brugge
576	Belgium	Brussels
577	Belgium	Charleroi
578	Belgium	Chaudfontaine
579	Belgium	Colfontaine
580	Belgium	Courcelles
581	Belgium	Deinze
582	Belgium	Denderleeuw
583	Belgium	Dendermonde
584	Belgium	Destelbergen
585	Belgium	Diepenbeek
586	Belgium	Diest
587	Belgium	Diksmuide
588	Belgium	Dilbeek
589	Belgium	Dour
590	Belgium	Duffel
591	Belgium	Edegem
592	Belgium	Eeklo
593	Belgium	Essen
594	Belgium	Eupen
595	Belgium	Evergem
596	Belgium	Fleurus
597	Belgium	Frameries
598	Belgium	Geel
599	Belgium	Gembloux
600	Belgium	Genk
601	Belgium	Gent
602	Belgium	Geraardsbergen
603	Belgium	Grimbergen
604	Belgium	Haaltert
605	Belgium	Halle
606	Belgium	Hamme
607	Belgium	Harelbeke
608	Belgium	Hasselt
609	Belgium	Helchteren
610	Belgium	Herent
611	Belgium	Herentals
612	Belgium	Herstal
613	Belgium	Herve
614	Belgium	Herzele
615	Belgium	Heusden
616	Belgium	Hoboken
617	Belgium	Hoogstraten
618	Belgium	Houthalen
619	Belgium	Huy
620	Belgium	Ieper
621	Belgium	Izegem
622	Belgium	Kalmthout
623	Belgium	Kapellen
624	Belgium	Kasterlee
625	Belgium	Koksijde
626	Belgium	Kontich
627	Belgium	Kortenberg
628	Belgium	Kortrijk
629	Belgium	Lanaken
630	Belgium	Lebbeke
631	Belgium	Lede
632	Belgium	Lessines
633	Belgium	Leuven
634	Belgium	Lier
635	Belgium	Lille
636	Belgium	Lochristi
637	Belgium	Lokeren
638	Belgium	Lommel
639	Belgium	Londerzeel
640	Belgium	Maaseik
641	Belgium	Maasmechelen
642	Belgium	Maldegem
643	Belgium	Manage
644	Belgium	Mechelen
645	Belgium	Meise
646	Belgium	Menen
647	Belgium	Merelbeke
648	Belgium	Middelkerke
649	Belgium	Mol
650	Belgium	Mons
651	Belgium	Mortsel
652	Belgium	Mouscron
653	Belgium	Namur
654	Belgium	Neerpelt
655	Belgium	Nijlen
656	Belgium	Ninove
657	Belgium	Nivelles
658	Belgium	Oostkamp
659	Belgium	Ostend
660	Belgium	Oudenaarde
661	Belgium	Oupeye
662	Belgium	Overijse
663	Belgium	Peer
664	Belgium	Poperinge
665	Belgium	Putte
666	Belgium	Puurs
667	Belgium	Quaregnon
668	Belgium	Ranst
669	Belgium	Riemst
670	Belgium	Rixensart
671	Belgium	Roeselare
672	Belgium	Ronse
673	Belgium	Rotselaar
674	Belgium	Schilde
675	Belgium	Schoten
676	Belgium	Seraing
677	Belgium	Soignies
678	Belgium	Soumagne
679	Belgium	Stabroek
680	Belgium	Stekene
681	Belgium	Temse
682	Belgium	Tervuren
683	Belgium	Tessenderlo
684	Belgium	Tielt
685	Belgium	Tienen
686	Belgium	Tongeren
687	Belgium	Torhout
688	Belgium	Tournai
689	Belgium	Tubize
690	Belgium	Turnhout
691	Belgium	Verviers
692	Belgium	Vilvoorde
693	Belgium	Walcourt
694	Belgium	Waregem
695	Belgium	Waterloo
696	Belgium	Wavre
697	Belgium	Wervik
698	Belgium	Westerlo
699	Belgium	Wetteren
700	Belgium	Wevelgem
701	Belgium	Willebroek
702	Belgium	Wuustwezel
703	Belgium	Zaventem
704	Belgium	Zedelgem
705	Belgium	Zele
706	Belgium	Zemst
707	Belgium	Zoersel
708	Belgium	Zonhoven
709	Belgium	Zottegem
710	Belgium	Zwevegem
711	Belgium	Zwijndrecht
712	Belize	Belmopan
713	Benin	Abomey
714	Benin	Allada
715	Benin	Banikoara
716	Benin	Bassila
717	Benin	Bohicon
718	Benin	Cotonou
719	Benin	Djougou
720	Benin	Dogbo
721	Benin	Kandi
722	Benin	Lokossa
723	Benin	Malanville
724	Benin	Natitingou
725	Benin	Nikki
726	Benin	Ouidah
727	Benin	Parakou
728	Benin	Savalou
729	Benin	Tchaourou
730	Bermuda	Hamilton
731	Bhutan	Phuntsholing
732	Bhutan	Thimphu
733	Bhutan	Tsirang
734	Bolivia	Camiri
735	Bolivia	Cobija
736	Bolivia	Cochabamba
737	Bolivia	Cotoca
738	Bolivia	Huanuni
739	Bolivia	Llallagua
740	Bolivia	Mizque
741	Bolivia	Montero
742	Bolivia	Oruro
743	Bolivia	Punata
744	Bolivia	Riberalta
745	Bolivia	Sucre
746	Bolivia	Tarija
747	Bolivia	Trinidad
748	Bolivia	Tupiza
749	Bolivia	Villamontes
750	Bolivia	Warnes
751	Bolivia	Yacuiba
752	Botswana	Francistown
753	Botswana	Gaborone
754	Botswana	Janeng
755	Botswana	Kanye
756	Botswana	Letlhakane
757	Botswana	Lobatse
758	Botswana	Mahalapye
759	Botswana	Maun
760	Botswana	Mochudi
761	Botswana	Mogoditshane
762	Botswana	Molepolole
763	Botswana	Mosopa
764	Botswana	Palapye
765	Botswana	Ramotswa
766	Botswana	Serowe
767	Botswana	Thamaga
768	Botswana	Tonota
769	Brazil	Abaetetuba
770	Brazil	Acopiara
771	Brazil	Adamantina
772	Brazil	Agudos
773	Brazil	Alagoinhas
774	Brazil	Alegre
775	Brazil	Alegrete
776	Brazil	Alenquer
777	Brazil	Alfenas
778	Brazil	Almeirim
779	Brazil	Almenara
780	Brazil	Altamira
781	Brazil	Altos
782	Brazil	Amaraji
783	Brazil	Amargosa
784	Brazil	Americana
785	Brazil	Amparo
786	Brazil	Ananindeua
787	Brazil	Andradas
788	Brazil	Andradina
789	Brazil	Anicuns
790	Brazil	Antonina
791	Brazil	Aparecida
792	Brazil	Apodi
793	Brazil	Apucarana
794	Brazil	Aquidauana
795	Brazil	Aquiraz
796	Brazil	Aracaju
797	Brazil	Aracati
798	Brazil	Araci
799	Brazil	Aracruz
800	Brazil	Araguari
801	Brazil	Arapiraca
802	Brazil	Arapongas
803	Brazil	Araraquara
804	Brazil	Araras
805	Brazil	Arari
806	Brazil	Araripina
807	Brazil	Araruama
808	Brazil	Arcos
809	Brazil	Arcoverde
810	Brazil	Ariquemes
811	Brazil	Assis
812	Brazil	Astorga
813	Brazil	Atalaia
814	Brazil	Atibaia
815	Brazil	Bacabal
816	Brazil	Balsas
817	Brazil	Bandeirantes
818	Brazil	Barbacena
819	Brazil	Barbalha
820	Brazil	Barcarena
821	Brazil	Bariri
822	Brazil	Barra
823	Brazil	Barras
824	Brazil	Barreiras
825	Brazil	Barreirinhas
826	Brazil	Barreiros
827	Brazil	Barretos
828	Brazil	Barrinha
829	Brazil	Barroso
830	Brazil	Barueri
831	Brazil	Bastos
832	Brazil	Batatais
833	Brazil	Bauru
834	Brazil	Bayeux
835	Brazil	Bebedouro
836	Brazil	Beberibe
837	Brazil	Benevides
838	Brazil	Bertioga
839	Brazil	Betim
840	Brazil	Bezerros
841	Brazil	Birigui
842	Brazil	Blumenau
843	Brazil	Boituva
844	Brazil	Botucatu
845	Brazil	Breves
846	Brazil	Brotas
847	Brazil	Brumadinho
848	Brazil	Brumado
849	Brazil	Brusque
850	Brazil	Buerarema
851	Brazil	Buri
852	Brazil	Buritis
853	Brazil	Buritizeiro
854	Brazil	Cabedelo
855	Brazil	Cabo
856	Brazil	Cachoeira
857	Brazil	Cachoeirinha
858	Brazil	Cacoal
859	Brazil	Caieiras
860	Brazil	Cajamar
861	Brazil	Cajati
862	Brazil	Cajazeiras
863	Brazil	Cajueiro
864	Brazil	Cajuru
865	Brazil	Camanducaia
866	Brazil	Cambebba
867	Brazil	Camocim
868	Brazil	Campinas
869	Brazil	Campos
870	Brazil	Canavieiras
871	Brazil	Canela
872	Brazil	Canguaretama
873	Brazil	Canoas
874	Brazil	Canoinhas
875	Brazil	Capanema
876	Brazil	Capela
877	Brazil	Capelinha
878	Brazil	Capinzal
879	Brazil	Capivari
880	Brazil	Caraguatatuba
881	Brazil	Carangola
882	Brazil	Caratinga
883	Brazil	Carauari
884	Brazil	Carazinho
885	Brazil	Carolina
886	Brazil	Carpina
887	Brazil	Caruaru
888	Brazil	Cascavel
889	Brazil	Castanhal
890	Brazil	Castelo
891	Brazil	Castro
892	Brazil	Cataguases
893	Brazil	Catanduva
894	Brazil	Catende
895	Brazil	Catu
896	Brazil	Caucaia
897	Brazil	Caxambu
898	Brazil	Caxias
899	Brazil	Ceres
900	Brazil	Cerquilho
901	Brazil	Chapadinha
902	Brazil	Charqueadas
903	Brazil	Cianorte
904	Brazil	Coaraci
905	Brazil	Coari
906	Brazil	Colatina
907	Brazil	Colinas
908	Brazil	Colombo
909	Brazil	Colorado
910	Brazil	Conchal
911	Brazil	Condado
912	Brazil	Conde
913	Brazil	Congonhas
914	Brazil	Contagem
915	Brazil	Cordeiro
916	Brazil	Corinto
917	Brazil	Coromandel
918	Brazil	Coruripe
919	Brazil	Cotia
920	Brazil	Coxim
921	Brazil	Crato
922	Brazil	Cravinhos
923	Brazil	Cristalina
924	Brazil	Cruzeiro
925	Brazil	Cupira
926	Brazil	Curitiba
927	Brazil	Curitibanos
928	Brazil	Cururupu
929	Brazil	Curvelo
930	Brazil	Descalvado
931	Brazil	Diadema
932	Brazil	Diamantina
933	Brazil	Diamantino
934	Brazil	Dourados
935	Brazil	Embu
936	Brazil	Encantado
937	Brazil	Erechim
938	Brazil	Escada
939	Brazil	Esmeraldas
940	Brazil	Esperantina
941	Brazil	Espinosa
942	Brazil	Esplanada
943	Brazil	Esteio
944	Brazil	Estreito
945	Brazil	Estrela
946	Brazil	Extremoz
947	Brazil	Farroupilha
948	Brazil	Floresta
949	Brazil	Floriano
950	Brazil	Formiga
951	Brazil	Formosa
952	Brazil	Forquilhinha
953	Brazil	Fortaleza
954	Brazil	Franca
955	Brazil	Frutal
956	Brazil	Gameleira
957	Brazil	Gandu
958	Brazil	Garanhuns
959	Brazil	Garibaldi
960	Brazil	Gaspar
961	Brazil	Goiana
962	Brazil	Goianira
963	Brazil	Goiatuba
964	Brazil	Granja
965	Brazil	Guanambi
966	Brazil	Guapimirim
967	Brazil	Guarabira
968	Brazil	Guaramirim
969	Brazil	Guarapari
970	Brazil	Guarapuava
971	Brazil	Guararapes
972	Brazil	Guararema
973	Brazil	Guaratuba
974	Brazil	Guariba
975	Brazil	Guarulhos
976	Brazil	Gurupi
977	Brazil	Herval
978	Brazil	Horizonte
979	Brazil	Ibaiti
980	Brazil	Ibirama
981	Brazil	Ibirataia
982	Brazil	Ibitinga
983	Brazil	Ibotirama
984	Brazil	Igarapava
985	Brazil	Igarassu
986	Brazil	Igrejinha
987	Brazil	Iguape
988	Brazil	Iguatu
989	Brazil	Ilhabela
990	Brazil	Imbituba
991	Brazil	Imbituva
992	Brazil	Imperatriz
993	Brazil	Indaial
994	Brazil	Indaiatuba
995	Brazil	Inhumas
996	Brazil	Ipaba
997	Brazil	Ipameri
998	Brazil	Ipatinga
999	Brazil	Ipojuca
1000	Brazil	Ipu
1001	Brazil	Ipubi
1002	Brazil	Ipueiras
1003	Brazil	Irati
1004	Brazil	Itabaiana
1005	Brazil	Itabaianinha
1006	Brazil	Itaberaba
1007	Brazil	Itabira
1008	Brazil	Itabirito
1009	Brazil	Itabuna
1010	Brazil	Itacoatiara
1011	Brazil	Itaitinga
1012	Brazil	Itaituba
1013	Brazil	Itamaraju
1014	Brazil	Itamarandiba
1015	Brazil	Itaocara
1016	Brazil	Itapaci
1017	Brazil	Itaparica
1018	Brazil	Itapecerica
1019	Brazil	Itapema
1020	Brazil	Itapemirim
1021	Brazil	Itaperuna
1022	Brazil	Itapetinga
1023	Brazil	Itapetininga
1024	Brazil	Itapeva
1025	Brazil	Itapevi
1026	Brazil	Itapipoca
1027	Brazil	Itapira
1028	Brazil	Itapissuma
1029	Brazil	Itaporanga
1030	Brazil	Itapuranga
1031	Brazil	Itaquaquecetuba
1032	Brazil	Itaqui
1033	Brazil	Itatiba
1034	Brazil	Itatinga
1035	Brazil	Itu
1036	Brazil	Ituiutaba
1037	Brazil	Itumbiara
1038	Brazil	Itupeva
1039	Brazil	Itupiranga
1040	Brazil	Iturama
1041	Brazil	Ituverava
1042	Brazil	Ivoti
1043	Brazil	Jaboticabal
1044	Brazil	Jacarezinho
1045	Brazil	Jaciara
1046	Brazil	Jacobina
1047	Brazil	Jacutinga
1048	Brazil	Jaguaquara
1049	Brazil	Jaguarari
1050	Brazil	Jaguaribe
1051	Brazil	Jaguaruana
1052	Brazil	Jales
1053	Brazil	Jandira
1054	Brazil	Japeri
1055	Brazil	Jardim
1056	Brazil	Jarinu
1057	Brazil	Jaru
1058	Brazil	Jequitinhonha
1059	Brazil	Jeremoabo
1060	Brazil	Joinville
1061	Brazil	Juatuba
1062	Brazil	Lagarto
1063	Brazil	Lages
1064	Brazil	Laguna
1065	Brazil	Lajeado
1066	Brazil	Lajedo
1067	Brazil	Lajinha
1068	Brazil	Lapa
1069	Brazil	Laranjeiras
1070	Brazil	Lavras
1071	Brazil	Leme
1072	Brazil	Leopoldina
1073	Brazil	Limeira
1074	Brazil	Limoeiro
1075	Brazil	Linhares
1076	Brazil	Lins
1077	Brazil	Loanda
1078	Brazil	Londrina
1079	Brazil	Lorena
1080	Brazil	Louveira
1081	Brazil	Lucas
1082	Brazil	Macatuba
1083	Brazil	Macau
1084	Brazil	Machado
1085	Brazil	Mafra
1086	Brazil	Mairinque
1087	Brazil	Mamanguape
1088	Brazil	Manacapuru
1089	Brazil	Manaus
1090	Brazil	Mandaguari
1091	Brazil	Mangaratiba
1092	Brazil	Manhumirim
1093	Brazil	Maracaju
1094	Brazil	Maragogi
1095	Brazil	Maragogipe
1096	Brazil	Marataizes
1097	Brazil	Marau
1098	Brazil	Mari
1099	Brazil	Marialva
1100	Brazil	Mariana
1101	Brazil	Mascote
1102	Brazil	Matozinhos
1103	Brazil	Medianeira
1104	Brazil	Mendes
1105	Brazil	Mineiros
1106	Brazil	Miracema
1107	Brazil	Mocajuba
1108	Brazil	Mococa
1109	Brazil	Moju
1110	Brazil	Monteiro
1111	Brazil	Montenegro
1112	Brazil	Moreno
1113	Brazil	Morrinhos
1114	Brazil	Mucuri
1115	Brazil	Murici
1116	Brazil	Muritiba
1117	Brazil	Muzambinho
1118	Brazil	Nanuque
1119	Brazil	Natal
1120	Brazil	Navegantes
1121	Brazil	Nepomuceno
1122	Brazil	Oeiras
1123	Brazil	Olinda
1124	Brazil	Oliveira
1125	Brazil	Orleans
1126	Brazil	Osasco
1127	Brazil	Ouricuri
1128	Brazil	Ourinhos
1129	Brazil	Pacajus
1130	Brazil	Pacatuba
1131	Brazil	Palmares
1132	Brazil	Palmas
1133	Brazil	Palmeira
1134	Brazil	Palmital
1135	Brazil	Palotina
1136	Brazil	Panambi
1137	Brazil	Paracambi
1138	Brazil	Paracatu
1139	Brazil	Paracuru
1140	Brazil	Paragominas
1141	Brazil	Paraipaba
1142	Brazil	Paranapanema
1143	Brazil	Paraty
1144	Brazil	Parelhas
1145	Brazil	Parintins
1146	Brazil	Parnamirim
1147	Brazil	Passos
1148	Brazil	Patos
1149	Brazil	Paulista
1150	Brazil	Pederneiras
1151	Brazil	Pedreira
1152	Brazil	Pelotas
1153	Brazil	Penalva
1154	Brazil	Penedo
1155	Brazil	Penha
1156	Brazil	Pentecoste
1157	Brazil	Pesqueira
1158	Brazil	Petrolina
1159	Brazil	Picos
1160	Brazil	Piedade
1161	Brazil	Pilar
1162	Brazil	Pindamonhangaba
1163	Brazil	Pinhais
1164	Brazil	Pinheiral
1165	Brazil	Pinheiro
1166	Brazil	Piracaia
1167	Brazil	Piracanjuba
1168	Brazil	Piracicaba
1169	Brazil	Piracuruca
1170	Brazil	Piraju
1171	Brazil	Pirapora
1172	Brazil	Pirapozinho
1173	Brazil	Piraquara
1174	Brazil	Pirassununga
1175	Brazil	Piripiri
1176	Brazil	Piritiba
1177	Brazil	Pitanga
1178	Brazil	Pitangueiras
1179	Brazil	Pitangui
1180	Brazil	Planaltina
1181	Brazil	Pombal
1182	Brazil	Pombos
1183	Brazil	Pomerode
1184	Brazil	Pontal
1185	Brazil	Porangatu
1186	Brazil	Portel
1187	Brazil	Posse
1188	Brazil	Prado
1189	Brazil	Prata
1190	Brazil	Queimados
1191	Brazil	Quixeramobim
1192	Brazil	Rancharia
1193	Brazil	Recife
1194	Brazil	Registro
1195	Brazil	Resende
1196	Brazil	Resplendor
1197	Brazil	Rolante
1198	Brazil	Rubiataba
1199	Brazil	Russas
1200	Brazil	Sacramento
1201	Brazil	Salgueiro
1202	Brazil	Salinas
1203	Brazil	Salto
1204	Brazil	Salvador
1205	Brazil	Santaluz
1206	Brazil	Santana
1207	Brazil	Santiago
1208	Brazil	Santos
1209	Brazil	Sapiranga
1210	Brazil	Sapucaia
1211	Brazil	Saquarema
1212	Brazil	Sarandi
1213	Brazil	Sarzedo
1214	Brazil	Satuba
1215	Brazil	Saubara
1216	Brazil	Schroeder
1217	Brazil	Seabra
1218	Brazil	Serra
1219	Brazil	Serrana
1220	Brazil	Serrinha
1221	Brazil	Sinop
1222	Brazil	Sobradinho
1223	Brazil	Sobral
1224	Brazil	Socorro
1225	Brazil	Soledade
1226	Brazil	Sorocaba
1227	Brazil	Soure
1228	Brazil	Sousa
1229	Brazil	Surubim
1230	Brazil	Suzano
1231	Brazil	Tabatinga
1232	Brazil	Tabira
1233	Brazil	Taiobeiras
1234	Brazil	Tanabi
1235	Brazil	Tapes
1236	Brazil	Taquara
1237	Brazil	Taquari
1238	Brazil	Taquaritinga
1239	Brazil	Taquarituba
1240	Brazil	Teresina
1241	Brazil	Tijucas
1242	Brazil	Timbiras
1243	Brazil	Timon
1244	Brazil	Toledo
1245	Brazil	Toritama
1246	Brazil	Torres
1247	Brazil	Trairi
1248	Brazil	Trindade
1249	Brazil	Tucano
1250	Brazil	Tuntum
1251	Brazil	Tupaciguara
1252	Brazil	Ubaitaba
1253	Brazil	Ubatuba
1254	Brazil	Uberaba
1255	Brazil	Umuarama
1256	Brazil	Una
1257	Brazil	Uruguaiana
1258	Brazil	Vacaria
1259	Brazil	Valinhos
1260	Brazil	Varginha
1261	Brazil	Varjota
1262	Brazil	Vassouras
1263	Brazil	Vazante
1264	Brazil	Vespasiano
1265	Brazil	Viana
1266	Brazil	Videira
1267	Brazil	Vigia
1268	Brazil	Vilhena
1269	Brazil	Vinhedo
1270	Brazil	Viradouro
1271	Brazil	Viseu
1272	Brazil	Votorantim
1273	Brazil	Votuporanga
1274	Brunei	Seria
1275	Brunei	Tutong
1276	Bulgaria	Asenovgrad
1277	Bulgaria	Aytos
1278	Bulgaria	Berkovitsa
1279	Bulgaria	Blagoevgrad
1280	Bulgaria	Botevgrad
1281	Bulgaria	Burgas
1282	Bulgaria	Chirpan
1283	Bulgaria	Dimitrovgrad
1284	Bulgaria	Dobrich
1285	Bulgaria	Dupnitsa
1286	Bulgaria	Gabrovo
1287	Bulgaria	Haskovo
1288	Bulgaria	Kardzhali
1289	Bulgaria	Karlovo
1290	Bulgaria	Karnobat
1291	Bulgaria	Kharmanli
1292	Bulgaria	Kyustendil
1293	Bulgaria	Lom
1294	Bulgaria	Lovech
1295	Bulgaria	Montana
1296	Bulgaria	Panagyurishte
1297	Bulgaria	Pazardzhik
1298	Bulgaria	Pernik
1299	Bulgaria	Peshtera
1300	Bulgaria	Petrich
1301	Bulgaria	Pleven
1302	Bulgaria	Plovdiv
1303	Bulgaria	Popovo
1304	Bulgaria	Rakovski
1305	Bulgaria	Razgrad
1306	Bulgaria	Ruse
1307	Bulgaria	Samokov
1308	Bulgaria	Sandanski
1309	Bulgaria	Sevlievo
1310	Bulgaria	Shumen
1311	Bulgaria	Silistra
1312	Bulgaria	Sliven
1313	Bulgaria	Smolyan
1314	Bulgaria	Sofia
1315	Bulgaria	Svilengrad
1316	Bulgaria	Svishtov
1317	Bulgaria	Targovishte
1318	Bulgaria	Troyan
1319	Bulgaria	Varna
1320	Bulgaria	Velingrad
1321	Bulgaria	Vidin
1322	Bulgaria	Vratsa
1323	Bulgaria	Yambol
1324	Burundi	Bujumbura
1325	Burundi	Bururi
1326	Burundi	Gitega
1327	Burundi	Kayanza
1328	Burundi	Makamba
1329	Burundi	Muramvya
1330	Burundi	Muyinga
1331	Burundi	Ngozi
1332	Burundi	Rutana
1333	Burundi	Ruyigi
1334	Cambodia	Battambang
1335	Cambodia	Kampot
1336	Cambodia	Pailin
1337	Cambodia	Pursat
1338	Cambodia	Sihanoukville
1339	Cambodia	Takeo
1340	Cameroon	Akonolinga
1341	Cameroon	Bafang
1342	Cameroon	Bafia
1343	Cameroon	Bafoussam
1344	Cameroon	Bali
1345	Cameroon	Bamenda
1346	Cameroon	Bamusso
1347	Cameroon	Banyo
1348	Cameroon	Batouri
1349	Cameroon	Bertoua
1350	Cameroon	Bogo
1351	Cameroon	Buea
1352	Cameroon	Douala
1353	Cameroon	Dschang
1354	Cameroon	Fontem
1355	Cameroon	Foumban
1356	Cameroon	Foumbot
1357	Cameroon	Fundong
1358	Cameroon	Garoua
1359	Cameroon	Guider
1360	Cameroon	Idenao
1361	Cameroon	Kribi
1362	Cameroon	Kumba
1363	Cameroon	Kumbo
1364	Cameroon	Lagdo
1365	Cameroon	Limbe
1366	Cameroon	Lolodorf
1367	Cameroon	Loum
1368	Cameroon	Mamfe
1369	Cameroon	Manjo
1370	Cameroon	Maroua
1371	Cameroon	Mbalmayo
1372	Cameroon	Mbandjok
1373	Cameroon	Mbanga
1374	Cameroon	Mbouda
1375	Cameroon	Melong
1376	Cameroon	Mokolo
1377	Cameroon	Mora
1378	Cameroon	Mutengene
1379	Cameroon	Muyuka
1380	Cameroon	Nkongsamba
1381	Cameroon	Nkoteng
1382	Cameroon	Obala
1383	Cameroon	Penja
1384	Cameroon	Tibati
1385	Cameroon	Tiko
1386	Cameroon	Tonga
1387	Cameroon	Wum
1388	Cameroon	Yagoua
1389	Canada	Abbotsford
1390	Canada	Airdrie
1391	Canada	Ajax
1392	Canada	Alma
1393	Canada	Amos
1394	Canada	Ancaster
1395	Canada	Anmore
1396	Canada	Barrie
1397	Canada	Beaconsfield
1398	Canada	Belleville
1399	Canada	Beloeil
1400	Canada	Blainville
1401	Canada	Boisbriand
1402	Canada	Boucherville
1403	Canada	Brampton
1404	Canada	Brandon
1405	Canada	Brant
1406	Canada	Brantford
1407	Canada	Brockville
1408	Canada	Brossard
1409	Canada	Burlington
1410	Canada	Burnaby
1411	Canada	Calgary
1412	Canada	Cambridge
1413	Canada	Camrose
1414	Canada	Candiac
1415	Canada	Chambly
1416	Canada	Charlottetown
1417	Canada	Chilliwack
1418	Canada	Cobourg
1419	Canada	Cochrane
1420	Canada	Collingwood
1421	Canada	Coquitlam
1422	Canada	Cornwall
1423	Canada	Courtenay
1424	Canada	Cranbrook
1425	Canada	Dartmouth
1426	Canada	Delta
1427	Canada	Dieppe
1428	Canada	Dorval
1429	Canada	Drummondville
1430	Canada	Duncan
1431	Canada	Edmonton
1432	Canada	Edmundston
1433	Canada	Etobicoke
1434	Canada	Fredericton
1435	Canada	Gatineau
1436	Canada	Granby
1437	Canada	Guelph
1438	Canada	Halifax
1439	Canada	Hamilton
1440	Canada	Huntsville
1441	Canada	Joliette
1442	Canada	Kamloops
1443	Canada	Kelowna
1444	Canada	Keswick
1445	Canada	Kingston
1446	Canada	Kirkland
1447	Canada	Kitchener
1448	Canada	Ladner
1449	Canada	Langford
1450	Canada	Langley
1451	Canada	Laval
1452	Canada	Leduc
1453	Canada	Lethbridge
1454	Canada	Lloydminster
1455	Canada	London
1456	Canada	Longueuil
1457	Canada	Magog
1458	Canada	Markham
1459	Canada	Mascouche
1460	Canada	Midland
1461	Canada	Milton
1462	Canada	Mirabel
1463	Canada	Miramichi
1464	Canada	Mississauga
1465	Canada	Moncton
1466	Canada	Nanaimo
1467	Canada	Newmarket
1468	Canada	Oakville
1469	Canada	Okanagan
1470	Canada	Orangeville
1471	Canada	Orillia
1472	Canada	Oshawa
1473	Canada	Ottawa
1474	Canada	Parksville
1475	Canada	Pembroke
1476	Canada	Penticton
1477	Canada	Petawawa
1478	Canada	Peterborough
1479	Canada	Pickering
1480	Canada	Regina
1481	Canada	Repentigny
1482	Canada	Richmond
1483	Canada	Rimouski
1484	Canada	Saguenay
1485	Canada	Sarnia
1486	Canada	Saskatoon
1487	Canada	Scarborough
1488	Canada	Shawinigan
1489	Canada	Sherbrooke
1490	Canada	Stratford
1491	Canada	Surrey
1492	Canada	Sydney
1493	Canada	Terrace
1494	Canada	Terrebonne
1495	Canada	Thorold
1496	Canada	Timmins
1497	Canada	Toronto
1498	Canada	Truro
1499	Canada	Vancouver
1500	Canada	Varennes
1501	Canada	Vaughan
1502	Canada	Vernon
1503	Canada	Victoria
1504	Canada	Victoriaville
1505	Canada	Waterloo
1506	Canada	Welland
1507	Canada	Westmount
1508	Canada	Whitehorse
1509	Canada	Willowdale
1510	Canada	Windsor
1511	Canada	Winnipeg
1512	Canada	Woodstock
1513	Canada	Yellowknife
1514	Canada	Yorkton
1515	Chad	Ati
1516	Chad	Benoy
1517	Chad	Bitkine
1518	Chad	Bongor
1519	Chad	Doba
1520	Chad	Dourbali
1521	Chad	Fada
1522	Chad	Kelo
1523	Chad	Koumra
1524	Chad	Mao
1525	Chad	Massaguet
1526	Chad	Massakory
1527	Chad	Mongo
1528	Chad	Moundou
1529	Chad	Moussoro
1530	Chad	Pala
1531	Chad	Sagh
1532	Chile	Ancud
1533	Chile	Angol
1534	Chile	Antofagasta
1535	Chile	Arauco
1536	Chile	Arica
1537	Chile	Buin
1538	Chile	Cabrero
1539	Chile	Calama
1540	Chile	Cartagena
1541	Chile	Castro
1542	Chile	Cauquenes
1543	Chile	Chiguayante
1544	Chile	Chimbarongo
1545	Chile	Coihaique
1546	Chile	Collipulli
1547	Chile	Coquimbo
1548	Chile	Coronel
1549	Chile	Curanilahue
1550	Chile	Frutillar
1551	Chile	Graneros
1552	Chile	Illapel
1553	Chile	Iquique
1554	Chile	Lampa
1555	Chile	Lautaro
1556	Chile	Lebu
1557	Chile	Limache
1558	Chile	Linares
1559	Chile	Llaillay
1560	Chile	Loncoche
1561	Chile	Lota
1562	Chile	Melipilla
1563	Chile	Molina
1564	Chile	Nacimiento
1565	Chile	Osorno
1566	Chile	Ovalle
1567	Chile	Paine
1568	Chile	Panguipulli
1569	Chile	Parral
1570	Chile	Penco
1571	Chile	Quillota
1572	Chile	Rancagua
1573	Chile	Rengo
1574	Chile	Santiago
1575	Chile	Talagante
1576	Chile	Talca
1577	Chile	Talcahuano
1578	Chile	Temuco
1579	Chile	Tocopilla
1580	Chile	Valdivia
1581	Chile	Vallenar
1582	Chile	Victoria
1583	Chile	Villarrica
1584	China	Acheng
1585	China	Altay
1586	China	Anbu
1587	China	Anda
1588	China	Anjiang
1589	China	Ankang
1590	China	Anlu
1591	China	Anqing
1592	China	Anqiu
1593	China	Anshan
1594	China	Anshun
1595	China	Anxiang
1596	China	Anyang
1597	China	Aral
1598	China	Babu
1599	China	Baicheng
1600	China	Baihe
1601	China	Baijiantan
1602	China	Baiquan
1603	China	Baishan
1604	China	Baishishan
1605	China	Baiyin
1606	China	Bamiantong
1607	China	Baoding
1608	China	Baoqing
1609	China	Baoshan
1610	China	Baotou
1611	China	Baoying
1612	China	Bayan
1613	China	Beibei
1614	China	Beichengqu
1615	China	Beidaihehaibin
1616	China	Beidao
1617	China	Beihai
1618	China	Beijing
1619	China	Beipiao
1620	China	Bengbu
1621	China	Benxi
1622	China	Bianzhuang
1623	China	Bijie
1624	China	Binhe
1625	China	Binzhou
1626	China	Bojia
1627	China	Boli
1628	China	Boshan
1629	China	Botou
1630	China	Bozhou
1631	China	Buhe
1632	China	Caidian
1633	China	Cangzhou
1634	China	Caohe
1635	China	Chaihe
1636	China	Changchun
1637	China	Changde
1638	China	Changji
1639	China	Changleng
1640	China	Changli
1641	China	Changling
1642	China	Changping
1643	China	Changqing
1644	China	Changsha
1645	China	Changtu
1646	China	Changzhi
1647	China	Changzhou
1648	China	Chaohu
1649	China	Chaoyang
1650	China	Chaozhou
1651	China	Chengde
1652	China	Chengdu
1653	China	Chenghua
1654	China	Chengyang
1655	China	Chengzhong
1656	China	Chengzihe
1657	China	Chenzhou
1658	China	Chifeng
1659	China	Chizhou
1660	China	Chonglong
1661	China	Chongqing
1662	China	Chuzhou
1663	China	Dadukou
1664	China	Dalai
1665	China	Dali
1666	China	Dalian
1667	China	Daliang
1668	China	Dalianwan
1669	China	Dandong
1670	China	Danjiangkou
1671	China	Danshui
1672	China	Daokou
1673	China	Daqing
1674	China	Dasha
1675	China	Dashiqiao
1676	China	Dashitou
1677	China	Datong
1678	China	Dawukou
1679	China	Daxing
1680	China	Daye
1681	China	Dazhong
1682	China	Dazhou
1683	China	Dehui
1684	China	Dengzhou
1685	China	Deqing
1686	China	Deyang
1687	China	Dezhou
1688	China	Dingcheng
1689	China	Dingtao
1690	China	Dingzhou
1691	China	Dongcun
1692	China	Dongdu
1693	China	Dongfeng
1694	China	Dongguan
1695	China	Donghai
1696	China	Dongkan
1697	China	Dongling
1698	China	Dongning
1699	China	Dongsheng
1700	China	Dongtai
1701	China	Dongxing
1702	China	Dongyang
1703	China	Ducheng
1704	China	Dunhua
1705	China	Duobao
1706	China	Duyun
1707	China	Encheng
1708	China	Enshi
1709	China	Erdaojiang
1710	China	Erenhot
1711	China	Ezhou
1712	China	Fangshan
1713	China	Feicheng
1714	China	Fendou
1715	China	Fengcheng
1716	China	Fenghua
1717	China	Fenghuang
1718	China	Fengkou
1719	China	Fengrun
1720	China	Fengxian
1721	China	Fengxiang
1722	China	Fenyi
1723	China	Foshan
1724	China	Fuding
1725	China	Fujin
1726	China	Fuli
1727	China	Fuling
1728	China	Fuqing
1729	China	Fushun
1730	China	Fuxin
1731	China	Fuyang
1732	China	Fuyu
1733	China	Fuyuan
1734	China	Fuzhou
1735	China	Gannan
1736	China	Gaogou
1737	China	Gaomi
1738	China	Gaoping
1739	China	Gaoyou
1740	China	Gaozhou
1741	China	Gejiu
1742	China	Genhe
1743	China	Gongchangling
1744	China	Gongzhuling
1745	China	Guangming
1746	China	Guangshui
1747	China	Guangyuan
1748	China	Guangzhou
1749	China	Guankou
1750	China	Guigang
1751	China	Guilin
1752	China	Guiping
1753	China	Guiren
1754	China	Guixi
1755	China	Guiyang
1756	China	Guli
1757	China	Guozhen
1758	China	Gushu
1759	China	Gutao
1760	China	Guye
1761	China	Haicheng
1762	China	Haikou
1763	China	Hailar
1764	China	Hailin
1765	China	Hailun
1766	China	Haimen
1767	China	Haizhou
1768	China	Hami
1769	China	Hancheng
1770	China	Hanchuan
1771	China	Handan
1772	China	Hangu
1773	China	Hangzhou
1774	China	Hanting
1775	China	Hanzhong
1776	China	Harbin
1777	China	Hebi
1778	China	Hechuan
1779	China	Hecun
1780	China	Hede
1781	China	Hefei
1782	China	Hegang
1783	China	Heihe
1784	China	Heishan
1785	China	Helong
1786	China	Hengshui
1787	China	Hengyang
1788	China	Hepingjie
1789	China	Hepo
1790	China	Heyuan
1791	China	Heze
1792	China	Hohhot
1793	China	Honggang
1794	China	Hongjiang
1795	China	Hongqiao
1796	China	Hotan
1797	China	Hoxtolgay
1798	China	Huadian
1799	China	Huaibei
1800	China	Huaicheng
1801	China	Huaidian
1802	China	Huaihua
1803	China	Huainan
1804	China	Huanan
1805	China	Huanggang
1806	China	Huangmei
1807	China	Huangnihe
1808	China	Huangpi
1809	China	Huangshan
1810	China	Huangshi
1811	China	Huangyan
1812	China	Huangzhou
1813	China	Huanren
1814	China	Huazhou
1815	China	Huicheng
1816	China	Huilong
1817	China	Huinan
1818	China	Huizhou
1819	China	Hulan
1820	China	Humen
1821	China	Hunchun
1822	China	Hushitai
1823	China	Hutang
1824	China	Huzhou
1825	China	Jagdaqi
1826	China	Jiamusi
1827	China	Jiangguanchi
1828	China	Jiangkou
1829	China	Jiangmen
1830	China	Jianguang
1831	China	Jiangyan
1832	China	Jiangyin
1833	China	Jiangyou
1834	China	Jiaojiang
1835	China	Jiaozhou
1836	China	Jiaozuo
1837	China	Jiashan
1838	China	Jiaxing
1839	China	Jiayuguan
1840	China	Jiazi
1841	China	Jidong
1842	China	Jiehu
1843	China	Jieshi
1844	China	Jieshou
1845	China	Jiexiu
1846	China	Jieyang
1847	China	Jijiang
1848	China	Jilin
1849	China	Jimo
1850	China	Jinan
1851	China	Jinchang
1852	China	Jincheng
1853	China	Jingdezhen
1854	China	Jinghong
1855	China	Jingling
1856	China	Jingmen
1857	China	Jingzhou
1858	China	Jinhua
1859	China	Jining
1860	China	Jinji
1861	China	Jinjiang
1862	China	Jinsha
1863	China	Jinshi
1864	China	Jinxiang
1865	China	Jinzhou
1866	China	Jishu
1867	China	Jishui
1868	China	Jiujiang
1869	China	Jiupu
1870	China	Jiuquan
1871	China	Jiutai
1872	China	Jixi
1873	China	Juegang
1874	China	Juye
1875	China	Kaifeng
1876	China	Kaihua
1877	China	Kaitong
1878	China	Kaiyuan
1879	China	Kangding
1880	China	Kashgar
1881	China	Kuandian
1882	China	Kuche
1883	China	Kunming
1884	China	Kunshan
1885	China	Kunyang
1886	China	Laibin
1887	China	Laiwu
1888	China	Laixi
1889	China	Laiyang
1890	China	Langfang
1891	China	Langtou
1892	China	Langxiang
1893	China	Langzhong
1894	China	Lanxi
1895	China	Lanzhou
1896	China	Laochenglu
1897	China	Laohekou
1898	China	Laojunmiao
1899	China	Lecheng
1900	China	Leiyang
1901	China	Lengshuijiang
1902	China	Lengshuitan
1903	China	Leshan
1904	China	Lhasa
1905	China	Lianghu
1906	China	Liangxiang
1907	China	Lianhe
1908	China	Lianjiang
1909	China	Lianran
1910	China	Lianshan
1911	China	Lianyuan
1912	China	Lianzhou
1913	China	Liaocheng
1914	China	Liaoyang
1915	China	Liaoyuan
1916	China	Liaozhong
1917	China	Licheng
1918	China	Lichuan
1919	China	Lijiang
1920	China	Lincheng
1921	China	Linfen
1922	China	Lingcheng
1923	China	Lingdong
1924	China	Linghai
1925	China	Lingyuan
1926	China	Linhai
1927	China	Linjiang
1928	China	Linkou
1929	China	Linping
1930	China	Linqiong
1931	China	Linqu
1932	China	Linshui
1933	China	Lintong
1934	China	Linxi
1935	China	Linyi
1936	China	Lishu
1937	China	Lishui
1938	China	Liuhe
1939	China	Liupanshui
1940	China	Longfeng
1941	China	Longgang
1942	China	Longjiang
1943	China	Longjing
1944	China	Longquan
1945	China	Loudi
1946	China	Loushanguan
1947	China	Luancheng
1948	China	Lubu
1949	China	Lucheng
1950	China	Luocheng
1951	China	Luofeng
1952	China	Luohe
1953	China	Luorong
1954	China	Luoyang
1955	China	Luqiao
1956	China	Luxu
1957	China	Maba
1958	China	Mabai
1959	China	Macheng
1960	China	Majie
1961	China	Manzhouli
1962	China	Meihekou
1963	China	Meizhou
1964	China	Mengyin
1965	China	Mentougou
1966	China	Mianyang
1967	China	Minggang
1968	China	Mingguang
1969	China	Mingshui
1970	China	Mingyue
1971	China	Minzhu
1972	China	Mishan
1973	China	Miyang
1974	China	Mizhou
1975	China	Mudanjiang
1976	China	Mudu
1977	China	Mujiayingzi
1978	China	Nagqu
1979	China	Nanchang
1980	China	Nanchong
1981	China	Nanding
1982	China	Nandu
1983	China	Nanfeng
1984	China	Nangandao
1985	China	Nangong
1986	China	Nanjing
1987	China	Nanlong
1988	China	Nanma
1989	China	Nanning
1990	China	Nanpiao
1991	China	Nanping
1992	China	Nantai
1993	China	Nantong
1994	China	Nanyang
1995	China	Nanzhou
1996	China	Nehe
1997	China	Neijiang
1998	China	Nenjiang
1999	China	Nianzishan
2000	China	Ningbo
2001	China	Ningde
2002	China	Ninghai
2003	China	Ningyang
2004	China	Ordos
2005	China	Panshan
2006	China	Panshi
2007	China	Pengcheng
2008	China	Pingdingshan
2009	China	Pingdu
2010	China	Pingliang
2011	China	Pingnan
2012	China	Pingshan
2013	China	Pingxiang
2014	China	Pingyi
2015	China	Pingyin
2016	China	Pingzhuang
2017	China	Pizhou
2018	China	Poyang
2019	China	Pucheng
2020	China	Pulandian
2021	China	Pumiao
2022	China	Puning
2023	China	Puqi
2024	China	Putian
2025	China	Puyang
2026	China	Qamdo
2027	China	Qianguo
2028	China	Qianjiang
2029	China	Qianzhou
2030	China	Qingdao
2031	China	Qinggang
2032	China	Qingnian
2033	China	Qingquan
2034	China	Qingyang
2035	China	Qingyuan
2036	China	Qingzhou
2037	China	Qinhuangdao
2038	China	Qinnan
2039	China	Qinzhou
2040	China	Qionghu
2041	China	Qiongshan
2042	China	Qiqihar
2043	China	Quanzhou
2044	China	Qufu
2045	China	Qujing
2046	China	Quzhou
2047	China	Renqiu
2048	China	Rikaze
2049	China	Rizhao
2050	China	Runing
2051	China	Salaqi
2052	China	Sanchazi
2053	China	Sanming
2054	China	Sanshui
2055	China	Sanya
2056	China	Sayibage
2057	China	Shache
2058	China	Shahecheng
2059	China	Shancheng
2060	China	Shanghai
2061	China	Shangmei
2062	China	Shangqiu
2063	China	Shangrao
2064	China	Shangyu
2065	China	Shangzhi
2066	China	Shanhaiguan
2067	China	Shanhetun
2068	China	Shanting
2069	China	Shantou
2070	China	Shanwei
2071	China	Shaoguan
2072	China	Shaowu
2073	China	Shaoxing
2074	China	Shaping
2075	China	Shashi
2076	China	Shengli
2077	China	Shenjiamen
2078	China	Shenyang
2079	China	Shenzhen
2080	China	Shiguai
2081	China	Shihezi
2082	China	Shijiazhuang
2083	China	Shilin
2084	China	Shilong
2085	China	Shima
2086	China	Shiqi
2087	China	Shiqiao
2088	China	Shitanjing
2089	China	Shiwan
2090	China	Shixing
2091	China	Shiyan
2092	China	Shizilu
2093	China	Shizuishan
2094	China	Shouguang
2095	China	Shuangcheng
2096	China	Shuangyang
2097	China	Shuangyashan
2098	China	Shulan
2099	China	Shunyi
2100	China	Siping
2101	China	Sishui
2102	China	Songjiang
2103	China	Songjianghe
2104	China	Songling
2105	China	Songyang
2106	China	Suicheng
2107	China	Suifenhe
2108	China	Suihua
2109	China	Suileng
2110	China	Suining
2111	China	Suixi
2112	China	Suizhou
2113	China	Sujiatun
2114	China	Suozhen
2115	China	Suzhou
2116	China	Tahe
2117	China	Taihe
2118	China	Taikang
2119	China	Tailai
2120	China	Taishan
2121	China	Taixing
2122	China	Taiyuan
2123	China	Taizhou
2124	China	Tanggu
2125	China	Tangjiazhuang
2126	China	Tangping
2127	China	Tangshan
2128	China	Tangzhai
2129	China	Tantou
2130	China	Taozhuang
2131	China	Tengzhou
2132	China	Tianchang
2133	China	Tianfu
2134	China	Tianjin
2135	China	Tianpeng
2136	China	Tianshui
2137	China	Tieli
2138	China	Tieling
2139	China	Tongchuan
2140	China	Tongliao
2141	China	Tongren
2142	China	Tongshan
2143	China	Tongzhou
2144	China	Tumen
2145	China	Ulanhot
2146	China	Wacheng
2147	China	Wafangdian
2148	China	Wangkui
2149	China	Wangqing
2150	China	Wanning
2151	China	Wanxian
2152	China	Weichanglu
2153	China	Weifang
2154	China	Weihai
2155	China	Weinan
2156	China	Weining
2157	China	Wenling
2158	China	Wenshang
2159	China	Wenxing
2160	China	Wenzhou
2161	China	Wuchang
2162	China	Wucheng
2163	China	Wuchuan
2164	China	Wuda
2165	China	Wuhai
2166	China	Wuhan
2167	China	Wuhu
2168	China	Wusong
2169	China	Wuwei
2170	China	Wuxi
2171	China	Wuxue
2172	China	Wuyang
2173	China	Wuzhou
2174	China	Xiamen
2175	China	Xiangtan
2176	China	Xiangxiang
2177	China	Xiangyang
2178	China	Xianju
2179	China	Xianning
2180	China	Xianshuigu
2181	China	Xiantao
2182	China	Xianyang
2183	China	Xiaogan
2184	China	Xiaolingwei
2185	China	Xiaoshan
2186	China	Xiaoshi
2187	China	Xiaoweizhai
2188	China	Xiashi
2189	China	Xiazhen
2190	China	Xiazhuang
2191	China	Xichang
2192	China	Xifeng
2193	China	Xihe
2194	China	Ximei
2195	China	Xincheng
2196	China	Xindi
2197	China	Xindian
2198	China	Xingcheng
2199	China	Xinghua
2200	China	Xinglongshan
2201	China	Xingtai
2202	China	Xinhui
2203	China	Xining
2204	China	Xinji
2205	China	Xinmin
2206	China	Xinpu
2207	China	Xinqing
2208	China	Xinshi
2209	China	Xintai
2210	China	Xinyang
2211	China	Xinyi
2212	China	Xinyu
2213	China	Xinzhi
2214	China	Xinzhou
2215	China	Xiongzhou
2216	China	Xishan
2217	China	Xiulin
2218	China	Xiuyan
2219	China	Xiuying
2220	China	Xixiang
2221	China	Xuanzhou
2222	China	Xucheng
2223	China	Xunchang
2224	China	Yakeshi
2225	China	Yancheng
2226	China	Yangchun
2227	China	Yangcun
2228	China	Yanggu
2229	China	Yangjiang
2230	China	Yangliuqing
2231	China	Yangquan
2232	China	Yangshuo
2233	China	Yangzhou
2234	China	Yanji
2235	China	Yanjiang
2236	China	Yanliang
2237	China	Yanta
2238	China	Yantai
2239	China	Yantongshan
2240	China	Yanzhou
2241	China	Yashan
2242	China	Yatou
2243	China	Yebaishou
2244	China	Yibin
2245	China	Yichang
2246	China	Yicheng
2247	China	Yichun
2248	China	Yigou
2249	China	Yilan
2250	China	Yima
2251	China	Yinchuan
2252	China	Yingbazha
2253	China	Yingchuan
2254	China	Yingkou
2255	China	Yinzhu
2256	China	Yishui
2257	China	Yiwu
2258	China	Yiyang
2259	China	Yongchuan
2260	China	Yongfeng
2261	China	Youhao
2262	China	Yuanping
2263	China	Yucheng
2264	China	Yuci
2265	China	Yudong
2266	China	Yueyang
2267	China	Yulin
2268	China	Yuncheng
2269	China	Yunfu
2270	China	Yunyang
2271	China	Yushu
2272	China	Yutan
2273	China	Yuxi
2274	China	Yuxia
2275	China	Yuyao
2276	China	Zalantun
2277	China	Zaoyang
2278	China	Zaozhuang
2279	China	Zhangjiagang
2280	China	Zhangjiajie
2281	China	Zhangjiakou
2282	China	Zhangye
2283	China	Zhangzhou
2284	China	Zhanjiang
2285	China	Zhaobaoshan
2286	China	Zhaodong
2287	China	Zhaogezhuang
2288	China	Zhaoqing
2289	China	Zhaotong
2290	China	Zhaoyuan
2291	China	Zhaozhou
2292	China	Zhengjiatun
2293	China	Zhengzhou
2294	China	Zhenjiang
2295	China	Zhenlai
2296	China	Zhenzhou
2297	China	Zhicheng
2298	China	Zhijiang
2299	China	Zhongshan
2300	China	Zhongshu
2301	China	Zhongxiang
2302	China	Zhongxing
2303	China	Zhoucheng
2304	China	Zhoucun
2305	China	Zhoukou
2306	China	Zhoushan
2307	China	Zhouzhuang
2308	China	Zhuanghe
2309	China	Zhuangyuan
2310	China	Zhuhai
2311	China	Zhuji
2312	China	Zhujiajiao
2313	China	Zhumadian
2314	China	Zhuzhou
2315	China	Zibo
2316	China	Zigong
2317	China	Zijinglu
2318	China	Zoucheng
2319	China	Zunyi
2320	Colombia	Aguachica
2321	Colombia	Aguadas
2322	Colombia	Aguazul
2323	Colombia	Andes
2324	Colombia	Anserma
2325	Colombia	Aracataca
2326	Colombia	Arauca
2327	Colombia	Arjona
2328	Colombia	Armenia
2329	Colombia	Ayapel
2330	Colombia	Baranoa
2331	Colombia	Barbosa
2332	Colombia	Barrancabermeja
2333	Colombia	Barrancas
2334	Colombia	Barranquilla
2335	Colombia	Belalcazar
2336	Colombia	Bello
2337	Colombia	Bucaramanga
2338	Colombia	Buenaventura
2339	Colombia	Buga
2340	Colombia	Caicedonia
2341	Colombia	Caldas
2342	Colombia	Cali
2343	Colombia	Campoalegre
2344	Colombia	Candelaria
2345	Colombia	Carepa
2346	Colombia	Cartagena
2347	Colombia	Cartago
2348	Colombia	Caucasia
2349	Colombia	Chaparral
2350	Colombia	Chimichagua
2351	Colombia	Circasia
2352	Colombia	Corinto
2353	Colombia	Corozal
2354	Colombia	Duitama
2355	Colombia	Envigado
2356	Colombia	Espinal
2357	Colombia	Flandes
2358	Colombia	Florencia
2359	Colombia	Florida
2360	Colombia	Floridablanca
2361	Colombia	Fonseca
2362	Colombia	Fresno
2363	Colombia	Funza
2364	Colombia	Fusagasuga
2365	Colombia	Galapa
2366	Colombia	Granada
2367	Colombia	Honda
2368	Colombia	Ipiales
2369	Colombia	Leticia
2370	Colombia	Lorica
2371	Colombia	Madrid
2372	Colombia	Maicao
2373	Colombia	Malambo
2374	Colombia	Manizales
2375	Colombia	Manzanares
2376	Colombia	Marinilla
2377	Colombia	Mariquita
2378	Colombia	Melgar
2379	Colombia	Mocoa
2380	Colombia	Montenegro
2381	Colombia	Morales
2382	Colombia	Mosquera
2383	Colombia	Neiva
2384	Colombia	Pacho
2385	Colombia	Palmira
2386	Colombia	Pamplona
2387	Colombia	Pasto
2388	Colombia	Pereira
2389	Colombia	Piedecuesta
2390	Colombia	Pitalito
2391	Colombia	Pivijay
2392	Colombia	Plato
2393	Colombia	Pradera
2394	Colombia	Quimbaya
2395	Colombia	Rionegro
2396	Colombia	Riosucio
2397	Colombia	Roldanillo
2398	Colombia	Sabanagrande
2399	Colombia	Sabanalarga
2400	Colombia	Sabaneta
2401	Colombia	Salamina
2402	Colombia	Santuario
2403	Colombia	Segovia
2404	Colombia	Sevilla
2405	Colombia	Sincelejo
2406	Colombia	Soacha
2407	Colombia	Socorro
2408	Colombia	Sogamoso
2409	Colombia	Soledad
2410	Colombia	Sucre
2411	Colombia	Tame
2412	Colombia	Tierralta
2413	Colombia	Tumaco
2414	Colombia	Tunja
2415	Colombia	Turbaco
2416	Colombia	Turbo
2417	Colombia	Urrao
2418	Colombia	Valledupar
2419	Colombia	Villanueva
2420	Colombia	Villavicencio
2421	Colombia	Villeta
2422	Colombia	Viterbo
2423	Colombia	Yarumal
2424	Colombia	Yopal
2425	Colombia	Yumbo
2426	Colombia	Zaragoza
2427	Colombia	Zarzal
2428	Comoros	Moroni
2429	Comoros	Moutsamoudou
2430	Croatia	Bjelovar
2431	Croatia	Dubrovnik
2432	Croatia	Karlovac
2433	Croatia	Koprivnica
2434	Croatia	Osijek
2435	Croatia	Pula
2436	Croatia	Rijeka
2437	Croatia	Samobor
2438	Croatia	Sesvete
2439	Croatia	Sisak
2440	Croatia	Solin
2441	Croatia	Split
2442	Croatia	Vinkovci
2443	Croatia	Virovitica
2444	Croatia	Vukovar
2445	Croatia	Zadar
2446	Croatia	Zagreb
2447	Cuba	Abreus
2448	Cuba	Alamar
2449	Cuba	Amancio
2450	Cuba	Artemisa
2451	Cuba	Banes
2452	Cuba	Baracoa
2453	Cuba	Bauta
2454	Cuba	Bayamo
2455	Cuba	Bejucal
2456	Cuba	Boyeros
2457	Cuba	Cacocum
2458	Cuba	Calimete
2459	Cuba	Campechuela
2460	Cuba	Cerro
2461	Cuba	Chambas
2462	Cuba	Cienfuegos
2463	Cuba	Cifuentes
2464	Cuba	Colombia
2465	Cuba	Condado
2466	Cuba	Contramaestre
2467	Cuba	Corralillo
2468	Cuba	Cruces
2469	Cuba	Cueto
2470	Cuba	Cumanayagua
2471	Cuba	Encrucijada
2472	Cuba	Esmeralda
2473	Cuba	Florencia
2474	Cuba	Florida
2475	Cuba	Fomento
2476	Cuba	Gibara
2477	Cuba	Guanabacoa
2478	Cuba	Guanajay
2479	Cuba	Guane
2480	Cuba	Guisa
2481	Cuba	Havana
2482	Cuba	Jaruco
2483	Cuba	Jatibonico
2484	Cuba	Jobabo
2485	Cuba	Jovellanos
2486	Cuba	Madruga
2487	Cuba	Manicaragua
2488	Cuba	Manzanillo
2489	Cuba	Mariel
2490	Cuba	Matanzas
2491	Cuba	Minas
2492	Cuba	Moa
2493	Cuba	Niquero
2494	Cuba	Nuevitas
2495	Cuba	Palmira
2496	Cuba	Perico
2497	Cuba	Placetas
2498	Cuba	Ranchuelo
2499	Cuba	Regla
2500	Cuba	Remedios
2501	Cuba	Rodas
2502	Cuba	Trinidad
2503	Cuba	Varadero
2504	Cuba	Venezuela
2505	Cuba	Vertientes
2506	Cuba	Yaguajay
2507	Cuba	Yara
2508	Curacao	Willemstad
2509	Cyprus	Famagusta
2510	Cyprus	Kyrenia
2511	Cyprus	Larnaca
2512	Cyprus	Limassol
2513	Cyprus	Nicosia
2514	Cyprus	Paphos
2515	Cyprus	Protaras
2516	Denmark	Aabenraa
2517	Denmark	Aalborg
2518	Denmark	Albertslund
2519	Denmark	Ballerup
2520	Denmark	Charlottenlund
2521	Denmark	Copenhagen
2522	Denmark	Esbjerg
2523	Denmark	Farum
2524	Denmark	Fredericia
2525	Denmark	Frederiksberg
2526	Denmark	Frederikshavn
2527	Denmark	Glostrup
2528	Denmark	Greve
2529	Denmark	Haderslev
2530	Denmark	Herning
2531	Denmark	Holstebro
2532	Denmark	Horsens
2533	Denmark	Hvidovre
2534	Denmark	Kalundborg
2535	Denmark	Kolding
2536	Denmark	Nyborg
2537	Denmark	Odense
2538	Denmark	Randers
2539	Denmark	Ringsted
2540	Denmark	Roskilde
2541	Denmark	Silkeborg
2542	Denmark	Skive
2543	Denmark	Slagelse
2544	Denmark	Svendborg
2545	Denmark	Taastrup
2546	Denmark	Vejle
2547	Denmark	Viborg
2548	Djibouti	Djibouti
2549	Djibouti	Obock
2550	Djibouti	Tadjoura
2551	Dominica	Roseau
2552	Ecuador	Ambato
2553	Ecuador	Atuntaqui
2554	Ecuador	Azogues
2555	Ecuador	Babahoyo
2556	Ecuador	Balzar
2557	Ecuador	Calceta
2558	Ecuador	Cariamanga
2559	Ecuador	Catamayo
2560	Ecuador	Cayambe
2561	Ecuador	Chone
2562	Ecuador	Cuenca
2563	Ecuador	Esmeraldas
2564	Ecuador	Gualaceo
2565	Ecuador	Guaranda
2566	Ecuador	Guayaquil
2567	Ecuador	Huaquillas
2568	Ecuador	Ibarra
2569	Ecuador	Jipijapa
2570	Ecuador	Latacunga
2571	Ecuador	Loja
2572	Ecuador	Macas
2573	Ecuador	Machachi
2574	Ecuador	Machala
2575	Ecuador	Manta
2576	Ecuador	Montalvo
2577	Ecuador	Montecristi
2578	Ecuador	Naranjal
2579	Ecuador	Naranjito
2580	Ecuador	Otavalo
2581	Ecuador	Pasaje
2582	Ecuador	Pelileo
2583	Ecuador	Playas
2584	Ecuador	Portoviejo
2585	Ecuador	Puyo
2586	Ecuador	Quevedo
2587	Ecuador	Quito
2588	Ecuador	Riobamba
2589	Ecuador	Salinas
2590	Ecuador	Sucre
2591	Ecuador	Tena
2592	Ecuador	Tutamandahostel
2593	Ecuador	Ventanas
2594	Ecuador	Vinces
2595	Ecuador	Zamora
2596	Egypt	Alexandria
2597	Egypt	Arish
2598	Egypt	Aswan
2599	Egypt	Bilbays
2600	Egypt	Cairo
2601	Egypt	Damietta
2602	Egypt	Dikirnis
2603	Egypt	Fuwwah
2604	Egypt	Hurghada
2605	Egypt	Ismailia
2606	Egypt	Juhaynah
2607	Egypt	Kousa
2608	Egypt	Luxor
2609	Egypt	Rosetta
2610	Egypt	Sohag
2611	Egypt	Suez
2612	Egypt	Tanda
2613	Egypt	Toukh
2614	Egypt	Zagazig
2615	Eritrea	Asmara
2616	Eritrea	Assab
2617	Eritrea	Barentu
2618	Eritrea	Keren
2619	Eritrea	Massawa
2620	Eritrea	Mendefera
2621	Estonia	Maardu
2622	Estonia	Narva
2623	Estonia	Rakvere
2624	Estonia	Tallinn
2625	Estonia	Tartu
2626	Estonia	Viljandi
2627	Ethiopia	Abomsa
2628	Ethiopia	Asaita
2629	Ethiopia	Axum
2630	Ethiopia	Bako
2631	Ethiopia	Bichena
2632	Ethiopia	Bishoftu
2633	Ethiopia	Bonga
2634	Ethiopia	Dodola
2635	Ethiopia	Dubti
2636	Ethiopia	Gelemso
2637	Ethiopia	Genet
2638	Ethiopia	Gimbi
2639	Ethiopia	Ginir
2640	Ethiopia	Goba
2641	Ethiopia	Gondar
2642	Ethiopia	Harar
2643	Ethiopia	Hawassa
2644	Ethiopia	Jijiga
2645	Ethiopia	Jinka
2646	Ethiopia	Kombolcha
2647	Ethiopia	Korem
2648	Ethiopia	Mekele
2649	Ethiopia	Metu
2650	Ethiopia	Mojo
2651	Ethiopia	Nejo
2652	Ethiopia	Sebeta
2653	Ethiopia	Shambu
2654	Ethiopia	Tippi
2655	Ethiopia	Waliso
2656	Ethiopia	Werota
2657	Ethiopia	Ziway
2658	Fiji	Labasa
2659	Fiji	Lautoka
2660	Fiji	Nadi
2661	Fiji	Suva
2662	Finland	Anjala
2663	Finland	Espoo
2664	Finland	Forssa
2665	Finland	Hamina
2666	Finland	Haukipudas
2667	Finland	Heinola
2668	Finland	Helsinki
2669	Finland	Hollola
2670	Finland	Hyvinge
2671	Finland	Iisalmi
2672	Finland	Imatra
2673	Finland	Jakobstad
2674	Finland	Janakkala
2675	Finland	Joensuu
2676	Finland	Kaarina
2677	Finland	Kajaani
2678	Finland	Kangasala
2679	Finland	Karhula
2680	Finland	Kemi
2681	Finland	Kerava
2682	Finland	Kirkkonummi
2683	Finland	Kokkola
2684	Finland	Korsholm
2685	Finland	Kotka
2686	Finland	Kouvola
2687	Finland	Kuopio
2688	Finland	Kuusamo
2689	Finland	Lahti
2690	Finland	Lappeenranta
2691	Finland	Laukaa
2692	Finland	Lieto
2693	Finland	Lohja
2694	Finland	Lovisa
2695	Finland	Mikkeli
2696	Finland	Nokia
2697	Finland	Oulu
2698	Finland	Pirkkala
2699	Finland	Pori
2700	Finland	Porvoo
2701	Finland	Raahe
2702	Finland	Raisio
2703	Finland	Rauma
2704	Finland	Rovaniemi
2705	Finland	Salo
2706	Finland	Savonlinna
2707	Finland	Sibbo
2708	Finland	Tampere
2709	Finland	Tornio
2710	Finland	Turku
2711	Finland	Tuusula
2712	Finland	Uusikaupunki
2713	Finland	Vaasa
2714	Finland	Valkeakoski
2715	Finland	Vantaa
2716	Finland	Varkaus
2717	Finland	Vihti
2718	France	Abbeville
2719	France	Agde
2720	France	Agen
2721	France	Ajaccio
2722	France	Albertville
2723	France	Albi
2724	France	Alfortville
2725	France	Allauch
2726	France	Amiens
2727	France	Angers
2728	France	Anglet
2729	France	Annecy
2730	France	Annemasse
2731	France	Annonay
2732	France	Antibes
2733	France	Antony
2734	France	Arcueil
2735	France	Argentan
2736	France	Argenteuil
2737	France	Arles
2738	France	Arras
2739	France	Aubagne
2740	France	Aubervilliers
2741	France	Auch
2742	France	Audincourt
2743	France	Aurillac
2744	France	Autun
2745	France	Auxerre
2746	France	Avignon
2747	France	Avion
2748	France	Avon
2749	France	Bagneux
2750	France	Bagnolet
2751	France	Balma
2752	France	Bastia
2753	France	Bayeux
2754	France	Bayonne
2755	France	Beaune
2756	France	Beauvais
2757	France	Belfort
2758	France	Berck
2759	France	Bergerac
2760	France	Bezons
2761	France	Biarritz
2762	France	Bischheim
2763	France	Blagnac
2764	France	Blanquefort
2765	France	Blois
2766	France	Bobigny
2767	France	Bondy
2768	France	Bordeaux
2769	France	Bouguenais
2770	France	Bourges
2771	France	Bourgoin
2772	France	Bressuire
2773	France	Brest
2774	France	Brignoles
2775	France	Bron
2776	France	Brunoy
2777	France	Cachan
2778	France	Caen
2779	France	Cahors
2780	France	Calais
2781	France	Cambrai
2782	France	Cannes
2783	France	Canteleu
2784	France	Carcassonne
2785	France	Carpentras
2786	France	Carquefou
2787	France	Carvin
2788	France	Castres
2789	France	Cavaillon
2790	France	Cenon
2791	France	Cergy
2792	France	Cestas
2793	France	Challans
2794	France	Chartres
2795	France	Chatou
2796	France	Chaumont
2797	France	Chaville
2798	France	Chelles
2799	France	Cholet
2800	France	Clamart
2801	France	Clichy
2802	France	Cluses
2803	France	Cognac
2804	France	Colmar
2805	France	Colombes
2806	France	Colomiers
2807	France	Concarneau
2808	France	Coulommiers
2809	France	Courbevoie
2810	France	Creil
2811	France	Croix
2812	France	Cugnaux
2813	France	Dax
2814	France	Denain
2815	France	Dieppe
2816	France	Dijon
2817	France	Dole
2818	France	Domont
2819	France	Douai
2820	France	Douarnenez
2821	France	Draguignan
2822	France	Drancy
2823	France	Draveil
2824	France	Dreux
2825	France	Dunkerque
2826	France	Eaubonne
2827	France	Elbeuf
2828	France	Ermont
2829	France	Eysines
2830	France	Firminy
2831	France	Flers
2832	France	Floirac
2833	France	Fontaine
2834	France	Fontainebleau
2835	France	Forbach
2836	France	Franconville
2837	France	Fresnes
2838	France	Frontignan
2839	France	Gagny
2840	France	Gap
2841	France	Garches
2842	France	Gardanne
2843	France	Gennevilliers
2844	France	Gentilly
2845	France	Gien
2846	France	Givors
2847	France	Gonesse
2848	France	Goussainville
2849	France	Gradignan
2850	France	Grasse
2851	France	Grenoble
2852	France	Grigny
2853	France	Guyancourt
2854	France	Haguenau
2855	France	Halluin
2856	France	Haubourdin
2857	France	Hautmont
2858	France	Hayange
2859	France	Hazebrouck
2860	France	Hem
2861	France	Herblay
2862	France	Houilles
2863	France	Illzach
2864	France	Issoire
2865	France	Istres
2866	France	Lambersart
2867	France	Landerneau
2868	France	Lanester
2869	France	Lannion
2870	France	Laon
2871	France	Lattes
2872	France	Laval
2873	France	Laxou
2874	France	Lens
2875	France	Libourne
2876	France	Lille
2877	France	Limay
2878	France	Limoges
2879	France	Lingolsheim
2880	France	Lisieux
2881	France	Lognes
2882	France	Lomme
2883	France	Longjumeau
2884	France	Loos
2885	France	Lorient
2886	France	Lormont
2887	France	Lourdes
2888	France	Louviers
2889	France	Lunel
2890	France	Lyon
2891	France	Malakoff
2892	France	Manosque
2893	France	Marignane
2894	France	Marmande
2895	France	Marseille
2896	France	Martigues
2897	France	Massy
2898	France	Maubeuge
2899	France	Mauguio
2900	France	Maurepas
2901	France	Mayenne
2902	France	Meaux
2903	France	Melun
2904	France	Menton
2905	France	Metz
2906	France	Meudon
2907	France	Meylan
2908	France	Meyzieu
2909	France	Millau
2910	France	Miramas
2911	France	Montargis
2912	France	Montauban
2913	France	Montbrison
2914	France	Montesson
2915	France	Montfermeil
2916	France	Montgeron
2917	France	Montivilliers
2918	France	Montmorency
2919	France	Montpellier
2920	France	Montreuil
2921	France	Montrouge
2922	France	Morlaix
2923	France	Mougins
2924	France	Moulins
2925	France	Mulhouse
2926	France	Muret
2927	France	Nancy
2928	France	Nanterre
2929	France	Nantes
2930	France	Narbonne
2931	France	Nevers
2932	France	Nice
2933	France	Niort
2934	France	Noisiel
2935	France	Noyon
2936	France	Octeville
2937	France	Olivet
2938	France	Orange
2939	France	Orly
2940	France	Orsay
2941	France	Orvault
2942	France	Osny
2943	France	Oullins
2944	France	Outreau
2945	France	Oyonnax
2946	France	Palaiseau
2947	France	Pamiers
2948	France	Pantin
2949	France	Paris
2950	France	Pau
2951	France	Perpignan
2952	France	Pertuis
2953	France	Pessac
2954	France	Plaisir
2955	France	Ploemeur
2956	France	Poissy
2957	France	Poitiers
2958	France	Pontarlier
2959	France	Pontivy
2960	France	Pontoise
2961	France	Puteaux
2962	France	Quimper
2963	France	Rambouillet
2964	France	Reims
2965	France	Rennes
2966	France	Riom
2967	France	Roanne
2968	France	Rochefort
2969	France	Rodez
2970	France	Romainville
2971	France	Ronchin
2972	France	Roubaix
2973	France	Rouen
2974	France	Royan
2975	France	Saintes
2976	France	Sallanches
2977	France	Sannois
2978	France	Saran
2979	France	Sarcelles
2980	France	Sarreguemines
2981	France	Sartrouville
2982	France	Saumur
2983	France	Sceaux
2984	France	Schiltigheim
2985	France	Sedan
2986	France	Senlis
2987	France	Sens
2988	France	Sevran
2989	France	Seynod
2990	France	Soissons
2991	France	Sorgues
2992	France	Stains
2993	France	Strasbourg
2994	France	Suresnes
2995	France	Talence
2996	France	Tarbes
2997	France	Taverny
2998	France	Tergnier
2999	France	Thiais
3000	France	Thionville
3001	France	Torcy
3002	France	Toul
3003	France	Toulon
3004	France	Toulouse
3005	France	Tourcoing
3006	France	Tourlaville
3007	France	Tournefeuille
3008	France	Tours
3009	France	Trappes
3010	France	Troyes
3011	France	Tulle
3012	France	Valence
3013	France	Valenciennes
3014	France	Vallauris
3015	France	Vannes
3016	France	Vanves
3017	France	Vence
3018	France	Verdun
3019	France	Vernon
3020	France	Versailles
3021	France	Vertou
3022	France	Vesoul
3023	France	Vichy
3024	France	Vienne
3025	France	Vierzon
3026	France	Villefontaine
3027	France	Villejuif
3028	France	Villemomble
3029	France	Villeparisis
3030	France	Villepinte
3031	France	Villeurbanne
3032	France	Vincennes
3033	France	Viroflay
3034	France	Vitrolles
3035	France	Voiron
3036	France	Wasquehal
3037	France	Wattrelos
3038	France	Wittenheim
3039	France	Yerres
3040	France	Yutz
3041	Gabon	Franceville
3042	Gabon	Koulamoutou
3043	Gabon	Libreville
3044	Gabon	Moanda
3045	Gabon	Mouila
3046	Gabon	Oyem
3047	Gabon	Tchibanga
3048	Gambia	Bakau
3049	Gambia	Banjul
3050	Gambia	Brikama
3051	Gambia	Farafenni
3052	Gambia	Lamin
3053	Gambia	Sukuta
3054	Georgia	Akhaltsikhe
3055	Georgia	Batumi
3056	Georgia	Gori
3057	Georgia	Khashuri
3058	Georgia	Kobuleti
3059	Georgia	Kutaisi
3060	Georgia	Marneuli
3061	Georgia	Ozurgeti
3062	Georgia	Samtredia
3063	Georgia	Sokhumi
3064	Georgia	Tbilisi
3065	Georgia	Telavi
3066	Georgia	Tsqaltubo
3067	Georgia	Zugdidi
3068	Germany	Aachen
3069	Germany	Aalen
3070	Germany	Achern
3071	Germany	Achim
3072	Germany	Adlershof
3073	Germany	Ahaus
3074	Germany	Ahlen
3075	Germany	Ahrensburg
3076	Germany	Aichach
3077	Germany	Albstadt
3078	Germany	Alfeld
3079	Germany	Alfter
3080	Germany	Alsdorf
3081	Germany	Alsfeld
3082	Germany	Altdorf
3083	Germany	Altena
3084	Germany	Altenburg
3085	Germany	Altglienicke
3086	Germany	Altona
3087	Germany	Alzey
3088	Germany	Amberg
3089	Germany	Andernach
3090	Germany	Ansbach
3091	Germany	Apolda
3092	Germany	Arnsberg
3093	Germany	Arnstadt
3094	Germany	Aschaffenburg
3095	Germany	Ascheberg
3096	Germany	Aschersleben
3097	Germany	Attendorn
3098	Germany	Aue
3099	Germany	Auerbach
3100	Germany	Augsburg
3101	Germany	Aurich
3102	Germany	Babenhausen
3103	Germany	Backnang
3104	Germany	Baesweiler
3105	Germany	Baiersbronn
3106	Germany	Balingen
3107	Germany	Bamberg
3108	Germany	Bassum
3109	Germany	Baumschulenweg
3110	Germany	Baunatal
3111	Germany	Bautzen
3112	Germany	Bayreuth
3113	Germany	Beckingen
3114	Germany	Beckum
3115	Germany	Bedburg
3116	Germany	Bendorf
3117	Germany	Bensheim
3118	Germany	Bergedorf
3119	Germany	Bergheim
3120	Germany	Bergkamen
3121	Germany	Bergneustadt
3122	Germany	Berlin
3123	Germany	Bernburg
3124	Germany	Beverungen
3125	Germany	Bexbach
3126	Germany	Bielefeld
3127	Germany	Biesdorf
3128	Germany	Bilderstoeckchen
3129	Germany	Blankenburg
3130	Germany	Blieskastel
3131	Germany	Blomberg
3132	Germany	Bobingen
3133	Germany	Bocholt
3134	Germany	Bochum
3135	Germany	Bogenhausen
3136	Germany	Bonn
3137	Germany	Boppard
3138	Germany	Borken
3139	Germany	Borna
3140	Germany	Bornheim
3141	Germany	Bottrop
3142	Germany	Brackenheim
3143	Germany	Brakel
3144	Germany	Bramsche
3145	Germany	Braunschweig
3146	Germany	Bremen
3147	Germany	Bremerhaven
3148	Germany	Bretten
3149	Germany	Brilon
3150	Germany	Britz
3151	Germany	Bruchsal
3152	Germany	Buchen
3153	Germany	Buckow
3154	Germany	Burgdorf
3155	Germany	Burghausen
3156	Germany	Burscheid
3157	Germany	Butzbach
3158	Germany	Buxtehude
3159	Germany	Calw
3160	Germany	Celle
3161	Germany	Cham
3162	Germany	Charlottenburg
3163	Germany	Chemnitz
3164	Germany	Cloppenburg
3165	Germany	Coburg
3166	Germany	Coesfeld
3167	Germany	Coswig
3168	Germany	Cottbus
3169	Germany	Crailsheim
3170	Germany	Crimmitschau
3171	Germany	Cuxhaven
3172	Germany	Dachau
3173	Germany	Dahlem
3174	Germany	Damme
3175	Germany	Darmstadt
3176	Germany	Datteln
3177	Germany	Deggendorf
3178	Germany	Delitzsch
3179	Germany	Delmenhorst
3180	Germany	Dessau
3181	Germany	Detmold
3182	Germany	Deutz
3183	Germany	Dieburg
3184	Germany	Diepholz
3185	Germany	Dietzenbach
3186	Germany	Dillenburg
3187	Germany	Dillingen
3188	Germany	Dingolfing
3189	Germany	Dinslaken
3190	Germany	Ditzingen
3191	Germany	Donaueschingen
3192	Germany	Dormagen
3193	Germany	Dorsten
3194	Germany	Dortmund
3195	Germany	Dreieich
3196	Germany	Drensteinfurt
3197	Germany	Dresden
3198	Germany	Duderstadt
3199	Germany	Duisburg
3200	Germany	Eberbach
3201	Germany	Eberswalde
3202	Germany	Edewecht
3203	Germany	Ehingen
3204	Germany	Eidelstedt
3205	Germany	Eilenburg
3206	Germany	Einbeck
3207	Germany	Eisenach
3208	Germany	Eislingen
3209	Germany	Eitorf
3210	Germany	Ellwangen
3211	Germany	Elmshorn
3212	Germany	Elsdorf
3213	Germany	Eltville
3214	Germany	Emden
3215	Germany	Emmendingen
3216	Germany	Emmerich
3217	Germany	Emsdetten
3218	Germany	Engelskirchen
3219	Germany	Enger
3220	Germany	Ennepetal
3221	Germany	Ennigerloh
3222	Germany	Eppelborn
3223	Germany	Eppingen
3224	Germany	Erding
3225	Germany	Erftstadt
3226	Germany	Erfurt
3227	Germany	Erkelenz
3228	Germany	Erkrath
3229	Germany	Erlangen
3230	Germany	Erwitte
3231	Germany	Eschborn
3232	Germany	Eschwege
3233	Germany	Eschweiler
3234	Germany	Espelkamp
3235	Germany	Essen
3236	Germany	Esslingen
3237	Germany	Ettlingen
3238	Germany	Euskirchen
3239	Germany	Eutin
3240	Germany	Falkensee
3241	Germany	Fellbach
3242	Germany	Fennpfuhl
3243	Germany	Filderstadt
3244	Germany	Finnentrop
3245	Germany	Finsterwalde
3246	Germany	Flensburg
3247	Germany	Forchheim
3248	Germany	Forst
3249	Germany	Frankenberg
3250	Germany	Frankenthal
3251	Germany	Frechen
3252	Germany	Freiberg
3253	Germany	Freiburg
3254	Germany	Freilassing
3255	Germany	Freising
3256	Germany	Freital
3257	Germany	Freudenberg
3258	Germany	Freudenstadt
3259	Germany	Friedberg
3260	Germany	Friedenau
3261	Germany	Friedrichsdorf
3262	Germany	Friedrichsfelde
3263	Germany	Friedrichshafen
3264	Germany	Friedrichshagen
3265	Germany	Friedrichshain
3266	Germany	Friesoythe
3267	Germany	Frohnau
3268	Germany	Fulda
3269	Germany	Gaggenau
3270	Germany	Ganderkesee
3271	Germany	Garbsen
3272	Germany	Gartenstadt
3273	Germany	Gauting
3274	Germany	Geesthacht
3275	Germany	Geilenkirchen
3276	Germany	Geldern
3277	Germany	Gelnhausen
3278	Germany	Gelsenkirchen
3279	Germany	Gera
3280	Germany	Geretsried
3281	Germany	Gerlingen
3282	Germany	Germering
3283	Germany	Germersheim
3284	Germany	Gersthofen
3285	Germany	Gescher
3286	Germany	Geseke
3287	Germany	Gesundbrunnen
3288	Germany	Gevelsberg
3289	Germany	Gifhorn
3290	Germany	Gilching
3291	Germany	Gladbeck
3292	Germany	Glauchau
3293	Germany	Glinde
3294	Germany	Goch
3295	Germany	Goslar
3296	Germany	Gotha
3297	Germany	Grefrath
3298	Germany	Greifswald
3299	Germany	Greiz
3300	Germany	Greven
3301	Germany	Grevenbroich
3302	Germany	Griesheim
3303	Germany	Grimma
3304	Germany	Gronau
3305	Germany	Gropiusstadt
3306	Germany	Guben
3307	Germany	Gummersbach
3308	Germany	Gunzenhausen
3309	Germany	Haan
3310	Germany	Haar
3311	Germany	Hagen
3312	Germany	Haiger
3313	Germany	Hakenfelde
3314	Germany	Halberstadt
3315	Germany	Halle
3316	Germany	Halstenbek
3317	Germany	Haltern
3318	Germany	Halver
3319	Germany	Hamburg
3320	Germany	Hameln
3321	Germany	Hamm
3322	Germany	Hamminkeln
3323	Germany	Hannover
3324	Germany	Harburg
3325	Germany	Haren
3326	Germany	Harsewinkel
3327	Germany	Haselbachtal
3328	Germany	Hattersheim
3329	Germany	Hattingen
3330	Germany	Hechingen
3331	Germany	Heide
3332	Germany	Heidelberg
3333	Germany	Heidenau
3334	Germany	Heilbronn
3335	Germany	Heiligenhaus
3336	Germany	Heiligensee
3337	Germany	Heinsberg
3338	Germany	Hellersdorf
3339	Germany	Helmstedt
3340	Germany	Hemer
3341	Germany	Hemmingen
3342	Germany	Hennef
3343	Germany	Hennigsdorf
3344	Germany	Herborn
3345	Germany	Herdecke
3346	Germany	Herford
3347	Germany	Hermsdorf
3348	Germany	Herne
3349	Germany	Herrenberg
3350	Germany	Herten
3351	Germany	Herzogenaurach
3352	Germany	Herzogenrath
3353	Germany	Hettstedt
3354	Germany	Heusenstamm
3355	Germany	Heusweiler
3356	Germany	Hiddenhausen
3357	Germany	Hilchenbach
3358	Germany	Hilden
3359	Germany	Hildesheim
3360	Germany	Hille
3361	Germany	Hochfeld
3362	Germany	Hockenheim
3363	Germany	Hof
3364	Germany	Hofgeismar
3365	Germany	Holzkirchen
3366	Germany	Holzminden
3367	Germany	Holzwickede
3368	Germany	Homburg
3369	Germany	Hoyerswerda
3370	Germany	Hude
3371	Germany	Humboldtkolonie
3372	Germany	Husum
3373	Germany	Idstein
3374	Germany	Illertissen
3375	Germany	Illingen
3376	Germany	Ilmenau
3377	Germany	Ingolstadt
3378	Germany	Iserlohn
3379	Germany	Itzehoe
3380	Germany	Jena
3381	Germany	Johannisthal
3382	Germany	Kaarst
3383	Germany	Kaiserslautern
3384	Germany	Kalk
3385	Germany	Kaltenkirchen
3386	Germany	Kamen
3387	Germany	Kamenz
3388	Germany	Karben
3389	Germany	Karlsfeld
3390	Germany	Karlshorst
3391	Germany	Karlsruhe
3392	Germany	Karlstadt
3393	Germany	Karow
3394	Germany	Kassel
3395	Germany	Kaufbeuren
3396	Germany	Kaulsdorf
3397	Germany	Kehl
3398	Germany	Kelheim
3399	Germany	Kempen
3400	Germany	Kerpen
3401	Germany	Kevelaer
3402	Germany	Kiel
3403	Germany	Kierspe
3404	Germany	Kirchhain
3405	Germany	Kirchlengern
3406	Germany	Kitzingen
3407	Germany	Kleinmachnow
3408	Germany	Kleve
3409	Germany	Koblenz
3410	Germany	Kolbermoor
3411	Germany	Konstanz
3412	Germany	Konz
3413	Germany	Korbach
3414	Germany	Korntal
3415	Germany	Kornwestheim
3416	Germany	Korschenbroich
3417	Germany	Krefeld
3418	Germany	Kreuzau
3419	Germany	Kreuzberg
3420	Germany	Kreuztal
3421	Germany	Kronach
3422	Germany	Kronberg
3423	Germany	Kulmbach
3424	Germany	Laatzen
3425	Germany	Lage
3426	Germany	Lahnstein
3427	Germany	Lahr
3428	Germany	Lampertheim
3429	Germany	Landshut
3430	Germany	Langen
3431	Germany	Langenfeld
3432	Germany	Langenhagen
3433	Germany	Langenhorn
3434	Germany	Lankwitz
3435	Germany	Lauchhammer
3436	Germany	Laupheim
3437	Germany	Lebach
3438	Germany	Leer
3439	Germany	Lehrte
3440	Germany	Leichlingen
3441	Germany	Leimen
3442	Germany	Leipzig
3443	Germany	Lemgo
3444	Germany	Lengerich
3445	Germany	Lennestadt
3446	Germany	Leonberg
3447	Germany	Leverkusen
3448	Germany	Lichtenberg
3449	Germany	Lichtenfels
3450	Germany	Lichtenrade
3451	Germany	Lichterfelde
3452	Germany	Lilienthal
3453	Germany	Lindau
3454	Germany	Lindlar
3455	Germany	Lingen
3456	Germany	Lippstadt
3457	Germany	Lohmar
3458	Germany	Lohne
3459	Germany	Losheim
3460	Germany	Loxstedt
3461	Germany	Luckenwalde
3462	Germany	Ludwigsburg
3463	Germany	Ludwigsfelde
3464	Germany	Magdeburg
3465	Germany	Mahlsdorf
3466	Germany	Maintal
3467	Germany	Mainz
3468	Germany	Mannheim
3469	Germany	Mariendorf
3470	Germany	Marienfelde
3471	Germany	Marienthal
3472	Germany	Markkleeberg
3473	Germany	Marktoberdorf
3474	Germany	Marktredwitz
3475	Germany	Marl
3476	Germany	Marsberg
3477	Germany	Marzahn
3478	Germany	Mayen
3479	Germany	Mechernich
3480	Germany	Meckenheim
3481	Germany	Meerane
3482	Germany	Meerbusch
3483	Germany	Meiderich
3484	Germany	Meinerzhagen
3485	Germany	Meiningen
3486	Germany	Meissen
3487	Germany	Melle
3488	Germany	Memmingen
3489	Germany	Menden
3490	Germany	Meppen
3491	Germany	Merseburg
3492	Germany	Merzig
3493	Germany	Meschede
3494	Germany	Mettmann
3495	Germany	Metzingen
3496	Germany	Michelstadt
3497	Germany	Minden
3498	Germany	Mitte
3499	Germany	Mittweida
3500	Germany	Moabit
3501	Germany	Moers
3502	Germany	Moosburg
3503	Germany	Mosbach
3504	Germany	Much
3505	Germany	Munich
3506	Germany	Munster
3507	Germany	Nagold
3508	Germany	Nauen
3509	Germany	Naumburg
3510	Germany	Neckarsulm
3511	Germany	Netphen
3512	Germany	Nettetal
3513	Germany	Neubrandenburg
3514	Germany	Neuehrenfeld
3515	Germany	Neuenhagen
3516	Germany	Neunkirchen
3517	Germany	Neuruppin
3518	Germany	Neuss
3519	Germany	Neustadt
3520	Germany	Neustrelitz
3521	Germany	Neuwied
3522	Germany	Nidda
3523	Germany	Nidderau
3524	Germany	Niederkassel
3525	Germany	Niederrad
3526	Germany	Nienburg
3527	Germany	Nikolassee
3528	Germany	Nippes
3529	Germany	Norden
3530	Germany	Nordenham
3531	Germany	Norderstedt
3532	Germany	Nordhausen
3533	Germany	Nordhorn
3534	Germany	Northeim
3535	Germany	Nottuln
3536	Germany	Oberasbach
3537	Germany	Oberhausen
3538	Germany	Oberkirch
3539	Germany	Obertshausen
3540	Germany	Oberursel
3541	Germany	Ochtrup
3542	Germany	Odenthal
3543	Germany	Oelde
3544	Germany	Oerlinghausen
3545	Germany	Offenbach
3546	Germany	Offenburg
3547	Germany	Olching
3548	Germany	Oldenburg
3549	Germany	Olpe
3550	Germany	Olsberg
3551	Germany	Opladen
3552	Germany	Oranienburg
3553	Germany	Oschatz
3554	Germany	Oschersleben
3555	Germany	Ostfildern
3556	Germany	Ottobrunn
3557	Germany	Ottweiler
3558	Germany	Overath
3559	Germany	Oyten
3560	Germany	Paderborn
3561	Germany	Pankow
3562	Germany	Papenburg
3563	Germany	Parchim
3564	Germany	Pasing
3565	Germany	Passau
3566	Germany	Peine
3567	Germany	Penzberg
3568	Germany	Petershagen
3569	Germany	Pforzheim
3570	Germany	Pfullingen
3571	Germany	Pfungstadt
3572	Germany	Pinneberg
3573	Germany	Pirmasens
3574	Germany	Pirna
3575	Germany	Plauen
3576	Germany	Plettenberg
3577	Germany	Potsdam
3578	Germany	Preetz
3579	Germany	Prenzlau
3580	Germany	Puchheim
3581	Germany	Pulheim
3582	Germany	Quedlinburg
3583	Germany	Quickborn
3584	Germany	Radeberg
3585	Germany	Radebeul
3586	Germany	Radevormwald
3587	Germany	Rahden
3588	Germany	Rastatt
3589	Germany	Rastede
3590	Germany	Ratekau
3591	Germany	Rathenow
3592	Germany	Ratingen
3593	Germany	Ravensburg
3594	Germany	Recklinghausen
3595	Germany	Rees
3596	Germany	Regensburg
3597	Germany	Reinbek
3598	Germany	Reinheim
3599	Germany	Reinickendorf
3600	Germany	Remagen
3601	Germany	Remscheid
3602	Germany	Rendsburg
3603	Germany	Renningen
3604	Germany	Reutlingen
3605	Germany	Rhede
3606	Germany	Rheinbach
3607	Germany	Rheinberg
3608	Germany	Rheine
3609	Germany	Rheinstetten
3610	Germany	Riedstadt
3611	Germany	Riegelsberg
3612	Germany	Riesa
3613	Germany	Rietberg
3614	Germany	Rinteln
3615	Germany	Rodgau
3616	Germany	Ronnenberg
3617	Germany	Rosenheim
3618	Germany	Rostock
3619	Germany	Rotenburg
3620	Germany	Roth
3621	Germany	Rottenburg
3622	Germany	Rottweil
3623	Germany	Rudolstadt
3624	Germany	Rudow
3625	Germany	Rummelsburg
3626	Germany	Saalfeld
3627	Germany	Saarlouis
3628	Germany	Salzkotten
3629	Germany	Salzwedel
3630	Germany	Sangerhausen
3631	Germany	Sarstedt
3632	Germany	Sasel
3633	Germany	Saulgau
3634	Germany	Schifferstadt
3635	Germany	Schiffweiler
3636	Germany	Schkeuditz
3637	Germany	Schleswig
3638	Germany	Schmalkalden
3639	Germany	Schmallenberg
3640	Germany	Schmargendorf
3641	Germany	Schmelz
3642	Germany	Schneeberg
3643	Germany	Schneverdingen
3644	Germany	Schopfheim
3645	Germany	Schorndorf
3646	Germany	Schortens
3647	Germany	Schramberg
3648	Germany	Schrobenhausen
3649	Germany	Schwabach
3650	Germany	Schwalbach
3651	Germany	Schwalmstadt
3652	Germany	Schwalmtal
3653	Germany	Schwanewede
3654	Germany	Schwarzenberg
3655	Germany	Schweinfurt
3656	Germany	Schwelm
3657	Germany	Schwerin
3658	Germany	Schwerte
3659	Germany	Schwetzingen
3660	Germany	Seelze
3661	Germany	Seesen
3662	Germany	Seevetal
3663	Germany	Sehnde
3664	Germany	Selb
3665	Germany	Seligenstadt
3666	Germany	Selm
3667	Germany	Senden
3668	Germany	Senftenberg
3669	Germany	Siegburg
3670	Germany	Siegen
3671	Germany	Sigmaringen
3672	Germany	Simmerath
3673	Germany	Sindelfingen
3674	Germany	Singen
3675	Germany	Sinsheim
3676	Germany	Sinzig
3677	Germany	Soest
3678	Germany	Solingen
3679	Germany	Soltau
3680	Germany	Sondershausen
3681	Germany	Sonneberg
3682	Germany	Sonthofen
3683	Germany	Spandau
3684	Germany	Spenge
3685	Germany	Speyer
3686	Germany	Spremberg
3687	Germany	Springe
3688	Germany	Staaken
3689	Germany	Stade
3690	Germany	Stadtallendorf
3691	Germany	Stadthagen
3692	Germany	Stadtlohn
3693	Germany	Starnberg
3694	Germany	Steglitz
3695	Germany	Steilshoop
3696	Germany	Steinfurt
3697	Germany	Steinhagen
3698	Germany	Stellingen
3699	Germany	Stendal
3700	Germany	Stockach
3701	Germany	Stockelsdorf
3702	Germany	Stolberg
3703	Germany	Straelen
3704	Germany	Stralsund
3705	Germany	Straubing
3706	Germany	Strausberg
3707	Germany	Stuhr
3708	Germany	Stuttgart
3709	Germany	Suhl
3710	Germany	Sulzbach
3711	Germany	Sundern
3712	Germany	Syke
3713	Germany	Taufkirchen
3714	Germany	Taunusstein
3715	Germany	Tegel
3716	Germany	Telgte
3717	Germany	Teltow
3718	Germany	Tempelhof
3719	Germany	Templin
3720	Germany	Tettnang
3721	Germany	Torgau
3722	Germany	Traunreut
3723	Germany	Traunstein
3724	Germany	Trier
3725	Germany	Troisdorf
3726	Germany	Trossingen
3727	Germany	Tuttlingen
3728	Germany	Uelzen
3729	Germany	Uetersen
3730	Germany	Ulm
3731	Germany	Unna
3732	Germany	Unterhaching
3733	Germany	Unterkrozingen
3734	Germany	Uslar
3735	Germany	Varel
3736	Germany	Vaterstetten
3737	Germany	Vechelde
3738	Germany	Vechta
3739	Germany	Velbert
3740	Germany	Vellmar
3741	Germany	Verden
3742	Germany	Verl
3743	Germany	Versmold
3744	Germany	Viernheim
3745	Germany	Viersen
3746	Germany	Vilshofen
3747	Germany	Vlotho
3748	Germany	Voerde
3749	Germany	Vreden
3750	Germany	Wachtberg
3751	Germany	Wadern
3752	Germany	Wadgassen
3753	Germany	Waiblingen
3754	Germany	Waldkirch
3755	Germany	Waldkraiburg
3756	Germany	Wallenhorst
3757	Germany	Walsrode
3758	Germany	Waltrop
3759	Germany	Wandlitz
3760	Germany	Wandsbek
3761	Germany	Warburg
3762	Germany	Wardenburg
3763	Germany	Waren
3764	Germany	Warendorf
3765	Germany	Warstein
3766	Germany	Wassenberg
3767	Germany	Wedding
3768	Germany	Wedel
3769	Germany	Weener
3770	Germany	Wegberg
3771	Germany	Weiden
3772	Germany	Weilerswist
3773	Germany	Weilheim
3774	Germany	Weimar
3775	Germany	Weingarten
3776	Germany	Weinheim
3777	Germany	Weiterstadt
3778	Germany	Wendelstein
3779	Germany	Wenden
3780	Germany	Werdau
3781	Germany	Werder
3782	Germany	Werdohl
3783	Germany	Werl
3784	Germany	Wermelskirchen
3785	Germany	Werne
3786	Germany	Wernigerode
3787	Germany	Wertheim
3788	Germany	Wesel
3789	Germany	Wesseling
3790	Germany	Westend
3791	Germany	Westerstede
3792	Germany	Wetzlar
3793	Germany	Wiehl
3794	Germany	Wiesbaden
3795	Germany	Wiesloch
3796	Germany	Wildeshausen
3797	Germany	Wilhelmshaven
3798	Germany	Wilhelmstadt
3799	Germany	Willich
3800	Germany	Wilmersdorf
3801	Germany	Wilnsdorf
3802	Germany	Winnenden
3803	Germany	Winsen
3804	Germany	Winterhude
3805	Germany	Wismar
3806	Germany	Witten
3807	Germany	Wittenau
3808	Germany	Wittenberge
3809	Germany	Wittlich
3810	Germany	Wittmund
3811	Germany	Wittstock
3812	Germany	Witzenhausen
3813	Germany	Wolfen
3814	Germany	Wolfratshausen
3815	Germany	Wolfsburg
3816	Germany	Worms
3817	Germany	Wunstorf
3818	Germany	Wuppertal
3819	Germany	Wurzen
3820	Germany	Xanten
3821	Germany	Zehlendorf
3822	Germany	Zeitz
3823	Germany	Zerbst
3824	Germany	Zirndorf
3825	Germany	Zittau
3826	Germany	Zossen
3827	Germany	Zulpich
3828	Germany	Zwickau
3829	Ghana	Aburi
3830	Ghana	Accra
3831	Ghana	Achiaman
3832	Ghana	Agogo
3833	Ghana	Akwatia
3834	Ghana	Anloga
3835	Ghana	Apam
3836	Ghana	Asamankese
3837	Ghana	Axim
3838	Ghana	Bawku
3839	Ghana	Begoro
3840	Ghana	Berekum
3841	Ghana	Bibiani
3842	Ghana	Bolgatanga
3843	Ghana	Dome
3844	Ghana	Dunkwa
3845	Ghana	Ejura
3846	Ghana	Elmina
3847	Ghana	Foso
3848	Ghana	Gbawe
3849	Ghana	Ho
3850	Ghana	Hohoe
3851	Ghana	Kasoa
3852	Ghana	Keta
3853	Ghana	Kintampo
3854	Ghana	Koforidua
3855	Ghana	Konongo
3856	Ghana	Kpandu
3857	Ghana	Kumasi
3858	Ghana	Mampong
3859	Ghana	Navrongo
3860	Ghana	Nkawkaw
3861	Ghana	Nsawam
3862	Ghana	Nungua
3863	Ghana	Obuasi
3864	Ghana	Prestea
3865	Ghana	Salaga
3866	Ghana	Saltpond
3867	Ghana	Savelugu
3868	Ghana	Suhum
3869	Ghana	Sunyani
3870	Ghana	Swedru
3871	Ghana	Tafo
3872	Ghana	Takoradi
3873	Ghana	Tamale
3874	Ghana	Tarkwa
3875	Ghana	Techiman
3876	Ghana	Tema
3877	Ghana	Wa
3878	Ghana	Wenchi
3879	Ghana	Winneba
3880	Ghana	Yendi
3881	Gibraltar	Gibraltar
3882	Greece	Athens
3883	Greece	Chios
3884	Greece	Corfu
3885	Greece	Kos
3886	Greece	Piraeus
3887	Greece	Rethymno
3888	Greece	Vrilissia
3889	Greenland	Nuuk
3890	Guatemala	Alotenango
3891	Guatemala	Barberena
3892	Guatemala	Cantel
3893	Guatemala	Chicacao
3894	Guatemala	Chichicastenango
3895	Guatemala	Chimaltenango
3896	Guatemala	Chinautla
3897	Guatemala	Chiquimula
3898	Guatemala	Chisec
3899	Guatemala	Coatepeque
3900	Guatemala	Colomba
3901	Guatemala	Comalapa
3902	Guatemala	Comitancillo
3903	Guatemala	Cuilapa
3904	Guatemala	Escuintla
3905	Guatemala	Esquipulas
3906	Guatemala	Flores
3907	Guatemala	Fraijanes
3908	Guatemala	Huehuetenango
3909	Guatemala	Jacaltenango
3910	Guatemala	Jalapa
3911	Guatemala	Jocotenango
3912	Guatemala	Jutiapa
3913	Guatemala	Mazatenango
3914	Guatemala	Mixco
3915	Guatemala	Momostenango
3916	Guatemala	Morales
3917	Guatemala	Nebaj
3918	Guatemala	Ostuncalco
3919	Guatemala	Palencia
3920	Guatemala	Petapa
3921	Guatemala	Quetzaltenango
3922	Guatemala	Retalhuleu
3923	Guatemala	Sanarate
3924	Guatemala	Sumpango
3925	Guatemala	Tiquisate
3926	Guatemala	Zacapa
3927	Guinea	Camayenne
3928	Guinea	Conakry
3929	Guinea	Coyah
3930	Guinea	Fria
3931	Guinea	Gueckedou
3932	Guinea	Kamsar
3933	Guinea	Kankan
3934	Guinea	Kindia
3935	Guinea	Kissidougou
3936	Guinea	Macenta
3937	Guinea	Mamou
3938	Guinea	Pita
3939	Guinea	Siguiri
3940	Guyana	Georgetown
3941	Guyana	Linden
3942	Haiti	Carrefour
3943	Haiti	Gonayiv
3944	Haiti	Grangwav
3945	Haiti	Gressier
3946	Haiti	Hinche
3947	Haiti	Jacmel
3948	Haiti	Kenscoff
3949	Haiti	Lenbe
3950	Haiti	Okap
3951	Haiti	Thomazeau
3952	Haiti	Tigwav
3953	Haiti	Verrettes
3954	Honduras	Choloma
3955	Honduras	Comayagua
3956	Honduras	Juticalpa
3957	Honduras	Olanchito
3958	Honduras	Potrerillos
3959	Honduras	Siguatepeque
3960	Honduras	Tegucigalpa
3961	Honduras	Tela
3962	Honduras	Tocoa
3963	Honduras	Villanueva
3964	Honduras	Yoro
3965	Hungary	Abony
3966	Hungary	Ajka
3967	Hungary	Baja
3968	Hungary	Balassagyarmat
3969	Hungary	Budapest
3970	Hungary	Dabas
3971	Hungary	Debrecen
3972	Hungary	Dunaharaszti
3973	Hungary	Dunakeszi
3974	Hungary	Eger
3975	Hungary	Esztergom
3976	Hungary	Gyula
3977	Hungary	Hatvan
3978	Hungary	Kalocsa
3979	Hungary	Karcag
3980	Hungary	Kazincbarcika
3981	Hungary	Keszthely
3982	Hungary	Kiskunhalas
3983	Hungary	Miskolc
3984	Hungary	Monor
3985	Hungary	Nagykanizsa
3986	Hungary	Paks
3987	Hungary	Sopron
3988	Hungary	Szarvas
3989	Hungary	Szeged
3990	Hungary	Szentendre
3991	Hungary	Szentes
3992	Hungary	Szolnok
3993	Hungary	Szombathely
3994	Hungary	Tapolca
3995	Hungary	Tata
3996	Hungary	Zalaegerszeg
3997	Iceland	Akureyri
3998	India	Abohar
3999	India	Achalpur
4000	India	Achhnera
4001	India	Addanki
4002	India	Adirampattinam
4003	India	Adra
4004	India	Afzalgarh
4005	India	Afzalpur
4006	India	Agar
4007	India	Agartala
4008	India	Ahmadnagar
4009	India	Ahmadpur
4010	India	Ahmedabad
4011	India	Ahraura
4012	India	Airoli
4013	India	Aistala
4014	India	Aizawl
4015	India	Ajmer
4016	India	Ajodhya
4017	India	Ajra
4018	India	Akalkot
4019	India	Akaltara
4020	India	Akbarpur
4021	India	Akkarampalle
4022	India	Aklera
4023	India	Akola
4024	India	Akot
4025	India	Aland
4026	India	Alandi
4027	India	Alandur
4028	India	Alleppey
4029	India	Almora
4030	India	Along
4031	India	Alot
4032	India	Aluva
4033	India	Alwar
4034	India	Amalner
4035	India	Amarpur
4036	India	Ambad
4037	India	Ambasamudram
4038	India	Ambur
4039	India	Amet
4040	India	Amla
4041	India	Amod
4042	India	Amreli
4043	India	Amritsar
4044	India	Amroha
4045	India	Amroli
4046	India	Anaimalai
4047	India	Anandpur
4048	India	Anantapur
4049	India	Anantnag
4050	India	Andol
4051	India	Anekal
4052	India	Angul
4053	India	Anjad
4054	India	Anjangaon
4055	India	Ankleshwar
4056	India	Annigeri
4057	India	Annur
4058	India	Anshing
4059	India	Anta
4060	India	Anthiyur
4061	India	Aonla
4062	India	Arakkonam
4063	India	Arang
4064	India	Arcot
4065	India	Aroor
4066	India	Arrah
4067	India	Arsikere
4068	India	Arukutti
4069	India	Arumuganeri
4070	India	Aruppukkottai
4071	India	Ashoknagar
4072	India	Ashta
4073	India	Atarra
4074	India	Athni
4075	India	Attili
4076	India	Attingal
4077	India	Attur
4078	India	Auraiya
4079	India	Aurangabad
4080	India	Ausa
4081	India	Avanigadda
4082	India	Avinashi
4083	India	Ayakudi
4084	India	Azamgarh
4085	India	Baberu
4086	India	Bachhraon
4087	India	Badagara
4088	India	Baddi
4089	India	Badlapur
4090	India	Badvel
4091	India	Bagaha
4092	India	Bagalkot
4093	India	Bagar
4094	India	Bagasra
4095	India	Baharampur
4096	India	Baheri
4097	India	Bahjoi
4098	India	Bahraigh
4099	India	Bahula
4100	India	Baihar
4101	India	Balasore
4102	India	Balod
4103	India	Banat
4104	India	Banda
4105	India	Bandipura
4106	India	Banga
4107	India	Banganapalle
4108	India	Bangaon
4109	India	Bankra
4110	India	Banmankhi
4111	India	Baranagar
4112	India	Barauli
4113	India	Baraut
4114	India	Barbil
4115	India	Bareilly
4116	India	Bargarh
4117	India	Bargi
4118	India	Barhiya
4119	India	Barjala
4120	India	Barpeta
4121	India	Basi
4122	India	Basmat
4123	India	Basni
4124	India	Baswa
4125	India	Bauda
4126	India	Bedi
4127	India	Begamganj
4128	India	Begusarai
4129	India	Behat
4130	India	Behror
4131	India	Bela
4132	India	Belgaum
4133	India	Bellampalli
4134	India	Bellary
4135	India	Belonia
4136	India	Belsand
4137	India	Bengaluru
4138	India	Berasia
4139	India	Betamcherla
4140	India	Bettiah
4141	India	Bewar
4142	India	Beypore
4143	India	Bhabhua
4144	India	Bhadaur
4145	India	Bhadohi
4146	India	Bhadrakh
4147	India	Bhadreswar
4148	India	Bhainsdehi
4149	India	Bhaisa
4150	India	Bhanjanagar
4151	India	Bharatpur
4152	India	Bharthana
4153	India	Bhatinda
4154	India	Bhatkal
4155	India	Bhattiprolu
4156	India	Bhawanipur
4157	India	Bhayandar
4158	India	Bhikangaon
4159	India	Bhilai
4160	India	Bhind
4161	India	Bhinga
4162	India	Bhiwadi
4163	India	Bhiwandi
4164	India	Bhogpur
4165	India	Bhongaon
4166	India	Bhopal
4167	India	Bhor
4168	India	Bhuban
4169	India	Bhubaneshwar
4170	India	Bhudgaon
4171	India	Bhuj
4172	India	Bhuvanagiri
4173	India	Biaora
4174	India	Bijapur
4175	India	Bijnor
4176	India	Bikramganj
4177	India	Bilgi
4178	India	Bilhaur
4179	India	Bilimora
4180	India	Bilsanda
4181	India	Bilsi
4182	India	Bilthra
4183	India	Bindki
4184	India	Binka
4185	India	Birmitrapur
4186	India	Birpara
4187	India	Bisauli
4188	India	Bishnupur
4189	India	Bobbili
4190	India	Bodhan
4191	India	Boisar
4192	India	Bolpur
4193	India	Bongaigaon
4194	India	Borivli
4195	India	Borsad
4196	India	Brahmapur
4197	India	Budaun
4198	India	Bulandshahr
4199	India	Burhar
4200	India	Burla
4201	India	Buxar
4202	India	Byndoor
4203	India	Calangute
4204	India	Cannanore
4205	India	Canning
4206	India	Chakapara
4207	India	Chakradharpur
4208	India	Chaksu
4209	India	Challakere
4210	India	Challapalle
4211	India	Chamba
4212	India	Chamrajnagar
4213	India	Chandannagar
4214	India	Chandauli
4215	India	Chanderi
4216	India	Chandigarh
4217	India	Chandrakona
4218	India	Chanduasi
4219	India	Channagiri
4220	India	Channapatna
4221	India	Chatra
4222	India	Chatrapur
4223	India	Chemmumiahpet
4224	India	Chengalpattu
4225	India	Chengam
4226	India	Chennai
4227	India	Chennimalai
4228	India	Cherpulassery
4229	India	Cherthala
4230	India	Chetput
4231	India	Cheyyar
4232	India	Chhabra
4233	India	Chhala
4234	India	Chhaprauli
4235	India	Chharra
4236	India	Chhatarpur
4237	India	Chicacole
4238	India	Chicholi
4239	India	Chidambaram
4240	India	Chidawa
4241	India	Chikhli
4242	India	Chikodi
4243	India	Chincholi
4244	India	Chinnachowk
4245	India	Chitradurga
4246	India	Chittaranjan
4247	India	Chittaurgarh
4248	India	Chodavaram
4249	India	Chopda
4250	India	Chotila
4251	India	Cochin
4252	India	Coimbatore
4253	India	Colachel
4254	India	Colgong
4255	India	Colonelganj
4256	India	Contai
4257	India	Coondapoor
4258	India	Cuddalore
4259	India	Cuddapah
4260	India	Cumbum
4261	India	Cuncolim
4262	India	Curchorem
4263	India	Cuttack
4264	India	Dabhoi
4265	India	Daboh
4266	India	Dabra
4267	India	Dalkola
4268	India	Daltonganj
4269	India	Daman
4270	India	Damoh
4271	India	Dandeli
4272	India	Darbhanga
4273	India	Dasnapur
4274	India	Datia
4275	India	Daudnagar
4276	India	Daund
4277	India	Dausa
4278	India	Dehri
4279	India	Delhi
4280	India	Denkanikota
4281	India	Deoband
4282	India	Deogarh
4283	India	Deoli
4284	India	Deoria
4285	India	Deshnoke
4286	India	Devakottai
4287	India	Devanhalli
4288	India	Devarkonda
4289	India	Devgarh
4290	India	Dewas
4291	India	Dhamtari
4292	India	Dhanaula
4293	India	Dhanaura
4294	India	Dhandhuka
4295	India	Dhanera
4296	India	Dharampur
4297	India	Dharangaon
4298	India	Dharapuram
4299	India	Dharmadam
4300	India	Dharmanagar
4301	India	Dharmapuri
4302	India	Dharmavaram
4303	India	Dhaulpur
4304	India	Dhaurahra
4305	India	Dhekiajuli
4306	India	Dhing
4307	India	Dholka
4308	India	Dhone
4309	India	Dhrol
4310	India	Dhuburi
4311	India	Dhulagari
4312	India	Dibai
4313	India	Dibrugarh
4314	India	Dicholi
4315	India	Digboi
4316	India	Digras
4317	India	Dinapore
4318	India	Dindigul
4319	India	Dindori
4320	India	Diphu
4321	India	Diu
4322	India	Doda
4323	India	Dohad
4324	India	Dombivli
4325	India	Dondaicha
4326	India	Dongargarh
4327	India	Dornakal
4328	India	Dugda
4329	India	Dumjor
4330	India	Dumka
4331	India	Dumra
4332	India	Dumraon
4333	India	Durg
4334	India	Durgapur
4335	India	Egra
4336	India	Elamanchili
4337	India	Ellenabad
4338	India	Ellore
4339	India	Erandol
4340	India	Erode
4341	India	Erraguntla
4342	India	Faizpur
4343	India	Farakka
4344	India	Farrukhnagar
4345	India	Fatehpur
4346	India	Fatwa
4347	India	Ferokh
4348	India	Ferozepore
4349	India	Forbesganj
4350	India	Gadag
4351	India	Gadhada
4352	India	Gadhinglaj
4353	India	Gajendragarh
4354	India	Gajraula
4355	India	Gajuwaka
4356	India	Gandevi
4357	India	Gangoh
4358	India	Gangolli
4359	India	Gangtok
4360	India	Gannavaram
4361	India	Garhmuktesar
4362	India	Garhshankar
4363	India	Garhwa
4364	India	Gariadhar
4365	India	Garui
4366	India	Gauripur
4367	India	Gaya
4368	India	Gevrai
4369	India	Ghandinagar
4370	India	Gharaunda
4371	India	Ghatkesar
4372	India	Ghugus
4373	India	Gingee
4374	India	Gobichettipalayam
4375	India	Gobindpur
4376	India	Godda
4377	India	Godhra
4378	India	Gohadi
4379	India	Gokak
4380	India	Gokarna
4381	India	Gomoh
4382	India	Gondal
4383	India	Gorakhpur
4384	India	Govardhan
4385	India	Gubbi
4386	India	Gudalur
4387	India	Gudiyatham
4388	India	Gulbarga
4389	India	Guledagudda
4390	India	Gumia
4391	India	Gumla
4392	India	Gummidipundi
4393	India	Guna
4394	India	Gundlupet
4395	India	Gunnaur
4396	India	Gunupur
4397	India	Gurgaon
4398	India	Guskhara
4399	India	Guwahati
4400	India	Gwalior
4401	India	Hadagalli
4402	India	Haldaur
4403	India	Haldia
4404	India	Haldwani
4405	India	Haliyal
4406	India	Halvad
4407	India	Haridwar
4408	India	Harihar
4409	India	Harpanahalli
4410	India	Hasanpur
4411	India	Hassan
4412	India	Hatta
4413	India	Hilsa
4414	India	Himatnagar
4415	India	Hindaun
4416	India	Hindoria
4417	India	Hindupur
4418	India	Hingoli
4419	India	Hinjilikatu
4420	India	Hisar
4421	India	Hodal
4422	India	Holalkere
4423	India	Hosdurga
4424	India	Hoskote
4425	India	Hospet
4426	India	Howli
4427	India	Hubli
4428	India	Hugli
4429	India	Hukeri
4430	India	Hungund
4431	India	Hyderabad
4432	India	Ichalkaranji
4433	India	Idappadi
4434	India	Igatpuri
4435	India	Ilkal
4436	India	Imphal
4437	India	Indergarh
4438	India	Indi
4439	India	Indore
4440	India	Indri
4441	India	Injambakkam
4442	India	Iringal
4443	India	Jabalpur
4444	India	Jagatsinghapur
4445	India	Jagdalpur
4446	India	Jaggayyapeta
4447	India	Jagraon
4448	India	Jaigaon
4449	India	Jaipur
4450	India	Jais
4451	India	Jaisalmer
4452	India	Jaisingpur
4453	India	Jaito
4454	India	Jalandhar
4455	India	Jalesar
4456	India	Jaleshwar
4457	India	Jalgaon
4458	India	Jalor
4459	India	Jambusar
4460	India	Jamkhandi
4461	India	Jammalamadugu
4462	India	Jammu
4463	India	Jamshedpur
4464	India	Jangaon
4465	India	Jangipur
4466	India	Jarwal
4467	India	Jasdan
4468	India	Jashpurnagar
4469	India	Jasidih
4470	India	Jaspur
4471	India	Jaswantnagar
4472	India	Jatani
4473	India	Jaunpur
4474	India	Jayamkondacholapuram
4475	India	Jaynagar
4476	India	Jetpur
4477	India	Jevargi
4478	India	Jewar
4479	India	Jeypore
4480	India	Jhajjar
4481	India	Jhalida
4482	India	Jharia
4483	India	Jodhpur
4484	India	Jogbani
4485	India	Jora
4486	India	Junnar
4487	India	Kachhwa
4488	India	Kadakkavoor
4489	India	Kadayanallur
4490	India	Kadi
4491	India	Kadiri
4492	India	Kadod
4493	India	Kaimganj
4494	India	Kaimori
4495	India	Kaithal
4496	India	Kakching
4497	India	Kalamassery
4498	India	Kalamb
4499	India	Kalavoor
4500	India	Kalghatgi
4501	India	Kallakkurichchi
4502	India	Kallidaikurichchi
4503	India	Kalmeshwar
4504	India	Kalpetta
4505	India	Kalugumalai
4506	India	Kalyandurg
4507	India	Kalyani
4508	India	Kamalganj
4509	India	Kampli
4510	India	Kanakapura
4511	India	Kangayam
4512	India	Kanigiri
4513	India	Kankauli
4514	India	Kannad
4515	India	Kannauj
4516	India	Kannod
4517	India	Kanpur
4518	India	Kanuru
4519	India	Kapadvanj
4520	India	Karamsad
4521	India	Karanpur
4522	India	Karauli
4523	India	Kareli
4524	India	Karera
4525	India	Karhal
4526	India	Karjat
4527	India	Karur
4528	India	Karwar
4529	India	Kasba
4530	India	Kashipur
4531	India	Katangi
4532	India	Katghora
4533	India	Kathua
4534	India	Katihar
4535	India	Kattanam
4536	India	Kawardha
4537	India	Kayalpattinam
4538	India	Keelakarai
4539	India	Kekri
4540	India	Kenda
4541	India	Keshod
4542	India	Kesinga
4543	India	Khada
4544	India	Khadki
4545	India	Khagaria
4546	India	Khagaul
4547	India	Khair
4548	India	Khamaria
4549	India	Khammam
4550	India	Khandela
4551	India	Khandwa
4552	India	Khanna
4553	India	Kharagpur
4554	India	Kharakvasla
4555	India	Kharar
4556	India	Khardah
4557	India	Khargone
4558	India	Kharkhauda
4559	India	Kharsia
4560	India	Khatauli
4561	India	Kheda
4562	India	Khekra
4563	India	Kheri
4564	India	Khetia
4565	India	Khetri
4566	India	Khilchipur
4567	India	Khopoli
4568	India	Khowai
4569	India	Khunti
4570	India	Khurai
4571	India	Khurda
4572	India	Khurja
4573	India	Kichha
4574	India	Kinwat
4575	India	Kirandul
4576	India	Kiraoli
4577	India	Kishanganj
4578	India	Kishangarh
4579	India	Kithor
4580	India	Kodoli
4581	India	Kohima
4582	India	Kokrajhar
4583	India	Kolasib
4584	India	Kolkata
4585	India	Kollam
4586	India	Konch
4587	India	Kondagaon
4588	India	Kondapalle
4589	India	Konnagar
4590	India	Koothanallur
4591	India	Kopargaon
4592	India	Koppal
4593	India	Koratla
4594	India	Korba
4595	India	Koregaon
4596	India	Korwai
4597	India	Kosamba
4598	India	Kosi
4599	India	Kosigi
4600	India	Kota
4601	India	Kotagiri
4602	India	Kotamangalam
4603	India	Kotkapura
4604	India	Kotma
4605	India	Kotputli
4606	India	Kottayam
4607	India	Kovilpatti
4608	India	Koynanagar
4609	India	Kozhikode
4610	India	Krishnagiri
4611	India	Krishnanagar
4612	India	Kuchaiburi
4613	India	Kuchera
4614	India	Kudachi
4615	India	Kuju
4616	India	Kukshi
4617	India	Kulgam
4618	India	Kulittalai
4619	India	Kultali
4620	India	Kulti
4621	India	Kulu
4622	India	Kumbakonam
4623	India	Kumbalam
4624	India	Kumta
4625	India	Kunda
4626	India	Kundarkhi
4627	India	Kundgol
4628	India	Kundla
4629	India	Kunigal
4630	India	Kunnamangalam
4631	India	Kunnamkulam
4632	India	Kuppam
4633	India	Kushtagi
4634	India	Kutiatodu
4635	India	Kuttampuzha
4636	India	Kuzhithurai
4637	India	Kyathampalle
4638	India	Lakhyabad
4639	India	Laksar
4640	India	Lakshmeshwar
4641	India	Lalgudi
4642	India	Lalitpur
4643	India	Lar
4644	India	Latur
4645	India	Leh
4646	India	Leteri
4647	India	Limbdi
4648	India	Lonavla
4649	India	Loni
4650	India	Losal
4651	India	Luckeesarai
4652	India	Lucknow
4653	India	Lunglei
4654	India	Madambakkam
4655	India	Madanapalle
4656	India	Maddagiri
4657	India	Madgaon
4658	India	Madhipura
4659	India	Madhubani
4660	India	Madhupur
4661	India	Madhyamgram
4662	India	Madikeri
4663	India	Madipakkam
4664	India	Madukkarai
4665	India	Madurai
4666	India	Maghar
4667	India	Maham
4668	India	Mahendragarh
4669	India	Maheshwar
4670	India	Mahiari
4671	India	Maholi
4672	India	Mahudha
4673	India	Mahwah
4674	India	Maihar
4675	India	Mainpuri
4676	India	Mairwa
4677	India	Maksi
4678	India	Malakanagiri
4679	India	Malappuram
4680	India	Malaut
4681	India	Malavalli
4682	India	Malkajgiri
4683	India	Mallasamudram
4684	India	Malpe
4685	India	Manali
4686	India	Manamadurai
4687	India	Manapparai
4688	India	Mandamarri
4689	India	Mandapam
4690	India	Mandapeta
4691	India	Mandi
4692	India	Mandideep
4693	India	Mandsaur
4694	India	Mandya
4695	India	Maner
4696	India	Mangalagiri
4697	India	Mangaldai
4698	India	Mangalore
4699	India	Manglaur
4700	India	Maniar
4701	India	Manjeri
4702	India	Manjhanpur
4703	India	Mannargudi
4704	India	Manoharpur
4705	India	Manthani
4706	India	Manuguru
4707	India	Marakkanam
4708	India	Margherita
4709	India	Marhaura
4710	India	Marigaon
4711	India	Marmagao
4712	India	Mathura
4713	India	Mau
4714	India	Maudaha
4715	India	Mauganj
4716	India	Maur
4717	India	Mavoor
4718	India	Mayiladuthurai
4719	India	Medak
4720	India	Meerut
4721	India	Mehekar
4722	India	Melur
4723	India	Mendarda
4724	India	Merta
4725	India	Mettupalayam
4726	India	Mettur
4727	India	Mihona
4728	India	Milak
4729	India	Misrikh
4730	India	Moga
4731	India	Mohali
4732	India	Mokameh
4733	India	Mon
4734	India	Monghyr
4735	India	Monoharpur
4736	India	Moram
4737	India	Morbi
4738	India	Morena
4739	India	Morinda
4740	India	Morsi
4741	India	Morwa
4742	India	Mudgal
4743	India	Mudhol
4744	India	Mudkhed
4745	India	Mukher
4746	India	Muktsar
4747	India	Mulgund
4748	India	Multai
4749	India	Muluppilagadu
4750	India	Mumbai
4751	India	Mundargi
4752	India	Mundgod
4753	India	Mundra
4754	India	Mungaoli
4755	India	Mungeli
4756	India	Munnar
4757	India	Murudeshwara
4758	India	Musiri
4759	India	Mussoorie
4760	India	Muttupet
4761	India	Muvattupuzha
4762	India	Muzaffarnagar
4763	India	Muzaffarpur
4764	India	Mysore
4765	India	Nagar
4766	India	Nagari
4767	India	Nagda
4768	India	Nagpur
4769	India	Naharlagun
4770	India	Nahorkatiya
4771	India	Nainpur
4772	India	Nainwa
4773	India	Nakodar
4774	India	Naldurg
4775	India	Nalgonda
4776	India	Nanauta
4777	India	Nanded
4778	India	Nandurbar
4779	India	Nangi
4780	India	Naraina
4781	India	Naraini
4782	India	Narasannapeta
4783	India	Narasapur
4784	India	Narasaraopet
4785	India	Narauli
4786	India	Naraura
4787	India	Naregal
4788	India	Nargund
4789	India	Narsimhapur
4790	India	Narsinghgarh
4791	India	Narwar
4792	India	Nashik
4793	India	Nattam
4794	India	Naugachhia
4795	India	Nautanwa
4796	India	Navalgund
4797	India	Nawalgarh
4798	India	Neelankarai
4799	India	Nelamangala
4800	India	Nellikkuppam
4801	India	Nellore
4802	India	Neral
4803	India	Nichlaul
4804	India	Nidadavole
4805	India	Nihtaur
4806	India	Nilakottai
4807	India	Nilanga
4808	India	Nirmal
4809	India	Niwai
4810	India	Nohar
4811	India	Noida
4812	India	Nokha
4813	India	Nongstoin
4814	India	Nowrangapur
4815	India	Obra
4816	India	Okha
4817	India	Ongole
4818	India	Ooty
4819	India	Orai
4820	India	Osmanabad
4821	India	Ozar
4822	India	Pachperwa
4823	India	Padam
4824	India	Padampur
4825	India	Padra
4826	India	Padrauna
4827	India	Paithan
4828	India	Palakkad
4829	India	Palani
4830	India	Palera
4831	India	Palladam
4832	India	Pallappatti
4833	India	Pallikondai
4834	India	Pallippatti
4835	India	Palmaner
4836	India	Palwal
4837	India	Palwancha
4838	India	Panaji
4839	India	Pandharpur
4840	India	Pandua
4841	India	Panmana
4842	India	Panna
4843	India	Panruti
4844	India	Panvel
4845	India	Papanasam
4846	India	Paramagudi
4847	India	Parbhani
4848	India	Parola
4849	India	Parvatsar
4850	India	Patancheru
4851	India	Pataudi
4852	India	Pathalgaon
4853	India	Patharia
4854	India	Patna
4855	India	Patti
4856	India	Pattukkottai
4857	India	Pauri
4858	India	Pawni
4859	India	Pedana
4860	India	Peddapalli
4861	India	Pehowa
4862	India	Pen
4863	India	Penugonda
4864	India	Penukonda
4865	India	Perambalur
4866	India	Peravurani
4867	India	Periyakulam
4868	India	Periyanayakkanpalaiyam
4869	India	Perumbavoor
4870	India	Perundurai
4871	India	Perungudi
4872	India	Phalauda
4873	India	Phalodi
4874	India	Phaltan
4875	India	Phek
4876	India	Phillaur
4877	India	Phirangipuram
4878	India	Phulera
4879	India	Phulpur
4880	India	Pilibangan
4881	India	Pilkhua
4882	India	Pimpri
4883	India	Pinjaur
4884	India	Pipili
4885	India	Pipraich
4886	India	Piravam
4887	India	Piro
4888	India	Pithampur
4889	India	Pokaran
4890	India	Polasara
4891	India	Polavaram
4892	India	Pollachi
4893	India	Ponda
4894	India	Ponneri
4895	India	Ponnur
4896	India	Poonamalle
4897	India	Porbandar
4898	India	Porsa
4899	India	Porur
4900	India	Powai
4901	India	Puducherry
4902	India	Pudukkottai
4903	India	Pujali
4904	India	Pulgaon
4905	India	Pulivendla
4906	India	Puliyangudi
4907	India	Pulwama
4908	India	Pune
4909	India	Pupri
4910	India	Puri
4911	India	Purnia
4912	India	Puruliya
4913	India	Pusad
4914	India	Pushkar
4915	India	Quthbullapur
4916	India	Rabkavi
4917	India	Raebareli
4918	India	Rafiganj
4919	India	Raghunathpur
4920	India	Rahimatpur
4921	India	Raigarh
4922	India	Raipur
4923	India	Raisen
4924	India	Rajaori
4925	India	Rajapalaiyam
4926	India	Rajpur
4927	India	Ramagundam
4928	India	Ramanathapuram
4929	India	Ramanayyapeta
4930	India	Rameswaram
4931	India	Rampachodavaram
4932	India	Ranchi
4933	India	Rangia
4934	India	Rasipuram
4935	India	Ratangarh
4936	India	Ratanpur
4937	India	Ratia
4938	India	Ratnagiri
4939	India	Raxaul
4940	India	Rehli
4941	India	Remuna
4942	India	Renigunta
4943	India	Reoti
4944	India	Repalle
4945	India	Revelganj
4946	India	Rewa
4947	India	Richha
4948	India	Rishra
4949	India	Risod
4950	India	Robertsganj
4951	India	Robertsonpet
4952	India	Roha
4953	India	Rohtak
4954	India	Ron
4955	India	Roorkee
4956	India	Ropar
4957	India	Rura
4958	India	Rusera
4959	India	Sabalgarh
4960	India	Sadalgi
4961	India	Safidon
4962	India	Sagauli
4963	India	Saharsa
4964	India	Sahaspur
4965	India	Saidpur
4966	India	Saiha
4967	India	Sainthia
4968	India	Sakleshpur
4969	India	Salem
4970	India	Sambalpur
4971	India	Sambhal
4972	India	Samdari
4973	India	Samthar
4974	India	Sanaur
4975	India	Sancoale
4976	India	Sangamner
4977	India	Sangod
4978	India	Sankeshwar
4979	India	Saoner
4980	India	Saraipali
4981	India	Sarauli
4982	India	Sardhana
4983	India	Sardulgarh
4984	India	Sarkhej
4985	India	Sathupalli
4986	India	Sathyamangalam
4987	India	Satna
4988	India	Sattenapalle
4989	India	Sattur
4990	India	Saugor
4991	India	Saundatti
4992	India	Sausar
4993	India	Secunderabad
4994	India	Sehore
4995	India	Selu
4996	India	Sendhwa
4997	India	Seondha
4998	India	Seoni
4999	India	Seram
5000	India	Serilingampalle
5001	India	Shahbazpur
5002	India	Shahdol
5003	India	Shegaon
5004	India	Sheikhpura
5005	India	Sheoganj
5006	India	Sheohar
5007	India	Sheopur
5008	India	Sherkot
5009	India	Shertallai
5010	India	Shiggaon
5011	India	Shiliguri
5012	India	Shillong
5013	India	Shimla
5014	India	Shimoga
5015	India	Shiraguppi
5016	India	Shirdi
5017	India	Shirhatti
5018	India	Shirpur
5019	India	Shivpuri
5020	India	Sholinghur
5021	India	Shyamnagar
5022	India	Siddhapur
5023	India	Siddipet
5024	India	Sidhi
5025	India	Sidlaghatta
5026	India	Sihor
5027	India	Sijua
5028	India	Sikandarpur
5029	India	Sikka
5030	India	Silao
5031	India	Silapathar
5032	India	Silchar
5033	India	Sillod
5034	India	Silvassa
5035	India	Simdega
5036	India	Sindgi
5037	India	Singrauli
5038	India	Singur
5039	India	Sinnar
5040	India	Sirhind
5041	India	Sirohi
5042	India	Sironj
5043	India	Sirsa
5044	India	Sirsi
5045	India	Sirsilla
5046	India	Siruguppa
5047	India	Sirumugai
5048	India	Sisauli
5049	India	Siuri
5050	India	Sivaganga
5051	India	Sivagiri
5052	India	Sivakasi
5053	India	Sohna
5054	India	Sojat
5055	India	Solan
5056	India	Someshwar
5057	India	Sompeta
5058	India	Sonepur
5059	India	Songadh
5060	India	Sopur
5061	India	Sorada
5062	India	Soro
5063	India	Soron
5064	India	Soygaon
5065	India	Srinagar
5066	India	Srivaikuntam
5067	India	Srivilliputhur
5068	India	Suket
5069	India	Sultanpur
5070	India	Sulur
5071	India	Sulya
5072	India	Sundargarh
5073	India	Sundarnagar
5074	India	Sunel
5075	India	Supaul
5076	India	Surendranagar
5077	India	Takhatgarh
5078	India	Takhatpur
5079	India	Taleigao
5080	India	Talipparamba
5081	India	Taloda
5082	India	Tanakpur
5083	India	Tanuku
5084	India	Tarakeswar
5085	India	Tarikere
5086	India	Teghra
5087	India	Tehri
5088	India	Tekkalakote
5089	India	Tekkali
5090	India	Tellicherry
5091	India	Teni
5092	India	Teonthar
5093	India	Tezpur
5094	India	Thakurdwara
5095	India	Tharangambadi
5096	India	Thenkasi
5097	India	Thiruthani
5098	India	Thiruvananthapuram
5099	India	Thiruvarur
5100	India	Tilhar
5101	India	Tindivanam
5102	India	Tinsukia
5103	India	Tiruchchendur
5104	India	Tiruchengode
5105	India	Tiruchirappalli
5106	India	Tirukkoyilur
5107	India	Tirumala
5108	India	Tirunelveli
5109	India	Tirupati
5110	India	Tirupparangunram
5111	India	Tiruppur
5112	India	Tiruppuvanam
5113	India	Tirur
5114	India	Tiruttangal
5115	India	Tiruvalla
5116	India	Tiruvallur
5117	India	Tisaiyanvilai
5118	India	Todabhim
5119	India	Todaraisingh
5120	India	Tondi
5121	India	Tonk
5122	India	Tuensang
5123	India	Tumsar
5124	India	Tuni
5125	India	Tura
5126	India	Udaipur
5127	India	Udaipura
5128	India	Udalguri
5129	India	Udankudi
5130	India	Udhampur
5131	India	Udipi
5132	India	Udumalaippettai
5133	India	Ujjain
5134	India	Ulhasnagar
5135	India	Ullal
5136	India	Umarga
5137	India	Umaria
5138	India	Umarkhed
5139	India	Umarkot
5140	India	Umred
5141	India	Umreth
5142	India	Un
5143	India	Una
5144	India	Unhel
5145	India	Unjha
5146	India	Upleta
5147	India	Uran
5148	India	Uravakonda
5149	India	Usehat
5150	India	Usilampatti
5151	India	Utraula
5152	India	Vadamadurai
5153	India	Vadnagar
5154	India	Vadodara
5155	India	Vaikam
5156	India	Valparai
5157	India	Vaniyambadi
5158	India	Vapi
5159	India	Varanasi
5160	India	Varangaon
5161	India	Varkala
5162	India	Vasa
5163	India	Vasind
5164	India	Vattalkundu
5165	India	Vedaraniyam
5166	India	Vejalpur
5167	India	Vellore
5168	India	Velur
5169	India	Venkatagiri
5170	India	Vepagunta
5171	India	Vettaikkaranpudur
5172	India	Vidisha
5173	India	Vijayapura
5174	India	Vijayawada
5175	India	Villupuram
5176	India	Vinukonda
5177	India	Virudunagar
5178	India	Visakhapatnam
5179	India	Visnagar
5180	India	Vite
5181	India	Vizianagaram
5182	India	Wai
5183	India	Walajapet
5184	India	Wani
5185	India	Wanparti
5186	India	Warangal
5187	India	Wardha
5188	India	Warora
5189	India	Warud
5190	India	Wellington
5191	India	Wer
5192	India	Wokha
5193	India	Yanam
5194	India	Yanamalakuduru
5195	India	Yelahanka
5196	India	Yellandu
5197	India	Yeola
5198	India	Zaidpur
5199	India	Zira
5200	India	Zunheboto
5201	Indonesia	Abepura
5202	Indonesia	Adiwerna
5203	Indonesia	Amahai
5204	Indonesia	Ambarawa
5205	Indonesia	Ambon
5206	Indonesia	Amuntai
5207	Indonesia	Arjawinangun
5208	Indonesia	Astanajapura
5209	Indonesia	Atambua
5210	Indonesia	Babat
5211	Indonesia	Baekrajan
5212	Indonesia	Baki
5213	Indonesia	Balaipungut
5214	Indonesia	Balapulang
5215	Indonesia	Balikpapan
5216	Indonesia	Balung
5217	Indonesia	Bambanglipuro
5218	Indonesia	Bandar
5219	Indonesia	Bandung
5220	Indonesia	Bangil
5221	Indonesia	Bangkalan
5222	Indonesia	Banjar
5223	Indonesia	Banjaran
5224	Indonesia	Banjarmasin
5225	Indonesia	Bantul
5226	Indonesia	Banyumas
5227	Indonesia	Banyuwangi
5228	Indonesia	Barabai
5229	Indonesia	Batang
5230	Indonesia	Batu
5231	Indonesia	Baturaden
5232	Indonesia	Baturaja
5233	Indonesia	Bekasi
5234	Indonesia	Belawan
5235	Indonesia	Bengkulu
5236	Indonesia	Berastagi
5237	Indonesia	Besuki
5238	Indonesia	Bima
5239	Indonesia	Binjai
5240	Indonesia	Bireun
5241	Indonesia	Bitung
5242	Indonesia	Blitar
5243	Indonesia	Blora
5244	Indonesia	Bogor
5245	Indonesia	Bojonegoro
5246	Indonesia	Bondowoso
5247	Indonesia	Bontang
5248	Indonesia	Boyolali
5249	Indonesia	Boyolangu
5250	Indonesia	Buaran
5251	Indonesia	Buduran
5252	Indonesia	Bukittinggi
5253	Indonesia	Bulakamba
5254	Indonesia	Caringin
5255	Indonesia	Ceper
5256	Indonesia	Cepu
5257	Indonesia	Ciamis
5258	Indonesia	Ciampea
5259	Indonesia	Cibinong
5260	Indonesia	Cicurug
5261	Indonesia	Cikampek
5262	Indonesia	Cikarang
5263	Indonesia	Cikupa
5264	Indonesia	Cileungsir
5265	Indonesia	Cileunyi
5266	Indonesia	Cimahi
5267	Indonesia	Ciputat
5268	Indonesia	Cirebon
5269	Indonesia	Citeureup
5270	Indonesia	Colomadu
5271	Indonesia	Comal
5272	Indonesia	Curug
5273	Indonesia	Curup
5274	Indonesia	Dampit
5275	Indonesia	Delanggu
5276	Indonesia	Demak
5277	Indonesia	Denpasar
5278	Indonesia	Depok
5279	Indonesia	Diwek
5280	Indonesia	Dompu
5281	Indonesia	Driyorejo
5282	Indonesia	Dukuhturi
5283	Indonesia	Dumai
5284	Indonesia	Ende
5285	Indonesia	Galesong
5286	Indonesia	Gampengrejo
5287	Indonesia	Gatak
5288	Indonesia	Gebog
5289	Indonesia	Gedangan
5290	Indonesia	Genteng
5291	Indonesia	Godean
5292	Indonesia	Gombong
5293	Indonesia	Gorontalo
5294	Indonesia	Gresik
5295	Indonesia	Grogol
5296	Indonesia	Indramayu
5297	Indonesia	Jakarta
5298	Indonesia	Jaten
5299	Indonesia	Jatibarang
5300	Indonesia	Jatiroto
5301	Indonesia	Jatiwangi
5302	Indonesia	Jayapura
5303	Indonesia	Jekulo
5304	Indonesia	Jember
5305	Indonesia	Jogonalan
5306	Indonesia	Jombang
5307	Indonesia	Juwana
5308	Indonesia	Kabanjahe
5309	Indonesia	Kalianget
5310	Indonesia	Kamal
5311	Indonesia	Karangampel
5312	Indonesia	Karanganom
5313	Indonesia	Karangasem
5314	Indonesia	Karangsembung
5315	Indonesia	Kartasura
5316	Indonesia	Kasihan
5317	Indonesia	Katabu
5318	Indonesia	Kawalu
5319	Indonesia	Kebomas
5320	Indonesia	Kebonarun
5321	Indonesia	Kediri
5322	Indonesia	Kedungwaru
5323	Indonesia	Kedungwuni
5324	Indonesia	Kefamenanu
5325	Indonesia	Kencong
5326	Indonesia	Kendari
5327	Indonesia	Kepanjen
5328	Indonesia	Kertosono
5329	Indonesia	Ketanggungan
5330	Indonesia	Kijang
5331	Indonesia	Kisaran
5332	Indonesia	Klangenan
5333	Indonesia	Klaten
5334	Indonesia	Klungkung
5335	Indonesia	Kotabumi
5336	Indonesia	Kraksaan
5337	Indonesia	Kresek
5338	Indonesia	Krian
5339	Indonesia	Kroya
5340	Indonesia	Kualakapuas
5341	Indonesia	Kudus
5342	Indonesia	Kuningan
5343	Indonesia	Kupang
5344	Indonesia	Kuta
5345	Indonesia	Kutoarjo
5346	Indonesia	Labuan
5347	Indonesia	Lahat
5348	Indonesia	Lamongan
5349	Indonesia	Langsa
5350	Indonesia	Lasem
5351	Indonesia	Lawang
5352	Indonesia	Lebaksiu
5353	Indonesia	Lembang
5354	Indonesia	Lhokseumawe
5355	Indonesia	Lubuklinggau
5356	Indonesia	Lumajang
5357	Indonesia	Luwuk
5358	Indonesia	Madiun
5359	Indonesia	Magelang
5360	Indonesia	Majalengka
5361	Indonesia	Majenang
5362	Indonesia	Majene
5363	Indonesia	Makassar
5364	Indonesia	Malang
5365	Indonesia	Manado
5366	Indonesia	Manggar
5367	Indonesia	Manismata
5368	Indonesia	Manokwari
5369	Indonesia	Margahayukencana
5370	Indonesia	Margasari
5371	Indonesia	Martapura
5372	Indonesia	Mataram
5373	Indonesia	Maumere
5374	Indonesia	Medan
5375	Indonesia	Melati
5376	Indonesia	Mendaha
5377	Indonesia	Mertoyudan
5378	Indonesia	Metro
5379	Indonesia	Meulaboh
5380	Indonesia	Mlonggo
5381	Indonesia	Mojoagung
5382	Indonesia	Mojokerto
5383	Indonesia	Mranggen
5384	Indonesia	Muncar
5385	Indonesia	Muntilan
5386	Indonesia	Muntok
5387	Indonesia	Nabire
5388	Indonesia	Negara
5389	Indonesia	Nganjuk
5390	Indonesia	Ngawi
5391	Indonesia	Ngemplak
5392	Indonesia	Ngoro
5393	Indonesia	Ngunut
5394	Indonesia	Paciran
5395	Indonesia	Padalarang
5396	Indonesia	Padang
5397	Indonesia	Padangsidempuan
5398	Indonesia	Pageralam
5399	Indonesia	Pakisaji
5400	Indonesia	Palangkaraya
5401	Indonesia	Palembang
5402	Indonesia	Palimanan
5403	Indonesia	Palopo
5404	Indonesia	Palu
5405	Indonesia	Pamanukan
5406	Indonesia	Pamekasan
5407	Indonesia	Pameungpeuk
5408	Indonesia	Pamulang
5409	Indonesia	Panarukan
5410	Indonesia	Pandaan
5411	Indonesia	Pandak
5412	Indonesia	Pandeglang
5413	Indonesia	Pangkalanbuun
5414	Indonesia	Pangkalpinang
5415	Indonesia	Panji
5416	Indonesia	Pare
5417	Indonesia	Parepare
5418	Indonesia	Pariaman
5419	Indonesia	Parung
5420	Indonesia	Pasarkemis
5421	Indonesia	Paseh
5422	Indonesia	Pasuruan
5423	Indonesia	Pati
5424	Indonesia	Payakumbuh
5425	Indonesia	Pecangaan
5426	Indonesia	Pekalongan
5427	Indonesia	Pekanbaru
5428	Indonesia	Pelabuhanratu
5429	Indonesia	Pemalang
5430	Indonesia	Pemangkat
5431	Indonesia	Pematangsiantar
5432	Indonesia	Perbaungan
5433	Indonesia	Percut
5434	Indonesia	Petarukan
5435	Indonesia	Plumbon
5436	Indonesia	Polewali
5437	Indonesia	Ponorogo
5438	Indonesia	Pontianak
5439	Indonesia	Poso
5440	Indonesia	Prabumulih
5441	Indonesia	Praya
5442	Indonesia	Prigen
5443	Indonesia	Probolinggo
5444	Indonesia	Pundong
5445	Indonesia	Purbalingga
5446	Indonesia	Purwakarta
5447	Indonesia	Purwodadi
5448	Indonesia	Purwokerto
5449	Indonesia	Rajapolah
5450	Indonesia	Randudongkal
5451	Indonesia	Rangkasbitung
5452	Indonesia	Rantauprapat
5453	Indonesia	Rantepao
5454	Indonesia	Rembangan
5455	Indonesia	Rengasdengklok
5456	Indonesia	Reuleuet
5457	Indonesia	Ruteng
5458	Indonesia	Sabang
5459	Indonesia	Salatiga
5460	Indonesia	Samarinda
5461	Indonesia	Sampang
5462	Indonesia	Sampit
5463	Indonesia	Sawangan
5464	Indonesia	Selogiri
5465	Indonesia	Semarang
5466	Indonesia	Sengkang
5467	Indonesia	Sepatan
5468	Indonesia	Serang
5469	Indonesia	Seririt
5470	Indonesia	Serpong
5471	Indonesia	Sewon
5472	Indonesia	Sibolga
5473	Indonesia	Sidareja
5474	Indonesia	Sidoarjo
5475	Indonesia	Sigli
5476	Indonesia	Sijunjung
5477	Indonesia	Simpang
5478	Indonesia	Singaparna
5479	Indonesia	Singaraja
5480	Indonesia	Singkawang
5481	Indonesia	Singkil
5482	Indonesia	Singojuruh
5483	Indonesia	Singosari
5484	Indonesia	Sinjai
5485	Indonesia	Situbondo
5486	Indonesia	Slawi
5487	Indonesia	Sleman
5488	Indonesia	Soe
5489	Indonesia	Sofifi
5490	Indonesia	Sokaraja
5491	Indonesia	Soko
5492	Indonesia	Solok
5493	Indonesia	Soreang
5494	Indonesia	Sorong
5495	Indonesia	Sragen
5496	Indonesia	Srandakan
5497	Indonesia	Srono
5498	Indonesia	Stabat
5499	Indonesia	Sukabumi
5500	Indonesia	Sumber
5501	Indonesia	Sumberpucung
5502	Indonesia	Sumenep
5503	Indonesia	Sungailiat
5504	Indonesia	Sunggal
5505	Indonesia	Surabaya
5506	Indonesia	Surakarta
5507	Indonesia	Tabanan
5508	Indonesia	Tangerang
5509	Indonesia	Tanggulangin
5510	Indonesia	Tanjungagung
5511	Indonesia	Tanjungbalai
5512	Indonesia	Tanjungpinang
5513	Indonesia	Tanjungtiram
5514	Indonesia	Tarakan
5515	Indonesia	Tarub
5516	Indonesia	Tasikmalaya
5517	Indonesia	Tayu
5518	Indonesia	Tebingtinggi
5519	Indonesia	Tegal
5520	Indonesia	Teluknaga
5521	Indonesia	Ternate
5522	Indonesia	Tomohon
5523	Indonesia	Tondano
5524	Indonesia	Tongging
5525	Indonesia	Trenggalek
5526	Indonesia	Trucuk
5527	Indonesia	Tual
5528	Indonesia	Tuban
5529	Indonesia	Tulungagung
5530	Indonesia	Ubud
5531	Indonesia	Ungaran
5532	Indonesia	Waingapu
5533	Indonesia	Wanaraja
5534	Indonesia	Wangon
5535	Indonesia	Watampone
5536	Indonesia	Wedi
5537	Indonesia	Welahan
5538	Indonesia	Weleri
5539	Indonesia	Weru
5540	Indonesia	Wiradesa
5541	Indonesia	Wongsorejo
5542	Indonesia	Wonopringgo
5543	Indonesia	Wonosari
5544	Indonesia	Wonosobo
5545	Indonesia	Yogyakarta
5546	Iran	Abadan
5547	Iran	Abhar
5548	Iran	Aghajari
5549	Iran	Ahar
5550	Iran	Ahvaz
5551	Iran	Aleshtar
5552	Iran	Alvand
5553	Iran	Bam
5554	Iran	Behshahr
5555	Iran	Chabahar
5556	Iran	Dehdasht
5557	Iran	Dogonbadan
5558	Iran	Hashtpar
5559	Iran	Isfahan
5560	Iran	Karaj
5561	Iran	Kerman
5562	Iran	Khomeyn
5563	Iran	Khorramabad
5564	Iran	Khorramdarreh
5565	Iran	Khorramshahr
5566	Iran	Khvoy
5567	Iran	Mahdishahr
5568	Iran	Marand
5569	Iran	Mashhad
5570	Iran	Meybod
5571	Iran	Naqadeh
5572	Iran	Nowshahr
5573	Iran	Piranshahr
5574	Iran	Qarchak
5575	Iran	Qazvin
5576	Iran	Qeshm
5577	Iran	Qom
5578	Iran	Qorveh
5579	Iran	Rasht
5580	Iran	Sabzevar
5581	Iran	Sanandaj
5582	Iran	Saqqez
5583	Iran	Sarakhs
5584	Iran	Sari
5585	Iran	Shahrud
5586	Iran	Shiraz
5587	Iran	Sirjan
5588	Iran	Sonqor
5589	Iran	Tabas
5590	Iran	Tabriz
5591	Iran	Taft
5592	Iran	Tehran
5593	Iran	Yasuj
5594	Iran	Yazd
5595	Iran	Zahedan
5596	Iran	Zarand
5597	Iraq	Baghdad
5598	Iraq	Balad
5599	Iraq	Baqubah
5600	Iraq	Basrah
5601	Iraq	Baynjiwayn
5602	Iraq	Dihok
5603	Iraq	Erbil
5604	Iraq	Karbala
5605	Iraq	Kirkuk
5606	Iraq	Koysinceq
5607	Iraq	Kufa
5608	Iraq	Mosul
5609	Iraq	Najaf
5610	Iraq	Ramadi
5611	Iraq	Tallkayf
5612	Iraq	Tozkhurmato
5613	Iraq	Zaxo
5614	Ireland	Athlone
5615	Ireland	Balbriggan
5616	Ireland	Blanchardstown
5617	Ireland	Carlow
5618	Ireland	Celbridge
5619	Ireland	Cork
5620	Ireland	Donaghmede
5621	Ireland	Drogheda
5622	Ireland	Dublin
5623	Ireland	Dundalk
5624	Ireland	Ennis
5625	Ireland	Finglas
5626	Ireland	Gaillimh
5627	Ireland	Kilkenny
5628	Ireland	Leixlip
5629	Ireland	Letterkenny
5630	Ireland	Lucan
5631	Ireland	Luimneach
5632	Ireland	Malahide
5633	Ireland	Naas
5634	Ireland	Navan
5635	Ireland	Sandyford
5636	Ireland	Sligo
5637	Ireland	Swords
5638	Ireland	Tallaght
5639	Ireland	Tralee
5640	Ireland	Waterford
5641	Israel	Ariel
5642	Israel	Ashdod
5643	Israel	Ashqelon
5644	Israel	Beersheba
5645	Israel	Dimona
5646	Israel	Eilat
5647	Israel	Haifa
5648	Israel	Herzliyya
5649	Israel	Jerusalem
5650	Israel	Lod
5651	Israel	Modiin
5652	Israel	Nahariya
5653	Israel	Nazareth
5654	Israel	Nesher
5655	Israel	Netanya
5656	Israel	Netivot
5657	Israel	Ofaqim
5658	Israel	Qalansuwa
5659	Israel	Ramla
5660	Israel	Safed
5661	Israel	Sederot
5662	Israel	Tamra
5663	Israel	Tiberias
5664	Israel	Tirah
5665	Israel	Yafo
5666	Israel	Yehud
5667	Italy	Abbiategrasso
5668	Italy	Acerra
5669	Italy	Acireale
5670	Italy	Adelfia
5671	Italy	Adrano
5672	Italy	Afragola
5673	Italy	Agrigento
5674	Italy	Agropoli
5675	Italy	Alba
5676	Italy	Albenga
5677	Italy	Albignasego
5678	Italy	Alcamo
5679	Italy	Alessandria
5680	Italy	Alghero
5681	Italy	Alpignano
5682	Italy	Altamura
5683	Italy	Amato
5684	Italy	Ancona
5685	Italy	Andria
5686	Italy	Angri
5687	Italy	Anzio
5688	Italy	Aosta
5689	Italy	Aprilia
5690	Italy	Arcore
5691	Italy	Ardea
5692	Italy	Arese
5693	Italy	Arezzo
5694	Italy	Ariccia
5695	Italy	Arpino
5696	Italy	Arzano
5697	Italy	Arzignano
5698	Italy	Assemini
5699	Italy	Asti
5700	Italy	Augusta
5701	Italy	Avellino
5702	Italy	Aversa
5703	Italy	Avezzano
5704	Italy	Avola
5705	Italy	Bacoli
5706	Italy	Bagheria
5707	Italy	Bagnoli
5708	Italy	Bareggio
5709	Italy	Bari
5710	Italy	Barletta
5711	Italy	Battipaglia
5712	Italy	Belluno
5713	Italy	Belpasso
5714	Italy	Benevento
5715	Italy	Bergamo
5716	Italy	Biancavilla
5717	Italy	Biella
5718	Italy	Bisceglie
5719	Italy	Bitonto
5720	Italy	Bollate
5721	Italy	Bologna
5722	Italy	Bolzano
5723	Italy	Borgomanero
5724	Italy	Boscoreale
5725	Italy	Bra
5726	Italy	Brescia
5727	Italy	Bressanone
5728	Italy	Bresso
5729	Italy	Brindisi
5730	Italy	Bronte
5731	Italy	Brugherio
5732	Italy	Brusciano
5733	Italy	Bussolengo
5734	Italy	Cagliari
5735	Italy	Caivano
5736	Italy	Caltagirone
5737	Italy	Caltanissetta
5738	Italy	Camaiore
5739	Italy	Campobasso
5740	Italy	Capannori
5741	Italy	Capua
5742	Italy	Carbonia
5743	Italy	Cardito
5744	Italy	Carini
5745	Italy	Carmagnola
5746	Italy	Carrara
5747	Italy	Casamassima
5748	Italy	Casarano
5749	Italy	Casavatore
5750	Italy	Cascina
5751	Italy	Caserta
5752	Italy	Casoria
5753	Italy	Cassino
5754	Italy	Castelvetrano
5755	Italy	Castrovillari
5756	Italy	Catania
5757	Italy	Catanzaro
5758	Italy	Cattolica
5759	Italy	Cecina
5760	Italy	Cento
5761	Italy	Cercola
5762	Italy	Cerignola
5763	Italy	Cerveteri
5764	Italy	Cervia
5765	Italy	Cesena
5766	Italy	Cesenatico
5767	Italy	Chiari
5768	Italy	Chiavari
5769	Italy	Chieri
5770	Italy	Chieti
5771	Italy	Chioggia
5772	Italy	Chivasso
5773	Italy	Ciampino
5774	Italy	Civitavecchia
5775	Italy	Colleferro
5776	Italy	Collegno
5777	Italy	Comiso
5778	Italy	Como
5779	Italy	Conegliano
5780	Italy	Conversano
5781	Italy	Copertino
5782	Italy	Corato
5783	Italy	Cordenons
5784	Italy	Cormano
5785	Italy	Cornaredo
5786	Italy	Correggio
5787	Italy	Corsico
5788	Italy	Cosenza
5789	Italy	Crema
5790	Italy	Cremona
5791	Italy	Crotone
5792	Italy	Cuneo
5793	Italy	Dalmine
5794	Italy	Desio
5795	Italy	Domodossola
5796	Italy	Eboli
5797	Italy	Empoli
5798	Italy	Enna
5799	Italy	Erba
5800	Italy	Ercolano
5801	Italy	Fabriano
5802	Italy	Faenza
5803	Italy	Fano
5804	Italy	Fasano
5805	Italy	Favara
5806	Italy	Fermo
5807	Italy	Ferrara
5808	Italy	Fidenza
5809	Italy	Fiorano
5810	Italy	Florence
5811	Italy	Floridia
5812	Italy	Foggia
5813	Italy	Foligno
5814	Italy	Follonica
5815	Italy	Fondi
5816	Italy	Forio
5817	Italy	Formia
5818	Italy	Formigine
5819	Italy	Fornacelle
5820	Italy	Fossano
5821	Italy	Frascati
5822	Italy	Frattamaggiore
5823	Italy	Frattaminore
5824	Italy	Frosinone
5825	Italy	Gaeta
5826	Italy	Galatina
5827	Italy	Gallarate
5828	Italy	Gallipoli
5829	Italy	Gela
5830	Italy	Genoa
5831	Italy	Ghedi
5832	Italy	Giarre
5833	Italy	Ginosa
5834	Italy	Giovinazzo
5835	Italy	Giulianova
5836	Italy	Giussano
5837	Italy	Gorgonzola
5838	Italy	Gorizia
5839	Italy	Gragnano
5840	Italy	Grosseto
5841	Italy	Grottaferrata
5842	Italy	Grottaglie
5843	Italy	Grugliasco
5844	Italy	Guidonia
5845	Italy	Iglesias
5846	Italy	Imola
5847	Italy	Imperia
5848	Italy	Ischia
5849	Italy	Isernia
5850	Italy	Ivrea
5851	Italy	Jesi
5852	Italy	Ladispoli
5853	Italy	Lainate
5854	Italy	Lanciano
5855	Italy	Latina
5856	Italy	Lecce
5857	Italy	Lecco
5858	Italy	Legnago
5859	Italy	Legnano
5860	Italy	Lentini
5861	Italy	Licata
5862	Italy	Lido
5863	Italy	Limbiate
5864	Italy	Lissone
5865	Italy	Livorno
5866	Italy	Lodi
5867	Italy	Lucca
5868	Italy	Lucera
5869	Italy	Lugo
5870	Italy	Lumezzane
5871	Italy	Macerata
5872	Italy	Maddaloni
5873	Italy	Magenta
5874	Italy	Malnate
5875	Italy	Manduria
5876	Italy	Manfredonia
5877	Italy	Mantova
5878	Italy	Marcianise
5879	Italy	Marigliano
5880	Italy	Marino
5881	Italy	Marsala
5882	Italy	Mascalucia
5883	Italy	Massa
5884	Italy	Massafra
5885	Italy	Matera
5886	Italy	Meda
5887	Italy	Melegnano
5888	Italy	Melzo
5889	Italy	Mentana
5890	Italy	Merano
5891	Italy	Mesagne
5892	Italy	Messina
5893	Italy	Mestre
5894	Italy	Milano
5895	Italy	Milazzo
5896	Italy	Minturno
5897	Italy	Mirandola
5898	Italy	Mirano
5899	Italy	Misilmeri
5900	Italy	Misterbianco
5901	Italy	Modena
5902	Italy	Modica
5903	Italy	Modugno
5904	Italy	Molfetta
5905	Italy	Moncalieri
5906	Italy	Mondragone
5907	Italy	Monfalcone
5908	Italy	Monopoli
5909	Italy	Monreale
5910	Italy	Monserrato
5911	Italy	Montebelluna
5912	Italy	Montemurlo
5913	Italy	Monterotondo
5914	Italy	Monterusciello
5915	Italy	Montevarchi
5916	Italy	Montichiari
5917	Italy	Monza
5918	Italy	Napoli
5919	Italy	Nerviano
5920	Italy	Nettuno
5921	Italy	Nichelino
5922	Italy	Niscemi
5923	Italy	Noci
5924	Italy	Noicattaro
5925	Italy	Nola
5926	Italy	Noto
5927	Italy	Novara
5928	Italy	Nuoro
5929	Italy	Oderzo
5930	Italy	Olbia
5931	Italy	Orbassano
5932	Italy	Oristano
5933	Italy	Osimo
5934	Italy	Ostuni
5935	Italy	Ottaviano
5936	Italy	Pachino
5937	Italy	Padova
5938	Italy	Pagani
5939	Italy	Palagiano
5940	Italy	Palagonia
5941	Italy	Palermo
5942	Italy	Palmi
5943	Italy	Parabiago
5944	Italy	Parma
5945	Italy	Partinico
5946	Italy	Pavia
5947	Italy	Perugia
5948	Italy	Pesaro
5949	Italy	Pescara
5950	Italy	Piacenza
5951	Italy	Pietrasanta
5952	Italy	Pinerolo
5953	Italy	Pioltello
5954	Italy	Piombino
5955	Italy	Piossasco
5956	Italy	Pisa
5957	Italy	Pistoia
5958	Italy	Poggibonsi
5959	Italy	Poggiomarino
5960	Italy	Pomezia
5961	Italy	Pompei
5962	Italy	Pontedera
5963	Italy	Pordenone
5964	Italy	Portici
5965	Italy	Portogruaro
5966	Italy	Potenza
5967	Italy	Pozzallo
5968	Italy	Pozzuoli
5969	Italy	Prato
5970	Italy	Putignano
5971	Italy	Qualiano
5972	Italy	Quarto
5973	Italy	Quattromiglia
5974	Italy	Ragusa
5975	Italy	Rapallo
5976	Italy	Ravenna
5977	Italy	Rho
5978	Italy	Ribera
5979	Italy	Riccione
5980	Italy	Rieti
5981	Italy	Rimini
5982	Italy	Rivoli
5983	Italy	Rome
5984	Italy	Rosolini
5985	Italy	Rovereto
5986	Italy	Rovigo
5987	Italy	Rozzano
5988	Italy	Rutigliano
5989	Italy	Sacile
5990	Italy	Salerno
5991	Italy	Sarno
5992	Italy	Saronno
5993	Italy	Sarzana
5994	Italy	Sassari
5995	Italy	Sassuolo
5996	Italy	Sava
5997	Italy	Savigliano
5998	Italy	Savona
5999	Italy	Scafati
6000	Italy	Scandicci
6001	Italy	Schio
6002	Italy	Sciacca
6003	Italy	Scicli
6004	Italy	Scordia
6005	Italy	Segrate
6006	Italy	Selargius
6007	Italy	Senago
6008	Italy	Senigallia
6009	Italy	Seregno
6010	Italy	Seriate
6011	Italy	Sestu
6012	Italy	Seveso
6013	Italy	Sezze
6014	Italy	Siderno
6015	Italy	Siena
6016	Italy	Sinnai
6017	Italy	Siracusa
6018	Italy	Sondrio
6019	Italy	Sora
6020	Italy	Spoleto
6021	Italy	Sulmona
6022	Italy	Suzzara
6023	Italy	Taranto
6024	Italy	Teramo
6025	Italy	Terlizzi
6026	Italy	Termoli
6027	Italy	Terni
6028	Italy	Terracina
6029	Italy	Terzigno
6030	Italy	Thiene
6031	Italy	Tivoli
6032	Italy	Tolentino
6033	Italy	Torremaggiore
6034	Italy	Tortona
6035	Italy	Torvaianica
6036	Italy	Tradate
6037	Italy	Trani
6038	Italy	Trapani
6039	Italy	Trecate
6040	Italy	Trento
6041	Italy	Treviglio
6042	Italy	Treviso
6043	Italy	Trieste
6044	Italy	Triggiano
6045	Italy	Turin
6046	Italy	Udine
6047	Italy	Valdagno
6048	Italy	Valenza
6049	Italy	Valenzano
6050	Italy	Varese
6051	Italy	Vasto
6052	Italy	Velletri
6053	Italy	Venice
6054	Italy	Ventimiglia
6055	Italy	Verbania
6056	Italy	Vercelli
6057	Italy	Verona
6058	Italy	Viareggio
6059	Italy	Vicenza
6060	Italy	Vigevano
6061	Italy	Vignola
6062	Italy	Villabate
6063	Italy	Villanova
6064	Italy	Villaricca
6065	Italy	Vimercate
6066	Italy	Vimodrone
6067	Italy	Viterbo
6068	Italy	Vittoria
6069	Italy	Voghera
6070	Italy	Volla
6071	Jamaica	Kingston
6072	Jamaica	Linstead
6073	Jamaica	Mandeville
6074	Jamaica	Portmore
6075	Japan	Abashiri
6076	Japan	Abiko
6077	Japan	Ageoshimo
6078	Japan	Aioi
6079	Japan	Akashi
6080	Japan	Aki
6081	Japan	Akita
6082	Japan	Akitashi
6083	Japan	Akune
6084	Japan	Amagasaki
6085	Japan	Amagi
6086	Japan	Ami
6087	Japan	Anan
6088	Japan	Annaka
6089	Japan	Aomorishi
6090	Japan	Arai
6091	Japan	Asahi
6092	Japan	Asahikawa
6093	Japan	Asaka
6094	Japan	Ashibetsu
6095	Japan	Ashikaga
6096	Japan	Ashiya
6097	Japan	Aso
6098	Japan	Atami
6099	Japan	Atsugi
6100	Japan	Ayabe
6101	Japan	Beppu
6102	Japan	Bibai
6103	Japan	Bihoro
6104	Japan	Buzen
6105	Japan	Chatan
6106	Japan	Chiba
6107	Japan	Chichibu
6108	Japan	Chigasaki
6109	Japan	Chino
6110	Japan	Chitose
6111	Japan	Daigo
6112	Japan	Date
6113	Japan	Dazaifu
6114	Japan	Ebetsu
6115	Japan	Edosaki
6116	Japan	Enzan
6117	Japan	Fuji
6118	Japan	Fujieda
6119	Japan	Fujikawaguchiko
6120	Japan	Fujinomiya
6121	Japan	Fujioka
6122	Japan	Fujisawa
6123	Japan	Fujishiro
6124	Japan	Fukagawa
6125	Japan	Fukuchiyama
6126	Japan	Fukumitsu
6127	Japan	Fukuoka
6128	Japan	Fukura
6129	Japan	Fukuroi
6130	Japan	Fukushima
6131	Japan	Fukuyama
6132	Japan	Funaishikawa
6133	Japan	Furukawa
6134	Japan	Fussa
6135	Japan	Futtsu
6136	Japan	Gero
6137	Japan	Ginowan
6138	Japan	Gose
6139	Japan	Gosen
6140	Japan	Goshogawara
6141	Japan	Gotenba
6142	Japan	Gushikawa
6143	Japan	Hachinohe
6144	Japan	Hadano
6145	Japan	Hagi
6146	Japan	Hakodate
6147	Japan	Hakui
6148	Japan	Hamada
6149	Japan	Hamakita
6150	Japan	Hamamatsu
6151	Japan	Hamanoichi
6152	Japan	Hanamaki
6153	Japan	Hanawa
6154	Japan	Handa
6155	Japan	Hasaki
6156	Japan	Hashimoto
6157	Japan	Hasuda
6158	Japan	Hatsukaichi
6159	Japan	Hayama
6160	Japan	Hekinan
6161	Japan	Higashine
6162	Japan	Hiji
6163	Japan	Hikari
6164	Japan	Hikone
6165	Japan	Himeji
6166	Japan	Himimachi
6167	Japan	Hino
6168	Japan	Hirado
6169	Japan	Hirakata
6170	Japan	Hirara
6171	Japan	Hiratsuka
6172	Japan	Hirosaki
6173	Japan	Hiroshima
6174	Japan	Hita
6175	Japan	Hitachi
6176	Japan	Hitoyoshi
6177	Japan	Hobaramachi
6178	Japan	Hondo
6179	Japan	Hotaka
6180	Japan	Ibara
6181	Japan	Ibaraki
6182	Japan	Ibusuki
6183	Japan	Ichihara
6184	Japan	Ichinohe
6185	Japan	Ichinomiya
6186	Japan	Ichinoseki
6187	Japan	Iida
6188	Japan	Iiyama
6189	Japan	Iizuka
6190	Japan	Ikeda
6191	Japan	Ikoma
6192	Japan	Imaichi
6193	Japan	Ina
6194	Japan	Inashiki
6195	Japan	Inawashiro
6196	Japan	Inazawa
6197	Japan	Innoshima
6198	Japan	Ino
6199	Japan	Inuyama
6200	Japan	Isahaya
6201	Japan	Isawa
6202	Japan	Ise
6203	Japan	Isehara
6204	Japan	Isesaki
6205	Japan	Ishigaki
6206	Japan	Ishige
6207	Japan	Ishii
6208	Japan	Ishikari
6209	Japan	Ishikawa
6210	Japan	Ishiki
6211	Japan	Ishinomaki
6212	Japan	Ishioka
6213	Japan	Itako
6214	Japan	Itami
6215	Japan	Itoigawa
6216	Japan	Itoman
6217	Japan	Itsukaichi
6218	Japan	Iwade
6219	Japan	Iwai
6220	Japan	Iwaki
6221	Japan	Iwakuni
6222	Japan	Iwakura
6223	Japan	Iwamizawa
6224	Japan	Iwanai
6225	Japan	Iwanuma
6226	Japan	Iwase
6227	Japan	Iwata
6228	Japan	Iwatsuki
6229	Japan	Iyo
6230	Japan	Izumi
6231	Japan	Izumo
6232	Japan	Kadoma
6233	Japan	Kagoshima
6234	Japan	Kainan
6235	Japan	Kaizuka
6236	Japan	Kajiki
6237	Japan	Kakamigahara
6238	Japan	Kakegawa
6239	Japan	Kakuda
6240	Japan	Kamaishi
6241	Japan	Kamakura
6242	Japan	Kameoka
6243	Japan	Kameyama
6244	Japan	Kamifukuoka
6245	Japan	Kamiichi
6246	Japan	Kamiiso
6247	Japan	Kamimaruko
6248	Japan	Kaminokawa
6249	Japan	Kaminoyama
6250	Japan	Kamirenjaku
6251	Japan	Kamo
6252	Japan	Kamogawa
6253	Japan	Kanaya
6254	Japan	Kanazawa
6255	Japan	Kanda
6256	Japan	Kanekomachi
6257	Japan	Kanie
6258	Japan	Kanoya
6259	Japan	Kanuma
6260	Japan	Karasuyama
6261	Japan	Karatsu
6262	Japan	Kariya
6263	Japan	Kasama
6264	Japan	Kasaoka
6265	Japan	Kashihara
6266	Japan	Kashima
6267	Japan	Kashiwa
6268	Japan	Kashiwazaki
6269	Japan	Kasugai
6270	Japan	Kasukabe
6271	Japan	Katsuta
6272	Japan	Katsuura
6273	Japan	Katsuyama
6274	Japan	Kawage
6275	Japan	Kawagoe
6276	Japan	Kawaguchi
6277	Japan	Kawanishi
6278	Japan	Kawasaki
6279	Japan	Kazo
6280	Japan	Kikuchi
6281	Japan	Kimitsu
6282	Japan	Kisai
6283	Japan	Kisarazu
6284	Japan	Kishiwada
6285	Japan	Kitahama
6286	Japan	Kitahiroshima
6287	Japan	Kitaibaraki
6288	Japan	Kitakami
6289	Japan	Kitakata
6290	Japan	Kitakyushu
6291	Japan	Kitami
6292	Japan	Kitsuki
6293	Japan	Kobayashi
6294	Japan	Kobe
6295	Japan	Kochi
6296	Japan	Koga
6297	Japan	Kogota
6298	Japan	Kokubunji
6299	Japan	Komaki
6300	Japan	Komatsu
6301	Japan	Komono
6302	Japan	Komoro
6303	Japan	Koshigaya
6304	Japan	Kudamatsu
6305	Japan	Kumagaya
6306	Japan	Kumamoto
6307	Japan	Kurashiki
6308	Japan	Kurayoshi
6309	Japan	Kure
6310	Japan	Kurihashi
6311	Japan	Kuroda
6312	Japan	Kuroishi
6313	Japan	Kuroiso
6314	Japan	Kurume
6315	Japan	Kusatsu
6316	Japan	Kushikino
6317	Japan	Kushima
6318	Japan	Kushiro
6319	Japan	Kyoto
6320	Japan	Machida
6321	Japan	Maebashi
6322	Japan	Maizuru
6323	Japan	Makabe
6324	Japan	Maki
6325	Japan	Makubetsu
6326	Japan	Makurazaki
6327	Japan	Marugame
6328	Japan	Marumori
6329	Japan	Maruoka
6330	Japan	Mashiko
6331	Japan	Masuda
6332	Japan	Matsubara
6333	Japan	Matsubase
6334	Japan	Matsudo
6335	Japan	Matsue
6336	Japan	Matsumoto
6337	Japan	Matsushima
6338	Japan	Matsuyama
6339	Japan	Menuma
6340	Japan	Mibu
6341	Japan	Mihara
6342	Japan	Miharu
6343	Japan	Miki
6344	Japan	Mikuni
6345	Japan	Minamata
6346	Japan	Minamirinkan
6347	Japan	Minato
6348	Japan	Mino
6349	Japan	Minokamo
6350	Japan	Misawa
6351	Japan	Mishima
6352	Japan	Mitake
6353	Japan	Mito
6354	Japan	Mitsuke
6355	Japan	Miura
6356	Japan	Miyako
6357	Japan	Miyata
6358	Japan	Miyazaki
6359	Japan	Miyazu
6360	Japan	Miyoshi
6361	Japan	Mizunami
6362	Japan	Mizusawa
6363	Japan	Mobara
6364	Japan	Mombetsu
6365	Japan	Mooka
6366	Japan	Mori
6367	Japan	Moriguchi
6368	Japan	Morioka
6369	Japan	Moriya
6370	Japan	Moriyama
6371	Japan	Motegi
6372	Japan	Motomiya
6373	Japan	Muikamachi
6374	Japan	Murakami
6375	Japan	Muramatsu
6376	Japan	Muroran
6377	Japan	Musashino
6378	Japan	Mutsu
6379	Japan	Nabari
6380	Japan	Nagahama
6381	Japan	Nagai
6382	Japan	Nagano
6383	Japan	Nagaoka
6384	Japan	Nagareyama
6385	Japan	Nagasaki
6386	Japan	Nagato
6387	Japan	Nago
6388	Japan	Nagoya
6389	Japan	Naha
6390	Japan	Naka
6391	Japan	Nakama
6392	Japan	Nakamura
6393	Japan	Nakano
6394	Japan	Nakatsu
6395	Japan	Nakatsugawa
6396	Japan	Namerikawa
6397	Japan	Namie
6398	Japan	Namioka
6399	Japan	Nanae
6400	Japan	Nanao
6401	Japan	Narita
6402	Japan	Nayoro
6403	Japan	Naze
6404	Japan	Nemuro
6405	Japan	Neyagawa
6406	Japan	Nichinan
6407	Japan	Nihommatsu
6408	Japan	Niigata
6409	Japan	Niihama
6410	Japan	Niimi
6411	Japan	Ninomiya
6412	Japan	Nirasaki
6413	Japan	Nishifukuma
6414	Japan	Nishinoomote
6415	Japan	Nishio
6416	Japan	Nishishinminato
6417	Japan	Nishiwaki
6418	Japan	Nobeoka
6419	Japan	Noda
6420	Japan	Nonoichi
6421	Japan	Noshiro
6422	Japan	Numata
6423	Japan	Numazu
6424	Japan	Obama
6425	Japan	Obanazawa
6426	Japan	Obihiro
6427	Japan	Obita
6428	Japan	Odawara
6429	Japan	Ogawa
6430	Japan	Ojiya
6431	Japan	Okaya
6432	Japan	Okayama
6433	Japan	Okazaki
6434	Japan	Okegawa
6435	Japan	Okinawa
6436	Japan	Okunoya
6437	Japan	Omigawa
6438	Japan	Ono
6439	Japan	Onoda
6440	Japan	Onomichi
6441	Japan	Osaka
6442	Japan	Otaru
6443	Japan	Otofuke
6444	Japan	Owase
6445	Japan	Oyama
6446	Japan	Rifu
6447	Japan	Rumoi
6448	Japan	Sabae
6449	Japan	Saga
6450	Japan	Sagae
6451	Japan	Sagara
6452	Japan	Saiki
6453	Japan	Saitama
6454	Japan	Sakado
6455	Japan	Sakai
6456	Japan	Sakaiminato
6457	Japan	Sakata
6458	Japan	Saku
6459	Japan	Sakura
6460	Japan	Sakurai
6461	Japan	Sano
6462	Japan	Sapporo
6463	Japan	Sasaguri
6464	Japan	Sasayama
6465	Japan	Sasebo
6466	Japan	Satsumasendai
6467	Japan	Satte
6468	Japan	Sawara
6469	Japan	Sayama
6470	Japan	Sendai
6471	Japan	Seto
6472	Japan	Shibata
6473	Japan	Shibetsu
6474	Japan	Shibukawa
6475	Japan	Shibushi
6476	Japan	Shido
6477	Japan	Shiki
6478	Japan	Shimabara
6479	Japan	Shimada
6480	Japan	Shimoda
6481	Japan	Shimodate
6482	Japan	Shimokizukuri
6483	Japan	Shimonoseki
6484	Japan	Shimotoda
6485	Japan	Shinshiro
6486	Japan	Shiogama
6487	Japan	Shiojiri
6488	Japan	Shiozawa
6489	Japan	Shiraoi
6490	Japan	Shiraoka
6491	Japan	Shiroi
6492	Japan	Shiroishi
6493	Japan	Shirone
6494	Japan	Shisui
6495	Japan	Shizukuishi
6496	Japan	Shizuoka
6497	Japan	Sobue
6498	Japan	Sugito
6499	Japan	Suibara
6500	Japan	Suita
6501	Japan	Sukagawa
6502	Japan	Sukumo
6503	Japan	Sumoto
6504	Japan	Sunagawa
6505	Japan	Susaki
6506	Japan	Suwa
6507	Japan	Suzaka
6508	Japan	Suzuka
6509	Japan	Tadotsu
6510	Japan	Tagawa
6511	Japan	Tahara
6512	Japan	Tajimi
6513	Japan	Takahagi
6514	Japan	Takahama
6515	Japan	Takahashi
6516	Japan	Takahata
6517	Japan	Takaishi
6518	Japan	Takamatsu
6519	Japan	Takanabe
6520	Japan	Takanosu
6521	Japan	Takaoka
6522	Japan	Takarazuka
6523	Japan	Takasaki
6524	Japan	Takatsuki
6525	Japan	Takayama
6526	Japan	Takedamachi
6527	Japan	Takefu
6528	Japan	Takehara
6529	Japan	Taketoyo
6530	Japan	Takikawa
6531	Japan	Tamamura
6532	Japan	Tamana
6533	Japan	Tamano
6534	Japan	Tanabe
6535	Japan	Tanuma
6536	Japan	Tarui
6537	Japan	Tarumizu
6538	Japan	Tatebayashi
6539	Japan	Tateyama
6540	Japan	Tatsuno
6541	Japan	Tawaramoto
6542	Japan	Tenri
6543	Japan	Toba
6544	Japan	Tochigi
6545	Japan	Togitsu
6546	Japan	Toki
6547	Japan	Tokoname
6548	Japan	Tokorozawa
6549	Japan	Tokushima
6550	Japan	Tokuyama
6551	Japan	Tokyo
6552	Japan	Tomakomai
6553	Japan	Tomigusuku
6554	Japan	Tomioka
6555	Japan	Tomiya
6556	Japan	Tomobe
6557	Japan	Toride
6558	Japan	Tosu
6559	Japan	Tottori
6560	Japan	Toyama
6561	Japan	Toyohama
6562	Japan	Toyohashi
6563	Japan	Toyokawa
6564	Japan	Toyonaka
6565	Japan	Toyooka
6566	Japan	Toyoshina
6567	Japan	Toyota
6568	Japan	Tsu
6569	Japan	Tsubame
6570	Japan	Tsubata
6571	Japan	Tsukawaki
6572	Japan	Tsukuba
6573	Japan	Tsukumiura
6574	Japan	Tsuma
6575	Japan	Tsuruga
6576	Japan	Tsuruoka
6577	Japan	Tsurusaki
6578	Japan	Tsushima
6579	Japan	Tsuyama
6580	Japan	Ube
6581	Japan	Ueda
6582	Japan	Ueki
6583	Japan	Uenohara
6584	Japan	Uji
6585	Japan	Ujiie
6586	Japan	Umi
6587	Japan	Uozu
6588	Japan	Urayasu
6589	Japan	Ushibuka
6590	Japan	Ushiku
6591	Japan	Usuki
6592	Japan	Uto
6593	Japan	Utsunomiya
6594	Japan	Uwajima
6595	Japan	Wakayama
6596	Japan	Wakimachi
6597	Japan	Wakkanai
6598	Japan	Wako
6599	Japan	Wakuya
6600	Japan	Watari
6601	Japan	Yachimata
6602	Japan	Yaita
6603	Japan	Yaizu
6604	Japan	Yamada
6605	Japan	Yamaga
6606	Japan	Yamagata
6607	Japan	Yamaguchi
6608	Japan	Yamoto
6609	Japan	Yanagawa
6610	Japan	Yanai
6611	Japan	Yao
6612	Japan	Yashiro
6613	Japan	Yatsushiro
6614	Japan	Yawata
6615	Japan	Yoichi
6616	Japan	Yokkaichi
6617	Japan	Yokohama
6618	Japan	Yokosuka
6619	Japan	Yokotemachi
6620	Japan	Yonago
6621	Japan	Yonezawa
6622	Japan	Yono
6623	Japan	Yorii
6624	Japan	Yoshii
6625	Japan	Yoshikawa
6626	Japan	Youkaichi
6627	Japan	Yugawara
6628	Japan	Yukuhashi
6629	Japan	Yuza
6630	Japan	Yuzawa
6631	Japan	Zama
6632	Japan	Zushi
6633	Jordan	Amman
6634	Jordan	Aqaba
6635	Jordan	Irbid
6636	Jordan	Jarash
6637	Jordan	Judita
6638	Jordan	Kurayyimah
6639	Jordan	Mafraq
6640	Jordan	Russeifa
6641	Jordan	Safi
6642	Jordan	Zarqa
6643	Kazakhstan	Abay
6644	Kazakhstan	Aksu
6645	Kazakhstan	Aktau
6646	Kazakhstan	Almaty
6647	Kazakhstan	Aqsay
6648	Kazakhstan	Aral
6649	Kazakhstan	Arkalyk
6650	Kazakhstan	Arys
6651	Kazakhstan	Astana
6652	Kazakhstan	Atbasar
6653	Kazakhstan	Atyrau
6654	Kazakhstan	Ayagoz
6655	Kazakhstan	Balqash
6656	Kazakhstan	Balyqshy
6657	Kazakhstan	Baykonyr
6658	Kazakhstan	Burunday
6659	Kazakhstan	Chu
6660	Kazakhstan	Dzhetygara
6661	Kazakhstan	Ekibastuz
6662	Kazakhstan	Embi
6663	Kazakhstan	Esik
6664	Kazakhstan	Kandyagash
6665	Kazakhstan	Kapshagay
6666	Kazakhstan	Karagandy
6667	Kazakhstan	Karatau
6668	Kazakhstan	Kentau
6669	Kazakhstan	Khromtau
6670	Kazakhstan	Kokshetau
6671	Kazakhstan	Kostanay
6672	Kazakhstan	Kyzylorda
6673	Kazakhstan	Lenger
6674	Kazakhstan	Lisakovsk
6675	Kazakhstan	Merke
6676	Kazakhstan	Oral
6677	Kazakhstan	Pavlodar
6678	Kazakhstan	Petropavl
6679	Kazakhstan	Qulsary
6680	Kazakhstan	Ridder
6681	Kazakhstan	Rudnyy
6682	Kazakhstan	Sarkand
6683	Kazakhstan	Saryaghash
6684	Kazakhstan	Sarykemer
6685	Kazakhstan	Semey
6686	Kazakhstan	Shalkar
6687	Kazakhstan	Shalqar
6688	Kazakhstan	Shardara
6689	Kazakhstan	Shymkent
6690	Kazakhstan	Sorang
6691	Kazakhstan	Stepnogorsk
6692	Kazakhstan	Taldykorgan
6693	Kazakhstan	Taldyqorghan
6694	Kazakhstan	Talghar
6695	Kazakhstan	Taraz
6696	Kazakhstan	Tekeli
6697	Kazakhstan	Temirtau
6698	Kazakhstan	Turkestan
6699	Kazakhstan	Vannovka
6700	Kazakhstan	Yanykurgan
6701	Kazakhstan	Zaysan
6702	Kazakhstan	Zhanaozen
6703	Kazakhstan	Zhangatas
6704	Kazakhstan	Zharkent
6705	Kazakhstan	Zhezqazghan
6706	Kazakhstan	Zhosaly
6707	Kazakhstan	Zyryanovsk
6708	Kenya	Bungoma
6709	Kenya	Busia
6710	Kenya	Eldoret
6711	Kenya	Embu
6712	Kenya	Garissa
6713	Kenya	Isiolo
6714	Kenya	Kabarnet
6715	Kenya	Kakamega
6716	Kenya	Kapenguria
6717	Kenya	Karuri
6718	Kenya	Kericho
6719	Kenya	Keruguya
6720	Kenya	Kiambu
6721	Kenya	Kilifi
6722	Kenya	Kisii
6723	Kenya	Kisumu
6724	Kenya	Kitale
6725	Kenya	Kitui
6726	Kenya	Lamu
6727	Kenya	Lodwar
6728	Kenya	Lugulu
6729	Kenya	Machakos
6730	Kenya	Makueni
6731	Kenya	Malindi
6732	Kenya	Mandera
6733	Kenya	Maralal
6734	Kenya	Marsabit
6735	Kenya	Mbale
6736	Kenya	Meru
6737	Kenya	Migori
6738	Kenya	Molo
6739	Kenya	Mombasa
6740	Kenya	Moyale
6741	Kenya	Muhoroni
6742	Kenya	Mumias
6743	Kenya	Nairobi
6744	Kenya	Naivasha
6745	Kenya	Nakuru
6746	Kenya	Nanyuki
6747	Kenya	Narok
6748	Kenya	Nyahururu
6749	Kenya	Nyeri
6750	Kenya	Pumwani
6751	Kenya	Rongai
6752	Kenya	Siaya
6753	Kenya	Thika
6754	Kenya	Voi
6755	Kenya	Wajir
6756	Kenya	Webuye
6757	Kiribati	Tarawa
6758	Kosovo	Dragash
6759	Kosovo	Ferizaj
6760	Kosovo	Gjilan
6761	Kosovo	Glogovac
6762	Kosovo	Istok
6763	Kosovo	Leposaviq
6764	Kosovo	Orahovac
6765	Kosovo	Podujeva
6766	Kosovo	Pristina
6767	Kosovo	Prizren
6768	Kosovo	Shtime
6769	Kosovo	Vitina
6770	Kosovo	Vushtrri
6771	Kyrgyzstan	Balykchy
6772	Kyrgyzstan	Bishkek
6773	Kyrgyzstan	Iradan
6774	Kyrgyzstan	Isfana
6775	Kyrgyzstan	Kant
6776	Kyrgyzstan	Karakol
6777	Kyrgyzstan	Naryn
6778	Kyrgyzstan	Osh
6779	Kyrgyzstan	Suluktu
6780	Kyrgyzstan	Talas
6781	Kyrgyzstan	Tokmok
6782	Kyrgyzstan	Toktogul
6783	Kyrgyzstan	Uzgen
6784	Laos	Phonsavan
6785	Laos	Vangviang
6786	Laos	Vientiane
6787	Latvia	Daugavpils
6788	Latvia	Jelgava
6789	Latvia	Ogre
6790	Latvia	Riga
6791	Latvia	Salaspils
6792	Latvia	Tukums
6793	Latvia	Valmiera
6794	Latvia	Ventspils
6795	Lebanon	Baalbek
6796	Lebanon	Beirut
6797	Lebanon	Djounie
6798	Lebanon	Sidon
6799	Lebanon	Tripoli
6800	Lebanon	Tyre
6801	Lesotho	Leribe
6802	Lesotho	Mafeteng
6803	Lesotho	Maputsoe
6804	Lesotho	Maseru
6805	Lesotho	Quthing
6806	Liberia	Bensonville
6807	Liberia	Buchanan
6808	Liberia	Gbarnga
6809	Liberia	Greenville
6810	Liberia	Harper
6811	Liberia	Kakata
6812	Liberia	Monrovia
6813	Liberia	Voinjama
6814	Liberia	Zwedru
6815	Libya	Ajdabiya
6816	Libya	Benghazi
6817	Libya	Brak
6818	Libya	Darnah
6819	Libya	Gharyan
6820	Libya	Ghat
6821	Libya	Mizdah
6822	Libya	Murzuq
6823	Libya	Sirte
6824	Libya	Tagiura
6825	Libya	Tarhuna
6826	Libya	Tobruk
6827	Libya	Tripoli
6828	Libya	Yafran
6829	Libya	Zawiya
6830	Libya	Zliten
6831	Liechtenstein	Vaduz
6832	Lithuania	Aleksotas
6833	Lithuania	Alytus
6834	Lithuania	Druskininkai
6835	Lithuania	Eiguliai
6836	Lithuania	Jonava
6837	Lithuania	Kaunas
6838	Lithuania	Kretinga
6839	Lithuania	Lazdynai
6840	Lithuania	Mazeikiai
6841	Lithuania	Naujamiestis
6842	Lithuania	Palanga
6843	Lithuania	Plunge
6844	Lithuania	Radviliskis
6845	Lithuania	Silute
6846	Lithuania	Taurage
6847	Lithuania	Telsiai
6848	Lithuania	Ukmerge
6849	Lithuania	Utena
6850	Lithuania	Vilnius
6851	Lithuania	Visaginas
6852	Luxembourg	Dudelange
6853	Luxembourg	Luxembourg
6854	Macao	Macau
6855	Macedonia	Bitola
6856	Macedonia	Bogovinje
6857	Macedonia	Brvenica
6858	Macedonia	Butel
6859	Macedonia	Debar
6860	Macedonia	Delcevo
6861	Macedonia	Gevgelija
6862	Macedonia	Gostivar
6863	Macedonia	Ilinden
6864	Macedonia	Kamenjane
6865	Macedonia	Kavadarci
6866	Macedonia	Kochani
6867	Macedonia	Kumanovo
6868	Macedonia	Negotino
6869	Macedonia	Ohrid
6870	Macedonia	Prilep
6871	Macedonia	Shtip
6872	Macedonia	Skopje
6873	Macedonia	Struga
6874	Macedonia	Strumica
6875	Macedonia	Tetovo
6876	Macedonia	Veles
6877	Macedonia	Vinica
6878	Madagascar	Alarobia
6879	Madagascar	Ambalavao
6880	Madagascar	Ambanja
6881	Madagascar	Ambarakaraka
6882	Madagascar	Ambatofinandrahana
6883	Madagascar	Ambatolampy
6884	Madagascar	Ambatondrazaka
6885	Madagascar	Ambilobe
6886	Madagascar	Amboanjo
6887	Madagascar	Amboasary
6888	Madagascar	Ambohitrolomahitsy
6889	Madagascar	Ambositra
6890	Madagascar	Ambovombe
6891	Madagascar	Ampahana
6892	Madagascar	Ampanihy
6893	Madagascar	Amparafaravola
6894	Madagascar	Ampasimanolotra
6895	Madagascar	Andapa
6896	Madagascar	Andilamena
6897	Madagascar	Anjozorobe
6898	Madagascar	Ankazoabo
6899	Madagascar	Ankazobe
6900	Madagascar	Ankazondandy
6901	Madagascar	Antalaha
6902	Madagascar	Antananarivo
6903	Madagascar	Antanifotsy
6904	Madagascar	Antsirabe
6905	Madagascar	Antsiranana
6906	Madagascar	Antsohihy
6907	Madagascar	Antsohimbondrona
6908	Madagascar	Arivonimamo
6909	Madagascar	Bealanana
6910	Madagascar	Beloha
6911	Madagascar	Beroroha
6912	Madagascar	Betafo
6913	Madagascar	Betioky
6914	Madagascar	Fandriana
6915	Madagascar	Farafangana
6916	Madagascar	Faratsiho
6917	Madagascar	Fianarantsoa
6918	Madagascar	Ifanadiana
6919	Madagascar	Ihosy
6920	Madagascar	Ikalamavony
6921	Madagascar	Ikongo
6922	Madagascar	Maevatanana
6923	Madagascar	Mahajanga
6924	Madagascar	Mahanoro
6925	Madagascar	Maintirano
6926	Madagascar	Manakara
6927	Madagascar	Mananara
6928	Madagascar	Mananjary
6929	Madagascar	Manjakandriana
6930	Madagascar	Maroantsetra
6931	Madagascar	Marolambo
6932	Madagascar	Marovoay
6933	Madagascar	Miandrarivo
6934	Madagascar	Miandrivazo
6935	Madagascar	Moramanga
6936	Madagascar	Morondava
6937	Madagascar	Sadabe
6938	Madagascar	Sahavato
6939	Madagascar	Sakaraha
6940	Madagascar	Sambava
6941	Madagascar	Sitampiky
6942	Madagascar	Soanindrariny
6943	Madagascar	Soavinandriana
6944	Madagascar	Toamasina
6945	Madagascar	Toliara
6946	Madagascar	Tsaratanana
6947	Madagascar	Tsiombe
6948	Madagascar	Tsiroanomandidy
6949	Madagascar	Vangaindrano
6950	Madagascar	Vavatenina
6951	Madagascar	Vohibinany
6952	Madagascar	Vohipaho
6953	Madagascar	Vondrozo
6954	Malawi	Balaka
6955	Malawi	Blantyre
6956	Malawi	Dedza
6957	Malawi	Karonga
6958	Malawi	Kasungu
6959	Malawi	Lilongwe
6960	Malawi	Liwonde
6961	Malawi	Mangochi
6962	Malawi	Mchinji
6963	Malawi	Mulanje
6964	Malawi	Mzimba
6965	Malawi	Mzuzu
6966	Malawi	Nkhotakota
6967	Malawi	Nsanje
6968	Malawi	Rumphi
6969	Malawi	Salima
6970	Malawi	Zomba
6971	Malaysia	Bahau
6972	Malaysia	Bakri
6973	Malaysia	Banting
6974	Malaysia	Beaufort
6975	Malaysia	Bedong
6976	Malaysia	Bidur
6977	Malaysia	Bintulu
6978	Malaysia	Butterworth
6979	Malaysia	Cukai
6980	Malaysia	Donggongon
6981	Malaysia	Gurun
6982	Malaysia	Ipoh
6983	Malaysia	Jenjarum
6984	Malaysia	Jerantut
6985	Malaysia	Jitra
6986	Malaysia	Kampar
6987	Malaysia	Kangar
6988	Malaysia	Kapit
6989	Malaysia	Keningau
6990	Malaysia	Kertih
6991	Malaysia	Kinarut
6992	Malaysia	Klang
6993	Malaysia	Kluang
6994	Malaysia	Kuah
6995	Malaysia	Kuang
6996	Malaysia	Kuantan
6997	Malaysia	Kuching
6998	Malaysia	Kudat
6999	Malaysia	Kulai
7000	Malaysia	Kulim
7001	Malaysia	Labis
7002	Malaysia	Limbang
7003	Malaysia	Lumut
7004	Malaysia	Malacca
7005	Malaysia	Marang
7006	Malaysia	Mentekab
7007	Malaysia	Mersing
7008	Malaysia	Miri
7009	Malaysia	Muar
7010	Malaysia	Paka
7011	Malaysia	Papar
7012	Malaysia	Pekan
7013	Malaysia	Perai
7014	Malaysia	Peringat
7015	Malaysia	Putatan
7016	Malaysia	Putrajaya
7017	Malaysia	Ranau
7018	Malaysia	Raub
7019	Malaysia	Rawang
7020	Malaysia	Sandakan
7021	Malaysia	Sarikei
7022	Malaysia	Segamat
7023	Malaysia	Semenyih
7024	Malaysia	Semporna
7025	Malaysia	Sepang
7026	Malaysia	Seremban
7027	Malaysia	Serendah
7028	Malaysia	Sibu
7029	Malaysia	Simanggang
7030	Malaysia	Skudai
7031	Malaysia	Taiping
7032	Malaysia	Tampin
7033	Malaysia	Tangkak
7034	Malaysia	Tawau
7035	Malaysia	Temerluh
7036	Malaysia	Victoria
7037	Maldives	Male
7038	Mali	Bamako
7039	Mali	Banamba
7040	Mali	Bougouni
7041	Mali	Gao
7042	Mali	Kangaba
7043	Mali	Kati
7044	Mali	Kayes
7045	Mali	Kolokani
7046	Mali	Koulikoro
7047	Mali	Koutiala
7048	Mali	Markala
7049	Mali	Mopti
7050	Mali	Sagalo
7051	Mali	San
7052	Mali	Sikasso
7053	Mali	Timbuktu
7054	Mali	Yorosso
7055	Malta	Birkirkara
7056	Malta	Mosta
7057	Malta	Qormi
7058	Malta	Valletta
7059	Martinique	Ducos
7060	Mauritania	Aleg
7061	Mauritania	Atar
7062	Mauritania	Kiffa
7063	Mauritania	Nouakchott
7064	Mauritania	Rosso
7065	Mauritania	Zouerate
7066	Mauritius	Curepipe
7067	Mauritius	Goodlands
7068	Mauritius	Triolet
7069	Mauritius	Vacoas
7070	Mayotte	Dzaoudzi
7071	Mayotte	Koungou
7072	Mayotte	Mamoudzou
7073	Mexico	Abasolo
7074	Mexico	Acajete
7075	Mexico	Acaponeta
7076	Mexico	Acayucan
7077	Mexico	Actopan
7078	Mexico	Aguascalientes
7079	Mexico	Ajalpan
7080	Mexico	Allende
7081	Mexico	Altamira
7082	Mexico	Altepexi
7083	Mexico	Altotonga
7084	Mexico	Ameca
7085	Mexico	Amecameca
7086	Mexico	Apan
7087	Mexico	Apizaco
7088	Mexico	Apodaca
7089	Mexico	Arandas
7090	Mexico	Arcelia
7091	Mexico	Armeria
7092	Mexico	Arriaga
7093	Mexico	Atlacomulco
7094	Mexico	Atlixco
7095	Mexico	Axochiapan
7096	Mexico	Azcapotzalco
7097	Mexico	Banderilla
7098	Mexico	Buenavista
7099	Mexico	Cadereyta
7100	Mexico	Calpulalpan
7101	Mexico	Calvillo
7102	Mexico	Campeche
7103	Mexico	Cananea
7104	Mexico	Capulhuac
7105	Mexico	Cardenas
7106	Mexico	Catemaco
7107	Mexico	Celaya
7108	Mexico	Chapala
7109	Mexico	Chetumal
7110	Mexico	Chiautempan
7111	Mexico	Chiautla
7112	Mexico	Chiconcuac
7113	Mexico	Chignahuapan
7114	Mexico	Chihuahua
7115	Mexico	Cholula
7116	Mexico	Coacalco
7117	Mexico	Coatepec
7118	Mexico	Coatzacoalcos
7119	Mexico	Coatzintla
7120	Mexico	Colima
7121	Mexico	Comalcalco
7122	Mexico	Comonfort
7123	Mexico	Compostela
7124	Mexico	Cortazar
7125	Mexico	Cosoleacaque
7126	Mexico	Coyotepec
7127	Mexico	Crucecita
7128	Mexico	Cuajimalpa
7129	Mexico	Cuautlancingo
7130	Mexico	Cuernavaca
7131	Mexico	Ecatepec
7132	Mexico	Empalme
7133	Mexico	Ensenada
7134	Mexico	Fresnillo
7135	Mexico	Frontera
7136	Mexico	Guacamayas
7137	Mexico	Guadalajara
7138	Mexico	Guadalupe
7139	Mexico	Guanajuato
7140	Mexico	Guasave
7141	Mexico	Hermosillo
7142	Mexico	Hidalgo
7143	Mexico	Huamantla
7144	Mexico	Huatabampo
7145	Mexico	Huauchinango
7146	Mexico	Huejotzingo
7147	Mexico	Huilango
7148	Mexico	Huimanguillo
7149	Mexico	Huixquilucan
7150	Mexico	Huixtla
7151	Mexico	Irapuato
7152	Mexico	Ixmiquilpan
7153	Mexico	Ixtapa
7154	Mexico	Ixtapaluca
7155	Mexico	Iztacalco
7156	Mexico	Iztapalapa
7157	Mexico	Jamay
7158	Mexico	Jiutepec
7159	Mexico	Jocotepec
7160	Mexico	Jojutla
7161	Mexico	Linares
7162	Mexico	Loreto
7163	Mexico	Macuspana
7164	Mexico	Malinaltepec
7165	Mexico	Manzanillo
7166	Mexico	Mapastepec
7167	Mexico	Marfil
7168	Mexico	Matamoros
7169	Mexico	Matehuala
7170	Mexico	Medina
7171	Mexico	Metepec
7172	Mexico	Mexicali
7173	Mexico	Minatitlan
7174	Mexico	Miramar
7175	Mexico	Misantla
7176	Mexico	Monclova
7177	Mexico	Montemorelos
7178	Mexico	Monterrey
7179	Mexico	Morelia
7180	Mexico	Motozintla
7181	Mexico	Motul
7182	Mexico	Moyotzingo
7183	Mexico	Naranjos
7184	Mexico	Nava
7185	Mexico	Navojoa
7186	Mexico	Navolato
7187	Mexico	Nogales
7188	Mexico	Ocosingo
7189	Mexico	Ocoyoacac
7190	Mexico	Ojinaga
7191	Mexico	Ometepec
7192	Mexico	Orizaba
7193	Mexico	Oxkutzkab
7194	Mexico	Palau
7195	Mexico	Palenque
7196	Mexico	Papalotla
7197	Mexico	Paraiso
7198	Mexico	Perote
7199	Mexico	Peto
7200	Mexico	Pijijiapan
7201	Mexico	Polanco
7202	Mexico	Puebla
7203	Mexico	Reynosa
7204	Mexico	Romita
7205	Mexico	Rosarito
7206	Mexico	Salamanca
7207	Mexico	Saltillo
7208	Mexico	Salvatierra
7209	Mexico	Sanctorum
7210	Mexico	Santiago
7211	Mexico	Sayula
7212	Mexico	Silao
7213	Mexico	Sombrerete
7214	Mexico	Tala
7215	Mexico	Tamazunchale
7216	Mexico	Tampico
7217	Mexico	Tantoyuca
7218	Mexico	Tapachula
7219	Mexico	Teapa
7220	Mexico	Tecamachalco
7221	Mexico	Tecate
7222	Mexico	Tecax
7223	Mexico	Tecoman
7224	Mexico	Teloloapan
7225	Mexico	Temapache
7226	Mexico	Temixco
7227	Mexico	Teocaltiche
7228	Mexico	Teolocholco
7229	Mexico	Teoloyucan
7230	Mexico	Tepalcatepec
7231	Mexico	Tepeaca
7232	Mexico	Tepic
7233	Mexico	Tequila
7234	Mexico	Tequisquiapan
7235	Mexico	Tequixquiac
7236	Mexico	Teziutlan
7237	Mexico	Ticul
7238	Mexico	Tijuana
7239	Mexico	Tizayuca
7240	Mexico	Tlahuac
7241	Mexico	Tlalnepantla
7242	Mexico	Tlalpan
7243	Mexico	Tlapacoyan
7244	Mexico	Tlaquepaque
7245	Mexico	Tlaquiltenango
7246	Mexico	Tlazcalancingo
7247	Mexico	Toluca
7248	Mexico	Torreon
7249	Mexico	Tulancingo
7250	Mexico	Tultepec
7251	Mexico	Tuxpan
7252	Mexico	Tuxtepec
7253	Mexico	Uman
7254	Mexico	Uriangato
7255	Mexico	Uruapan
7256	Mexico	Valladolid
7257	Mexico	Venceremos
7258	Mexico	Veracruz
7259	Mexico	Villahermosa
7260	Mexico	Xico
7261	Mexico	Xochimilco
7262	Mexico	Xochitepec
7263	Mexico	Xoxocotla
7264	Mexico	Yautepec
7265	Mexico	Yecapixtla
7266	Mexico	Yuriria
7267	Mexico	Zacatecas
7268	Mexico	Zacatelco
7269	Mexico	Zacatepec
7270	Mexico	Zamora
7271	Mexico	Zapopan
7272	Mexico	Zapotiltic
7273	Mexico	Zapotlanejo
7274	Mexico	Zumpango
7275	Moldova	Bender
7276	Moldova	Cahul
7277	Moldova	Comrat
7278	Moldova	Drochia
7279	Moldova	Orhei
7280	Moldova	Slobozia
7281	Moldova	Soroca
7282	Moldova	Tiraspolul
7283	Moldova	Ungheni
7284	Monaco	Monaco
7285	Mongolia	Altai
7286	Mongolia	Arvayheer
7287	Mongolia	Bayanhongor
7288	Mongolia	Bulgan
7289	Mongolia	Dalandzadgad
7290	Mongolia	Darhan
7291	Mongolia	Erdenet
7292	Mongolia	Hovd
7293	Mongolia	Khovd
7294	Mongolia	Mandalgovi
7295	Mongolia	Saynshand
7296	Mongolia	Ulaangom
7297	Mongolia	Uliastay
7298	Montenegro	Bar
7299	Montenegro	Budva
7300	Montenegro	Cetinje
7301	Montenegro	Pljevlja
7302	Montenegro	Podgorica
7303	Montserrat	Brades
7304	Montserrat	Plymouth
7305	Morocco	Agadir
7306	Morocco	Ahfir
7307	Morocco	Asilah
7308	Morocco	Azemmour
7309	Morocco	Azrou
7310	Morocco	Berkane
7311	Morocco	Berrechid
7312	Morocco	Boujniba
7313	Morocco	Bouznika
7314	Morocco	Casablanca
7315	Morocco	Chefchaouene
7316	Morocco	Dakhla
7317	Morocco	Essaouira
7318	Morocco	Fes
7319	Morocco	Guelmim
7320	Morocco	Guercif
7321	Morocco	Jerada
7322	Morocco	Kenitra
7323	Morocco	Khemisset
7324	Morocco	Khenifra
7325	Morocco	Khouribga
7326	Morocco	Larache
7327	Morocco	Marrakesh
7328	Morocco	Martil
7329	Morocco	Midelt
7330	Morocco	Mohammedia
7331	Morocco	Nador
7332	Morocco	Ouarzazat
7333	Morocco	Ouezzane
7334	Morocco	Oujda
7335	Morocco	Rabat
7336	Morocco	Safi
7337	Morocco	Sale
7338	Morocco	Sefrou
7339	Morocco	Settat
7340	Morocco	Skhirate
7341	Morocco	Tahla
7342	Morocco	Tangier
7343	Morocco	Taounate
7344	Morocco	Taourirt
7345	Morocco	Taroudant
7346	Morocco	Taza
7347	Morocco	Tiflet
7348	Morocco	Tinghir
7349	Morocco	Tiznit
7350	Morocco	Youssoufia
7351	Morocco	Zagora
7352	Mozambique	Beira
7353	Mozambique	Chibuto
7354	Mozambique	Chimoio
7355	Mozambique	Cuamba
7356	Mozambique	Dondo
7357	Mozambique	Inhambane
7358	Mozambique	Lichinga
7359	Mozambique	Macia
7360	Mozambique	Manjacaze
7361	Mozambique	Maputo
7362	Mozambique	Matola
7363	Mozambique	Maxixe
7364	Mozambique	Montepuez
7365	Mozambique	Nacala
7366	Mozambique	Nampula
7367	Mozambique	Pemba
7368	Mozambique	Quelimane
7369	Mozambique	Tete
7370	Myanmar	Bago
7371	Myanmar	Bhamo
7372	Myanmar	Bogale
7373	Myanmar	Chauk
7374	Myanmar	Dawei
7375	Myanmar	Hakha
7376	Myanmar	Hinthada
7377	Myanmar	Kanbe
7378	Myanmar	Kayan
7379	Myanmar	Kyaikkami
7380	Myanmar	Kyaiklat
7381	Myanmar	Kyaikto
7382	Myanmar	Kyaukse
7383	Myanmar	Lashio
7384	Myanmar	Letpandan
7385	Myanmar	Loikaw
7386	Myanmar	Magway
7387	Myanmar	Mandalay
7388	Myanmar	Martaban
7389	Myanmar	Maubin
7390	Myanmar	Mawlaik
7391	Myanmar	Mawlamyine
7392	Myanmar	Mawlamyinegyunn
7393	Myanmar	Meiktila
7394	Myanmar	Minbu
7395	Myanmar	Mogok
7396	Myanmar	Monywa
7397	Myanmar	Mudon
7398	Myanmar	Myanaung
7399	Myanmar	Myawadi
7400	Myanmar	Myaydo
7401	Myanmar	Myeik
7402	Myanmar	Myingyan
7403	Myanmar	Myitkyina
7404	Myanmar	Nyaungdon
7405	Myanmar	Nyaunglebin
7406	Myanmar	Pakokku
7407	Myanmar	Pathein
7408	Myanmar	Paungde
7409	Myanmar	Pyapon
7410	Myanmar	Pyay
7411	Myanmar	Pyinmana
7412	Myanmar	Pyu
7413	Myanmar	Sagaing
7414	Myanmar	Shwebo
7415	Myanmar	Sittwe
7416	Myanmar	Syriam
7417	Myanmar	Taungdwingyi
7418	Myanmar	Taunggyi
7419	Myanmar	Taungoo
7420	Myanmar	Thanatpin
7421	Myanmar	Tharyarwady
7422	Myanmar	Thaton
7423	Myanmar	Thayetmyo
7424	Myanmar	Thongwa
7425	Myanmar	Twante
7426	Myanmar	Wakema
7427	Myanmar	Yamethin
7428	Myanmar	Yangon
7429	Myanmar	Yenangyaung
7430	Namibia	Gobabis
7431	Namibia	Grootfontein
7432	Namibia	Keetmanshoop
7433	Namibia	Okahandja
7434	Namibia	Oshakati
7435	Namibia	Otjiwarongo
7436	Namibia	Rehoboth
7437	Namibia	Rundu
7438	Namibia	Swakopmund
7439	Namibia	Windhoek
7440	Nauru	Yaren
7441	Nepal	Bhadrapur
7442	Nepal	Bharatpur
7443	Nepal	Birendranagar
7444	Nepal	Dailekh
7445	Nepal	Dhangarhi
7446	Nepal	Dipayal
7447	Nepal	Gaur
7448	Nepal	Hetauda
7449	Nepal	Ithari
7450	Nepal	Jaleswar
7451	Nepal	Janakpur
7452	Nepal	Kathmandu
7453	Nepal	Kirtipur
7454	Nepal	Mahendranagar
7455	Nepal	Malangwa
7456	Nepal	Nepalgunj
7457	Nepal	Pokhara
7458	Netherlands	Aalsmeer
7459	Netherlands	Aalten
7460	Netherlands	Alblasserdam
7461	Netherlands	Alkmaar
7462	Netherlands	Almelo
7463	Netherlands	Amersfoort
7464	Netherlands	Amstelveen
7465	Netherlands	Amsterdam
7466	Netherlands	Anloo
7467	Netherlands	Apeldoorn
7468	Netherlands	Arnhem
7469	Netherlands	Assen
7470	Netherlands	Asten
7471	Netherlands	Baarn
7472	Netherlands	Barendrecht
7473	Netherlands	Barneveld
7474	Netherlands	Beek
7475	Netherlands	Benthuizen
7476	Netherlands	Bergeijk
7477	Netherlands	Bergschenhoek
7478	Netherlands	Best
7479	Netherlands	Beuningen
7480	Netherlands	Beverwijk
7481	Netherlands	Bladel
7482	Netherlands	Bloemendaal
7483	Netherlands	Bodegraven
7484	Netherlands	Borger
7485	Netherlands	Born
7486	Netherlands	Borne
7487	Netherlands	Borssele
7488	Netherlands	Boskoop
7489	Netherlands	Boxtel
7490	Netherlands	Breda
7491	Netherlands	Brummen
7492	Netherlands	Brunssum
7493	Netherlands	Bunschoten
7494	Netherlands	Bussum
7495	Netherlands	Castricum
7496	Netherlands	Cranendonck
7497	Netherlands	Cuijk
7498	Netherlands	Culemborg
7499	Netherlands	Dalfsen
7500	Netherlands	Delfshaven
7501	Netherlands	Delft
7502	Netherlands	Delfzijl
7503	Netherlands	Deventer
7504	Netherlands	Diemen
7505	Netherlands	Doetinchem
7506	Netherlands	Dongen
7507	Netherlands	Dordrecht
7508	Netherlands	Drachten
7509	Netherlands	Drimmelen
7510	Netherlands	Dronten
7511	Netherlands	Druten
7512	Netherlands	Duiven
7513	Netherlands	Ede
7514	Netherlands	Eersel
7515	Netherlands	Eibergen
7516	Netherlands	Eindhoven
7517	Netherlands	Elburg
7518	Netherlands	Elst
7519	Netherlands	Emmeloord
7520	Netherlands	Emmen
7521	Netherlands	Enkhuizen
7522	Netherlands	Enschede
7523	Netherlands	Epe
7524	Netherlands	Ermelo
7525	Netherlands	Geertruidenberg
7526	Netherlands	Geldermalsen
7527	Netherlands	Geldrop
7528	Netherlands	Gendringen
7529	Netherlands	Gennep
7530	Netherlands	Goes
7531	Netherlands	Goirle
7532	Netherlands	Gorinchem
7533	Netherlands	Gouda
7534	Netherlands	Groesbeek
7535	Netherlands	Groningen
7536	Netherlands	Haaksbergen
7537	Netherlands	Haarlem
7538	Netherlands	Hardenberg
7539	Netherlands	Harderwijk
7540	Netherlands	Haren
7541	Netherlands	Harenkarspel
7542	Netherlands	Harlingen
7543	Netherlands	Heemskerk
7544	Netherlands	Heemstede
7545	Netherlands	Heerde
7546	Netherlands	Heerenveen
7547	Netherlands	Heerhugowaard
7548	Netherlands	Heerlen
7549	Netherlands	Heesch
7550	Netherlands	Heiloo
7551	Netherlands	Hellevoetsluis
7552	Netherlands	Helmond
7553	Netherlands	Hengelo
7554	Netherlands	Heusden
7555	Netherlands	Hillegom
7556	Netherlands	Hilvarenbeek
7557	Netherlands	Hilversum
7558	Netherlands	Hoensbroek
7559	Netherlands	Hoofddorp
7560	Netherlands	Hoogeveen
7561	Netherlands	Hoogezand
7562	Netherlands	Hoorn
7563	Netherlands	Horst
7564	Netherlands	Houten
7565	Netherlands	Huizen
7566	Netherlands	IJsselstein
7567	Netherlands	Kampen
7568	Netherlands	Kerkrade
7569	Netherlands	Korrewegwijk
7570	Netherlands	Leek
7571	Netherlands	Leerdam
7572	Netherlands	Leeuwarden
7573	Netherlands	Leiden
7574	Netherlands	Leiderdorp
7575	Netherlands	Lelystad
7576	Netherlands	Leusden
7577	Netherlands	Lichtenvoorde
7578	Netherlands	Lindenholt
7579	Netherlands	Lisse
7580	Netherlands	Losser
7581	Netherlands	Maarssen
7582	Netherlands	Maassluis
7583	Netherlands	Maastricht
7584	Netherlands	Medemblik
7585	Netherlands	Meerssen
7586	Netherlands	Meppel
7587	Netherlands	Middelburg
7588	Netherlands	Middelharnis
7589	Netherlands	Mijdrecht
7590	Netherlands	Naaldwijk
7591	Netherlands	Naarden
7592	Netherlands	Nederweert
7593	Netherlands	Nieuwegein
7594	Netherlands	Nijkerk
7595	Netherlands	Nijmegen
7596	Netherlands	Noordwijkerhout
7597	Netherlands	Nuenen
7598	Netherlands	Nunspeet
7599	Netherlands	Nuth
7600	Netherlands	Oegstgeest
7601	Netherlands	Oisterwijk
7602	Netherlands	Oldebroek
7603	Netherlands	Oldenzaal
7604	Netherlands	Oosterhout
7605	Netherlands	Oss
7606	Netherlands	Papendrecht
7607	Netherlands	Pijnacker
7608	Netherlands	Purmerend
7609	Netherlands	Putten
7610	Netherlands	Raalte
7611	Netherlands	Rhenen
7612	Netherlands	Rhoon
7613	Netherlands	Ridderkerk
7614	Netherlands	Rijswijk
7615	Netherlands	Roermond
7616	Netherlands	Roosendaal
7617	Netherlands	Rotterdam
7618	Netherlands	Rucphen
7619	Netherlands	Schagen
7620	Netherlands	Scheveningen
7621	Netherlands	Schiedam
7622	Netherlands	Schijndel
7623	Netherlands	Sittard
7624	Netherlands	Sliedrecht
7625	Netherlands	Sneek
7626	Netherlands	Soest
7627	Netherlands	Someren
7628	Netherlands	Spijkenisse
7629	Netherlands	Stadskanaal
7630	Netherlands	Staphorst
7631	Netherlands	Steenbergen
7632	Netherlands	Steenwijk
7633	Netherlands	Tegelen
7634	Netherlands	Terneuzen
7635	Netherlands	Tiel
7636	Netherlands	Tilburg
7637	Netherlands	Tongelre
7638	Netherlands	Tubbergen
7639	Netherlands	Uden
7640	Netherlands	Uithoorn
7641	Netherlands	Urk
7642	Netherlands	Utrecht
7643	Netherlands	Valkenswaard
7644	Netherlands	Veendam
7645	Netherlands	Veenendaal
7646	Netherlands	Veere
7647	Netherlands	Veghel
7648	Netherlands	Veldhoven
7649	Netherlands	Velp
7650	Netherlands	Venlo
7651	Netherlands	Venray
7652	Netherlands	Vianen
7653	Netherlands	Vlaardingen
7654	Netherlands	Vlagtwedde
7655	Netherlands	Vlissingen
7656	Netherlands	Volendam
7657	Netherlands	Voorburg
7658	Netherlands	Voorhout
7659	Netherlands	Voorschoten
7660	Netherlands	Voorst
7661	Netherlands	Vught
7662	Netherlands	Waalre
7663	Netherlands	Waalwijk
7664	Netherlands	Waddinxveen
7665	Netherlands	Wageningen
7666	Netherlands	Wassenaar
7667	Netherlands	Weert
7668	Netherlands	Weesp
7669	Netherlands	Werkendam
7670	Netherlands	Westervoort
7671	Netherlands	Wierden
7672	Netherlands	Wijchen
7673	Netherlands	Winschoten
7674	Netherlands	Winterswijk
7675	Netherlands	Wisch
7676	Netherlands	Woensdrecht
7677	Netherlands	Woerden
7678	Netherlands	Wolvega
7679	Netherlands	Ypenburg
7680	Netherlands	Zaandam
7681	Netherlands	Zaanstad
7682	Netherlands	Zaltbommel
7683	Netherlands	Zandvoort
7684	Netherlands	Zeewolde
7685	Netherlands	Zeist
7686	Netherlands	Zevenaar
7687	Netherlands	Zoetermeer
7688	Netherlands	Zundert
7689	Netherlands	Zutphen
7690	Netherlands	Zwijndrecht
7691	Netherlands	Zwolle
7692	Nicaragua	Bluefields
7693	Nicaragua	Boaco
7694	Nicaragua	Camoapa
7695	Nicaragua	Chichigalpa
7696	Nicaragua	Chinandega
7697	Nicaragua	Corinto
7698	Nicaragua	Diriamba
7699	Nicaragua	Granada
7700	Nicaragua	Jalapa
7701	Nicaragua	Jinotega
7702	Nicaragua	Jinotepe
7703	Nicaragua	Juigalpa
7704	Nicaragua	Managua
7705	Nicaragua	Masatepe
7706	Nicaragua	Masaya
7707	Nicaragua	Matagalpa
7708	Nicaragua	Nagarote
7709	Nicaragua	Nandaime
7710	Nicaragua	Ocotal
7711	Nicaragua	Rama
7712	Nicaragua	Rivas
7713	Nicaragua	Siuna
7714	Nicaragua	Somotillo
7715	Nicaragua	Somoto
7716	Nicaragua	Tipitapa
7717	Niger	Agadez
7718	Niger	Alaghsas
7719	Niger	Ayorou
7720	Niger	Dakoro
7721	Niger	Diffa
7722	Niger	Dogondoutchi
7723	Niger	Dosso
7724	Niger	Gaya
7725	Niger	Madaoua
7726	Niger	Magaria
7727	Niger	Maradi
7728	Niger	Matamey
7729	Niger	Mayahi
7730	Niger	Mirriah
7731	Niger	Nguigmi
7732	Niger	Niamey
7733	Niger	Tahoua
7734	Niger	Tanout
7735	Niger	Tessaoua
7736	Niger	Tibiri
7737	Niger	Zinder
7738	Nigeria	Aba
7739	Nigeria	Abakaliki
7740	Nigeria	Abeokuta
7741	Nigeria	Abuja
7742	Nigeria	Afikpo
7743	Nigeria	Agbor
7744	Nigeria	Agulu
7745	Nigeria	Ajaokuta
7746	Nigeria	Aku
7747	Nigeria	Akure
7748	Nigeria	Akwanga
7749	Nigeria	Amaigbo
7750	Nigeria	Anchau
7751	Nigeria	Apomu
7752	Nigeria	Argungu
7753	Nigeria	Asaba
7754	Nigeria	Auchi
7755	Nigeria	Awgu
7756	Nigeria	Awka
7757	Nigeria	Azare
7758	Nigeria	Babana
7759	Nigeria	Badagry
7760	Nigeria	Bama
7761	Nigeria	Baro
7762	Nigeria	Bauchi
7763	Nigeria	Beli
7764	Nigeria	Bende
7765	Nigeria	Bida
7766	Nigeria	Billiri
7767	Nigeria	Biu
7768	Nigeria	Bonny
7769	Nigeria	Buguma
7770	Nigeria	Bukuru
7771	Nigeria	Burutu
7772	Nigeria	Calabar
7773	Nigeria	Damaturu
7774	Nigeria	Damboa
7775	Nigeria	Darazo
7776	Nigeria	Daura
7777	Nigeria	Deba
7778	Nigeria	Dikwa
7779	Nigeria	Doma
7780	Nigeria	Dukku
7781	Nigeria	Dutse
7782	Nigeria	Effium
7783	Nigeria	Egbe
7784	Nigeria	Ejigbo
7785	Nigeria	Eket
7786	Nigeria	Ekpoma
7787	Nigeria	Elele
7788	Nigeria	Enugu
7789	Nigeria	Epe
7790	Nigeria	Fiditi
7791	Nigeria	Funtua
7792	Nigeria	Gamboru
7793	Nigeria	Ganye
7794	Nigeria	Garko
7795	Nigeria	Gashua
7796	Nigeria	Gaya
7797	Nigeria	Gbongan
7798	Nigeria	Geidam
7799	Nigeria	Gembu
7800	Nigeria	Gombe
7801	Nigeria	Gombi
7802	Nigeria	Gumel
7803	Nigeria	Gummi
7804	Nigeria	Gusau
7805	Nigeria	Gwadabawa
7806	Nigeria	Gwaram
7807	Nigeria	Gwarzo
7808	Nigeria	Gwoza
7809	Nigeria	Hadejia
7810	Nigeria	Ibadan
7811	Nigeria	Ibeto
7812	Nigeria	Ibi
7813	Nigeria	Idah
7814	Nigeria	Idanre
7815	Nigeria	Ifo
7816	Nigeria	Igbeti
7817	Nigeria	Igboho
7818	Nigeria	Igbor
7819	Nigeria	Ihiala
7820	Nigeria	Ikeja
7821	Nigeria	Ikire
7822	Nigeria	Ikirun
7823	Nigeria	Ikom
7824	Nigeria	Ilaro
7825	Nigeria	Ilesa
7826	Nigeria	Illela
7827	Nigeria	Ilobu
7828	Nigeria	Ilorin
7829	Nigeria	Inisa
7830	Nigeria	Iperu
7831	Nigeria	Ipoti
7832	Nigeria	Isieke
7833	Nigeria	Itu
7834	Nigeria	Iwo
7835	Nigeria	Jalingo
7836	Nigeria	Jebba
7837	Nigeria	Jega
7838	Nigeria	Jimeta
7839	Nigeria	Jos
7840	Nigeria	Kabba
7841	Nigeria	Kachia
7842	Nigeria	Kaduna
7843	Nigeria	Kafanchan
7844	Nigeria	Kagoro
7845	Nigeria	Kaiama
7846	Nigeria	Kamba
7847	Nigeria	Kano
7848	Nigeria	Kari
7849	Nigeria	Katsina
7850	Nigeria	Keffi
7851	Nigeria	Kisi
7852	Nigeria	Kiyawa
7853	Nigeria	Kontagora
7854	Nigeria	Kuje
7855	Nigeria	Kukawa
7856	Nigeria	Kumagunnam
7857	Nigeria	Kumo
7858	Nigeria	Kwale
7859	Nigeria	Lafia
7860	Nigeria	Lafiagi
7861	Nigeria	Lagos
7862	Nigeria	Lalupon
7863	Nigeria	Lapai
7864	Nigeria	Lere
7865	Nigeria	Lokoja
7866	Nigeria	Magumeri
7867	Nigeria	Maiduguri
7868	Nigeria	Makoko
7869	Nigeria	Makurdi
7870	Nigeria	Malumfashi
7871	Nigeria	Marte
7872	Nigeria	Minna
7873	Nigeria	Modakeke
7874	Nigeria	Mokwa
7875	Nigeria	Monguno
7876	Nigeria	Moriki
7877	Nigeria	Mubi
7878	Nigeria	Nafada
7879	Nigeria	Nasarawa
7880	Nigeria	Nguru
7881	Nigeria	Nkpor
7882	Nigeria	Nkwerre
7883	Nigeria	Nnewi
7884	Nigeria	Nsukka
7885	Nigeria	Numan
7886	Nigeria	Obonoma
7887	Nigeria	Obudu
7888	Nigeria	Ode
7889	Nigeria	Offa
7890	Nigeria	Ogaminana
7891	Nigeria	Ogoja
7892	Nigeria	Oguta
7893	Nigeria	Okene
7894	Nigeria	Okigwe
7895	Nigeria	Okrika
7896	Nigeria	Okuta
7897	Nigeria	Olupona
7898	Nigeria	Ondo
7899	Nigeria	Onitsha
7900	Nigeria	Osogbo
7901	Nigeria	Otukpa
7902	Nigeria	Owerri
7903	Nigeria	Owo
7904	Nigeria	Oyan
7905	Nigeria	Oyo
7906	Nigeria	Ozubulu
7907	Nigeria	Pankshin
7908	Nigeria	Patigi
7909	Nigeria	Pindiga
7910	Nigeria	Potiskum
7911	Nigeria	Rano
7912	Nigeria	Rijau
7913	Nigeria	Saki
7914	Nigeria	Sapele
7915	Nigeria	Shagamu
7916	Nigeria	Soba
7917	Nigeria	Sokoto
7918	Nigeria	Suleja
7919	Nigeria	Takum
7920	Nigeria	Tambuwal
7921	Nigeria	Tegina
7922	Nigeria	Ubiaja
7923	Nigeria	Uga
7924	Nigeria	Ugep
7925	Nigeria	Ughelli
7926	Nigeria	Umuahia
7927	Nigeria	Uromi
7928	Nigeria	Uyo
7929	Nigeria	Wamba
7930	Nigeria	Warri
7931	Nigeria	Wudil
7932	Nigeria	Wukari
7933	Nigeria	Yenagoa
7934	Nigeria	Yola
7935	Nigeria	Zaria
7936	Nigeria	Zungeru
7937	Nigeria	Zuru
7938	Niue	Alofi
7939	Norway	Arendal
7940	Norway	Bergen
7941	Norway	Drammen
7942	Norway	Fredrikstad
7943	Norway	Halden
7944	Norway	Hamar
7945	Norway	Harstad
7946	Norway	Haugesund
7947	Norway	Horten
7948	Norway	Kongsberg
7949	Norway	Kristiansand
7950	Norway	Kristiansund
7951	Norway	Larvik
7952	Norway	Lillehammer
7953	Norway	Molde
7954	Norway	Moss
7955	Norway	Oslo
7956	Norway	Porsgrunn
7957	Norway	Sandefjord
7958	Norway	Sandnes
7959	Norway	Sarpsborg
7960	Norway	Skien
7961	Norway	Stavanger
7962	Norway	Steinkjer
7963	Norway	Trondheim
7964	Norway	Ytrebygda
7965	Oman	Bawshar
7966	Oman	Bidbid
7967	Oman	Khasab
7968	Oman	Muscat
7969	Oman	Rustaq
7970	Oman	Seeb
7971	Oman	Sohar
7972	Oman	Sur
7973	Oman	Yanqul
7974	Pakistan	Akora
7975	Pakistan	Amangarh
7976	Pakistan	Baddomalhi
7977	Pakistan	Bannu
7978	Pakistan	Bela
7979	Pakistan	Bhakkar
7980	Pakistan	Bhera
7981	Pakistan	Bhimbar
7982	Pakistan	Chaman
7983	Pakistan	Charsadda
7984	Pakistan	Chawinda
7985	Pakistan	Chiniot
7986	Pakistan	Chor
7987	Pakistan	Dadu
7988	Pakistan	Daska
7989	Pakistan	Daur
7990	Pakistan	Dhanot
7991	Pakistan	Digri
7992	Pakistan	Dijkot
7993	Pakistan	Dinga
7994	Pakistan	Faruka
7995	Pakistan	Fazalpur
7996	Pakistan	Gambat
7997	Pakistan	Ghauspur
7998	Pakistan	Ghotki
7999	Pakistan	Gojra
8000	Pakistan	Gwadar
8001	Pakistan	Hangu
8002	Pakistan	Harnoli
8003	Pakistan	Haveli
8004	Pakistan	Hazro
8005	Pakistan	Hingorja
8006	Pakistan	Hujra
8007	Pakistan	Hyderabad
8008	Pakistan	Islamabad
8009	Pakistan	Jand
8010	Pakistan	Jhelum
8011	Pakistan	Jhol
8012	Pakistan	Jhumra
8013	Pakistan	Johi
8014	Pakistan	Kambar
8015	Pakistan	Kamoke
8016	Pakistan	Kandhkot
8017	Pakistan	Kanganpur
8018	Pakistan	Karachi
8019	Pakistan	Karor
8020	Pakistan	Kashmor
8021	Pakistan	Khairpur
8022	Pakistan	Khewra
8023	Pakistan	Kotli
8024	Pakistan	Kotri
8025	Pakistan	Kunri
8026	Pakistan	Lahore
8027	Pakistan	Layyah
8028	Pakistan	Loralai
8029	Pakistan	Mach
8030	Pakistan	Mailsi
8031	Pakistan	Mangla
8032	Pakistan	Mardan
8033	Pakistan	Mastung
8034	Pakistan	Mehar
8035	Pakistan	Mingora
8036	Pakistan	Mithi
8037	Pakistan	Moro
8038	Pakistan	Murree
8039	Pakistan	Muzaffargarh
8040	Pakistan	Naudero
8041	Pakistan	Naukot
8042	Pakistan	Nushki
8043	Pakistan	Pabbi
8044	Pakistan	Pasni
8045	Pakistan	Pattoki
8046	Pakistan	Peshawar
8047	Pakistan	Pishin
8048	Pakistan	Quetta
8049	Pakistan	Ratodero
8050	Pakistan	Rawalpindi
8051	Pakistan	Rohri
8052	Pakistan	Sahiwal
8053	Pakistan	Sakrand
8054	Pakistan	Sargodha
8055	Pakistan	Shabqadar
8056	Pakistan	Shahkot
8057	Pakistan	Shakargarr
8058	Pakistan	Sharqpur
8059	Pakistan	Sheikhupura
8060	Pakistan	Shorko
8061	Pakistan	Sialkot
8062	Pakistan	Sibi
8063	Pakistan	Sinjhoro
8064	Pakistan	Sodhra
8065	Pakistan	Sukkur
8066	Pakistan	Surkhpur
8067	Pakistan	Talagang
8068	Pakistan	Talamba
8069	Pakistan	Tangi
8070	Pakistan	Taunsa
8071	Pakistan	Thatta
8072	Pakistan	Thul
8073	Pakistan	Topi
8074	Pakistan	Turbat
8075	Pakistan	Ubauro
8076	Pakistan	Umarkot
8077	Pakistan	Uthal
8078	Pakistan	Warburton
8079	Pakistan	Yazman
8080	Pakistan	Zaida
8081	Pakistan	Zhob
8082	Palau	Melekeok
8083	Panama	Aguadulce
8084	Panama	Changuinola
8085	Panama	Chepo
8086	Panama	Chilibre
8087	Panama	David
8088	Panama	Pacora
8089	Panama	Pedregal
8090	Panama	Tocumen
8091	Panama	Veracruz
8092	Paraguay	Limpio
8093	Paraguay	Nemby
8094	Paraguay	Pilar
8095	Paraguay	Villarrica
8096	Peru	Abancay
8097	Peru	Andahuaylas
8098	Peru	Arequipa
8099	Peru	Ayacucho
8100	Peru	Ayaviri
8101	Peru	Barranca
8102	Peru	Bellavista
8103	Peru	Cajamarca
8104	Peru	Callao
8105	Peru	Catacaos
8106	Peru	Chachapoyas
8107	Peru	Chancay
8108	Peru	Chaupimarca
8109	Peru	Chiclayo
8110	Peru	Chimbote
8111	Peru	Chocope
8112	Peru	Chongoyape
8113	Peru	Chosica
8114	Peru	Chulucanas
8115	Peru	Coishco
8116	Peru	Cusco
8117	Peru	Guadalupe
8118	Peru	Huacho
8119	Peru	Hualmay
8120	Peru	Huamachuco
8121	Peru	Huancavelica
8122	Peru	Huancayo
8123	Peru	Huanta
8124	Peru	Huaral
8125	Peru	Huaraz
8126	Peru	Huarmey
8127	Peru	Huaura
8128	Peru	Ica
8129	Peru	Ilave
8130	Peru	Ilo
8131	Peru	Imperial
8132	Peru	Iquitos
8133	Peru	Jauja
8134	Peru	Juliaca
8135	Peru	Lambayeque
8136	Peru	Laredo
8137	Peru	Lima
8138	Peru	Mala
8139	Peru	Marcavelica
8140	Peru	Moche
8141	Peru	Mollendo
8142	Peru	Moquegua
8143	Peru	Moyobamba
8144	Peru	Nazca
8145	Peru	Pacasmayo
8146	Peru	Paita
8147	Peru	Paramonga
8148	Peru	Picsi
8149	Peru	Pimentel
8150	Peru	Pisco
8151	Peru	Piura
8152	Peru	Pucallpa
8153	Peru	Puno
8154	Peru	Querecotillo
8155	Peru	Rioja
8156	Peru	Satipo
8157	Peru	Sechura
8158	Peru	Sicuani
8159	Peru	Sullana
8160	Peru	Tacna
8161	Peru	Talara
8162	Peru	Tambopata
8163	Peru	Tarma
8164	Peru	Tocache
8165	Peru	Trujillo
8166	Peru	Tumbes
8167	Peru	Uchiza
8168	Peru	Yanacancha
8169	Peru	Yunguyo
8170	Peru	Yurimaguas
8171	Peru	Zarumilla
8172	Philippines	Abucay
8173	Philippines	Abuyog
8174	Philippines	Agoo
8175	Philippines	Alabel
8176	Philippines	Alaminos
8177	Philippines	Aliaga
8178	Philippines	Alicia
8179	Philippines	Amadeo
8180	Philippines	Angat
8181	Philippines	Angono
8182	Philippines	Antipolo
8183	Philippines	Apalit
8184	Philippines	Aparri
8185	Philippines	Apas
8186	Philippines	Arayat
8187	Philippines	Aringay
8188	Philippines	Asia
8189	Philippines	Atimonan
8190	Philippines	Aurora
8191	Philippines	Baao
8192	Philippines	Bacoor
8193	Philippines	Baguio
8194	Philippines	Bais
8195	Philippines	Balagtas
8196	Philippines	Balamban
8197	Philippines	Balanga
8198	Philippines	Balayan
8199	Philippines	Baliuag
8200	Philippines	Bambang
8201	Philippines	Banaybanay
8202	Philippines	Bansalan
8203	Philippines	Bantayan
8204	Philippines	Baras
8205	Philippines	Batangas
8206	Philippines	Bato
8207	Philippines	Bauan
8208	Philippines	Bauang
8209	Philippines	Bay
8210	Philippines	Bayambang
8211	Philippines	Bayawan
8212	Philippines	Baybay
8213	Philippines	Bayombong
8214	Philippines	Bayugan
8215	Philippines	Binalbagan
8216	Philippines	Binangonan
8217	Philippines	Binmaley
8218	Philippines	Binonga
8219	Philippines	Bislig
8220	Philippines	Bocaue
8221	Philippines	Bogo
8222	Philippines	Bongabon
8223	Philippines	Bongao
8224	Philippines	Borongan
8225	Philippines	Boroon
8226	Philippines	Botolan
8227	Philippines	Budta
8228	Philippines	Buenavista
8229	Philippines	Bugo
8230	Philippines	Buhi
8231	Philippines	Bulacan
8232	Philippines	Bulan
8233	Philippines	Bulaon
8234	Philippines	Buluan
8235	Philippines	Bunawan
8236	Philippines	Burgos
8237	Philippines	Bustos
8238	Philippines	Butuan
8239	Philippines	Cabadbaran
8240	Philippines	Cabagan
8241	Philippines	Cabayangan
8242	Philippines	Cabiao
8243	Philippines	Cadiz
8244	Philippines	Cainta
8245	Philippines	Calabanga
8246	Philippines	Calaca
8247	Philippines	Calamba
8248	Philippines	Calapan
8249	Philippines	Calasiao
8250	Philippines	Calatagan
8251	Philippines	Calauag
8252	Philippines	Calauan
8253	Philippines	Calumpang
8254	Philippines	Calumpit
8255	Philippines	Camiling
8256	Philippines	Candaba
8257	Philippines	Candelaria
8258	Philippines	Canlaon
8259	Philippines	Capas
8260	Philippines	Carcar
8261	Philippines	Cardona
8262	Philippines	Carigara
8263	Philippines	Carmona
8264	Philippines	Castillejos
8265	Philippines	Catanauan
8266	Philippines	Catarman
8267	Philippines	Catbalogan
8268	Philippines	Cogan
8269	Philippines	Compostela
8270	Philippines	Concepcion
8271	Philippines	Consolacion
8272	Philippines	Cordova
8273	Philippines	Cotabato
8274	Philippines	Cuenca
8275	Philippines	Daet
8276	Philippines	Danao
8277	Philippines	Dapitan
8278	Philippines	Davao
8279	Philippines	Diadi
8280	Philippines	Digos
8281	Philippines	Dinalupihan
8282	Philippines	Dipolog
8283	Philippines	Dologon
8284	Philippines	Domalanoan
8285	Philippines	Dumaguete
8286	Philippines	Escalante
8287	Philippines	Gapan
8288	Philippines	Gerona
8289	Philippines	Glan
8290	Philippines	Goa
8291	Philippines	Guiguinto
8292	Philippines	Guimba
8293	Philippines	Gumaca
8294	Philippines	Guyong
8295	Philippines	Hagonoy
8296	Philippines	Hermosa
8297	Philippines	Himamaylan
8298	Philippines	Hinigaran
8299	Philippines	Iba
8300	Philippines	Ilagan
8301	Philippines	Iloilo
8302	Philippines	Imus
8303	Philippines	Indang
8304	Philippines	Ipil
8305	Philippines	Irosin
8306	Philippines	Isabela
8307	Philippines	Isulan
8308	Philippines	Itogon
8309	Philippines	Jaen
8310	Philippines	Jagna
8311	Philippines	Jalajala
8312	Philippines	Jasaan
8313	Philippines	Jolo
8314	Philippines	Kabacan
8315	Philippines	Kabankalan
8316	Philippines	Kawit
8317	Philippines	Kidapawan
8318	Philippines	Koronadal
8319	Philippines	Labo
8320	Philippines	Laguilayan
8321	Philippines	Lala
8322	Philippines	Laoag
8323	Philippines	Laoang
8324	Philippines	Laur
8325	Philippines	Legaspi
8326	Philippines	Libertad
8327	Philippines	Libon
8328	Philippines	Lilio
8329	Philippines	Liloan
8330	Philippines	Limay
8331	Philippines	Lingayen
8332	Philippines	Loboc
8333	Philippines	Lopez
8334	Philippines	Lubao
8335	Philippines	Lucban
8336	Philippines	Lucena
8337	Philippines	Lumbang
8338	Philippines	Lupon
8339	Philippines	Maao
8340	Philippines	Maasin
8341	Philippines	Magalang
8342	Philippines	Maganoy
8343	Philippines	Magarao
8344	Philippines	Magsaysay
8345	Philippines	Mahayag
8346	Philippines	Malanday
8347	Philippines	Malapatan
8348	Philippines	Malaybalay
8349	Philippines	Malilipot
8350	Philippines	Malingao
8351	Philippines	Malita
8352	Philippines	Malolos
8353	Philippines	Maluso
8354	Philippines	Malvar
8355	Philippines	Mamatid
8356	Philippines	Mamburao
8357	Philippines	Manaoag
8358	Philippines	Manapla
8359	Philippines	Manay
8360	Philippines	Mangaldan
8361	Philippines	Manila
8362	Philippines	Mankayan
8363	Philippines	Mansalay
8364	Philippines	Mansilingan
8365	Philippines	Mantampay
8366	Philippines	Maragondon
8367	Philippines	Maramag
8368	Philippines	Mariano
8369	Philippines	Marilao
8370	Philippines	Mariveles
8371	Philippines	Masantol
8372	Philippines	Masbate
8373	Philippines	Masinloc
8374	Philippines	Mati
8375	Philippines	Mauban
8376	Philippines	Mercedes
8377	Philippines	Mexico
8378	Philippines	Meycauayan
8379	Philippines	Midsayap
8380	Philippines	Minglanilla
8381	Philippines	Molave
8382	Philippines	Monkayo
8383	Philippines	Morong
8384	Philippines	Murcia
8385	Philippines	Muricay
8386	Philippines	Nabua
8387	Philippines	Nabunturan
8388	Philippines	Naga
8389	Philippines	Nagcarlan
8390	Philippines	Naic
8391	Philippines	Narra
8392	Philippines	Nasugbu
8393	Philippines	Norzagaray
8394	Philippines	Noveleta
8395	Philippines	Obando
8396	Philippines	Olongapo
8397	Philippines	Orani
8398	Philippines	Orion
8399	Philippines	Ormoc
8400	Philippines	Oroquieta
8401	Philippines	Pacol
8402	Philippines	Paete
8403	Philippines	Pagadian
8404	Philippines	Pagbilao
8405	Philippines	Palo
8406	Philippines	Panabo
8407	Philippines	Panalanoy
8408	Philippines	Pandacaqui
8409	Philippines	Pandan
8410	Philippines	Pandi
8411	Philippines	Pangil
8412	Philippines	Paniqui
8413	Philippines	Pantubig
8414	Philippines	Paombong
8415	Philippines	Papaya
8416	Philippines	Paraiso
8417	Philippines	Parang
8418	Philippines	Passi
8419	Philippines	Patuto
8420	Philippines	Pila
8421	Philippines	Pilar
8422	Philippines	Pililla
8423	Philippines	Pinamalayan
8424	Philippines	Pinamungahan
8425	Philippines	Pio
8426	Philippines	Plaridel
8427	Philippines	Polangui
8428	Philippines	Polomolok
8429	Philippines	Porac
8430	Philippines	Pulilan
8431	Philippines	Pulupandan
8432	Philippines	Quezon
8433	Philippines	Quiapo
8434	Philippines	Ramon
8435	Philippines	Ramos
8436	Philippines	Recodo
8437	Philippines	Rizal
8438	Philippines	Rodriguez
8439	Philippines	Romblon
8440	Philippines	Roxas
8441	Philippines	Sablayan
8442	Philippines	Sagay
8443	Philippines	Samal
8444	Philippines	Sampaloc
8445	Philippines	Santiago
8446	Philippines	Santol
8447	Philippines	Saravia
8448	Philippines	Sariaya
8449	Philippines	Sebu
8450	Philippines	Sexmoan
8451	Philippines	Sibulan
8452	Philippines	Silang
8453	Philippines	Sipalay
8454	Philippines	Sitangkai
8455	Philippines	Solana
8456	Philippines	Solano
8457	Philippines	Sorsogon
8458	Philippines	Suay
8459	Philippines	Subic
8460	Philippines	Surallah
8461	Philippines	Surigao
8462	Philippines	Taal
8463	Philippines	Tabaco
8464	Philippines	Tabuk
8465	Philippines	Tacurong
8466	Philippines	Tagas
8467	Philippines	Tagoloan
8468	Philippines	Tagudin
8469	Philippines	Taguig
8470	Philippines	Tagum
8471	Philippines	Talacogon
8472	Philippines	Talavera
8473	Philippines	Talisay
8474	Philippines	Taloc
8475	Philippines	Tanauan
8476	Philippines	Tanay
8477	Philippines	Tandag
8478	Philippines	Tangub
8479	Philippines	Tanjay
8480	Philippines	Tanza
8481	Philippines	Tayabas
8482	Philippines	Taytay
8483	Philippines	Telabastagan
8484	Philippines	Teresa
8485	Philippines	Ternate
8486	Philippines	Tiwi
8487	Philippines	Toledo
8488	Philippines	Trento
8489	Philippines	Tupi
8490	Philippines	Ualog
8491	Philippines	Urdaneta
8492	Philippines	Valencia
8493	Philippines	Veruela
8494	Philippines	Victoria
8495	Philippines	Victorias
8496	Philippines	Vigan
8497	Philippines	Virac
8498	Philippines	Wao
8499	Philippines	Zamboanga
8500	Pitcairn	Adamstown
8501	Poland	Bartoszyce
8502	Poland	Rzeszow
8503	Poland	Bemowo
8504	Poland	Lodz
8505	Poland	Torun
8506	Poland	Bielany
8507	Poland	Bielawa
8508	Poland	Bochnia
8509	Poland	Bogatynia
8510	Poland	Braniewo
8511	Poland	Brodnica
8512	Poland	Brzeg
8513	Poland	Brzesko
8514	Poland	Bydgoszcz
8515	Poland	Bytom
8516	Poland	Chojnice
8517	Poland	Choszczno
8518	Poland	Cieszyn
8519	Poland	Fordon
8520	Poland	Garwolin
8521	Poland	Gdynia
8522	Poland	Gliwice
8523	Poland	Gniezno
8524	Poland	Gorlice
8525	Poland	Gostynin
8526	Poland	Grajewo
8527	Poland	Gryfice
8528	Poland	Gryfino
8529	Poland	Gubin
8530	Poland	Jarocin
8531	Poland	Jawor
8532	Poland	Wroclaw
8533	Poland	Jaworzno
8534	Poland	Gdansk
8535	Poland	Jelcz
8536	Poland	Kabaty
8537	Poland	Kalisz
8538	Poland	Kartuzy
8539	Poland	Katowice
8540	Poland	Kielce
8541	Poland	Kluczbork
8542	Poland	Konin
8543	Poland	Koszalin
8544	Poland	Kozienice
8545	Poland	Krapkowice
8546	Poland	Krakow
8547	Poland	Krasnystaw
8548	Poland	Krosno
8549	Poland	Krotoszyn
8550	Poland	Kutno
8551	Poland	Kwidzyn
8552	Poland	Legionowo
8553	Poland	Legnica
8554	Poland	Leszno
8555	Poland	Lubin
8556	Poland	Lublin
8557	Poland	Lubliniec
8558	Poland	Malbork
8559	Poland	Marki
8560	Poland	Mielec
8561	Poland	Nisko
8562	Poland	Nowogard
8563	Poland	Nysa
8564	Poland	Oborniki
8565	Poland	Ochota
8566	Poland	Olecko
8567	Poland	Olkusz
8568	Poland	Olsztyn
8569	Poland	Opoczno
8570	Poland	Opole
8571	Poland	Orzesze
8572	Poland	Otwock
8573	Poland	Pabianice
8574	Poland	Piaseczno
8575	Poland	Pionki
8576	Poland	Pisz
8577	Poland	Pleszew
8578	Poland	Police
8579	Poland	Polkowice
8580	Poland	Prudnik
8581	Poland	Przasnysz
8582	Poland	Przeworsk
8583	Poland	Pszczyna
8584	Poland	Pyskowice
8585	Poland	Radlin
8586	Poland	Radom
8587	Poland	Radomsko
8588	Poland	Rawicz
8589	Poland	Reda
8590	Poland	Ropczyce
8591	Poland	Rumia
8592	Poland	Rybnik
8593	Poland	Rypin
8594	Poland	Sandomierz
8595	Poland	Sanok
8596	Poland	Siedlce
8597	Poland	Siemiatycze
8598	Poland	Sieradz
8599	Poland	Sierpc
8600	Poland	Skawina
8601	Poland	Skierniewice
8602	Poland	Sochaczew
8603	Poland	Sopot
8604	Poland	Sosnowiec
8605	Poland	Starachowice
8606	Poland	Strzegom
8607	Poland	Szczecin
8608	Poland	Szczecinek
8609	Poland	Szczytno
8610	Poland	Tarnobrzeg
8611	Poland	Tczew
8612	Poland	Trzcianka
8613	Poland	Trzebinia
8614	Poland	Turek
8615	Poland	Tychy
8616	Poland	Ursus
8617	Poland	Ustka
8618	Poland	Wadowice
8619	Poland	Warsaw
8620	Poland	Wawer
8621	Poland	Poznan
8622	Poland	Wejherowo
8623	Poland	Wieliczka
8624	Poland	Wola
8625	Poland	Zabrze
8626	Poland	Zakopane
8627	Poland	Zawiercie
8628	Poland	Zgierz
8629	Poland	Zgorzelec
8630	Poland	Zielonka
8631	Portugal	Albufeira
8632	Portugal	Alcabideche
8633	Portugal	Almada
8634	Portugal	Amadora
8635	Portugal	Amora
8636	Portugal	Arrentela
8637	Portugal	Aveiro
8638	Portugal	Barcelos
8639	Portugal	Barreiro
8640	Portugal	Beja
8641	Portugal	Belas
8642	Portugal	Bougado
8643	Portugal	Braga
8644	Portugal	Camarate
8645	Portugal	Canidelo
8646	Portugal	Caparica
8647	Portugal	Carcavelos
8648	Portugal	Carnaxide
8649	Portugal	Cascais
8650	Portugal	Charneca
8651	Portugal	Coimbra
8652	Portugal	Corroios
8653	Portugal	Custoias
8654	Portugal	Entroncamento
8655	Portugal	Ermesinde
8656	Portugal	Esposende
8657	Portugal	Estoril
8658	Portugal	Fafe
8659	Portugal	Faro
8660	Portugal	Feira
8661	Portugal	Funchal
8662	Portugal	Gondomar
8663	Portugal	Guarda
8664	Portugal	Lagos
8665	Portugal	Laranjeiro
8666	Portugal	Leiria
8667	Portugal	Lisbon
8668	Portugal	Loures
8669	Portugal	Maia
8670	Portugal	Matosinhos
8671	Portugal	Moita
8672	Portugal	Monsanto
8673	Portugal	Montijo
8674	Portugal	Odivelas
8675	Portugal	Ovar
8676	Portugal	Palmela
8677	Portugal	Parede
8678	Portugal	Pedroso
8679	Portugal	Peniche
8680	Portugal	Piedade
8681	Portugal	Pombal
8682	Portugal	Pontinha
8683	Portugal	Portalegre
8684	Portugal	Porto
8685	Portugal	Quarteira
8686	Portugal	Queluz
8687	Portugal	Ramada
8688	Portugal	Sequeira
8689	Portugal	Sesimbra
8690	Portugal	Sintra
8691	Portugal	Tomar
8692	Portugal	Valongo
8693	Portugal	Vialonga
8694	Portugal	Viseu
8695	Qatar	Doha
8696	Romania	Adjud
8697	Romania	Aiud
8698	Romania	Alexandria
8699	Romania	Arad
8700	Romania	Blaj
8701	Romania	Brad
8702	Romania	Breaza
8703	Romania	Bucharest
8704	Romania	Buftea
8705	Romania	Calafat
8706	Romania	Caracal
8707	Romania	Carei
8708	Romania	Codlea
8709	Romania	Corabia
8710	Romania	Craiova
8711	Romania	Cugir
8712	Romania	Dej
8713	Romania	Deva
8714	Romania	Dorohoi
8715	Romania	Gheorgheni
8716	Romania	Gherla
8717	Romania	Giurgiu
8718	Romania	Hunedoara
8719	Romania	Lugoj
8720	Romania	Lupeni
8721	Romania	Mangalia
8722	Romania	Medgidia
8723	Romania	Mioveni
8724	Romania	Mizil
8725	Romania	Moreni
8726	Romania	Motru
8727	Romania	Oradea
8728	Romania	Pantelimon
8729	Romania	Petrila
8730	Romania	Roman
8731	Romania	Salonta
8732	Romania	Sibiu
8733	Romania	Slatina
8734	Romania	Slobozia
8735	Romania	Suceava
8736	Romania	Tecuci
8737	Romania	Tulcea
8738	Romania	Turda
8739	Romania	Urziceni
8740	Romania	Vaslui
8741	Romania	Voluntari
8742	Romania	Vulcan
8743	Romania	Zimnicea
8744	Russia	Abakan
8745	Russia	Abaza
8746	Russia	Abdulino
8747	Russia	Abinsk
8748	Russia	Achinsk
8749	Russia	Adler
8750	Russia	Admiralteisky
8751	Russia	Afipskiy
8752	Russia	Agryz
8753	Russia	Akademgorodok
8754	Russia	Akademicheskoe
8755	Russia	Akhtubinsk
8756	Russia	Akhtyrskiy
8757	Russia	Aksay
8758	Russia	Alagir
8759	Russia	Alapayevsk
8760	Russia	Aldan
8761	Russia	Aleksandrov
8762	Russia	Aleksandrovsk
8763	Russia	Aleksandrovskoye
8764	Russia	Alekseyevka
8765	Russia	Aleksin
8766	Russia	Aleysk
8767	Russia	Amursk
8768	Russia	Anapa
8769	Russia	Andreyevskoye
8770	Russia	Angarsk
8771	Russia	Anna
8772	Russia	Annino
8773	Russia	Apatity
8774	Russia	Aprelevka
8775	Russia	Apsheronsk
8776	Russia	Aramil
8777	Russia	Ardon
8778	Russia	Argun
8779	Russia	Armavir
8780	Russia	Arsk
8781	Russia	Arzamas
8782	Russia	Arzgir
8783	Russia	Asbest
8784	Russia	Asha
8785	Russia	Asino
8786	Russia	Astrakhan
8787	Russia	Atkarsk
8788	Russia	Avtovo
8789	Russia	Avtury
8790	Russia	Aykhal
8791	Russia	Azov
8792	Russia	Babushkin
8793	Russia	Bagayevskaya
8794	Russia	Bakal
8795	Russia	Baksan
8796	Russia	Balabanovo
8797	Russia	Balakovo
8798	Russia	Balashikha
8799	Russia	Balashov
8800	Russia	Balezino
8801	Russia	Baltiysk
8802	Russia	Barabinsk
8803	Russia	Barnaul
8804	Russia	Barysh
8805	Russia	Bataysk
8806	Russia	Bavly
8807	Russia	Baymak
8808	Russia	Belebey
8809	Russia	Belgorod
8810	Russia	Belidzhi
8811	Russia	Belogorsk
8812	Russia	Belorechensk
8813	Russia	Beloretsk
8814	Russia	Belovo
8815	Russia	Beloyarskiy
8816	Russia	Berdsk
8817	Russia	Berezniki
8818	Russia	Beryozovsky
8819	Russia	Beslan
8820	Russia	Bezenchuk
8821	Russia	Bezhetsk
8822	Russia	Bibirevo
8823	Russia	Bikin
8824	Russia	Birobidzhan
8825	Russia	Birsk
8826	Russia	Biysk
8827	Russia	Blagodarnyy
8828	Russia	Blagoveshchensk
8829	Russia	Bobrov
8830	Russia	Bodaybo
8831	Russia	Bogdanovich
8832	Russia	Bogoroditsk
8833	Russia	Bogorodsk
8834	Russia	Bogorodskoye
8835	Russia	Bogotol
8836	Russia	Boguchar
8837	Russia	Boksitogorsk
8838	Russia	Bologoye
8839	Russia	Bolotnoye
8840	Russia	Bor
8841	Russia	Borisoglebsk
8842	Russia	Borodino
8843	Russia	Borovichi
8844	Russia	Borovskiy
8845	Russia	Borzya
8846	Russia	Brateyevo
8847	Russia	Bratsk
8848	Russia	Bronnitsy
8849	Russia	Bryansk
8850	Russia	Bryukhovetskaya
8851	Russia	Buguruslan
8852	Russia	Buinsk
8853	Russia	Businovo
8854	Russia	Buturlinovka
8855	Russia	Buy
8856	Russia	Buynaksk
8857	Russia	Buzuluk
8858	Russia	Centralniy
8859	Russia	Chapayevsk
8860	Russia	Chaykovskiy
8861	Russia	Cheboksary
8862	Russia	Chegem
8863	Russia	Chekhov
8864	Russia	Chelyabinsk
8865	Russia	Cheremkhovo
8866	Russia	Cherepanovo
8867	Russia	Cherepovets
8868	Russia	Cherkessk
8869	Russia	Chernogolovka
8870	Russia	Chernogorsk
8871	Russia	Chernushka
8872	Russia	Chernyakhovsk
8873	Russia	Chernyanka
8874	Russia	Chishmy
8875	Russia	Chita
8876	Russia	Chudovo
8877	Russia	Chunskiy
8878	Russia	Chusovoy
8879	Russia	Dachnoye
8880	Russia	Dagomys
8881	Russia	Danilov
8882	Russia	Dankov
8883	Russia	Davlekanovo
8884	Russia	Davydkovo
8885	Russia	Dedovsk
8886	Russia	Degtyarsk
8887	Russia	Derbent
8888	Russia	Desnogorsk
8889	Russia	Dimitrovgrad
8890	Russia	Dinskaya
8891	Russia	Divnogorsk
8892	Russia	Divnoye
8893	Russia	Dmitrov
8894	Russia	Dobryanka
8895	Russia	Dolgoprudnyy
8896	Russia	Domodedovo
8897	Russia	Donetsk
8898	Russia	Donskoy
8899	Russia	Donskoye
8900	Russia	Dorogomilovo
8901	Russia	Dubna
8902	Russia	Dubovka
8903	Russia	Dudinka
8904	Russia	Dugulubgey
8905	Russia	Dyurtyuli
8906	Russia	Dzerzhinsk
8907	Russia	Dzerzhinskiy
8908	Russia	Ekazhevo
8909	Russia	Elektrogorsk
8910	Russia	Elektrougli
8911	Russia	Elista
8912	Russia	Enem
8913	Russia	Ezhva
8914	Russia	Fili
8915	Russia	Finlyandskiy
8916	Russia	Fokino
8917	Russia	Frolovo
8918	Russia	Fryazevo
8919	Russia	Fryazino
8920	Russia	Furmanov
8921	Russia	Gagarin
8922	Russia	Galich
8923	Russia	Gatchina
8924	Russia	Gay
8925	Russia	Gelendzhik
8926	Russia	Georgiyevsk
8927	Russia	Giaginskaya
8928	Russia	Glazov
8929	Russia	Golitsyno
8930	Russia	Gorelovo
8931	Russia	Gornyak
8932	Russia	Gorodets
8933	Russia	Gorodishche
8934	Russia	Goryachevodskiy
8935	Russia	Grazhdanka
8936	Russia	Gribanovskiy
8937	Russia	Groznyy
8938	Russia	Gryazi
8939	Russia	Gryazovets
8940	Russia	Gubakha
8941	Russia	Gubkin
8942	Russia	Gubkinskiy
8943	Russia	Gudermes
8944	Russia	Gukovo
8945	Russia	Gusev
8946	Russia	Gusinoozyorsk
8947	Russia	Igra
8948	Russia	Ilanskiy
8949	Russia	Inozemtsevo
8950	Russia	Inza
8951	Russia	Ipatovo
8952	Russia	Irbit
8953	Russia	Irkutsk
8954	Russia	Isakogorka
8955	Russia	Ishim
8956	Russia	Ishimbay
8957	Russia	Iskitim
8958	Russia	Istra
8959	Russia	Ivanovo
8960	Russia	Ivanovskoye
8961	Russia	Ivanteyevka
8962	Russia	Izberbash
8963	Russia	Izhevsk
8964	Russia	Izluchinsk
8965	Russia	Izmaylovo
8966	Russia	Kabanovo
8967	Russia	Kachkanar
8968	Russia	Kalach
8969	Russia	Kalachinsk
8970	Russia	Kaliningrad
8971	Russia	Kalininsk
8972	Russia	Kalininskiy
8973	Russia	Kaltan
8974	Russia	Kaluga
8975	Russia	Kamyshin
8976	Russia	Kamyshlov
8977	Russia	Kamyzyak
8978	Russia	Kanash
8979	Russia	Kandalaksha
8980	Russia	Kanevskaya
8981	Russia	Kansk
8982	Russia	Kantyshevo
8983	Russia	Kapotnya
8984	Russia	Karabanovo
8985	Russia	Karabash
8986	Russia	Karabulak
8987	Russia	Karachayevsk
8988	Russia	Karachev
8989	Russia	Karasuk
8990	Russia	Karpinsk
8991	Russia	Kartaly
8992	Russia	Kashin
8993	Russia	Kashira
8994	Russia	Kasimov
8995	Russia	Kasli
8996	Russia	Kaspiysk
8997	Russia	Kastanayevo
8998	Russia	Kataysk
8999	Russia	Kavalerovo
9000	Russia	Kayyerkan
9001	Russia	Kazan
9002	Russia	Kedrovka
9003	Russia	Kemerovo
9004	Russia	Khabarovsk
9005	Russia	Khadyzhensk
9006	Russia	Kharabali
9007	Russia	Khasavyurt
9008	Russia	Khimki
9009	Russia	Kholmsk
9010	Russia	Kholmskiy
9011	Russia	Khosta
9012	Russia	Kimovsk
9013	Russia	Kimry
9014	Russia	Kineshma
9015	Russia	Kingisepp
9016	Russia	Kireyevsk
9017	Russia	Kirishi
9018	Russia	Kirov
9019	Russia	Kirovgrad
9020	Russia	Kirovsk
9021	Russia	Kirsanov
9022	Russia	Kirzhach
9023	Russia	Kislovodsk
9024	Russia	Kizel
9025	Russia	Kizilyurt
9026	Russia	Kizlyar
9027	Russia	Klimovsk
9028	Russia	Klin
9029	Russia	Klintsy
9030	Russia	Kochubeyevskoye
9031	Russia	Kodinsk
9032	Russia	Kogalym
9033	Russia	Kokhma
9034	Russia	Kolomenskoye
9035	Russia	Kolomna
9036	Russia	Kolomyagi
9037	Russia	Kolpashevo
9038	Russia	Kolpino
9039	Russia	Kommunar
9040	Russia	Konakovo
9041	Russia	Kondopoga
9042	Russia	Kondrovo
9043	Russia	Konstantinovsk
9044	Russia	Kopeysk
9045	Russia	Korenovsk
9046	Russia	Korkino
9047	Russia	Korolev
9048	Russia	Korsakov
9049	Russia	Koryazhma
9050	Russia	Kostomuksha
9051	Russia	Kostroma
9052	Russia	Kotlas
9053	Russia	Kotlovka
9054	Russia	Kotovo
9055	Russia	Kotovsk
9056	Russia	Kovdor
9057	Russia	Kovrov
9058	Russia	Kovylkino
9059	Russia	Kozeyevo
9060	Russia	Kozhukhovo
9061	Russia	Krasnoarmeysk
9062	Russia	Krasnoarmeyskaya
9063	Russia	Krasnodar
9064	Russia	Krasnogorsk
9065	Russia	Krasnogvardeyskoye
9066	Russia	Krasnogvargeisky
9067	Russia	Krasnokamensk
9068	Russia	Krasnokamsk
9069	Russia	Krasnoobsk
9070	Russia	Krasnoufimsk
9071	Russia	Krasnovishersk
9072	Russia	Krasnoyarsk
9073	Russia	Krasnoznamensk
9074	Russia	Kronshtadt
9075	Russia	Kropotkin
9076	Russia	Krymsk
9077	Russia	Kstovo
9078	Russia	Kubinka
9079	Russia	Kudepsta
9080	Russia	Kudymkar
9081	Russia	Kukmor
9082	Russia	Kulebaki
9083	Russia	Kulunda
9084	Russia	Kumertau
9085	Russia	Kungur
9086	Russia	Kupchino
9087	Russia	Kupino
9088	Russia	Kurchaloy
9089	Russia	Kurchatov
9090	Russia	Kurgan
9091	Russia	Kurganinsk
9092	Russia	Kurortnyy
9093	Russia	Kurovskoye
9094	Russia	Kursk
9095	Russia	Kurtamysh
9096	Russia	Kusa
9097	Russia	Kushva
9098	Russia	Kuskovo
9099	Russia	Kuvandyk
9100	Russia	Kuybyshev
9101	Russia	Kuznetsk
9102	Russia	Kyakhta
9103	Russia	Kyshtym
9104	Russia	Kyzyl
9105	Russia	Labinsk
9106	Russia	Labytnangi
9107	Russia	Lakinsk
9108	Russia	Langepas
9109	Russia	Lazarevskoye
9110	Russia	Lefortovo
9111	Russia	Leningradskaya
9112	Russia	Leninogorsk
9113	Russia	Leninsk
9114	Russia	Lensk
9115	Russia	Leonovo
9116	Russia	Lermontov
9117	Russia	Lesnoy
9118	Russia	Lesosibirsk
9119	Russia	Lesozavodsk
9120	Russia	Levoberezhnaya
9121	Russia	Levoberezhnyy
9122	Russia	Lianozovo
9123	Russia	Likhobory
9124	Russia	Lipetsk
9125	Russia	Liski
9126	Russia	Livny
9127	Russia	Lobnya
9128	Russia	Lomonosov
9129	Russia	Luchegorsk
9130	Russia	Luga
9131	Russia	Lukhovitsy
9132	Russia	Luzhniki
9133	Russia	Lyantor
9134	Russia	Lyskovo
9135	Russia	Lytkarino
9136	Russia	Lyubertsy
9137	Russia	Lyublino
9138	Russia	Lyudinovo
9139	Russia	Magadan
9140	Russia	Magnitogorsk
9141	Russia	Makhachkala
9142	Russia	Malakhovka
9143	Russia	Malgobek
9144	Russia	Maloyaroslavets
9145	Russia	Manturovo
9146	Russia	Mariinsk
9147	Russia	Markova
9148	Russia	Marks
9149	Russia	Matveyevskoye
9150	Russia	Maykop
9151	Russia	Mayma
9152	Russia	Mednogorsk
9153	Russia	Medvedevo
9154	Russia	Medvedovskaya
9155	Russia	Megion
9156	Russia	Melenki
9157	Russia	Meleuz
9158	Russia	Mendeleyevsk
9159	Russia	Menzelinsk
9160	Russia	Metallostroy
9161	Russia	Metrogorodok
9162	Russia	Mezhdurechensk
9163	Russia	Miass
9164	Russia	Michurinsk
9165	Russia	Mikhalkovo
9166	Russia	Mikhaylovka
9167	Russia	Mikhaylovsk
9168	Russia	Millerovo
9169	Russia	Minusinsk
9170	Russia	Mirny
9171	Russia	Mirnyy
9172	Russia	Monchegorsk
9173	Russia	Monino
9174	Russia	Morozovsk
9175	Russia	Morshansk
9176	Russia	Moscow
9177	Russia	Moskovskiy
9178	Russia	Mostovskoy
9179	Russia	Mozdok
9180	Russia	Mozhaysk
9181	Russia	Mozhga
9182	Russia	Mtsensk
9183	Russia	Muravlenko
9184	Russia	Murmansk
9185	Russia	Murom
9186	Russia	Myski
9187	Russia	Mytishchi
9188	Russia	Nadym
9189	Russia	Nagornyy
9190	Russia	Nakhabino
9191	Russia	Nakhodka
9192	Russia	Nartkala
9193	Russia	Navashino
9194	Russia	Nazarovo
9195	Russia	Neftegorsk
9196	Russia	Neftekamsk
9197	Russia	Neftekumsk
9198	Russia	Nefteyugansk
9199	Russia	Nelidovo
9200	Russia	Nerchinsk
9201	Russia	Nerekhta
9202	Russia	Neryungri
9203	Russia	Nesterovskaya
9204	Russia	Nevinnomyssk
9205	Russia	Nezlobnaya
9206	Russia	Nikolayevsk
9207	Russia	Nikulino
9208	Russia	Nizhnekamsk
9209	Russia	Nizhnesortymskiy
9210	Russia	Nizhneudinsk
9211	Russia	Nizhnevartovsk
9212	Russia	Noginsk
9213	Russia	Norilsk
9214	Russia	Novoaleksandrovsk
9215	Russia	Novoaltaysk
9216	Russia	Novoanninskiy
9217	Russia	Novocheboksarsk
9218	Russia	Novocherkassk
9219	Russia	Novodvinsk
9220	Russia	Novogireyevo
9221	Russia	Novokhovrino
9222	Russia	Novokubansk
9223	Russia	Novokuybyshevsk
9224	Russia	Novokuznetsk
9225	Russia	Novomichurinsk
9226	Russia	Novomoskovsk
9227	Russia	Novopavlovsk
9228	Russia	Novopokrovskaya
9229	Russia	Novorossiysk
9230	Russia	Novoshakhtinsk
9231	Russia	Novosibirsk
9232	Russia	Novosilikatnyy
9233	Russia	Novotitarovskaya
9234	Russia	Novotroitsk
9235	Russia	Novouzensk
9236	Russia	Novovladykino
9237	Russia	Novovoronezh
9238	Russia	Novozybkov
9239	Russia	Noyabrsk
9240	Russia	Nurlat
9241	Russia	Nyagan
9242	Russia	Nyandoma
9243	Russia	Nytva
9244	Russia	Obninsk
9245	Russia	Obukhovo
9246	Russia	Odintsovo
9247	Russia	Okha
9248	Russia	Olenegorsk
9249	Russia	Omsk
9250	Russia	Omutninsk
9251	Russia	Onega
9252	Russia	Ordzhonikidzevskaya
9253	Russia	Orenburg
9254	Russia	Orlovskiy
9255	Russia	Orsk
9256	Russia	Osa
9257	Russia	Osinniki
9258	Russia	Ostankinskiy
9259	Russia	Ostashkov
9260	Russia	Ostrogozhsk
9261	Russia	Ostrov
9262	Russia	Otradnaya
9263	Russia	Otradnoye
9264	Russia	Otradnyy
9265	Russia	Ozerki
9266	Russia	Ozersk
9267	Russia	Pallasovka
9268	Russia	Parnas
9269	Russia	Partizansk
9270	Russia	Pashkovskiy
9271	Russia	Pavlovo
9272	Russia	Pavlovsk
9273	Russia	Pavlovskaya
9274	Russia	Pechora
9275	Russia	Penza
9276	Russia	Perm
9277	Russia	Perovo
9278	Russia	Persianovka
9279	Russia	Pestovo
9280	Russia	Peterhof
9281	Russia	Petrodvorets
9282	Russia	Petrogradka
9283	Russia	Petrovsk
9284	Russia	Petrovskaya
9285	Russia	Petrozavodsk
9286	Russia	Petushki
9287	Russia	Plast
9288	Russia	Plavsk
9289	Russia	Pochep
9290	Russia	Pokachi
9291	Russia	Pokhvistnevo
9292	Russia	Pokrov
9293	Russia	Polevskoy
9294	Russia	Polyarnyy
9295	Russia	Polysayevo
9296	Russia	Poronaysk
9297	Russia	Povorino
9298	Russia	Poykovskiy
9299	Russia	Presnenskiy
9300	Russia	Pridonskoy
9301	Russia	Privolzhsk
9302	Russia	Privolzhskiy
9303	Russia	Priyutovo
9304	Russia	Prokhladnyy
9305	Russia	Proletarsk
9306	Russia	Promyshlennaya
9307	Russia	Protvino
9308	Russia	Pskov
9309	Russia	Pugachev
9310	Russia	Pushchino
9311	Russia	Pushkin
9312	Russia	Pushkino
9313	Russia	Pyatigorsk
9314	Russia	Raduzhny
9315	Russia	Raduzhnyy
9316	Russia	Ramenki
9317	Russia	Rasskazovo
9318	Russia	Raychikhinsk
9319	Russia	Rayevskiy
9320	Russia	Razumnoye
9321	Russia	Reftinskiy
9322	Russia	Reutov
9323	Russia	Revda
9324	Russia	Rezh
9325	Russia	Rodniki
9326	Russia	Rostokino
9327	Russia	Rostov
9328	Russia	Rtishchevo
9329	Russia	Rubtsovsk
9330	Russia	Ruzayevka
9331	Russia	Ryazanskiy
9332	Russia	Ryazhsk
9333	Russia	Rybatskoye
9334	Russia	Rybinsk
9335	Russia	Rybnoye
9336	Russia	Rzhev
9337	Russia	Safonovo
9338	Russia	Salavat
9339	Russia	Salekhard
9340	Russia	Samara
9341	Russia	Sampsonievskiy
9342	Russia	Saraktash
9343	Russia	Saransk
9344	Russia	Sarapul
9345	Russia	Saratov
9346	Russia	Sarov
9347	Russia	Sasovo
9348	Russia	Satka
9349	Russia	Sayanogorsk
9350	Russia	Sayansk
9351	Russia	Segezha
9352	Russia	Semikarakorsk
9353	Russia	Semiluki
9354	Russia	Serdobsk
9355	Russia	Sergach
9356	Russia	Serov
9357	Russia	Serpukhov
9358	Russia	Sertolovo
9359	Russia	Sestroretsk
9360	Russia	Severnyy
9361	Russia	Severodvinsk
9362	Russia	Severomorsk
9363	Russia	Seversk
9364	Russia	Severskaya
9365	Russia	Shadrinsk
9366	Russia	Shakhty
9367	Russia	Shali
9368	Russia	Sharypovo
9369	Russia	Shatura
9370	Russia	Shchelkovo
9371	Russia	Shcherbinka
9372	Russia	Shchigry
9373	Russia	Shchukino
9374	Russia	Shebekino
9375	Russia	Sheksna
9376	Russia	Shelekhov
9377	Russia	Shilovo
9378	Russia	Shimanovsk
9379	Russia	Shumerlya
9380	Russia	Shumikha
9381	Russia	Shushary
9382	Russia	Shushenskoye
9383	Russia	Shuya
9384	Russia	Sibay
9385	Russia	Sim
9386	Russia	Skhodnya
9387	Russia	Skopin
9388	Russia	Slantsy
9389	Russia	Slavgorod
9390	Russia	Slobodka
9391	Russia	Slobodskoy
9392	Russia	Slyudyanka
9393	Russia	Smolensk
9394	Russia	Snezhinsk
9395	Russia	Sobinka
9396	Russia	Sochi
9397	Russia	Sofrino
9398	Russia	Sokol
9399	Russia	Solikamsk
9400	Russia	Solnechnogorsk
9401	Russia	Solntsevo
9402	Russia	Sorochinsk
9403	Russia	Sortavala
9404	Russia	Sosnogorsk
9405	Russia	Sosnovka
9406	Russia	Sosnovoborsk
9407	Russia	Sovetsk
9408	Russia	Sovetskiy
9409	Russia	Sredneuralsk
9410	Russia	Starodub
9411	Russia	Starominskaya
9412	Russia	Staroshcherbinovskaya
9413	Russia	Sterlitamak
9414	Russia	Strezhevoy
9415	Russia	Strogino
9416	Russia	Strunino
9417	Russia	Stupino
9418	Russia	Sukhinichi
9419	Russia	Surgut
9420	Russia	Surkhakhi
9421	Russia	Surovikino
9422	Russia	Suvorov
9423	Russia	Suvorovskaya
9424	Russia	Suzun
9425	Russia	Svetlanovskiy
9426	Russia	Svetlograd
9427	Russia	Svetlyy
9428	Russia	Svetogorsk
9429	Russia	Sviblovo
9430	Russia	Svobodnyy
9431	Russia	Svobody
9432	Russia	Syktyvkar
9433	Russia	Taganrog
9434	Russia	Taganskiy
9435	Russia	Talitsa
9436	Russia	Talnakh
9437	Russia	Tambov
9438	Russia	Tara
9439	Russia	Tashtagol
9440	Russia	Tatarsk
9441	Russia	Tavda
9442	Russia	Tayga
9443	Russia	Tayshet
9444	Russia	Tbilisskaya
9445	Russia	Temryuk
9446	Russia	Terek
9447	Russia	Teykovo
9448	Russia	Tikhoretsk
9449	Russia	Tikhvin
9450	Russia	Toguchin
9451	Russia	Tomilino
9452	Russia	Tomsk
9453	Russia	Topki
9454	Russia	Torzhok
9455	Russia	Tosno
9456	Russia	Troitsk
9457	Russia	Troitskaya
9458	Russia	Trubchevsk
9459	Russia	Trudovoye
9460	Russia	Tsaritsyno
9461	Russia	Tsimlyansk
9462	Russia	Tuapse
9463	Russia	Tuchkovo
9464	Russia	Tula
9465	Russia	Tulun
9466	Russia	Turinsk
9467	Russia	Tutayev
9468	Russia	Tuymazy
9469	Russia	Tver
9470	Russia	Tynda
9471	Russia	Tyrnyauz
9472	Russia	Tyumen
9473	Russia	Uchaly
9474	Russia	Uchkeken
9475	Russia	Udachny
9476	Russia	Udomlya
9477	Russia	Ufa
9478	Russia	Uglich
9479	Russia	Ukhta
9480	Russia	Ulyanovsk
9481	Russia	Unecha
9482	Russia	Untolovo
9483	Russia	Uray
9484	Russia	Uritsk
9485	Russia	Uryupinsk
9486	Russia	Usinsk
9487	Russia	Ussuriysk
9488	Russia	Uva
9489	Russia	Uvarovo
9490	Russia	Uzhur
9491	Russia	Uzlovaya
9492	Russia	Vagonoremont
9493	Russia	Valday
9494	Russia	Valuyki
9495	Russia	Vanino
9496	Russia	Vatutino
9497	Russia	Vereshchagino
9498	Russia	Veshnyaki
9499	Russia	Vichuga
9500	Russia	Vidnoye
9501	Russia	Vikhorevka
9502	Russia	Vilyuchinsk
9503	Russia	Vladikavkaz
9504	Russia	Vladimir
9505	Russia	Vladivostok
9506	Russia	Vnukovo
9507	Russia	Volgodonsk
9508	Russia	Volgograd
9509	Russia	Volgorechensk
9510	Russia	Volkhov
9511	Russia	Vologda
9512	Russia	Volokolamsk
9513	Russia	Volzhsk
9514	Russia	Volzhskiy
9515	Russia	Vorgashor
9516	Russia	Vorkuta
9517	Russia	Voronezh
9518	Russia	Voskresensk
9519	Russia	Vostryakovo
9520	Russia	Votkinsk
9521	Russia	Vsevolozhsk
9522	Russia	Vyazemskiy
9523	Russia	Vyazniki
9524	Russia	Vyborg
9525	Russia	Vyksa
9526	Russia	Vyselki
9527	Russia	Yablonovskiy
9528	Russia	Yagry
9529	Russia	Yakutsk
9530	Russia	Yalutorovsk
9531	Russia	Yanaul
9532	Russia	Yaransk
9533	Russia	Yaroslavl
9534	Russia	Yaroslavskiy
9535	Russia	Yarovoye
9536	Russia	Yartsevo
9537	Russia	Yasenevo
9538	Russia	Yashkino
9539	Russia	Yasnogorsk
9540	Russia	Yasnyy
9541	Russia	Yefremov
9542	Russia	Yegorlykskaya
9543	Russia	Yekaterinburg
9544	Russia	Yelabuga
9545	Russia	Yelets
9546	Russia	Yelizavetinskaya
9547	Russia	Yelizovo
9548	Russia	Yemanzhelinsk
9549	Russia	Yemva
9550	Russia	Yeniseysk
9551	Russia	Yershov
9552	Russia	Yessentuki
9553	Russia	Yessentukskaya
9554	Russia	Yeysk
9555	Russia	Yubileyny
9556	Russia	Yugorsk
9557	Russia	Yurga
9558	Russia	Yuzhnyy
9559	Russia	Zainsk
9560	Russia	Zapolyarnyy
9561	Russia	Zaraysk
9562	Russia	Zarechnyy
9563	Russia	Zarinsk
9564	Russia	Zarya
9565	Russia	Zavodoukovsk
9566	Russia	Zelenchukskaya
9567	Russia	Zelenodolsk
9568	Russia	Zelenogorsk
9569	Russia	Zelenograd
9570	Russia	Zelenokumsk
9571	Russia	Zernograd
9572	Russia	Zeya
9573	Russia	Zheleznodorozhnyy
9574	Russia	Zheleznogorsk
9575	Russia	Zheleznovodsk
9576	Russia	Zherdevka
9577	Russia	Zhigulevsk
9578	Russia	Zhirnovsk
9579	Russia	Zhukovka
9580	Russia	Zhukovskiy
9581	Russia	Zhulebino
9582	Russia	Zima
9583	Russia	Zimovniki
9584	Russia	Zlatoust
9585	Russia	Znamensk
9586	Russia	Zvenigorod
9587	Russia	Zverevo
9588	Russia	Zyablikovo
9589	Russia	Zyuzino
9590	Rwanda	Butare
9591	Rwanda	Byumba
9592	Rwanda	Cyangugu
9593	Rwanda	Gisenyi
9594	Rwanda	Gitarama
9595	Rwanda	Kibungo
9596	Rwanda	Kibuye
9597	Rwanda	Kigali
9598	Rwanda	Musanze
9599	Rwanda	Nzega
9600	Rwanda	Rwamagana
9601	Samoa	Apia
9602	Senegal	Bignona
9603	Senegal	Dakar
9604	Senegal	Dara
9605	Senegal	Kaffrine
9606	Senegal	Kaolack
9607	Senegal	Kayar
9608	Senegal	Kolda
9609	Senegal	Louga
9610	Senegal	Matam
9611	Senegal	Pikine
9612	Senegal	Pourham
9613	Senegal	Pout
9614	Senegal	Tambacounda
9615	Senegal	Touba
9616	Senegal	Ziguinchor
9617	Serbia	Apatin
9618	Serbia	Belgrade
9619	Serbia	Bor
9620	Serbia	Jagodina
9621	Serbia	Kikinda
9622	Serbia	Knjazevac
9623	Serbia	Kragujevac
9624	Serbia	Kraljevo
9625	Serbia	Lazarevac
9626	Serbia	Leskovac
9627	Serbia	Negotin
9628	Serbia	Obrenovac
9629	Serbia	Pirot
9630	Serbia	Prokuplje
9631	Serbia	Ruma
9632	Serbia	Senta
9633	Serbia	Smederevo
9634	Serbia	Sombor
9635	Serbia	Subotica
9636	Serbia	Trstenik
9637	Serbia	Valjevo
9638	Serbia	Vranje
9639	Serbia	Vrbas
9640	Serbia	Zemun
9641	Serbia	Zrenjanin
9642	Seychelles	Victoria
9643	Singapore	Singapore
9644	Slovakia	Bardejov
9645	Slovakia	Bratislava
9646	Slovakia	Brezno
9647	Slovakia	Detva
9648	Slovakia	Galanta
9649	Slovakia	Hlohovec
9650	Slovakia	Levice
9651	Slovakia	Malacky
9652	Slovakia	Martin
9653	Slovakia	Michalovce
9654	Slovakia	Nitra
9655	Slovakia	Pezinok
9656	Slovakia	Poprad
9657	Slovakia	Prievidza
9658	Slovakia	Sellye
9659	Slovakia	Senica
9660	Slovakia	Skalica
9661	Slovakia	Snina
9662	Slovakia	Trnava
9663	Slovakia	Zvolen
9664	Slovenia	Celje
9665	Slovenia	Koper
9666	Slovenia	Kranj
9667	Slovenia	Ljubljana
9668	Slovenia	Maribor
9669	Slovenia	Ptuj
9670	Slovenia	Trbovlje
9671	Slovenia	Velenje
9672	Somalia	Afgooye
9673	Somalia	Baardheere
9674	Somalia	Baidoa
9675	Somalia	Baki
9676	Somalia	Beledweyne
9677	Somalia	Berbera
9678	Somalia	Bosaso
9679	Somalia	Burao
9680	Somalia	Buulobarde
9681	Somalia	Buurhakaba
9682	Somalia	Ceeldheer
9683	Somalia	Ceerigaabo
9684	Somalia	Eyl
9685	Somalia	Gaalkacyo
9686	Somalia	Garoowe
9687	Somalia	Hargeysa
9688	Somalia	Jamaame
9689	Somalia	Jawhar
9690	Somalia	Jilib
9691	Somalia	Kismayo
9692	Somalia	Laascaanood
9693	Somalia	Luuq
9694	Somalia	Marka
9695	Somalia	Mogadishu
9696	Somalia	Qandala
9697	Somalia	Qoryooley
9698	Somalia	Wanlaweyn
9699	Spain	Adeje
9700	Spain	Adra
9701	Spain	Albacete
9702	Spain	Albal
9703	Spain	Albolote
9704	Spain	Alboraya
9705	Spain	Alcantarilla
9706	Spain	Alcobendas
9707	Spain	Alcoy
9708	Spain	Aldaia
9709	Spain	Alfafar
9710	Spain	Algeciras
9711	Spain	Algete
9712	Spain	Algorta
9713	Spain	Alicante
9714	Spain	Aljaraque
9715	Spain	Almansa
9716	Spain	Almassora
9717	Spain	Almendralejo
9718	Spain	Almonte
9719	Spain	Almozara
9720	Spain	Altea
9721	Spain	Alzira
9722	Spain	Amorebieta
9723	Spain	Amposta
9724	Spain	Antequera
9725	Spain	Aranjuez
9726	Spain	Archena
9727	Spain	Arganda
9728	Spain	Arganzuela
9729	Spain	Armilla
9730	Spain	Arona
9731	Spain	Arrecife
9732	Spain	Arteixo
9733	Spain	Arucas
9734	Spain	Aspe
9735	Spain	Atarfe
9736	Spain	Ayamonte
9737	Spain	Badajoz
9738	Spain	Badalona
9739	Spain	Baena
9740	Spain	Baeza
9741	Spain	Balaguer
9742	Spain	Banyoles
9743	Spain	Barakaldo
9744	Spain	Barbastro
9745	Spain	Barcelona
9746	Spain	Basauri
9747	Spain	Baza
9748	Spain	Benavente
9749	Spain	Benidorm
9750	Spain	Berga
9751	Spain	Berja
9752	Spain	Bermeo
9753	Spain	Bilbao
9754	Spain	Blanes
9755	Spain	Boiro
9756	Spain	Bormujos
9757	Spain	Burgos
9758	Spain	Burjassot
9759	Spain	Burlata
9760	Spain	Burriana
9761	Spain	Cabra
9762	Spain	Cadiz
9763	Spain	Calafell
9764	Spain	Calahorra
9765	Spain	Calatayud
9766	Spain	Calella
9767	Spain	Calp
9768	Spain	Camargo
9769	Spain	Camas
9770	Spain	Cambre
9771	Spain	Cambrils
9772	Spain	Candelaria
9773	Spain	Canovelles
9774	Spain	Carabanchel
9775	Spain	Caravaca
9776	Spain	Carballo
9777	Spain	Carcaixent
9778	Spain	Cardedeu
9779	Spain	Carlet
9780	Spain	Carmona
9781	Spain	Cartagena
9782	Spain	Cartaya
9783	Spain	Castelldefels
9784	Spain	Catarroja
9785	Spain	Ceuta
9786	Spain	Chipiona
9787	Spain	Ciempozuelos
9788	Spain	Cieza
9789	Spain	Ciutadella
9790	Spain	Coslada
9791	Spain	Crevillente
9792	Spain	Cuenca
9793	Spain	Cullera
9794	Spain	Culleredo
9795	Spain	Daimiel
9796	Spain	Delicias
9797	Spain	Denia
9798	Spain	Durango
9799	Spain	Eibar
9800	Spain	Eixample
9801	Spain	Elche
9802	Spain	Elda
9803	Spain	Erandio
9804	Spain	Ermua
9805	Spain	Errenteria
9806	Spain	Esparreguera
9807	Spain	Estepona
9808	Spain	Felanitx
9809	Spain	Ferrol
9810	Spain	Figueras
9811	Spain	Figueres
9812	Spain	Fuengirola
9813	Spain	Fuenlabrada
9814	Spain	Galapagar
9815	Spain	Galdakao
9816	Spain	Gandia
9817	Spain	Getafe
9818	Spain	Getxo
9819	Spain	Girona
9820	Spain	Granada
9821	Spain	Granollers
9822	Spain	Guadalajara
9823	Spain	Guadix
9824	Spain	Hernani
9825	Spain	Hondarribia
9826	Spain	Hortaleza
9827	Spain	Huelva
9828	Spain	Huesca
9829	Spain	Ibi
9830	Spain	Ibiza
9831	Spain	Igualada
9832	Spain	Illescas
9833	Spain	Inca
9834	Spain	Ingenio
9835	Spain	Irun
9836	Spain	Iturrama
9837	Spain	Javea
9838	Spain	Jumilla
9839	Spain	Lasarte
9840	Spain	Latina
9841	Spain	Lebrija
9842	Spain	Leioa
9843	Spain	Lepe
9844	Spain	Linares
9845	Spain	Lleida
9846	Spain	Llucmajor
9847	Spain	Loja
9848	Spain	Lorca
9849	Spain	Lucena
9850	Spain	Lugo
9851	Spain	Madrid
9852	Spain	Majadahonda
9853	Spain	Manacor
9854	Spain	Manises
9855	Spain	Manlleu
9856	Spain	Manresa
9857	Spain	Manzanares
9858	Spain	Maracena
9859	Spain	Marbella
9860	Spain	Marchena
9861	Spain	Martorell
9862	Spain	Martos
9863	Spain	Maspalomas
9864	Spain	Massamagrell
9865	Spain	Melilla
9866	Spain	Mieres
9867	Spain	Mijas
9868	Spain	Mislata
9869	Spain	Moguer
9870	Spain	Moncada
9871	Spain	Montecanal
9872	Spain	Montijo
9873	Spain	Montilla
9874	Spain	Moratalaz
9875	Spain	Motril
9876	Spain	Muchamiel
9877	Spain	Mula
9878	Spain	Mungia
9879	Spain	Murcia
9880	Spain	Natahoyo
9881	Spain	Navalcarnero
9882	Spain	Nerja
9883	Spain	Novelda
9884	Spain	Oleiros
9885	Spain	Oliva
9886	Spain	Olot
9887	Spain	Onda
9888	Spain	Ontinyent
9889	Spain	Oria
9890	Spain	Orihuela
9891	Spain	Osuna
9892	Spain	Ourense
9893	Spain	Oviedo
9894	Spain	Paiporta
9895	Spain	Palafrugell
9896	Spain	Palencia
9897	Spain	Palma
9898	Spain	Pamplona
9899	Spain	Parla
9900	Spain	Pasaia
9901	Spain	Paterna
9902	Spain	Picassent
9903	Spain	Pinto
9904	Spain	Plasencia
9905	Spain	Poio
9906	Spain	Ponferrada
9907	Spain	Ponteareas
9908	Spain	Pontevedra
9909	Spain	Portugalete
9910	Spain	Pozoblanco
9911	Spain	Puertollano
9912	Spain	Redondela
9913	Spain	Requena
9914	Spain	Retiro
9915	Spain	Reus
9916	Spain	Ribarroja
9917	Spain	Ribeira
9918	Spain	Ripollet
9919	Spain	Rojales
9920	Spain	Ronda
9921	Spain	Roses
9922	Spain	Rota
9923	Spain	Sabadell
9924	Spain	Sagunto
9925	Spain	Salamanca
9926	Spain	Salou
9927	Spain	Salt
9928	Spain	Sama
9929	Spain	Santander
9930	Spain	Santomera
9931	Spain	Santurtzi
9932	Spain	Santutxu
9933	Spain	Sanxenxo
9934	Spain	Segovia
9935	Spain	Sestao
9936	Spain	Sevilla
9937	Spain	Silla
9938	Spain	Sitges
9939	Spain	Soria
9940	Spain	Sueca
9941	Spain	Tacoronte
9942	Spain	Tarifa
9943	Spain	Tarragona
9944	Spain	Teguise
9945	Spain	Telde
9946	Spain	Teo
9947	Spain	Terrassa
9948	Spain	Teruel
9949	Spain	Toledo
9950	Spain	Tolosa
9951	Spain	Tomares
9952	Spain	Tomelloso
9953	Spain	Tordera
9954	Spain	Torredembarra
9955	Spain	Torrelavega
9956	Spain	Torrelodones
9957	Spain	Torremolinos
9958	Spain	Torrent
9959	Spain	Torrevieja
9960	Spain	Torrox
9961	Spain	Tortosa
9962	Spain	Totana
9963	Spain	Tudela
9964	Spain	Tui
9965	Spain	Ubrique
9966	Spain	Usera
9967	Spain	Utebo
9968	Spain	Utrera
9969	Spain	Valdemoro
9970	Spain	Valencia
9971	Spain	Valladolid
9972	Spain	Valls
9973	Spain	Vic
9974	Spain	Vigo
9975	Spain	Viladecans
9976	Spain	Vilalba
9977	Spain	Vilaseca
9978	Spain	Villajoyosa
9979	Spain	Villaquilambre
9980	Spain	Villarrobledo
9981	Spain	Villaverde
9982	Spain	Villena
9983	Spain	Viveiro
9984	Spain	Xirivella
9985	Spain	Yecla
9986	Spain	Zafra
9987	Spain	Zamora
9988	Spain	Zaragoza
9989	Spain	Zarautz
9990	Spain	Zubia
9991	Sudan	Atbara
9992	Sudan	Berber
9993	Sudan	Dilling
9994	Sudan	Doka
9995	Sudan	Geneina
9996	Sudan	Kadugli
9997	Sudan	Kassala
9998	Sudan	Khartoum
9999	Sudan	Kosti
10000	Sudan	Kuraymah
10001	Sudan	Maiurno
10002	Sudan	Omdurman
10003	Sudan	Rabak
10004	Sudan	Shendi
10005	Sudan	Singa
10006	Sudan	Sinnar
10007	Sudan	Zalingei
10008	Suriname	Lelydorp
10009	Suriname	Paramaribo
10010	Swaziland	Lobamba
10011	Swaziland	Manzini
10012	Swaziland	Mbabane
10013	Sweden	Boden
10014	Sweden	Boo
10015	Sweden	Bromma
10016	Sweden	Eskilstuna
10017	Sweden	Falkenberg
10018	Sweden	Falun
10019	Sweden	Halmstad
10020	Sweden	Haninge
10021	Sweden	Helsingborg
10022	Sweden	Huddinge
10023	Sweden	Huskvarna
10024	Sweden	Jakobsberg
10025	Sweden	Kalmar
10026	Sweden	Karlshamn
10027	Sweden	Karlskoga
10028	Sweden	Karlskrona
10029	Sweden	Karlstad
10030	Sweden	Katrineholm
10031	Sweden	Kiruna
10032	Sweden	Kristianstad
10033	Sweden	Kristinehamn
10034	Sweden	Kungsbacka
10035	Sweden	Landskrona
10036	Sweden	Lerum
10037	Sweden	Lund
10038	Sweden	Majorna
10039	Sweden	Motala
10040	Sweden	Nacka
10041	Sweden	Oskarshamn
10042	Sweden	Partille
10043	Sweden	Sandviken
10044	Sweden	Skara
10045	Sweden	Sollentuna
10046	Sweden	Solna
10047	Sweden	Stockholm
10048	Sweden	Sundbyberg
10049	Sweden	Sundsvall
10050	Sweden	Trelleborg
10051	Sweden	Tullinge
10052	Sweden	Tumba
10053	Sweden	Uddevalla
10054	Sweden	Uppsala
10055	Sweden	Vallentuna
10056	Sweden	Varberg
10057	Sweden	Visby
10058	Sweden	Ystad
10059	Switzerland	Aarau
10060	Switzerland	Adliswil
10061	Switzerland	Allschwil
10062	Switzerland	Baar
10063	Switzerland	Baden
10064	Switzerland	Basel
10065	Switzerland	Bellinzona
10066	Switzerland	Bern
10067	Switzerland	Carouge
10068	Switzerland	Chur
10069	Switzerland	Dietikon
10070	Switzerland	Emmen
10071	Switzerland	Frauenfeld
10072	Switzerland	Fribourg
10073	Switzerland	Gossau
10074	Switzerland	Grenchen
10075	Switzerland	Herisau
10076	Switzerland	Horgen
10077	Switzerland	Jona
10078	Switzerland	Kloten
10079	Switzerland	Kreuzlingen
10080	Switzerland	Kriens
10081	Switzerland	Lancy
10082	Switzerland	Lausanne
10083	Switzerland	Littau
10084	Switzerland	Lugano
10085	Switzerland	Luzern
10086	Switzerland	Meyrin
10087	Switzerland	Monthey
10088	Switzerland	Montreux
10089	Switzerland	Muttenz
10090	Switzerland	Nyon
10091	Switzerland	Olten
10092	Switzerland	Onex
10093	Switzerland	Pully
10094	Switzerland	Rapperswil
10095	Switzerland	Renens
10096	Switzerland	Riehen
10097	Switzerland	Schaffhausen
10098	Switzerland	Sierre
10099	Switzerland	Sitten
10100	Switzerland	Steffisburg
10101	Switzerland	Thun
10102	Switzerland	Uster
10103	Switzerland	Vernier
10104	Switzerland	Vevey
10105	Switzerland	Wettingen
10106	Switzerland	Wil
10107	Switzerland	Winterthur
10108	Switzerland	Zug
10109	Syria	Aleppo
10110	Syria	Binnish
10111	Syria	Damascus
10112	Syria	Douma
10113	Syria	Homs
10114	Syria	Idlib
10115	Syria	Inkhil
10116	Syria	Jablah
10117	Syria	Latakia
10118	Syria	Manbij
10119	Syria	Nubl
10120	Syria	Satita
10121	Syria	Souran
10122	Syria	Tadmur
10123	Syria	Tallkalakh
10124	Syria	Tartouss
10125	Taiwan	Banqiao
10126	Taiwan	Daxi
10127	Taiwan	Douliu
10128	Taiwan	Hengchun
10129	Taiwan	Hsinchu
10130	Taiwan	Jincheng
10131	Taiwan	Kaohsiung
10132	Taiwan	Keelung
10133	Taiwan	Lugu
10134	Taiwan	Magong
10135	Taiwan	Nantou
10136	Taiwan	Puli
10137	Taiwan	Taichung
10138	Taiwan	Tainan
10139	Taiwan	Taipei
10140	Taiwan	Yilan
10141	Taiwan	Yujing
10142	Tajikistan	Boshkengash
10143	Tajikistan	Chkalov
10144	Tajikistan	Chubek
10145	Tajikistan	Danghara
10146	Tajikistan	Dushanbe
10147	Tajikistan	Farkhor
10148	Tajikistan	Hisor
10149	Tajikistan	Isfara
10150	Tajikistan	Ishqoshim
10151	Tajikistan	Istaravshan
10152	Tajikistan	Khorugh
10153	Tajikistan	Kolkhozobod
10154	Tajikistan	Konibodom
10155	Tajikistan	Moskovskiy
10156	Tajikistan	Norak
10157	Tajikistan	Panjakent
10158	Tajikistan	Proletar
10159	Tajikistan	Tursunzoda
10160	Tajikistan	Vahdat
10161	Tajikistan	Vakhsh
10162	Tajikistan	Yovon
10163	Tanzania	Arusha
10164	Tanzania	Babati
10165	Tanzania	Bagamoyo
10166	Tanzania	Bariadi
10167	Tanzania	Bashanet
10168	Tanzania	Basotu
10169	Tanzania	Biharamulo
10170	Tanzania	Bugarama
10171	Tanzania	Bukoba
10172	Tanzania	Bunda
10173	Tanzania	Bungu
10174	Tanzania	Buseresere
10175	Tanzania	Butiama
10176	Tanzania	Chala
10177	Tanzania	Chalinze
10178	Tanzania	Chanika
10179	Tanzania	Chato
10180	Tanzania	Chimala
10181	Tanzania	Dareda
10182	Tanzania	Dodoma
10183	Tanzania	Dongobesh
10184	Tanzania	Galappo
10185	Tanzania	Geiro
10186	Tanzania	Geita
10187	Tanzania	Hedaru
10188	Tanzania	Ifakara
10189	Tanzania	Igugunu
10190	Tanzania	Igunga
10191	Tanzania	Igurusi
10192	Tanzania	Ikungi
10193	Tanzania	Ilembula
10194	Tanzania	Ilongero
10195	Tanzania	Ilula
10196	Tanzania	Ipinda
10197	Tanzania	Iringa
10198	Tanzania	Isaka
10199	Tanzania	Itigi
10200	Tanzania	Izazi
10201	Tanzania	Kabanga
10202	Tanzania	Kahama
10203	Tanzania	Kakonko
10204	Tanzania	Kamachumu
10205	Tanzania	Kasamwa
10206	Tanzania	Kasulu
10207	Tanzania	Katerero
10208	Tanzania	Katoro
10209	Tanzania	Katumba
10210	Tanzania	Kibaha
10211	Tanzania	Kibakwe
10212	Tanzania	Kibara
10213	Tanzania	Kibiti
10214	Tanzania	Kibondo
10215	Tanzania	Kidatu
10216	Tanzania	Kidodi
10217	Tanzania	Kigoma
10218	Tanzania	Kigonsera
10219	Tanzania	Kihangara
10220	Tanzania	Kilosa
10221	Tanzania	Kingori
10222	Tanzania	Kiomboi
10223	Tanzania	Kirando
10224	Tanzania	Kiratu
10225	Tanzania	Kisesa
10226	Tanzania	Kishapu
10227	Tanzania	Kitama
10228	Tanzania	Kiwira
10229	Tanzania	Kondoa
10230	Tanzania	Kyela
10231	Tanzania	Laela
10232	Tanzania	Lalago
10233	Tanzania	Lembeni
10234	Tanzania	Lindi
10235	Tanzania	Liwale
10236	Tanzania	Luchingu
10237	Tanzania	Lugoba
10238	Tanzania	Lukuledi
10239	Tanzania	Lushoto
10240	Tanzania	Mabama
10241	Tanzania	Mafinga
10242	Tanzania	Magole
10243	Tanzania	Magomeni
10244	Tanzania	Magugu
10245	Tanzania	Mahanje
10246	Tanzania	Makumbako
10247	Tanzania	Makuyuni
10248	Tanzania	Malampaka
10249	Tanzania	Malinyi
10250	Tanzania	Maposeni
10251	Tanzania	Maramba
10252	Tanzania	Masasi
10253	Tanzania	Masumbwe
10254	Tanzania	Maswa
10255	Tanzania	Matai
10256	Tanzania	Matiri
10257	Tanzania	Matui
10258	Tanzania	Mazinde
10259	Tanzania	Mbeya
10260	Tanzania	Mbinga
10261	Tanzania	Mbuguni
10262	Tanzania	Merelani
10263	Tanzania	Mgandu
10264	Tanzania	Mhango
10265	Tanzania	Mikumi
10266	Tanzania	Misungwi
10267	Tanzania	Mkuranga
10268	Tanzania	Mlalo
10269	Tanzania	Mlandizi
10270	Tanzania	Mlangali
10271	Tanzania	Mlimba
10272	Tanzania	Mlowo
10273	Tanzania	Morogoro
10274	Tanzania	Moshi
10275	Tanzania	Mpanda
10276	Tanzania	Mpwapwa
10277	Tanzania	Msowero
10278	Tanzania	Mtinko
10279	Tanzania	Mtwango
10280	Tanzania	Mtwara
10281	Tanzania	Mugumu
10282	Tanzania	Muheza
10283	Tanzania	Mungaa
10284	Tanzania	Muriti
10285	Tanzania	Musoma
10286	Tanzania	Mvomero
10287	Tanzania	Mwadui
10288	Tanzania	Mwandiga
10289	Tanzania	Mwanza
10290	Tanzania	Nachingwea
10291	Tanzania	Namanyere
10292	Tanzania	Nanganga
10293	Tanzania	Nangomba
10294	Tanzania	Nangwa
10295	Tanzania	Nanyamba
10296	Tanzania	Ngara
10297	Tanzania	Ngerengere
10298	Tanzania	Ngudu
10299	Tanzania	Nguruka
10300	Tanzania	Njombe
10301	Tanzania	Nshamba
10302	Tanzania	Nsunga
10303	Tanzania	Nyakabindi
10304	Tanzania	Nyalikungu
10305	Tanzania	Nyamuswa
10306	Tanzania	Nyangao
10307	Tanzania	Nzega
10308	Tanzania	Puma
10309	Tanzania	Rujewa
10310	Tanzania	Rulenge
10311	Tanzania	Same
10312	Tanzania	Sepuka
10313	Tanzania	Shelui
10314	Tanzania	Shinyanga
10315	Tanzania	Sikonge
10316	Tanzania	Singida
10317	Tanzania	Sirari
10318	Tanzania	Sokoni
10319	Tanzania	Somanda
10320	Tanzania	Songea
10321	Tanzania	Songwa
10322	Tanzania	Sumbawanga
10323	Tanzania	Tabora
10324	Tanzania	Tandahimba
10325	Tanzania	Tanga
10326	Tanzania	Tarime
10327	Tanzania	Tinde
10328	Tanzania	Tingi
10329	Tanzania	Tukuyu
10330	Tanzania	Tumbi
10331	Tanzania	Tunduma
10332	Tanzania	Urambo
10333	Tanzania	Usagara
10334	Tanzania	Usevia
10335	Tanzania	Ushirombo
10336	Tanzania	Uvinza
10337	Tanzania	Uyovu
10338	Tanzania	Vikindu
10339	Tanzania	Vwawa
10340	Tanzania	Wete
10341	Tanzania	Zanzibar
10342	Thailand	Aranyaprathet
10343	Thailand	Bangkok
10344	Thailand	Betong
10345	Thailand	Buriram
10346	Thailand	Chachoengsao
10347	Thailand	Chaiyaphum
10348	Thailand	Chanthaburi
10349	Thailand	Chumphon
10350	Thailand	Kalasin
10351	Thailand	Kamalasai
10352	Thailand	Kanchanaburi
10353	Thailand	Kantharalak
10354	Thailand	Kathu
10355	Thailand	Klaeng
10356	Thailand	Krabi
10357	Thailand	Kuchinarai
10358	Thailand	Lampang
10359	Thailand	Lamphun
10360	Thailand	Loei
10361	Thailand	Mukdahan
10362	Thailand	Nan
10363	Thailand	Narathiwat
10364	Thailand	Pattani
10365	Thailand	Phatthalung
10366	Thailand	Phatthaya
10367	Thailand	Phayao
10368	Thailand	Phetchabun
10369	Thailand	Phetchaburi
10370	Thailand	Phichit
10371	Thailand	Phitsanulok
10372	Thailand	Photharam
10373	Thailand	Phrae
10374	Thailand	Phuket
10375	Thailand	Phunphin
10376	Thailand	Ranong
10377	Thailand	Ranot
10378	Thailand	Ratchaburi
10379	Thailand	Rayong
10380	Thailand	Sadao
10381	Thailand	Saraburi
10382	Thailand	Sattahip
10383	Thailand	Satun
10384	Thailand	Sawankhalok
10385	Thailand	Seka
10386	Thailand	Songkhla
10387	Thailand	Sukhothai
10388	Thailand	Surin
10389	Thailand	Tak
10390	Thailand	Thoen
10391	Thailand	Trang
10392	Thailand	Trat
10393	Thailand	Uttaradit
10394	Thailand	Wichit
10395	Thailand	Yala
10396	Thailand	Yaring
10397	Thailand	Yasothon
10398	Togo	Badou
10399	Togo	Bafilo
10400	Togo	Bassar
10401	Togo	Dapaong
10402	Togo	Kara
10403	Togo	Niamtougou
10404	Togo	Sotouboua
10405	Togo	Tchamba
10406	Togo	Vogan
10407	Tunisia	Akouda
10408	Tunisia	Ariana
10409	Tunisia	Bekalta
10410	Tunisia	Bizerte
10411	Tunisia	Carthage
10412	Tunisia	Chebba
10413	Tunisia	Djemmal
10414	Tunisia	Douane
10415	Tunisia	Douz
10416	Tunisia	Gafsa
10417	Tunisia	Gremda
10418	Tunisia	Hammamet
10419	Tunisia	Jendouba
10420	Tunisia	Kairouan
10421	Tunisia	Kasserine
10422	Tunisia	Kebili
10423	Tunisia	Korba
10424	Tunisia	Mahdia
10425	Tunisia	Manouba
10426	Tunisia	Mateur
10427	Tunisia	Medenine
10428	Tunisia	Metlaoui
10429	Tunisia	Midoun
10430	Tunisia	Monastir
10431	Tunisia	Msaken
10432	Tunisia	Nabeul
10433	Tunisia	Nefta
10434	Tunisia	Ouardenine
10435	Tunisia	Sfax
10436	Tunisia	Siliana
10437	Tunisia	Skanes
10438	Tunisia	Sousse
10439	Tunisia	Tajerouine
10440	Tunisia	Takelsa
10441	Tunisia	Tataouine
10442	Tunisia	Thala
10443	Tunisia	Tozeur
10444	Tunisia	Tunis
10445	Tunisia	Zaghouan
10446	Tunisia	Zarzis
10447	Tunisia	Zouila
10448	Turkey	Adana
10449	Turkey	Adilcevaz
10450	Turkey	Afyonkarahisar
10451	Turkey	Ahlat
10452	Turkey	Akhisar
10453	Turkey	Aksaray
10454	Turkey	Alaca
10455	Turkey	Alanya
10456	Turkey	Amasya
10457	Turkey	Anamur
10458	Turkey	Ankara
10459	Turkey	Antakya
10460	Turkey	Antalya
10461	Turkey	Ardahan
10462	Turkey	Arhavi
10463	Turkey	Arsin
10464	Turkey	Artvin
10465	Turkey	Babaeski
10466	Turkey	Bafra
10467	Turkey	Banaz
10468	Turkey	Baskil
10469	Turkey	Batikent
10470	Turkey	Batman
10471	Turkey	Bayburt
10472	Turkey	Belek
10473	Turkey	Belen
10474	Turkey	Bergama
10475	Turkey	Besni
10476	Turkey	Beykonak
10477	Turkey	Biga
10478	Turkey	Bilecik
10479	Turkey	Birecik
10480	Turkey	Bismil
10481	Turkey	Bitlis
10482	Turkey	Bodrum
10483	Turkey	Bolu
10484	Turkey	Bolvadin
10485	Turkey	Bor
10486	Turkey	Boyabat
10487	Turkey	Bozova
10488	Turkey	Bucak
10489	Turkey	Bulancak
10490	Turkey	Burdur
10491	Turkey	Burhaniye
10492	Turkey	Bursa
10493	Turkey	Ceyhan
10494	Turkey	Cimin
10495	Turkey	Cizre
10496	Turkey	Dalaman
10497	Turkey	Darende
10498	Turkey	Demirci
10499	Turkey	Denizciler
10500	Turkey	Denizli
10501	Turkey	Develi
10502	Turkey	Devrek
10503	Turkey	Didim
10504	Turkey	Dinar
10505	Turkey	Diyadin
10506	Turkey	Dursunbey
10507	Turkey	Edirne
10508	Turkey	Edremit
10509	Turkey	Elbistan
10510	Turkey	Emet
10511	Turkey	Erbaa
10512	Turkey	Erdek
10513	Turkey	Erdemli
10514	Turkey	Ergani
10515	Turkey	Ermenek
10516	Turkey	Erzin
10517	Turkey	Erzincan
10518	Turkey	Erzurum
10519	Turkey	Esenler
10520	Turkey	Esenyurt
10521	Turkey	Espiye
10522	Turkey	Ezine
10523	Turkey	Fatsa
10524	Turkey	Ferizli
10525	Turkey	Fethiye
10526	Turkey	Gaziantep
10527	Turkey	Gebze
10528	Turkey	Gediz
10529	Turkey	Gelibolu
10530	Turkey	Gemerek
10531	Turkey	Gemlik
10532	Turkey	Gerede
10533	Turkey	Geyve
10534	Turkey	Giresun
10535	Turkey	Gumushkhane
10536	Turkey	Hadim
10537	Turkey	Hakkari
10538	Turkey	Havza
10539	Turkey	Hayrabolu
10540	Turkey	Hendek
10541	Turkey	Hilvan
10542	Turkey	Hizan
10543	Turkey	Hopa
10544	Turkey	Horasan
10545	Turkey	Isparta
10546	Turkey	Kadirli
10547	Turkey	Kaman
10548	Turkey	Karacabey
10549	Turkey	Karaman
10550	Turkey	Karasu
10551	Turkey	Kars
10552	Turkey	Kastamonu
10553	Turkey	Kayseri
10554	Turkey	Kazan
10555	Turkey	Kelkit
10556	Turkey	Kemer
10557	Turkey	Keskin
10558	Turkey	Kestel
10559	Turkey	Khanjarah
10560	Turkey	Kilis
10561	Turkey	Kocaali
10562	Turkey	Konya
10563	Turkey	Korgan
10564	Turkey	Korkuteli
10565	Turkey	Kozan
10566	Turkey	Kozluk
10567	Turkey	Kula
10568	Turkey	Kulp
10569	Turkey	Kulu
10570	Turkey	Kumru
10571	Turkey	Kurtalan
10572	Turkey	Lice
10573	Turkey	Mahmutlar
10574	Turkey	Malatya
10575	Turkey	Malazgirt
10576	Turkey	Malkara
10577	Turkey	Maltepe
10578	Turkey	Manavgat
10579	Turkey	Manisa
10580	Turkey	Mardin
10581	Turkey	Marmaris
10582	Turkey	Menderes
10583	Turkey	Menemen
10584	Turkey	Mercin
10585	Turkey	Merzifon
10586	Turkey	Midyat
10587	Turkey	Milas
10588	Turkey	Mimarsinan
10589	Turkey	Mucur
10590	Turkey	Mudanya
10591	Turkey	Mut
10592	Turkey	Nazilli
10593	Turkey	Niksar
10594	Turkey	Nizip
10595	Turkey	Nusaybin
10596	Turkey	Of
10597	Turkey	Oltu
10598	Turkey	Ordu
10599	Turkey	Orhangazi
10600	Turkey	Ortaca
10601	Turkey	Osmaneli
10602	Turkey	Osmaniye
10603	Turkey	Pasinler
10604	Turkey	Patnos
10605	Turkey	Rize
10606	Turkey	Safranbolu
10607	Turkey	Salihli
10608	Turkey	Samsun
10609	Turkey	Sancaktepe
10610	Turkey	Sapanca
10611	Turkey	Sarigerme
10612	Turkey	Seferhisar
10613	Turkey	Senirkent
10614	Turkey	Serik
10615	Turkey	Serinhisar
10616	Turkey	Serinyol
10617	Turkey	Siirt
10618	Turkey	Silifke
10619	Turkey	Silivri
10620	Turkey	Silopi
10621	Turkey	Silvan
10622	Turkey	Simav
10623	Turkey	Sinop
10624	Turkey	Sivas
10625	Turkey	Siverek
10626	Turkey	Solhan
10627	Turkey	Soma
10628	Turkey	Sorgun
10629	Turkey	Sultanbeyli
10630	Turkey	Sultangazi
10631	Turkey	Suluova
10632	Turkey	Sungurlu
10633	Turkey	Susurluk
10634	Turkey	Talas
10635	Turkey	Tarsus
10636	Turkey	Tatvan
10637	Turkey	Tekirova
10638	Turkey	Tepecik
10639	Turkey	Terme
10640	Turkey	Tire
10641	Turkey	Tirebolu
10642	Turkey	Tokat
10643	Turkey	Tosya
10644	Turkey	Trabzon
10645	Turkey	Tunceli
10646	Turkey	Turgutlu
10647	Turkey	Turgutreis
10648	Turkey	Turhal
10649	Turkey	Umraniye
10650	Turkey	Urla
10651	Turkey	Van
10652	Turkey	Varto
10653	Turkey	Yakuplu
10654	Turkey	Yalova
10655	Turkey	Yomra
10656	Turkey	Yozgat
10657	Turkey	Zeytinburnu
10658	Turkey	Zile
10659	Turkey	Zonguldak
10660	Turkmenistan	Abadan
10661	Turkmenistan	Annau
10662	Turkmenistan	Ashgabat
10663	Turkmenistan	Atamyrat
10664	Turkmenistan	Baharly
10665	Turkmenistan	Balkanabat
10666	Turkmenistan	Bayramaly
10667	Turkmenistan	Boldumsaz
10668	Turkmenistan	Gazanjyk
10669	Turkmenistan	Gazojak
10670	Turkmenistan	Gowurdak
10671	Turkmenistan	Gumdag
10672	Turkmenistan	Kaka
10673	Turkmenistan	Mary
10674	Turkmenistan	Seydi
10675	Turkmenistan	Tagta
10676	Turkmenistan	Tejen
10677	Turkmenistan	Yylanly
10678	Tuvalu	Funafuti
10679	Uganda	Adjumani
10680	Uganda	Arua
10681	Uganda	Bugiri
10682	Uganda	Bundibugyo
10683	Uganda	Busembatia
10684	Uganda	Busia
10685	Uganda	Buwenge
10686	Uganda	Bwizibwera
10687	Uganda	Entebbe
10688	Uganda	Gulu
10689	Uganda	Hoima
10690	Uganda	Iganga
10691	Uganda	Jinja
10692	Uganda	Kabale
10693	Uganda	Kampala
10694	Uganda	Kamwenge
10695	Uganda	Kasese
10696	Uganda	Kayunga
10697	Uganda	Kireka
10698	Uganda	Kitgum
10699	Uganda	Kotido
10700	Uganda	Kyenjojo
10701	Uganda	Lira
10702	Uganda	Lugazi
10703	Uganda	Luwero
10704	Uganda	Masaka
10705	Uganda	Masindi
10706	Uganda	Mbale
10707	Uganda	Mbarara
10708	Uganda	Mityana
10709	Uganda	Moyo
10710	Uganda	Mubende
10711	Uganda	Mukono
10712	Uganda	Namasuba
10713	Uganda	Nebbi
10714	Uganda	Njeru
10715	Uganda	Ntungamo
10716	Uganda	Nyachera
10717	Uganda	Paidha
10718	Uganda	Pallisa
10719	Uganda	Soroti
10720	Uganda	Tororo
10721	Uganda	Wakiso
10722	Uganda	Wobulenzi
10723	Uganda	Yumbe
10724	Ukraine	Alushta
10725	Ukraine	Amvrosiyivka
10726	Ukraine	Antratsyt
10727	Ukraine	Apostolove
10728	Ukraine	Artsyz
10729	Ukraine	Avdiyivka
10730	Ukraine	Bakhchysaray
10731	Ukraine	Bakhmach
10732	Ukraine	Balaklava
10733	Ukraine	Balakliya
10734	Ukraine	Balta
10735	Ukraine	Bar
10736	Ukraine	Berdychiv
10737	Ukraine	Berehove
10738	Ukraine	Bilopillya
10739	Ukraine	Bohodukhiv
10740	Ukraine	Bohuslav
10741	Ukraine	Bolhrad
10742	Ukraine	Boryslav
10743	Ukraine	Boyarka
10744	Ukraine	Brody
10745	Ukraine	Brovary
10746	Ukraine	Bryanka
10747	Ukraine	Bucha
10748	Ukraine	Cherkasy
10749	Ukraine	Chernihiv
10750	Ukraine	Chernivtsi
10751	Ukraine	Chervonohrad
10752	Ukraine	Chortkiv
10753	Ukraine	Chuhuyiv
10754	Ukraine	Derhachi
10755	Ukraine	Dnipropetrovsk
10756	Ukraine	Dniprorudne
10757	Ukraine	Dobropillya
10758	Ukraine	Dolyna
10759	Ukraine	Donetsk
10760	Ukraine	Drohobych
10761	Ukraine	Druzhkivka
10762	Ukraine	Dubno
10763	Ukraine	Dunaivtsi
10764	Ukraine	Dymytrov
10765	Ukraine	Dzhankoy
10766	Ukraine	Energodar
10767	Ukraine	Fastiv
10768	Ukraine	Feodosiya
10769	Ukraine	Hadyach
10770	Ukraine	Haysyn
10771	Ukraine	Hayvoron
10772	Ukraine	Hlukhiv
10773	Ukraine	Horlivka
10774	Ukraine	Horodok
10775	Ukraine	Horodyshche
10776	Ukraine	Hulyaypole
10777	Ukraine	Irpin
10778	Ukraine	Izmayil
10779	Ukraine	Izyaslav
10780	Ukraine	Izyum
10781	Ukraine	Kakhovka
10782	Ukraine	Kalush
10783	Ukraine	Kalynivka
10784	Ukraine	Kaniv
10785	Ukraine	Karlivka
10786	Ukraine	Kerch
10787	Ukraine	Kharkiv
10788	Ukraine	Kherson
10789	Ukraine	Khust
10790	Ukraine	Kiev
10791	Ukraine	Kiliya
10792	Ukraine	Kirovohrad
10793	Ukraine	Kivertsi
10794	Ukraine	Kivsharivka
10795	Ukraine	Kolomyya
10796	Ukraine	Komsomolsk
10797	Ukraine	Konotop
10798	Ukraine	Korostyshiv
10799	Ukraine	Kostyantynivka
10800	Ukraine	Kozyatyn
10801	Ukraine	Krasnodon
10802	Ukraine	Krasnohrad
10803	Ukraine	Krasyliv
10804	Ukraine	Kremenchuk
10805	Ukraine	Kreminna
10806	Ukraine	Kupjansk
10807	Ukraine	Kurakhovo
10808	Ukraine	Ladyzhyn
10809	Ukraine	Lebedyn
10810	Ukraine	Lozova
10811	Ukraine	Lubny
10812	Ukraine	Luhansk
10813	Ukraine	Lutuhyne
10814	Ukraine	Lviv
10815	Ukraine	Lyubotyn
10816	Ukraine	Makiyivka
10817	Ukraine	Malyn
10818	Ukraine	Mariupol
10819	Ukraine	Merefa
10820	Ukraine	Miskhor
10821	Ukraine	Mukacheve
10822	Ukraine	Mykolayiv
10823	Ukraine	Myrhorod
10824	Ukraine	Nadvirna
10825	Ukraine	Netishyn
10826	Ukraine	Nizhyn
10827	Ukraine	Nosivka
10828	Ukraine	Novoukrayinka
10829	Ukraine	Obukhiv
10830	Ukraine	Ochakiv
10831	Ukraine	Odessa
10832	Ukraine	Okhtyrka
10833	Ukraine	Oleksandriya
10834	Ukraine	Orikhiv
10835	Ukraine	Ovruch
10836	Ukraine	Pavlohrad
10837	Ukraine	Piatykhatky
10838	Ukraine	Pidhorodne
10839	Ukraine	Polohy
10840	Ukraine	Polonne
10841	Ukraine	Poltava
10842	Ukraine	Popasna
10843	Ukraine	Pryluky
10844	Ukraine	Pyryatyn
10845	Ukraine	Reni
10846	Ukraine	Rivne
10847	Ukraine	Romny
10848	Ukraine	Rubizhne
10849	Ukraine	Saky
10850	Ukraine	Sambir
10851	Ukraine	Sarny
10852	Ukraine	Selydove
10853	Ukraine	Sevastopol
10854	Ukraine	Shepetivka
10855	Ukraine	Shostka
10856	Ukraine	Shpola
10857	Ukraine	Simferopol
10858	Ukraine	Skvyra
10859	Ukraine	Slavuta
10860	Ukraine	Sloviansk
10861	Ukraine	Smila
10862	Ukraine	Snizhne
10863	Ukraine	Stakhanov
10864	Ukraine	Starokostyantyniv
10865	Ukraine	Stebnyk
10866	Ukraine	Stryi
10867	Ukraine	Sumy
10868	Ukraine	Svalyava
10869	Ukraine	Svatove
10870	Ukraine	Tokmak
10871	Ukraine	Torez
10872	Ukraine	Truskavets
10873	Ukraine	Uzhhorod
10874	Ukraine	Vasylivka
10875	Ukraine	Vasylkiv
10876	Ukraine	Vatutine
10877	Ukraine	Vinnytsya
10878	Ukraine	Volnovakha
10879	Ukraine	Voznesensk
10880	Ukraine	Vynohradiv
10881	Ukraine	Vyshhorod
10882	Ukraine	Vyshneve
10883	Ukraine	Yahotyn
10884	Ukraine	Yalta
10885	Ukraine	Yasynuvata
10886	Ukraine	Yenakiyeve
10887	Ukraine	Yevpatoriya
10888	Ukraine	Yuzhne
10889	Ukraine	Zaporizhzhya
10890	Ukraine	Zdolbuniv
10891	Ukraine	Zhashkiv
10892	Ukraine	Zhmerynka
10893	Ukraine	Zhytomyr
10894	Ukraine	Zmiyiv
10895	Ukraine	Znomenka
10896	Ukraine	Zolochiv
10897	Ukraine	Zolotonosha
10898	Ukraine	Zuhres
10899	Ukraine	Zvenyhorodka
10900	Uruguay	Artigas
10901	Uruguay	Canelones
10902	Uruguay	Carmelo
10903	Uruguay	Dolores
10904	Uruguay	Durazno
10905	Uruguay	Florida
10906	Uruguay	Maldonado
10907	Uruguay	Melo
10908	Uruguay	Mercedes
10909	Uruguay	Minas
10910	Uruguay	Montevideo
10911	Uruguay	Pando
10912	Uruguay	Progreso
10913	Uruguay	Rivera
10914	Uruguay	Rocha
10915	Uruguay	Salto
10916	Uruguay	Trinidad
10917	Uruguay	Young
10918	Uzbekistan	Andijon
10919	Uzbekistan	Angren
10920	Uzbekistan	Asaka
10921	Uzbekistan	Bekobod
10922	Uzbekistan	Bektemir
10923	Uzbekistan	Beruniy
10924	Uzbekistan	Beshariq
10925	Uzbekistan	Beshkent
10926	Uzbekistan	Boysun
10927	Uzbekistan	Bukhara
10928	Uzbekistan	Chelak
10929	Uzbekistan	Chinoz
10930	Uzbekistan	Chirchiq
10931	Uzbekistan	Chiroqchi
10932	Uzbekistan	Chortoq
10933	Uzbekistan	Dashtobod
10934	Uzbekistan	Denov
10935	Uzbekistan	Fergana
10936	Uzbekistan	Gagarin
10937	Uzbekistan	Galaosiyo
10938	Uzbekistan	Ghijduwon
10939	Uzbekistan	Guliston
10940	Uzbekistan	Gurlan
10941	Uzbekistan	Haqqulobod
10942	Uzbekistan	Hazorasp
10943	Uzbekistan	Iskandar
10944	Uzbekistan	Jizzax
10945	Uzbekistan	Juma
10946	Uzbekistan	Khiwa
10947	Uzbekistan	Kirguli
10948	Uzbekistan	Kitob
10949	Uzbekistan	Kogon
10950	Uzbekistan	Koson
10951	Uzbekistan	Kosonsoy
10952	Uzbekistan	Manghit
10953	Uzbekistan	Muborak
10954	Uzbekistan	Namangan
10955	Uzbekistan	Navoiy
10956	Uzbekistan	Nukus
10957	Uzbekistan	Nurota
10958	Uzbekistan	Ohangaron
10959	Uzbekistan	Olmaliq
10960	Uzbekistan	Oltiariq
10961	Uzbekistan	Oqtosh
10962	Uzbekistan	Parkent
10963	Uzbekistan	Paxtakor
10964	Uzbekistan	Payshanba
10965	Uzbekistan	Piskent
10966	Uzbekistan	Pop
10967	Uzbekistan	Qarshi
10968	Uzbekistan	Qibray
10969	Uzbekistan	Quva
10970	Uzbekistan	Quvasoy
10971	Uzbekistan	Salor
10972	Uzbekistan	Samarqand
10973	Uzbekistan	Shahrisabz
10974	Uzbekistan	Shofirkon
10975	Uzbekistan	Showot
10976	Uzbekistan	Sirdaryo
10977	Uzbekistan	Tashkent
10978	Uzbekistan	Tirmiz
10979	Uzbekistan	Toshbuloq
10980	Uzbekistan	Toshloq
10981	Uzbekistan	Urganch
10982	Uzbekistan	Urgut
10983	Uzbekistan	Uychi
10984	Uzbekistan	Wobkent
10985	Uzbekistan	Yangiobod
10986	Uzbekistan	Yangirabot
10987	Uzbekistan	Yangiyer
10988	Uzbekistan	Yaypan
10989	Uzbekistan	Zafar
10990	Uzbekistan	Zomin
10991	Venezuela	Acarigua
10992	Venezuela	Anaco
10993	Venezuela	Araure
10994	Venezuela	Barcelona
10995	Venezuela	Barinas
10996	Venezuela	Barinitas
10997	Venezuela	Barquisimeto
10998	Venezuela	Baruta
10999	Venezuela	Cabimas
11000	Venezuela	Cagua
11001	Venezuela	Calabozo
11002	Venezuela	Cantaura
11003	Venezuela	Caraballeda
11004	Venezuela	Caracas
11005	Venezuela	Carora
11006	Venezuela	Carrizal
11007	Venezuela	Caucaguita
11008	Venezuela	Chacao
11009	Venezuela	Charallave
11010	Venezuela	Chivacoa
11011	Venezuela	Coro
11012	Venezuela	Ejido
11013	Venezuela	Guacara
11014	Venezuela	Guanare
11015	Venezuela	Guarenas
11016	Venezuela	Guasdualito
11017	Venezuela	Guatire
11018	Venezuela	Lagunillas
11019	Venezuela	Machiques
11020	Venezuela	Maracaibo
11021	Venezuela	Maracay
11022	Venezuela	Mariara
11023	Venezuela	Mucumpiz
11024	Venezuela	Nirgua
11025	Venezuela	Petare
11026	Venezuela	Porlamar
11027	Venezuela	Rubio
11028	Venezuela	Tacarigua
11029	Venezuela	Tinaquillo
11030	Venezuela	Trujillo
11031	Venezuela	Tucupita
11032	Venezuela	Turmero
11033	Venezuela	Upata
11034	Venezuela	Valencia
11035	Venezuela	Valera
11036	Venezuela	Yaritagua
11037	Venezuela	Zaraza
11038	Vietnam	Haiphong
11039	Vietnam	Hanoi
11040	Vietnam	Pleiku
11041	Vietnam	Sadek
11042	Vietnam	Vinh
11043	Yemen	Aden
11044	Yemen	Ataq
11045	Yemen	Ibb
11046	Yemen	Sanaa
11047	Zambia	Chililabombwe
11048	Zambia	Chingola
11049	Zambia	Chipata
11050	Zambia	Choma
11051	Zambia	Kabwe
11052	Zambia	Kafue
11053	Zambia	Kalulushi
11054	Zambia	Kansanshi
11055	Zambia	Kasama
11056	Zambia	Kawambwa
11057	Zambia	Kitwe
11058	Zambia	Livingstone
11059	Zambia	Luanshya
11060	Zambia	Lusaka
11061	Zambia	Mansa
11062	Zambia	Mazabuka
11063	Zambia	Mbala
11064	Zambia	Mongu
11065	Zambia	Monze
11066	Zambia	Mpika
11067	Zambia	Mufulira
11068	Zambia	Mumbwa
11069	Zambia	Nchelenge
11070	Zambia	Ndola
11071	Zambia	Petauke
11072	Zambia	Samfya
11073	Zambia	Sesheke
11074	Zambia	Siavonga
11075	Zimbabwe	Beitbridge
11076	Zimbabwe	Bindura
11077	Zimbabwe	Bulawayo
11078	Zimbabwe	Chegutu
11079	Zimbabwe	Chinhoyi
11080	Zimbabwe	Chipinge
11081	Zimbabwe	Chiredzi
11082	Zimbabwe	Chitungwiza
11083	Zimbabwe	Epworth
11084	Zimbabwe	Gokwe
11085	Zimbabwe	Gweru
11086	Zimbabwe	Harare
11087	Zimbabwe	Hwange
11088	Zimbabwe	Kadoma
11089	Zimbabwe	Kariba
11090	Zimbabwe	Karoi
11091	Zimbabwe	Kwekwe
11092	Zimbabwe	Marondera
11093	Zimbabwe	Masvingo
11094	Zimbabwe	Mutare
11095	Zimbabwe	Norton
11096	Zimbabwe	Redcliff
11097	Zimbabwe	Rusape
11098	Zimbabwe	Shurugwi
11099	Zimbabwe	Zvishavane
11100	USA	New York
11101	USA	Los Angeles
11102	USA	Chicago
11103	USA	Houston
11104	USA	Phoenix
11105	USA	Philadelphia
11106	USA	San Antonio
11107	USA	San Diego
11108	USA	Dallas
11109	USA	San Jose
11110	USA	Austin
11111	USA	Jacksonville
11112	USA	Fort Worth
11113	USA	Columbus
11114	USA	Charlotte
11115	USA	San Francisco
11116	USA	Indianapolis
11117	USA	Seattle
11118	USA	Denver
11119	USA	Washington
11120	USA	Boston
11121	USA	El Paso
11122	USA	Nashville
11123	USA	Detroit
11124	USA	Oklahoma City
11125	USA	Portland
11126	USA	Las Vegas
11127	USA	Memphis
11128	USA	Louisville
11129	USA	Baltimore
11130	USA	Milwaukee
11131	USA	Albuquerque
11132	USA	Tucson
11133	USA	Fresno
11134	USA	Mesa
11135	USA	Sacramento
11136	USA	Atlanta
11137	USA	Kansas City
11138	USA	Colorado Springs
11139	USA	Miami
11140	USA	Raleigh
11141	USA	Omaha
11142	USA	Long Beach
11143	USA	Virginia Beach
11144	USA	Oakland
11145	USA	Minneapolis
11146	USA	Tulsa
11147	USA	Tampa
11148	USA	Cambridge
11149	USA	Stanford
11150	USA	Berkeley
11151	USA	Princeton
11152	USA	New Haven
11153	USA	Pasadena
11154	USA	Arlington
\.


--
-- Data for Name: countries; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.countries (country, id) FROM stdin;
Afghanistan	1
Albania	2
Algeria	3
Angola	4
Argentina	5
Armenia	6
Aruba	7
Australia	8
Austria	9
Azerbaijan	10
Bahamas	11
Bahrain	12
Bangladesh	13
Barbados	14
Belarus	15
Belgium	16
Belize	17
Benin	18
Bermuda	19
Bhutan	20
Bolivia	21
Botswana	22
Brazil	23
Brunei	24
Bulgaria	25
Burundi	26
Cambodia	27
Cameroon	28
Canada	29
Chad	30
Chile	31
China	32
Colombia	33
Comoros	34
Croatia	35
Cuba	36
Curacao	37
Cyprus	38
Denmark	39
Djibouti	40
Dominica	41
Ecuador	42
Egypt	43
Eritrea	44
Estonia	45
Ethiopia	46
Fiji	47
Finland	48
France	49
Gabon	50
Gambia	51
Georgia	52
Germany	53
Ghana	54
Gibraltar	55
Greece	56
Greenland	57
Guatemala	58
Guinea	59
Guyana	60
Haiti	61
Honduras	62
Hungary	63
Iceland	64
India	65
Indonesia	66
Iran	67
Iraq	68
Ireland	69
Israel	70
Italy	71
Jamaica	72
Japan	73
Jordan	74
Kazakhstan	75
Kenya	76
Kiribati	77
Kosovo	78
Kyrgyzstan	79
Laos	80
Latvia	81
Lebanon	82
Lesotho	83
Liberia	84
Libya	85
Liechtenstein	86
Lithuania	87
Luxembourg	88
Macao	89
Macedonia	90
Madagascar	91
Malawi	92
Malaysia	93
Maldives	94
Mali	95
Malta	96
Martinique	97
Mauritania	98
Mauritius	99
Mayotte	100
Mexico	101
Moldova	102
Monaco	103
Mongolia	104
Montenegro	105
Montserrat	106
Morocco	107
Mozambique	108
Myanmar	109
Namibia	110
Nauru	111
Nepal	112
Netherlands	113
Nicaragua	114
Niger	115
Nigeria	116
Niue	117
Norway	118
Oman	119
Pakistan	120
Palau	121
Panama	122
Paraguay	123
Peru	124
Philippines	125
Pitcairn	126
Poland	127
Portugal	128
Qatar	129
Romania	130
Russia	131
Rwanda	132
Samoa	133
Senegal	134
Serbia	135
Seychelles	136
Singapore	137
Slovakia	138
Slovenia	139
Somalia	140
Spain	141
Sudan	142
Suriname	143
Swaziland	144
Sweden	145
Switzerland	146
Syria	147
Taiwan	148
Tajikistan	149
Tanzania	150
Thailand	151
Togo	152
Tunisia	153
Turkey	154
Turkmenistan	155
Tuvalu	156
Uganda	157
Ukraine	158
Uruguay	159
Uzbekistan	160
Venezuela	161
Vietnam	162
Yemen	163
Zambia	164
Zimbabwe	165
USA	166
\.


--
-- Data for Name: death_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.death_certificates (id, issuer, person, issue_date) FROM stdin;
1	435	5	2008-11-19
2	1155	7	2018-12-12
3	152	8	1973-10-05
4	874	9	2013-11-24
5	861	10	1967-09-22
6	148	11	1992-06-27
7	678	12	1989-02-27
8	373	13	1968-03-11
9	98	14	1965-10-13
10	211	15	1980-10-20
11	63	16	1967-02-08
12	1072	17	1968-12-11
13	495	18	1954-06-13
14	111	19	1963-11-16
15	615	20	1967-09-10
16	776	21	1983-10-01
17	1031	22	1969-04-25
18	497	23	1968-08-12
19	1171	24	1957-08-16
20	809	25	1941-03-25
21	402	26	1978-07-26
22	131	27	1986-08-04
23	607	28	1971-07-05
24	1041	29	1957-12-22
25	610	30	1969-03-23
26	676	31	1983-01-09
27	510	32	1961-11-26
28	720	33	1947-08-23
29	65	34	1959-09-04
30	350	35	1940-11-26
31	619	36	1925-01-19
32	286	37	1936-10-06
33	316	38	1924-01-03
34	624	39	1933-06-11
35	700	40	1948-05-12
36	578	41	1929-11-14
37	355	42	1950-03-21
38	1057	43	1942-10-12
39	374	44	1920-10-08
40	332	45	1961-01-13
41	791	46	1959-10-15
42	162	47	1958-11-01
43	1026	48	1929-02-17
44	636	49	1939-02-13
45	951	50	1965-05-24
46	1143	51	1952-05-22
47	1027	52	1960-05-09
48	673	53	1935-06-04
49	240	54	1920-03-02
50	1108	55	1951-07-25
51	202	56	1944-10-08
52	860	57	1939-03-05
53	558	58	1918-09-10
54	780	59	1955-09-17
55	199	60	1928-11-01
56	1171	61	1923-07-15
57	28	62	1924-07-13
58	1003	63	1930-03-12
59	1177	64	1919-03-26
60	293	65	1938-07-15
61	856	66	1933-08-21
62	1208	67	1919-08-19
63	478	68	1935-01-07
64	43	69	1927-07-17
65	713	70	1935-01-28
66	188	71	1908-12-11
67	746	72	1891-03-15
68	1016	73	1910-06-18
69	1144	74	1906-01-28
70	694	75	1894-12-21
71	300	76	1911-03-06
72	953	77	1893-05-09
73	620	78	1921-04-23
74	68	79	1936-12-08
75	569	80	1928-08-06
76	148	81	1928-11-07
77	1158	82	1929-03-08
78	449	83	1894-03-17
79	1170	84	1907-10-15
80	965	85	1900-06-23
81	745	86	1900-08-19
82	787	87	1908-04-17
83	970	88	1904-05-23
84	375	89	1910-05-13
85	892	90	1919-01-19
86	610	91	1938-05-09
87	42	92	1907-02-10
88	374	93	1894-02-06
89	712	94	1897-09-16
90	1187	95	1911-07-09
91	970	96	1937-03-23
92	660	97	1921-01-16
93	443	98	1932-09-03
94	562	99	1929-11-23
95	421	100	1937-01-07
96	1185	101	1940-09-04
97	794	102	1931-12-19
98	497	103	1898-03-19
99	340	104	1932-09-18
100	324	105	1892-07-24
101	667	106	1919-04-04
102	258	107	1897-11-21
103	801	108	1936-01-26
104	160	109	1890-01-01
105	1247	110	1890-01-25
106	642	111	1921-03-18
107	147	112	1906-08-27
108	1059	113	1895-09-14
109	702	114	1936-10-09
110	813	115	1934-05-24
111	1155	116	1893-09-10
112	392	117	1904-04-27
113	1187	118	1918-03-21
114	367	119	1903-09-19
115	34	120	1905-08-26
116	50	121	1896-01-13
117	434	122	1910-08-10
118	1007	123	1899-08-03
119	252	124	1893-09-27
120	726	125	1934-07-11
121	928	126	1935-01-19
122	716	127	1935-02-07
123	297	128	1867-08-27
124	923	129	1910-02-28
125	941	130	1866-07-04
126	218	131	1871-06-20
127	887	132	1908-02-08
128	757	133	1898-04-28
129	183	134	1893-03-02
130	900	135	1866-05-15
131	1165	136	1900-11-10
132	1138	137	1881-12-20
133	66	138	1877-02-05
134	906	139	1912-04-22
135	347	140	1874-03-24
136	1202	141	1915-05-11
137	87	142	1894-09-20
138	991	143	1902-09-26
139	809	144	1901-02-10
140	311	145	1909-04-24
141	851	146	1898-06-15
142	992	147	1901-07-01
143	42	148	1876-01-25
144	545	149	1906-04-01
145	104	150	1867-02-09
146	635	151	1868-09-14
147	129	152	1915-03-20
148	663	153	1872-08-09
149	657	154	1911-11-05
150	912	155	1888-09-03
151	678	156	1875-07-09
152	836	157	1882-06-01
153	387	158	1896-08-28
154	523	159	1872-09-04
155	965	160	1868-01-16
156	1248	161	1879-12-19
157	160	162	1896-10-25
158	375	163	1874-05-28
159	1059	164	1870-03-06
160	762	165	1880-08-16
161	563	166	1904-07-17
162	359	167	1886-11-09
163	791	168	1890-05-21
164	301	169	1908-05-22
165	75	170	1871-09-27
166	236	171	1915-03-14
167	216	172	1905-02-11
168	756	173	1904-12-02
169	1085	174	1873-04-09
170	1206	175	1885-06-14
171	296	176	1914-07-11
172	1103	177	1892-06-03
173	699	178	1911-09-17
174	1165	179	1890-07-26
175	293	180	1875-11-18
176	1019	181	1881-09-26
177	98	182	1899-04-15
178	735	183	1880-12-15
179	910	184	1871-07-23
180	181	185	1883-05-07
181	959	186	1908-09-15
182	776	187	1910-03-09
183	658	188	1903-04-28
184	108	189	1877-01-10
185	44	190	1882-01-16
186	33	191	1873-10-09
187	210	192	1896-01-27
188	132	193	1888-08-11
189	309	194	1883-08-11
190	153	195	1909-07-12
191	115	196	1889-03-26
192	505	197	1879-01-24
193	892	198	1889-04-24
194	39	199	1868-12-01
195	485	200	1901-05-09
196	1048	201	1892-02-19
197	531	202	1895-06-18
198	822	203	1910-04-28
199	1051	204	1890-07-17
200	633	205	1868-08-13
201	243	206	1903-12-12
202	1019	207	1887-02-26
203	627	208	1869-11-06
204	912	209	1865-10-23
205	1208	210	1888-11-17
206	392	211	1879-09-14
207	472	212	1902-03-18
208	1009	213	1892-02-16
209	973	214	1882-03-28
210	1090	215	1870-09-10
211	650	216	1865-10-20
212	304	217	1867-06-14
213	1189	218	1912-03-25
214	558	219	1868-10-05
215	962	220	1892-08-09
216	435	221	1887-10-03
217	1170	222	1893-12-17
218	377	223	1868-05-26
219	1212	224	1884-07-24
220	1225	225	1869-05-06
221	789	226	1880-03-07
222	974	227	1900-12-04
223	1143	228	1875-11-07
224	381	229	1878-08-06
225	87	230	1890-03-09
226	87	231	1893-10-21
227	784	232	1895-07-14
228	717	233	1871-11-22
229	33	234	1886-05-23
230	634	235	1865-08-22
231	1165	236	1908-06-10
232	1179	237	1872-12-27
233	520	238	1886-05-05
234	1189	239	1891-10-25
235	462	240	1871-05-07
236	933	241	1906-03-03
237	531	242	1895-09-07
238	85	243	1901-05-09
239	170	244	1869-12-13
240	588	245	1886-09-12
241	1039	246	1866-09-01
242	1247	247	1872-08-25
243	131	248	1876-09-24
244	642	249	1883-10-01
245	285	250	1905-12-16
246	824	251	1877-08-02
247	97	252	1868-09-21
248	969	253	1879-08-16
249	845	254	1906-01-13
250	436	255	1877-05-03
251	1209	256	1850-08-21
252	355	257	1856-01-22
253	587	258	1850-08-07
254	493	259	1872-12-13
255	526	260	1861-02-02
256	283	261	1887-02-05
257	1016	262	1840-07-20
258	664	263	1860-11-16
259	1021	264	1851-10-22
260	303	265	1846-05-20
261	1185	266	1876-10-06
262	1041	267	1874-07-18
263	138	268	1871-07-14
264	747	269	1844-04-17
265	24	270	1860-12-12
266	147	271	1849-10-15
267	347	272	1848-06-12
268	79	273	1880-05-13
269	633	274	1873-01-16
270	56	275	1862-05-22
271	374	276	1862-02-28
272	651	277	1872-06-22
273	1090	278	1854-01-12
274	276	279	1870-04-17
275	581	280	1883-02-22
276	607	281	1890-02-03
277	478	282	1873-11-22
278	116	283	1860-03-24
279	870	284	1847-04-19
280	357	285	1846-12-13
281	166	286	1841-09-23
282	959	287	1874-08-20
283	298	288	1874-07-09
284	1209	289	1886-03-07
285	1165	290	1883-10-19
286	1067	291	1851-06-18
287	1083	292	1865-07-11
288	801	293	1882-03-05
289	1057	294	1852-07-25
290	927	295	1842-12-25
291	375	296	1882-01-02
292	912	297	1866-08-03
293	421	298	1884-06-04
294	1170	299	1876-11-19
295	840	300	1847-12-08
296	477	301	1858-11-14
297	823	302	1868-12-16
298	692	303	1880-12-09
299	840	304	1843-01-21
300	746	305	1890-09-06
301	1043	306	1872-05-14
302	721	307	1865-05-18
303	532	308	1881-10-14
304	611	309	1875-06-25
305	492	310	1889-02-14
306	965	311	1864-01-18
307	1138	312	1869-11-08
308	1212	313	1846-09-23
309	201	314	1843-07-07
310	27	315	1870-03-09
311	250	316	1890-08-14
312	1203	317	1857-08-08
313	14	318	1840-07-10
314	39	319	1867-09-01
315	429	320	1853-08-11
316	838	321	1840-07-14
317	373	322	1887-05-23
318	54	323	1859-04-08
319	147	324	1851-03-15
320	518	325	1866-11-09
321	638	326	1840-09-23
322	85	327	1840-05-13
323	648	328	1845-04-24
324	966	329	1861-07-13
325	694	330	1860-06-28
326	144	331	1880-06-01
327	944	332	1889-08-01
328	200	333	1860-05-19
329	1033	334	1873-03-15
330	72	335	1850-02-12
331	361	336	1845-11-15
332	713	337	1876-12-21
333	976	338	1872-04-08
334	1046	339	1844-03-17
335	794	340	1866-07-26
336	360	341	1878-10-20
337	780	342	1856-04-24
338	198	343	1840-12-19
339	465	344	1858-02-12
340	428	345	1875-05-06
341	1215	346	1888-06-11
342	693	347	1890-08-27
343	1206	348	1889-04-09
344	823	349	1862-08-01
345	781	350	1856-12-25
346	279	351	1851-02-25
347	368	352	1867-12-01
348	518	353	1843-08-10
349	720	354	1885-07-23
350	783	355	1883-06-04
351	789	356	1868-07-25
352	368	357	1875-07-26
353	268	358	1855-07-28
354	165	359	1883-10-14
355	713	360	1851-08-12
356	925	361	1879-03-05
357	1247	362	1846-02-18
358	145	363	1875-02-22
359	1015	364	1875-04-18
360	984	365	1857-12-22
361	430	366	1883-11-14
362	441	367	1868-01-08
363	418	368	1866-10-02
364	800	369	1850-03-06
365	915	370	1854-11-14
366	1144	371	1879-09-18
367	252	372	1870-03-01
368	1002	373	1866-09-06
369	143	374	1879-11-06
370	927	375	1856-09-01
371	136	376	1856-01-07
372	1096	377	1873-03-17
373	549	378	1871-03-19
374	442	379	1883-09-15
375	191	380	1870-05-13
376	477	381	1880-03-02
377	1219	382	1872-04-14
378	1006	383	1846-10-21
379	382	384	1886-08-09
380	664	385	1880-04-22
381	229	386	1889-05-27
382	361	387	1866-02-21
383	939	388	1876-06-11
384	276	389	1889-12-13
385	1049	390	1842-12-03
386	452	391	1849-02-01
387	887	392	1854-08-16
388	972	393	1874-05-12
389	977	394	1874-02-18
390	201	395	1841-03-23
391	466	396	1856-03-12
392	133	397	1866-01-12
393	888	398	1848-12-20
394	644	399	1890-05-05
395	1041	400	1845-04-14
396	397	401	1887-02-17
397	510	402	1855-11-08
398	418	403	1869-04-16
399	1225	404	1866-12-01
400	201	405	1883-09-20
401	1213	406	1841-03-01
402	1043	407	1870-05-09
403	703	408	1854-03-01
404	1141	409	1875-11-26
405	727	410	1869-08-04
406	398	411	1864-12-04
407	1221	412	1884-04-08
408	53	413	1882-08-02
409	530	414	1869-09-04
410	716	415	1857-07-17
411	811	416	1862-03-19
412	390	417	1845-03-20
413	561	418	1868-01-16
414	1180	419	1871-05-01
415	987	420	1847-08-24
416	1072	421	1887-10-04
417	704	422	1877-05-07
418	234	423	1885-10-16
419	974	424	1872-06-04
420	1153	425	1854-11-02
421	1140	426	1863-04-04
422	678	427	1867-09-19
423	47	428	1880-01-20
424	1078	429	1856-07-16
425	310	430	1853-05-13
426	692	431	1879-10-02
427	1239	432	1888-09-03
428	236	433	1881-02-09
429	591	434	1866-07-21
430	966	435	1883-05-17
431	213	436	1863-06-24
432	922	437	1848-09-22
433	305	438	1877-03-04
434	279	439	1885-07-07
435	931	440	1842-10-13
436	684	441	1868-07-18
437	926	442	1890-06-07
438	11	443	1890-05-28
439	1166	444	1843-06-01
440	39	445	1859-07-20
441	553	446	1877-08-17
442	526	447	1847-08-10
443	153	448	1847-08-13
444	1239	449	1848-04-02
445	578	450	1856-11-10
446	814	451	1847-11-05
447	1247	452	1867-08-21
448	787	453	1864-07-23
449	106	454	1865-11-12
450	242	455	1880-08-18
451	382	456	1848-06-10
452	1007	457	1860-12-26
453	700	458	1848-09-13
454	217	459	1853-03-10
455	1176	460	1886-07-10
456	231	461	1855-07-16
457	402	462	1852-08-02
458	1034	463	1865-02-24
459	1006	464	1862-12-01
460	445	465	1864-10-27
461	1167	466	1865-11-16
462	816	467	1880-01-01
463	893	468	1885-12-08
464	88	469	1871-11-24
465	155	470	1857-03-11
466	529	471	1842-12-04
467	783	472	1883-01-22
468	492	473	1842-02-17
469	1021	474	1869-12-13
470	1246	475	1873-12-05
471	767	476	1878-12-23
472	817	477	1852-11-16
473	496	478	1865-09-03
474	851	479	1882-03-18
475	836	480	1847-04-01
476	870	481	1841-10-13
477	702	482	1878-03-20
478	548	483	1847-03-08
479	606	484	1885-10-23
480	243	485	1880-10-03
481	1205	486	1868-01-17
482	1215	487	1867-04-21
483	961	488	1862-09-13
484	1020	489	1877-06-06
485	621	490	1873-03-08
486	833	491	1886-09-25
487	531	492	1871-08-23
488	145	493	1881-08-14
489	703	494	1885-05-28
490	727	495	1842-04-25
491	466	496	1850-11-21
492	1041	497	1854-10-15
493	98	498	1860-10-01
494	541	499	1854-01-10
495	1047	500	1853-05-17
\.


--
-- Data for Name: divorce_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorce_certificates (id, divorce_id, issue_date, issuer) FROM stdin;
1	1	1966-04-10	701
2	2	1951-12-14	996
3	3	1954-10-20	496
4	4	1919-10-23	816
5	5	1916-05-11	845
6	6	1917-11-11	37
7	7	1925-02-19	811
8	8	1927-06-23	477
9	9	1891-11-27	276
10	10	1900-02-19	174
11	11	1901-02-28	1122
12	12	1904-06-16	639
13	13	1897-07-07	631
14	14	1889-09-17	649
15	15	1886-04-03	272
16	16	1898-02-10	1193
17	17	1886-04-07	289
18	18	1887-07-08	122
19	19	1905-11-04	1157
20	20	1889-11-05	370
21	21	1901-05-28	348
22	22	1875-11-27	156
23	23	1873-03-08	601
24	24	1862-05-10	831
25	25	1879-02-09	66
26	26	1864-05-27	549
27	27	1861-08-11	670
28	28	1875-01-18	1036
29	29	1862-04-13	434
30	30	1874-12-20	151
31	31	1877-12-11	513
32	32	1867-01-10	35
33	33	1866-07-22	139
34	34	1861-12-09	600
35	35	1871-10-20	225
36	36	1873-08-22	225
37	37	1868-12-25	918
38	38	1866-02-08	266
39	39	1873-03-06	708
40	40	1860-09-13	1082
41	41	1872-06-25	1160
42	42	1881-03-20	704
43	43	1857-04-08	1051
44	44	1836-02-08	101
45	45	1849-09-16	663
46	46	1840-05-02	193
47	47	1857-03-21	493
48	48	1848-01-18	1012
49	49	1845-05-16	549
50	50	1852-12-05	47
51	51	1844-04-09	109
52	52	1849-06-15	306
53	53	1856-12-26	846
54	54	1850-03-12	465
55	55	1851-07-01	893
56	56	1845-12-26	1127
57	57	1840-09-21	156
58	58	1847-08-04	10
59	59	1841-03-18	604
60	60	1853-04-14	398
61	61	1846-07-05	1226
62	62	1843-12-21	1094
63	63	1833-09-24	1213
64	64	1852-11-08	13
65	65	1847-10-19	1095
66	66	1848-09-05	174
67	67	1837-02-16	618
68	68	1851-04-07	446
69	69	1844-07-16	56
70	70	1846-02-18	132
71	71	1849-03-01	1009
72	72	1835-02-12	699
73	73	1844-01-03	619
74	74	1850-04-23	430
75	75	1843-01-26	907
76	76	1843-10-04	1206
77	77	1849-05-02	962
78	78	1834-04-17	164
79	79	1847-11-23	97
80	80	1858-03-03	823
81	81	1837-11-23	670
82	82	1843-08-18	1244
83	83	1845-04-26	466
84	84	1852-12-02	811
85	85	1834-09-28	113
86	86	1851-06-12	329
87	87	1840-07-21	10
88	88	1839-04-11	673
89	89	1849-05-12	361
90	90	1852-02-15	117
91	91	1856-03-12	753
92	92	1837-05-28	496
93	93	1812-05-20	474
94	94	1822-07-13	459
95	95	1815-06-24	653
96	96	1818-12-07	519
97	97	1817-12-08	832
98	98	1829-03-05	730
99	99	1825-04-12	422
100	100	1820-02-20	818
101	101	1829-08-25	792
102	102	1822-07-27	1041
103	103	1830-01-25	464
104	104	1819-04-09	1124
105	105	1825-06-18	135
106	106	1817-09-11	850
107	107	1824-12-28	112
108	108	1817-06-25	908
109	109	1823-09-19	510
110	110	1818-11-22	643
111	111	1821-02-10	687
112	112	1818-05-16	184
113	113	1829-05-12	325
114	114	1814-01-06	211
115	115	1823-09-06	472
116	116	1812-07-10	665
117	117	1824-07-04	479
118	118	1819-03-14	927
119	119	1818-08-26	996
120	120	1817-11-10	445
121	121	1811-05-14	164
122	122	1817-04-20	37
123	123	1813-10-25	416
124	124	1821-06-23	553
125	125	1819-01-28	927
126	126	1814-05-10	134
127	127	1829-11-26	127
128	128	1820-06-01	269
129	129	1826-02-28	160
130	130	1824-04-01	1023
131	131	1833-02-28	627
132	132	1807-03-06	538
133	133	1829-03-09	845
134	134	1821-10-06	219
135	135	1821-12-04	410
136	136	1827-04-17	447
137	137	1811-03-08	731
138	138	1821-11-02	381
139	139	1820-06-07	883
140	140	1822-04-25	701
141	141	1825-12-17	1046
142	142	1820-08-10	138
143	143	1826-10-04	938
144	144	1826-04-25	204
145	145	1817-10-09	720
146	146	1819-01-05	960
147	147	1814-04-01	63
148	148	1831-06-06	339
149	149	1821-04-24	601
150	150	1812-01-18	116
151	151	1817-04-18	1166
152	152	1821-08-28	778
153	153	1828-04-26	534
154	154	1817-04-03	962
155	155	1822-03-23	785
156	156	1826-05-13	349
157	157	1821-11-21	167
158	158	1816-06-12	983
159	159	1813-12-18	707
160	160	1831-04-19	490
161	161	1826-09-22	135
162	162	1828-12-16	1250
163	163	1827-09-27	469
164	164	1824-12-22	676
165	165	1812-06-25	1246
166	166	1827-01-01	679
167	167	1828-04-17	679
168	168	1817-10-25	1075
169	169	1827-11-11	785
170	170	1827-04-04	33
171	171	1821-10-20	268
172	172	1824-03-21	1243
173	173	1827-10-24	293
174	174	1827-02-02	409
175	175	1816-11-05	599
176	176	1822-07-20	883
177	177	1826-09-12	1119
178	178	1824-12-25	714
179	179	1822-08-11	639
\.


--
-- Data for Name: divorces; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorces (id, marriage_id, divorce_date) FROM stdin;
1	2	1966-04-10
2	5	1951-12-14
3	6	1954-10-20
4	8	1919-10-23
5	10	1916-05-11
6	12	1917-11-11
7	13	1925-02-19
8	15	1927-06-23
9	16	1891-11-27
10	17	1900-02-19
11	18	1901-02-28
12	19	1904-06-16
13	20	1897-07-07
14	22	1889-09-17
15	24	1886-04-03
16	25	1898-02-10
17	26	1886-04-07
18	27	1887-07-08
19	28	1905-11-04
20	29	1889-11-05
21	30	1901-05-28
22	32	1875-11-27
23	34	1873-03-08
24	35	1862-05-10
25	36	1879-02-09
26	37	1864-05-27
27	40	1861-08-11
28	41	1875-01-18
29	42	1862-04-13
30	45	1874-12-20
31	46	1877-12-11
32	48	1867-01-10
33	49	1866-07-22
34	50	1861-12-09
35	51	1871-10-20
36	52	1873-08-22
37	54	1868-12-25
38	55	1866-02-08
39	57	1873-03-06
40	58	1860-09-13
41	59	1872-06-25
42	63	1881-03-20
43	64	1857-04-08
44	65	1836-02-08
45	67	1849-09-16
46	69	1840-05-02
47	70	1857-03-21
48	71	1848-01-18
49	72	1845-05-16
50	73	1852-12-05
51	75	1844-04-09
52	76	1849-06-15
53	77	1856-12-26
54	80	1850-03-12
55	81	1851-07-01
56	82	1845-12-26
57	84	1840-09-21
58	85	1847-08-04
59	86	1841-03-18
60	87	1853-04-14
61	88	1846-07-05
62	89	1843-12-21
63	92	1833-09-24
64	93	1852-11-08
65	94	1847-10-19
66	95	1848-09-05
67	99	1837-02-16
68	100	1851-04-07
69	102	1844-07-16
70	103	1846-02-18
71	104	1849-03-01
72	105	1835-02-12
73	106	1844-01-03
74	107	1850-04-23
75	108	1843-01-26
76	109	1843-10-04
77	110	1849-05-02
78	111	1834-04-17
79	112	1847-11-23
80	113	1858-03-03
81	114	1837-11-23
82	116	1843-08-18
83	117	1845-04-26
84	119	1852-12-02
85	120	1834-09-28
86	121	1851-06-12
87	122	1840-07-21
88	123	1839-04-11
89	124	1849-05-12
90	125	1852-02-15
91	126	1856-03-12
92	127	1837-05-28
93	128	1812-05-20
94	129	1822-07-13
95	130	1815-06-24
96	133	1818-12-07
97	134	1817-12-08
98	135	1829-03-05
99	136	1825-04-12
100	137	1820-02-20
101	138	1829-08-25
102	139	1822-07-27
103	140	1830-01-25
104	141	1819-04-09
105	142	1825-06-18
106	144	1817-09-11
107	147	1824-12-28
108	148	1817-06-25
109	149	1823-09-19
110	150	1818-11-22
111	151	1821-02-10
112	152	1818-05-16
113	153	1829-05-12
114	155	1814-01-06
115	156	1823-09-06
116	158	1812-07-10
117	161	1824-07-04
118	162	1819-03-14
119	165	1818-08-26
120	166	1817-11-10
121	169	1811-05-14
122	170	1817-04-20
123	173	1813-10-25
124	175	1821-06-23
125	176	1819-01-28
126	177	1814-05-10
127	178	1829-11-26
128	179	1820-06-01
129	180	1826-02-28
130	182	1824-04-01
131	183	1833-02-28
132	184	1807-03-06
133	185	1829-03-09
134	186	1821-10-06
135	187	1821-12-04
136	188	1827-04-17
137	189	1811-03-08
138	192	1821-11-02
139	193	1820-06-07
140	194	1822-04-25
141	195	1825-12-17
142	196	1820-08-10
143	198	1826-10-04
144	199	1826-04-25
145	200	1817-10-09
146	202	1819-01-05
147	203	1814-04-01
148	205	1831-06-06
149	206	1821-04-24
150	207	1812-01-18
151	208	1817-04-18
152	210	1821-08-28
153	211	1828-04-26
154	213	1817-04-03
155	215	1822-03-23
156	216	1826-05-13
157	217	1821-11-21
158	218	1816-06-12
159	220	1813-12-18
160	221	1831-04-19
161	222	1826-09-22
162	223	1828-12-16
163	225	1827-09-27
164	226	1824-12-22
165	231	1812-06-25
166	233	1827-01-01
167	235	1828-04-17
168	236	1817-10-25
169	237	1827-11-11
170	239	1827-04-04
171	240	1821-10-20
172	241	1824-03-21
173	242	1827-10-24
174	243	1827-02-02
175	244	1816-11-05
176	245	1822-07-20
177	247	1826-09-12
178	248	1824-12-25
179	249	1822-08-11
\.


--
-- Data for Name: document_types; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.document_types (id, document) FROM stdin;
4	Birth certificate
5	Death certificate
6	Divorce certificate
7	Driver license
9	Educational certificate
1	International passport
2	Marriage certificate
8	Passport
10	Pet passport
3	Visa
\.


--
-- Data for Name: drivers_licences; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.drivers_licences (id, type, person, issuer, issue_date, expiration_date) FROM stdin;
1	C	289	113	1865-05-21	1875-05-21
2	C1	102	619	1864-05-28	1874-05-28
3	B1	232	125	1991-09-16	2001-09-16
4	C1	285	315	1884-09-26	1894-09-26
5	A	15	710	2013-09-26	2023-09-26
6	D	276	208	1844-08-19	1854-08-19
7	D1	387	355	1873-09-23	1883-09-23
8	B1	246	43	2023-12-07	2033-12-07
9	C	443	459	1815-12-10	1825-12-10
10	D1	22	89	1972-06-09	1982-06-09
11	D1	386	850	1922-11-03	1932-11-03
12	C	235	679	1859-12-03	1869-12-03
13	C	314	1239	1961-01-18	1971-01-18
14	D1	444	592	1951-11-21	1961-11-21
15	D1	125	1001	1880-05-12	1890-05-12
16	D1	139	96	1981-01-10	1991-01-10
17	D	104	173	1931-09-21	1941-09-21
18	C1	307	436	1841-02-13	1851-02-13
19	D1	366	1161	1860-11-05	1870-11-05
20	C1	274	16	1837-05-19	1847-05-19
21	B1	275	655	1880-07-14	1890-07-14
22	D	274	591	1893-12-28	1903-12-28
23	D	273	1026	2013-07-01	2023-07-01
24	A	267	1138	2001-11-21	2011-11-21
25	D1	232	292	1981-11-09	1991-11-09
26	C	331	441	1846-08-10	1856-08-10
27	A	371	1024	1904-02-18	1914-02-18
28	C	69	781	1910-03-26	1920-03-26
29	C	404	902	1876-01-06	1886-01-06
30	D	221	462	1973-02-05	1983-02-05
31	C	342	841	1826-03-27	1836-03-27
32	C1	96	877	1908-05-26	1918-05-26
33	B1	394	745	1999-06-16	2009-06-16
34	B1	4	227	1969-11-23	1979-11-23
35	C	46	1097	2009-06-08	2019-06-08
36	B1	30	687	2021-12-24	2031-12-24
37	D	438	925	1899-08-24	1909-08-24
38	A	454	724	1851-09-09	1861-09-09
39	B1	68	333	1968-09-01	1978-09-01
40	D	486	15	1897-08-05	1907-08-05
41	D1	206	1218	1906-02-13	1916-02-13
42	C	284	954	1925-07-21	1935-07-21
43	A	101	311	2005-10-26	2015-10-26
44	D	423	101	1844-11-22	1854-11-22
45	C1	391	206	1947-11-14	1957-11-14
46	A	94	866	1945-03-08	1955-03-08
47	C	30	43	1983-08-12	1993-08-12
48	B1	176	1078	1838-12-02	1848-12-02
49	B1	496	1172	1935-07-19	1945-07-19
50	D1	421	844	1940-01-14	1950-01-14
51	D1	281	355	2003-09-13	2013-09-13
52	C1	406	1171	1903-10-01	1913-10-01
53	D	119	704	1859-08-12	1869-08-12
54	D	225	345	1940-10-08	1950-10-08
55	B1	237	332	2007-10-17	2017-10-17
56	C1	435	53	2004-10-23	2014-10-23
57	A	437	271	1883-11-13	1893-11-13
58	C	257	490	1977-08-26	1987-08-26
59	D1	125	946	1952-12-13	1962-12-13
60	D	424	584	1906-08-06	1916-08-06
61	D1	418	703	1823-09-07	1833-09-07
62	C	342	351	1817-09-06	1827-09-06
63	A	497	34	1828-02-22	1838-02-22
64	B1	313	771	1970-12-08	1980-12-08
65	D1	294	117	1963-11-23	1973-11-23
66	C	144	133	1965-06-14	1975-06-14
67	C1	322	766	1921-05-04	1931-05-04
68	A	359	351	1979-10-13	1989-10-13
69	C	457	1210	1999-01-24	2009-01-24
70	C	461	599	1851-09-13	1861-09-13
71	D	376	818	1844-08-18	1854-08-18
72	C	212	1031	1884-09-18	1894-09-18
73	C	391	1068	1992-01-24	2002-01-24
74	C	418	550	1990-08-10	2000-08-10
75	D	140	872	1952-11-14	1962-11-14
76	C	360	650	1976-08-18	1986-08-18
77	A	495	414	1900-07-01	1910-07-01
78	A	425	350	1923-01-26	1933-01-26
79	C1	27	187	1916-01-25	1926-01-25
80	D	476	677	1957-02-26	1967-02-26
81	D	448	446	2016-05-25	2026-05-25
82	D1	311	251	2013-07-02	2023-07-02
83	A	123	1130	1956-07-04	1966-07-04
84	D1	225	1140	1942-04-23	1952-04-23
85	D1	60	332	1947-07-23	1957-07-23
86	A	153	905	2003-08-14	2013-08-14
87	D1	405	773	1818-09-04	1828-09-04
88	C1	312	45	1816-10-02	1826-10-02
89	C	365	404	1925-05-01	1935-05-01
90	A	107	941	1932-03-07	1942-03-07
91	A	202	420	1894-05-19	1904-05-19
92	C	351	1128	1932-11-01	1942-11-01
93	C1	186	38	1912-03-02	1922-03-02
94	A	137	1022	1858-09-11	1868-09-11
95	B1	456	644	2014-06-26	2024-06-26
96	C	427	1082	1840-05-11	1850-05-11
97	C	317	300	1949-11-11	1959-11-11
98	D1	404	116	1912-03-20	1922-03-20
99	C1	358	849	1914-10-08	1924-10-08
100	B1	121	903	1978-01-11	1988-01-11
101	B1	230	686	1858-09-07	1868-09-07
102	C1	79	795	1884-08-01	1894-08-01
103	A	42	697	1887-07-19	1897-07-19
104	A	122	649	1983-03-11	1993-03-11
105	C1	283	140	1810-03-19	1820-03-19
106	B1	12	671	1939-02-01	1949-02-01
107	B1	94	481	2001-10-17	2011-10-17
108	D	228	1035	1950-03-24	1960-03-24
109	A	28	962	1939-07-04	1949-07-04
110	C	419	1165	1810-02-02	1820-02-02
111	B1	386	431	1859-01-18	1869-01-18
112	C	214	1166	1925-09-22	1935-09-22
113	C1	145	675	1991-07-19	2001-07-19
114	D	100	1246	1930-02-04	1940-02-04
115	C	288	534	1979-10-22	1989-10-22
116	B1	150	1186	1970-01-05	1980-01-05
117	A	365	108	1875-07-14	1885-07-14
118	D	248	1119	1909-12-15	1919-12-15
119	B1	403	890	2002-02-13	2012-02-13
120	D1	471	777	2000-08-24	2010-08-24
121	B1	161	1056	1921-10-28	1931-10-28
122	D1	433	1249	1910-05-15	1920-05-15
123	C1	464	572	1862-02-15	1872-02-15
124	A	240	23	1889-01-26	1899-01-26
125	D	282	1228	1889-05-24	1899-05-24
126	A	311	650	1932-02-27	1942-02-27
127	D	482	720	1879-06-12	1889-06-12
128	D1	307	45	1843-01-18	1853-01-18
129	C1	205	1030	1989-12-28	1999-12-28
130	D	100	320	1882-02-07	1892-02-07
131	A	262	625	1909-11-28	1919-11-28
132	D	403	657	1819-11-04	1829-11-04
133	C	299	1001	1933-03-28	1943-03-28
134	D	150	915	1898-12-12	1908-12-12
135	B1	99	46	2016-07-15	2026-07-15
136	A	111	353	2009-11-13	2019-11-13
137	C1	296	431	1818-10-20	1828-10-20
138	A	499	459	1859-04-16	1869-04-16
139	C1	374	902	1958-06-27	1968-06-27
140	C1	204	971	1851-10-05	1861-10-05
141	A	93	585	1987-08-21	1997-08-21
142	B1	290	398	2013-04-07	2023-04-07
143	B1	50	231	1985-03-19	1995-03-19
144	B1	368	886	1980-11-10	1990-11-10
145	B1	325	851	1910-08-23	1920-08-23
146	C	51	1200	1909-06-09	1919-06-09
147	D1	465	1185	1816-08-06	1826-08-06
148	D1	383	734	1877-07-12	1887-07-12
149	D	145	817	2014-01-12	2024-01-12
150	D1	325	810	1934-02-26	1944-02-26
151	C1	167	1192	1997-03-24	2007-03-24
152	B1	85	969	1882-11-28	1892-11-28
153	C	447	798	1848-03-20	1858-03-20
154	C	435	720	1877-04-21	1887-04-21
155	A	42	523	1898-07-23	1908-07-23
156	B1	328	1149	1985-12-09	1995-12-09
157	C1	93	756	1998-11-17	2008-11-17
158	C1	164	1056	1920-01-10	1930-01-10
159	D1	468	721	1909-11-12	1919-11-12
160	C1	86	483	1895-05-10	1905-05-10
161	D	435	644	1846-08-18	1856-08-18
162	C	183	845	1954-06-04	1964-06-04
163	A	109	714	1884-02-14	1894-02-14
164	D1	92	679	1977-12-09	1987-12-09
165	A	168	401	1973-12-21	1983-12-21
166	C	292	232	1842-06-28	1852-06-28
167	C	276	205	1970-09-17	1980-09-17
168	D	295	39	1971-01-04	1981-01-04
169	C	265	389	1966-12-28	1976-12-28
170	D1	75	1026	2009-09-28	2019-09-28
171	D1	412	187	2003-12-02	2013-12-02
172	C1	455	1019	1890-03-03	1900-03-03
173	A	14	225	1964-11-17	1974-11-17
174	C	404	714	1944-10-26	1954-10-26
175	D1	385	1063	1884-09-15	1894-09-15
176	C1	72	259	1909-11-05	1919-11-05
177	D1	442	31	1867-06-23	1877-06-23
178	B1	175	404	1952-09-05	1962-09-05
179	A	5	336	2017-01-06	2027-01-06
180	C1	75	872	1965-12-02	1975-12-02
181	A	51	891	1914-05-23	1924-05-23
182	C1	197	333	1949-01-19	1959-01-19
183	C1	409	132	1962-12-14	1972-12-14
184	D1	457	1194	1903-10-15	1913-10-15
185	D	213	392	1995-01-24	2005-01-24
186	B1	307	456	1870-12-13	1880-12-13
187	C	369	530	1903-01-24	1913-01-24
188	C1	6	295	2003-12-17	2013-12-17
189	D1	123	402	1950-03-09	1960-03-09
190	D	226	63	1924-09-06	1934-09-06
191	C1	125	1162	2005-05-26	2015-05-26
192	C1	181	791	1955-07-23	1965-07-23
193	A	364	790	1896-09-10	1906-09-10
194	D1	94	821	1917-09-12	1927-09-12
195	D	241	89	1902-12-24	1912-12-24
196	D1	80	876	1913-04-04	1923-04-04
197	A	16	69	1991-08-26	2001-08-26
198	A	421	655	1890-07-12	1900-07-12
199	A	149	1042	1984-12-04	1994-12-04
200	C	158	649	1935-12-18	1945-12-18
\.


--
-- Data for Name: educational_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificates (id, issuer, holder, issue_date, kind) FROM stdin;
1	21	1	2004-02-06	1
2	38	1	2005-12-23	3
3	4	1	2005-11-24	6
4	22	2	1981-12-09	1
5	29	2	1982-10-10	2
6	18	2	1981-06-16	5
7	27	3	1980-07-06	1
8	21	3	1981-02-25	2
9	14	3	1981-05-26	5
10	25	5	1957-12-01	1
11	28	5	1955-04-03	2
12	25	6	1957-07-25	1
13	35	6	1955-05-06	3
14	11	6	1957-04-27	6
15	28	8	1932-03-18	1
16	26	8	1929-11-20	2
17	22	9	1930-02-17	1
18	30	10	1932-09-18	1
19	30	10	1929-06-22	2
20	2	10	1932-10-17	4
21	24	12	1931-01-05	1
22	21	12	1929-04-13	2
23	30	13	1930-11-19	1
24	34	13	1930-06-01	3
25	14	13	1932-09-07	6
26	30	14	1930-08-06	1
27	21	14	1929-07-05	2
28	14	14	1931-05-10	4
29	28	15	1929-11-20	1
30	26	15	1930-06-17	2
31	23	16	1905-12-01	1
32	32	16	1906-07-04	3
33	3	16	1904-12-04	7
34	21	18	1906-01-11	1
35	23	19	1906-05-04	1
36	29	19	1907-06-23	2
37	18	19	1906-12-04	4
38	29	20	1907-06-12	1
39	27	21	1907-02-08	1
40	39	21	1907-07-14	3
41	22	22	1907-03-01	1
42	36	22	1906-08-15	3
43	28	23	1907-03-25	1
44	24	24	1907-04-12	1
45	22	25	1904-03-11	1
46	27	27	1905-08-14	1
47	27	29	1907-06-02	1
48	26	30	1906-08-23	1
49	21	31	1907-11-28	1
50	22	31	1906-03-26	2
51	23	33	1880-06-19	1
52	35	33	1880-02-03	3
53	25	35	1879-02-05	1
54	31	35	1881-12-03	3
55	4	35	1881-01-21	7
56	28	36	1879-01-19	1
57	26	36	1881-11-17	2
58	23	37	1881-05-06	1
59	26	37	1879-02-19	2
60	26	39	1880-11-06	1
61	30	39	1880-05-14	2
62	23	42	1879-03-25	1
63	22	43	1880-11-23	1
64	39	43	1879-05-05	3
65	27	44	1881-08-06	1
66	22	45	1881-10-19	1
67	29	45	1879-10-12	2
68	21	46	1881-12-13	1
69	34	46	1881-05-07	3
70	24	47	1880-10-07	1
71	25	49	1880-12-01	1
72	29	50	1880-05-09	1
73	39	50	1881-03-08	3
74	29	51	1882-03-22	1
75	21	51	1881-12-02	2
76	27	52	1882-06-05	1
77	24	53	1882-07-13	1
78	31	53	1879-05-16	3
79	23	54	1881-06-03	1
80	26	54	1880-09-01	2
81	28	55	1880-03-07	1
82	23	59	1882-12-24	1
83	32	59	1882-11-20	3
84	14	59	1880-12-06	7
85	24	60	1881-01-07	1
86	30	60	1880-07-08	2
87	29	62	1880-07-27	1
88	29	63	1879-05-01	1
89	37	63	1879-08-11	3
90	14	63	1879-03-13	7
91	23	64	1854-03-07	1
92	23	65	1856-03-09	1
93	31	65	1857-01-02	3
94	30	66	1854-03-03	1
95	23	68	1857-10-23	1
96	29	68	1855-11-19	2
97	4	68	1855-03-07	4
98	30	70	1856-03-18	1
99	27	70	1854-04-14	2
100	24	71	1855-02-16	1
101	37	71	1856-03-05	3
102	25	72	1854-05-09	1
103	22	72	1856-02-02	2
104	2	72	1857-01-21	5
105	25	73	1855-09-22	1
106	26	73	1857-09-03	2
107	8	73	1854-06-04	4
108	26	74	1856-08-05	1
109	28	74	1857-06-24	2
110	13	74	1856-02-02	4
111	26	75	1856-02-05	1
112	23	77	1856-07-09	1
113	35	77	1854-02-17	3
114	21	78	1855-10-03	1
115	21	80	1854-02-05	1
116	23	81	1856-08-18	1
117	23	82	1856-09-09	1
118	28	83	1856-06-16	1
119	26	85	1854-09-10	1
120	24	85	1856-12-19	2
121	10	85	1857-06-13	5
122	23	86	1855-04-21	1
123	37	86	1854-07-20	3
124	27	88	1857-11-26	1
125	40	88	1856-11-28	3
126	21	89	1854-02-25	1
127	35	89	1855-12-26	3
128	25	90	1854-08-03	1
129	22	91	1855-06-03	1
130	21	92	1854-10-25	1
131	21	94	1856-08-13	1
132	34	94	1857-03-17	3
133	30	95	1855-11-24	1
134	25	96	1856-07-13	1
135	39	96	1857-01-12	3
136	25	97	1855-09-01	1
137	24	99	1854-05-03	1
138	29	100	1854-11-04	1
139	21	100	1856-11-22	2
140	10	100	1857-05-03	5
141	30	101	1857-01-06	1
142	22	102	1854-05-23	1
143	30	102	1855-06-13	2
144	1	102	1856-10-20	5
145	21	104	1856-06-19	1
146	40	104	1854-08-15	3
147	15	104	1855-05-07	6
148	25	105	1857-02-15	1
149	37	105	1855-02-19	3
150	25	106	1854-11-22	1
151	38	106	1855-07-27	3
152	4	106	1856-08-20	6
153	27	107	1856-09-15	1
154	38	107	1856-09-16	3
155	2	107	1854-01-07	6
156	29	109	1857-06-09	1
157	23	109	1854-01-14	2
158	16	109	1854-05-08	4
159	28	110	1856-10-05	1
160	27	110	1855-05-05	2
161	5	110	1857-01-25	5
162	30	111	1857-03-10	1
163	40	111	1854-07-13	3
164	26	112	1854-02-27	1
165	25	112	1857-10-22	2
166	22	114	1856-05-15	1
167	29	114	1855-06-16	2
168	29	117	1857-10-22	1
169	21	117	1856-04-28	2
170	18	117	1855-10-02	4
171	23	118	1854-09-15	1
172	32	118	1856-11-24	3
173	19	118	1856-02-18	6
174	24	119	1856-05-23	1
175	23	121	1854-10-09	1
176	30	122	1857-05-22	1
177	25	122	1856-07-20	2
178	23	124	1854-05-23	1
179	27	125	1857-06-16	1
180	31	125	1857-03-02	3
181	22	126	1854-11-22	1
182	37	126	1854-02-22	3
183	16	126	1855-08-24	7
184	22	127	1854-02-17	1
185	26	128	1832-03-13	1
186	30	128	1829-09-20	2
187	24	130	1832-10-05	1
188	24	130	1829-02-19	2
189	18	130	1829-11-17	4
190	29	132	1830-06-02	1
191	26	134	1831-06-20	1
192	23	135	1830-04-08	1
193	22	138	1829-03-13	1
194	25	138	1832-07-19	2
195	20	138	1830-01-21	5
196	27	140	1830-05-24	1
197	30	141	1832-01-04	1
198	21	141	1832-05-26	2
199	21	142	1831-11-06	1
200	29	143	1830-07-21	1
201	31	143	1831-03-24	3
202	23	144	1830-01-12	1
203	24	146	1829-04-20	1
204	30	147	1830-08-07	1
205	29	149	1831-10-28	1
206	26	149	1829-11-12	2
207	5	149	1830-04-04	4
208	22	150	1829-01-25	1
209	33	150	1829-04-23	3
210	25	151	1831-04-19	1
211	29	151	1832-05-02	2
212	23	152	1831-02-13	1
213	32	152	1829-08-12	3
214	25	154	1829-07-23	1
215	22	156	1832-05-16	1
216	23	157	1829-09-21	1
217	25	157	1831-06-17	2
218	26	158	1830-09-05	1
219	28	158	1832-12-11	2
220	14	158	1832-05-24	4
221	29	159	1829-08-20	1
222	23	159	1832-01-26	2
223	26	160	1830-11-22	1
224	21	162	1829-06-21	1
225	28	162	1830-05-10	2
226	13	162	1831-10-04	5
227	26	163	1832-08-04	1
228	40	163	1831-03-18	3
229	8	163	1831-06-21	6
230	23	164	1831-12-11	1
231	33	164	1832-01-07	3
232	13	164	1831-05-20	6
233	21	166	1832-05-07	1
234	28	166	1830-05-23	2
235	29	167	1832-10-11	1
236	32	167	1829-07-18	3
237	17	167	1832-12-01	7
238	21	168	1830-08-11	1
239	23	169	1831-08-19	1
240	25	169	1831-07-02	2
241	16	169	1832-02-19	5
242	22	170	1832-10-27	1
243	40	170	1832-06-03	3
244	25	171	1830-06-04	1
245	24	171	1830-02-05	2
246	30	172	1829-02-21	1
247	31	172	1832-11-06	3
248	21	173	1831-08-11	1
249	40	173	1831-03-18	3
250	10	173	1832-02-07	6
251	24	174	1829-03-13	1
252	30	174	1829-11-06	2
253	11	174	1830-02-01	4
254	22	175	1829-09-06	1
255	29	175	1829-09-02	2
256	21	176	1832-04-04	1
257	24	176	1829-04-04	2
258	2	176	1831-05-07	5
259	29	177	1829-02-18	1
260	30	178	1830-05-22	1
261	29	178	1831-10-24	2
262	7	178	1832-05-01	4
263	24	180	1831-10-21	1
264	21	180	1831-07-01	2
265	24	182	1832-04-09	1
266	25	182	1830-02-10	2
267	25	183	1830-07-12	1
268	26	184	1829-12-21	1
269	36	184	1832-02-22	3
270	7	184	1830-11-13	7
271	25	186	1832-04-05	1
272	22	186	1831-04-14	2
273	8	186	1830-03-10	5
274	25	187	1832-12-03	1
275	26	187	1832-04-13	2
276	29	188	1829-09-23	1
277	23	189	1829-08-21	1
278	24	189	1830-07-17	2
279	29	190	1831-10-19	1
280	31	190	1829-09-12	3
281	21	191	1829-10-19	1
282	31	191	1829-06-01	3
283	26	192	1832-04-12	1
284	23	192	1829-03-13	2
285	3	192	1831-01-02	5
286	28	193	1832-01-06	1
287	35	193	1831-04-12	3
288	1	193	1829-03-08	6
289	28	194	1831-11-27	1
290	27	196	1830-03-14	1
291	25	196	1830-06-02	2
292	25	197	1830-10-18	1
293	29	198	1832-06-04	1
294	38	198	1832-02-08	3
295	16	198	1831-03-22	6
296	30	199	1829-11-19	1
297	23	200	1829-03-09	1
298	36	200	1832-08-08	3
299	27	201	1832-03-13	1
300	23	202	1830-09-07	1
301	21	202	1829-08-06	2
302	7	202	1832-04-23	4
303	28	203	1829-02-25	1
304	32	203	1832-07-02	3
305	19	203	1832-08-24	6
306	28	204	1831-08-11	1
307	23	205	1832-09-22	1
308	27	207	1831-02-18	1
309	21	207	1830-02-28	2
310	21	209	1831-09-24	1
311	36	209	1832-05-03	3
312	10	209	1829-05-12	7
313	28	210	1832-01-12	1
314	29	212	1830-01-27	1
315	24	213	1830-04-10	1
316	33	213	1830-07-15	3
317	23	214	1832-03-11	1
318	39	214	1830-09-02	3
319	28	215	1831-01-24	1
320	40	215	1831-11-25	3
321	6	215	1831-03-23	7
322	28	216	1831-03-16	1
323	24	218	1829-06-11	1
324	33	218	1832-03-24	3
325	4	218	1829-08-28	6
326	25	221	1831-10-02	1
327	29	224	1832-06-21	1
328	27	225	1832-09-17	1
329	23	226	1832-04-18	1
330	27	226	1832-02-23	2
331	27	227	1830-07-16	1
332	26	227	1831-06-20	2
333	18	227	1832-12-23	5
334	26	228	1829-08-15	1
335	34	228	1831-12-03	3
336	27	229	1829-11-27	1
337	28	229	1829-08-08	2
338	20	229	1831-12-10	4
339	29	230	1832-10-08	1
340	27	231	1831-11-02	1
341	27	232	1832-02-07	1
342	40	232	1831-10-13	3
343	20	232	1829-04-16	7
344	27	233	1831-04-19	1
345	29	234	1831-11-06	1
346	22	234	1832-03-24	2
347	10	234	1829-12-26	4
348	25	235	1832-09-17	1
349	28	235	1832-06-27	2
350	24	236	1830-10-23	1
351	34	236	1830-09-11	3
352	25	237	1831-05-05	1
353	27	239	1831-10-04	1
354	24	239	1831-11-23	2
355	27	240	1830-05-26	1
356	23	241	1831-10-11	1
357	34	241	1831-03-14	3
358	14	241	1830-10-11	6
359	29	242	1832-03-03	1
360	31	242	1832-04-12	3
361	26	243	1831-12-17	1
362	26	243	1831-04-01	2
363	24	244	1832-05-01	1
364	35	244	1829-02-22	3
365	27	245	1832-01-14	1
366	29	245	1832-10-08	2
367	2	245	1832-02-22	4
368	22	247	1830-04-19	1
369	36	247	1832-04-05	3
370	13	247	1831-12-24	6
371	27	250	1830-01-28	1
372	27	250	1829-05-07	2
373	1	250	1831-02-05	5
374	29	251	1832-04-04	1
375	25	251	1830-03-06	2
376	19	251	1832-03-10	4
377	28	252	1830-11-19	1
378	37	252	1830-04-17	3
379	21	253	1831-06-16	1
380	33	253	1832-10-27	3
381	23	254	1832-10-05	1
382	30	254	1830-02-17	2
383	5	254	1830-02-11	4
384	26	255	1831-03-13	1
385	24	256	1805-09-25	1
386	24	257	1807-04-16	1
387	32	257	1807-03-04	3
388	3	257	1807-06-12	7
389	30	260	1807-06-07	1
390	27	260	1807-12-06	2
391	25	261	1805-05-19	1
392	38	261	1807-09-12	3
393	23	262	1807-06-03	1
394	29	262	1804-07-12	2
395	5	262	1805-09-24	4
396	30	263	1807-04-07	1
397	21	263	1807-04-17	2
398	28	264	1804-03-17	1
399	22	264	1805-07-02	2
400	6	264	1804-09-16	4
401	25	265	1807-11-13	1
402	32	265	1806-07-10	3
403	2	265	1806-08-20	7
404	25	266	1806-06-03	1
405	37	266	1806-07-14	3
406	2	266	1806-03-21	7
407	27	267	1807-09-20	1
408	22	267	1805-01-20	2
409	3	267	1807-04-15	5
410	28	268	1807-05-16	1
411	39	268	1806-04-13	3
412	28	269	1804-04-05	1
413	28	270	1806-02-16	1
414	37	270	1805-03-08	3
415	24	272	1804-02-28	1
416	26	273	1804-04-09	1
417	28	273	1806-02-20	2
418	23	275	1806-09-22	1
419	24	275	1806-10-03	2
420	20	275	1804-03-15	4
421	30	276	1807-12-04	1
422	30	277	1804-10-10	1
423	23	277	1806-06-17	2
424	16	277	1804-09-02	5
425	26	278	1805-04-04	1
426	21	279	1804-01-18	1
427	30	279	1804-03-23	2
428	6	279	1807-05-15	4
429	24	280	1804-07-17	1
430	25	280	1807-09-25	2
431	8	280	1805-04-07	5
432	21	282	1805-08-06	1
433	25	282	1804-12-16	2
434	30	283	1804-02-23	1
435	31	283	1804-04-15	3
436	24	284	1806-08-20	1
437	22	288	1807-01-19	1
438	33	288	1804-11-23	3
439	28	289	1805-06-11	1
440	37	289	1804-07-13	3
441	2	289	1804-04-12	7
442	21	292	1805-02-01	1
443	23	293	1804-02-27	1
444	23	295	1805-07-07	1
445	24	296	1807-10-01	1
446	21	297	1806-01-19	1
447	26	299	1806-02-06	1
448	22	300	1807-05-11	1
449	23	300	1807-03-11	2
450	17	300	1806-11-05	5
451	27	302	1806-06-23	1
452	23	302	1804-09-08	2
453	6	302	1804-04-17	5
454	29	303	1804-10-22	1
455	30	303	1807-09-28	2
456	29	304	1805-08-08	1
457	29	305	1804-10-03	1
458	27	305	1807-04-20	2
459	14	305	1804-06-25	4
460	28	306	1804-12-09	1
461	38	306	1805-07-06	3
462	20	306	1804-06-14	6
463	26	307	1805-09-15	1
464	28	308	1807-06-24	1
465	28	308	1806-03-28	2
466	25	310	1807-02-17	1
467	23	310	1804-11-11	2
468	1	310	1805-11-07	4
469	27	311	1806-07-10	1
470	39	311	1804-12-05	3
471	20	311	1807-01-09	7
472	30	312	1805-09-24	1
473	24	313	1806-11-23	1
474	24	313	1804-02-08	2
475	10	313	1806-01-07	5
476	30	315	1805-06-06	1
477	30	315	1804-07-20	2
478	23	316	1804-02-06	1
479	28	318	1804-03-05	1
480	21	319	1807-07-27	1
481	35	319	1805-08-08	3
482	19	319	1805-07-16	7
483	27	320	1804-08-28	1
484	23	320	1807-08-10	2
485	24	322	1805-11-02	1
486	25	322	1807-10-27	2
487	27	323	1806-07-11	1
488	29	324	1807-11-21	1
489	27	325	1807-01-20	1
490	32	325	1806-11-15	3
491	10	325	1806-10-02	7
492	26	327	1806-01-08	1
493	25	327	1804-05-15	2
494	27	328	1804-04-10	1
495	38	328	1804-05-28	3
496	18	328	1806-04-22	6
497	30	329	1805-01-07	1
498	28	329	1806-03-27	2
499	23	331	1805-05-18	1
500	37	331	1806-02-09	3
501	2	331	1804-10-23	6
502	30	333	1806-06-18	1
503	25	333	1807-05-20	2
504	8	333	1804-03-23	4
505	30	334	1807-10-01	1
506	36	334	1805-09-01	3
507	24	335	1807-02-13	1
508	25	336	1807-10-14	1
509	39	336	1804-09-20	3
510	16	336	1807-02-09	6
511	23	337	1807-03-07	1
512	35	337	1807-03-21	3
513	29	338	1805-07-25	1
514	30	338	1805-12-12	2
515	22	339	1807-07-18	1
516	34	339	1807-12-04	3
517	30	340	1807-03-03	1
518	27	342	1804-05-26	1
519	25	343	1807-06-16	1
520	40	343	1807-06-11	3
521	29	344	1804-02-02	1
522	29	345	1807-09-13	1
523	30	345	1806-09-01	2
524	26	346	1806-01-24	1
525	22	346	1807-12-01	2
526	14	346	1807-11-16	4
527	23	347	1805-01-02	1
528	27	347	1804-12-21	2
529	15	347	1807-06-26	4
530	27	348	1805-09-20	1
531	23	348	1805-12-23	2
532	26	349	1807-03-01	1
533	28	350	1805-06-28	1
534	24	351	1807-08-28	1
535	27	354	1806-01-07	1
536	30	356	1804-09-22	1
537	27	356	1804-05-14	2
538	10	356	1806-04-19	5
539	27	357	1806-02-26	1
540	34	357	1805-01-02	3
541	24	358	1804-01-19	1
542	24	359	1805-05-02	1
543	23	360	1805-07-14	1
544	23	360	1804-02-10	2
545	29	361	1804-05-20	1
546	21	362	1806-02-25	1
547	25	363	1805-12-12	1
548	38	363	1807-11-13	3
549	22	364	1805-04-03	1
550	24	364	1804-06-08	2
551	27	366	1804-01-20	1
552	38	366	1806-08-25	3
553	4	366	1804-12-06	7
554	30	367	1804-02-15	1
555	23	367	1805-12-27	2
556	14	367	1807-07-03	4
557	26	368	1804-12-11	1
558	24	368	1805-07-09	2
559	16	368	1805-12-23	5
560	22	369	1805-07-24	1
561	28	370	1805-02-02	1
562	22	372	1804-03-28	1
563	23	374	1806-03-01	1
564	30	374	1804-04-02	2
565	28	375	1805-10-04	1
566	21	376	1804-08-09	1
567	26	376	1805-08-19	2
568	23	378	1806-08-24	1
569	28	379	1804-02-02	1
570	30	379	1807-08-04	2
571	18	379	1807-05-18	4
572	21	380	1805-06-26	1
573	36	380	1807-02-10	3
574	19	380	1805-10-08	7
575	27	381	1804-01-23	1
576	25	387	1805-02-02	1
577	29	388	1807-10-08	1
578	30	388	1806-08-15	2
579	7	388	1807-07-07	4
580	24	391	1806-01-01	1
581	29	391	1806-07-01	2
582	23	392	1804-09-09	1
583	31	392	1806-06-13	3
584	18	392	1805-05-16	6
585	27	394	1805-03-23	1
586	28	395	1806-03-06	1
587	22	395	1807-10-18	2
588	8	395	1807-10-16	4
589	24	397	1806-02-28	1
590	29	398	1804-10-02	1
591	30	399	1806-08-03	1
592	30	399	1806-11-20	2
593	3	399	1807-08-23	4
594	28	400	1806-06-19	1
595	26	402	1804-01-15	1
596	24	403	1805-12-11	1
597	34	403	1804-10-15	3
598	2	403	1804-03-07	7
599	29	404	1807-09-06	1
600	29	404	1807-08-10	2
601	21	405	1806-06-04	1
602	22	405	1807-02-27	2
603	4	405	1807-04-18	5
604	23	406	1806-09-11	1
605	29	406	1807-10-07	2
606	1	406	1807-10-28	4
607	28	407	1804-04-24	1
608	39	407	1805-04-27	3
609	15	407	1805-02-27	7
610	25	408	1807-01-26	1
611	29	408	1807-03-27	2
612	8	408	1807-01-20	4
613	30	409	1806-11-05	1
614	26	409	1806-01-25	2
615	25	410	1807-02-05	1
616	37	410	1804-09-01	3
617	22	411	1804-11-23	1
618	35	411	1805-03-19	3
619	24	412	1804-02-24	1
620	40	412	1806-12-12	3
621	26	413	1807-09-07	1
622	27	414	1806-12-28	1
623	27	414	1804-05-23	2
624	12	414	1804-03-26	5
625	23	415	1806-11-18	1
626	25	416	1805-09-08	1
627	33	416	1807-10-05	3
628	30	417	1806-07-07	1
629	26	418	1804-01-08	1
630	21	421	1805-02-13	1
631	40	421	1806-02-22	3
632	2	421	1805-02-18	7
633	28	423	1805-10-20	1
634	39	423	1804-09-03	3
635	2	423	1806-04-07	7
636	28	424	1805-03-17	1
637	30	424	1806-02-07	2
638	12	424	1804-08-28	4
639	23	425	1806-07-07	1
640	37	425	1807-06-16	3
641	22	426	1806-03-23	1
642	28	426	1805-11-08	2
643	20	426	1807-03-24	5
644	22	427	1805-12-27	1
645	27	427	1806-02-07	2
646	15	427	1804-11-25	4
647	26	428	1807-07-16	1
648	36	428	1807-06-17	3
649	26	430	1804-09-26	1
650	27	430	1807-12-16	2
651	14	430	1804-02-15	4
652	22	431	1807-07-03	1
653	40	431	1806-07-02	3
654	18	431	1804-03-23	6
655	27	432	1804-01-16	1
656	36	432	1805-06-12	3
657	3	432	1804-09-01	7
658	23	433	1805-06-09	1
659	22	434	1806-04-07	1
660	24	435	1804-05-16	1
661	24	435	1805-11-24	2
662	24	436	1805-02-15	1
663	31	436	1805-12-26	3
664	24	437	1807-07-24	1
665	26	437	1805-07-15	2
666	14	437	1807-09-21	5
667	27	438	1807-06-11	1
668	31	438	1806-09-09	3
669	6	438	1804-11-21	6
670	29	441	1807-01-15	1
671	31	441	1804-03-03	3
672	4	441	1807-03-27	7
673	28	442	1806-10-24	1
674	31	442	1804-05-15	3
675	6	442	1804-09-18	7
676	30	444	1804-05-28	1
677	22	445	1804-03-12	1
678	24	447	1805-02-21	1
679	32	447	1804-02-04	3
680	8	447	1807-10-27	6
681	22	449	1807-01-17	1
682	30	451	1804-10-06	1
683	25	451	1806-12-22	2
684	25	452	1804-12-03	1
685	28	452	1804-12-20	2
686	25	453	1807-08-14	1
687	36	453	1805-11-15	3
688	29	455	1804-01-19	1
689	21	455	1804-03-08	2
690	27	456	1804-02-20	1
691	22	456	1805-09-03	2
692	18	456	1807-06-03	5
693	29	457	1804-05-11	1
694	30	457	1806-09-10	2
695	12	457	1806-03-04	4
696	28	458	1807-05-01	1
697	27	460	1805-12-25	1
698	32	460	1804-10-10	3
699	8	460	1804-08-02	6
700	30	461	1805-02-09	1
701	36	461	1804-11-21	3
702	23	462	1807-10-03	1
703	34	462	1806-09-13	3
704	7	462	1806-11-12	6
705	29	463	1804-07-15	1
706	30	464	1804-08-22	1
707	27	465	1807-07-17	1
708	32	465	1807-10-07	3
709	5	465	1805-07-18	6
710	27	466	1804-08-07	1
711	26	466	1805-07-16	2
712	11	466	1807-11-15	5
713	21	467	1807-08-04	1
714	33	467	1807-05-15	3
715	25	468	1804-02-28	1
716	26	468	1806-01-25	2
717	23	469	1804-10-24	1
718	35	469	1805-04-09	3
719	28	470	1806-08-21	1
720	31	470	1806-05-24	3
721	27	471	1806-04-05	1
722	29	471	1805-05-20	2
723	16	471	1804-03-17	5
724	24	472	1805-03-19	1
725	24	475	1804-10-20	1
726	38	475	1807-08-20	3
727	9	475	1806-12-18	6
728	30	476	1807-07-01	1
729	27	479	1806-08-08	1
730	28	480	1807-08-03	1
731	21	481	1806-07-18	1
732	35	481	1804-12-15	3
733	13	481	1807-11-19	6
734	23	483	1807-12-20	1
735	27	484	1807-08-08	1
736	35	484	1804-03-20	3
737	4	484	1807-06-22	7
738	26	485	1805-04-23	1
739	22	486	1807-12-12	1
740	22	487	1807-04-05	1
741	35	487	1804-10-02	3
742	4	487	1807-06-14	7
743	23	488	1807-12-22	1
744	28	489	1806-06-16	1
745	31	489	1807-04-21	3
746	21	490	1805-01-04	1
747	22	492	1804-10-28	1
748	25	493	1805-03-07	1
749	35	493	1805-04-20	3
750	6	493	1804-02-12	7
751	21	495	1806-07-05	1
752	30	495	1805-08-15	2
753	10	495	1804-01-05	4
754	30	496	1805-01-08	1
755	30	497	1805-11-02	1
756	21	497	1804-10-17	2
757	17	497	1804-12-11	4
758	24	498	1804-11-23	1
759	32	498	1806-04-22	3
760	23	499	1807-07-15	1
\.


--
-- Data for Name: educational_certificates_types; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificates_types (id, name, prerequirement) FROM stdin;
1	Certificate of Participation/Completion	\N
2	High School Diploma or Equivalent (e.g., GED)	1
3	Vocational or Technical Certificates	1
4	Associate Degree	2
5	Bachelor's Degree	2
6	Graduate Certificates	3
7	Master's Degree	3
8	Professional Degrees	4
9	Doctoral Degree (Ph.D.)	4
10	Post-Doctoral Certifications/Fellowships	5
\.


--
-- Data for Name: educational_instances; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_instances (id, name, address, creation_date, closure_date, country, city) FROM stdin;
1	University of Warsaw	Krakowskie Przedmieście 26/28, 00-927 Warsaw	1616-11-19	\N	Poland	Warsaw
2	Jagiellonian University	Golebia 24, 31-007 Krakow	1164-05-12	\N	Poland	Krakow
3	Adam Mickiewicz University	ul. Henryka Wieniawskiego 1, 61-712 Poznan	1719-05-07	\N	Poland	Poznan
4	AGH University of Science and Technology	al. Mickiewicza 30, 30-059 Krakow	1719-04-20	\N	Poland	Krakow
5	Warsaw University of Technology	Plac Politechniki 1, 00-661 Warsaw	1626-01-04	\N	Poland	Warsaw
6	University of Wroclaw	pl. Uniwersytecki 1, 50-137 Wroclaw	1502-08-01	\N	Poland	Wroclaw
7	Gdansk University of Technology	ul. Narutowicza 11/12, 80-233 Gdansk	1704-10-06	\N	Poland	Gdansk
8	Lodz University of Technology	ul. Stefana Żeromskiego 116, 90-924 Lodz	1745-05-24	\N	Poland	Lodz
9	Nicolaus Copernicus University	ul. Gagarina 11, 87-100 Torun	1745-10-15	\N	Poland	Torun
10	Medical University of Warsaw	ul. Żwirki i Wigury 61, 02-091 Warsaw	1750-12-01	\N	Poland	Warsaw
11	Harvard University	Massachusetts Hall, Cambridge, MA 02138	1436-09-08	\N	USA	Cambridge
12	Stanford University	450 Serra Mall, Stanford, CA 94305	1685-11-11	\N	USA	Stanford
13	Massachusetts Institute of Technology	77 Massachusetts Ave, Cambridge, MA 02139	1661-04-10	\N	USA	Cambridge
14	University of California, Berkeley	200 California Hall, Berkeley, CA 94720	1668-03-23	\N	USA	Berkeley
15	California Institute of Technology	1200 E California Blvd, Pasadena, CA 91125	1691-09-23	\N	USA	Pasadena
16	University of Chicago	5801 S Ellis Ave, Chicago, IL 60637	1690-10-01	\N	USA	Chicago
17	Princeton University	Princeton, NJ 08544	1546-10-22	\N	USA	Princeton
18	Columbia University	116th St & Broadway, New York, NY 10027	1554-05-25	\N	USA	New York
19	Yale University	New Haven, CT 06520	1501-10-09	\N	USA	New Haven
20	University of Pennsylvania	Philadelphia, PA 19104	1540-11-14	\N	USA	Philadelphia
21	John Paul II High School	ul. Swietej Gertrudy 7, 31-046 Krakow	1757-09-01	\N	Poland	Krakow
22	High School No. 5 Krakow	ul. Studencka 12, 31-116 Krakow	1745-09-01	\N	Poland	Krakow
23	International School of Krakow	ul. Starowislna 26, 31-032 Krakow	1793-09-01	\N	Poland	Krakow
24	School Complex No. 1 Krakow	ul. Ulanow 3, 31-450 Krakow	1764-09-01	\N	Poland	Krakow
25	High School No. 8 Krakow	ul. Grzegorzecka 24, 31-532 Krakow	1728-09-01	\N	Poland	Krakow
26	School Complex No. 2 Krakow	ul. Sobieskiego 15, 31-136 Krakow	1759-09-01	\N	Poland	Krakow
27	Bilingual High School No. 1 Warsaw	ul. Syrokomli 20, 30-102 Warsaw	1792-09-01	\N	Poland	Warsaw
28	Lyceum No. 9 Warsaw	ul. Nowosadecka 41, 30-383 Warsaw	1735-09-01	\N	Poland	Warsaw
29	Lyceum No. 3 Warsaw	ul. Topolowa 22, 31-506 Warsaw	1710-09-01	\N	Poland	Warsaw
30	Catholic School Complex Warsaw	ul. Bernardynska 5, 00-055 Warsaw	1791-09-01	\N	Poland	Warsaw
31	Cracow University of Technology	ul. Warszawska 24, 31-155 Krakow	1745-10-06	\N	Poland	Krakow
32	AGH University of Science and Technology	al. Mickiewicza 30, 30-059 Krakow	1719-04-20	\N	Poland	Krakow
33	Warsaw University of Technology	Plac Politechniki 1, 00-661 Warsaw	1626-01-04	\N	Poland	Warsaw
34	University of Warsaw	Krakowskie Przedmieście 26/28, 00-927 Warsaw	1616-11-19	\N	Poland	Warsaw
35	University of Social Sciences and Humanities	ul. Chodakowska 19/31, 03-815 Warsaw	1796-10-01	\N	Poland	Warsaw
36	Warsaw School of Economics	al. Niepodleglosci 162, 02-554 Warsaw	1706-10-30	\N	Poland	Warsaw
37	University of Information Technology and Management in Rzeszow	ul. Sucharskiego 2, 35-225 Rzeszow	1796-11-01	\N	Poland	Rzeszow
38	Cracow University of Economics	ul. Rakowicka 27, 31-510 Krakow	1725-10-01	\N	Poland	Krakow
39	Warsaw University of Life Sciences	Nowoursynowska 166, 02-787 Warsaw	1616-09-23	\N	Poland	Warsaw
40	Academy of Fine Arts in Warsaw	Krakowskie Przedmieście 5, 00-068 Warsaw	1745-10-22	\N	Poland	Warsaw
\.


--
-- Data for Name: educational_instances_types_relation; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_instances_types_relation (instance_id, type_id) FROM stdin;
1	4
1	5
1	6
1	7
1	8
1	9
1	10
2	4
2	5
2	6
2	7
2	8
2	9
2	10
3	4
3	5
3	6
3	7
3	8
3	9
3	10
4	4
4	5
4	6
4	7
4	8
4	9
4	10
5	4
5	5
5	6
5	7
5	8
5	9
5	10
6	4
6	5
6	6
6	7
6	8
6	9
6	10
7	4
7	5
7	6
7	7
7	8
7	9
7	10
8	4
8	5
8	6
8	7
8	8
8	9
8	10
9	4
9	5
9	6
9	7
9	8
9	9
9	10
10	4
10	5
10	6
10	7
10	8
10	9
10	10
11	4
11	5
11	6
11	7
11	8
11	9
11	10
12	4
12	5
12	6
12	7
12	8
12	9
12	10
13	4
13	5
13	6
13	7
13	8
13	9
13	10
14	4
14	5
14	6
14	7
14	8
14	9
14	10
15	4
15	5
15	6
15	7
15	8
15	9
15	10
16	4
16	5
16	6
16	7
16	8
16	9
16	10
17	4
17	5
17	6
17	7
17	8
17	9
17	10
18	4
18	5
18	6
18	7
18	8
18	9
18	10
19	4
19	5
19	6
19	7
19	8
19	9
19	10
20	4
20	5
20	6
20	7
20	8
20	9
20	10
21	1
21	2
22	1
22	2
23	1
23	2
24	1
24	2
25	1
25	2
26	1
26	2
27	1
27	2
28	1
28	2
29	1
29	2
30	1
30	2
31	3
32	3
33	3
34	3
35	3
36	3
37	3
38	3
39	3
40	3
\.


--
-- Data for Name: international_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.international_passports (id, original_name, original_surname, en_name, en_surname, issuer, issue_date, expiration_date, sex, passport_owner, country, lost, invalidated, series) FROM stdin;
1	Sandra	Frye	Sandra	Frye	47	2005-01-18	2025-06-13	F	1	Philippines	f	f	LH
2	Tyler	Brandt	Tyler	Brandt	130	1977-05-12	1997-03-07	M	2	Iceland	f	f	LB
3	Amanda	Hayes	Amanda	Hayes	1218	1982-10-07	2002-09-18	F	3	Libya	f	f	SV
4	Anthony	Knight	Anthony	Knight	822	1953-09-12	1973-02-23	M	4	Argentina	f	f	SU
5	Lawrence	Suarez	Lawrence	Suarez	183	1955-10-19	1975-09-18	F	5	Belgium	f	f	QO
6	Tamara	Snyder	Tamara	Snyder	786	1958-09-27	1978-01-02	M	6	Iran	f	f	VH
7	Timothy	Elliott	Timothy	Elliott	306	1953-06-05	1973-03-03	F	7	Malta	f	f	SE
8	Jamie	Smith	Jamie	Smith	106	1930-09-25	1950-02-24	M	8	Syria	f	f	ZM
9	Nicole	Martinez	Nicole	Martinez	598	1933-08-15	1953-09-19	F	9	Niue	f	f	HW
10	Kyle	Foster	Kyle	Foster	544	1931-08-27	1951-01-06	M	10	Greenland	f	f	AE
11	Logan	Adams	Logan	Adams	299	1930-10-27	1950-03-13	F	11	Chile	f	f	AO
12	Paul	Hanson	Paul	Hanson	1223	1928-08-28	1948-12-07	M	12	Morocco	f	f	FK
13	Michael	Cole	Michael	Cole	742	1928-12-27	1948-09-24	F	13	Cuba	f	f	VR
14	Robert	Foster	Robert	Foster	138	1933-12-23	1953-09-09	M	14	Russia	f	f	ML
15	Brandon	Rodriguez	Brandon	Rodriguez	112	1928-10-26	1948-01-12	F	15	Belize	f	f	QJ
16	Melinda	Evans	Melinda	Evans	392	1907-03-08	1927-03-14	M	16	Guatemala	f	f	FP
17	Emily	George	Emily	George	402	1904-06-23	1924-05-27	F	17	Paraguay	f	f	RK
18	John	Nelson	John	Nelson	685	1907-04-19	1927-09-15	M	18	Chad	f	f	GS
19	Julie	Crane	Julie	Crane	1135	1908-05-02	1928-01-13	F	19	Ethiopia	f	f	TW
20	Sandra	Smith	Sandra	Smith	1221	1902-03-02	1922-10-22	M	20	Austria	f	f	WH
21	Tony	Harris	Tony	Harris	133	1902-06-23	1922-05-12	F	21	Niue	f	f	IO
22	Calvin	Garza	Calvin	Garza	827	1904-11-17	1924-01-10	M	22	Guatemala	f	f	CG
23	Aaron	Calhoun	Aaron	Calhoun	402	1903-11-08	1923-09-03	F	23	Swaziland	f	f	VW
24	Crystal	Scott	Crystal	Scott	534	1905-04-07	1925-11-01	M	24	Mexico	f	f	KH
25	Walter	Bowen	Walter	Bowen	1119	1908-02-23	1928-08-03	F	25	Ireland	f	f	BQ
26	Lucas	Austin	Lucas	Austin	1112	1908-09-23	1928-03-22	M	26	Bangladesh	f	f	TZ
27	Kristen	Long	Kristen	Long	459	1908-07-18	1928-08-03	F	27	Uzbekistan	f	f	BZ
28	Christina	Taylor	Christina	Taylor	357	1905-11-21	1925-07-10	M	28	Netherlands	f	f	AN
29	Melissa	Thomas	Melissa	Thomas	952	1902-03-23	1922-06-25	F	29	Italy	f	f	CB
30	Robert	Fuller	Robert	Fuller	601	1905-10-27	1925-05-16	M	30	Tajikistan	f	f	TV
31	Whitney	Harris	Whitney	Harris	1176	1903-11-20	1923-04-03	F	31	Liberia	f	f	IY
32	Andrea	Shepard	Andrea	Shepard	1063	1880-12-28	1900-11-15	M	32	Myanmar	f	f	PO
33	Luis	Barron	Luis	Barron	18	1878-12-27	1898-09-13	F	33	Australia	f	f	BO
34	David	Weaver	David	Weaver	126	1882-07-19	1902-07-03	M	34	Slovenia	f	f	GN
35	Emma	Matthews	Emma	Matthews	307	1878-11-15	1898-03-20	F	35	Ethiopia	f	f	CR
36	Allen	Gallagher	Allen	Gallagher	160	1880-06-12	1900-10-12	M	36	Palau	f	f	XU
37	Ryan	Luna	Ryan	Luna	1168	1879-09-12	1899-03-20	F	37	Belgium	f	f	PD
38	Alejandro	Brown	Alejandro	Brown	390	1877-03-26	1897-03-15	M	38	Monaco	f	f	SF
39	Emily	Ayers	Emily	Ayers	1058	1883-09-27	1903-08-24	F	39	Dominica	f	f	MC
40	Gina	Clay	Gina	Clay	261	1878-03-14	1898-04-20	M	40	India	f	f	NY
41	Amanda	Davenport	Amanda	Davenport	1103	1881-01-18	1901-05-22	F	41	Sweden	f	f	JP
42	Toni	Miller	Toni	Miller	577	1883-04-18	1903-07-25	M	42	Yemen	f	f	AJ
43	Jeffrey	Ryan	Jeffrey	Ryan	729	1879-09-13	1899-10-26	F	43	Kosovo	f	f	QP
44	John	Smith	John	Smith	518	1879-04-05	1899-07-06	M	44	Niger	f	f	WB
45	Kristin	Williams	Kristin	Williams	833	1882-04-23	1902-11-23	F	45	Lebanon	f	f	PG
46	Tracy	Caldwell	Tracy	Caldwell	637	1879-03-12	1899-11-09	M	46	Lesotho	f	f	FG
47	Alan	Nunez	Alan	Nunez	29	1882-01-04	1902-04-04	F	47	Argentina	f	f	KE
48	Amber	Green	Amber	Green	193	1882-03-23	1902-11-18	M	48	Cameroon	f	f	AJ
49	Darryl	Olson	Darryl	Olson	740	1879-02-19	1899-12-28	F	49	Ghana	f	f	QM
50	Brenda	Rollins	Brenda	Rollins	513	1880-05-20	1900-08-25	M	50	Bolivia	f	f	LF
51	Grant	Roberson	Grant	Roberson	291	1879-03-08	1899-07-07	F	51	Brunei	f	f	RS
52	Lauren	Wood	Lauren	Wood	1124	1881-05-22	1901-12-23	M	52	Zambia	f	f	ED
53	Jon	Dickson	Jon	Dickson	1183	1881-01-21	1901-03-02	F	53	Luxembourg	f	f	HI
54	Kyle	Gonzales	Kyle	Gonzales	376	1883-05-14	1903-05-12	M	54	Guyana	f	f	HL
55	Jessica	White	Jessica	White	1009	1879-07-06	1899-04-15	F	55	Curacao	f	f	MR
56	Tyler	Salazar	Tyler	Salazar	248	1883-04-22	1903-04-25	M	56	Denmark	f	f	OD
57	Paul	Wheeler	Paul	Wheeler	46	1877-11-09	1897-07-15	F	57	Spain	f	f	UT
58	Kyle	Blake	Kyle	Blake	632	1880-03-07	1900-12-25	M	58	Niue	f	f	EZ
59	Nicholas	Bowen	Nicholas	Bowen	1054	1877-04-24	1897-12-26	F	59	Lebanon	f	f	HG
60	Kristopher	Hancock	Kristopher	Hancock	468	1879-01-12	1899-03-05	M	60	Slovenia	f	f	MX
61	Hector	Edwards	Hector	Edwards	37	1880-07-12	1900-03-10	F	61	Haiti	f	f	XF
62	Cindy	Marquez	Cindy	Marquez	1131	1877-11-03	1897-04-03	M	62	Luxembourg	f	f	NK
63	John	Simmons	John	Simmons	464	1878-06-03	1898-02-11	F	63	Greenland	f	f	HY
64	Edward	Grant	Edward	Grant	200	1852-09-13	1872-02-16	M	64	Bahrain	f	f	GN
65	Samuel	Nielsen	Samuel	Nielsen	542	1852-02-19	1872-05-03	F	65	Bahamas	f	f	QX
66	Scott	Guerrero	Scott	Guerrero	1023	1858-03-16	1878-11-27	M	66	Belize	f	f	WE
67	Jennifer	Jones	Jennifer	Jones	707	1854-09-06	1874-04-14	F	67	Mozambique	f	f	JO
68	Thomas	Neal	Thomas	Neal	415	1858-06-10	1878-01-12	M	68	Zambia	f	f	AA
69	Steven	Morgan	Steven	Morgan	487	1856-10-25	1876-04-03	F	69	Tajikistan	f	f	QA
70	Stephen	Bender	Stephen	Bender	1234	1854-01-03	1874-05-27	M	70	Kyrgyzstan	f	f	VN
71	Rebecca	Haynes	Rebecca	Haynes	1180	1853-11-25	1873-01-22	F	71	Montenegro	f	f	VA
72	Corey	Daniels	Corey	Daniels	910	1852-03-11	1872-07-01	M	72	Benin	f	f	UD
73	Julie	Martinez	Julie	Martinez	34	1852-08-17	1872-10-01	F	73	Austria	f	f	ZP
74	Kyle	Tucker	Kyle	Tucker	292	1855-08-15	1875-03-05	M	74	Hungary	f	f	EP
75	Nathan	Martin	Nathan	Martin	305	1856-11-05	1876-09-10	F	75	Venezuela	f	f	HD
76	Levi	Long	Levi	Long	39	1854-10-24	1874-03-25	M	76	Singapore	f	f	IF
77	Zachary	Jackson	Zachary	Jackson	495	1858-04-05	1878-04-27	F	77	Gambia	f	f	JI
78	Juan	Smith	Juan	Smith	883	1855-06-09	1875-07-08	M	78	Gambia	f	f	EI
79	Michael	Young	Michael	Young	1230	1857-05-19	1877-12-14	F	79	Angola	f	f	KI
80	Carolyn	Rivera	Carolyn	Rivera	374	1856-01-23	1876-04-02	M	80	Namibia	f	f	KX
81	John	Robinson	John	Robinson	248	1858-09-22	1878-07-25	F	81	Germany	f	f	TP
82	Justin	Hughes	Justin	Hughes	377	1856-07-01	1876-03-10	M	82	Indonesia	f	f	RR
83	Michael	Murillo	Michael	Murillo	965	1853-03-24	1873-07-17	F	83	Kyrgyzstan	f	f	CP
84	Wyatt	Brennan	Wyatt	Brennan	99	1856-07-08	1876-12-17	M	84	Singapore	f	f	BL
85	Christy	Obrien	Christy	Obrien	1178	1855-10-20	1875-10-10	F	85	Nauru	f	f	TK
86	Martin	Greer	Martin	Greer	494	1855-02-17	1875-12-14	M	86	Gambia	f	f	ZJ
87	Cynthia	Walker	Cynthia	Walker	60	1853-09-21	1873-08-16	F	87	Lesotho	f	f	YH
88	Adam	Hunt	Adam	Hunt	1234	1855-09-03	1875-02-13	M	88	Paraguay	f	f	KU
89	Joseph	Nelson	Joseph	Nelson	544	1852-05-17	1872-08-13	F	89	Libya	f	f	LK
90	Damon	Valenzuela	Damon	Valenzuela	880	1857-06-06	1877-07-11	M	90	Netherlands	f	f	PJ
91	Linda	Golden	Linda	Golden	493	1856-06-10	1876-09-21	F	91	Pakistan	f	f	WI
92	Richard	Flores	Richard	Flores	48	1855-04-26	1875-04-28	M	92	Oman	f	f	OE
93	Matthew	Tucker	Matthew	Tucker	510	1853-12-03	1873-03-14	F	93	Barbados	f	f	IC
94	Rebecca	Hughes	Rebecca	Hughes	926	1856-11-28	1876-06-01	M	94	Guatemala	f	f	IB
95	Jennifer	Nelson	Jennifer	Nelson	921	1853-10-15	1873-10-14	F	95	Israel	f	f	NX
96	Megan	Davis	Megan	Davis	313	1856-05-08	1876-02-27	M	96	Seychelles	f	f	SC
97	Daniel	Wilson	Daniel	Wilson	480	1856-04-05	1876-06-04	F	97	Albania	f	f	HT
98	Henry	Carrillo	Henry	Carrillo	1081	1854-05-15	1874-01-24	M	98	Maldives	f	f	JC
99	Dalton	Henderson	Dalton	Henderson	1197	1852-02-01	1872-09-10	F	99	Kyrgyzstan	f	f	MJ
100	James	Hill	James	Hill	903	1854-01-20	1874-10-28	M	100	Ethiopia	f	f	JB
101	Patricia	Garcia	Patricia	Garcia	173	1854-11-25	1874-12-02	F	101	Haiti	f	f	HD
102	John	Hawkins	John	Hawkins	1107	1856-07-15	1876-09-12	M	102	Kiribati	f	f	QF
103	Danielle	Phillips	Danielle	Phillips	1178	1856-08-16	1876-06-21	F	103	Ukraine	f	f	IN
104	Michael	Davis	Michael	Davis	612	1854-02-12	1874-05-11	M	104	Colombia	f	f	IP
105	Danielle	Anderson	Danielle	Anderson	990	1852-06-18	1872-05-26	F	105	Israel	f	f	PI
106	Lisa	Rodriguez	Lisa	Rodriguez	791	1853-05-19	1873-07-03	M	106	Bermuda	f	f	NH
107	Ryan	Jenkins	Ryan	Jenkins	243	1855-04-03	1875-06-18	F	107	Malaysia	f	f	ZK
108	Scott	Patterson	Scott	Patterson	271	1858-02-22	1878-09-24	M	108	Montenegro	f	f	QA
109	John	Gonzalez	John	Gonzalez	339	1852-06-02	1872-01-05	F	109	Japan	f	f	EU
110	Kathy	Fry	Kathy	Fry	1060	1856-06-27	1876-06-06	M	110	Norway	f	f	JU
111	Kelly	Mejia	Kelly	Mejia	965	1853-08-26	1873-05-26	F	111	Indonesia	f	f	LE
112	Lisa	Le	Lisa	Le	517	1854-10-21	1874-04-06	M	112	Iceland	f	f	TT
113	John	Nelson	John	Nelson	90	1855-05-03	1875-02-23	F	113	Sweden	f	f	TP
114	Angela	Marsh	Angela	Marsh	1020	1858-11-14	1878-05-20	M	114	Vietnam	f	f	FX
115	Jonathan	Edwards	Jonathan	Edwards	1093	1856-08-20	1876-07-16	F	115	Morocco	f	f	HO
116	David	Williams	David	Williams	231	1855-01-14	1875-02-28	M	116	Switzerland	f	f	PF
117	Kristin	Gonzalez	Kristin	Gonzalez	637	1854-07-12	1874-07-19	F	117	Haiti	f	f	EX
118	Susan	Neal	Susan	Neal	18	1858-03-15	1878-06-15	M	118	Australia	f	f	QW
119	Lucas	Gilbert	Lucas	Gilbert	727	1858-11-27	1878-08-17	F	119	Liberia	f	f	BA
120	Cody	Meyer	Cody	Meyer	1218	1853-11-19	1873-03-25	M	120	Uganda	f	f	OW
121	Michelle	Ross	Michelle	Ross	1184	1853-07-03	1873-04-08	F	121	Cameroon	f	f	ZQ
122	Donna	Daniels	Donna	Daniels	349	1858-10-04	1878-12-11	M	122	Cambodia	f	f	MY
123	Joel	Miller	Joel	Miller	824	1858-03-01	1878-06-21	F	123	Niue	f	f	RZ
124	Jennifer	Johnson	Jennifer	Johnson	415	1852-09-26	1872-06-02	M	124	Turkey	f	f	UB
125	Maurice	Smith	Maurice	Smith	147	1853-12-13	1873-11-26	F	125	Colombia	f	f	BV
126	Ryan	Matthews	Ryan	Matthews	598	1856-02-06	1876-01-04	M	126	Curacao	f	f	YG
127	Sharon	Perry	Sharon	Perry	350	1853-07-02	1873-07-22	F	127	Kenya	f	f	HN
128	Ashley	Reed	Ashley	Reed	20	1829-07-19	1849-07-27	M	128	Djibouti	f	f	NP
129	Teresa	Shaw	Teresa	Shaw	59	1832-02-18	1852-10-06	F	129	Mali	f	f	BC
130	Stacy	Jenkins	Stacy	Jenkins	762	1827-02-23	1847-10-09	M	130	Nigeria	f	f	TJ
131	David	Brooks	David	Brooks	738	1830-12-03	1850-04-24	F	131	Luxembourg	f	f	AG
132	Angelica	Reyes	Angelica	Reyes	442	1832-07-16	1852-12-04	M	132	Slovakia	f	f	RL
133	Natalie	Holmes	Natalie	Holmes	1103	1830-01-20	1850-09-16	F	133	Belgium	f	f	RS
134	Joshua	Flores	Joshua	Flores	440	1830-03-12	1850-11-27	M	134	Morocco	f	f	BL
135	Melissa	Young	Melissa	Young	289	1828-03-26	1848-09-13	F	135	Portugal	f	f	LD
136	Tracey	Williams	Tracey	Williams	212	1827-07-26	1847-02-04	M	136	Haiti	f	f	WT
137	Jessica	Rubio	Jessica	Rubio	1148	1829-10-27	1849-01-25	F	137	Zambia	f	f	XQ
138	Darlene	Kelley	Darlene	Kelley	270	1827-05-17	1847-08-23	M	138	Slovakia	f	f	SE
139	Sherry	Melton	Sherry	Melton	921	1832-02-18	1852-02-02	F	139	Montserrat	f	f	VG
140	Emily	Garner	Emily	Garner	344	1833-11-26	1853-07-27	M	140	Hungary	f	f	UD
141	Amber	Dickerson	Amber	Dickerson	121	1827-07-24	1847-07-12	F	141	Aruba	f	f	XR
142	Kathryn	Leach	Kathryn	Leach	291	1829-11-03	1849-04-15	M	142	Venezuela	f	f	KJ
143	Andrew	Scott	Andrew	Scott	1107	1828-02-20	1848-04-03	F	143	Kyrgyzstan	f	f	GG
144	Jerry	Grant	Jerry	Grant	212	1833-08-25	1853-12-07	M	144	Croatia	f	f	BL
145	Wesley	Cross	Wesley	Cross	5	1829-07-25	1849-06-19	F	145	Martinique	f	f	TY
146	Randy	Miller	Randy	Miller	583	1833-04-09	1853-10-23	M	146	Montenegro	f	f	ZJ
147	Jamie	Vaughn	Jamie	Vaughn	102	1830-10-14	1850-05-05	F	147	Belize	f	f	HF
148	Melissa	Callahan	Melissa	Callahan	1061	1830-02-04	1850-10-18	M	148	Jamaica	f	f	JF
149	Samantha	Williams	Samantha	Williams	155	1830-01-05	1850-01-16	F	149	Malaysia	f	f	PE
150	Cathy	Michael	Cathy	Michael	822	1827-07-16	1847-09-06	M	150	Jamaica	f	f	LN
151	Abigail	Patterson	Abigail	Patterson	738	1827-06-04	1847-12-26	F	151	Poland	f	f	NU
152	Allison	Dudley	Allison	Dudley	812	1829-01-24	1849-07-23	M	152	Libya	f	f	FB
153	Kaitlyn	Peters	Kaitlyn	Peters	67	1833-09-21	1853-09-09	F	153	Tanzania	f	f	HM
154	Darlene	Byrd	Darlene	Byrd	804	1828-09-09	1848-09-07	M	154	Venezuela	f	f	OH
155	David	Huang	David	Huang	659	1828-09-14	1848-09-27	F	155	Vietnam	f	f	JQ
156	Phillip	Sullivan	Phillip	Sullivan	800	1830-05-17	1850-03-07	M	156	Norway	f	f	NJ
157	Morgan	Duncan	Morgan	Duncan	378	1831-12-09	1851-12-17	F	157	Yemen	f	f	IN
158	Danielle	Martinez	Danielle	Martinez	288	1827-07-28	1847-06-27	M	158	Pitcairn	f	f	LO
159	Natasha	Grant	Natasha	Grant	755	1828-12-13	1848-07-01	F	159	Bahrain	f	f	DO
160	Stephanie	Wheeler	Stephanie	Wheeler	600	1828-12-19	1848-01-23	M	160	Austria	f	f	AX
161	Raymond	Terrell	Raymond	Terrell	583	1832-03-01	1852-12-01	F	161	Jordan	f	f	OF
162	Krista	Marquez	Krista	Marquez	459	1830-04-16	1850-11-01	M	162	Albania	f	f	ES
163	Tamara	Tucker	Tamara	Tucker	693	1833-05-21	1853-12-22	F	163	Moldova	f	f	AG
164	Connie	Garza	Connie	Garza	866	1831-05-16	1851-12-17	M	164	Georgia	f	f	AE
165	David	King	David	King	405	1827-10-23	1847-09-05	F	165	Zimbabwe	f	f	IU
166	Tracey	Ponce	Tracey	Ponce	714	1828-06-05	1848-01-26	M	166	Monaco	f	f	PB
167	Michael	Morrow	Michael	Morrow	677	1831-09-24	1851-09-13	F	167	Samoa	f	f	US
168	Laura	Richardson	Laura	Richardson	415	1827-06-09	1847-07-17	M	168	Barbados	f	f	AZ
169	Melinda	Atkins	Melinda	Atkins	800	1830-05-14	1850-05-26	F	169	France	f	f	EA
170	Pamela	Robinson	Pamela	Robinson	298	1831-03-25	1851-05-01	M	170	Ghana	f	f	NQ
171	Tara	Murray	Tara	Murray	935	1827-03-13	1847-12-15	F	171	Ireland	f	f	CZ
172	Elizabeth	Glover	Elizabeth	Glover	47	1829-06-04	1849-11-04	M	172	Mauritania	f	f	HO
173	Dennis	Gomez	Dennis	Gomez	68	1827-06-26	1847-07-03	F	173	Brunei	f	f	UG
174	Jenna	Schroeder	Jenna	Schroeder	118	1827-07-10	1847-02-06	M	174	Portugal	f	f	BW
175	Amber	Hill	Amber	Hill	294	1827-06-02	1847-07-21	F	175	Fiji	f	f	NF
176	Brittany	Kim	Brittany	Kim	972	1831-05-26	1851-09-05	M	176	Mauritania	f	f	PR
177	Diana	Hall	Diana	Hall	325	1833-08-06	1853-03-01	F	177	Netherlands	f	f	TA
178	Logan	Morris	Logan	Morris	1197	1831-10-22	1851-12-23	M	178	Liechtenstein	f	f	WO
179	Ashley	Delgado	Ashley	Delgado	226	1829-08-16	1849-03-10	F	179	Gabon	f	f	HW
180	Rachel	Frederick	Rachel	Frederick	52	1827-05-21	1847-01-14	M	180	Haiti	f	f	IK
181	Rachel	Andrews	Rachel	Andrews	827	1829-01-23	1849-11-01	F	181	Slovakia	f	f	GV
182	Mario	Harris	Mario	Harris	862	1831-03-20	1851-04-25	M	182	Bolivia	f	f	SL
183	Scott	Martin	Scott	Martin	278	1831-07-26	1851-10-13	F	183	Kenya	f	f	KL
184	Alyssa	Williams	Alyssa	Williams	354	1828-05-23	1848-07-28	M	184	Nauru	f	f	ZK
185	Steven	Silva	Steven	Silva	1050	1832-02-19	1852-02-11	F	185	Comoros	f	f	WE
186	John	Knox	John	Knox	870	1828-09-21	1848-05-06	M	186	Aruba	f	f	QJ
187	Donna	Green	Donna	Green	47	1827-12-10	1847-10-06	F	187	Kyrgyzstan	f	f	OY
188	Natalie	Taylor	Natalie	Taylor	1057	1829-12-08	1849-01-23	M	188	Yemen	f	f	SW
189	Robert	Lam	Robert	Lam	599	1827-04-02	1847-10-13	F	189	Slovakia	f	f	NU
190	Nathan	Campbell	Nathan	Campbell	726	1827-08-14	1847-09-26	M	190	Nigeria	f	f	AO
191	Crystal	Meza	Crystal	Meza	1190	1827-08-09	1847-02-20	F	191	Barbados	f	f	GT
192	Robert	Lane	Robert	Lane	468	1829-10-25	1849-02-27	M	192	Angola	f	f	EZ
193	Valerie	Wade	Valerie	Wade	224	1829-12-10	1849-06-28	F	193	Mongolia	f	f	JS
194	Tiffany	Patterson	Tiffany	Patterson	1155	1830-07-08	1850-09-08	M	194	Croatia	f	f	RP
195	Stephanie	Garza	Stephanie	Garza	139	1829-09-17	1849-06-05	F	195	Cambodia	f	f	OQ
196	Kimberly	Shields	Kimberly	Shields	687	1829-04-23	1849-04-04	M	196	Curacao	f	f	HD
197	Austin	Martinez	Austin	Martinez	469	1833-08-16	1853-04-22	F	197	China	f	f	AA
198	Timothy	Carter	Timothy	Carter	887	1833-02-27	1853-12-22	M	198	Uruguay	f	f	TX
199	Timothy	Harris	Timothy	Harris	24	1828-08-19	1848-02-13	F	199	Nepal	f	f	GW
200	Martin	Riley	Martin	Riley	1136	1831-05-21	1851-05-28	M	200	Botswana	f	f	VB
201	Walter	Clarke	Walter	Clarke	404	1827-09-14	1847-09-06	F	201	Kazakhstan	f	f	MR
202	Kayla	Herrera	Kayla	Herrera	1081	1828-01-05	1848-06-14	M	202	Bolivia	f	f	QA
203	William	Adams	William	Adams	276	1832-01-01	1852-07-14	F	203	Botswana	f	f	DS
204	Bryan	Blackwell	Bryan	Blackwell	857	1828-07-27	1848-02-14	M	204	Liberia	f	f	OT
205	Donald	Anderson	Donald	Anderson	1018	1831-09-05	1851-12-14	F	205	Pitcairn	f	f	LQ
206	Jonathan	Gutierrez	Jonathan	Gutierrez	170	1827-09-15	1847-03-28	M	206	Liechtenstein	f	f	QB
207	Jennifer	Marquez	Jennifer	Marquez	307	1833-10-23	1853-09-07	F	207	Denmark	f	f	QP
208	Kelsey	Smith	Kelsey	Smith	422	1831-06-13	1851-11-21	M	208	Montenegro	f	f	VD
209	Mark	Ware	Mark	Ware	849	1833-09-09	1853-08-16	F	209	Lithuania	f	f	LG
210	Jonathan	Haynes	Jonathan	Haynes	1194	1830-01-05	1850-04-23	M	210	Maldives	f	f	LM
211	Sandra	Kirk	Sandra	Kirk	1107	1833-05-22	1853-05-26	F	211	Kyrgyzstan	f	f	KF
212	Elizabeth	Pope	Elizabeth	Pope	25	1833-08-06	1853-03-25	M	212	Mexico	f	f	SS
213	Misty	Hart	Misty	Hart	363	1831-04-03	1851-10-20	F	213	Philippines	f	f	QE
214	Darrell	Moyer	Darrell	Moyer	102	1831-02-06	1851-11-14	M	214	Cyprus	f	f	DU
215	Bernard	Mann	Bernard	Mann	1181	1831-07-06	1851-07-27	F	215	Cuba	f	f	IH
216	Jerry	Huffman	Jerry	Huffman	788	1832-05-03	1852-08-18	M	216	Swaziland	f	f	WM
217	Chad	Park	Chad	Park	581	1832-01-15	1852-07-03	F	217	Mongolia	f	f	GD
218	Pamela	Wagner	Pamela	Wagner	492	1832-02-23	1852-06-17	M	218	Spain	f	f	HL
219	Lauren	Lamb	Lauren	Lamb	153	1833-09-21	1853-10-21	F	219	Pakistan	f	f	TM
220	Sandra	Wright	Sandra	Wright	1174	1830-04-11	1850-07-22	M	220	Bahrain	f	f	CX
221	Kathryn	Cain	Kathryn	Cain	941	1828-11-05	1848-08-09	F	221	Chad	f	f	HS
222	Molly	Newman	Molly	Newman	644	1829-12-08	1849-05-09	M	222	Djibouti	f	f	VM
223	Keith	Wallace	Keith	Wallace	584	1832-10-24	1852-12-03	F	223	Vietnam	f	f	WT
224	Rebecca	Hogan	Rebecca	Hogan	82	1828-10-28	1848-09-16	M	224	Turkmenistan	f	f	BB
225	Daniel	Chen	Daniel	Chen	926	1829-03-16	1849-05-20	F	225	Bhutan	f	f	FI
226	Jason	Stewart	Jason	Stewart	943	1832-06-18	1852-07-13	M	226	Colombia	f	f	XE
227	Christopher	Bailey	Christopher	Bailey	915	1827-10-10	1847-04-22	F	227	Tajikistan	f	f	NM
228	Phillip	Martin	Phillip	Martin	130	1827-06-18	1847-12-12	M	228	Macedonia	f	f	QA
229	Kelsey	Mayo	Kelsey	Mayo	368	1832-03-01	1852-10-13	F	229	Iran	f	f	QQ
230	Karen	Thompson	Karen	Thompson	495	1829-01-27	1849-02-18	M	230	Armenia	f	f	MD
231	Jamie	Atkins	Jamie	Atkins	257	1833-04-08	1853-03-24	F	231	Vietnam	f	f	YQ
232	Edward	Strong	Edward	Strong	992	1828-11-14	1848-10-21	M	232	Japan	f	f	TU
233	Stacy	Kim	Stacy	Kim	13	1832-01-12	1852-06-05	F	233	Ukraine	f	f	VZ
234	Bryan	Ross	Bryan	Ross	518	1827-01-06	1847-12-01	M	234	Uzbekistan	f	f	FE
235	David	Kirby	David	Kirby	487	1829-12-22	1849-06-09	F	235	Benin	f	f	BH
236	Andrew	Freeman	Andrew	Freeman	51	1833-11-18	1853-06-09	M	236	Montenegro	f	f	UQ
237	Jennifer	Hudson	Jennifer	Hudson	460	1828-04-17	1848-05-17	F	237	Liberia	f	f	QR
238	Scott	Moreno	Scott	Moreno	488	1828-06-21	1848-11-12	M	238	Russia	f	f	FZ
239	Shannon	King	Shannon	King	823	1830-12-14	1850-11-10	F	239	Montenegro	f	f	LX
240	Kristen	Thomas	Kristen	Thomas	1144	1827-08-15	1847-05-07	M	240	Burundi	f	f	QT
241	Brittany	Dickerson	Brittany	Dickerson	176	1832-02-28	1852-09-14	F	241	Georgia	f	f	RF
242	Laura	Robles	Laura	Robles	992	1827-07-06	1847-09-09	M	242	Finland	f	f	UE
243	Rick	Murphy	Rick	Murphy	1063	1829-08-27	1849-03-11	F	243	Syria	f	f	NA
244	Jennifer	Black	Jennifer	Black	959	1827-03-20	1847-07-28	M	244	Norway	f	f	QJ
245	Janet	Nelson	Janet	Nelson	545	1829-12-04	1849-11-03	F	245	Germany	f	f	LH
246	Susan	Smith	Susan	Smith	861	1830-08-04	1850-08-24	M	246	Hungary	f	f	BQ
247	Chad	Nelson	Chad	Nelson	118	1828-05-26	1848-12-16	F	247	Senegal	f	f	SO
248	Cesar	Peterson	Cesar	Peterson	390	1833-10-05	1853-03-19	M	248	Rwanda	f	f	RH
249	Amanda	Green	Amanda	Green	469	1833-04-10	1853-05-04	F	249	Tanzania	f	f	MP
250	Jennifer	Brown	Jennifer	Brown	231	1827-05-18	1847-03-02	M	250	Switzerland	f	f	EU
251	Rebecca	Novak	Rebecca	Novak	102	1827-08-15	1847-01-23	F	251	Denmark	f	f	XT
252	Michael	Smith	Michael	Smith	24	1833-10-13	1853-09-19	M	252	Bulgaria	f	f	JP
253	Melissa	Barron	Melissa	Barron	374	1832-01-04	1852-12-13	F	253	Burundi	f	f	PQ
254	Aaron	Richardson	Aaron	Richardson	899	1828-07-13	1848-04-25	M	254	Spain	f	f	QN
255	Patrick	Jacobs	Patrick	Jacobs	1135	1831-11-15	1851-11-25	F	255	Croatia	f	f	QS
256	Crystal	Braun	Crystal	Braun	921	1804-02-28	1824-03-03	M	256	Zimbabwe	f	f	HB
257	John	Mullen	John	Mullen	58	1808-12-16	1828-07-07	F	257	Yemen	f	f	FE
258	Rachel	Martinez	Rachel	Martinez	783	1805-10-17	1825-01-08	M	258	Lithuania	f	f	AX
259	Joseph	Lawson	Joseph	Lawson	798	1806-11-11	1826-10-03	F	259	Finland	f	f	WF
260	Dana	Hicks	Dana	Hicks	67	1804-05-16	1824-07-04	M	260	Belize	f	f	AX
261	Jillian	Russell	Jillian	Russell	903	1808-09-09	1828-01-01	F	261	Colombia	f	f	TF
262	Scott	Williams	Scott	Williams	965	1808-04-21	1828-12-16	M	262	Malawi	f	f	CP
263	Ronald	Sharp	Ronald	Sharp	942	1802-09-28	1822-04-20	F	263	Colombia	f	f	PB
264	Ronald	Rodriguez	Ronald	Rodriguez	766	1802-05-21	1822-05-19	M	264	Bhutan	f	f	CK
265	Christopher	Davis	Christopher	Davis	1150	1803-11-18	1823-04-19	F	265	Poland	f	f	HE
266	Maria	Fletcher	Maria	Fletcher	98	1803-01-02	1823-08-06	M	266	Nicaragua	f	f	PV
267	James	Chambers	James	Chambers	37	1806-01-03	1826-11-16	F	267	Latvia	f	f	CR
268	Michael	Morris	Michael	Morris	1182	1803-02-12	1823-09-20	M	268	Kosovo	f	f	AM
269	Deborah	Williams	Deborah	Williams	177	1805-10-19	1825-02-14	F	269	Tanzania	f	f	CN
270	Patrick	Jimenez	Patrick	Jimenez	345	1805-05-24	1825-10-20	M	270	Bahamas	f	f	RF
271	Debra	Rojas	Debra	Rojas	247	1806-07-21	1826-08-26	F	271	Seychelles	f	f	TH
272	Amy	Mitchell	Amy	Mitchell	51	1807-02-12	1827-03-05	M	272	Tanzania	f	f	KZ
273	Angela	Macias	Angela	Macias	7	1807-02-23	1827-11-07	F	273	Nigeria	f	f	RP
274	Jessica	Young	Jessica	Young	92	1808-05-16	1828-12-05	M	274	Haiti	f	f	EG
275	Lance	Evans	Lance	Evans	496	1804-08-01	1824-07-21	F	275	Afghanistan	f	f	OY
276	Nicholas	Phillips	Nicholas	Phillips	1088	1806-06-05	1826-03-01	M	276	Nicaragua	f	f	QG
277	Robert	Smith	Robert	Smith	162	1803-11-06	1823-11-08	F	277	Iceland	f	f	RK
278	Lori	Kennedy	Lori	Kennedy	928	1805-09-01	1825-06-08	M	278	Kazakhstan	f	f	BA
279	Wesley	Williams	Wesley	Williams	1107	1803-08-06	1823-02-14	F	279	Pitcairn	f	f	JC
280	Kevin	Bailey	Kevin	Bailey	1048	1805-11-25	1825-02-17	M	280	Croatia	f	f	BL
281	Kimberly	Finley	Kimberly	Finley	702	1804-09-05	1824-10-05	F	281	Spain	f	f	WU
282	Mitchell	Madden	Mitchell	Madden	1174	1808-06-08	1828-02-04	M	282	Switzerland	f	f	JO
283	Sophia	Williams	Sophia	Williams	696	1802-04-20	1822-06-05	F	283	Montenegro	f	f	WT
284	Craig	Luna	Craig	Luna	293	1808-09-07	1828-02-07	M	284	Denmark	f	f	FZ
285	Jeff	Ramirez	Jeff	Ramirez	969	1808-12-15	1828-02-22	F	285	Malawi	f	f	LW
286	Angelica	Owens	Angelica	Owens	870	1804-05-13	1824-09-23	M	286	Turkmenistan	f	f	QT
287	Crystal	Mitchell	Crystal	Mitchell	1038	1808-07-03	1828-02-13	F	287	Aruba	f	f	UZ
288	Carrie	Holloway	Carrie	Holloway	1072	1803-02-22	1823-10-11	M	288	Somalia	f	f	MM
289	Alicia	Clark	Alicia	Clark	1117	1802-09-09	1822-03-15	F	289	Egypt	f	f	LZ
290	Michael	Gonzalez	Michael	Gonzalez	474	1808-12-01	1828-01-12	M	290	Somalia	f	f	DM
291	Carlos	Griffith	Carlos	Griffith	351	1806-10-18	1826-08-09	F	291	Greece	f	f	XP
292	Gary	Dean	Gary	Dean	376	1807-05-14	1827-11-06	M	292	Zimbabwe	f	f	UF
293	Kevin	Smith	Kevin	Smith	1108	1805-12-19	1825-12-08	F	293	Kiribati	f	f	YO
294	Travis	Jensen	Travis	Jensen	32	1805-01-12	1825-05-25	M	294	Kenya	f	f	LD
295	Elizabeth	Nichols	Elizabeth	Nichols	955	1807-02-07	1827-03-27	F	295	Tajikistan	f	f	UV
296	Sean	Castillo	Sean	Castillo	646	1802-04-12	1822-12-04	M	296	Tunisia	f	f	ER
297	David	Yu	David	Yu	1131	1807-10-18	1827-02-08	F	297	Montenegro	f	f	JE
298	Edward	Davis	Edward	Davis	441	1804-07-15	1824-03-27	M	298	Georgia	f	f	UR
299	Donna	David	Donna	David	1240	1808-12-24	1828-08-22	F	299	Iraq	f	f	YC
300	Lisa	Moss	Lisa	Moss	718	1804-06-19	1824-10-24	M	300	Paraguay	f	f	TK
301	Frank	Robinson	Frank	Robinson	727	1803-05-22	1823-09-11	F	301	Mali	f	f	YV
302	Courtney	Moore	Courtney	Moore	121	1805-04-03	1825-02-09	M	302	Pitcairn	f	f	MG
303	Samantha	Gill	Samantha	Gill	1089	1802-12-08	1822-06-15	F	303	Ecuador	f	f	MM
304	Betty	Bauer	Betty	Bauer	740	1805-03-07	1825-12-27	M	304	Gibraltar	f	f	PW
305	Matthew	Vang	Matthew	Vang	736	1802-09-15	1822-03-27	F	305	Bolivia	f	f	OR
306	Jessica	Mata	Jessica	Mata	1021	1807-08-14	1827-05-20	M	306	Pitcairn	f	f	YI
307	Karen	Jones	Karen	Jones	91	1804-08-18	1824-10-21	F	307	Denmark	f	f	DU
308	Robert	Garza	Robert	Garza	1088	1804-08-19	1824-10-07	M	308	Samoa	f	f	ND
309	Charles	Norton	Charles	Norton	377	1803-09-06	1823-06-07	F	309	Seychelles	f	f	ZT
310	Daniel	Garner	Daniel	Garner	975	1804-04-24	1824-06-08	M	310	Romania	f	f	GM
311	David	Singleton	David	Singleton	851	1804-06-22	1824-10-16	F	311	Myanmar	f	f	VL
312	Justin	Baker	Justin	Baker	1154	1805-04-02	1825-07-27	M	312	Iraq	f	f	SE
313	Heather	Taylor	Heather	Taylor	529	1804-10-17	1824-05-21	F	313	Rwanda	f	f	ZY
314	Brandon	Velasquez	Brandon	Velasquez	146	1808-04-14	1828-05-04	M	314	Denmark	f	f	PL
315	Adam	Black	Adam	Black	162	1805-06-04	1825-01-05	F	315	Cyprus	f	f	OM
316	Albert	Smith	Albert	Smith	1097	1805-08-23	1825-12-18	M	316	Brunei	f	f	QS
317	David	Barnes	David	Barnes	354	1803-04-26	1823-07-14	F	317	Bhutan	f	f	ON
318	Katherine	Benjamin	Katherine	Benjamin	1028	1807-01-19	1827-02-10	M	318	Nepal	f	f	MT
319	Amber	Lopez	Amber	Lopez	1126	1803-11-14	1823-05-14	F	319	Romania	f	f	DW
320	Cynthia	Phelps	Cynthia	Phelps	55	1806-12-02	1826-03-13	M	320	Kazakhstan	f	f	IU
321	Jonathon	Hurley	Jonathon	Hurley	1136	1802-11-28	1822-05-07	F	321	Mongolia	f	f	HR
322	Evan	Bowers	Evan	Bowers	345	1804-09-06	1824-01-15	M	322	Seychelles	f	f	KQ
323	Kristen	Wolfe	Kristen	Wolfe	1087	1807-10-09	1827-03-02	F	323	Qatar	f	f	SM
324	Christopher	Lee	Christopher	Lee	985	1808-07-18	1828-06-13	M	324	Colombia	f	f	UK
325	Kristin	Sawyer	Kristin	Sawyer	415	1805-08-15	1825-04-14	F	325	Afghanistan	f	f	RP
326	Nicholas	Dickerson	Nicholas	Dickerson	964	1805-03-02	1825-05-21	M	326	Cameroon	f	f	PP
327	Katherine	Figueroa	Katherine	Figueroa	1151	1805-10-16	1825-04-11	F	327	Germany	f	f	HD
328	Lisa	Le	Lisa	Le	762	1802-12-19	1822-11-21	M	328	Eritrea	f	f	FK
329	Jon	Thornton	Jon	Thornton	228	1802-11-25	1822-06-19	F	329	Macao	f	f	AZ
330	David	Wilkins	David	Wilkins	44	1802-12-24	1822-11-21	M	330	Armenia	f	f	GQ
331	Michael	Nash	Michael	Nash	464	1808-11-19	1828-06-06	F	331	Malaysia	f	f	OQ
332	Olivia	George	Olivia	George	752	1804-08-23	1824-12-05	M	332	Belize	f	f	XN
333	Benjamin	Oneill	Benjamin	Oneill	52	1802-04-08	1822-05-05	F	333	Gambia	f	f	DN
334	Scott	Ashley	Scott	Ashley	398	1802-02-09	1822-10-22	M	334	Cuba	f	f	PC
335	Edward	Frank	Edward	Frank	223	1803-11-04	1823-01-22	F	335	Botswana	f	f	GG
336	Tamara	Flores	Tamara	Flores	1142	1808-07-17	1828-07-05	M	336	Uruguay	f	f	XV
337	Jerry	Ramsey	Jerry	Ramsey	1101	1804-04-06	1824-03-14	F	337	Croatia	f	f	TZ
338	Anna	Merritt	Anna	Merritt	506	1806-09-01	1826-12-23	M	338	Argentina	f	f	JH
339	Laurie	Benson	Laurie	Benson	703	1805-09-15	1825-01-16	F	339	Moldova	f	f	MZ
340	Matthew	Sandoval	Matthew	Sandoval	780	1803-07-03	1823-01-27	M	340	Chile	f	f	PV
341	Jerry	Taylor	Jerry	Taylor	292	1804-09-18	1824-11-07	F	341	China	f	f	IH
342	Robert	Garcia	Robert	Garcia	326	1808-08-15	1828-09-27	M	342	Malaysia	f	f	WI
343	Ashley	Keller	Ashley	Keller	942	1802-09-03	1822-06-19	F	343	Philippines	f	f	FM
344	Melissa	Thompson	Melissa	Thompson	920	1802-04-27	1822-08-18	M	344	Jamaica	f	f	CT
345	Kathleen	Gray	Kathleen	Gray	833	1805-01-13	1825-06-10	F	345	Senegal	f	f	LY
346	Ryan	Cochran	Ryan	Cochran	889	1808-03-21	1828-05-05	M	346	Mongolia	f	f	CY
347	Ashley	Wilkinson	Ashley	Wilkinson	425	1803-06-28	1823-09-04	F	347	Poland	f	f	HV
348	Jacqueline	Yates	Jacqueline	Yates	1203	1806-07-26	1826-06-04	M	348	Egypt	f	f	IX
349	Erin	Fisher	Erin	Fisher	471	1808-07-28	1828-11-04	F	349	Sudan	f	f	IU
350	Christine	Garcia	Christine	Garcia	834	1808-01-24	1828-12-26	M	350	Afghanistan	f	f	XS
351	David	Bowman	David	Bowman	268	1803-11-08	1823-07-25	F	351	Gabon	f	f	RZ
352	Lance	Mosley	Lance	Mosley	592	1804-07-28	1824-03-15	M	352	Belarus	f	f	TN
353	Kim	Rodriguez	Kim	Rodriguez	834	1802-09-03	1822-07-26	F	353	Nauru	f	f	PW
354	Erin	Erickson	Erin	Erickson	278	1805-05-03	1825-01-11	M	354	Japan	f	f	ZU
355	Rachel	Robbins	Rachel	Robbins	764	1806-09-01	1826-04-19	F	355	Liechtenstein	f	f	HB
356	Jake	Reilly	Jake	Reilly	495	1805-12-10	1825-12-26	M	356	Moldova	f	f	HM
357	Christian	Thomas	Christian	Thomas	204	1803-04-16	1823-12-19	F	357	Afghanistan	f	f	NJ
358	Leonard	Michael	Leonard	Michael	1006	1804-03-02	1824-09-20	M	358	Burundi	f	f	YU
359	Alyssa	Ellison	Alyssa	Ellison	329	1808-10-10	1828-09-24	F	359	Tunisia	f	f	FG
360	Amber	Lee	Amber	Lee	441	1807-01-28	1827-05-16	M	360	India	f	f	VW
361	Barbara	Jones	Barbara	Jones	924	1804-06-06	1824-06-08	F	361	Guatemala	f	f	GZ
362	Michael	Pierce	Michael	Pierce	452	1807-12-13	1827-06-06	M	362	Armenia	f	f	TU
363	David	Dean	David	Dean	245	1808-07-27	1828-04-22	F	363	Aruba	f	f	CA
364	Samantha	Evans	Samantha	Evans	313	1808-06-05	1828-02-12	M	364	Uganda	f	f	KV
365	Carla	Lyons	Carla	Lyons	758	1807-01-05	1827-04-05	F	365	Mauritania	f	f	RH
366	Taylor	Williams	Taylor	Williams	1240	1803-03-13	1823-02-09	M	366	Ukraine	f	f	AP
367	Charles	Madden	Charles	Madden	840	1805-05-15	1825-06-05	F	367	Latvia	f	f	CH
368	Michael	Davis	Michael	Davis	715	1802-08-25	1822-11-17	M	368	Macao	f	f	SH
369	Donna	Nelson	Donna	Nelson	696	1804-06-08	1824-06-02	F	369	USA	f	f	PH
370	Shari	Jimenez	Shari	Jimenez	124	1802-04-15	1822-01-16	M	370	Lithuania	f	f	IG
371	Raymond	Lopez	Raymond	Lopez	361	1802-05-21	1822-02-23	F	371	Canada	f	f	AV
372	Amanda	Levy	Amanda	Levy	845	1804-02-06	1824-09-27	M	372	Chad	f	f	KP
373	Keith	Rowland	Keith	Rowland	705	1805-10-21	1825-06-09	F	373	Russia	f	f	CK
374	Robert	Shelton	Robert	Shelton	1201	1807-04-11	1827-12-28	M	374	Paraguay	f	f	XE
375	Robert	Hutchinson	Robert	Hutchinson	879	1803-11-27	1823-02-27	F	375	Senegal	f	f	IG
376	Tammy	Gomez	Tammy	Gomez	935	1803-07-26	1823-02-20	M	376	Tunisia	f	f	ZQ
377	Randy	Herrera	Randy	Herrera	415	1808-03-02	1828-03-01	F	377	Djibouti	f	f	JI
378	Wendy	Oneal	Wendy	Oneal	1125	1802-12-26	1822-03-08	M	378	Malawi	f	f	DY
379	Caitlin	Wright	Caitlin	Wright	293	1808-09-14	1828-01-17	F	379	Angola	f	f	QF
380	Joshua	Jones	Joshua	Jones	745	1802-05-01	1822-02-02	M	380	Iceland	f	f	AU
381	Chris	Moore	Chris	Moore	1187	1808-12-05	1828-11-07	F	381	Israel	f	f	ZW
382	Daniel	Anderson	Daniel	Anderson	1007	1806-12-02	1826-06-25	M	382	Brunei	f	f	BI
383	Erin	Johnson	Erin	Johnson	680	1804-06-04	1824-01-08	F	383	Ethiopia	f	f	CC
384	Erika	Diaz	Erika	Diaz	1138	1802-03-17	1822-06-08	M	384	Mali	f	f	UW
385	Angela	Wood	Angela	Wood	58	1803-02-17	1823-09-17	F	385	Ghana	f	f	UJ
386	Shaun	Gates	Shaun	Gates	788	1806-11-24	1826-06-27	M	386	Comoros	f	f	VK
387	Jessica	Garza	Jessica	Garza	214	1807-12-27	1827-02-11	F	387	Nigeria	f	f	BN
388	Margaret	Henderson	Margaret	Henderson	1206	1803-02-05	1823-12-02	M	388	Nigeria	f	f	RO
389	Rebecca	Miller	Rebecca	Miller	576	1803-04-22	1823-06-05	F	389	Norway	f	f	ZZ
390	Lori	Wright	Lori	Wright	683	1805-06-24	1825-10-07	M	390	Comoros	f	f	LS
391	Mark	Jenkins	Mark	Jenkins	327	1806-05-15	1826-05-06	F	391	Belgium	f	f	NZ
392	Elizabeth	Pierce	Elizabeth	Pierce	460	1803-07-23	1823-02-07	M	392	Barbados	f	f	ZE
393	Thomas	Davis	Thomas	Davis	148	1807-01-01	1827-01-02	F	393	Nicaragua	f	f	QW
394	Kenneth	Gaines	Kenneth	Gaines	715	1804-06-21	1824-02-19	M	394	Jamaica	f	f	OQ
395	Jennifer	Wall	Jennifer	Wall	853	1806-11-20	1826-07-01	F	395	Singapore	f	f	AO
396	Elizabeth	Robertson	Elizabeth	Robertson	646	1808-02-11	1828-05-17	M	396	Canada	f	f	WU
397	Kristin	Todd	Kristin	Todd	22	1807-10-12	1827-10-05	F	397	Germany	f	f	UH
398	Sarah	Haynes	Sarah	Haynes	780	1802-01-11	1822-06-05	M	398	Gabon	f	f	OB
399	Margaret	Beard	Margaret	Beard	224	1808-10-16	1828-04-09	F	399	Azerbaijan	f	f	LL
400	Jonathan	Garza	Jonathan	Garza	51	1805-04-13	1825-02-21	M	400	Kosovo	f	f	HM
401	Kristi	Stewart	Kristi	Stewart	920	1806-01-23	1826-06-01	F	401	Guinea	f	f	QU
402	Dwayne	Mcgee	Dwayne	Mcgee	783	1805-03-05	1825-08-25	M	402	Rwanda	f	f	NW
403	Richard	Jones	Richard	Jones	67	1807-11-21	1827-01-26	F	403	Bahamas	f	f	FL
404	Alexandria	Alvarado	Alexandria	Alvarado	425	1805-10-07	1825-08-15	M	404	Kyrgyzstan	f	f	RM
405	Christina	Smith	Christina	Smith	268	1803-09-07	1823-04-17	F	405	Madagascar	f	f	RW
406	Michael	Trujillo	Michael	Trujillo	794	1804-03-24	1824-11-06	M	406	Poland	f	f	LV
407	Jennifer	Gutierrez	Jennifer	Gutierrez	984	1802-03-17	1822-04-17	F	407	Senegal	f	f	NP
408	Christian	Cooper	Christian	Cooper	692	1808-04-05	1828-06-26	M	408	Poland	f	f	BJ
409	Anthony	Jones	Anthony	Jones	338	1802-12-24	1822-02-09	F	409	Jordan	f	f	OH
410	Pedro	Skinner	Pedro	Skinner	235	1803-06-12	1823-01-21	M	410	Libya	f	f	LO
411	Dean	Griffin	Dean	Griffin	707	1808-03-13	1828-06-04	F	411	Moldova	f	f	VK
412	Sharon	Wells	Sharon	Wells	43	1803-10-09	1823-10-09	M	412	Laos	f	f	DT
413	Kristy	Blake	Kristy	Blake	1157	1807-11-26	1827-02-20	F	413	Cyprus	f	f	HW
414	Stephen	Morales	Stephen	Morales	214	1808-06-23	1828-06-11	M	414	Switzerland	f	f	VN
415	Meghan	Patton	Meghan	Patton	586	1802-05-24	1822-09-12	F	415	Ukraine	f	f	CW
416	Debra	Rivera	Debra	Rivera	227	1804-09-16	1824-05-23	M	416	Belarus	f	f	IR
417	Chad	White	Chad	White	249	1803-02-14	1823-02-07	F	417	Oman	f	f	UG
418	Darrell	Pace	Darrell	Pace	417	1805-09-27	1825-09-17	M	418	Morocco	f	f	IO
419	Paul	Miller	Paul	Miller	568	1808-09-06	1828-03-28	F	419	Malta	f	f	OF
420	Martha	Ware	Martha	Ware	325	1807-01-14	1827-02-25	M	420	Turkmenistan	f	f	WQ
421	Leslie	Roberts	Leslie	Roberts	342	1808-10-02	1828-10-22	F	421	Bermuda	f	f	UM
422	Phillip	Nelson	Phillip	Nelson	892	1804-04-14	1824-12-13	M	422	Argentina	f	f	NQ
423	Jack	Miller	Jack	Miller	952	1805-04-22	1825-01-04	F	423	Slovenia	f	f	UD
424	Justin	Williams	Justin	Williams	581	1806-09-12	1826-08-10	M	424	Slovakia	f	f	XR
425	Marcia	Mcdonald	Marcia	Mcdonald	671	1807-10-24	1827-08-04	F	425	USA	f	f	NO
426	Erin	Cox	Erin	Cox	373	1803-05-03	1823-04-11	M	426	Angola	f	f	YZ
427	Richard	Barker	Richard	Barker	485	1804-12-10	1824-01-02	F	427	Liberia	f	f	FT
428	Meredith	Woodward	Meredith	Woodward	668	1808-07-23	1828-03-09	M	428	Croatia	f	f	IC
429	Emma	Mendez	Emma	Mendez	933	1806-06-08	1826-09-20	F	429	Fiji	f	f	LH
430	John	Guzman	John	Guzman	214	1806-12-19	1826-02-02	M	430	Gambia	f	f	CD
431	Kelly	Medina	Kelly	Medina	27	1806-05-24	1826-12-23	F	431	Bermuda	f	f	GZ
432	Erica	Middleton	Erica	Middleton	1220	1802-01-22	1822-03-03	M	432	Cameroon	f	f	AO
433	Natalie	Mata	Natalie	Mata	291	1807-08-03	1827-04-10	F	433	Cameroon	f	f	JP
434	Monique	Harris	Monique	Harris	221	1807-04-12	1827-10-26	M	434	Djibouti	f	f	DZ
435	Amber	Williams	Amber	Williams	1023	1806-06-14	1826-12-01	F	435	Ukraine	f	f	SF
436	Jessica	Gibson	Jessica	Gibson	212	1806-10-22	1826-11-24	M	436	Oman	f	f	TK
437	Jennifer	Woods	Jennifer	Woods	1223	1804-12-28	1824-06-06	F	437	Madagascar	f	f	QZ
438	Stacie	Burns	Stacie	Burns	387	1805-12-24	1825-09-09	M	438	France	f	f	PG
439	Tyler	Martinez	Tyler	Martinez	3	1806-01-04	1826-12-21	F	439	Curacao	f	f	RS
440	Ana	Douglas	Ana	Douglas	108	1803-09-23	1823-04-12	M	440	Venezuela	f	f	BR
441	Alan	Frazier	Alan	Frazier	21	1804-10-08	1824-06-23	F	441	Portugal	f	f	KV
442	Stephen	Murphy	Stephen	Murphy	387	1805-06-17	1825-07-20	M	442	Bhutan	f	f	TA
443	Jeffrey	Miller	Jeffrey	Miller	823	1802-02-09	1822-11-16	F	443	Chad	f	f	VR
444	Emily	Mooney	Emily	Mooney	1151	1806-03-10	1826-10-09	M	444	Liberia	f	f	VQ
445	Justin	Palmer	Justin	Palmer	1097	1805-07-01	1825-06-09	F	445	Djibouti	f	f	HX
446	Christy	Robbins	Christy	Robbins	450	1807-07-22	1827-06-02	M	446	Uganda	f	f	NB
447	Joseph	Kennedy	Joseph	Kennedy	308	1805-09-12	1825-05-19	F	447	Swaziland	f	f	VP
448	Veronica	Waters	Veronica	Waters	29	1808-03-07	1828-09-07	M	448	Norway	f	f	ZO
449	Benjamin	Blair	Benjamin	Blair	347	1808-05-27	1828-08-25	F	449	Kenya	f	f	XE
450	Amanda	Morgan	Amanda	Morgan	1052	1803-07-07	1823-07-22	M	450	Macao	f	f	PY
451	Nathaniel	Jackson	Nathaniel	Jackson	330	1807-02-05	1827-08-17	F	451	Maldives	f	f	TJ
452	John	Hensley	John	Hensley	732	1806-06-15	1826-10-17	M	452	Japan	f	f	JJ
453	Veronica	Hart	Veronica	Hart	306	1802-06-14	1822-09-03	F	453	Chile	f	f	UU
454	Jeremy	Snyder	Jeremy	Snyder	381	1807-05-01	1827-12-04	M	454	Mali	f	f	DU
455	Amanda	Lambert	Amanda	Lambert	465	1805-01-22	1825-02-08	F	455	Ecuador	f	f	UB
456	Christopher	Stark	Christopher	Stark	840	1802-06-22	1822-05-14	M	456	Mali	f	f	WA
457	Daniel	Duran	Daniel	Duran	580	1806-07-23	1826-04-28	F	457	Niue	f	f	VR
458	Kevin	Mcconnell	Kevin	Mcconnell	1021	1804-01-26	1824-07-09	M	458	Myanmar	f	f	LS
459	Troy	Montes	Troy	Montes	359	1806-11-12	1826-01-22	F	459	Moldova	f	f	JJ
460	Jose	Smith	Jose	Smith	330	1805-01-26	1825-08-26	M	460	China	f	f	TK
461	Kevin	Kramer	Kevin	Kramer	546	1808-09-20	1828-07-02	F	461	Zambia	f	f	UO
462	Elizabeth	Carter	Elizabeth	Carter	137	1807-04-16	1827-07-22	M	462	Australia	f	f	OY
463	Anthony	Woods	Anthony	Woods	740	1808-05-07	1828-08-01	F	463	Mexico	f	f	FO
464	Jennifer	Shaffer	Jennifer	Shaffer	761	1806-02-04	1826-05-21	M	464	Aruba	f	f	TL
465	Erika	Tran	Erika	Tran	1242	1802-08-12	1822-03-10	F	465	Kyrgyzstan	f	f	OB
466	Colleen	Hampton	Colleen	Hampton	1107	1804-08-08	1824-08-08	M	466	Thailand	f	f	OM
467	Allison	Johnson	Allison	Johnson	288	1803-02-21	1823-02-04	F	467	Sweden	f	f	BG
468	Donald	Mcguire	Donald	Mcguire	589	1804-09-10	1824-03-15	M	468	Nigeria	f	f	EG
469	Elizabeth	Snyder	Elizabeth	Snyder	650	1804-04-27	1824-04-11	F	469	Bahrain	f	f	RI
470	Nathan	Elliott	Nathan	Elliott	1057	1807-05-10	1827-07-05	M	470	Norway	f	f	JL
471	Ana	Ford	Ana	Ford	20	1807-07-21	1827-05-23	F	471	Germany	f	f	PQ
472	Matthew	Juarez	Matthew	Juarez	311	1804-05-28	1824-09-02	M	472	Ecuador	f	f	XR
473	Monica	Stewart	Monica	Stewart	366	1803-03-27	1823-01-23	F	473	Poland	f	f	QK
474	Preston	Jensen	Preston	Jensen	738	1803-04-16	1823-01-14	M	474	Bhutan	f	f	EI
475	Valerie	Strickland	Valerie	Strickland	436	1802-03-03	1822-09-23	F	475	Swaziland	f	f	KW
476	Amy	Murphy	Amy	Murphy	132	1806-12-28	1826-05-15	M	476	Togo	f	f	YQ
477	Krista	Morgan	Krista	Morgan	534	1806-09-18	1826-11-03	F	477	Greece	f	f	HC
478	Samuel	Le	Samuel	Le	6	1803-11-12	1823-08-15	M	478	Haiti	f	f	WX
479	Sierra	Bentley	Sierra	Bentley	766	1802-06-03	1822-05-16	F	479	Italy	f	f	VA
480	Wyatt	Nelson	Wyatt	Nelson	817	1806-04-16	1826-08-27	M	480	Macao	f	f	AB
481	Steven	Ramos	Steven	Ramos	735	1808-12-07	1828-01-24	F	481	Turkmenistan	f	f	ES
482	Jason	Peters	Jason	Peters	91	1802-09-11	1822-08-28	M	482	Mauritius	f	f	ZS
483	Frank	Sanchez	Frank	Sanchez	697	1807-01-05	1827-11-27	F	483	Nigeria	f	f	YO
484	James	Sloan	James	Sloan	735	1808-05-13	1828-05-26	M	484	China	f	f	XV
485	Thomas	Anderson	Thomas	Anderson	889	1805-09-08	1825-04-27	F	485	Uzbekistan	f	f	TI
486	Samuel	Cuevas	Samuel	Cuevas	112	1803-08-02	1823-01-02	M	486	Palau	f	f	NH
487	Ian	Hoffman	Ian	Hoffman	655	1806-07-24	1826-01-18	F	487	Burundi	f	f	WK
488	Derek	Blair	Derek	Blair	1099	1804-08-27	1824-02-28	M	488	Sudan	f	f	TO
489	Alexandria	Richard	Alexandria	Richard	267	1802-06-19	1822-01-01	F	489	Niue	f	f	ZM
490	Craig	Blake	Craig	Blake	846	1808-09-26	1828-01-18	M	490	Pitcairn	f	f	DC
491	Jonathan	Alvarado	Jonathan	Alvarado	1106	1807-01-17	1827-12-27	F	491	Jamaica	f	f	JT
492	Steven	Miranda	Steven	Miranda	842	1803-08-27	1823-05-25	M	492	Cambodia	f	f	LI
493	Dennis	Wiggins	Dennis	Wiggins	972	1804-05-20	1824-01-17	F	493	Georgia	f	f	XX
494	Elizabeth	Bailey	Elizabeth	Bailey	644	1808-09-17	1828-10-10	M	494	Namibia	f	f	ST
495	Cheryl	Henry	Cheryl	Henry	736	1802-12-14	1822-11-28	F	495	Monaco	f	f	AT
496	Jacqueline	Bailey	Jacqueline	Bailey	1218	1808-04-18	1828-10-20	M	496	Taiwan	f	f	OT
497	Ashley	Baker	Ashley	Baker	191	1808-08-07	1828-02-14	F	497	Liechtenstein	f	f	JW
498	Kenneth	Williams	Kenneth	Williams	520	1807-12-14	1827-08-23	M	498	Gambia	f	f	GA
499	Donald	Mejia	Donald	Mejia	452	1808-11-24	1828-06-03	F	499	Palau	f	f	ND
500					307	1803-07-01	1823-11-15	M	500	Tuvalu	f	f	XM
\.


--
-- Data for Name: marriage_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriage_certificates (id, marriage_id, issuer, issue_date) FROM stdin;
1	1	238	1981-07-27
2	2	378	1958-01-23
3	3	762	1962-09-08
4	4	1043	1936-08-26
5	5	2	1933-12-15
6	6	426	1935-06-08
7	7	775	1936-11-17
8	8	907	1908-06-09
9	9	327	1910-07-06
10	10	397	1911-06-26
11	11	766	1909-06-27
12	12	674	1906-11-26
13	13	818	1913-07-18
14	14	399	1911-01-23
15	15	1124	1912-09-02
16	16	206	1887-07-13
17	17	948	1886-09-24
18	18	1028	1885-04-05
19	19	1167	1887-01-13
20	20	1066	1885-12-16
21	21	778	1886-09-04
22	22	1188	1885-04-28
23	23	986	1883-10-08
24	24	785	1883-12-04
25	25	398	1885-10-14
26	26	607	1883-02-05
27	27	1219	1884-04-13
28	28	225	1886-02-18
29	29	311	1888-06-25
30	30	1031	1887-12-03
31	31	421	1883-03-27
32	32	665	1863-09-14
33	33	1086	1863-11-12
34	34	745	1860-03-13
35	35	860	1861-11-22
36	36	500	1859-04-07
37	37	1140	1860-06-17
38	38	980	1857-10-04
39	39	1211	1861-12-02
40	40	1193	1860-06-02
41	41	908	1862-09-05
42	42	980	1859-04-19
43	43	722	1863-05-03
44	44	556	1858-03-20
45	45	311	1857-05-24
46	46	517	1862-12-26
47	47	588	1860-03-28
48	48	1018	1859-04-10
49	49	634	1861-12-21
50	50	813	1858-02-03
51	51	1200	1858-01-18
52	52	409	1861-04-26
53	53	310	1862-12-03
54	54	845	1862-11-15
55	55	713	1858-07-06
56	56	905	1859-11-15
57	57	75	1861-09-23
58	58	811	1859-12-20
59	59	587	1861-09-05
60	60	1058	1862-12-16
61	61	464	1858-10-13
62	62	850	1863-11-08
63	63	864	1862-05-11
64	64	434	1837-09-12
65	65	718	1831-03-12
66	66	766	1835-03-06
67	67	1051	1836-05-04
68	68	141	1835-06-02
69	69	1066	1836-10-28
70	70	355	1838-02-01
71	71	452	1838-07-16
72	72	1025	1831-10-28
73	73	756	1835-04-04
74	74	402	1836-12-09
75	75	378	1833-04-09
76	76	543	1836-06-03
77	77	781	1837-07-14
78	78	937	1837-07-02
79	79	193	1831-03-05
80	80	905	1836-03-24
81	81	800	1835-02-05
82	82	387	1833-01-25
83	83	917	1834-10-08
84	84	714	1831-03-25
85	85	1234	1833-07-14
86	86	1247	1831-07-06
87	87	226	1834-08-17
88	88	63	1836-12-09
89	89	1127	1831-09-11
90	90	1122	1835-11-03
91	91	135	1838-09-16
92	92	933	1831-03-28
93	93	491	1833-02-14
94	94	850	1837-05-23
95	95	792	1835-12-04
96	96	704	1835-05-20
97	97	335	1838-07-07
98	98	944	1833-10-20
99	99	416	1832-06-16
100	100	755	1834-09-06
101	101	378	1831-10-28
102	102	209	1838-12-13
103	103	644	1833-06-20
104	104	1227	1832-03-05
105	105	321	1832-10-04
106	106	1150	1837-06-09
107	107	720	1834-07-27
108	108	784	1833-03-28
109	109	1008	1833-08-10
110	110	115	1832-12-17
111	111	548	1833-03-18
112	112	990	1833-01-22
113	113	757	1838-05-01
114	114	225	1831-06-13
115	115	573	1833-12-12
116	116	35	1836-02-22
117	117	103	1835-10-10
118	118	910	1837-09-27
119	119	797	1835-10-09
120	120	525	1833-09-16
121	121	107	1832-12-06
122	122	590	1832-09-22
123	123	234	1837-07-08
124	124	1085	1834-08-21
125	125	716	1835-01-12
126	126	775	1836-05-23
127	127	793	1835-05-04
128	128	295	1810-07-04
129	129	1169	1809-11-02
130	130	415	1811-03-18
131	131	310	1812-02-03
132	132	211	1809-02-04
133	133	1112	1813-01-15
134	134	1147	1808-09-24
135	135	774	1811-10-09
136	136	726	1806-07-28
137	137	1170	1806-07-17
138	138	351	1809-01-27
139	139	953	1811-07-19
140	140	857	1810-12-20
141	141	1223	1813-07-28
142	142	822	1812-11-11
143	143	734	1810-12-13
144	144	366	1812-12-20
145	145	902	1806-10-05
146	146	489	1811-02-05
147	147	85	1808-09-07
148	148	296	1808-10-16
149	149	121	1813-01-12
150	150	1188	1811-03-05
151	151	290	1808-11-17
152	152	711	1809-10-03
153	153	219	1809-03-28
154	154	121	1806-08-08
155	155	355	1810-08-21
156	156	743	1806-04-25
157	157	992	1813-03-23
158	158	960	1809-06-24
159	159	142	1808-01-09
160	160	816	1811-10-17
161	161	669	1813-03-23
162	162	538	1813-03-28
163	163	1027	1811-06-17
164	164	610	1813-04-09
165	165	162	1809-02-12
166	166	554	1812-01-03
167	167	643	1807-01-02
168	168	276	1806-03-20
169	169	647	1810-10-06
170	170	52	1812-01-01
171	171	548	1807-05-04
172	172	694	1806-10-25
173	173	72	1807-03-03
174	174	85	1810-11-15
175	175	876	1806-05-20
176	176	936	1808-05-02
177	177	700	1812-12-05
178	178	538	1813-07-08
179	179	784	1809-12-01
180	180	1158	1806-07-27
181	181	656	1808-02-17
182	182	141	1811-11-13
183	183	1066	1813-11-17
184	184	1166	1806-07-09
185	185	32	1812-01-21
186	186	282	1812-01-23
187	187	142	1810-05-07
188	188	523	1810-08-28
189	189	314	1810-07-06
190	190	510	1811-07-11
191	191	557	1811-06-12
192	192	361	1811-01-17
193	193	755	1806-05-13
194	194	1160	1813-03-20
195	195	1	1813-05-17
196	196	376	1806-12-20
197	197	66	1809-07-15
198	198	366	1809-07-04
199	199	332	1808-03-03
200	200	784	1810-08-06
201	201	446	1808-05-06
202	202	1049	1813-03-20
203	203	553	1811-04-20
204	204	1127	1812-01-10
205	205	1014	1811-11-05
206	206	1157	1806-03-05
207	207	83	1811-11-10
208	208	1044	1812-03-01
209	209	614	1812-07-18
210	210	1109	1806-02-20
211	211	193	1808-12-09
212	212	992	1808-01-25
213	213	567	1809-08-09
214	214	1222	1813-08-12
215	215	792	1811-09-07
216	216	276	1807-09-12
217	217	250	1812-10-20
218	218	326	1810-12-27
219	219	589	1811-02-16
220	220	147	1807-07-14
221	221	591	1813-11-15
222	222	445	1812-05-04
223	223	657	1810-02-06
224	224	1107	1811-04-21
225	225	678	1812-01-14
226	226	113	1807-02-23
227	227	673	1812-12-03
228	228	117	1806-02-24
229	229	1016	1811-12-07
230	230	276	1806-10-22
231	231	354	1811-03-20
232	232	901	1809-08-06
233	233	775	1810-11-23
234	234	917	1807-10-11
235	235	33	1808-10-19
236	236	953	1807-11-22
237	237	1006	1809-12-05
238	238	515	1806-12-16
239	239	1169	1807-10-02
240	240	177	1811-08-06
241	241	631	1809-09-18
242	242	937	1812-04-02
243	243	1124	1808-11-19
244	244	1024	1807-12-14
245	245	1187	1807-10-24
246	246	649	1813-03-17
247	247	187	1807-05-03
248	248	272	1808-10-08
249	249	866	1812-11-15
\.


--
-- Data for Name: marriages; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriages (id, person1, person2, marriage_date) FROM stdin;
1	2	3	1981-07-27
2	4	5	1958-01-23
3	6	7	1962-09-08
4	8	9	1936-08-26
5	10	11	1933-12-15
6	12	13	1935-06-08
7	14	15	1936-11-17
8	16	17	1908-06-09
9	18	19	1910-07-06
10	20	21	1911-06-26
11	22	23	1909-06-27
12	24	25	1906-11-26
13	26	27	1913-07-18
14	28	29	1911-01-23
15	30	31	1912-09-02
16	32	33	1887-07-13
17	34	35	1886-09-24
18	36	37	1885-04-05
19	38	39	1887-01-13
20	40	41	1885-12-16
21	42	43	1886-09-04
22	44	45	1885-04-28
23	46	47	1883-10-08
24	48	49	1883-12-04
25	50	51	1885-10-14
26	52	53	1883-02-05
27	54	55	1884-04-13
28	56	57	1886-02-18
29	58	59	1888-06-25
30	60	61	1887-12-03
31	62	63	1883-03-27
32	64	65	1863-09-14
33	66	67	1863-11-12
34	68	69	1860-03-13
35	70	71	1861-11-22
36	72	73	1859-04-07
37	74	75	1860-06-17
38	76	77	1857-10-04
39	78	79	1861-12-02
40	80	81	1860-06-02
41	82	83	1862-09-05
42	84	85	1859-04-19
43	86	87	1863-05-03
44	88	89	1858-03-20
45	90	91	1857-05-24
46	92	93	1862-12-26
47	94	95	1860-03-28
48	96	97	1859-04-10
49	98	99	1861-12-21
50	100	101	1858-02-03
51	102	103	1858-01-18
52	104	105	1861-04-26
53	106	107	1862-12-03
54	108	109	1862-11-15
55	110	111	1858-07-06
56	112	113	1859-11-15
57	114	115	1861-09-23
58	116	117	1859-12-20
59	118	119	1861-09-05
60	120	121	1862-12-16
61	122	123	1858-10-13
62	124	125	1863-11-08
63	126	127	1862-05-11
64	128	129	1837-09-12
65	130	131	1831-03-12
66	132	133	1835-03-06
67	134	135	1836-05-04
68	136	137	1835-06-02
69	138	139	1836-10-28
70	140	141	1838-02-01
71	142	143	1838-07-16
72	144	145	1831-10-28
73	146	147	1835-04-04
74	148	149	1836-12-09
75	150	151	1833-04-09
76	152	153	1836-06-03
77	154	155	1837-07-14
78	156	157	1837-07-02
79	158	159	1831-03-05
80	160	161	1836-03-24
81	162	163	1835-02-05
82	164	165	1833-01-25
83	166	167	1834-10-08
84	168	169	1831-03-25
85	170	171	1833-07-14
86	172	173	1831-07-06
87	174	175	1834-08-17
88	176	177	1836-12-09
89	178	179	1831-09-11
90	180	181	1835-11-03
91	182	183	1838-09-16
92	184	185	1831-03-28
93	186	187	1833-02-14
94	188	189	1837-05-23
95	190	191	1835-12-04
96	192	193	1835-05-20
97	194	195	1838-07-07
98	196	197	1833-10-20
99	198	199	1832-06-16
100	200	201	1834-09-06
101	202	203	1831-10-28
102	204	205	1838-12-13
103	206	207	1833-06-20
104	208	209	1832-03-05
105	210	211	1832-10-04
106	212	213	1837-06-09
107	214	215	1834-07-27
108	216	217	1833-03-28
109	218	219	1833-08-10
110	220	221	1832-12-17
111	222	223	1833-03-18
112	224	225	1833-01-22
113	226	227	1838-05-01
114	228	229	1831-06-13
115	230	231	1833-12-12
116	232	233	1836-02-22
117	234	235	1835-10-10
118	236	237	1837-09-27
119	238	239	1835-10-09
120	240	241	1833-09-16
121	242	243	1832-12-06
122	244	245	1832-09-22
123	246	247	1837-07-08
124	248	249	1834-08-21
125	250	251	1835-01-12
126	252	253	1836-05-23
127	254	255	1835-05-04
128	256	257	1810-07-04
129	258	259	1809-11-02
130	260	261	1811-03-18
131	262	263	1812-02-03
132	264	265	1809-02-04
133	266	267	1813-01-15
134	268	269	1808-09-24
135	270	271	1811-10-09
136	272	273	1806-07-28
137	274	275	1806-07-17
138	276	277	1809-01-27
139	278	279	1811-07-19
140	280	281	1810-12-20
141	282	283	1813-07-28
142	284	285	1812-11-11
143	286	287	1810-12-13
144	288	289	1812-12-20
145	290	291	1806-10-05
146	292	293	1811-02-05
147	294	295	1808-09-07
148	296	297	1808-10-16
149	298	299	1813-01-12
150	300	301	1811-03-05
151	302	303	1808-11-17
152	304	305	1809-10-03
153	306	307	1809-03-28
154	308	309	1806-08-08
155	310	311	1810-08-21
156	312	313	1806-04-25
157	314	315	1813-03-23
158	316	317	1809-06-24
159	318	319	1808-01-09
160	320	321	1811-10-17
161	322	323	1813-03-23
162	324	325	1813-03-28
163	326	327	1811-06-17
164	328	329	1813-04-09
165	330	331	1809-02-12
166	332	333	1812-01-03
167	334	335	1807-01-02
168	336	337	1806-03-20
169	338	339	1810-10-06
170	340	341	1812-01-01
171	342	343	1807-05-04
172	344	345	1806-10-25
173	346	347	1807-03-03
174	348	349	1810-11-15
175	350	351	1806-05-20
176	352	353	1808-05-02
177	354	355	1812-12-05
178	356	357	1813-07-08
179	358	359	1809-12-01
180	360	361	1806-07-27
181	362	363	1808-02-17
182	364	365	1811-11-13
183	366	367	1813-11-17
184	368	369	1806-07-09
185	370	371	1812-01-21
186	372	373	1812-01-23
187	374	375	1810-05-07
188	376	377	1810-08-28
189	378	379	1810-07-06
190	380	381	1811-07-11
191	382	383	1811-06-12
192	384	385	1811-01-17
193	386	387	1806-05-13
194	388	389	1813-03-20
195	390	391	1813-05-17
196	392	393	1806-12-20
197	394	395	1809-07-15
198	396	397	1809-07-04
199	398	399	1808-03-03
200	400	401	1810-08-06
201	402	403	1808-05-06
202	404	405	1813-03-20
203	406	407	1811-04-20
204	408	409	1812-01-10
205	410	411	1811-11-05
206	412	413	1806-03-05
207	414	415	1811-11-10
208	416	417	1812-03-01
209	418	419	1812-07-18
210	420	421	1806-02-20
211	422	423	1808-12-09
212	424	425	1808-01-25
213	426	427	1809-08-09
214	428	429	1813-08-12
215	430	431	1811-09-07
216	432	433	1807-09-12
217	434	435	1812-10-20
218	436	437	1810-12-27
219	438	439	1811-02-16
220	440	441	1807-07-14
221	442	443	1813-11-15
222	444	445	1812-05-04
223	446	447	1810-02-06
224	448	449	1811-04-21
225	450	451	1812-01-14
226	452	453	1807-02-23
227	454	455	1812-12-03
228	456	457	1806-02-24
229	458	459	1811-12-07
230	460	461	1806-10-22
231	462	463	1811-03-20
232	464	465	1809-08-06
233	466	467	1810-11-23
234	468	469	1807-10-11
235	470	471	1808-10-19
236	472	473	1807-11-22
237	474	475	1809-12-05
238	476	477	1806-12-16
239	478	479	1807-10-02
240	480	481	1811-08-06
241	482	483	1809-09-18
242	484	485	1812-04-02
243	486	487	1808-11-19
244	488	489	1807-12-14
245	490	491	1807-10-24
246	492	493	1813-03-17
247	494	495	1807-05-03
248	496	497	1808-10-08
249	498	499	1812-11-15
\.


--
-- Data for Name: office_kinds_documents; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.office_kinds_documents (document_id, kind_id) FROM stdin;
4	4
5	4
6	2
7	3
1	1
2	2
8	1
10	5
3	1
\.


--
-- Data for Name: offices; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices (id, name, country, address, city) FROM stdin;
1	Balkh's office	Afghanistan	Afghanistan Balkh	Balkh
2	Charikar's office	Afghanistan	Afghanistan Charikar	Charikar
3	Farah's office	Afghanistan	Afghanistan Farah	Farah
4	Fayzabad's office	Afghanistan	Afghanistan Fayzabad	Fayzabad
5	Gereshk's office	Afghanistan	Afghanistan Gereshk	Gereshk
6	Ghazni's office	Afghanistan	Afghanistan Ghazni	Ghazni
7	Ghormach's office	Afghanistan	Afghanistan Ghormach	Ghormach
8	Kabul's office	Afghanistan	Afghanistan Kabul	Kabul
9	Karukh's office	Afghanistan	Afghanistan Karukh	Karukh
10	Khanabad's office	Afghanistan	Afghanistan Khanabad	Khanabad
11	Berat's office	Albania	Albania Berat	Berat
12	Burrel's office	Albania	Albania Burrel	Burrel
13	Elbasan's office	Albania	Albania Elbasan	Elbasan
14	Fier's office	Albania	Albania Fier	Fier
15	Tirana's office	Albania	Albania Tirana	Tirana
16	Adrar's office	Algeria	Algeria Adrar	Adrar
17	Aflou's office	Algeria	Algeria Aflou	Aflou
18	Akbou's office	Algeria	Algeria Akbou	Akbou
19	Algiers's office	Algeria	Algeria Algiers	Algiers
20	Amizour's office	Algeria	Algeria Amizour	Amizour
21	Annaba's office	Algeria	Algeria Annaba	Annaba
22	Aoulef's office	Algeria	Algeria Aoulef	Aoulef
23	Arbatache's office	Algeria	Algeria Arbatache	Arbatache
24	Arhribs's office	Algeria	Algeria Arhribs	Arhribs
25	Arris's office	Algeria	Algeria Arris	Arris
26	Benguela's office	Angola	Angola Benguela	Benguela
27	Cabinda's office	Angola	Angola Cabinda	Cabinda
28	Caluquembe's office	Angola	Angola Caluquembe	Caluquembe
29	Camacupa's office	Angola	Angola Camacupa	Camacupa
30	Catabola's office	Angola	Angola Catabola	Catabola
31	Catumbela's office	Angola	Angola Catumbela	Catumbela
32	Caxito's office	Angola	Angola Caxito	Caxito
33	Cuito's office	Angola	Angola Cuito	Cuito
34	Huambo's office	Angola	Angola Huambo	Huambo
35	Lobito's office	Angola	Angola Lobito	Lobito
36	Aguilares's office	Argentina	Argentina Aguilares	Aguilares
37	Alderetes's office	Argentina	Argentina Alderetes	Alderetes
38	Allen's office	Argentina	Argentina Allen	Allen
39	Arroyito's office	Argentina	Argentina Arroyito	Arroyito
40	Avellaneda's office	Argentina	Argentina Avellaneda	Avellaneda
41	Azul's office	Argentina	Argentina Azul	Azul
42	Barranqueras's office	Argentina	Argentina Barranqueras	Barranqueras
43	Campana's office	Argentina	Argentina Campana	Campana
44	Casilda's office	Argentina	Argentina Casilda	Casilda
45	Castelli's office	Argentina	Argentina Castelli	Castelli
46	Abovyan's office	Armenia	Armenia Abovyan	Abovyan
47	Ararat's office	Armenia	Armenia Ararat	Ararat
48	Armavir's office	Armenia	Armenia Armavir	Armavir
49	Artashat's office	Armenia	Armenia Artashat	Artashat
50	Ashtarak's office	Armenia	Armenia Ashtarak	Ashtarak
51	Ejmiatsin's office	Armenia	Armenia Ejmiatsin	Ejmiatsin
52	Gavarr's office	Armenia	Armenia Gavarr	Gavarr
53	Goris's office	Armenia	Armenia Goris	Goris
54	Gyumri's office	Armenia	Armenia Gyumri	Gyumri
55	Hrazdan's office	Armenia	Armenia Hrazdan	Hrazdan
56	Angochi's office	Aruba	Aruba Angochi	Angochi
57	Babijn's office	Aruba	Aruba Babijn	Babijn
58	Oranjestad's office	Aruba	Aruba Oranjestad	Oranjestad
59	Adelaide's office	Australia	Australia Adelaide	Adelaide
60	Albany's office	Australia	Australia Albany	Albany
61	Albury's office	Australia	Australia Albury	Albury
62	Armadale's office	Australia	Australia Armadale	Armadale
63	Armidale's office	Australia	Australia Armidale	Armidale
64	Ashfield's office	Australia	Australia Ashfield	Ashfield
65	Auburn's office	Australia	Australia Auburn	Auburn
66	Ballarat's office	Australia	Australia Ballarat	Ballarat
67	Bankstown's office	Australia	Australia Bankstown	Bankstown
68	Bathurst's office	Australia	Australia Bathurst	Bathurst
69	Amstetten's office	Austria	Austria Amstetten	Amstetten
70	Ansfelden's office	Austria	Austria Ansfelden	Ansfelden
71	Baden's office	Austria	Austria Baden	Baden
72	Bregenz's office	Austria	Austria Bregenz	Bregenz
73	Dornbirn's office	Austria	Austria Dornbirn	Dornbirn
74	Feldkirch's office	Austria	Austria Feldkirch	Feldkirch
75	Graz's office	Austria	Austria Graz	Graz
76	Hallein's office	Austria	Austria Hallein	Hallein
77	Innsbruck's office	Austria	Austria Innsbruck	Innsbruck
78	Kapfenberg's office	Austria	Austria Kapfenberg	Kapfenberg
79	Agdzhabedy's office	Azerbaijan	Azerbaijan Agdzhabedy	Agdzhabedy
80	Aghsu's office	Azerbaijan	Azerbaijan Aghsu	Aghsu
81	Amirdzhan's office	Azerbaijan	Azerbaijan Amirdzhan	Amirdzhan
82	Astara's office	Azerbaijan	Azerbaijan Astara	Astara
83	Baku's office	Azerbaijan	Azerbaijan Baku	Baku
84	Barda's office	Azerbaijan	Azerbaijan Barda	Barda
85	Beylagan's office	Azerbaijan	Azerbaijan Beylagan	Beylagan
86	Bilajari's office	Azerbaijan	Azerbaijan Bilajari	Bilajari
87	Buzovna's office	Azerbaijan	Azerbaijan Buzovna	Buzovna
88	Divichibazar's office	Azerbaijan	Azerbaijan Divichibazar	Divichibazar
89	Freeport's office	Bahamas	Bahamas Freeport	Freeport
90	Lucaya's office	Bahamas	Bahamas Lucaya	Lucaya
91	Nassau's office	Bahamas	Bahamas Nassau	Nassau
92	Manama's office	Bahrain	Bahrain Manama	Manama
93	Sitrah's office	Bahrain	Bahrain Sitrah	Sitrah
94	Azimpur's office	Bangladesh	Bangladesh Azimpur	Azimpur
95	Badarganj's office	Bangladesh	Bangladesh Badarganj	Badarganj
96	Baniachang's office	Bangladesh	Bangladesh Baniachang	Baniachang
97	Bera's office	Bangladesh	Bangladesh Bera	Bera
98	Bhola's office	Bangladesh	Bangladesh Bhola	Bhola
99	Bogra's office	Bangladesh	Bangladesh Bogra	Bogra
100	Chittagong's office	Bangladesh	Bangladesh Chittagong	Chittagong
101	Comilla's office	Bangladesh	Bangladesh Comilla	Comilla
102	Dhaka's office	Bangladesh	Bangladesh Dhaka	Dhaka
103	Fatikchari's office	Bangladesh	Bangladesh Fatikchari	Fatikchari
104	Bridgetown's office	Barbados	Barbados Bridgetown	Bridgetown
105	Asipovichy's office	Belarus	Belarus Asipovichy	Asipovichy
106	Babruysk's office	Belarus	Belarus Babruysk	Babruysk
107	Baranovichi's office	Belarus	Belarus Baranovichi	Baranovichi
108	Brest's office	Belarus	Belarus Brest	Brest
109	Byaroza's office	Belarus	Belarus Byaroza	Byaroza
110	Bykhaw's office	Belarus	Belarus Bykhaw	Bykhaw
111	Dobrush's office	Belarus	Belarus Dobrush	Dobrush
112	Dzyarzhynsk's office	Belarus	Belarus Dzyarzhynsk	Dzyarzhynsk
113	Gomel's office	Belarus	Belarus Gomel	Gomel
114	Hlybokaye's office	Belarus	Belarus Hlybokaye	Hlybokaye
115	Aalst's office	Belgium	Belgium Aalst	Aalst
116	Aalter's office	Belgium	Belgium Aalter	Aalter
117	Aarschot's office	Belgium	Belgium Aarschot	Aarschot
118	Andenne's office	Belgium	Belgium Andenne	Andenne
119	Ans's office	Belgium	Belgium Ans	Ans
120	Antwerpen's office	Belgium	Belgium Antwerpen	Antwerpen
121	Arlon's office	Belgium	Belgium Arlon	Arlon
122	Asse's office	Belgium	Belgium Asse	Asse
123	Ath's office	Belgium	Belgium Ath	Ath
124	Balen's office	Belgium	Belgium Balen	Balen
125	Belmopan's office	Belize	Belize Belmopan	Belmopan
126	Abomey's office	Benin	Benin Abomey	Abomey
127	Allada's office	Benin	Benin Allada	Allada
128	Banikoara's office	Benin	Benin Banikoara	Banikoara
129	Bassila's office	Benin	Benin Bassila	Bassila
130	Bohicon's office	Benin	Benin Bohicon	Bohicon
131	Cotonou's office	Benin	Benin Cotonou	Cotonou
132	Djougou's office	Benin	Benin Djougou	Djougou
133	Dogbo's office	Benin	Benin Dogbo	Dogbo
134	Kandi's office	Benin	Benin Kandi	Kandi
135	Lokossa's office	Benin	Benin Lokossa	Lokossa
136	Hamilton's office	Bermuda	Bermuda Hamilton	Hamilton
137	Phuntsholing's office	Bhutan	Bhutan Phuntsholing	Phuntsholing
138	Thimphu's office	Bhutan	Bhutan Thimphu	Thimphu
139	Tsirang's office	Bhutan	Bhutan Tsirang	Tsirang
140	Camiri's office	Bolivia	Bolivia Camiri	Camiri
141	Cobija's office	Bolivia	Bolivia Cobija	Cobija
142	Cochabamba's office	Bolivia	Bolivia Cochabamba	Cochabamba
143	Cotoca's office	Bolivia	Bolivia Cotoca	Cotoca
144	Huanuni's office	Bolivia	Bolivia Huanuni	Huanuni
145	Llallagua's office	Bolivia	Bolivia Llallagua	Llallagua
146	Mizque's office	Bolivia	Bolivia Mizque	Mizque
147	Montero's office	Bolivia	Bolivia Montero	Montero
148	Oruro's office	Bolivia	Bolivia Oruro	Oruro
149	Punata's office	Bolivia	Bolivia Punata	Punata
150	Francistown's office	Botswana	Botswana Francistown	Francistown
151	Gaborone's office	Botswana	Botswana Gaborone	Gaborone
152	Janeng's office	Botswana	Botswana Janeng	Janeng
153	Kanye's office	Botswana	Botswana Kanye	Kanye
154	Letlhakane's office	Botswana	Botswana Letlhakane	Letlhakane
155	Lobatse's office	Botswana	Botswana Lobatse	Lobatse
156	Mahalapye's office	Botswana	Botswana Mahalapye	Mahalapye
157	Maun's office	Botswana	Botswana Maun	Maun
158	Mochudi's office	Botswana	Botswana Mochudi	Mochudi
159	Mogoditshane's office	Botswana	Botswana Mogoditshane	Mogoditshane
160	Abaetetuba's office	Brazil	Brazil Abaetetuba	Abaetetuba
161	Acopiara's office	Brazil	Brazil Acopiara	Acopiara
162	Adamantina's office	Brazil	Brazil Adamantina	Adamantina
163	Agudos's office	Brazil	Brazil Agudos	Agudos
164	Alagoinhas's office	Brazil	Brazil Alagoinhas	Alagoinhas
165	Alegre's office	Brazil	Brazil Alegre	Alegre
166	Alegrete's office	Brazil	Brazil Alegrete	Alegrete
167	Alenquer's office	Brazil	Brazil Alenquer	Alenquer
168	Alfenas's office	Brazil	Brazil Alfenas	Alfenas
169	Almeirim's office	Brazil	Brazil Almeirim	Almeirim
170	Seria's office	Brunei	Brunei Seria	Seria
171	Tutong's office	Brunei	Brunei Tutong	Tutong
172	Asenovgrad's office	Bulgaria	Bulgaria Asenovgrad	Asenovgrad
173	Aytos's office	Bulgaria	Bulgaria Aytos	Aytos
174	Berkovitsa's office	Bulgaria	Bulgaria Berkovitsa	Berkovitsa
175	Blagoevgrad's office	Bulgaria	Bulgaria Blagoevgrad	Blagoevgrad
176	Botevgrad's office	Bulgaria	Bulgaria Botevgrad	Botevgrad
177	Burgas's office	Bulgaria	Bulgaria Burgas	Burgas
178	Chirpan's office	Bulgaria	Bulgaria Chirpan	Chirpan
179	Dimitrovgrad's office	Bulgaria	Bulgaria Dimitrovgrad	Dimitrovgrad
180	Dobrich's office	Bulgaria	Bulgaria Dobrich	Dobrich
181	Dupnitsa's office	Bulgaria	Bulgaria Dupnitsa	Dupnitsa
182	Bujumbura's office	Burundi	Burundi Bujumbura	Bujumbura
183	Bururi's office	Burundi	Burundi Bururi	Bururi
184	Gitega's office	Burundi	Burundi Gitega	Gitega
185	Kayanza's office	Burundi	Burundi Kayanza	Kayanza
186	Makamba's office	Burundi	Burundi Makamba	Makamba
187	Muramvya's office	Burundi	Burundi Muramvya	Muramvya
188	Muyinga's office	Burundi	Burundi Muyinga	Muyinga
189	Ngozi's office	Burundi	Burundi Ngozi	Ngozi
190	Rutana's office	Burundi	Burundi Rutana	Rutana
191	Ruyigi's office	Burundi	Burundi Ruyigi	Ruyigi
192	Battambang's office	Cambodia	Cambodia Battambang	Battambang
193	Kampot's office	Cambodia	Cambodia Kampot	Kampot
194	Pailin's office	Cambodia	Cambodia Pailin	Pailin
195	Pursat's office	Cambodia	Cambodia Pursat	Pursat
196	Sihanoukville's office	Cambodia	Cambodia Sihanoukville	Sihanoukville
197	Takeo's office	Cambodia	Cambodia Takeo	Takeo
198	Akonolinga's office	Cameroon	Cameroon Akonolinga	Akonolinga
199	Bafang's office	Cameroon	Cameroon Bafang	Bafang
200	Bafia's office	Cameroon	Cameroon Bafia	Bafia
201	Bafoussam's office	Cameroon	Cameroon Bafoussam	Bafoussam
202	Bali's office	Cameroon	Cameroon Bali	Bali
203	Bamenda's office	Cameroon	Cameroon Bamenda	Bamenda
204	Bamusso's office	Cameroon	Cameroon Bamusso	Bamusso
205	Banyo's office	Cameroon	Cameroon Banyo	Banyo
206	Batouri's office	Cameroon	Cameroon Batouri	Batouri
207	Bertoua's office	Cameroon	Cameroon Bertoua	Bertoua
208	Abbotsford's office	Canada	Canada Abbotsford	Abbotsford
209	Airdrie's office	Canada	Canada Airdrie	Airdrie
210	Ajax's office	Canada	Canada Ajax	Ajax
211	Alma's office	Canada	Canada Alma	Alma
212	Amos's office	Canada	Canada Amos	Amos
213	Ancaster's office	Canada	Canada Ancaster	Ancaster
214	Anmore's office	Canada	Canada Anmore	Anmore
215	Barrie's office	Canada	Canada Barrie	Barrie
216	Beaconsfield's office	Canada	Canada Beaconsfield	Beaconsfield
217	Belleville's office	Canada	Canada Belleville	Belleville
218	Ati's office	Chad	Chad Ati	Ati
219	Benoy's office	Chad	Chad Benoy	Benoy
220	Bitkine's office	Chad	Chad Bitkine	Bitkine
221	Bongor's office	Chad	Chad Bongor	Bongor
222	Doba's office	Chad	Chad Doba	Doba
223	Dourbali's office	Chad	Chad Dourbali	Dourbali
224	Fada's office	Chad	Chad Fada	Fada
225	Kelo's office	Chad	Chad Kelo	Kelo
226	Koumra's office	Chad	Chad Koumra	Koumra
227	Mao's office	Chad	Chad Mao	Mao
228	Ancud's office	Chile	Chile Ancud	Ancud
229	Angol's office	Chile	Chile Angol	Angol
230	Antofagasta's office	Chile	Chile Antofagasta	Antofagasta
231	Arauco's office	Chile	Chile Arauco	Arauco
232	Arica's office	Chile	Chile Arica	Arica
233	Buin's office	Chile	Chile Buin	Buin
234	Cabrero's office	Chile	Chile Cabrero	Cabrero
235	Calama's office	Chile	Chile Calama	Calama
236	Cartagena's office	Chile	Chile Cartagena	Cartagena
237	Castro's office	Chile	Chile Castro	Castro
238	Acheng's office	China	China Acheng	Acheng
239	Altay's office	China	China Altay	Altay
240	Anbu's office	China	China Anbu	Anbu
241	Anda's office	China	China Anda	Anda
242	Anjiang's office	China	China Anjiang	Anjiang
243	Ankang's office	China	China Ankang	Ankang
244	Anlu's office	China	China Anlu	Anlu
245	Anqing's office	China	China Anqing	Anqing
246	Anqiu's office	China	China Anqiu	Anqiu
247	Anshan's office	China	China Anshan	Anshan
248	Aguachica's office	Colombia	Colombia Aguachica	Aguachica
249	Aguadas's office	Colombia	Colombia Aguadas	Aguadas
250	Aguazul's office	Colombia	Colombia Aguazul	Aguazul
251	Andes's office	Colombia	Colombia Andes	Andes
252	Anserma's office	Colombia	Colombia Anserma	Anserma
253	Aracataca's office	Colombia	Colombia Aracataca	Aracataca
254	Arauca's office	Colombia	Colombia Arauca	Arauca
255	Arjona's office	Colombia	Colombia Arjona	Arjona
256	Armenia's office	Colombia	Colombia Armenia	Armenia
257	Ayapel's office	Colombia	Colombia Ayapel	Ayapel
258	Moroni's office	Comoros	Comoros Moroni	Moroni
259	Moutsamoudou's office	Comoros	Comoros Moutsamoudou	Moutsamoudou
260	Bjelovar's office	Croatia	Croatia Bjelovar	Bjelovar
261	Dubrovnik's office	Croatia	Croatia Dubrovnik	Dubrovnik
262	Karlovac's office	Croatia	Croatia Karlovac	Karlovac
263	Koprivnica's office	Croatia	Croatia Koprivnica	Koprivnica
264	Osijek's office	Croatia	Croatia Osijek	Osijek
265	Pula's office	Croatia	Croatia Pula	Pula
266	Rijeka's office	Croatia	Croatia Rijeka	Rijeka
267	Samobor's office	Croatia	Croatia Samobor	Samobor
268	Sesvete's office	Croatia	Croatia Sesvete	Sesvete
269	Sisak's office	Croatia	Croatia Sisak	Sisak
270	Abreus's office	Cuba	Cuba Abreus	Abreus
271	Alamar's office	Cuba	Cuba Alamar	Alamar
272	Amancio's office	Cuba	Cuba Amancio	Amancio
273	Artemisa's office	Cuba	Cuba Artemisa	Artemisa
274	Banes's office	Cuba	Cuba Banes	Banes
275	Baracoa's office	Cuba	Cuba Baracoa	Baracoa
276	Bauta's office	Cuba	Cuba Bauta	Bauta
277	Bayamo's office	Cuba	Cuba Bayamo	Bayamo
278	Bejucal's office	Cuba	Cuba Bejucal	Bejucal
279	Boyeros's office	Cuba	Cuba Boyeros	Boyeros
280	Willemstad's office	Curacao	Curacao Willemstad	Willemstad
281	Famagusta's office	Cyprus	Cyprus Famagusta	Famagusta
282	Kyrenia's office	Cyprus	Cyprus Kyrenia	Kyrenia
283	Larnaca's office	Cyprus	Cyprus Larnaca	Larnaca
284	Limassol's office	Cyprus	Cyprus Limassol	Limassol
285	Nicosia's office	Cyprus	Cyprus Nicosia	Nicosia
286	Paphos's office	Cyprus	Cyprus Paphos	Paphos
287	Protaras's office	Cyprus	Cyprus Protaras	Protaras
288	Aabenraa's office	Denmark	Denmark Aabenraa	Aabenraa
289	Aalborg's office	Denmark	Denmark Aalborg	Aalborg
290	Albertslund's office	Denmark	Denmark Albertslund	Albertslund
291	Ballerup's office	Denmark	Denmark Ballerup	Ballerup
292	Charlottenlund's office	Denmark	Denmark Charlottenlund	Charlottenlund
293	Copenhagen's office	Denmark	Denmark Copenhagen	Copenhagen
294	Esbjerg's office	Denmark	Denmark Esbjerg	Esbjerg
295	Farum's office	Denmark	Denmark Farum	Farum
296	Fredericia's office	Denmark	Denmark Fredericia	Fredericia
297	Frederiksberg's office	Denmark	Denmark Frederiksberg	Frederiksberg
298	Djibouti's office	Djibouti	Djibouti Djibouti	Djibouti
299	Obock's office	Djibouti	Djibouti Obock	Obock
300	Tadjoura's office	Djibouti	Djibouti Tadjoura	Tadjoura
301	Roseau's office	Dominica	Dominica Roseau	Roseau
302	Ambato's office	Ecuador	Ecuador Ambato	Ambato
303	Atuntaqui's office	Ecuador	Ecuador Atuntaqui	Atuntaqui
304	Azogues's office	Ecuador	Ecuador Azogues	Azogues
305	Babahoyo's office	Ecuador	Ecuador Babahoyo	Babahoyo
306	Balzar's office	Ecuador	Ecuador Balzar	Balzar
307	Calceta's office	Ecuador	Ecuador Calceta	Calceta
308	Cariamanga's office	Ecuador	Ecuador Cariamanga	Cariamanga
309	Catamayo's office	Ecuador	Ecuador Catamayo	Catamayo
310	Cayambe's office	Ecuador	Ecuador Cayambe	Cayambe
311	Chone's office	Ecuador	Ecuador Chone	Chone
312	Alexandria's office	Egypt	Egypt Alexandria	Alexandria
313	Arish's office	Egypt	Egypt Arish	Arish
314	Aswan's office	Egypt	Egypt Aswan	Aswan
315	Bilbays's office	Egypt	Egypt Bilbays	Bilbays
316	Cairo's office	Egypt	Egypt Cairo	Cairo
317	Damietta's office	Egypt	Egypt Damietta	Damietta
318	Dikirnis's office	Egypt	Egypt Dikirnis	Dikirnis
319	Fuwwah's office	Egypt	Egypt Fuwwah	Fuwwah
320	Hurghada's office	Egypt	Egypt Hurghada	Hurghada
321	Ismailia's office	Egypt	Egypt Ismailia	Ismailia
322	Asmara's office	Eritrea	Eritrea Asmara	Asmara
323	Assab's office	Eritrea	Eritrea Assab	Assab
324	Barentu's office	Eritrea	Eritrea Barentu	Barentu
325	Keren's office	Eritrea	Eritrea Keren	Keren
326	Massawa's office	Eritrea	Eritrea Massawa	Massawa
327	Mendefera's office	Eritrea	Eritrea Mendefera	Mendefera
328	Maardu's office	Estonia	Estonia Maardu	Maardu
329	Narva's office	Estonia	Estonia Narva	Narva
330	Rakvere's office	Estonia	Estonia Rakvere	Rakvere
331	Tallinn's office	Estonia	Estonia Tallinn	Tallinn
332	Tartu's office	Estonia	Estonia Tartu	Tartu
333	Viljandi's office	Estonia	Estonia Viljandi	Viljandi
334	Abomsa's office	Ethiopia	Ethiopia Abomsa	Abomsa
335	Asaita's office	Ethiopia	Ethiopia Asaita	Asaita
336	Axum's office	Ethiopia	Ethiopia Axum	Axum
337	Bako's office	Ethiopia	Ethiopia Bako	Bako
338	Bichena's office	Ethiopia	Ethiopia Bichena	Bichena
339	Bishoftu's office	Ethiopia	Ethiopia Bishoftu	Bishoftu
340	Bonga's office	Ethiopia	Ethiopia Bonga	Bonga
341	Dodola's office	Ethiopia	Ethiopia Dodola	Dodola
342	Dubti's office	Ethiopia	Ethiopia Dubti	Dubti
343	Gelemso's office	Ethiopia	Ethiopia Gelemso	Gelemso
344	Labasa's office	Fiji	Fiji Labasa	Labasa
345	Lautoka's office	Fiji	Fiji Lautoka	Lautoka
346	Nadi's office	Fiji	Fiji Nadi	Nadi
347	Suva's office	Fiji	Fiji Suva	Suva
348	Anjala's office	Finland	Finland Anjala	Anjala
349	Espoo's office	Finland	Finland Espoo	Espoo
350	Forssa's office	Finland	Finland Forssa	Forssa
351	Hamina's office	Finland	Finland Hamina	Hamina
352	Haukipudas's office	Finland	Finland Haukipudas	Haukipudas
353	Heinola's office	Finland	Finland Heinola	Heinola
354	Helsinki's office	Finland	Finland Helsinki	Helsinki
355	Hollola's office	Finland	Finland Hollola	Hollola
356	Hyvinge's office	Finland	Finland Hyvinge	Hyvinge
357	Iisalmi's office	Finland	Finland Iisalmi	Iisalmi
358	Abbeville's office	France	France Abbeville	Abbeville
359	Agde's office	France	France Agde	Agde
360	Agen's office	France	France Agen	Agen
361	Ajaccio's office	France	France Ajaccio	Ajaccio
362	Albertville's office	France	France Albertville	Albertville
363	Albi's office	France	France Albi	Albi
364	Alfortville's office	France	France Alfortville	Alfortville
365	Allauch's office	France	France Allauch	Allauch
366	Amiens's office	France	France Amiens	Amiens
367	Angers's office	France	France Angers	Angers
368	Franceville's office	Gabon	Gabon Franceville	Franceville
369	Koulamoutou's office	Gabon	Gabon Koulamoutou	Koulamoutou
370	Libreville's office	Gabon	Gabon Libreville	Libreville
371	Moanda's office	Gabon	Gabon Moanda	Moanda
372	Mouila's office	Gabon	Gabon Mouila	Mouila
373	Oyem's office	Gabon	Gabon Oyem	Oyem
374	Tchibanga's office	Gabon	Gabon Tchibanga	Tchibanga
375	Bakau's office	Gambia	Gambia Bakau	Bakau
376	Banjul's office	Gambia	Gambia Banjul	Banjul
377	Brikama's office	Gambia	Gambia Brikama	Brikama
378	Farafenni's office	Gambia	Gambia Farafenni	Farafenni
379	Lamin's office	Gambia	Gambia Lamin	Lamin
380	Sukuta's office	Gambia	Gambia Sukuta	Sukuta
381	Akhaltsikhe's office	Georgia	Georgia Akhaltsikhe	Akhaltsikhe
382	Batumi's office	Georgia	Georgia Batumi	Batumi
383	Gori's office	Georgia	Georgia Gori	Gori
384	Khashuri's office	Georgia	Georgia Khashuri	Khashuri
385	Kobuleti's office	Georgia	Georgia Kobuleti	Kobuleti
386	Kutaisi's office	Georgia	Georgia Kutaisi	Kutaisi
387	Marneuli's office	Georgia	Georgia Marneuli	Marneuli
388	Ozurgeti's office	Georgia	Georgia Ozurgeti	Ozurgeti
389	Samtredia's office	Georgia	Georgia Samtredia	Samtredia
390	Sokhumi's office	Georgia	Georgia Sokhumi	Sokhumi
391	Aachen's office	Germany	Germany Aachen	Aachen
392	Aalen's office	Germany	Germany Aalen	Aalen
393	Achern's office	Germany	Germany Achern	Achern
394	Achim's office	Germany	Germany Achim	Achim
395	Adlershof's office	Germany	Germany Adlershof	Adlershof
396	Ahaus's office	Germany	Germany Ahaus	Ahaus
397	Ahlen's office	Germany	Germany Ahlen	Ahlen
398	Ahrensburg's office	Germany	Germany Ahrensburg	Ahrensburg
399	Aichach's office	Germany	Germany Aichach	Aichach
400	Albstadt's office	Germany	Germany Albstadt	Albstadt
401	Aburi's office	Ghana	Ghana Aburi	Aburi
402	Accra's office	Ghana	Ghana Accra	Accra
403	Achiaman's office	Ghana	Ghana Achiaman	Achiaman
404	Agogo's office	Ghana	Ghana Agogo	Agogo
405	Akwatia's office	Ghana	Ghana Akwatia	Akwatia
406	Anloga's office	Ghana	Ghana Anloga	Anloga
407	Apam's office	Ghana	Ghana Apam	Apam
408	Asamankese's office	Ghana	Ghana Asamankese	Asamankese
409	Axim's office	Ghana	Ghana Axim	Axim
410	Bawku's office	Ghana	Ghana Bawku	Bawku
411	Gibraltar's office	Gibraltar	Gibraltar Gibraltar	Gibraltar
412	Athens's office	Greece	Greece Athens	Athens
413	Chios's office	Greece	Greece Chios	Chios
414	Corfu's office	Greece	Greece Corfu	Corfu
415	Kos's office	Greece	Greece Kos	Kos
416	Piraeus's office	Greece	Greece Piraeus	Piraeus
417	Rethymno's office	Greece	Greece Rethymno	Rethymno
418	Vrilissia's office	Greece	Greece Vrilissia	Vrilissia
419	Nuuk's office	Greenland	Greenland Nuuk	Nuuk
420	Alotenango's office	Guatemala	Guatemala Alotenango	Alotenango
421	Barberena's office	Guatemala	Guatemala Barberena	Barberena
422	Cantel's office	Guatemala	Guatemala Cantel	Cantel
423	Chicacao's office	Guatemala	Guatemala Chicacao	Chicacao
424	Chichicastenango's office	Guatemala	Guatemala Chichicastenango	Chichicastenango
425	Chimaltenango's office	Guatemala	Guatemala Chimaltenango	Chimaltenango
426	Chinautla's office	Guatemala	Guatemala Chinautla	Chinautla
427	Chiquimula's office	Guatemala	Guatemala Chiquimula	Chiquimula
428	Chisec's office	Guatemala	Guatemala Chisec	Chisec
429	Coatepeque's office	Guatemala	Guatemala Coatepeque	Coatepeque
430	Camayenne's office	Guinea	Guinea Camayenne	Camayenne
431	Conakry's office	Guinea	Guinea Conakry	Conakry
432	Coyah's office	Guinea	Guinea Coyah	Coyah
433	Fria's office	Guinea	Guinea Fria	Fria
434	Gueckedou's office	Guinea	Guinea Gueckedou	Gueckedou
435	Kamsar's office	Guinea	Guinea Kamsar	Kamsar
436	Kankan's office	Guinea	Guinea Kankan	Kankan
437	Kindia's office	Guinea	Guinea Kindia	Kindia
438	Kissidougou's office	Guinea	Guinea Kissidougou	Kissidougou
439	Macenta's office	Guinea	Guinea Macenta	Macenta
440	Georgetown's office	Guyana	Guyana Georgetown	Georgetown
441	Linden's office	Guyana	Guyana Linden	Linden
442	Carrefour's office	Haiti	Haiti Carrefour	Carrefour
443	Gonayiv's office	Haiti	Haiti Gonayiv	Gonayiv
444	Grangwav's office	Haiti	Haiti Grangwav	Grangwav
445	Gressier's office	Haiti	Haiti Gressier	Gressier
446	Hinche's office	Haiti	Haiti Hinche	Hinche
447	Jacmel's office	Haiti	Haiti Jacmel	Jacmel
448	Kenscoff's office	Haiti	Haiti Kenscoff	Kenscoff
449	Lenbe's office	Haiti	Haiti Lenbe	Lenbe
450	Okap's office	Haiti	Haiti Okap	Okap
451	Thomazeau's office	Haiti	Haiti Thomazeau	Thomazeau
452	Choloma's office	Honduras	Honduras Choloma	Choloma
453	Comayagua's office	Honduras	Honduras Comayagua	Comayagua
454	Juticalpa's office	Honduras	Honduras Juticalpa	Juticalpa
455	Olanchito's office	Honduras	Honduras Olanchito	Olanchito
456	Potrerillos's office	Honduras	Honduras Potrerillos	Potrerillos
457	Siguatepeque's office	Honduras	Honduras Siguatepeque	Siguatepeque
458	Tegucigalpa's office	Honduras	Honduras Tegucigalpa	Tegucigalpa
459	Tela's office	Honduras	Honduras Tela	Tela
460	Tocoa's office	Honduras	Honduras Tocoa	Tocoa
461	Villanueva's office	Honduras	Honduras Villanueva	Villanueva
462	Abony's office	Hungary	Hungary Abony	Abony
463	Ajka's office	Hungary	Hungary Ajka	Ajka
464	Baja's office	Hungary	Hungary Baja	Baja
465	Balassagyarmat's office	Hungary	Hungary Balassagyarmat	Balassagyarmat
466	Budapest's office	Hungary	Hungary Budapest	Budapest
467	Dabas's office	Hungary	Hungary Dabas	Dabas
468	Debrecen's office	Hungary	Hungary Debrecen	Debrecen
469	Dunaharaszti's office	Hungary	Hungary Dunaharaszti	Dunaharaszti
470	Dunakeszi's office	Hungary	Hungary Dunakeszi	Dunakeszi
471	Eger's office	Hungary	Hungary Eger	Eger
472	Akureyri's office	Iceland	Iceland Akureyri	Akureyri
473	Abohar's office	India	India Abohar	Abohar
474	Achalpur's office	India	India Achalpur	Achalpur
475	Achhnera's office	India	India Achhnera	Achhnera
476	Addanki's office	India	India Addanki	Addanki
477	Adirampattinam's office	India	India Adirampattinam	Adirampattinam
478	Adra's office	India	India Adra	Adra
479	Afzalgarh's office	India	India Afzalgarh	Afzalgarh
480	Afzalpur's office	India	India Afzalpur	Afzalpur
481	Agar's office	India	India Agar	Agar
482	Agartala's office	India	India Agartala	Agartala
483	Abepura's office	Indonesia	Indonesia Abepura	Abepura
484	Adiwerna's office	Indonesia	Indonesia Adiwerna	Adiwerna
485	Amahai's office	Indonesia	Indonesia Amahai	Amahai
486	Ambarawa's office	Indonesia	Indonesia Ambarawa	Ambarawa
487	Ambon's office	Indonesia	Indonesia Ambon	Ambon
488	Amuntai's office	Indonesia	Indonesia Amuntai	Amuntai
489	Arjawinangun's office	Indonesia	Indonesia Arjawinangun	Arjawinangun
490	Astanajapura's office	Indonesia	Indonesia Astanajapura	Astanajapura
491	Atambua's office	Indonesia	Indonesia Atambua	Atambua
492	Babat's office	Indonesia	Indonesia Babat	Babat
493	Abadan's office	Iran	Iran Abadan	Abadan
494	Abhar's office	Iran	Iran Abhar	Abhar
495	Aghajari's office	Iran	Iran Aghajari	Aghajari
496	Ahar's office	Iran	Iran Ahar	Ahar
497	Ahvaz's office	Iran	Iran Ahvaz	Ahvaz
498	Aleshtar's office	Iran	Iran Aleshtar	Aleshtar
499	Alvand's office	Iran	Iran Alvand	Alvand
500	Bam's office	Iran	Iran Bam	Bam
501	Behshahr's office	Iran	Iran Behshahr	Behshahr
502	Chabahar's office	Iran	Iran Chabahar	Chabahar
503	Baghdad's office	Iraq	Iraq Baghdad	Baghdad
504	Balad's office	Iraq	Iraq Balad	Balad
505	Baqubah's office	Iraq	Iraq Baqubah	Baqubah
506	Basrah's office	Iraq	Iraq Basrah	Basrah
507	Baynjiwayn's office	Iraq	Iraq Baynjiwayn	Baynjiwayn
508	Dihok's office	Iraq	Iraq Dihok	Dihok
509	Erbil's office	Iraq	Iraq Erbil	Erbil
510	Karbala's office	Iraq	Iraq Karbala	Karbala
511	Kirkuk's office	Iraq	Iraq Kirkuk	Kirkuk
512	Koysinceq's office	Iraq	Iraq Koysinceq	Koysinceq
513	Athlone's office	Ireland	Ireland Athlone	Athlone
514	Balbriggan's office	Ireland	Ireland Balbriggan	Balbriggan
515	Blanchardstown's office	Ireland	Ireland Blanchardstown	Blanchardstown
516	Carlow's office	Ireland	Ireland Carlow	Carlow
517	Celbridge's office	Ireland	Ireland Celbridge	Celbridge
518	Cork's office	Ireland	Ireland Cork	Cork
519	Donaghmede's office	Ireland	Ireland Donaghmede	Donaghmede
520	Drogheda's office	Ireland	Ireland Drogheda	Drogheda
521	Dublin's office	Ireland	Ireland Dublin	Dublin
522	Dundalk's office	Ireland	Ireland Dundalk	Dundalk
523	Ariel's office	Israel	Israel Ariel	Ariel
524	Ashdod's office	Israel	Israel Ashdod	Ashdod
525	Ashqelon's office	Israel	Israel Ashqelon	Ashqelon
526	Beersheba's office	Israel	Israel Beersheba	Beersheba
527	Dimona's office	Israel	Israel Dimona	Dimona
528	Eilat's office	Israel	Israel Eilat	Eilat
529	Haifa's office	Israel	Israel Haifa	Haifa
530	Herzliyya's office	Israel	Israel Herzliyya	Herzliyya
531	Jerusalem's office	Israel	Israel Jerusalem	Jerusalem
532	Lod's office	Israel	Israel Lod	Lod
533	Abbiategrasso's office	Italy	Italy Abbiategrasso	Abbiategrasso
534	Acerra's office	Italy	Italy Acerra	Acerra
535	Acireale's office	Italy	Italy Acireale	Acireale
536	Adelfia's office	Italy	Italy Adelfia	Adelfia
537	Adrano's office	Italy	Italy Adrano	Adrano
538	Afragola's office	Italy	Italy Afragola	Afragola
539	Agrigento's office	Italy	Italy Agrigento	Agrigento
540	Agropoli's office	Italy	Italy Agropoli	Agropoli
541	Alba's office	Italy	Italy Alba	Alba
542	Albenga's office	Italy	Italy Albenga	Albenga
543	Kingston's office	Jamaica	Jamaica Kingston	Kingston
544	Linstead's office	Jamaica	Jamaica Linstead	Linstead
545	Mandeville's office	Jamaica	Jamaica Mandeville	Mandeville
546	Portmore's office	Jamaica	Jamaica Portmore	Portmore
547	Abashiri's office	Japan	Japan Abashiri	Abashiri
548	Abiko's office	Japan	Japan Abiko	Abiko
549	Ageoshimo's office	Japan	Japan Ageoshimo	Ageoshimo
550	Aioi's office	Japan	Japan Aioi	Aioi
551	Akashi's office	Japan	Japan Akashi	Akashi
552	Aki's office	Japan	Japan Aki	Aki
553	Akita's office	Japan	Japan Akita	Akita
554	Akitashi's office	Japan	Japan Akitashi	Akitashi
555	Akune's office	Japan	Japan Akune	Akune
556	Amagasaki's office	Japan	Japan Amagasaki	Amagasaki
557	Amman's office	Jordan	Jordan Amman	Amman
558	Aqaba's office	Jordan	Jordan Aqaba	Aqaba
559	Irbid's office	Jordan	Jordan Irbid	Irbid
560	Jarash's office	Jordan	Jordan Jarash	Jarash
561	Judita's office	Jordan	Jordan Judita	Judita
562	Kurayyimah's office	Jordan	Jordan Kurayyimah	Kurayyimah
563	Mafraq's office	Jordan	Jordan Mafraq	Mafraq
564	Russeifa's office	Jordan	Jordan Russeifa	Russeifa
565	Safi's office	Jordan	Jordan Safi	Safi
566	Zarqa's office	Jordan	Jordan Zarqa	Zarqa
567	Abay's office	Kazakhstan	Kazakhstan Abay	Abay
568	Aksu's office	Kazakhstan	Kazakhstan Aksu	Aksu
569	Aktau's office	Kazakhstan	Kazakhstan Aktau	Aktau
570	Almaty's office	Kazakhstan	Kazakhstan Almaty	Almaty
571	Aqsay's office	Kazakhstan	Kazakhstan Aqsay	Aqsay
572	Aral's office	Kazakhstan	Kazakhstan Aral	Aral
573	Arkalyk's office	Kazakhstan	Kazakhstan Arkalyk	Arkalyk
574	Arys's office	Kazakhstan	Kazakhstan Arys	Arys
575	Astana's office	Kazakhstan	Kazakhstan Astana	Astana
576	Atbasar's office	Kazakhstan	Kazakhstan Atbasar	Atbasar
577	Bungoma's office	Kenya	Kenya Bungoma	Bungoma
578	Busia's office	Kenya	Kenya Busia	Busia
579	Eldoret's office	Kenya	Kenya Eldoret	Eldoret
580	Embu's office	Kenya	Kenya Embu	Embu
581	Garissa's office	Kenya	Kenya Garissa	Garissa
582	Isiolo's office	Kenya	Kenya Isiolo	Isiolo
583	Kabarnet's office	Kenya	Kenya Kabarnet	Kabarnet
584	Kakamega's office	Kenya	Kenya Kakamega	Kakamega
585	Kapenguria's office	Kenya	Kenya Kapenguria	Kapenguria
586	Karuri's office	Kenya	Kenya Karuri	Karuri
587	Tarawa's office	Kiribati	Kiribati Tarawa	Tarawa
588	Dragash's office	Kosovo	Kosovo Dragash	Dragash
589	Ferizaj's office	Kosovo	Kosovo Ferizaj	Ferizaj
590	Gjilan's office	Kosovo	Kosovo Gjilan	Gjilan
591	Glogovac's office	Kosovo	Kosovo Glogovac	Glogovac
592	Istok's office	Kosovo	Kosovo Istok	Istok
593	Leposaviq's office	Kosovo	Kosovo Leposaviq	Leposaviq
594	Orahovac's office	Kosovo	Kosovo Orahovac	Orahovac
595	Podujeva's office	Kosovo	Kosovo Podujeva	Podujeva
596	Pristina's office	Kosovo	Kosovo Pristina	Pristina
597	Prizren's office	Kosovo	Kosovo Prizren	Prizren
598	Balykchy's office	Kyrgyzstan	Kyrgyzstan Balykchy	Balykchy
599	Bishkek's office	Kyrgyzstan	Kyrgyzstan Bishkek	Bishkek
600	Iradan's office	Kyrgyzstan	Kyrgyzstan Iradan	Iradan
601	Isfana's office	Kyrgyzstan	Kyrgyzstan Isfana	Isfana
602	Kant's office	Kyrgyzstan	Kyrgyzstan Kant	Kant
603	Karakol's office	Kyrgyzstan	Kyrgyzstan Karakol	Karakol
604	Naryn's office	Kyrgyzstan	Kyrgyzstan Naryn	Naryn
605	Osh's office	Kyrgyzstan	Kyrgyzstan Osh	Osh
606	Suluktu's office	Kyrgyzstan	Kyrgyzstan Suluktu	Suluktu
607	Talas's office	Kyrgyzstan	Kyrgyzstan Talas	Talas
608	Phonsavan's office	Laos	Laos Phonsavan	Phonsavan
609	Vangviang's office	Laos	Laos Vangviang	Vangviang
610	Vientiane's office	Laos	Laos Vientiane	Vientiane
611	Daugavpils's office	Latvia	Latvia Daugavpils	Daugavpils
612	Jelgava's office	Latvia	Latvia Jelgava	Jelgava
613	Ogre's office	Latvia	Latvia Ogre	Ogre
614	Riga's office	Latvia	Latvia Riga	Riga
615	Salaspils's office	Latvia	Latvia Salaspils	Salaspils
616	Tukums's office	Latvia	Latvia Tukums	Tukums
617	Valmiera's office	Latvia	Latvia Valmiera	Valmiera
618	Ventspils's office	Latvia	Latvia Ventspils	Ventspils
619	Baalbek's office	Lebanon	Lebanon Baalbek	Baalbek
620	Beirut's office	Lebanon	Lebanon Beirut	Beirut
621	Djounie's office	Lebanon	Lebanon Djounie	Djounie
622	Sidon's office	Lebanon	Lebanon Sidon	Sidon
623	Tripoli's office	Lebanon	Lebanon Tripoli	Tripoli
624	Tyre's office	Lebanon	Lebanon Tyre	Tyre
625	Leribe's office	Lesotho	Lesotho Leribe	Leribe
626	Mafeteng's office	Lesotho	Lesotho Mafeteng	Mafeteng
627	Maputsoe's office	Lesotho	Lesotho Maputsoe	Maputsoe
628	Maseru's office	Lesotho	Lesotho Maseru	Maseru
629	Quthing's office	Lesotho	Lesotho Quthing	Quthing
630	Bensonville's office	Liberia	Liberia Bensonville	Bensonville
631	Buchanan's office	Liberia	Liberia Buchanan	Buchanan
632	Gbarnga's office	Liberia	Liberia Gbarnga	Gbarnga
633	Greenville's office	Liberia	Liberia Greenville	Greenville
634	Harper's office	Liberia	Liberia Harper	Harper
635	Kakata's office	Liberia	Liberia Kakata	Kakata
636	Monrovia's office	Liberia	Liberia Monrovia	Monrovia
637	Voinjama's office	Liberia	Liberia Voinjama	Voinjama
638	Zwedru's office	Liberia	Liberia Zwedru	Zwedru
639	Ajdabiya's office	Libya	Libya Ajdabiya	Ajdabiya
640	Benghazi's office	Libya	Libya Benghazi	Benghazi
641	Brak's office	Libya	Libya Brak	Brak
642	Darnah's office	Libya	Libya Darnah	Darnah
643	Gharyan's office	Libya	Libya Gharyan	Gharyan
644	Ghat's office	Libya	Libya Ghat	Ghat
645	Mizdah's office	Libya	Libya Mizdah	Mizdah
646	Murzuq's office	Libya	Libya Murzuq	Murzuq
647	Sirte's office	Libya	Libya Sirte	Sirte
648	Tagiura's office	Libya	Libya Tagiura	Tagiura
649	Vaduz's office	Liechtenstein	Liechtenstein Vaduz	Vaduz
650	Aleksotas's office	Lithuania	Lithuania Aleksotas	Aleksotas
651	Alytus's office	Lithuania	Lithuania Alytus	Alytus
652	Druskininkai's office	Lithuania	Lithuania Druskininkai	Druskininkai
653	Eiguliai's office	Lithuania	Lithuania Eiguliai	Eiguliai
654	Jonava's office	Lithuania	Lithuania Jonava	Jonava
655	Kaunas's office	Lithuania	Lithuania Kaunas	Kaunas
656	Kretinga's office	Lithuania	Lithuania Kretinga	Kretinga
657	Lazdynai's office	Lithuania	Lithuania Lazdynai	Lazdynai
658	Mazeikiai's office	Lithuania	Lithuania Mazeikiai	Mazeikiai
659	Naujamiestis's office	Lithuania	Lithuania Naujamiestis	Naujamiestis
660	Dudelange's office	Luxembourg	Luxembourg Dudelange	Dudelange
661	Luxembourg's office	Luxembourg	Luxembourg Luxembourg	Luxembourg
662	Macau's office	Macao	Macao Macau	Macau
663	Bitola's office	Macedonia	Macedonia Bitola	Bitola
664	Bogovinje's office	Macedonia	Macedonia Bogovinje	Bogovinje
665	Brvenica's office	Macedonia	Macedonia Brvenica	Brvenica
666	Butel's office	Macedonia	Macedonia Butel	Butel
667	Debar's office	Macedonia	Macedonia Debar	Debar
668	Delcevo's office	Macedonia	Macedonia Delcevo	Delcevo
669	Gevgelija's office	Macedonia	Macedonia Gevgelija	Gevgelija
670	Gostivar's office	Macedonia	Macedonia Gostivar	Gostivar
671	Ilinden's office	Macedonia	Macedonia Ilinden	Ilinden
672	Kamenjane's office	Macedonia	Macedonia Kamenjane	Kamenjane
673	Alarobia's office	Madagascar	Madagascar Alarobia	Alarobia
674	Ambalavao's office	Madagascar	Madagascar Ambalavao	Ambalavao
675	Ambanja's office	Madagascar	Madagascar Ambanja	Ambanja
676	Ambarakaraka's office	Madagascar	Madagascar Ambarakaraka	Ambarakaraka
677	Ambatofinandrahana's office	Madagascar	Madagascar Ambatofinandrahana	Ambatofinandrahana
678	Ambatolampy's office	Madagascar	Madagascar Ambatolampy	Ambatolampy
679	Ambatondrazaka's office	Madagascar	Madagascar Ambatondrazaka	Ambatondrazaka
680	Ambilobe's office	Madagascar	Madagascar Ambilobe	Ambilobe
681	Amboanjo's office	Madagascar	Madagascar Amboanjo	Amboanjo
682	Amboasary's office	Madagascar	Madagascar Amboasary	Amboasary
683	Balaka's office	Malawi	Malawi Balaka	Balaka
684	Blantyre's office	Malawi	Malawi Blantyre	Blantyre
685	Dedza's office	Malawi	Malawi Dedza	Dedza
686	Karonga's office	Malawi	Malawi Karonga	Karonga
687	Kasungu's office	Malawi	Malawi Kasungu	Kasungu
688	Lilongwe's office	Malawi	Malawi Lilongwe	Lilongwe
689	Liwonde's office	Malawi	Malawi Liwonde	Liwonde
690	Mangochi's office	Malawi	Malawi Mangochi	Mangochi
691	Mchinji's office	Malawi	Malawi Mchinji	Mchinji
692	Mulanje's office	Malawi	Malawi Mulanje	Mulanje
693	Bahau's office	Malaysia	Malaysia Bahau	Bahau
694	Bakri's office	Malaysia	Malaysia Bakri	Bakri
695	Banting's office	Malaysia	Malaysia Banting	Banting
696	Beaufort's office	Malaysia	Malaysia Beaufort	Beaufort
697	Bedong's office	Malaysia	Malaysia Bedong	Bedong
698	Bidur's office	Malaysia	Malaysia Bidur	Bidur
699	Bintulu's office	Malaysia	Malaysia Bintulu	Bintulu
700	Butterworth's office	Malaysia	Malaysia Butterworth	Butterworth
701	Cukai's office	Malaysia	Malaysia Cukai	Cukai
702	Donggongon's office	Malaysia	Malaysia Donggongon	Donggongon
703	Male's office	Maldives	Maldives Male	Male
704	Bamako's office	Mali	Mali Bamako	Bamako
705	Banamba's office	Mali	Mali Banamba	Banamba
706	Bougouni's office	Mali	Mali Bougouni	Bougouni
707	Gao's office	Mali	Mali Gao	Gao
708	Kangaba's office	Mali	Mali Kangaba	Kangaba
709	Kati's office	Mali	Mali Kati	Kati
710	Kayes's office	Mali	Mali Kayes	Kayes
711	Kolokani's office	Mali	Mali Kolokani	Kolokani
712	Koulikoro's office	Mali	Mali Koulikoro	Koulikoro
713	Koutiala's office	Mali	Mali Koutiala	Koutiala
714	Birkirkara's office	Malta	Malta Birkirkara	Birkirkara
715	Mosta's office	Malta	Malta Mosta	Mosta
716	Qormi's office	Malta	Malta Qormi	Qormi
717	Valletta's office	Malta	Malta Valletta	Valletta
718	Ducos's office	Martinique	Martinique Ducos	Ducos
719	Aleg's office	Mauritania	Mauritania Aleg	Aleg
720	Atar's office	Mauritania	Mauritania Atar	Atar
721	Kiffa's office	Mauritania	Mauritania Kiffa	Kiffa
722	Nouakchott's office	Mauritania	Mauritania Nouakchott	Nouakchott
723	Rosso's office	Mauritania	Mauritania Rosso	Rosso
724	Zouerate's office	Mauritania	Mauritania Zouerate	Zouerate
725	Curepipe's office	Mauritius	Mauritius Curepipe	Curepipe
726	Goodlands's office	Mauritius	Mauritius Goodlands	Goodlands
727	Triolet's office	Mauritius	Mauritius Triolet	Triolet
728	Vacoas's office	Mauritius	Mauritius Vacoas	Vacoas
729	Dzaoudzi's office	Mayotte	Mayotte Dzaoudzi	Dzaoudzi
730	Koungou's office	Mayotte	Mayotte Koungou	Koungou
731	Mamoudzou's office	Mayotte	Mayotte Mamoudzou	Mamoudzou
732	Abasolo's office	Mexico	Mexico Abasolo	Abasolo
733	Acajete's office	Mexico	Mexico Acajete	Acajete
734	Acaponeta's office	Mexico	Mexico Acaponeta	Acaponeta
735	Acayucan's office	Mexico	Mexico Acayucan	Acayucan
736	Actopan's office	Mexico	Mexico Actopan	Actopan
737	Aguascalientes's office	Mexico	Mexico Aguascalientes	Aguascalientes
738	Ajalpan's office	Mexico	Mexico Ajalpan	Ajalpan
739	Allende's office	Mexico	Mexico Allende	Allende
740	Altamira's office	Mexico	Mexico Altamira	Altamira
741	Altepexi's office	Mexico	Mexico Altepexi	Altepexi
742	Bender's office	Moldova	Moldova Bender	Bender
743	Cahul's office	Moldova	Moldova Cahul	Cahul
744	Comrat's office	Moldova	Moldova Comrat	Comrat
745	Drochia's office	Moldova	Moldova Drochia	Drochia
746	Orhei's office	Moldova	Moldova Orhei	Orhei
747	Slobozia's office	Moldova	Moldova Slobozia	Slobozia
748	Soroca's office	Moldova	Moldova Soroca	Soroca
749	Tiraspolul's office	Moldova	Moldova Tiraspolul	Tiraspolul
750	Ungheni's office	Moldova	Moldova Ungheni	Ungheni
751	Monaco's office	Monaco	Monaco Monaco	Monaco
752	Altai's office	Mongolia	Mongolia Altai	Altai
753	Arvayheer's office	Mongolia	Mongolia Arvayheer	Arvayheer
754	Bayanhongor's office	Mongolia	Mongolia Bayanhongor	Bayanhongor
755	Bulgan's office	Mongolia	Mongolia Bulgan	Bulgan
756	Dalandzadgad's office	Mongolia	Mongolia Dalandzadgad	Dalandzadgad
757	Darhan's office	Mongolia	Mongolia Darhan	Darhan
758	Erdenet's office	Mongolia	Mongolia Erdenet	Erdenet
759	Hovd's office	Mongolia	Mongolia Hovd	Hovd
760	Khovd's office	Mongolia	Mongolia Khovd	Khovd
761	Mandalgovi's office	Mongolia	Mongolia Mandalgovi	Mandalgovi
762	Bar's office	Montenegro	Montenegro Bar	Bar
763	Budva's office	Montenegro	Montenegro Budva	Budva
764	Cetinje's office	Montenegro	Montenegro Cetinje	Cetinje
765	Pljevlja's office	Montenegro	Montenegro Pljevlja	Pljevlja
766	Podgorica's office	Montenegro	Montenegro Podgorica	Podgorica
767	Brades's office	Montserrat	Montserrat Brades	Brades
768	Plymouth's office	Montserrat	Montserrat Plymouth	Plymouth
769	Agadir's office	Morocco	Morocco Agadir	Agadir
770	Ahfir's office	Morocco	Morocco Ahfir	Ahfir
771	Asilah's office	Morocco	Morocco Asilah	Asilah
772	Azemmour's office	Morocco	Morocco Azemmour	Azemmour
773	Azrou's office	Morocco	Morocco Azrou	Azrou
774	Berkane's office	Morocco	Morocco Berkane	Berkane
775	Berrechid's office	Morocco	Morocco Berrechid	Berrechid
776	Boujniba's office	Morocco	Morocco Boujniba	Boujniba
777	Bouznika's office	Morocco	Morocco Bouznika	Bouznika
778	Casablanca's office	Morocco	Morocco Casablanca	Casablanca
779	Beira's office	Mozambique	Mozambique Beira	Beira
780	Chibuto's office	Mozambique	Mozambique Chibuto	Chibuto
781	Chimoio's office	Mozambique	Mozambique Chimoio	Chimoio
782	Cuamba's office	Mozambique	Mozambique Cuamba	Cuamba
783	Dondo's office	Mozambique	Mozambique Dondo	Dondo
784	Inhambane's office	Mozambique	Mozambique Inhambane	Inhambane
785	Lichinga's office	Mozambique	Mozambique Lichinga	Lichinga
786	Macia's office	Mozambique	Mozambique Macia	Macia
787	Manjacaze's office	Mozambique	Mozambique Manjacaze	Manjacaze
788	Maputo's office	Mozambique	Mozambique Maputo	Maputo
789	Bago's office	Myanmar	Myanmar Bago	Bago
790	Bhamo's office	Myanmar	Myanmar Bhamo	Bhamo
791	Bogale's office	Myanmar	Myanmar Bogale	Bogale
792	Chauk's office	Myanmar	Myanmar Chauk	Chauk
793	Dawei's office	Myanmar	Myanmar Dawei	Dawei
794	Hakha's office	Myanmar	Myanmar Hakha	Hakha
795	Hinthada's office	Myanmar	Myanmar Hinthada	Hinthada
796	Kanbe's office	Myanmar	Myanmar Kanbe	Kanbe
797	Kayan's office	Myanmar	Myanmar Kayan	Kayan
798	Kyaikkami's office	Myanmar	Myanmar Kyaikkami	Kyaikkami
799	Gobabis's office	Namibia	Namibia Gobabis	Gobabis
800	Grootfontein's office	Namibia	Namibia Grootfontein	Grootfontein
801	Keetmanshoop's office	Namibia	Namibia Keetmanshoop	Keetmanshoop
802	Okahandja's office	Namibia	Namibia Okahandja	Okahandja
803	Oshakati's office	Namibia	Namibia Oshakati	Oshakati
804	Otjiwarongo's office	Namibia	Namibia Otjiwarongo	Otjiwarongo
805	Rehoboth's office	Namibia	Namibia Rehoboth	Rehoboth
806	Rundu's office	Namibia	Namibia Rundu	Rundu
807	Swakopmund's office	Namibia	Namibia Swakopmund	Swakopmund
808	Windhoek's office	Namibia	Namibia Windhoek	Windhoek
809	Yaren's office	Nauru	Nauru Yaren	Yaren
810	Bhadrapur's office	Nepal	Nepal Bhadrapur	Bhadrapur
811	Bharatpur's office	Nepal	Nepal Bharatpur	Bharatpur
812	Birendranagar's office	Nepal	Nepal Birendranagar	Birendranagar
813	Dailekh's office	Nepal	Nepal Dailekh	Dailekh
814	Dhangarhi's office	Nepal	Nepal Dhangarhi	Dhangarhi
815	Dipayal's office	Nepal	Nepal Dipayal	Dipayal
816	Gaur's office	Nepal	Nepal Gaur	Gaur
817	Hetauda's office	Nepal	Nepal Hetauda	Hetauda
818	Ithari's office	Nepal	Nepal Ithari	Ithari
819	Jaleswar's office	Nepal	Nepal Jaleswar	Jaleswar
820	Aalsmeer's office	Netherlands	Netherlands Aalsmeer	Aalsmeer
821	Aalten's office	Netherlands	Netherlands Aalten	Aalten
822	Alblasserdam's office	Netherlands	Netherlands Alblasserdam	Alblasserdam
823	Alkmaar's office	Netherlands	Netherlands Alkmaar	Alkmaar
824	Almelo's office	Netherlands	Netherlands Almelo	Almelo
825	Amersfoort's office	Netherlands	Netherlands Amersfoort	Amersfoort
826	Amstelveen's office	Netherlands	Netherlands Amstelveen	Amstelveen
827	Amsterdam's office	Netherlands	Netherlands Amsterdam	Amsterdam
828	Anloo's office	Netherlands	Netherlands Anloo	Anloo
829	Apeldoorn's office	Netherlands	Netherlands Apeldoorn	Apeldoorn
830	Bluefields's office	Nicaragua	Nicaragua Bluefields	Bluefields
831	Boaco's office	Nicaragua	Nicaragua Boaco	Boaco
832	Camoapa's office	Nicaragua	Nicaragua Camoapa	Camoapa
833	Chichigalpa's office	Nicaragua	Nicaragua Chichigalpa	Chichigalpa
834	Chinandega's office	Nicaragua	Nicaragua Chinandega	Chinandega
835	Corinto's office	Nicaragua	Nicaragua Corinto	Corinto
836	Diriamba's office	Nicaragua	Nicaragua Diriamba	Diriamba
837	Granada's office	Nicaragua	Nicaragua Granada	Granada
838	Jalapa's office	Nicaragua	Nicaragua Jalapa	Jalapa
839	Jinotega's office	Nicaragua	Nicaragua Jinotega	Jinotega
840	Agadez's office	Niger	Niger Agadez	Agadez
841	Alaghsas's office	Niger	Niger Alaghsas	Alaghsas
842	Ayorou's office	Niger	Niger Ayorou	Ayorou
843	Dakoro's office	Niger	Niger Dakoro	Dakoro
844	Diffa's office	Niger	Niger Diffa	Diffa
845	Dogondoutchi's office	Niger	Niger Dogondoutchi	Dogondoutchi
846	Dosso's office	Niger	Niger Dosso	Dosso
847	Gaya's office	Niger	Niger Gaya	Gaya
848	Madaoua's office	Niger	Niger Madaoua	Madaoua
849	Magaria's office	Niger	Niger Magaria	Magaria
850	Aba's office	Nigeria	Nigeria Aba	Aba
851	Abakaliki's office	Nigeria	Nigeria Abakaliki	Abakaliki
852	Abeokuta's office	Nigeria	Nigeria Abeokuta	Abeokuta
853	Abuja's office	Nigeria	Nigeria Abuja	Abuja
854	Afikpo's office	Nigeria	Nigeria Afikpo	Afikpo
855	Agbor's office	Nigeria	Nigeria Agbor	Agbor
856	Agulu's office	Nigeria	Nigeria Agulu	Agulu
857	Ajaokuta's office	Nigeria	Nigeria Ajaokuta	Ajaokuta
858	Aku's office	Nigeria	Nigeria Aku	Aku
859	Akure's office	Nigeria	Nigeria Akure	Akure
860	Alofi's office	Niue	Niue Alofi	Alofi
861	Arendal's office	Norway	Norway Arendal	Arendal
862	Bergen's office	Norway	Norway Bergen	Bergen
863	Drammen's office	Norway	Norway Drammen	Drammen
864	Fredrikstad's office	Norway	Norway Fredrikstad	Fredrikstad
865	Halden's office	Norway	Norway Halden	Halden
866	Hamar's office	Norway	Norway Hamar	Hamar
867	Harstad's office	Norway	Norway Harstad	Harstad
868	Haugesund's office	Norway	Norway Haugesund	Haugesund
869	Horten's office	Norway	Norway Horten	Horten
870	Kongsberg's office	Norway	Norway Kongsberg	Kongsberg
871	Bawshar's office	Oman	Oman Bawshar	Bawshar
872	Bidbid's office	Oman	Oman Bidbid	Bidbid
873	Khasab's office	Oman	Oman Khasab	Khasab
874	Muscat's office	Oman	Oman Muscat	Muscat
875	Rustaq's office	Oman	Oman Rustaq	Rustaq
876	Seeb's office	Oman	Oman Seeb	Seeb
877	Sohar's office	Oman	Oman Sohar	Sohar
878	Sur's office	Oman	Oman Sur	Sur
879	Yanqul's office	Oman	Oman Yanqul	Yanqul
880	Akora's office	Pakistan	Pakistan Akora	Akora
881	Amangarh's office	Pakistan	Pakistan Amangarh	Amangarh
882	Baddomalhi's office	Pakistan	Pakistan Baddomalhi	Baddomalhi
883	Bannu's office	Pakistan	Pakistan Bannu	Bannu
884	Bela's office	Pakistan	Pakistan Bela	Bela
885	Bhakkar's office	Pakistan	Pakistan Bhakkar	Bhakkar
886	Bhera's office	Pakistan	Pakistan Bhera	Bhera
887	Bhimbar's office	Pakistan	Pakistan Bhimbar	Bhimbar
888	Chaman's office	Pakistan	Pakistan Chaman	Chaman
889	Charsadda's office	Pakistan	Pakistan Charsadda	Charsadda
890	Melekeok's office	Palau	Palau Melekeok	Melekeok
891	Aguadulce's office	Panama	Panama Aguadulce	Aguadulce
892	Changuinola's office	Panama	Panama Changuinola	Changuinola
893	Chepo's office	Panama	Panama Chepo	Chepo
894	Chilibre's office	Panama	Panama Chilibre	Chilibre
895	David's office	Panama	Panama David	David
896	Pacora's office	Panama	Panama Pacora	Pacora
897	Pedregal's office	Panama	Panama Pedregal	Pedregal
898	Tocumen's office	Panama	Panama Tocumen	Tocumen
899	Veracruz's office	Panama	Panama Veracruz	Veracruz
900	Limpio's office	Paraguay	Paraguay Limpio	Limpio
901	Nemby's office	Paraguay	Paraguay Nemby	Nemby
902	Pilar's office	Paraguay	Paraguay Pilar	Pilar
903	Villarrica's office	Paraguay	Paraguay Villarrica	Villarrica
904	Abancay's office	Peru	Peru Abancay	Abancay
905	Andahuaylas's office	Peru	Peru Andahuaylas	Andahuaylas
906	Arequipa's office	Peru	Peru Arequipa	Arequipa
907	Ayacucho's office	Peru	Peru Ayacucho	Ayacucho
908	Ayaviri's office	Peru	Peru Ayaviri	Ayaviri
909	Barranca's office	Peru	Peru Barranca	Barranca
910	Bellavista's office	Peru	Peru Bellavista	Bellavista
911	Cajamarca's office	Peru	Peru Cajamarca	Cajamarca
912	Callao's office	Peru	Peru Callao	Callao
913	Catacaos's office	Peru	Peru Catacaos	Catacaos
914	Abucay's office	Philippines	Philippines Abucay	Abucay
915	Abuyog's office	Philippines	Philippines Abuyog	Abuyog
916	Agoo's office	Philippines	Philippines Agoo	Agoo
917	Alabel's office	Philippines	Philippines Alabel	Alabel
918	Alaminos's office	Philippines	Philippines Alaminos	Alaminos
919	Aliaga's office	Philippines	Philippines Aliaga	Aliaga
920	Alicia's office	Philippines	Philippines Alicia	Alicia
921	Amadeo's office	Philippines	Philippines Amadeo	Amadeo
922	Angat's office	Philippines	Philippines Angat	Angat
923	Angono's office	Philippines	Philippines Angono	Angono
924	Adamstown's office	Pitcairn	Pitcairn Adamstown	Adamstown
925	Bartoszyce's office	Poland	Poland Bartoszyce	Bartoszyce
926	Rzeszow's office	Poland	Poland Rzeszow	Rzeszow
927	Bemowo's office	Poland	Poland Bemowo	Bemowo
928	Lodz's office	Poland	Poland Lodz	Lodz
929	Torun's office	Poland	Poland Torun	Torun
930	Bielany's office	Poland	Poland Bielany	Bielany
931	Bielawa's office	Poland	Poland Bielawa	Bielawa
932	Bochnia's office	Poland	Poland Bochnia	Bochnia
933	Bogatynia's office	Poland	Poland Bogatynia	Bogatynia
934	Braniewo's office	Poland	Poland Braniewo	Braniewo
935	Albufeira's office	Portugal	Portugal Albufeira	Albufeira
936	Alcabideche's office	Portugal	Portugal Alcabideche	Alcabideche
937	Almada's office	Portugal	Portugal Almada	Almada
938	Amadora's office	Portugal	Portugal Amadora	Amadora
939	Amora's office	Portugal	Portugal Amora	Amora
940	Arrentela's office	Portugal	Portugal Arrentela	Arrentela
941	Aveiro's office	Portugal	Portugal Aveiro	Aveiro
942	Barcelos's office	Portugal	Portugal Barcelos	Barcelos
943	Barreiro's office	Portugal	Portugal Barreiro	Barreiro
944	Beja's office	Portugal	Portugal Beja	Beja
945	Doha's office	Qatar	Qatar Doha	Doha
946	Adjud's office	Romania	Romania Adjud	Adjud
947	Aiud's office	Romania	Romania Aiud	Aiud
948	Alexandria's office	Romania	Romania Alexandria	Alexandria
949	Arad's office	Romania	Romania Arad	Arad
950	Blaj's office	Romania	Romania Blaj	Blaj
951	Brad's office	Romania	Romania Brad	Brad
952	Breaza's office	Romania	Romania Breaza	Breaza
953	Bucharest's office	Romania	Romania Bucharest	Bucharest
954	Buftea's office	Romania	Romania Buftea	Buftea
955	Calafat's office	Romania	Romania Calafat	Calafat
956	Abakan's office	Russia	Russia Abakan	Abakan
957	Abaza's office	Russia	Russia Abaza	Abaza
958	Abdulino's office	Russia	Russia Abdulino	Abdulino
959	Abinsk's office	Russia	Russia Abinsk	Abinsk
960	Achinsk's office	Russia	Russia Achinsk	Achinsk
961	Adler's office	Russia	Russia Adler	Adler
962	Admiralteisky's office	Russia	Russia Admiralteisky	Admiralteisky
963	Afipskiy's office	Russia	Russia Afipskiy	Afipskiy
964	Agryz's office	Russia	Russia Agryz	Agryz
965	Akademgorodok's office	Russia	Russia Akademgorodok	Akademgorodok
966	Butare's office	Rwanda	Rwanda Butare	Butare
967	Byumba's office	Rwanda	Rwanda Byumba	Byumba
968	Cyangugu's office	Rwanda	Rwanda Cyangugu	Cyangugu
969	Gisenyi's office	Rwanda	Rwanda Gisenyi	Gisenyi
970	Gitarama's office	Rwanda	Rwanda Gitarama	Gitarama
971	Kibungo's office	Rwanda	Rwanda Kibungo	Kibungo
972	Kibuye's office	Rwanda	Rwanda Kibuye	Kibuye
973	Kigali's office	Rwanda	Rwanda Kigali	Kigali
974	Musanze's office	Rwanda	Rwanda Musanze	Musanze
975	Nzega's office	Rwanda	Rwanda Nzega	Nzega
976	Apia's office	Samoa	Samoa Apia	Apia
977	Bignona's office	Senegal	Senegal Bignona	Bignona
978	Dakar's office	Senegal	Senegal Dakar	Dakar
979	Dara's office	Senegal	Senegal Dara	Dara
980	Kaffrine's office	Senegal	Senegal Kaffrine	Kaffrine
981	Kaolack's office	Senegal	Senegal Kaolack	Kaolack
982	Kayar's office	Senegal	Senegal Kayar	Kayar
983	Kolda's office	Senegal	Senegal Kolda	Kolda
984	Louga's office	Senegal	Senegal Louga	Louga
985	Matam's office	Senegal	Senegal Matam	Matam
986	Pikine's office	Senegal	Senegal Pikine	Pikine
987	Apatin's office	Serbia	Serbia Apatin	Apatin
988	Belgrade's office	Serbia	Serbia Belgrade	Belgrade
989	Bor's office	Serbia	Serbia Bor	Bor
990	Jagodina's office	Serbia	Serbia Jagodina	Jagodina
991	Kikinda's office	Serbia	Serbia Kikinda	Kikinda
992	Knjazevac's office	Serbia	Serbia Knjazevac	Knjazevac
993	Kragujevac's office	Serbia	Serbia Kragujevac	Kragujevac
994	Kraljevo's office	Serbia	Serbia Kraljevo	Kraljevo
995	Lazarevac's office	Serbia	Serbia Lazarevac	Lazarevac
996	Leskovac's office	Serbia	Serbia Leskovac	Leskovac
997	Victoria's office	Seychelles	Seychelles Victoria	Victoria
998	Singapore's office	Singapore	Singapore Singapore	Singapore
999	Bardejov's office	Slovakia	Slovakia Bardejov	Bardejov
1000	Bratislava's office	Slovakia	Slovakia Bratislava	Bratislava
1001	Brezno's office	Slovakia	Slovakia Brezno	Brezno
1002	Detva's office	Slovakia	Slovakia Detva	Detva
1003	Galanta's office	Slovakia	Slovakia Galanta	Galanta
1004	Hlohovec's office	Slovakia	Slovakia Hlohovec	Hlohovec
1005	Levice's office	Slovakia	Slovakia Levice	Levice
1006	Malacky's office	Slovakia	Slovakia Malacky	Malacky
1007	Martin's office	Slovakia	Slovakia Martin	Martin
1008	Michalovce's office	Slovakia	Slovakia Michalovce	Michalovce
1009	Celje's office	Slovenia	Slovenia Celje	Celje
1010	Koper's office	Slovenia	Slovenia Koper	Koper
1011	Kranj's office	Slovenia	Slovenia Kranj	Kranj
1012	Ljubljana's office	Slovenia	Slovenia Ljubljana	Ljubljana
1013	Maribor's office	Slovenia	Slovenia Maribor	Maribor
1014	Ptuj's office	Slovenia	Slovenia Ptuj	Ptuj
1015	Trbovlje's office	Slovenia	Slovenia Trbovlje	Trbovlje
1016	Velenje's office	Slovenia	Slovenia Velenje	Velenje
1017	Afgooye's office	Somalia	Somalia Afgooye	Afgooye
1018	Baardheere's office	Somalia	Somalia Baardheere	Baardheere
1019	Baidoa's office	Somalia	Somalia Baidoa	Baidoa
1020	Baki's office	Somalia	Somalia Baki	Baki
1021	Beledweyne's office	Somalia	Somalia Beledweyne	Beledweyne
1022	Berbera's office	Somalia	Somalia Berbera	Berbera
1023	Bosaso's office	Somalia	Somalia Bosaso	Bosaso
1024	Burao's office	Somalia	Somalia Burao	Burao
1025	Buulobarde's office	Somalia	Somalia Buulobarde	Buulobarde
1026	Buurhakaba's office	Somalia	Somalia Buurhakaba	Buurhakaba
1027	Adeje's office	Spain	Spain Adeje	Adeje
1028	Adra's office	Spain	Spain Adra	Adra
1029	Albacete's office	Spain	Spain Albacete	Albacete
1030	Albal's office	Spain	Spain Albal	Albal
1031	Albolote's office	Spain	Spain Albolote	Albolote
1032	Alboraya's office	Spain	Spain Alboraya	Alboraya
1033	Alcantarilla's office	Spain	Spain Alcantarilla	Alcantarilla
1034	Alcobendas's office	Spain	Spain Alcobendas	Alcobendas
1035	Alcoy's office	Spain	Spain Alcoy	Alcoy
1036	Aldaia's office	Spain	Spain Aldaia	Aldaia
1037	Atbara's office	Sudan	Sudan Atbara	Atbara
1038	Berber's office	Sudan	Sudan Berber	Berber
1039	Dilling's office	Sudan	Sudan Dilling	Dilling
1040	Doka's office	Sudan	Sudan Doka	Doka
1041	Geneina's office	Sudan	Sudan Geneina	Geneina
1042	Kadugli's office	Sudan	Sudan Kadugli	Kadugli
1043	Kassala's office	Sudan	Sudan Kassala	Kassala
1044	Khartoum's office	Sudan	Sudan Khartoum	Khartoum
1045	Kosti's office	Sudan	Sudan Kosti	Kosti
1046	Kuraymah's office	Sudan	Sudan Kuraymah	Kuraymah
1047	Lelydorp's office	Suriname	Suriname Lelydorp	Lelydorp
1048	Paramaribo's office	Suriname	Suriname Paramaribo	Paramaribo
1049	Lobamba's office	Swaziland	Swaziland Lobamba	Lobamba
1050	Manzini's office	Swaziland	Swaziland Manzini	Manzini
1051	Mbabane's office	Swaziland	Swaziland Mbabane	Mbabane
1052	Boden's office	Sweden	Sweden Boden	Boden
1053	Boo's office	Sweden	Sweden Boo	Boo
1054	Bromma's office	Sweden	Sweden Bromma	Bromma
1055	Eskilstuna's office	Sweden	Sweden Eskilstuna	Eskilstuna
1056	Falkenberg's office	Sweden	Sweden Falkenberg	Falkenberg
1057	Falun's office	Sweden	Sweden Falun	Falun
1058	Halmstad's office	Sweden	Sweden Halmstad	Halmstad
1059	Haninge's office	Sweden	Sweden Haninge	Haninge
1060	Helsingborg's office	Sweden	Sweden Helsingborg	Helsingborg
1061	Huddinge's office	Sweden	Sweden Huddinge	Huddinge
1062	Aarau's office	Switzerland	Switzerland Aarau	Aarau
1063	Adliswil's office	Switzerland	Switzerland Adliswil	Adliswil
1064	Allschwil's office	Switzerland	Switzerland Allschwil	Allschwil
1065	Baar's office	Switzerland	Switzerland Baar	Baar
1066	Baden's office	Switzerland	Switzerland Baden	Baden
1067	Basel's office	Switzerland	Switzerland Basel	Basel
1068	Bellinzona's office	Switzerland	Switzerland Bellinzona	Bellinzona
1069	Bern's office	Switzerland	Switzerland Bern	Bern
1070	Carouge's office	Switzerland	Switzerland Carouge	Carouge
1071	Chur's office	Switzerland	Switzerland Chur	Chur
1072	Aleppo's office	Syria	Syria Aleppo	Aleppo
1073	Binnish's office	Syria	Syria Binnish	Binnish
1074	Damascus's office	Syria	Syria Damascus	Damascus
1075	Douma's office	Syria	Syria Douma	Douma
1076	Homs's office	Syria	Syria Homs	Homs
1077	Idlib's office	Syria	Syria Idlib	Idlib
1078	Inkhil's office	Syria	Syria Inkhil	Inkhil
1079	Jablah's office	Syria	Syria Jablah	Jablah
1080	Latakia's office	Syria	Syria Latakia	Latakia
1081	Manbij's office	Syria	Syria Manbij	Manbij
1082	Banqiao's office	Taiwan	Taiwan Banqiao	Banqiao
1083	Daxi's office	Taiwan	Taiwan Daxi	Daxi
1084	Douliu's office	Taiwan	Taiwan Douliu	Douliu
1085	Hengchun's office	Taiwan	Taiwan Hengchun	Hengchun
1086	Hsinchu's office	Taiwan	Taiwan Hsinchu	Hsinchu
1087	Jincheng's office	Taiwan	Taiwan Jincheng	Jincheng
1088	Kaohsiung's office	Taiwan	Taiwan Kaohsiung	Kaohsiung
1089	Keelung's office	Taiwan	Taiwan Keelung	Keelung
1090	Lugu's office	Taiwan	Taiwan Lugu	Lugu
1091	Magong's office	Taiwan	Taiwan Magong	Magong
1092	Boshkengash's office	Tajikistan	Tajikistan Boshkengash	Boshkengash
1093	Chkalov's office	Tajikistan	Tajikistan Chkalov	Chkalov
1094	Chubek's office	Tajikistan	Tajikistan Chubek	Chubek
1095	Danghara's office	Tajikistan	Tajikistan Danghara	Danghara
1096	Dushanbe's office	Tajikistan	Tajikistan Dushanbe	Dushanbe
1097	Farkhor's office	Tajikistan	Tajikistan Farkhor	Farkhor
1098	Hisor's office	Tajikistan	Tajikistan Hisor	Hisor
1099	Isfara's office	Tajikistan	Tajikistan Isfara	Isfara
1100	Ishqoshim's office	Tajikistan	Tajikistan Ishqoshim	Ishqoshim
1101	Istaravshan's office	Tajikistan	Tajikistan Istaravshan	Istaravshan
1102	Arusha's office	Tanzania	Tanzania Arusha	Arusha
1103	Babati's office	Tanzania	Tanzania Babati	Babati
1104	Bagamoyo's office	Tanzania	Tanzania Bagamoyo	Bagamoyo
1105	Bariadi's office	Tanzania	Tanzania Bariadi	Bariadi
1106	Bashanet's office	Tanzania	Tanzania Bashanet	Bashanet
1107	Basotu's office	Tanzania	Tanzania Basotu	Basotu
1108	Biharamulo's office	Tanzania	Tanzania Biharamulo	Biharamulo
1109	Bugarama's office	Tanzania	Tanzania Bugarama	Bugarama
1110	Bukoba's office	Tanzania	Tanzania Bukoba	Bukoba
1111	Bunda's office	Tanzania	Tanzania Bunda	Bunda
1112	Aranyaprathet's office	Thailand	Thailand Aranyaprathet	Aranyaprathet
1113	Bangkok's office	Thailand	Thailand Bangkok	Bangkok
1114	Betong's office	Thailand	Thailand Betong	Betong
1115	Buriram's office	Thailand	Thailand Buriram	Buriram
1116	Chachoengsao's office	Thailand	Thailand Chachoengsao	Chachoengsao
1117	Chaiyaphum's office	Thailand	Thailand Chaiyaphum	Chaiyaphum
1118	Chanthaburi's office	Thailand	Thailand Chanthaburi	Chanthaburi
1119	Chumphon's office	Thailand	Thailand Chumphon	Chumphon
1120	Kalasin's office	Thailand	Thailand Kalasin	Kalasin
1121	Kamalasai's office	Thailand	Thailand Kamalasai	Kamalasai
1122	Badou's office	Togo	Togo Badou	Badou
1123	Bafilo's office	Togo	Togo Bafilo	Bafilo
1124	Bassar's office	Togo	Togo Bassar	Bassar
1125	Dapaong's office	Togo	Togo Dapaong	Dapaong
1126	Kara's office	Togo	Togo Kara	Kara
1127	Niamtougou's office	Togo	Togo Niamtougou	Niamtougou
1128	Sotouboua's office	Togo	Togo Sotouboua	Sotouboua
1129	Tchamba's office	Togo	Togo Tchamba	Tchamba
1130	Vogan's office	Togo	Togo Vogan	Vogan
1131	Akouda's office	Tunisia	Tunisia Akouda	Akouda
1132	Ariana's office	Tunisia	Tunisia Ariana	Ariana
1133	Bekalta's office	Tunisia	Tunisia Bekalta	Bekalta
1134	Bizerte's office	Tunisia	Tunisia Bizerte	Bizerte
1135	Carthage's office	Tunisia	Tunisia Carthage	Carthage
1136	Chebba's office	Tunisia	Tunisia Chebba	Chebba
1137	Djemmal's office	Tunisia	Tunisia Djemmal	Djemmal
1138	Douane's office	Tunisia	Tunisia Douane	Douane
1139	Douz's office	Tunisia	Tunisia Douz	Douz
1140	Gafsa's office	Tunisia	Tunisia Gafsa	Gafsa
1141	Adana's office	Turkey	Turkey Adana	Adana
1142	Adilcevaz's office	Turkey	Turkey Adilcevaz	Adilcevaz
1143	Afyonkarahisar's office	Turkey	Turkey Afyonkarahisar	Afyonkarahisar
1144	Ahlat's office	Turkey	Turkey Ahlat	Ahlat
1145	Akhisar's office	Turkey	Turkey Akhisar	Akhisar
1146	Aksaray's office	Turkey	Turkey Aksaray	Aksaray
1147	Alaca's office	Turkey	Turkey Alaca	Alaca
1148	Alanya's office	Turkey	Turkey Alanya	Alanya
1149	Amasya's office	Turkey	Turkey Amasya	Amasya
1150	Anamur's office	Turkey	Turkey Anamur	Anamur
1151	Abadan's office	Turkmenistan	Turkmenistan Abadan	Abadan
1152	Annau's office	Turkmenistan	Turkmenistan Annau	Annau
1153	Ashgabat's office	Turkmenistan	Turkmenistan Ashgabat	Ashgabat
1154	Atamyrat's office	Turkmenistan	Turkmenistan Atamyrat	Atamyrat
1155	Baharly's office	Turkmenistan	Turkmenistan Baharly	Baharly
1156	Balkanabat's office	Turkmenistan	Turkmenistan Balkanabat	Balkanabat
1157	Bayramaly's office	Turkmenistan	Turkmenistan Bayramaly	Bayramaly
1158	Boldumsaz's office	Turkmenistan	Turkmenistan Boldumsaz	Boldumsaz
1159	Gazanjyk's office	Turkmenistan	Turkmenistan Gazanjyk	Gazanjyk
1160	Gazojak's office	Turkmenistan	Turkmenistan Gazojak	Gazojak
1161	Funafuti's office	Tuvalu	Tuvalu Funafuti	Funafuti
1162	Adjumani's office	Uganda	Uganda Adjumani	Adjumani
1163	Arua's office	Uganda	Uganda Arua	Arua
1164	Bugiri's office	Uganda	Uganda Bugiri	Bugiri
1165	Bundibugyo's office	Uganda	Uganda Bundibugyo	Bundibugyo
1166	Busembatia's office	Uganda	Uganda Busembatia	Busembatia
1167	Busia's office	Uganda	Uganda Busia	Busia
1168	Buwenge's office	Uganda	Uganda Buwenge	Buwenge
1169	Bwizibwera's office	Uganda	Uganda Bwizibwera	Bwizibwera
1170	Entebbe's office	Uganda	Uganda Entebbe	Entebbe
1171	Gulu's office	Uganda	Uganda Gulu	Gulu
1172	Alushta's office	Ukraine	Ukraine Alushta	Alushta
1173	Amvrosiyivka's office	Ukraine	Ukraine Amvrosiyivka	Amvrosiyivka
1174	Antratsyt's office	Ukraine	Ukraine Antratsyt	Antratsyt
1175	Apostolove's office	Ukraine	Ukraine Apostolove	Apostolove
1176	Artsyz's office	Ukraine	Ukraine Artsyz	Artsyz
1177	Avdiyivka's office	Ukraine	Ukraine Avdiyivka	Avdiyivka
1178	Bakhchysaray's office	Ukraine	Ukraine Bakhchysaray	Bakhchysaray
1179	Bakhmach's office	Ukraine	Ukraine Bakhmach	Bakhmach
1180	Balaklava's office	Ukraine	Ukraine Balaklava	Balaklava
1181	Balakliya's office	Ukraine	Ukraine Balakliya	Balakliya
1182	Artigas's office	Uruguay	Uruguay Artigas	Artigas
1183	Canelones's office	Uruguay	Uruguay Canelones	Canelones
1184	Carmelo's office	Uruguay	Uruguay Carmelo	Carmelo
1185	Dolores's office	Uruguay	Uruguay Dolores	Dolores
1186	Durazno's office	Uruguay	Uruguay Durazno	Durazno
1187	Florida's office	Uruguay	Uruguay Florida	Florida
1188	Maldonado's office	Uruguay	Uruguay Maldonado	Maldonado
1189	Melo's office	Uruguay	Uruguay Melo	Melo
1190	Mercedes's office	Uruguay	Uruguay Mercedes	Mercedes
1191	Minas's office	Uruguay	Uruguay Minas	Minas
1192	Andijon's office	Uzbekistan	Uzbekistan Andijon	Andijon
1193	Angren's office	Uzbekistan	Uzbekistan Angren	Angren
1194	Asaka's office	Uzbekistan	Uzbekistan Asaka	Asaka
1195	Bekobod's office	Uzbekistan	Uzbekistan Bekobod	Bekobod
1196	Bektemir's office	Uzbekistan	Uzbekistan Bektemir	Bektemir
1197	Beruniy's office	Uzbekistan	Uzbekistan Beruniy	Beruniy
1198	Beshariq's office	Uzbekistan	Uzbekistan Beshariq	Beshariq
1199	Beshkent's office	Uzbekistan	Uzbekistan Beshkent	Beshkent
1200	Boysun's office	Uzbekistan	Uzbekistan Boysun	Boysun
1201	Bukhara's office	Uzbekistan	Uzbekistan Bukhara	Bukhara
1202	Acarigua's office	Venezuela	Venezuela Acarigua	Acarigua
1203	Anaco's office	Venezuela	Venezuela Anaco	Anaco
1204	Araure's office	Venezuela	Venezuela Araure	Araure
1205	Barcelona's office	Venezuela	Venezuela Barcelona	Barcelona
1206	Barinas's office	Venezuela	Venezuela Barinas	Barinas
1207	Barinitas's office	Venezuela	Venezuela Barinitas	Barinitas
1208	Barquisimeto's office	Venezuela	Venezuela Barquisimeto	Barquisimeto
1209	Baruta's office	Venezuela	Venezuela Baruta	Baruta
1210	Cabimas's office	Venezuela	Venezuela Cabimas	Cabimas
1211	Cagua's office	Venezuela	Venezuela Cagua	Cagua
1212	Haiphong's office	Vietnam	Vietnam Haiphong	Haiphong
1213	Hanoi's office	Vietnam	Vietnam Hanoi	Hanoi
1214	Pleiku's office	Vietnam	Vietnam Pleiku	Pleiku
1215	Sadek's office	Vietnam	Vietnam Sadek	Sadek
1216	Vinh's office	Vietnam	Vietnam Vinh	Vinh
1217	Aden's office	Yemen	Yemen Aden	Aden
1218	Ataq's office	Yemen	Yemen Ataq	Ataq
1219	Ibb's office	Yemen	Yemen Ibb	Ibb
1220	Sanaa's office	Yemen	Yemen Sanaa	Sanaa
1221	Chililabombwe's office	Zambia	Zambia Chililabombwe	Chililabombwe
1222	Chingola's office	Zambia	Zambia Chingola	Chingola
1223	Chipata's office	Zambia	Zambia Chipata	Chipata
1224	Choma's office	Zambia	Zambia Choma	Choma
1225	Kabwe's office	Zambia	Zambia Kabwe	Kabwe
1226	Kafue's office	Zambia	Zambia Kafue	Kafue
1227	Kalulushi's office	Zambia	Zambia Kalulushi	Kalulushi
1228	Kansanshi's office	Zambia	Zambia Kansanshi	Kansanshi
1229	Kasama's office	Zambia	Zambia Kasama	Kasama
1230	Kawambwa's office	Zambia	Zambia Kawambwa	Kawambwa
1231	Beitbridge's office	Zimbabwe	Zimbabwe Beitbridge	Beitbridge
1232	Bindura's office	Zimbabwe	Zimbabwe Bindura	Bindura
1233	Bulawayo's office	Zimbabwe	Zimbabwe Bulawayo	Bulawayo
1234	Chegutu's office	Zimbabwe	Zimbabwe Chegutu	Chegutu
1235	Chinhoyi's office	Zimbabwe	Zimbabwe Chinhoyi	Chinhoyi
1236	Chipinge's office	Zimbabwe	Zimbabwe Chipinge	Chipinge
1237	Chiredzi's office	Zimbabwe	Zimbabwe Chiredzi	Chiredzi
1238	Chitungwiza's office	Zimbabwe	Zimbabwe Chitungwiza	Chitungwiza
1239	Epworth's office	Zimbabwe	Zimbabwe Epworth	Epworth
1240	Gokwe's office	Zimbabwe	Zimbabwe Gokwe	Gokwe
1241	New York's office	USA	USA New York	New York
1242	Los Angeles's office	USA	USA Los Angeles	Los Angeles
1243	Chicago's office	USA	USA Chicago	Chicago
1244	Houston's office	USA	USA Houston	Houston
1245	Phoenix's office	USA	USA Phoenix	Phoenix
1246	Philadelphia's office	USA	USA Philadelphia	Philadelphia
1247	San Antonio's office	USA	USA San Antonio	San Antonio
1248	San Diego's office	USA	USA San Diego	San Diego
1249	Dallas's office	USA	USA Dallas	Dallas
1250	San Jose's office	USA	USA San Jose	San Jose
\.


--
-- Data for Name: offices_kinds; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices_kinds (kind, description) FROM stdin;
1	consulat
2	marriage agency
3	driver schools
4	medical center
5	official veterinarian
\.


--
-- Data for Name: offices_kinds_relations; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices_kinds_relations (office_id, kind_id) FROM stdin;
1	2
2	3
2	5
2	1
2	2
3	4
3	1
3	3
4	3
5	3
5	4
5	5
5	2
5	1
6	4
6	5
6	1
7	3
7	1
7	5
7	4
7	2
8	5
9	1
9	2
10	5
10	2
11	2
11	4
11	5
12	1
12	4
12	5
13	1
13	5
13	2
14	1
14	4
14	3
14	5
15	5
15	3
15	2
16	3
17	5
17	2
17	4
18	5
18	1
18	3
19	1
19	3
20	5
20	2
20	1
21	1
22	5
22	1
23	3
23	1
23	5
23	4
24	4
24	1
25	3
25	1
26	3
26	5
26	1
26	2
26	4
27	4
27	3
27	1
28	4
28	2
29	2
29	4
29	3
29	1
29	5
30	2
30	3
30	5
31	3
31	5
31	2
32	5
32	2
32	1
32	4
33	4
33	2
33	5
34	5
34	1
34	3
34	4
35	2
36	5
36	3
36	1
37	4
37	1
37	2
37	3
38	3
38	5
38	2
38	1
39	1
39	2
39	3
39	5
39	4
40	4
40	3
40	5
40	2
41	3
42	5
42	4
43	4
43	2
43	5
43	3
43	1
44	5
44	1
44	4
45	2
45	5
45	4
45	3
46	4
46	3
46	1
46	5
46	2
47	5
47	1
47	2
47	4
48	2
48	1
48	4
49	5
49	2
49	1
49	3
50	3
50	4
51	3
51	2
51	1
51	5
52	5
52	2
52	1
53	4
53	3
53	2
54	2
54	1
54	3
54	4
54	5
55	1
56	4
56	3
56	5
56	1
56	2
57	3
57	2
58	1
58	3
58	4
58	2
58	5
59	5
59	3
59	1
59	4
59	2
60	1
60	4
60	2
60	3
60	5
61	3
61	5
61	1
62	5
62	2
62	3
63	2
63	3
63	5
63	4
64	3
65	1
65	3
65	2
65	4
66	4
66	2
66	5
67	1
68	3
68	4
68	1
68	2
68	5
69	5
69	3
70	5
71	5
71	3
72	4
72	2
72	1
73	5
74	3
74	4
75	3
75	4
75	5
75	2
75	1
76	1
77	3
77	4
78	2
78	3
78	1
79	4
79	1
80	5
81	4
81	5
82	1
83	2
83	1
84	3
84	5
85	5
85	2
85	4
86	4
86	1
86	5
87	5
87	2
87	4
87	1
88	2
88	4
89	3
89	4
89	5
90	2
90	3
90	1
90	5
91	2
91	5
91	3
91	1
92	4
92	3
92	2
92	5
92	1
93	1
93	4
94	4
94	2
94	5
95	2
96	3
96	4
96	1
96	5
96	2
97	2
97	4
97	1
97	5
97	3
98	4
98	2
98	5
98	1
98	3
99	1
99	3
100	1
100	4
101	5
101	4
101	2
101	3
102	3
102	1
102	2
102	5
103	2
104	4
104	2
104	3
105	1
106	1
106	4
106	2
106	5
107	2
107	3
108	4
108	3
108	5
108	1
109	2
110	2
110	5
111	4
111	5
111	3
111	2
112	3
112	4
112	1
112	2
113	1
113	2
113	3
114	2
115	4
115	3
115	5
115	2
115	1
116	3
116	5
116	2
116	4
117	2
117	4
117	3
117	5
117	1
118	1
118	2
118	4
118	3
118	5
119	2
119	5
119	3
119	1
120	4
120	2
121	5
121	2
121	1
122	2
123	5
124	5
124	1
124	4
125	3
126	5
126	3
126	1
127	1
127	2
127	4
127	5
128	3
128	5
129	5
129	4
129	2
130	1
130	2
130	4
130	5
130	3
131	1
131	2
131	3
131	4
132	3
132	2
132	1
132	4
133	2
133	1
133	4
133	3
134	3
134	5
134	2
135	3
135	5
135	4
135	2
136	4
136	5
137	3
137	2
137	1
137	4
137	5
138	2
138	4
138	1
138	5
139	3
139	4
139	5
139	2
139	1
140	3
141	2
141	5
142	1
142	2
142	5
142	3
143	3
143	2
143	5
143	4
143	1
144	2
144	4
144	5
144	1
144	3
145	4
145	5
145	3
145	2
146	3
146	1
146	4
146	5
147	1
147	4
147	3
147	5
147	2
148	3
148	1
148	4
148	5
149	5
149	3
150	5
151	3
151	2
151	5
152	5
152	4
153	5
153	1
153	2
153	3
153	4
154	2
154	5
155	4
155	1
156	2
156	3
157	2
157	4
158	2
159	4
160	4
160	3
160	5
160	2
160	1
161	1
161	5
162	4
162	1
162	3
162	2
163	5
164	2
165	1
165	2
165	5
165	4
165	3
166	3
166	4
166	5
166	2
167	5
167	2
168	5
168	3
169	4
169	5
170	4
170	5
170	1
170	3
171	5
171	3
171	2
172	2
173	3
173	2
173	1
174	1
174	2
175	1
175	3
175	5
176	2
176	1
177	2
177	1
178	5
179	5
179	1
180	2
180	4
181	3
181	2
181	5
181	4
182	2
182	5
183	4
183	3
183	1
183	2
183	5
184	2
184	5
185	4
185	1
185	2
185	5
185	3
186	3
187	5
187	2
187	1
187	3
187	4
188	3
188	4
189	2
190	4
190	5
190	3
191	3
191	4
191	1
191	5
192	5
192	3
193	1
193	4
193	2
193	5
194	5
194	1
194	3
194	4
194	2
195	1
196	2
196	5
197	3
198	4
198	2
198	5
199	4
199	5
199	1
199	2
199	3
200	5
200	2
200	4
200	1
200	3
201	4
201	2
201	3
201	1
202	5
202	4
202	1
202	3
203	5
203	1
203	3
203	2
203	4
204	1
204	4
204	5
204	2
205	1
205	3
206	4
206	3
206	5
206	2
206	1
207	4
207	1
207	2
207	3
207	5
208	3
208	5
209	2
210	5
210	3
210	4
210	2
210	1
211	5
211	2
211	4
211	3
212	4
212	1
212	5
213	4
214	4
214	3
214	1
215	3
215	2
216	3
216	1
216	4
216	2
217	4
217	2
218	2
218	3
218	4
219	2
220	5
221	5
221	1
221	4
222	3
222	5
222	4
222	2
223	1
224	1
224	5
224	3
224	2
225	3
225	2
226	2
226	1
227	3
227	1
227	5
227	4
228	1
229	2
229	3
229	4
229	5
230	1
231	3
231	4
231	2
231	5
231	1
232	3
232	5
232	2
232	4
232	1
233	5
234	5
234	4
234	1
234	2
235	1
235	3
235	4
236	5
236	4
236	2
237	2
237	4
238	3
238	2
238	5
239	4
239	2
239	1
239	5
239	3
240	5
240	4
241	5
241	2
241	1
242	4
242	2
243	2
243	3
243	1
243	5
243	4
244	2
244	3
244	5
244	4
244	1
245	1
246	5
247	1
248	3
248	2
248	4
248	1
248	5
249	2
249	1
250	4
250	5
250	2
250	1
250	3
251	2
251	3
251	1
251	4
252	4
253	2
253	4
253	3
253	5
254	2
254	3
254	5
255	2
255	5
256	2
256	5
257	1
257	3
258	5
258	2
258	3
258	1
258	4
259	4
259	3
259	1
259	5
260	3
260	4
260	5
261	1
261	4
261	5
261	2
262	4
263	3
263	2
264	3
265	4
265	5
265	2
266	2
266	1
266	3
266	5
267	3
267	1
267	4
267	5
267	2
268	4
268	2
268	5
268	1
269	2
269	5
270	1
270	2
270	5
270	3
271	1
271	4
271	3
271	5
272	2
272	4
272	5
272	1
273	5
274	2
274	5
275	5
276	5
276	3
276	2
276	4
276	1
277	1
277	4
278	3
278	5
278	1
279	3
279	4
279	5
280	4
280	5
281	2
282	1
282	5
282	3
282	2
283	4
284	2
284	5
285	4
286	4
287	1
287	2
287	3
288	4
288	3
288	5
288	2
288	1
289	2
289	5
289	1
289	4
290	2
290	3
290	5
291	2
291	3
291	1
291	5
292	3
292	1
292	4
293	4
293	5
293	3
293	2
293	1
294	1
295	2
295	3
296	4
296	2
296	3
296	1
296	5
297	4
298	3
298	4
298	2
298	1
299	1
300	4
300	3
300	2
301	4
301	1
301	3
302	5
303	4
303	5
303	2
303	3
304	4
304	2
304	5
305	3
305	1
305	4
306	1
306	2
306	5
307	3
307	2
307	1
307	5
308	1
308	5
309	4
309	2
310	1
310	4
310	5
310	2
310	3
311	3
311	1
311	4
311	5
311	2
312	5
313	2
313	1
313	4
314	2
315	5
315	2
315	4
315	3
316	4
317	2
318	1
318	5
319	4
319	1
319	5
319	2
319	3
320	3
320	5
321	4
321	2
322	1
322	4
322	2
322	5
322	3
323	4
323	5
323	3
323	2
324	4
324	3
325	3
325	1
325	4
325	2
325	5
326	4
326	2
326	5
326	1
327	1
327	2
327	5
328	5
329	5
329	1
329	3
329	2
330	5
330	1
330	3
331	5
332	2
332	4
332	1
332	3
333	3
333	4
334	4
334	3
335	3
335	5
335	4
335	1
335	2
336	5
336	4
336	3
336	1
337	5
337	2
338	3
338	1
338	4
339	1
339	2
340	5
340	3
340	4
341	1
341	4
341	5
342	1
342	4
343	1
343	2
343	3
344	4
344	1
344	2
345	5
345	2
345	4
345	1
345	3
346	1
346	4
346	5
346	2
347	1
347	4
348	4
348	2
348	3
348	1
349	3
349	5
349	2
349	1
350	3
350	1
350	2
350	4
350	5
351	2
351	4
351	3
351	5
351	1
352	4
352	2
352	1
352	3
353	3
354	5
354	2
354	3
354	1
355	5
355	1
355	3
355	4
355	2
356	2
357	1
357	2
357	5
357	4
358	4
358	1
358	2
358	5
358	3
359	4
359	3
359	2
359	1
359	5
360	1
360	2
360	4
360	5
361	5
361	4
361	1
361	2
362	4
362	2
362	3
363	1
364	3
365	3
365	4
366	1
366	2
367	5
367	4
367	3
367	2
368	2
368	4
368	1
369	4
370	1
370	2
371	5
372	3
372	2
372	1
373	4
373	1
373	3
373	2
374	4
374	1
374	3
374	5
375	4
375	3
376	5
376	1
376	3
376	2
377	3
377	4
377	1
377	2
377	5
378	4
378	2
378	1
378	5
379	1
379	2
379	5
380	2
381	4
381	1
381	2
381	3
382	4
383	1
383	5
383	2
383	4
384	4
385	1
386	2
387	4
387	5
387	1
387	2
388	3
388	5
389	3
390	5
390	3
390	2
390	1
390	4
391	4
392	4
392	5
392	1
392	3
392	2
393	3
393	1
394	1
394	5
395	5
395	3
396	4
396	3
396	5
396	1
397	2
397	5
397	4
397	3
397	1
398	5
398	4
398	3
398	2
398	1
399	5
399	4
399	1
399	3
399	2
400	3
400	5
401	3
401	2
402	1
402	5
402	4
402	2
402	3
403	5
403	2
404	1
404	3
404	5
405	1
406	5
406	3
407	3
408	2
408	5
408	3
409	2
409	3
410	5
410	2
411	4
411	1
411	3
411	5
411	2
412	2
413	5
414	3
414	5
414	2
415	2
415	3
415	1
415	5
415	4
416	2
417	1
418	5
418	4
418	3
418	2
419	3
420	4
420	3
421	1
421	3
421	2
421	4
422	5
422	4
422	3
422	1
422	2
423	3
423	1
424	5
424	3
425	5
425	3
425	2
425	1
425	4
426	1
426	2
426	3
427	2
428	2
428	3
428	4
429	1
429	3
429	2
429	4
430	3
430	2
430	1
430	4
431	3
432	2
433	3
433	2
433	4
433	5
434	5
434	4
434	2
434	3
434	1
435	1
435	4
435	5
436	4
436	1
436	3
437	4
438	1
438	5
439	3
440	1
440	5
441	2
441	3
441	5
441	1
441	4
442	1
442	5
442	2
442	4
442	3
443	5
443	4
443	2
443	3
443	1
444	5
444	4
444	3
445	2
445	4
446	1
446	2
446	3
446	5
447	3
447	5
447	4
447	2
448	5
448	4
449	4
450	1
450	3
450	4
450	2
450	5
451	3
451	1
451	4
451	2
451	5
452	2
452	1
452	5
452	4
452	3
453	2
453	5
453	1
454	4
454	1
454	5
455	3
455	5
455	4
455	1
456	5
456	3
457	1
457	2
457	4
457	5
457	3
458	3
458	5
459	3
459	2
459	5
459	1
460	5
460	3
460	1
461	1
462	4
462	3
463	5
463	4
463	2
463	3
464	4
464	5
464	1
464	3
464	2
465	5
465	4
465	2
465	1
465	3
466	4
466	5
466	2
467	3
468	1
468	5
469	5
469	3
469	2
469	4
469	1
470	4
470	1
470	5
471	1
471	5
472	4
472	1
472	2
472	5
473	5
474	3
474	5
474	1
474	2
475	5
476	3
477	5
477	2
477	4
477	1
478	3
478	2
478	1
478	4
478	5
479	2
479	4
479	1
479	3
479	5
480	4
480	1
480	2
480	3
481	4
481	3
481	1
481	5
482	1
482	5
483	3
484	3
485	1
485	5
485	3
485	2
485	4
486	5
486	1
487	5
487	1
487	4
487	3
487	2
488	2
488	1
489	3
489	1
489	2
490	2
490	4
490	3
491	4
491	2
491	1
491	5
491	3
492	1
492	5
492	4
492	3
492	2
493	1
493	4
493	5
493	3
493	2
494	2
494	1
494	3
495	4
495	3
495	1
495	5
495	2
496	1
496	2
496	3
496	4
496	5
497	4
497	2
497	3
498	3
498	2
498	1
498	4
498	5
499	2
499	1
499	5
499	4
499	3
500	5
500	2
500	1
501	2
502	5
503	2
504	2
504	3
504	1
505	2
505	4
505	3
506	1
507	5
507	3
508	2
508	4
509	1
509	4
509	5
510	2
510	4
510	1
511	5
511	2
511	3
512	3
512	5
512	2
513	5
513	1
513	2
513	3
514	1
515	5
515	3
515	2
516	2
516	5
516	4
517	2
517	1
518	4
518	1
518	3
519	1
519	2
519	3
519	4
519	5
520	1
520	4
520	3
520	5
521	3
521	1
521	4
522	5
523	1
523	2
523	3
523	5
523	4
524	2
524	1
524	3
524	5
525	1
525	3
525	5
525	2
526	2
526	3
526	5
526	4
527	2
527	4
527	3
527	1
527	5
528	5
529	1
529	5
529	2
529	4
530	3
530	4
530	2
531	2
531	4
531	3
532	4
532	2
532	3
532	5
533	5
533	2
534	1
534	2
534	5
534	3
535	5
535	3
536	1
536	2
536	3
536	5
537	3
538	1
538	5
538	3
538	2
538	4
539	4
539	3
539	2
539	1
539	5
540	3
540	5
541	4
542	1
542	5
543	2
544	5
544	3
544	1
544	4
545	5
545	1
545	2
545	3
545	4
546	1
547	5
547	2
547	1
547	4
547	3
548	3
548	2
548	1
548	5
548	4
549	2
549	5
549	4
550	1
550	4
550	3
550	5
551	5
551	1
552	3
553	2
553	3
553	4
553	1
554	1
554	5
554	3
554	2
555	4
555	3
555	1
555	5
555	2
556	1
556	2
556	5
557	3
557	4
557	5
557	2
558	1
558	2
558	4
558	3
558	5
559	4
559	3
559	1
559	2
559	5
560	3
560	2
561	1
561	3
561	2
561	5
561	4
562	5
562	3
562	4
563	2
563	1
563	5
563	3
563	4
564	4
564	2
564	3
565	1
565	2
565	4
565	5
566	1
566	4
567	2
568	4
568	3
568	1
568	5
568	2
569	5
569	4
569	1
569	3
570	1
571	5
571	1
571	3
572	1
572	2
572	3
572	5
573	1
573	2
574	3
574	2
575	2
575	4
575	1
575	5
575	3
576	2
576	5
576	1
576	3
576	4
577	4
577	1
577	5
577	3
578	4
578	1
579	4
579	5
580	2
580	1
580	5
581	1
581	4
582	5
582	1
583	1
583	3
584	3
584	1
584	4
585	2
585	3
585	5
586	1
587	1
587	3
587	2
587	4
587	5
588	5
588	4
588	3
588	2
589	4
589	5
589	1
589	2
590	2
590	1
590	4
591	3
591	1
591	4
591	2
591	5
592	4
592	5
592	2
592	3
592	1
593	5
594	1
595	1
595	3
596	4
596	2
596	1
596	5
597	4
597	5
597	3
598	4
598	1
598	5
598	2
599	4
599	2
599	1
599	3
599	5
600	1
600	5
600	3
600	2
601	3
601	4
601	5
601	1
601	2
602	1
603	4
604	2
605	5
605	3
605	4
606	3
606	1
606	4
606	5
607	5
607	2
607	4
608	1
608	2
608	3
609	4
609	1
610	1
610	2
610	4
610	3
611	4
612	1
612	4
612	5
612	3
613	1
613	3
614	5
614	2
615	4
616	3
616	5
616	2
617	1
618	3
618	2
619	2
619	1
619	3
619	4
620	4
620	1
621	2
621	5
621	4
622	4
623	5
623	4
623	2
624	4
624	1
625	3
626	1
627	2
627	1
627	5
627	4
627	3
628	4
628	1
629	3
630	5
631	2
631	3
632	4
632	3
632	5
632	1
633	2
633	1
633	3
633	5
633	4
634	2
634	4
634	5
634	3
634	1
635	4
636	4
636	5
637	4
637	2
637	3
637	5
637	1
638	3
638	1
638	2
638	4
638	5
639	1
639	2
639	5
639	4
640	2
640	5
641	1
642	1
642	4
643	2
644	2
644	4
644	3
644	1
645	3
645	1
646	3
646	2
646	5
646	1
647	5
647	3
647	2
648	1
648	4
648	5
648	2
648	3
649	2
649	3
649	4
649	5
649	1
650	1
650	3
650	2
650	4
651	5
651	4
651	3
652	1
652	3
652	5
653	2
654	5
655	4
655	2
655	1
655	3
656	3
656	4
656	5
656	1
656	2
657	1
657	4
657	2
657	3
657	5
658	1
658	4
658	3
659	4
659	1
659	3
660	4
660	3
660	5
660	1
661	3
662	4
662	1
663	2
663	4
663	1
663	3
664	1
664	4
665	2
666	3
666	4
666	5
666	2
667	4
667	5
668	3
668	1
668	4
668	5
668	2
669	2
669	1
669	5
669	4
670	3
670	4
670	2
670	5
671	1
671	3
671	2
671	5
672	4
673	1
673	4
673	2
673	3
674	2
674	3
675	3
676	1
676	4
676	5
676	2
677	3
677	1
677	5
677	4
678	4
678	2
679	4
679	5
679	2
679	1
679	3
680	3
680	4
680	2
680	1
680	5
681	1
681	5
682	3
682	5
682	1
683	5
683	1
684	5
684	4
684	2
685	5
685	1
685	3
686	3
686	1
686	5
687	3
687	1
687	2
687	4
687	5
688	2
689	3
690	5
691	3
692	3
692	4
692	1
692	2
692	5
693	4
693	5
693	1
694	3
694	2
694	4
694	5
695	5
696	4
696	1
697	3
697	1
697	5
697	2
698	5
699	3
699	4
699	2
700	3
700	1
700	2
700	4
700	5
701	5
701	2
701	3
702	2
702	1
702	4
703	4
703	3
703	5
703	1
704	1
704	3
704	5
704	4
704	2
705	3
705	2
705	5
705	1
706	4
707	2
707	1
707	5
707	3
708	3
708	1
708	5
708	2
708	4
709	1
710	1
710	4
710	3
710	5
710	2
711	1
711	3
711	5
711	2
712	5
712	3
712	1
712	2
712	4
713	2
713	1
713	3
713	5
713	4
714	2
714	4
714	1
714	5
714	3
715	1
715	5
716	4
716	5
716	2
717	4
718	5
718	1
718	3
718	2
719	4
720	3
720	1
720	5
720	4
720	2
721	3
721	4
721	2
721	5
721	1
722	5
722	2
723	3
724	3
724	2
724	5
724	1
725	5
725	3
725	1
725	4
726	1
726	2
726	4
727	5
727	4
727	3
727	1
727	2
728	5
728	4
729	1
730	4
730	2
731	3
731	2
731	5
732	5
732	3
732	1
732	4
733	5
734	2
734	1
734	4
734	5
734	3
735	1
735	4
736	1
736	4
737	4
737	2
737	5
738	5
738	1
738	2
739	4
739	5
739	2
739	3
740	3
740	4
740	5
740	1
741	4
742	1
743	2
743	1
743	3
743	5
744	1
744	3
744	2
744	5
744	4
745	3
745	4
745	1
745	2
745	5
746	3
746	4
747	4
748	3
748	1
749	3
749	2
750	1
750	3
750	4
750	2
750	5
751	4
751	3
752	5
752	1
753	2
754	4
755	2
755	1
756	3
756	5
756	1
756	4
756	2
757	5
757	4
757	3
757	2
758	1
759	3
760	2
760	1
760	3
760	5
761	1
761	2
761	5
762	1
762	2
762	4
763	4
764	1
765	1
765	3
765	4
765	2
765	5
766	2
766	1
766	3
766	4
766	5
767	4
767	3
767	5
767	1
768	4
768	1
769	3
770	3
771	2
771	3
771	5
772	3
772	2
773	3
773	2
773	1
774	5
774	2
775	2
776	2
776	1
776	3
776	4
777	4
777	5
777	3
778	1
778	2
778	3
779	5
779	1
779	3
779	2
780	4
780	2
780	1
780	3
780	5
781	5
781	1
781	3
781	4
781	2
782	5
783	1
783	2
783	4
783	5
783	3
784	1
784	3
784	2
784	4
785	5
785	2
785	1
786	5
786	1
787	4
788	1
789	1
789	4
789	5
790	4
790	3
790	5
790	2
791	5
791	4
791	1
791	2
791	3
792	2
793	1
793	2
794	3
794	4
794	5
794	1
795	3
795	1
796	3
797	5
797	1
797	2
797	3
798	1
798	3
798	5
799	2
799	4
800	3
800	5
800	2
800	4
800	1
801	4
801	2
802	1
803	2
803	4
803	1
803	5
804	3
804	1
804	5
804	4
805	4
805	2
805	1
805	5
805	3
806	5
806	1
807	1
807	3
808	1
809	4
809	3
809	2
809	1
810	3
811	4
811	2
812	5
812	1
813	2
813	3
813	4
814	3
814	2
814	1
814	5
814	4
815	4
815	5
815	3
816	2
816	4
817	3
817	2
817	1
817	4
817	5
818	2
818	5
818	3
818	1
819	5
820	1
820	5
821	1
821	3
821	2
822	4
822	1
822	3
822	2
822	5
823	1
823	5
823	4
823	3
823	2
824	2
824	1
824	4
825	2
825	3
826	3
827	5
827	1
828	4
829	5
829	3
829	1
829	2
830	2
831	2
831	5
831	4
832	5
832	4
832	3
832	2
833	1
833	2
833	5
833	3
833	4
834	1
835	2
835	4
835	5
836	4
837	2
838	3
838	5
838	4
839	2
839	4
839	5
840	3
840	4
840	2
840	5
840	1
841	3
841	2
842	1
842	3
842	5
842	4
843	3
843	1
844	2
844	1
844	5
844	4
844	3
845	2
845	5
845	3
845	1
845	4
846	1
846	3
846	2
847	4
848	3
849	2
849	5
849	1
849	3
849	4
850	2
850	5
850	3
851	2
851	3
851	4
851	1
851	5
852	5
853	1
853	5
854	2
855	5
855	4
855	1
856	5
856	4
856	2
857	2
857	1
858	5
859	2
859	4
859	5
859	3
859	1
860	4
860	2
860	1
861	4
861	1
861	5
861	3
862	5
862	1
863	2
863	5
864	5
864	4
864	2
865	3
866	3
866	4
866	2
866	1
867	5
867	2
868	5
869	5
869	1
869	3
869	4
869	2
870	1
870	2
870	5
870	3
870	4
871	1
871	4
871	5
871	3
872	3
873	3
874	4
875	4
875	5
875	3
875	1
875	2
876	2
876	3
876	5
876	1
876	4
877	1
877	5
877	2
877	3
877	4
878	2
878	3
878	5
878	4
879	4
879	5
879	1
879	2
879	3
880	1
880	5
880	3
880	2
881	1
881	4
881	5
882	1
882	4
882	5
882	3
882	2
883	2
883	4
883	3
883	5
883	1
884	3
884	4
884	5
884	1
884	2
885	1
885	4
886	5
886	3
887	2
887	3
887	5
887	4
887	1
888	5
888	4
889	1
889	3
890	3
891	3
892	3
892	2
892	4
892	1
893	2
893	4
894	3
895	1
896	5
897	5
898	5
898	1
898	3
899	3
899	1
899	4
900	2
900	5
900	4
900	3
901	5
901	4
901	3
901	1
901	2
902	1
902	3
902	2
903	2
903	5
903	3
903	4
903	1
904	4
904	5
905	2
905	3
905	1
906	1
906	5
906	4
906	3
907	1
907	3
907	5
907	2
908	3
908	5
908	1
908	2
908	4
909	3
910	1
910	2
910	4
910	5
910	3
911	1
911	4
911	3
911	5
911	2
912	4
912	5
913	2
914	3
915	5
915	3
915	4
915	1
916	2
916	5
917	1
917	4
917	3
917	5
917	2
918	3
918	2
919	4
919	2
920	1
921	3
921	1
922	2
922	3
922	5
922	1
922	4
923	4
924	2
924	1
924	3
924	4
924	5
925	4
925	1
925	3
926	4
926	2
926	5
926	1
927	4
927	5
927	2
928	1
928	4
928	2
928	3
928	5
929	5
929	1
929	3
930	4
930	2
930	5
931	3
931	4
931	5
932	3
932	4
932	5
932	2
933	1
933	2
933	4
934	1
934	4
935	1
936	2
937	2
938	2
938	1
939	4
939	5
940	2
940	5
940	3
940	1
941	2
941	4
941	5
941	1
941	3
942	4
942	1
943	4
943	1
944	4
944	1
944	3
944	2
944	5
945	3
945	1
946	2
946	5
946	3
947	3
948	3
948	2
949	3
949	2
949	5
950	4
951	2
951	5
951	4
951	1
952	1
952	4
953	4
953	5
953	2
954	5
954	2
954	1
954	4
954	3
955	3
955	4
955	1
956	2
956	5
956	4
956	3
957	1
958	3
959	1
959	2
959	5
959	4
959	3
960	2
961	4
961	1
961	3
962	4
962	1
962	2
962	3
963	4
963	3
963	5
963	1
964	4
964	5
964	1
964	2
965	2
965	1
965	3
965	4
965	5
966	1
966	4
967	4
968	1
969	2
969	1
969	5
969	3
969	4
970	4
970	3
970	5
971	3
972	4
972	1
972	5
972	3
973	3
973	4
973	5
973	2
973	1
974	4
974	5
974	2
974	1
975	5
975	1
976	1
976	3
976	2
976	5
976	4
977	4
977	1
977	5
978	5
978	3
979	3
979	5
979	1
979	2
980	2
980	5
980	3
980	1
981	5
982	4
983	2
983	3
983	4
984	1
984	4
985	1
985	3
985	5
985	4
986	2
986	5
986	3
986	1
986	4
987	4
987	3
987	5
987	2
988	2
988	3
988	4
988	5
989	5
990	4
990	3
990	2
990	5
990	1
991	4
992	4
992	2
992	1
992	3
992	5
993	1
994	2
995	4
996	2
996	5
996	3
996	1
996	4
997	3
998	5
998	1
998	3
998	4
999	1
999	5
1000	2
1000	3
1000	4
1000	1
1001	1
1001	4
1001	3
1001	2
1002	3
1002	4
1002	5
1002	2
1003	3
1003	2
1003	5
1003	1
1003	4
1004	2
1005	3
1005	5
1006	4
1006	1
1006	5
1006	3
1006	2
1007	1
1007	2
1007	5
1007	4
1007	3
1008	1
1008	4
1008	5
1008	3
1008	2
1009	1
1009	4
1009	5
1009	2
1009	3
1010	1
1010	2
1010	5
1010	3
1011	4
1012	4
1012	1
1012	5
1012	2
1012	3
1013	1
1013	4
1013	5
1013	3
1014	3
1014	2
1014	1
1014	4
1015	3
1015	5
1015	4
1016	5
1016	2
1016	3
1016	1
1016	4
1017	2
1017	3
1018	3
1018	2
1018	5
1018	4
1018	1
1019	4
1019	3
1020	3
1020	1
1020	4
1021	4
1021	1
1021	5
1022	2
1022	3
1022	5
1022	1
1023	2
1023	4
1023	1
1024	5
1024	3
1024	2
1024	4
1025	5
1025	2
1025	1
1026	2
1026	1
1026	5
1026	4
1026	3
1027	2
1027	4
1027	5
1027	3
1027	1
1028	2
1028	4
1028	1
1028	5
1029	5
1030	4
1030	2
1030	5
1030	3
1031	3
1031	4
1031	2
1032	4
1033	4
1034	3
1034	4
1034	1
1035	3
1035	5
1035	2
1036	2
1037	5
1038	1
1038	2
1038	5
1039	5
1039	3
1039	4
1040	3
1040	4
1040	2
1041	3
1041	2
1041	4
1041	5
1042	2
1042	5
1042	3
1043	1
1043	4
1043	3
1043	2
1043	5
1044	5
1044	2
1044	1
1045	3
1046	1
1046	2
1046	4
1047	2
1047	4
1048	3
1048	2
1048	1
1048	5
1048	4
1049	5
1049	3
1049	1
1049	2
1049	4
1050	1
1050	2
1051	4
1051	5
1051	2
1051	1
1052	1
1052	4
1053	3
1054	1
1055	2
1055	5
1056	5
1056	2
1056	1
1056	3
1057	5
1057	1
1057	4
1057	3
1058	5
1058	1
1058	2
1059	4
1059	5
1060	4
1060	5
1060	3
1060	1
1060	2
1061	1
1061	5
1061	3
1061	4
1061	2
1062	2
1063	1
1063	2
1063	5
1063	3
1063	4
1064	1
1064	2
1065	4
1066	4
1066	3
1066	2
1066	5
1067	2
1067	4
1067	5
1067	3
1068	5
1068	3
1069	1
1069	2
1070	5
1070	4
1071	4
1071	5
1072	1
1072	2
1072	4
1073	3
1074	1
1074	4
1075	1
1075	2
1075	4
1075	5
1076	2
1076	3
1076	1
1076	4
1076	5
1077	2
1077	3
1077	5
1078	2
1078	3
1078	4
1079	2
1079	5
1080	2
1080	3
1080	4
1081	3
1081	1
1081	5
1082	1
1082	5
1082	2
1082	3
1083	4
1083	3
1083	5
1084	2
1085	2
1085	4
1085	1
1086	2
1086	5
1086	3
1087	1
1088	3
1088	4
1088	1
1088	2
1089	3
1089	1
1090	5
1090	2
1090	4
1091	4
1091	2
1092	3
1092	2
1093	2
1093	1
1094	5
1094	1
1094	2
1094	3
1094	4
1095	3
1095	1
1095	2
1095	4
1096	4
1096	5
1096	3
1096	1
1097	2
1097	3
1097	4
1097	1
1098	1
1099	5
1099	1
1099	3
1099	4
1099	2
1100	5
1101	1
1101	2
1102	2
1103	3
1103	2
1103	1
1103	5
1103	4
1104	1
1105	2
1105	1
1105	4
1105	5
1106	1
1107	4
1107	5
1107	1
1107	2
1107	3
1108	1
1108	2
1108	4
1109	4
1109	3
1109	5
1109	2
1109	1
1110	5
1110	4
1110	2
1110	3
1111	4
1111	2
1111	3
1111	5
1111	1
1112	2
1112	1
1112	3
1112	5
1113	3
1113	4
1114	5
1114	1
1114	3
1114	2
1115	5
1115	4
1116	1
1117	4
1117	3
1117	1
1117	5
1117	2
1118	3
1118	4
1119	3
1119	4
1119	2
1119	1
1119	5
1120	5
1120	1
1121	1
1121	2
1121	3
1121	4
1121	5
1122	4
1122	1
1122	2
1122	3
1122	5
1123	3
1124	5
1124	1
1124	3
1124	2
1125	4
1125	3
1125	1
1125	5
1126	4
1126	1
1127	5
1127	2
1128	3
1128	1
1129	1
1129	4
1129	2
1129	5
1130	3
1130	4
1131	5
1131	1
1132	4
1132	1
1132	2
1132	3
1133	4
1134	5
1134	2
1134	1
1135	3
1135	1
1135	5
1135	2
1135	4
1136	3
1136	4
1136	1
1137	5
1137	2
1137	4
1137	1
1138	4
1138	3
1138	5
1138	2
1138	1
1139	2
1140	5
1140	4
1140	2
1140	3
1140	1
1141	4
1141	5
1142	5
1142	4
1142	1
1142	3
1142	2
1143	4
1144	5
1144	2
1144	3
1144	1
1144	4
1145	2
1146	2
1146	3
1147	3
1147	4
1147	2
1147	5
1148	1
1148	5
1149	3
1149	2
1150	2
1150	1
1150	4
1151	3
1151	4
1151	1
1151	5
1152	5
1153	1
1153	3
1153	5
1153	4
1154	3
1154	5
1154	4
1154	2
1154	1
1155	3
1155	1
1155	5
1155	4
1156	5
1156	4
1156	2
1156	3
1157	1
1157	5
1157	3
1157	2
1158	2
1158	3
1158	5
1158	1
1158	4
1159	5
1159	3
1160	4
1160	5
1160	1
1160	2
1160	3
1161	5
1161	3
1162	2
1162	3
1163	2
1164	5
1164	2
1164	4
1164	3
1165	3
1165	4
1166	4
1166	2
1166	5
1166	3
1167	4
1167	1
1167	2
1168	2
1168	1
1168	5
1168	3
1169	2
1170	5
1170	4
1170	2
1170	1
1171	3
1171	5
1171	4
1171	1
1171	2
1172	3
1173	3
1174	3
1174	1
1174	4
1175	4
1176	2
1176	1
1176	4
1176	3
1176	5
1177	3
1177	2
1177	1
1177	4
1178	1
1178	2
1178	4
1178	5
1178	3
1179	5
1179	1
1179	2
1179	4
1179	3
1180	4
1180	3
1180	1
1180	2
1181	1
1181	5
1181	3
1181	4
1181	2
1182	3
1182	1
1182	2
1182	5
1183	1
1183	5
1184	1
1184	2
1185	5
1185	3
1185	4
1186	4
1186	3
1187	2
1187	4
1187	1
1187	3
1188	5
1188	2
1188	3
1188	4
1189	2
1189	5
1189	4
1189	3
1190	1
1191	1
1192	3
1193	1
1193	5
1193	3
1193	2
1194	3
1194	5
1194	4
1194	1
1194	2
1195	3
1195	1
1195	2
1196	1
1196	4
1196	5
1197	1
1197	5
1198	5
1198	1
1199	2
1199	4
1199	1
1199	3
1200	2
1200	3
1200	5
1201	1
1202	1
1202	2
1202	4
1203	3
1203	5
1203	4
1203	1
1204	3
1204	4
1204	2
1205	5
1205	4
1205	3
1206	5
1206	1
1206	3
1206	4
1206	2
1207	1
1207	3
1207	5
1208	2
1208	5
1208	4
1208	1
1208	3
1209	5
1209	4
1209	3
1209	2
1210	5
1210	2
1210	3
1210	1
1211	5
1211	3
1211	4
1211	2
1211	1
1212	4
1212	5
1212	1
1213	3
1213	5
1213	4
1213	2
1214	5
1214	3
1215	5
1215	4
1216	5
1217	2
1217	5
1217	4
1218	5
1218	1
1218	4
1218	2
1218	3
1219	3
1219	2
1219	4
1219	5
1220	1
1221	3
1221	2
1221	4
1221	5
1221	1
1222	5
1222	3
1222	2
1223	5
1223	2
1223	1
1224	5
1224	2
1224	3
1225	2
1225	1
1225	4
1225	3
1226	1
1226	2
1227	2
1227	1
1227	5
1227	3
1228	1
1228	4
1228	5
1228	2
1228	3
1229	2
1229	1
1230	5
1230	1
1230	4
1230	2
1230	3
1231	3
1231	2
1232	1
1232	3
1232	2
1233	4
1233	3
1233	5
1234	4
1234	5
1234	2
1234	1
1235	3
1236	3
1236	5
1236	1
1236	2
1237	2
1238	5
1238	2
1239	5
1239	4
1239	3
1240	5
1240	4
1240	1
1240	3
1240	2
1241	2
1241	5
1242	4
1242	5
1242	1
1243	2
1243	1
1243	5
1244	5
1244	2
1245	3
1245	5
1246	4
1246	5
1246	2
1246	3
1247	1
1247	2
1247	4
1247	3
1247	5
1248	2
1248	5
1248	1
1248	4
1249	3
1250	5
1250	2
\.


--
-- Data for Name: passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.passports (id, original_surname, original_name, en_name, en_surname, issue_date, expiration_date, sex, issuer, passport_owner, lost, invalidated) FROM stdin;
1	Sandra	Frye	Sandra	Frye	1998-08-20	2018-09-24	F	7	1	f	f
2	Tyler	Brandt	Tyler	Brandt	1973-04-01	1993-06-16	M	599	2	f	f
3	Amanda	Hayes	Amanda	Hayes	1973-08-26	1993-11-13	F	902	3	f	f
4	Anthony	Knight	Anthony	Knight	1948-05-28	1968-07-16	M	1106	4	f	f
5	Lawrence	Suarez	Lawrence	Suarez	1948-08-07	1968-03-26	F	1010	5	f	f
6	Tamara	Snyder	Tamara	Snyder	1948-12-26	1968-11-08	M	37	6	f	f
7	Timothy	Elliott	Timothy	Elliott	1948-03-06	1968-07-01	F	498	7	f	f
8	Jamie	Smith	Jamie	Smith	1923-12-18	1943-07-08	M	1052	8	f	f
9	Nicole	Martinez	Nicole	Martinez	1923-06-09	1943-10-11	F	1158	9	f	f
10	Kyle	Foster	Kyle	Foster	1923-03-06	1943-05-01	M	287	10	f	f
11	Logan	Adams	Logan	Adams	1923-05-03	1943-12-13	F	378	11	f	f
12	Paul	Hanson	Paul	Hanson	1923-09-16	1943-06-03	M	553	12	f	f
13	Michael	Cole	Michael	Cole	1923-07-10	1943-10-17	F	842	13	f	f
14	Robert	Foster	Robert	Foster	1923-03-28	1943-08-14	M	357	14	f	f
15	Brandon	Rodriguez	Brandon	Rodriguez	1923-05-16	1943-08-28	F	506	15	f	f
16	Melinda	Evans	Melinda	Evans	1898-09-10	1918-04-01	M	510	16	f	f
17	Emily	George	Emily	George	1898-06-20	1918-09-18	F	288	17	f	f
18	John	Nelson	John	Nelson	1898-10-28	1918-01-14	M	877	18	f	f
19	Julie	Crane	Julie	Crane	1898-11-08	1918-04-20	F	296	19	f	f
20	Sandra	Smith	Sandra	Smith	1898-06-09	1918-09-08	M	374	20	f	f
21	Tony	Harris	Tony	Harris	1898-03-16	1918-09-14	F	821	21	f	f
22	Calvin	Garza	Calvin	Garza	1898-09-18	1918-08-05	M	645	22	f	f
23	Aaron	Calhoun	Aaron	Calhoun	1898-05-08	1918-05-22	F	529	23	f	f
24	Crystal	Scott	Crystal	Scott	1898-12-09	1918-03-08	M	9	24	f	f
25	Walter	Bowen	Walter	Bowen	1898-12-08	1918-04-12	F	620	25	f	f
26	Lucas	Austin	Lucas	Austin	1898-02-05	1918-07-14	M	1000	26	f	f
27	Kristen	Long	Kristen	Long	1898-12-05	1918-04-02	F	680	27	f	f
28	Christina	Taylor	Christina	Taylor	1898-09-17	1918-06-12	M	1135	28	f	f
29	Melissa	Thomas	Melissa	Thomas	1898-01-09	1918-03-07	F	119	29	f	f
30	Robert	Fuller	Robert	Fuller	1898-05-22	1918-06-23	M	529	30	f	f
31	Whitney	Harris	Whitney	Harris	1898-07-28	1918-03-21	F	1135	31	f	f
32	Andrea	Shepard	Andrea	Shepard	1873-07-13	1893-04-21	M	743	32	f	f
33	Luis	Barron	Luis	Barron	1873-08-02	1893-12-05	F	344	33	f	f
34	David	Weaver	David	Weaver	1873-10-17	1893-12-19	M	821	34	f	f
35	Emma	Matthews	Emma	Matthews	1873-02-27	1893-08-25	F	494	35	f	f
36	Allen	Gallagher	Allen	Gallagher	1873-04-20	1893-11-28	M	498	36	f	f
37	Ryan	Luna	Ryan	Luna	1873-10-10	1893-08-01	F	1179	37	f	f
38	Alejandro	Brown	Alejandro	Brown	1873-05-17	1893-06-03	M	768	38	f	f
39	Emily	Ayers	Emily	Ayers	1873-08-09	1893-01-01	F	199	39	f	f
40	Gina	Clay	Gina	Clay	1873-08-22	1893-05-24	M	469	40	f	f
41	Amanda	Davenport	Amanda	Davenport	1873-03-25	1893-10-09	F	648	41	f	f
42	Toni	Miller	Toni	Miller	1873-08-01	1893-12-27	M	734	42	f	f
43	Jeffrey	Ryan	Jeffrey	Ryan	1873-01-24	1893-02-09	F	608	43	f	f
44	John	Smith	John	Smith	1873-09-16	1893-09-20	M	800	44	f	f
45	Kristin	Williams	Kristin	Williams	1873-03-23	1893-02-19	F	954	45	f	f
46	Tracy	Caldwell	Tracy	Caldwell	1873-10-24	1893-09-13	M	174	46	f	f
47	Alan	Nunez	Alan	Nunez	1873-01-06	1893-08-12	F	1208	47	f	f
48	Amber	Green	Amber	Green	1873-05-04	1893-10-14	M	700	48	f	f
49	Darryl	Olson	Darryl	Olson	1873-11-08	1893-09-23	F	571	49	f	f
50	Brenda	Rollins	Brenda	Rollins	1873-06-08	1893-08-26	M	1248	50	f	f
51	Grant	Roberson	Grant	Roberson	1873-04-26	1893-06-22	F	59	51	f	f
52	Lauren	Wood	Lauren	Wood	1873-02-07	1893-11-24	M	700	52	f	f
53	Jon	Dickson	Jon	Dickson	1873-03-27	1893-03-06	F	822	53	f	f
54	Kyle	Gonzales	Kyle	Gonzales	1873-01-10	1893-07-13	M	354	54	f	f
55	Jessica	White	Jessica	White	1873-07-08	1893-10-28	F	1142	55	f	f
56	Tyler	Salazar	Tyler	Salazar	1873-10-09	1893-09-03	M	554	56	f	f
57	Paul	Wheeler	Paul	Wheeler	1873-03-11	1893-03-26	F	1125	57	f	f
58	Kyle	Blake	Kyle	Blake	1873-11-23	1893-07-02	M	1096	58	f	f
59	Nicholas	Bowen	Nicholas	Bowen	1873-09-05	1893-04-12	F	957	59	f	f
60	Kristopher	Hancock	Kristopher	Hancock	1873-01-25	1893-09-03	M	720	60	f	f
61	Hector	Edwards	Hector	Edwards	1873-12-06	1893-08-17	F	817	61	f	f
62	Cindy	Marquez	Cindy	Marquez	1873-11-19	1893-06-10	M	12	62	f	f
63	John	Simmons	John	Simmons	1873-08-07	1893-10-26	F	797	63	f	f
64	Edward	Grant	Edward	Grant	1848-05-09	1868-03-11	M	130	64	f	f
65	Samuel	Nielsen	Samuel	Nielsen	1848-07-27	1868-07-08	F	1181	65	f	f
66	Scott	Guerrero	Scott	Guerrero	1848-09-20	1868-02-26	M	162	66	f	f
67	Jennifer	Jones	Jennifer	Jones	1848-03-26	1868-01-23	F	756	67	f	f
68	Thomas	Neal	Thomas	Neal	1848-08-14	1868-02-08	M	676	68	f	f
69	Steven	Morgan	Steven	Morgan	1848-08-18	1868-01-25	F	174	69	f	f
70	Stephen	Bender	Stephen	Bender	1848-10-02	1868-09-23	M	185	70	f	f
71	Rebecca	Haynes	Rebecca	Haynes	1848-11-23	1868-04-19	F	1021	71	f	f
72	Corey	Daniels	Corey	Daniels	1848-01-17	1868-08-18	M	920	72	f	f
73	Julie	Martinez	Julie	Martinez	1848-10-15	1868-04-28	F	804	73	f	f
74	Kyle	Tucker	Kyle	Tucker	1848-04-17	1868-10-06	M	65	74	f	f
75	Nathan	Martin	Nathan	Martin	1848-06-13	1868-03-23	F	1240	75	f	f
76	Levi	Long	Levi	Long	1848-11-07	1868-07-27	M	12	76	f	f
77	Zachary	Jackson	Zachary	Jackson	1848-05-08	1868-05-28	F	594	77	f	f
78	Juan	Smith	Juan	Smith	1848-08-24	1868-02-09	M	207	78	f	f
79	Michael	Young	Michael	Young	1848-10-12	1868-08-19	F	660	79	f	f
80	Carolyn	Rivera	Carolyn	Rivera	1848-12-02	1868-09-13	M	360	80	f	f
81	John	Robinson	John	Robinson	1848-06-13	1868-09-24	F	1206	81	f	f
82	Justin	Hughes	Justin	Hughes	1848-06-04	1868-09-22	M	1046	82	f	f
83	Michael	Murillo	Michael	Murillo	1848-11-02	1868-01-03	F	1058	83	f	f
84	Wyatt	Brennan	Wyatt	Brennan	1848-08-18	1868-06-20	M	875	84	f	f
85	Christy	Obrien	Christy	Obrien	1848-02-10	1868-04-02	F	806	85	f	f
86	Martin	Greer	Martin	Greer	1848-08-08	1868-09-16	M	1119	86	f	f
87	Cynthia	Walker	Cynthia	Walker	1848-07-16	1868-01-16	F	961	87	f	f
88	Adam	Hunt	Adam	Hunt	1848-10-06	1868-07-08	M	820	88	f	f
89	Joseph	Nelson	Joseph	Nelson	1848-01-02	1868-08-11	F	258	89	f	f
90	Damon	Valenzuela	Damon	Valenzuela	1848-03-14	1868-06-20	M	996	90	f	f
91	Linda	Golden	Linda	Golden	1848-12-19	1868-02-27	F	214	91	f	f
92	Richard	Flores	Richard	Flores	1848-06-08	1868-05-08	M	627	92	f	f
93	Matthew	Tucker	Matthew	Tucker	1848-03-18	1868-06-27	F	783	93	f	f
94	Rebecca	Hughes	Rebecca	Hughes	1848-03-26	1868-02-07	M	619	94	f	f
95	Jennifer	Nelson	Jennifer	Nelson	1848-05-09	1868-12-27	F	51	95	f	f
96	Megan	Davis	Megan	Davis	1848-05-16	1868-08-28	M	363	96	f	f
97	Daniel	Wilson	Daniel	Wilson	1848-04-26	1868-11-17	F	226	97	f	f
98	Henry	Carrillo	Henry	Carrillo	1848-07-26	1868-01-10	M	443	98	f	f
99	Dalton	Henderson	Dalton	Henderson	1848-05-27	1868-04-24	F	679	99	f	f
100	James	Hill	James	Hill	1848-12-21	1868-07-02	M	357	100	f	f
101	Patricia	Garcia	Patricia	Garcia	1848-12-03	1868-07-05	F	933	101	f	f
102	John	Hawkins	John	Hawkins	1848-09-09	1868-06-11	M	591	102	f	f
103	Danielle	Phillips	Danielle	Phillips	1848-05-01	1868-04-08	F	491	103	f	f
104	Michael	Davis	Michael	Davis	1848-09-05	1868-08-20	M	554	104	f	f
105	Danielle	Anderson	Danielle	Anderson	1848-06-03	1868-04-23	F	820	105	f	f
106	Lisa	Rodriguez	Lisa	Rodriguez	1848-12-09	1868-06-19	M	1008	106	f	f
107	Ryan	Jenkins	Ryan	Jenkins	1848-02-07	1868-10-05	F	779	107	f	f
108	Scott	Patterson	Scott	Patterson	1848-12-01	1868-02-25	M	351	108	f	f
109	John	Gonzalez	John	Gonzalez	1848-03-11	1868-03-03	F	658	109	f	f
110	Kathy	Fry	Kathy	Fry	1848-05-23	1868-09-28	M	488	110	f	f
111	Kelly	Mejia	Kelly	Mejia	1848-06-04	1868-08-08	F	681	111	f	f
112	Lisa	Le	Lisa	Le	1848-08-13	1868-10-27	M	221	112	f	f
113	John	Nelson	John	Nelson	1848-10-23	1868-02-16	F	47	113	f	f
114	Angela	Marsh	Angela	Marsh	1848-03-22	1868-02-24	M	361	114	f	f
115	Jonathan	Edwards	Jonathan	Edwards	1848-10-22	1868-08-27	F	720	115	f	f
116	David	Williams	David	Williams	1848-07-15	1868-01-20	M	1197	116	f	f
117	Kristin	Gonzalez	Kristin	Gonzalez	1848-03-07	1868-11-06	F	880	117	f	f
118	Susan	Neal	Susan	Neal	1848-10-21	1868-11-17	M	1025	118	f	f
119	Lucas	Gilbert	Lucas	Gilbert	1848-01-26	1868-02-10	F	1094	119	f	f
120	Cody	Meyer	Cody	Meyer	1848-11-09	1868-05-04	M	1116	120	f	f
121	Michelle	Ross	Michelle	Ross	1848-03-08	1868-12-02	F	68	121	f	f
122	Donna	Daniels	Donna	Daniels	1848-03-16	1868-08-12	M	707	122	f	f
123	Joel	Miller	Joel	Miller	1848-03-06	1868-12-08	F	493	123	f	f
124	Jennifer	Johnson	Jennifer	Johnson	1848-12-14	1868-10-09	M	1008	124	f	f
125	Maurice	Smith	Maurice	Smith	1848-06-14	1868-12-24	F	296	125	f	f
126	Ryan	Matthews	Ryan	Matthews	1848-12-06	1868-09-04	M	455	126	f	f
127	Sharon	Perry	Sharon	Perry	1848-02-07	1868-01-23	F	472	127	f	f
128	Ashley	Reed	Ashley	Reed	1823-07-10	1843-01-07	M	686	128	f	f
129	Teresa	Shaw	Teresa	Shaw	1823-03-04	1843-11-28	F	933	129	f	f
130	Stacy	Jenkins	Stacy	Jenkins	1823-07-05	1843-03-14	M	231	130	f	f
131	David	Brooks	David	Brooks	1823-07-18	1843-01-02	F	245	131	f	f
132	Angelica	Reyes	Angelica	Reyes	1823-11-08	1843-02-08	M	732	132	f	f
133	Natalie	Holmes	Natalie	Holmes	1823-03-21	1843-03-26	F	1108	133	f	f
134	Joshua	Flores	Joshua	Flores	1823-01-19	1843-07-24	M	1128	134	f	f
135	Melissa	Young	Melissa	Young	1823-03-26	1843-10-22	F	394	135	f	f
136	Tracey	Williams	Tracey	Williams	1823-09-21	1843-08-06	M	724	136	f	f
137	Jessica	Rubio	Jessica	Rubio	1823-01-13	1843-02-16	F	226	137	f	f
138	Darlene	Kelley	Darlene	Kelley	1823-08-21	1843-04-16	M	898	138	f	f
139	Sherry	Melton	Sherry	Melton	1823-09-10	1843-11-13	F	241	139	f	f
140	Emily	Garner	Emily	Garner	1823-07-10	1843-09-11	M	346	140	f	f
141	Amber	Dickerson	Amber	Dickerson	1823-12-27	1843-02-17	F	738	141	f	f
142	Kathryn	Leach	Kathryn	Leach	1823-05-12	1843-09-20	M	710	142	f	f
143	Andrew	Scott	Andrew	Scott	1823-02-10	1843-03-05	F	37	143	f	f
144	Jerry	Grant	Jerry	Grant	1823-06-25	1843-10-18	M	602	144	f	f
145	Wesley	Cross	Wesley	Cross	1823-10-27	1843-12-01	F	499	145	f	f
146	Randy	Miller	Randy	Miller	1823-05-01	1843-06-21	M	693	146	f	f
147	Jamie	Vaughn	Jamie	Vaughn	1823-07-22	1843-11-25	F	352	147	f	f
148	Melissa	Callahan	Melissa	Callahan	1823-05-02	1843-08-24	M	175	148	f	f
149	Samantha	Williams	Samantha	Williams	1823-01-12	1843-05-01	F	117	149	f	f
150	Cathy	Michael	Cathy	Michael	1823-12-22	1843-04-17	M	1203	150	f	f
151	Abigail	Patterson	Abigail	Patterson	1823-08-04	1843-10-23	F	234	151	f	f
152	Allison	Dudley	Allison	Dudley	1823-01-14	1843-06-26	M	332	152	f	f
153	Kaitlyn	Peters	Kaitlyn	Peters	1823-04-07	1843-10-07	F	1120	153	f	f
154	Darlene	Byrd	Darlene	Byrd	1823-11-20	1843-06-23	M	86	154	f	f
155	David	Huang	David	Huang	1823-08-22	1843-01-05	F	355	155	f	f
156	Phillip	Sullivan	Phillip	Sullivan	1823-04-27	1843-01-12	M	245	156	f	f
157	Morgan	Duncan	Morgan	Duncan	1823-10-10	1843-01-15	F	241	157	f	f
158	Danielle	Martinez	Danielle	Martinez	1823-07-28	1843-09-24	M	344	158	f	f
159	Natasha	Grant	Natasha	Grant	1823-03-16	1843-02-16	F	553	159	f	f
160	Stephanie	Wheeler	Stephanie	Wheeler	1823-09-12	1843-02-07	M	578	160	f	f
161	Raymond	Terrell	Raymond	Terrell	1823-03-12	1843-12-11	F	686	161	f	f
162	Krista	Marquez	Krista	Marquez	1823-05-01	1843-07-11	M	998	162	f	f
163	Tamara	Tucker	Tamara	Tucker	1823-08-07	1843-07-17	F	569	163	f	f
164	Connie	Garza	Connie	Garza	1823-11-14	1843-12-11	M	293	164	f	f
165	David	King	David	King	1823-01-18	1843-04-23	F	601	165	f	f
166	Tracey	Ponce	Tracey	Ponce	1823-04-10	1843-01-15	M	907	166	f	f
167	Michael	Morrow	Michael	Morrow	1823-09-27	1843-08-14	F	558	167	f	f
168	Laura	Richardson	Laura	Richardson	1823-03-08	1843-01-14	M	823	168	f	f
169	Melinda	Atkins	Melinda	Atkins	1823-06-22	1843-01-23	F	619	169	f	f
170	Pamela	Robinson	Pamela	Robinson	1823-03-25	1843-02-23	M	895	170	f	f
171	Tara	Murray	Tara	Murray	1823-03-14	1843-02-22	F	326	171	f	f
172	Elizabeth	Glover	Elizabeth	Glover	1823-02-18	1843-02-01	M	882	172	f	f
173	Dennis	Gomez	Dennis	Gomez	1823-08-23	1843-09-13	F	788	173	f	f
174	Jenna	Schroeder	Jenna	Schroeder	1823-12-19	1843-10-11	M	876	174	f	f
175	Amber	Hill	Amber	Hill	1823-09-22	1843-11-18	F	806	175	f	f
176	Brittany	Kim	Brittany	Kim	1823-07-12	1843-12-04	M	817	176	f	f
177	Diana	Hall	Diana	Hall	1823-10-09	1843-06-05	F	1206	177	f	f
178	Logan	Morris	Logan	Morris	1823-09-28	1843-12-26	M	267	178	f	f
179	Ashley	Delgado	Ashley	Delgado	1823-11-28	1843-01-08	F	555	179	f	f
180	Rachel	Frederick	Rachel	Frederick	1823-11-05	1843-05-25	M	715	180	f	f
181	Rachel	Andrews	Rachel	Andrews	1823-06-11	1843-07-23	F	720	181	f	f
182	Mario	Harris	Mario	Harris	1823-05-05	1843-08-02	M	1064	182	f	f
183	Scott	Martin	Scott	Martin	1823-11-18	1843-09-15	F	99	183	f	f
184	Alyssa	Williams	Alyssa	Williams	1823-11-20	1843-06-08	M	871	184	f	f
185	Steven	Silva	Steven	Silva	1823-11-03	1843-12-09	F	193	185	f	f
186	John	Knox	John	Knox	1823-10-01	1843-02-20	M	173	186	f	f
187	Donna	Green	Donna	Green	1823-02-06	1843-12-15	F	965	187	f	f
188	Natalie	Taylor	Natalie	Taylor	1823-07-07	1843-08-13	M	29	188	f	f
189	Robert	Lam	Robert	Lam	1823-03-14	1843-09-18	F	1009	189	f	f
190	Nathan	Campbell	Nathan	Campbell	1823-05-14	1843-09-17	M	915	190	f	f
191	Crystal	Meza	Crystal	Meza	1823-08-03	1843-03-20	F	986	191	f	f
192	Robert	Lane	Robert	Lane	1823-04-18	1843-01-03	M	87	192	f	f
193	Valerie	Wade	Valerie	Wade	1823-04-12	1843-03-28	F	696	193	f	f
194	Tiffany	Patterson	Tiffany	Patterson	1823-07-26	1843-04-13	M	224	194	f	f
195	Stephanie	Garza	Stephanie	Garza	1823-07-12	1843-07-14	F	72	195	f	f
196	Kimberly	Shields	Kimberly	Shields	1823-05-01	1843-01-14	M	1176	196	f	f
197	Austin	Martinez	Austin	Martinez	1823-05-10	1843-01-24	F	146	197	f	f
198	Timothy	Carter	Timothy	Carter	1823-06-05	1843-09-06	M	1187	198	f	f
199	Timothy	Harris	Timothy	Harris	1823-07-22	1843-03-27	F	113	199	f	f
200	Martin	Riley	Martin	Riley	1823-05-05	1843-07-05	M	504	200	f	f
201	Walter	Clarke	Walter	Clarke	1823-02-23	1843-03-09	F	592	201	f	f
202	Kayla	Herrera	Kayla	Herrera	1823-07-19	1843-08-18	M	1104	202	f	f
203	William	Adams	William	Adams	1823-03-10	1843-10-17	F	877	203	f	f
204	Bryan	Blackwell	Bryan	Blackwell	1823-09-15	1843-06-03	M	370	204	f	f
205	Donald	Anderson	Donald	Anderson	1823-01-07	1843-01-17	F	1058	205	f	f
206	Jonathan	Gutierrez	Jonathan	Gutierrez	1823-09-06	1843-11-04	M	350	206	f	f
207	Jennifer	Marquez	Jennifer	Marquez	1823-11-08	1843-12-05	F	740	207	f	f
208	Kelsey	Smith	Kelsey	Smith	1823-04-26	1843-11-03	M	895	208	f	f
209	Mark	Ware	Mark	Ware	1823-11-20	1843-06-16	F	13	209	f	f
210	Jonathan	Haynes	Jonathan	Haynes	1823-05-10	1843-10-02	M	1014	210	f	f
211	Sandra	Kirk	Sandra	Kirk	1823-05-16	1843-03-20	F	993	211	f	f
212	Elizabeth	Pope	Elizabeth	Pope	1823-12-13	1843-10-11	M	707	212	f	f
213	Misty	Hart	Misty	Hart	1823-12-26	1843-03-16	F	1034	213	f	f
214	Darrell	Moyer	Darrell	Moyer	1823-05-11	1843-01-26	M	441	214	f	f
215	Bernard	Mann	Bernard	Mann	1823-02-09	1843-09-23	F	645	215	f	f
216	Jerry	Huffman	Jerry	Huffman	1823-08-25	1843-03-05	M	634	216	f	f
217	Chad	Park	Chad	Park	1823-03-16	1843-05-17	F	556	217	f	f
218	Pamela	Wagner	Pamela	Wagner	1823-09-11	1843-06-22	M	620	218	f	f
219	Lauren	Lamb	Lauren	Lamb	1823-12-17	1843-01-25	F	376	219	f	f
220	Sandra	Wright	Sandra	Wright	1823-08-04	1843-07-23	M	1183	220	f	f
221	Kathryn	Cain	Kathryn	Cain	1823-08-24	1843-08-26	F	814	221	f	f
222	Molly	Newman	Molly	Newman	1823-07-05	1843-02-04	M	938	222	f	f
223	Keith	Wallace	Keith	Wallace	1823-06-22	1843-07-16	F	60	223	f	f
224	Rebecca	Hogan	Rebecca	Hogan	1823-10-27	1843-01-27	M	1061	224	f	f
225	Daniel	Chen	Daniel	Chen	1823-05-14	1843-04-16	F	36	225	f	f
226	Jason	Stewart	Jason	Stewart	1823-10-05	1843-06-09	M	55	226	f	f
227	Christopher	Bailey	Christopher	Bailey	1823-04-26	1843-11-12	F	147	227	f	f
228	Phillip	Martin	Phillip	Martin	1823-07-19	1843-09-12	M	553	228	f	f
229	Kelsey	Mayo	Kelsey	Mayo	1823-09-09	1843-11-18	F	1144	229	f	f
230	Karen	Thompson	Karen	Thompson	1823-02-22	1843-05-14	M	327	230	f	f
231	Jamie	Atkins	Jamie	Atkins	1823-04-05	1843-10-23	F	291	231	f	f
232	Edward	Strong	Edward	Strong	1823-04-14	1843-07-19	M	521	232	f	f
233	Stacy	Kim	Stacy	Kim	1823-07-11	1843-09-03	F	460	233	f	f
234	Bryan	Ross	Bryan	Ross	1823-09-02	1843-12-09	M	492	234	f	f
235	David	Kirby	David	Kirby	1823-12-15	1843-01-07	F	174	235	f	f
236	Andrew	Freeman	Andrew	Freeman	1823-05-07	1843-02-20	M	510	236	f	f
237	Jennifer	Hudson	Jennifer	Hudson	1823-09-14	1843-09-26	F	411	237	f	f
238	Scott	Moreno	Scott	Moreno	1823-09-24	1843-05-12	M	917	238	f	f
239	Shannon	King	Shannon	King	1823-08-02	1843-03-14	F	486	239	f	f
240	Kristen	Thomas	Kristen	Thomas	1823-05-19	1843-12-12	M	729	240	f	f
241	Brittany	Dickerson	Brittany	Dickerson	1823-05-21	1843-12-08	F	327	241	f	f
242	Laura	Robles	Laura	Robles	1823-12-13	1843-11-19	M	972	242	f	f
243	Rick	Murphy	Rick	Murphy	1823-09-21	1843-12-25	F	19	243	f	f
244	Jennifer	Black	Jennifer	Black	1823-02-15	1843-11-20	M	394	244	f	f
245	Janet	Nelson	Janet	Nelson	1823-05-04	1843-11-10	F	482	245	f	f
246	Susan	Smith	Susan	Smith	1823-02-15	1843-05-10	M	1180	246	f	f
247	Chad	Nelson	Chad	Nelson	1823-12-20	1843-09-12	F	990	247	f	f
248	Cesar	Peterson	Cesar	Peterson	1823-02-17	1843-10-18	M	1154	248	f	f
249	Amanda	Green	Amanda	Green	1823-09-02	1843-09-03	F	687	249	f	f
250	Jennifer	Brown	Jennifer	Brown	1823-03-11	1843-02-14	M	660	250	f	f
251	Rebecca	Novak	Rebecca	Novak	1823-05-25	1843-12-25	F	861	251	f	f
252	Michael	Smith	Michael	Smith	1823-07-18	1843-09-02	M	267	252	f	f
253	Melissa	Barron	Melissa	Barron	1823-08-08	1843-12-26	F	980	253	f	f
254	Aaron	Richardson	Aaron	Richardson	1823-10-24	1843-12-03	M	232	254	f	f
255	Patrick	Jacobs	Patrick	Jacobs	1823-12-15	1843-03-25	F	1050	255	f	f
256	Crystal	Braun	Crystal	Braun	1798-02-12	1818-01-20	M	87	256	f	f
257	John	Mullen	John	Mullen	1798-02-02	1818-08-14	F	718	257	f	f
258	Rachel	Martinez	Rachel	Martinez	1798-05-28	1818-12-01	M	1074	258	f	f
259	Joseph	Lawson	Joseph	Lawson	1798-12-22	1818-01-03	F	147	259	f	f
260	Dana	Hicks	Dana	Hicks	1798-04-03	1818-12-08	M	885	260	f	f
261	Jillian	Russell	Jillian	Russell	1798-12-25	1818-08-21	F	346	261	f	f
262	Scott	Williams	Scott	Williams	1798-10-03	1818-08-25	M	212	262	f	f
263	Ronald	Sharp	Ronald	Sharp	1798-11-26	1818-10-07	F	29	263	f	f
264	Ronald	Rodriguez	Ronald	Rodriguez	1798-06-11	1818-10-27	M	966	264	f	f
265	Christopher	Davis	Christopher	Davis	1798-11-15	1818-05-05	F	969	265	f	f
266	Maria	Fletcher	Maria	Fletcher	1798-09-24	1818-01-08	M	25	266	f	f
267	James	Chambers	James	Chambers	1798-10-25	1818-03-20	F	1105	267	f	f
268	Michael	Morris	Michael	Morris	1798-08-07	1818-07-20	M	470	268	f	f
269	Deborah	Williams	Deborah	Williams	1798-10-03	1818-10-08	F	1187	269	f	f
270	Patrick	Jimenez	Patrick	Jimenez	1798-05-06	1818-08-13	M	524	270	f	f
271	Debra	Rojas	Debra	Rojas	1798-06-08	1818-09-24	F	1221	271	f	f
272	Amy	Mitchell	Amy	Mitchell	1798-02-04	1818-06-17	M	1087	272	f	f
273	Angela	Macias	Angela	Macias	1798-11-21	1818-01-20	F	808	273	f	f
274	Jessica	Young	Jessica	Young	1798-08-16	1818-06-05	M	808	274	f	f
275	Lance	Evans	Lance	Evans	1798-04-21	1818-05-09	F	155	275	f	f
276	Nicholas	Phillips	Nicholas	Phillips	1798-07-27	1818-09-27	M	795	276	f	f
277	Robert	Smith	Robert	Smith	1798-12-05	1818-06-02	F	547	277	f	f
278	Lori	Kennedy	Lori	Kennedy	1798-07-22	1818-03-18	M	298	278	f	f
279	Wesley	Williams	Wesley	Williams	1798-05-28	1818-10-08	F	26	279	f	f
280	Kevin	Bailey	Kevin	Bailey	1798-12-17	1818-06-03	M	968	280	f	f
281	Kimberly	Finley	Kimberly	Finley	1798-06-13	1818-02-26	F	3	281	f	f
282	Mitchell	Madden	Mitchell	Madden	1798-02-03	1818-03-05	M	7	282	f	f
283	Sophia	Williams	Sophia	Williams	1798-03-25	1818-05-28	F	44	283	f	f
284	Craig	Luna	Craig	Luna	1798-07-25	1818-10-26	M	529	284	f	f
285	Jeff	Ramirez	Jeff	Ramirez	1798-06-10	1818-06-22	F	544	285	f	f
286	Angelica	Owens	Angelica	Owens	1798-08-13	1818-07-02	M	565	286	f	f
287	Crystal	Mitchell	Crystal	Mitchell	1798-11-14	1818-01-28	F	130	287	f	f
288	Carrie	Holloway	Carrie	Holloway	1798-09-19	1818-09-01	M	569	288	f	f
289	Alicia	Clark	Alicia	Clark	1798-12-01	1818-02-02	F	230	289	f	f
290	Michael	Gonzalez	Michael	Gonzalez	1798-11-17	1818-09-12	M	359	290	f	f
291	Carlos	Griffith	Carlos	Griffith	1798-07-27	1818-01-10	F	90	291	f	f
292	Gary	Dean	Gary	Dean	1798-12-24	1818-06-21	M	1191	292	f	f
293	Kevin	Smith	Kevin	Smith	1798-02-13	1818-03-27	F	748	293	f	f
294	Travis	Jensen	Travis	Jensen	1798-09-08	1818-06-27	M	1021	294	f	f
295	Elizabeth	Nichols	Elizabeth	Nichols	1798-09-04	1818-01-09	F	203	295	f	f
296	Sean	Castillo	Sean	Castillo	1798-04-20	1818-10-01	M	102	296	f	f
297	David	Yu	David	Yu	1798-03-18	1818-07-27	F	21	297	f	f
298	Edward	Davis	Edward	Davis	1798-04-10	1818-02-11	M	1087	298	f	f
299	Donna	David	Donna	David	1798-07-11	1818-09-23	F	572	299	f	f
300	Lisa	Moss	Lisa	Moss	1798-04-17	1818-10-02	M	820	300	f	f
301	Frank	Robinson	Frank	Robinson	1798-09-08	1818-06-22	F	907	301	f	f
302	Courtney	Moore	Courtney	Moore	1798-03-21	1818-01-26	M	499	302	f	f
303	Samantha	Gill	Samantha	Gill	1798-03-01	1818-08-18	F	251	303	f	f
304	Betty	Bauer	Betty	Bauer	1798-04-25	1818-05-05	M	1193	304	f	f
305	Matthew	Vang	Matthew	Vang	1798-02-11	1818-12-02	F	822	305	f	f
306	Jessica	Mata	Jessica	Mata	1798-03-23	1818-12-18	M	1184	306	f	f
307	Karen	Jones	Karen	Jones	1798-11-16	1818-12-06	F	1028	307	f	f
308	Robert	Garza	Robert	Garza	1798-04-12	1818-09-22	M	544	308	f	f
309	Charles	Norton	Charles	Norton	1798-06-08	1818-01-28	F	590	309	f	f
310	Daniel	Garner	Daniel	Garner	1798-12-23	1818-02-13	M	712	310	f	f
311	David	Singleton	David	Singleton	1798-04-05	1818-07-12	F	578	311	f	f
312	Justin	Baker	Justin	Baker	1798-02-04	1818-09-12	M	83	312	f	f
313	Heather	Taylor	Heather	Taylor	1798-04-02	1818-11-07	F	248	313	f	f
314	Brandon	Velasquez	Brandon	Velasquez	1798-11-16	1818-07-06	M	434	314	f	f
315	Adam	Black	Adam	Black	1798-10-15	1818-07-12	F	855	315	f	f
316	Albert	Smith	Albert	Smith	1798-01-20	1818-11-15	M	679	316	f	f
317	David	Barnes	David	Barnes	1798-05-04	1818-10-26	F	20	317	f	f
318	Katherine	Benjamin	Katherine	Benjamin	1798-08-11	1818-09-19	M	72	318	f	f
319	Amber	Lopez	Amber	Lopez	1798-02-20	1818-12-17	F	929	319	f	f
320	Cynthia	Phelps	Cynthia	Phelps	1798-12-18	1818-04-06	M	1197	320	f	f
321	Jonathon	Hurley	Jonathon	Hurley	1798-02-10	1818-01-12	F	291	321	f	f
322	Evan	Bowers	Evan	Bowers	1798-10-19	1818-08-26	M	776	322	f	f
323	Kristen	Wolfe	Kristen	Wolfe	1798-04-11	1818-07-14	F	639	323	f	f
324	Christopher	Lee	Christopher	Lee	1798-11-26	1818-06-05	M	199	324	f	f
325	Kristin	Sawyer	Kristin	Sawyer	1798-11-25	1818-10-07	F	441	325	f	f
326	Nicholas	Dickerson	Nicholas	Dickerson	1798-04-17	1818-03-06	M	230	326	f	f
327	Katherine	Figueroa	Katherine	Figueroa	1798-06-24	1818-06-05	F	807	327	f	f
328	Lisa	Le	Lisa	Le	1798-08-11	1818-12-23	M	1134	328	f	f
329	Jon	Thornton	Jon	Thornton	1798-09-26	1818-09-09	F	590	329	f	f
330	David	Wilkins	David	Wilkins	1798-08-19	1818-09-01	M	807	330	f	f
331	Michael	Nash	Michael	Nash	1798-11-05	1818-07-24	F	161	331	f	f
332	Olivia	George	Olivia	George	1798-03-03	1818-10-06	M	638	332	f	f
333	Benjamin	Oneill	Benjamin	Oneill	1798-09-15	1818-02-22	F	1050	333	f	f
334	Scott	Ashley	Scott	Ashley	1798-08-23	1818-05-28	M	1096	334	f	f
335	Edward	Frank	Edward	Frank	1798-05-20	1818-09-03	F	352	335	f	f
336	Tamara	Flores	Tamara	Flores	1798-06-10	1818-11-25	M	641	336	f	f
337	Jerry	Ramsey	Jerry	Ramsey	1798-09-23	1818-01-20	F	972	337	f	f
338	Anna	Merritt	Anna	Merritt	1798-11-23	1818-12-01	M	231	338	f	f
339	Laurie	Benson	Laurie	Benson	1798-07-06	1818-04-04	F	298	339	f	f
340	Matthew	Sandoval	Matthew	Sandoval	1798-02-13	1818-08-08	M	761	340	f	f
341	Jerry	Taylor	Jerry	Taylor	1798-02-01	1818-06-26	F	373	341	f	f
342	Robert	Garcia	Robert	Garcia	1798-05-17	1818-04-13	M	52	342	f	f
343	Ashley	Keller	Ashley	Keller	1798-05-03	1818-06-07	F	692	343	f	f
344	Melissa	Thompson	Melissa	Thompson	1798-06-06	1818-01-25	M	450	344	f	f
345	Kathleen	Gray	Kathleen	Gray	1798-08-02	1818-08-20	F	776	345	f	f
346	Ryan	Cochran	Ryan	Cochran	1798-12-02	1818-12-01	M	1096	346	f	f
347	Ashley	Wilkinson	Ashley	Wilkinson	1798-02-21	1818-04-05	F	776	347	f	f
348	Jacqueline	Yates	Jacqueline	Yates	1798-05-04	1818-06-21	M	153	348	f	f
349	Erin	Fisher	Erin	Fisher	1798-10-24	1818-03-11	F	435	349	f	f
350	Christine	Garcia	Christine	Garcia	1798-06-07	1818-09-14	M	883	350	f	f
351	David	Bowman	David	Bowman	1798-01-09	1818-06-27	F	485	351	f	f
352	Lance	Mosley	Lance	Mosley	1798-07-28	1818-05-11	M	450	352	f	f
353	Kim	Rodriguez	Kim	Rodriguez	1798-10-20	1818-06-11	F	1226	353	f	f
354	Erin	Erickson	Erin	Erickson	1798-07-08	1818-05-10	M	1153	354	f	f
355	Rachel	Robbins	Rachel	Robbins	1798-08-02	1818-08-04	F	944	355	f	f
356	Jake	Reilly	Jake	Reilly	1798-12-13	1818-03-17	M	985	356	f	f
357	Christian	Thomas	Christian	Thomas	1798-07-20	1818-09-26	F	49	357	f	f
358	Leonard	Michael	Leonard	Michael	1798-04-28	1818-10-27	M	1006	358	f	f
359	Alyssa	Ellison	Alyssa	Ellison	1798-04-20	1818-07-12	F	86	359	f	f
360	Amber	Lee	Amber	Lee	1798-02-02	1818-04-27	M	299	360	f	f
361	Barbara	Jones	Barbara	Jones	1798-03-12	1818-08-02	F	310	361	f	f
362	Michael	Pierce	Michael	Pierce	1798-11-10	1818-07-04	M	676	362	f	f
363	David	Dean	David	Dean	1798-01-11	1818-03-24	F	776	363	f	f
364	Samantha	Evans	Samantha	Evans	1798-04-15	1818-02-25	M	563	364	f	f
365	Carla	Lyons	Carla	Lyons	1798-10-19	1818-03-04	F	277	365	f	f
366	Taylor	Williams	Taylor	Williams	1798-12-18	1818-10-14	M	964	366	f	f
367	Charles	Madden	Charles	Madden	1798-07-21	1818-05-26	F	346	367	f	f
368	Michael	Davis	Michael	Davis	1798-09-02	1818-07-20	M	565	368	f	f
369	Donna	Nelson	Donna	Nelson	1798-02-12	1818-09-15	F	402	369	f	f
370	Shari	Jimenez	Shari	Jimenez	1798-06-08	1818-07-18	M	299	370	f	f
371	Raymond	Lopez	Raymond	Lopez	1798-10-11	1818-03-17	F	485	371	f	f
372	Amanda	Levy	Amanda	Levy	1798-08-10	1818-08-02	M	879	372	f	f
373	Keith	Rowland	Keith	Rowland	1798-08-03	1818-01-17	F	984	373	f	f
374	Robert	Shelton	Robert	Shelton	1798-06-05	1818-01-11	M	105	374	f	f
375	Robert	Hutchinson	Robert	Hutchinson	1798-04-17	1818-06-21	F	974	375	f	f
376	Tammy	Gomez	Tammy	Gomez	1798-11-02	1818-09-27	M	1103	376	f	f
377	Randy	Herrera	Randy	Herrera	1798-11-27	1818-02-01	F	871	377	f	f
378	Wendy	Oneal	Wendy	Oneal	1798-05-02	1818-09-08	M	322	378	f	f
379	Caitlin	Wright	Caitlin	Wright	1798-07-28	1818-11-28	F	942	379	f	f
380	Joshua	Jones	Joshua	Jones	1798-06-20	1818-11-22	M	881	380	f	f
381	Chris	Moore	Chris	Moore	1798-12-22	1818-05-06	F	22	381	f	f
382	Daniel	Anderson	Daniel	Anderson	1798-04-05	1818-05-02	M	957	382	f	f
383	Erin	Johnson	Erin	Johnson	1798-05-28	1818-11-15	F	56	383	f	f
384	Erika	Diaz	Erika	Diaz	1798-08-10	1818-06-24	M	65	384	f	f
385	Angela	Wood	Angela	Wood	1798-01-01	1818-02-06	F	589	385	f	f
386	Shaun	Gates	Shaun	Gates	1798-08-26	1818-05-18	M	812	386	f	f
387	Jessica	Garza	Jessica	Garza	1798-07-17	1818-10-15	F	130	387	f	f
388	Margaret	Henderson	Margaret	Henderson	1798-03-02	1818-03-24	M	305	388	f	f
389	Rebecca	Miller	Rebecca	Miller	1798-09-18	1818-05-25	F	709	389	f	f
390	Lori	Wright	Lori	Wright	1798-05-09	1818-08-14	M	898	390	f	f
391	Mark	Jenkins	Mark	Jenkins	1798-06-12	1818-12-07	F	576	391	f	f
392	Elizabeth	Pierce	Elizabeth	Pierce	1798-06-24	1818-05-27	M	669	392	f	f
393	Thomas	Davis	Thomas	Davis	1798-01-15	1818-05-22	F	397	393	f	f
394	Kenneth	Gaines	Kenneth	Gaines	1798-06-07	1818-01-10	M	1043	394	f	f
395	Jennifer	Wall	Jennifer	Wall	1798-04-06	1818-10-28	F	907	395	f	f
396	Elizabeth	Robertson	Elizabeth	Robertson	1798-07-24	1818-08-09	M	67	396	f	f
397	Kristin	Todd	Kristin	Todd	1798-01-19	1818-05-07	F	261	397	f	f
398	Sarah	Haynes	Sarah	Haynes	1798-01-24	1818-03-25	M	214	398	f	f
399	Margaret	Beard	Margaret	Beard	1798-02-17	1818-06-11	F	1230	399	f	f
400	Jonathan	Garza	Jonathan	Garza	1798-08-10	1818-02-19	M	613	400	f	f
401	Kristi	Stewart	Kristi	Stewart	1798-03-25	1818-07-05	F	1203	401	f	f
402	Dwayne	Mcgee	Dwayne	Mcgee	1798-09-20	1818-01-16	M	789	402	f	f
403	Richard	Jones	Richard	Jones	1798-02-23	1818-03-21	F	1225	403	f	f
404	Alexandria	Alvarado	Alexandria	Alvarado	1798-07-28	1818-03-12	M	655	404	f	f
405	Christina	Smith	Christina	Smith	1798-04-08	1818-08-14	F	764	405	f	f
406	Michael	Trujillo	Michael	Trujillo	1798-11-05	1818-09-19	M	955	406	f	f
407	Jennifer	Gutierrez	Jennifer	Gutierrez	1798-09-01	1818-04-27	F	1210	407	f	f
408	Christian	Cooper	Christian	Cooper	1798-07-09	1818-04-27	M	55	408	f	f
409	Anthony	Jones	Anthony	Jones	1798-04-09	1818-12-21	F	1126	409	f	f
410	Pedro	Skinner	Pedro	Skinner	1798-10-27	1818-10-05	M	336	410	f	f
411	Dean	Griffin	Dean	Griffin	1798-12-15	1818-11-06	F	351	411	f	f
412	Sharon	Wells	Sharon	Wells	1798-03-11	1818-09-28	M	926	412	f	f
413	Kristy	Blake	Kristy	Blake	1798-05-09	1818-04-17	F	804	413	f	f
414	Stephen	Morales	Stephen	Morales	1798-01-09	1818-12-07	M	598	414	f	f
415	Meghan	Patton	Meghan	Patton	1798-10-11	1818-12-13	F	313	415	f	f
416	Debra	Rivera	Debra	Rivera	1798-07-10	1818-03-08	M	1180	416	f	f
417	Chad	White	Chad	White	1798-08-06	1818-01-24	F	1154	417	f	f
418	Darrell	Pace	Darrell	Pace	1798-04-06	1818-02-22	M	60	418	f	f
419	Paul	Miller	Paul	Miller	1798-02-23	1818-07-03	F	879	419	f	f
420	Martha	Ware	Martha	Ware	1798-10-21	1818-08-04	M	764	420	f	f
421	Leslie	Roberts	Leslie	Roberts	1798-09-04	1818-08-25	F	47	421	f	f
422	Phillip	Nelson	Phillip	Nelson	1798-06-08	1818-05-27	M	840	422	f	f
423	Jack	Miller	Jack	Miller	1798-06-22	1818-08-03	F	193	423	f	f
424	Justin	Williams	Justin	Williams	1798-06-02	1818-04-14	M	829	424	f	f
425	Marcia	Mcdonald	Marcia	Mcdonald	1798-06-03	1818-03-11	F	1108	425	f	f
426	Erin	Cox	Erin	Cox	1798-12-16	1818-12-19	M	744	426	f	f
427	Richard	Barker	Richard	Barker	1798-05-10	1818-02-20	F	565	427	f	f
428	Meredith	Woodward	Meredith	Woodward	1798-08-05	1818-06-17	M	632	428	f	f
429	Emma	Mendez	Emma	Mendez	1798-09-08	1818-04-09	F	355	429	f	f
430	John	Guzman	John	Guzman	1798-04-21	1818-02-28	M	194	430	f	f
431	Kelly	Medina	Kelly	Medina	1798-12-21	1818-09-21	F	662	431	f	f
432	Erica	Middleton	Erica	Middleton	1798-02-16	1818-11-21	M	1111	432	f	f
433	Natalie	Mata	Natalie	Mata	1798-08-19	1818-05-09	F	47	433	f	f
434	Monique	Harris	Monique	Harris	1798-03-25	1818-03-14	M	207	434	f	f
435	Amber	Williams	Amber	Williams	1798-08-16	1818-03-14	F	755	435	f	f
436	Jessica	Gibson	Jessica	Gibson	1798-01-18	1818-08-19	M	245	436	f	f
437	Jennifer	Woods	Jennifer	Woods	1798-11-10	1818-07-20	F	144	437	f	f
438	Stacie	Burns	Stacie	Burns	1798-11-18	1818-12-07	M	393	438	f	f
439	Tyler	Martinez	Tyler	Martinez	1798-09-14	1818-11-24	F	576	439	f	f
440	Ana	Douglas	Ana	Douglas	1798-05-20	1818-10-16	M	488	440	f	f
441	Alan	Frazier	Alan	Frazier	1798-04-22	1818-09-05	F	1223	441	f	f
442	Stephen	Murphy	Stephen	Murphy	1798-05-16	1818-06-04	M	440	442	f	f
443	Jeffrey	Miller	Jeffrey	Miller	1798-11-01	1818-07-05	F	1122	443	f	f
444	Emily	Mooney	Emily	Mooney	1798-05-02	1818-10-13	M	783	444	f	f
445	Justin	Palmer	Justin	Palmer	1798-02-03	1818-07-24	F	161	445	f	f
446	Christy	Robbins	Christy	Robbins	1798-01-11	1818-10-05	M	1081	446	f	f
447	Joseph	Kennedy	Joseph	Kennedy	1798-01-19	1818-02-06	F	571	447	f	f
448	Veronica	Waters	Veronica	Waters	1798-12-18	1818-02-14	M	554	448	f	f
449	Benjamin	Blair	Benjamin	Blair	1798-11-25	1818-06-15	F	721	449	f	f
450	Amanda	Morgan	Amanda	Morgan	1798-12-08	1818-08-27	M	1201	450	f	f
451	Nathaniel	Jackson	Nathaniel	Jackson	1798-11-04	1818-04-15	F	645	451	f	f
452	John	Hensley	John	Hensley	1798-03-13	1818-02-23	M	1243	452	f	f
453	Veronica	Hart	Veronica	Hart	1798-02-23	1818-06-08	F	322	453	f	f
454	Jeremy	Snyder	Jeremy	Snyder	1798-02-05	1818-07-06	M	859	454	f	f
455	Amanda	Lambert	Amanda	Lambert	1798-01-10	1818-11-10	F	24	455	f	f
456	Christopher	Stark	Christopher	Stark	1798-09-03	1818-04-21	M	510	456	f	f
457	Daniel	Duran	Daniel	Duran	1798-07-24	1818-08-13	F	657	457	f	f
458	Kevin	Mcconnell	Kevin	Mcconnell	1798-04-27	1818-04-20	M	204	458	f	f
459	Troy	Montes	Troy	Montes	1798-08-20	1818-02-10	F	1176	459	f	f
460	Jose	Smith	Jose	Smith	1798-10-14	1818-08-24	M	350	460	f	f
461	Kevin	Kramer	Kevin	Kramer	1798-02-12	1818-03-12	F	195	461	f	f
462	Elizabeth	Carter	Elizabeth	Carter	1798-03-25	1818-02-02	M	702	462	f	f
463	Anthony	Woods	Anthony	Woods	1798-05-14	1818-06-17	F	91	463	f	f
464	Jennifer	Shaffer	Jennifer	Shaffer	1798-03-25	1818-04-05	M	599	464	f	f
465	Erika	Tran	Erika	Tran	1798-07-22	1818-06-17	F	783	465	f	f
466	Colleen	Hampton	Colleen	Hampton	1798-12-20	1818-09-18	M	558	466	f	f
467	Allison	Johnson	Allison	Johnson	1798-09-21	1818-08-27	F	938	467	f	f
468	Donald	Mcguire	Donald	Mcguire	1798-05-25	1818-08-22	M	740	468	f	f
469	Elizabeth	Snyder	Elizabeth	Snyder	1798-12-16	1818-06-09	F	538	469	f	f
470	Nathan	Elliott	Nathan	Elliott	1798-08-23	1818-01-10	M	179	470	f	f
471	Ana	Ford	Ana	Ford	1798-01-16	1818-02-04	F	1009	471	f	f
472	Matthew	Juarez	Matthew	Juarez	1798-01-11	1818-11-16	M	1181	472	f	f
473	Monica	Stewart	Monica	Stewart	1798-10-05	1818-02-18	F	1056	473	f	f
474	Preston	Jensen	Preston	Jensen	1798-03-10	1818-06-03	M	1243	474	f	f
475	Valerie	Strickland	Valerie	Strickland	1798-05-05	1818-12-06	F	143	475	f	f
476	Amy	Murphy	Amy	Murphy	1798-10-17	1818-11-15	M	1049	476	f	f
477	Krista	Morgan	Krista	Morgan	1798-12-27	1818-08-08	F	592	477	f	f
478	Samuel	Le	Samuel	Le	1798-02-27	1818-10-13	M	606	478	f	f
479	Sierra	Bentley	Sierra	Bentley	1798-03-06	1818-07-21	F	278	479	f	f
480	Wyatt	Nelson	Wyatt	Nelson	1798-09-05	1818-08-12	M	278	480	f	f
481	Steven	Ramos	Steven	Ramos	1798-09-14	1818-11-05	F	1058	481	f	f
482	Jason	Peters	Jason	Peters	1798-05-10	1818-10-02	M	514	482	f	f
483	Frank	Sanchez	Frank	Sanchez	1798-07-14	1818-08-02	F	743	483	f	f
484	James	Sloan	James	Sloan	1798-12-21	1818-08-01	M	1154	484	f	f
485	Thomas	Anderson	Thomas	Anderson	1798-10-12	1818-03-17	F	282	485	f	f
486	Samuel	Cuevas	Samuel	Cuevas	1798-05-02	1818-11-27	M	742	486	f	f
487	Ian	Hoffman	Ian	Hoffman	1798-03-11	1818-03-01	F	1014	487	f	f
488	Derek	Blair	Derek	Blair	1798-05-19	1818-03-10	M	60	488	f	f
489	Alexandria	Richard	Alexandria	Richard	1798-06-05	1818-01-06	F	693	489	f	f
490	Craig	Blake	Craig	Blake	1798-06-07	1818-02-28	M	1121	490	f	f
491	Jonathan	Alvarado	Jonathan	Alvarado	1798-06-20	1818-04-24	F	724	491	f	f
492	Steven	Miranda	Steven	Miranda	1798-06-16	1818-11-02	M	24	492	f	f
493	Dennis	Wiggins	Dennis	Wiggins	1798-11-27	1818-08-14	F	339	493	f	f
494	Elizabeth	Bailey	Elizabeth	Bailey	1798-02-07	1818-03-20	M	646	494	f	f
495	Cheryl	Henry	Cheryl	Henry	1798-12-21	1818-05-27	F	721	495	f	f
496	Jacqueline	Bailey	Jacqueline	Bailey	1798-07-24	1818-05-03	M	102	496	f	f
497	Ashley	Baker	Ashley	Baker	1798-12-26	1818-12-02	F	589	497	f	f
498	Kenneth	Williams	Kenneth	Williams	1798-03-25	1818-12-20	M	355	498	f	f
499	Donald	Mejia	Donald	Mejia	1798-12-20	1818-12-22	F	520	499	f	f
500					1798-10-12	1818-08-24	M	61	500	f	f
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.people (id, date_of_birth, date_of_death, name, surname) FROM stdin;
1	1990-09-11	\N	Ralph	Mahoney
2	1965-02-08	\N	Sandra	Frye
3	1965-04-11	\N	Tyler	Brandt
4	1940-08-01	\N	Amanda	Hayes
5	1940-03-25	\N	Anthony	Knight
6	1940-04-15	\N	Lawrence	Suarez
7	1940-12-01	\N	Tamara	Snyder
8	1915-01-18	\N	Timothy	Elliott
9	1915-01-28	\N	Jamie	Smith
10	1915-09-09	\N	Nicole	Martinez
11	1915-05-09	\N	Kyle	Foster
12	1915-12-25	\N	Logan	Adams
13	1915-01-26	\N	Paul	Hanson
14	1915-04-02	\N	Michael	Cole
15	1915-09-04	\N	Robert	Foster
16	1890-09-11	\N	Brandon	Rodriguez
17	1890-07-08	\N	Melinda	Evans
18	1890-03-02	\N	Emily	George
19	1890-08-21	\N	John	Nelson
20	1890-09-06	\N	Julie	Crane
21	1890-05-26	\N	Sandra	Smith
22	1890-10-13	\N	Tony	Harris
23	1890-12-04	\N	Calvin	Garza
24	1890-03-09	\N	Aaron	Calhoun
25	1890-02-10	\N	Crystal	Scott
26	1890-10-11	\N	Walter	Bowen
27	1890-09-14	\N	Lucas	Austin
28	1890-12-21	\N	Kristen	Long
29	1890-09-06	\N	Christina	Taylor
30	1890-04-16	\N	Melissa	Thomas
31	1890-12-24	\N	Robert	Fuller
32	1865-03-17	\N	Whitney	Harris
33	1865-01-13	\N	Andrea	Shepard
34	1865-09-03	\N	Luis	Barron
35	1865-04-26	\N	David	Weaver
36	1865-11-11	\N	Emma	Matthews
37	1865-06-24	\N	Allen	Gallagher
38	1865-02-03	\N	Ryan	Luna
39	1865-09-19	\N	Alejandro	Brown
40	1865-12-05	\N	Emily	Ayers
41	1865-07-04	\N	Gina	Clay
42	1865-11-08	\N	Amanda	Davenport
43	1865-05-24	\N	Toni	Miller
44	1865-07-19	\N	Jeffrey	Ryan
45	1865-09-15	\N	John	Smith
46	1865-08-06	\N	Kristin	Williams
47	1865-07-01	\N	Tracy	Caldwell
48	1865-07-25	\N	Alan	Nunez
49	1865-10-07	\N	Amber	Green
50	1865-11-20	\N	Darryl	Olson
51	1865-07-25	\N	Brenda	Rollins
52	1865-06-09	\N	Grant	Roberson
53	1865-05-15	\N	Lauren	Wood
54	1865-11-10	\N	Jon	Dickson
55	1865-02-25	\N	Kyle	Gonzales
56	1865-11-20	\N	Jessica	White
57	1865-08-23	\N	Tyler	Salazar
58	1865-08-26	\N	Paul	Wheeler
59	1865-12-01	\N	Kyle	Blake
60	1865-07-22	\N	Nicholas	Bowen
61	1865-06-25	\N	Kristopher	Hancock
62	1865-04-27	\N	Hector	Edwards
63	1865-12-03	\N	Cindy	Marquez
64	1840-05-09	\N	John	Simmons
65	1840-07-01	\N	Edward	Grant
66	1840-04-02	\N	Samuel	Nielsen
67	1840-04-06	\N	Scott	Guerrero
68	1840-12-12	\N	Jennifer	Jones
69	1840-10-05	\N	Thomas	Neal
70	1840-02-07	\N	Steven	Morgan
71	1840-05-26	\N	Stephen	Bender
72	1840-05-19	\N	Rebecca	Haynes
73	1840-04-02	\N	Corey	Daniels
74	1840-04-23	\N	Julie	Martinez
75	1840-09-18	\N	Kyle	Tucker
76	1840-05-10	\N	Nathan	Martin
77	1840-01-06	\N	Levi	Long
78	1840-01-27	\N	Zachary	Jackson
79	1840-01-02	\N	Juan	Smith
80	1840-04-06	\N	Michael	Young
81	1840-06-12	\N	Carolyn	Rivera
82	1840-02-21	\N	John	Robinson
83	1840-04-26	\N	Justin	Hughes
84	1840-11-09	\N	Michael	Murillo
85	1840-03-27	\N	Wyatt	Brennan
86	1840-06-07	\N	Christy	Obrien
87	1840-02-27	\N	Martin	Greer
88	1840-06-07	\N	Cynthia	Walker
89	1840-09-21	\N	Adam	Hunt
90	1840-09-02	\N	Joseph	Nelson
91	1840-07-06	\N	Damon	Valenzuela
92	1840-12-11	\N	Linda	Golden
93	1840-12-23	\N	Richard	Flores
94	1840-08-10	\N	Matthew	Tucker
95	1840-03-26	\N	Rebecca	Hughes
96	1840-08-07	\N	Jennifer	Nelson
97	1840-06-25	\N	Megan	Davis
98	1840-07-19	\N	Daniel	Wilson
99	1840-02-04	\N	Henry	Carrillo
100	1840-07-16	\N	Dalton	Henderson
101	1840-02-19	\N	James	Hill
102	1840-01-23	\N	Patricia	Garcia
103	1840-02-02	\N	John	Hawkins
104	1840-09-11	\N	Danielle	Phillips
105	1840-10-11	\N	Michael	Davis
106	1840-08-25	\N	Danielle	Anderson
107	1840-07-18	\N	Lisa	Rodriguez
108	1840-04-14	\N	Ryan	Jenkins
109	1840-02-03	\N	Scott	Patterson
110	1840-09-03	\N	John	Gonzalez
111	1840-08-07	\N	Kathy	Fry
112	1840-07-09	\N	Kelly	Mejia
113	1840-07-09	\N	Lisa	Le
114	1840-04-23	\N	John	Nelson
115	1840-03-24	\N	Angela	Marsh
116	1840-10-16	\N	Jonathan	Edwards
117	1840-12-04	\N	David	Williams
118	1840-06-08	\N	Kristin	Gonzalez
119	1840-02-15	\N	Susan	Neal
120	1840-09-11	\N	Lucas	Gilbert
121	1840-09-22	\N	Cody	Meyer
122	1840-02-22	\N	Michelle	Ross
123	1840-05-15	\N	Donna	Daniels
124	1840-04-22	\N	Joel	Miller
125	1840-06-06	\N	Jennifer	Johnson
126	1840-12-04	\N	Maurice	Smith
127	1840-11-21	\N	Ryan	Matthews
128	1815-11-08	\N	Sharon	Perry
129	1815-05-09	\N	Ashley	Reed
130	1815-09-07	\N	Teresa	Shaw
131	1815-01-07	\N	Stacy	Jenkins
132	1815-01-28	\N	David	Brooks
133	1815-02-04	\N	Angelica	Reyes
134	1815-11-02	\N	Natalie	Holmes
135	1815-09-27	\N	Joshua	Flores
136	1815-03-20	\N	Melissa	Young
137	1815-09-06	\N	Tracey	Williams
138	1815-09-22	\N	Jessica	Rubio
139	1815-12-20	\N	Darlene	Kelley
140	1815-08-23	\N	Sherry	Melton
141	1815-02-12	\N	Emily	Garner
142	1815-01-15	\N	Amber	Dickerson
143	1815-03-11	\N	Kathryn	Leach
144	1815-09-06	\N	Andrew	Scott
145	1815-05-13	\N	Jerry	Grant
146	1815-07-28	\N	Wesley	Cross
147	1815-11-12	\N	Randy	Miller
148	1815-04-25	\N	Jamie	Vaughn
149	1815-11-12	\N	Melissa	Callahan
150	1815-01-21	\N	Samantha	Williams
151	1815-07-05	\N	Cathy	Michael
152	1815-12-28	\N	Abigail	Patterson
153	1815-04-25	\N	Allison	Dudley
154	1815-11-26	\N	Kaitlyn	Peters
155	1815-06-07	\N	Darlene	Byrd
156	1815-09-07	\N	David	Huang
157	1815-11-26	\N	Phillip	Sullivan
158	1815-06-17	\N	Morgan	Duncan
159	1815-08-20	\N	Danielle	Martinez
160	1815-02-24	\N	Natasha	Grant
161	1815-04-21	\N	Stephanie	Wheeler
162	1815-01-24	\N	Raymond	Terrell
163	1815-09-22	\N	Krista	Marquez
164	1815-04-22	\N	Tamara	Tucker
165	1815-03-20	\N	Connie	Garza
166	1815-10-18	\N	David	King
167	1815-01-03	\N	Tracey	Ponce
168	1815-06-17	\N	Michael	Morrow
169	1815-05-22	\N	Laura	Richardson
170	1815-04-16	\N	Melinda	Atkins
171	1815-02-15	\N	Pamela	Robinson
172	1815-04-19	\N	Tara	Murray
173	1815-12-23	\N	Elizabeth	Glover
174	1815-01-21	\N	Dennis	Gomez
175	1815-04-10	\N	Jenna	Schroeder
176	1815-07-19	\N	Amber	Hill
177	1815-10-22	\N	Brittany	Kim
178	1815-07-09	\N	Diana	Hall
179	1815-03-25	\N	Logan	Morris
180	1815-02-20	\N	Ashley	Delgado
181	1815-06-19	\N	Rachel	Frederick
182	1815-01-01	\N	Rachel	Andrews
183	1815-07-16	\N	Mario	Harris
184	1815-12-06	\N	Scott	Martin
185	1815-12-12	\N	Alyssa	Williams
186	1815-02-01	\N	Steven	Silva
187	1815-10-13	\N	John	Knox
188	1815-02-07	\N	Donna	Green
189	1815-02-26	\N	Natalie	Taylor
190	1815-07-15	\N	Robert	Lam
191	1815-01-12	\N	Nathan	Campbell
192	1815-06-17	\N	Crystal	Meza
193	1815-01-27	\N	Robert	Lane
194	1815-05-17	\N	Valerie	Wade
195	1815-06-13	\N	Tiffany	Patterson
196	1815-02-18	\N	Stephanie	Garza
197	1815-11-18	\N	Kimberly	Shields
198	1815-09-14	\N	Austin	Martinez
199	1815-07-28	\N	Timothy	Carter
200	1815-09-17	\N	Timothy	Harris
201	1815-09-02	\N	Martin	Riley
202	1815-06-15	\N	Walter	Clarke
203	1815-06-20	\N	Kayla	Herrera
204	1815-10-21	\N	William	Adams
205	1815-08-19	\N	Bryan	Blackwell
206	1815-04-23	\N	Donald	Anderson
207	1815-07-22	\N	Jonathan	Gutierrez
208	1815-04-01	\N	Jennifer	Marquez
209	1815-08-20	\N	Kelsey	Smith
210	1815-12-24	\N	Mark	Ware
211	1815-10-12	\N	Jonathan	Haynes
212	1815-12-09	\N	Sandra	Kirk
213	1815-09-02	\N	Elizabeth	Pope
214	1815-10-21	\N	Misty	Hart
215	1815-02-17	\N	Darrell	Moyer
216	1815-10-01	\N	Bernard	Mann
217	1815-12-18	\N	Jerry	Huffman
218	1815-10-07	\N	Chad	Park
219	1815-05-03	\N	Pamela	Wagner
220	1815-08-05	\N	Lauren	Lamb
221	1815-09-03	\N	Sandra	Wright
222	1815-06-12	\N	Kathryn	Cain
223	1815-11-12	\N	Molly	Newman
224	1815-09-10	\N	Keith	Wallace
225	1815-01-04	\N	Rebecca	Hogan
226	1815-09-01	\N	Daniel	Chen
227	1815-09-11	\N	Jason	Stewart
228	1815-02-01	\N	Christopher	Bailey
229	1815-05-21	\N	Phillip	Martin
230	1815-07-11	\N	Kelsey	Mayo
231	1815-10-17	\N	Karen	Thompson
232	1815-10-04	\N	Jamie	Atkins
233	1815-05-06	\N	Edward	Strong
234	1815-04-16	\N	Stacy	Kim
235	1815-01-11	\N	Bryan	Ross
236	1815-12-26	\N	David	Kirby
237	1815-02-04	\N	Andrew	Freeman
238	1815-08-20	\N	Jennifer	Hudson
239	1815-04-17	\N	Scott	Moreno
240	1815-08-09	\N	Shannon	King
241	1815-06-11	\N	Kristen	Thomas
242	1815-10-06	\N	Brittany	Dickerson
243	1815-08-06	\N	Laura	Robles
244	1815-08-01	\N	Rick	Murphy
245	1815-03-02	\N	Jennifer	Black
246	1815-02-20	\N	Janet	Nelson
247	1815-12-05	\N	Susan	Smith
248	1815-03-14	\N	Chad	Nelson
249	1815-08-12	\N	Cesar	Peterson
250	1815-04-06	\N	Amanda	Green
251	1815-12-07	\N	Jennifer	Brown
252	1815-11-24	\N	Rebecca	Novak
253	1815-10-07	\N	Michael	Smith
254	1815-05-14	\N	Melissa	Barron
255	1815-12-10	\N	Aaron	Richardson
256	1790-12-17	\N	Patrick	Jacobs
257	1790-08-03	\N	Crystal	Braun
258	1790-11-28	\N	John	Mullen
259	1790-08-08	\N	Rachel	Martinez
260	1790-04-03	\N	Joseph	Lawson
261	1790-05-10	\N	Dana	Hicks
262	1790-07-10	\N	Jillian	Russell
263	1790-07-14	\N	Scott	Williams
264	1790-02-09	\N	Ronald	Sharp
265	1790-08-12	\N	Ronald	Rodriguez
266	1790-07-22	\N	Christopher	Davis
267	1790-03-19	\N	Maria	Fletcher
268	1790-06-15	\N	James	Chambers
269	1790-04-11	\N	Michael	Morris
270	1790-05-10	\N	Deborah	Williams
271	1790-12-26	\N	Patrick	Jimenez
272	1790-06-07	\N	Debra	Rojas
273	1790-02-24	\N	Amy	Mitchell
274	1790-02-06	\N	Angela	Macias
275	1790-08-17	\N	Jessica	Young
276	1790-10-23	\N	Lance	Evans
277	1790-07-11	\N	Nicholas	Phillips
278	1790-11-25	\N	Robert	Smith
279	1790-12-19	\N	Lori	Kennedy
280	1790-01-04	\N	Wesley	Williams
281	1790-01-18	\N	Kevin	Bailey
282	1790-08-22	\N	Kimberly	Finley
283	1790-01-07	\N	Mitchell	Madden
284	1790-04-24	\N	Sophia	Williams
285	1790-06-10	\N	Craig	Luna
286	1790-08-19	\N	Jeff	Ramirez
287	1790-12-02	\N	Angelica	Owens
288	1790-10-09	\N	Crystal	Mitchell
289	1790-08-13	\N	Carrie	Holloway
290	1790-06-25	\N	Alicia	Clark
291	1790-11-07	\N	Michael	Gonzalez
292	1790-09-15	\N	Carlos	Griffith
293	1790-07-16	\N	Gary	Dean
294	1790-05-19	\N	Kevin	Smith
295	1790-07-20	\N	Travis	Jensen
296	1790-02-12	\N	Elizabeth	Nichols
297	1790-01-19	\N	Sean	Castillo
298	1790-02-06	\N	David	Yu
299	1790-06-05	\N	Edward	Davis
300	1790-06-28	\N	Donna	David
301	1790-03-10	\N	Lisa	Moss
302	1790-04-02	\N	Frank	Robinson
303	1790-12-12	\N	Courtney	Moore
304	1790-04-26	\N	Samantha	Gill
305	1790-09-28	\N	Betty	Bauer
306	1790-01-25	\N	Matthew	Vang
307	1790-12-20	\N	Jessica	Mata
308	1790-02-03	\N	Karen	Jones
309	1790-04-11	\N	Robert	Garza
310	1790-06-28	\N	Charles	Norton
311	1790-11-03	\N	Daniel	Garner
312	1790-05-04	\N	David	Singleton
313	1790-02-25	\N	Justin	Baker
314	1790-02-14	\N	Heather	Taylor
315	1790-01-24	\N	Brandon	Velasquez
316	1790-06-06	\N	Adam	Black
317	1790-05-02	\N	Albert	Smith
318	1790-09-07	\N	David	Barnes
319	1790-07-01	\N	Katherine	Benjamin
320	1790-10-14	\N	Amber	Lopez
321	1790-04-04	\N	Cynthia	Phelps
322	1790-11-15	\N	Jonathon	Hurley
323	1790-06-09	\N	Evan	Bowers
324	1790-12-05	\N	Kristen	Wolfe
325	1790-11-23	\N	Christopher	Lee
326	1790-02-10	\N	Kristin	Sawyer
327	1790-05-15	\N	Nicholas	Dickerson
328	1790-05-20	\N	Katherine	Figueroa
329	1790-05-17	\N	Lisa	Le
330	1790-03-11	\N	Jon	Thornton
331	1790-02-15	\N	David	Wilkins
332	1790-10-02	\N	Michael	Nash
333	1790-08-04	\N	Olivia	George
334	1790-10-09	\N	Benjamin	Oneill
335	1790-01-15	\N	Scott	Ashley
336	1790-09-21	\N	Edward	Frank
337	1790-10-28	\N	Tamara	Flores
338	1790-08-14	\N	Jerry	Ramsey
339	1790-01-24	\N	Anna	Merritt
340	1790-04-19	\N	Laurie	Benson
341	1790-05-19	\N	Matthew	Sandoval
342	1790-08-05	\N	Jerry	Taylor
343	1790-04-26	\N	Robert	Garcia
344	1790-05-13	\N	Ashley	Keller
345	1790-10-13	\N	Melissa	Thompson
346	1790-10-07	\N	Kathleen	Gray
347	1790-09-15	\N	Ryan	Cochran
348	1790-04-22	\N	Ashley	Wilkinson
349	1790-10-11	\N	Jacqueline	Yates
350	1790-07-24	\N	Erin	Fisher
351	1790-12-14	\N	Christine	Garcia
352	1790-11-11	\N	David	Bowman
353	1790-08-07	\N	Lance	Mosley
354	1790-07-09	\N	Kim	Rodriguez
355	1790-09-17	\N	Erin	Erickson
356	1790-11-13	\N	Rachel	Robbins
357	1790-04-27	\N	Jake	Reilly
358	1790-05-14	\N	Christian	Thomas
359	1790-09-15	\N	Leonard	Michael
360	1790-12-01	\N	Alyssa	Ellison
361	1790-09-10	\N	Amber	Lee
362	1790-03-21	\N	Barbara	Jones
363	1790-07-26	\N	Michael	Pierce
364	1790-03-04	\N	David	Dean
365	1790-04-16	\N	Samantha	Evans
366	1790-12-19	\N	Carla	Lyons
367	1790-12-04	\N	Taylor	Williams
368	1790-10-16	\N	Charles	Madden
369	1790-12-03	\N	Michael	Davis
370	1790-04-28	\N	Donna	Nelson
371	1790-11-16	\N	Shari	Jimenez
372	1790-11-10	\N	Raymond	Lopez
373	1790-03-07	\N	Amanda	Levy
374	1790-08-03	\N	Keith	Rowland
375	1790-07-19	\N	Robert	Shelton
376	1790-11-28	\N	Robert	Hutchinson
377	1790-03-15	\N	Tammy	Gomez
378	1790-09-02	\N	Randy	Herrera
379	1790-07-11	\N	Wendy	Oneal
380	1790-12-17	\N	Caitlin	Wright
381	1790-08-19	\N	Joshua	Jones
382	1790-01-27	\N	Chris	Moore
383	1790-08-18	\N	Daniel	Anderson
384	1790-11-23	\N	Erin	Johnson
385	1790-01-13	\N	Erika	Diaz
386	1790-02-26	\N	Angela	Wood
387	1790-03-19	\N	Shaun	Gates
388	1790-02-22	\N	Jessica	Garza
389	1790-09-02	\N	Margaret	Henderson
390	1790-12-23	\N	Rebecca	Miller
391	1790-09-08	\N	Lori	Wright
392	1790-03-03	\N	Mark	Jenkins
393	1790-05-05	\N	Elizabeth	Pierce
394	1790-08-20	\N	Thomas	Davis
395	1790-10-11	\N	Kenneth	Gaines
396	1790-03-18	\N	Jennifer	Wall
397	1790-12-02	\N	Elizabeth	Robertson
398	1790-07-04	\N	Kristin	Todd
399	1790-11-24	\N	Sarah	Haynes
400	1790-04-07	\N	Margaret	Beard
401	1790-11-06	\N	Jonathan	Garza
402	1790-04-08	\N	Kristi	Stewart
403	1790-11-23	\N	Dwayne	Mcgee
404	1790-09-25	\N	Richard	Jones
405	1790-12-09	\N	Alexandria	Alvarado
406	1790-09-26	\N	Christina	Smith
407	1790-11-17	\N	Michael	Trujillo
408	1790-12-01	\N	Jennifer	Gutierrez
409	1790-04-07	\N	Christian	Cooper
410	1790-03-16	\N	Anthony	Jones
411	1790-05-04	\N	Pedro	Skinner
412	1790-03-18	\N	Dean	Griffin
413	1790-05-21	\N	Sharon	Wells
414	1790-05-08	\N	Kristy	Blake
415	1790-09-19	\N	Stephen	Morales
416	1790-10-05	\N	Meghan	Patton
417	1790-04-22	\N	Debra	Rivera
418	1790-01-08	\N	Chad	White
419	1790-07-19	\N	Darrell	Pace
420	1790-12-27	\N	Paul	Miller
421	1790-12-16	\N	Martha	Ware
422	1790-09-23	\N	Leslie	Roberts
423	1790-09-23	\N	Phillip	Nelson
424	1790-05-17	\N	Jack	Miller
425	1790-06-14	\N	Justin	Williams
426	1790-07-10	\N	Marcia	Mcdonald
427	1790-08-12	\N	Erin	Cox
428	1790-03-21	\N	Richard	Barker
429	1790-08-17	\N	Meredith	Woodward
430	1790-08-18	\N	Emma	Mendez
431	1790-04-28	\N	John	Guzman
432	1790-01-01	\N	Kelly	Medina
433	1790-01-01	\N	Erica	Middleton
434	1790-07-11	\N	Natalie	Mata
435	1790-06-06	\N	Monique	Harris
436	1790-09-24	\N	Amber	Williams
437	1790-02-01	\N	Jessica	Gibson
438	1790-05-17	\N	Jennifer	Woods
439	1790-01-13	\N	Stacie	Burns
440	1790-07-13	\N	Tyler	Martinez
441	1790-07-26	\N	Ana	Douglas
442	1790-03-24	\N	Alan	Frazier
443	1790-05-17	\N	Stephen	Murphy
444	1790-10-24	\N	Jeffrey	Miller
445	1790-01-15	\N	Emily	Mooney
446	1790-11-21	\N	Justin	Palmer
447	1790-11-08	\N	Christy	Robbins
448	1790-06-11	\N	Joseph	Kennedy
449	1790-09-02	\N	Veronica	Waters
450	1790-03-19	\N	Benjamin	Blair
451	1790-10-12	\N	Amanda	Morgan
452	1790-06-09	\N	Nathaniel	Jackson
453	1790-10-04	\N	John	Hensley
454	1790-03-10	\N	Veronica	Hart
455	1790-11-10	\N	Jeremy	Snyder
456	1790-01-18	\N	Amanda	Lambert
457	1790-07-03	\N	Christopher	Stark
458	1790-05-27	\N	Daniel	Duran
459	1790-09-03	\N	Kevin	Mcconnell
460	1790-11-01	\N	Troy	Montes
461	1790-01-11	\N	Jose	Smith
462	1790-09-08	\N	Kevin	Kramer
463	1790-01-28	\N	Elizabeth	Carter
464	1790-08-14	\N	Anthony	Woods
465	1790-05-01	\N	Jennifer	Shaffer
466	1790-01-21	\N	Erika	Tran
467	1790-07-03	\N	Colleen	Hampton
468	1790-11-28	\N	Allison	Johnson
469	1790-04-22	\N	Donald	Mcguire
470	1790-06-24	\N	Elizabeth	Snyder
471	1790-12-01	\N	Nathan	Elliott
472	1790-06-11	\N	Ana	Ford
473	1790-09-09	\N	Matthew	Juarez
474	1790-01-16	\N	Monica	Stewart
475	1790-05-06	\N	Preston	Jensen
476	1790-09-26	\N	Valerie	Strickland
477	1790-12-25	\N	Amy	Murphy
478	1790-06-26	\N	Krista	Morgan
479	1790-01-06	\N	Samuel	Le
480	1790-10-21	\N	Sierra	Bentley
481	1790-02-19	\N	Wyatt	Nelson
482	1790-06-09	\N	Steven	Ramos
483	1790-04-01	\N	Jason	Peters
484	1790-01-10	\N	Frank	Sanchez
485	1790-01-05	\N	James	Sloan
486	1790-02-11	\N	Thomas	Anderson
487	1790-09-19	\N	Samuel	Cuevas
488	1790-12-21	\N	Ian	Hoffman
489	1790-11-28	\N	Derek	Blair
490	1790-06-27	\N	Alexandria	Richard
491	1790-09-21	\N	Craig	Blake
492	1790-09-03	\N	Jonathan	Alvarado
493	1790-06-24	\N	Steven	Miranda
494	1790-04-09	\N	Dennis	Wiggins
495	1790-06-12	\N	Elizabeth	Bailey
496	1790-09-08	\N	Cheryl	Henry
497	1790-10-18	\N	Jacqueline	Bailey
498	1790-06-06	\N	Ashley	Baker
499	1790-05-28	\N	Kenneth	Williams
500	1790-01-21	\N	Donald	Mejia
\.


--
-- Data for Name: pet_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.pet_passports (id, name, pet_owner, issuer, date_of_birth, species) FROM stdin;
0	Daisy	3	996	1979-08-05	Python regius
1	Rocky	5	184	1960-03-08	Chinchilla lanigera
2	Chloe	8	738	1931-05-17	Ctenosaura similis
3	Lucy	11	129	1927-10-22	Oryctolagus cuniculus
4	Stella	12	549	1925-04-01	Nymphicus hollandicus
5	Lola	16	607	1900-10-06	Cavia porcellus
6	Lucy	17	512	1904-05-03	Nymphicus hollandicus
7	Cooper	18	326	1906-10-04	Python regius
8	Lucy	20	30	1906-08-16	Carassius auratus
9	Buddy	24	771	1902-04-09	Serinus canaria domestica
10	Lucy	25	1005	1901-09-16	Ctenosaura similis
11	Toby	30	1041	1907-02-05	Python regius
12	Molly	31	478	1907-11-07	Chinchilla lanigera
13	Chloe	33	66	1877-05-24	Carassius auratus
14	Buddy	34	871	1879-05-17	Rattus norvegicus domestica
15	Bentley	42	319	1880-11-01	Pogona vitticeps
16	Toby	44	1210	1883-12-24	Pogona vitticeps
17	Stella	46	1026	1877-02-16	Python regius
18	Buddy	51	882	1882-02-25	Python regius
19	Zoey	52	185	1882-02-25	Ctenosaura similis
20	Rocky	53	557	1883-03-23	Carassius auratus
21	Cooper	55	396	1877-06-06	Mesocricetus auratus
22	Max	56	760	1877-11-25	Felis catus
23	Daisy	59	240	1881-03-09	Serinus canaria domestica
24	Daisy	62	781	1876-10-10	Carassius auratus
25	Charlie	63	732	1876-10-18	Betta splendens
26	Luna	65	1094	1852-10-07	Psittacus erithacus
27	Lola	67	677	1853-04-06	Felis catus
28	Zoey	69	725	1850-02-18	Carassius auratus
29	Max	70	544	1855-08-04	Acanthoscurria geniculata
30	Molly	72	11	1860-07-02	Nymphicus hollandicus
31	Daisy	75	387	1855-10-16	Psittacus erithacus
32	Max	77	1148	1853-04-10	Nymphicus hollandicus
33	Sadie	80	1182	1859-09-05	Pogona vitticeps
34	Bella	90	1207	1854-11-25	Oryctolagus cuniculus
35	Stella	95	1042	1858-10-06	Canis lupus familiaris
36	Stella	98	1009	1857-01-18	Python regius
37	Milo	102	415	1857-08-08	Serinus canaria domestica
38	Lucy	103	1029	1854-08-05	Felis catus
39	Bentley	106	999	1853-03-15	Pogona vitticeps
40	Luna	107	143	1852-10-23	Oryctolagus cuniculus
41	Cooper	109	379	1856-06-03	Mesocricetus auratus
42	Sadie	110	740	1850-04-06	Pogona vitticeps
43	Cooper	112	2	1852-06-01	Acanthoscurria geniculata
44	Molly	114	31	1860-07-01	Psittacus erithacus
45	Rocky	116	954	1855-04-06	Betta splendens
46	Chloe	118	780	1852-07-11	Acanthoscurria geniculata
47	Zoey	119	8	1858-03-24	Testudo hermanni
48	Chloe	120	106	1857-02-28	Eublepharis macularius
49	Charlie	122	329	1855-02-11	Pogona vitticeps
50	Lola	124	904	1857-01-04	Psittacus erithacus
51	Rocky	125	54	1860-03-23	Acanthoscurria geniculata
52	Oliver	126	165	1858-03-23	Rattus norvegicus domestica
53	Stella	134	60	1832-05-28	Mesocricetus auratus
54	Lucy	136	679	1835-11-27	Cavia porcellus
55	Buddy	138	1230	1828-02-07	Chinchilla lanigera
56	Stella	143	928	1828-02-08	Carassius auratus
57	Buddy	145	714	1830-04-09	Oryctolagus cuniculus
58	Milo	150	46	1825-11-12	Eublepharis macularius
59	Sadie	151	922	1833-01-12	Mesocricetus auratus
60	Lola	154	951	1833-01-15	Oryctolagus cuniculus
61	Oliver	159	1112	1826-05-02	Oryctolagus cuniculus
62	Sadie	160	127	1834-11-18	Testudo hermanni
63	Buddy	161	84	1835-12-01	Felis catus
64	Bentley	163	686	1829-02-12	Chinchilla lanigera
65	Buddy	168	454	1828-03-06	Felis catus
66	Oliver	171	724	1825-01-28	Testudo hermanni
67	Max	177	881	1835-03-14	Felis catus
68	Bailey	178	1058	1825-08-05	Python regius
69	Oliver	179	786	1829-06-07	Felis catus
70	Stella	192	87	1828-02-03	Ctenosaura similis
71	Rocky	194	529	1830-12-07	Mesocricetus auratus
72	Bella	196	1221	1827-06-04	Oryctolagus cuniculus
73	Cooper	199	166	1833-04-28	Betta splendens
74	Lola	203	870	1832-04-27	Pogona vitticeps
75	Max	204	1164	1828-04-17	Betta splendens
76	Zoey	206	498	1834-09-07	Pogona vitticeps
77	Stella	210	526	1834-07-17	Eublepharis macularius
78	Toby	211	390	1833-08-24	Nymphicus hollandicus
79	Daisy	212	149	1826-08-11	Psittacus erithacus
80	Bentley	213	127	1829-12-20	Ctenosaura similis
81	Zoey	225	1112	1825-02-14	Python regius
82	Bella	230	1096	1826-08-21	Serinus canaria domestica
83	Bailey	231	883	1833-08-03	Ctenosaura similis
84	Zoey	232	668	1831-08-20	Python regius
85	Bella	235	208	1826-05-23	Melopsittacus undulatus
86	Sadie	242	563	1835-03-04	Acanthoscurria geniculata
87	Luna	245	487	1828-10-04	Ctenosaura similis
88	Milo	259	956	1808-08-04	Melopsittacus undulatus
89	Luna	261	1211	1803-02-25	Oryctolagus cuniculus
90	Oliver	263	868	1801-05-28	Nymphicus hollandicus
91	Daisy	264	954	1808-10-23	Chinchilla lanigera
92	Daisy	268	1025	1804-04-23	Serinus canaria domestica
93	Oliver	269	867	1801-01-21	Acanthoscurria geniculata
94	Max	271	6	1800-10-25	Canis lupus familiaris
95	Milo	276	261	1800-01-27	Pogona vitticeps
96	Chloe	277	964	1805-12-22	Carassius auratus
97	Bailey	280	800	1800-04-21	Rattus norvegicus domestica
98	Milo	281	38	1809-04-26	Cavia porcellus
99	Bella	285	473	1810-03-25	Betta splendens
100	Cooper	298	269	1804-05-08	Psittacus erithacus
101	Stella	300	1138	1809-12-08	Betta splendens
102	Sadie	314	229	1802-07-08	Oryctolagus cuniculus
103	Max	315	864	1802-04-02	Testudo hermanni
104	Lola	320	853	1803-09-02	Pogona vitticeps
105	Daisy	322	731	1808-02-19	Ctenosaura similis
106	Molly	324	1198	1800-03-22	Oryctolagus cuniculus
107	Max	329	282	1801-04-08	Python regius
108	Chloe	334	206	1802-10-16	Nymphicus hollandicus
109	Cooper	337	682	1802-05-13	Eublepharis macularius
110	Toby	338	804	1810-03-08	Chinchilla lanigera
111	Stella	342	212	1802-10-12	Betta splendens
112	Sadie	347	774	1809-05-10	Rattus norvegicus domestica
113	Zoey	348	569	1807-01-11	Rattus norvegicus domestica
114	Max	350	1044	1803-06-22	Pogona vitticeps
115	Milo	351	440	1802-07-03	Pogona vitticeps
116	Charlie	352	152	1810-07-14	Melopsittacus undulatus
117	Chloe	354	544	1806-06-25	Mesocricetus auratus
118	Bailey	356	1241	1805-06-02	Acanthoscurria geniculata
119	Zoey	359	701	1804-03-21	Mesocricetus auratus
120	Bailey	362	875	1800-08-08	Python regius
121	Stella	364	244	1803-06-23	Cavia porcellus
122	Chloe	366	1107	1804-03-15	Rattus norvegicus domestica
123	Bentley	373	85	1800-04-28	Eublepharis macularius
124	Lucy	374	910	1804-08-12	Pogona vitticeps
125	Zoey	394	1056	1805-02-03	Felis catus
126	Cooper	395	371	1805-02-06	Ctenosaura similis
127	Buddy	398	422	1803-04-07	Oryctolagus cuniculus
128	Lola	401	599	1805-04-11	Carassius auratus
129	Oliver	408	660	1803-03-28	Betta splendens
130	Sadie	417	527	1803-03-24	Pogona vitticeps
131	Toby	418	832	1805-06-04	Betta splendens
132	Bentley	419	803	1810-02-06	Rattus norvegicus domestica
133	Toby	422	875	1800-01-06	Testudo hermanni
134	Molly	427	259	1808-01-06	Canis lupus familiaris
135	Chloe	428	667	1804-12-18	Betta splendens
136	Molly	429	800	1801-05-26	Pogona vitticeps
137	Buddy	432	465	1808-06-24	Python regius
138	Cooper	435	888	1806-04-27	Rattus norvegicus domestica
139	Lola	436	906	1808-01-13	Melopsittacus undulatus
140	Lola	438	1244	1807-02-25	Psittacus erithacus
141	Charlie	439	745	1805-07-19	Melopsittacus undulatus
142	Bentley	440	700	1800-12-08	Pogona vitticeps
143	Lucy	441	630	1806-05-15	Cavia porcellus
144	Sadie	442	575	1808-10-10	Pogona vitticeps
145	Lucy	444	18	1807-01-04	Mesocricetus auratus
146	Rocky	445	1037	1800-06-24	Cavia porcellus
147	Cooper	446	36	1806-05-03	Betta splendens
148	Toby	448	142	1805-10-18	Cavia porcellus
149	Oliver	453	495	1801-04-17	Pogona vitticeps
150	Max	455	851	1804-11-19	Melopsittacus undulatus
151	Milo	460	63	1808-09-14	Testudo hermanni
152	Oliver	464	477	1804-09-08	Acanthoscurria geniculata
153	Bailey	468	291	1807-10-04	Mesocricetus auratus
154	Buddy	469	694	1806-02-16	Eublepharis macularius
155	Molly	471	1140	1801-07-23	Ctenosaura similis
156	Max	472	720	1803-01-18	Pogona vitticeps
157	Lola	474	377	1810-03-27	Rattus norvegicus domestica
158	Stella	478	601	1801-09-13	Pogona vitticeps
159	Bailey	480	211	1802-01-16	Cavia porcellus
160	Stella	481	879	1809-02-25	Cavia porcellus
161	Lola	484	15	1806-02-16	Rattus norvegicus domestica
162	Sadie	486	528	1807-03-07	Carassius auratus
163	Zoey	487	466	1808-08-16	Python regius
164	Buddy	490	308	1800-09-19	Pogona vitticeps
165	Bella	492	987	1807-04-09	Rattus norvegicus domestica
166	Cooper	496	513	1800-07-15	Mesocricetus auratus
167	Daisy	497	756	1804-05-06	Melopsittacus undulatus
\.


--
-- Data for Name: visa_categories; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visa_categories (type, description, working_permit, residence_permit, duration, country) FROM stdin;
1	Tourist Visas	f	f	7 years	Afghanistan
2	Business Visas	t	f	7 years	Afghanistan
3	Work Visas	t	f	10 years	Afghanistan
4	Student Visas	t	f	6 years	Afghanistan
5	Transit Visas	f	f	10 years	Afghanistan
6	Family and Dependent Visas	t	f	8 years	Afghanistan
7	Immigrant Visas	t	t	6 years	Afghanistan
8	Refugee and Asylum Visas	t	f	6 years	Afghanistan
9	Special Purpose Visas	t	f	5 years	Afghanistan
1	Tourist Visas	f	f	5 years	Albania
2	Business Visas	t	f	8 years	Albania
3	Work Visas	t	f	9 years	Albania
4	Student Visas	t	f	6 years	Albania
5	Transit Visas	f	f	6 years	Albania
6	Family and Dependent Visas	t	f	8 years	Albania
7	Immigrant Visas	t	t	10 years	Albania
8	Refugee and Asylum Visas	t	f	10 years	Albania
9	Special Purpose Visas	t	f	9 years	Albania
1	Tourist Visas	f	f	6 years	Algeria
2	Business Visas	t	f	8 years	Algeria
3	Work Visas	t	f	5 years	Algeria
4	Student Visas	t	f	10 years	Algeria
5	Transit Visas	f	f	10 years	Algeria
6	Family and Dependent Visas	t	f	5 years	Algeria
7	Immigrant Visas	t	t	9 years	Algeria
8	Refugee and Asylum Visas	t	f	9 years	Algeria
9	Special Purpose Visas	t	f	6 years	Algeria
1	Tourist Visas	f	f	8 years	Angola
2	Business Visas	t	f	7 years	Angola
3	Work Visas	t	f	7 years	Angola
4	Student Visas	t	f	7 years	Angola
5	Transit Visas	f	f	7 years	Angola
6	Family and Dependent Visas	t	f	6 years	Angola
7	Immigrant Visas	t	t	10 years	Angola
8	Refugee and Asylum Visas	t	f	10 years	Angola
9	Special Purpose Visas	t	f	10 years	Angola
1	Tourist Visas	f	f	9 years	Argentina
2	Business Visas	t	f	7 years	Argentina
3	Work Visas	t	f	5 years	Argentina
4	Student Visas	t	f	8 years	Argentina
5	Transit Visas	f	f	5 years	Argentina
6	Family and Dependent Visas	t	f	7 years	Argentina
7	Immigrant Visas	t	t	6 years	Argentina
8	Refugee and Asylum Visas	t	f	9 years	Argentina
9	Special Purpose Visas	t	f	10 years	Argentina
1	Tourist Visas	f	f	5 years	Armenia
2	Business Visas	t	f	9 years	Armenia
3	Work Visas	t	f	6 years	Armenia
4	Student Visas	t	f	7 years	Armenia
5	Transit Visas	f	f	9 years	Armenia
6	Family and Dependent Visas	t	f	7 years	Armenia
7	Immigrant Visas	t	t	9 years	Armenia
8	Refugee and Asylum Visas	t	f	8 years	Armenia
9	Special Purpose Visas	t	f	5 years	Armenia
1	Tourist Visas	f	f	6 years	Aruba
2	Business Visas	t	f	7 years	Aruba
3	Work Visas	t	f	5 years	Aruba
4	Student Visas	t	f	9 years	Aruba
5	Transit Visas	f	f	7 years	Aruba
6	Family and Dependent Visas	t	f	10 years	Aruba
7	Immigrant Visas	t	t	10 years	Aruba
8	Refugee and Asylum Visas	t	f	7 years	Aruba
9	Special Purpose Visas	t	f	6 years	Aruba
1	Tourist Visas	f	f	7 years	Australia
2	Business Visas	t	f	8 years	Australia
3	Work Visas	t	f	6 years	Australia
4	Student Visas	t	f	5 years	Australia
5	Transit Visas	f	f	8 years	Australia
6	Family and Dependent Visas	t	f	5 years	Australia
7	Immigrant Visas	t	t	10 years	Australia
8	Refugee and Asylum Visas	t	f	7 years	Australia
9	Special Purpose Visas	t	f	5 years	Australia
1	Tourist Visas	f	f	8 years	Austria
2	Business Visas	t	f	10 years	Austria
3	Work Visas	t	f	6 years	Austria
4	Student Visas	t	f	6 years	Austria
5	Transit Visas	f	f	8 years	Austria
6	Family and Dependent Visas	t	f	8 years	Austria
7	Immigrant Visas	t	t	7 years	Austria
8	Refugee and Asylum Visas	t	f	9 years	Austria
9	Special Purpose Visas	t	f	7 years	Austria
1	Tourist Visas	f	f	7 years	Azerbaijan
2	Business Visas	t	f	5 years	Azerbaijan
3	Work Visas	t	f	8 years	Azerbaijan
4	Student Visas	t	f	7 years	Azerbaijan
5	Transit Visas	f	f	5 years	Azerbaijan
6	Family and Dependent Visas	t	f	7 years	Azerbaijan
7	Immigrant Visas	t	t	8 years	Azerbaijan
8	Refugee and Asylum Visas	t	f	7 years	Azerbaijan
9	Special Purpose Visas	t	f	7 years	Azerbaijan
1	Tourist Visas	f	f	8 years	Bahamas
2	Business Visas	t	f	5 years	Bahamas
3	Work Visas	t	f	10 years	Bahamas
4	Student Visas	t	f	10 years	Bahamas
5	Transit Visas	f	f	10 years	Bahamas
6	Family and Dependent Visas	t	f	10 years	Bahamas
7	Immigrant Visas	t	t	6 years	Bahamas
8	Refugee and Asylum Visas	t	f	8 years	Bahamas
9	Special Purpose Visas	t	f	10 years	Bahamas
1	Tourist Visas	f	f	10 years	Bahrain
2	Business Visas	t	f	10 years	Bahrain
3	Work Visas	t	f	7 years	Bahrain
4	Student Visas	t	f	10 years	Bahrain
5	Transit Visas	f	f	10 years	Bahrain
6	Family and Dependent Visas	t	f	6 years	Bahrain
7	Immigrant Visas	t	t	8 years	Bahrain
8	Refugee and Asylum Visas	t	f	6 years	Bahrain
9	Special Purpose Visas	t	f	7 years	Bahrain
1	Tourist Visas	f	f	5 years	Bangladesh
2	Business Visas	t	f	7 years	Bangladesh
3	Work Visas	t	f	10 years	Bangladesh
4	Student Visas	t	f	8 years	Bangladesh
5	Transit Visas	f	f	10 years	Bangladesh
6	Family and Dependent Visas	t	f	5 years	Bangladesh
7	Immigrant Visas	t	t	9 years	Bangladesh
8	Refugee and Asylum Visas	t	f	10 years	Bangladesh
9	Special Purpose Visas	t	f	5 years	Bangladesh
1	Tourist Visas	f	f	7 years	Barbados
2	Business Visas	t	f	8 years	Barbados
3	Work Visas	t	f	6 years	Barbados
4	Student Visas	t	f	9 years	Barbados
5	Transit Visas	f	f	6 years	Barbados
6	Family and Dependent Visas	t	f	7 years	Barbados
7	Immigrant Visas	t	t	10 years	Barbados
8	Refugee and Asylum Visas	t	f	8 years	Barbados
9	Special Purpose Visas	t	f	9 years	Barbados
1	Tourist Visas	f	f	5 years	Belarus
2	Business Visas	t	f	9 years	Belarus
3	Work Visas	t	f	8 years	Belarus
4	Student Visas	t	f	5 years	Belarus
5	Transit Visas	f	f	5 years	Belarus
6	Family and Dependent Visas	t	f	5 years	Belarus
7	Immigrant Visas	t	t	5 years	Belarus
8	Refugee and Asylum Visas	t	f	5 years	Belarus
9	Special Purpose Visas	t	f	8 years	Belarus
1	Tourist Visas	f	f	7 years	Belgium
2	Business Visas	t	f	6 years	Belgium
3	Work Visas	t	f	8 years	Belgium
4	Student Visas	t	f	9 years	Belgium
5	Transit Visas	f	f	5 years	Belgium
6	Family and Dependent Visas	t	f	5 years	Belgium
7	Immigrant Visas	t	t	5 years	Belgium
8	Refugee and Asylum Visas	t	f	8 years	Belgium
9	Special Purpose Visas	t	f	8 years	Belgium
1	Tourist Visas	f	f	5 years	Belize
2	Business Visas	t	f	10 years	Belize
3	Work Visas	t	f	9 years	Belize
4	Student Visas	t	f	10 years	Belize
5	Transit Visas	f	f	5 years	Belize
6	Family and Dependent Visas	t	f	7 years	Belize
7	Immigrant Visas	t	t	7 years	Belize
8	Refugee and Asylum Visas	t	f	9 years	Belize
9	Special Purpose Visas	t	f	8 years	Belize
1	Tourist Visas	f	f	6 years	Benin
2	Business Visas	t	f	7 years	Benin
3	Work Visas	t	f	6 years	Benin
4	Student Visas	t	f	7 years	Benin
5	Transit Visas	f	f	10 years	Benin
6	Family and Dependent Visas	t	f	10 years	Benin
7	Immigrant Visas	t	t	6 years	Benin
8	Refugee and Asylum Visas	t	f	8 years	Benin
9	Special Purpose Visas	t	f	7 years	Benin
1	Tourist Visas	f	f	6 years	Bermuda
2	Business Visas	t	f	8 years	Bermuda
3	Work Visas	t	f	5 years	Bermuda
4	Student Visas	t	f	10 years	Bermuda
5	Transit Visas	f	f	7 years	Bermuda
6	Family and Dependent Visas	t	f	10 years	Bermuda
7	Immigrant Visas	t	t	8 years	Bermuda
8	Refugee and Asylum Visas	t	f	7 years	Bermuda
9	Special Purpose Visas	t	f	8 years	Bermuda
1	Tourist Visas	f	f	5 years	Bhutan
2	Business Visas	t	f	6 years	Bhutan
3	Work Visas	t	f	10 years	Bhutan
4	Student Visas	t	f	9 years	Bhutan
5	Transit Visas	f	f	9 years	Bhutan
6	Family and Dependent Visas	t	f	9 years	Bhutan
7	Immigrant Visas	t	t	7 years	Bhutan
8	Refugee and Asylum Visas	t	f	10 years	Bhutan
9	Special Purpose Visas	t	f	10 years	Bhutan
1	Tourist Visas	f	f	9 years	Bolivia
2	Business Visas	t	f	5 years	Bolivia
3	Work Visas	t	f	7 years	Bolivia
4	Student Visas	t	f	8 years	Bolivia
5	Transit Visas	f	f	5 years	Bolivia
6	Family and Dependent Visas	t	f	8 years	Bolivia
7	Immigrant Visas	t	t	10 years	Bolivia
8	Refugee and Asylum Visas	t	f	8 years	Bolivia
9	Special Purpose Visas	t	f	7 years	Bolivia
1	Tourist Visas	f	f	5 years	Botswana
2	Business Visas	t	f	9 years	Botswana
3	Work Visas	t	f	9 years	Botswana
4	Student Visas	t	f	5 years	Botswana
5	Transit Visas	f	f	9 years	Botswana
6	Family and Dependent Visas	t	f	7 years	Botswana
7	Immigrant Visas	t	t	6 years	Botswana
8	Refugee and Asylum Visas	t	f	7 years	Botswana
9	Special Purpose Visas	t	f	10 years	Botswana
1	Tourist Visas	f	f	8 years	Brazil
2	Business Visas	t	f	6 years	Brazil
3	Work Visas	t	f	5 years	Brazil
4	Student Visas	t	f	10 years	Brazil
5	Transit Visas	f	f	9 years	Brazil
6	Family and Dependent Visas	t	f	10 years	Brazil
7	Immigrant Visas	t	t	6 years	Brazil
8	Refugee and Asylum Visas	t	f	10 years	Brazil
9	Special Purpose Visas	t	f	5 years	Brazil
1	Tourist Visas	f	f	6 years	Brunei
2	Business Visas	t	f	7 years	Brunei
3	Work Visas	t	f	10 years	Brunei
4	Student Visas	t	f	9 years	Brunei
5	Transit Visas	f	f	5 years	Brunei
6	Family and Dependent Visas	t	f	10 years	Brunei
7	Immigrant Visas	t	t	8 years	Brunei
8	Refugee and Asylum Visas	t	f	6 years	Brunei
9	Special Purpose Visas	t	f	9 years	Brunei
1	Tourist Visas	f	f	6 years	Bulgaria
2	Business Visas	t	f	8 years	Bulgaria
3	Work Visas	t	f	9 years	Bulgaria
4	Student Visas	t	f	5 years	Bulgaria
5	Transit Visas	f	f	10 years	Bulgaria
6	Family and Dependent Visas	t	f	7 years	Bulgaria
7	Immigrant Visas	t	t	7 years	Bulgaria
8	Refugee and Asylum Visas	t	f	8 years	Bulgaria
9	Special Purpose Visas	t	f	9 years	Bulgaria
1	Tourist Visas	f	f	10 years	Burundi
2	Business Visas	t	f	10 years	Burundi
3	Work Visas	t	f	10 years	Burundi
4	Student Visas	t	f	7 years	Burundi
5	Transit Visas	f	f	10 years	Burundi
6	Family and Dependent Visas	t	f	10 years	Burundi
7	Immigrant Visas	t	t	9 years	Burundi
8	Refugee and Asylum Visas	t	f	7 years	Burundi
9	Special Purpose Visas	t	f	6 years	Burundi
1	Tourist Visas	f	f	7 years	Cambodia
2	Business Visas	t	f	10 years	Cambodia
3	Work Visas	t	f	7 years	Cambodia
4	Student Visas	t	f	10 years	Cambodia
5	Transit Visas	f	f	7 years	Cambodia
6	Family and Dependent Visas	t	f	5 years	Cambodia
7	Immigrant Visas	t	t	7 years	Cambodia
8	Refugee and Asylum Visas	t	f	7 years	Cambodia
9	Special Purpose Visas	t	f	5 years	Cambodia
1	Tourist Visas	f	f	9 years	Cameroon
2	Business Visas	t	f	8 years	Cameroon
3	Work Visas	t	f	10 years	Cameroon
4	Student Visas	t	f	9 years	Cameroon
5	Transit Visas	f	f	9 years	Cameroon
6	Family and Dependent Visas	t	f	9 years	Cameroon
7	Immigrant Visas	t	t	5 years	Cameroon
8	Refugee and Asylum Visas	t	f	5 years	Cameroon
9	Special Purpose Visas	t	f	9 years	Cameroon
1	Tourist Visas	f	f	10 years	Canada
2	Business Visas	t	f	9 years	Canada
3	Work Visas	t	f	8 years	Canada
4	Student Visas	t	f	7 years	Canada
5	Transit Visas	f	f	9 years	Canada
6	Family and Dependent Visas	t	f	7 years	Canada
7	Immigrant Visas	t	t	7 years	Canada
8	Refugee and Asylum Visas	t	f	8 years	Canada
9	Special Purpose Visas	t	f	6 years	Canada
1	Tourist Visas	f	f	8 years	Chad
2	Business Visas	t	f	7 years	Chad
3	Work Visas	t	f	6 years	Chad
4	Student Visas	t	f	9 years	Chad
5	Transit Visas	f	f	5 years	Chad
6	Family and Dependent Visas	t	f	8 years	Chad
7	Immigrant Visas	t	t	6 years	Chad
8	Refugee and Asylum Visas	t	f	7 years	Chad
9	Special Purpose Visas	t	f	5 years	Chad
1	Tourist Visas	f	f	9 years	Chile
2	Business Visas	t	f	9 years	Chile
3	Work Visas	t	f	5 years	Chile
4	Student Visas	t	f	6 years	Chile
5	Transit Visas	f	f	10 years	Chile
6	Family and Dependent Visas	t	f	9 years	Chile
7	Immigrant Visas	t	t	7 years	Chile
8	Refugee and Asylum Visas	t	f	9 years	Chile
9	Special Purpose Visas	t	f	7 years	Chile
1	Tourist Visas	f	f	7 years	China
2	Business Visas	t	f	6 years	China
3	Work Visas	t	f	5 years	China
4	Student Visas	t	f	8 years	China
5	Transit Visas	f	f	8 years	China
6	Family and Dependent Visas	t	f	6 years	China
7	Immigrant Visas	t	t	6 years	China
8	Refugee and Asylum Visas	t	f	8 years	China
9	Special Purpose Visas	t	f	6 years	China
1	Tourist Visas	f	f	7 years	Colombia
2	Business Visas	t	f	6 years	Colombia
3	Work Visas	t	f	10 years	Colombia
4	Student Visas	t	f	10 years	Colombia
5	Transit Visas	f	f	9 years	Colombia
6	Family and Dependent Visas	t	f	9 years	Colombia
7	Immigrant Visas	t	t	5 years	Colombia
8	Refugee and Asylum Visas	t	f	6 years	Colombia
9	Special Purpose Visas	t	f	5 years	Colombia
1	Tourist Visas	f	f	8 years	Comoros
2	Business Visas	t	f	10 years	Comoros
3	Work Visas	t	f	9 years	Comoros
4	Student Visas	t	f	6 years	Comoros
5	Transit Visas	f	f	8 years	Comoros
6	Family and Dependent Visas	t	f	9 years	Comoros
7	Immigrant Visas	t	t	8 years	Comoros
8	Refugee and Asylum Visas	t	f	8 years	Comoros
9	Special Purpose Visas	t	f	8 years	Comoros
1	Tourist Visas	f	f	8 years	Croatia
2	Business Visas	t	f	9 years	Croatia
3	Work Visas	t	f	9 years	Croatia
4	Student Visas	t	f	10 years	Croatia
5	Transit Visas	f	f	6 years	Croatia
6	Family and Dependent Visas	t	f	6 years	Croatia
7	Immigrant Visas	t	t	8 years	Croatia
8	Refugee and Asylum Visas	t	f	10 years	Croatia
9	Special Purpose Visas	t	f	8 years	Croatia
1	Tourist Visas	f	f	10 years	Cuba
2	Business Visas	t	f	5 years	Cuba
3	Work Visas	t	f	9 years	Cuba
4	Student Visas	t	f	6 years	Cuba
5	Transit Visas	f	f	6 years	Cuba
6	Family and Dependent Visas	t	f	10 years	Cuba
7	Immigrant Visas	t	t	7 years	Cuba
8	Refugee and Asylum Visas	t	f	10 years	Cuba
9	Special Purpose Visas	t	f	8 years	Cuba
1	Tourist Visas	f	f	6 years	Curacao
2	Business Visas	t	f	7 years	Curacao
3	Work Visas	t	f	10 years	Curacao
4	Student Visas	t	f	9 years	Curacao
5	Transit Visas	f	f	9 years	Curacao
6	Family and Dependent Visas	t	f	7 years	Curacao
7	Immigrant Visas	t	t	9 years	Curacao
8	Refugee and Asylum Visas	t	f	5 years	Curacao
9	Special Purpose Visas	t	f	10 years	Curacao
1	Tourist Visas	f	f	6 years	Cyprus
2	Business Visas	t	f	9 years	Cyprus
3	Work Visas	t	f	9 years	Cyprus
4	Student Visas	t	f	10 years	Cyprus
5	Transit Visas	f	f	7 years	Cyprus
6	Family and Dependent Visas	t	f	9 years	Cyprus
7	Immigrant Visas	t	t	5 years	Cyprus
8	Refugee and Asylum Visas	t	f	10 years	Cyprus
9	Special Purpose Visas	t	f	10 years	Cyprus
1	Tourist Visas	f	f	7 years	Denmark
2	Business Visas	t	f	7 years	Denmark
3	Work Visas	t	f	9 years	Denmark
4	Student Visas	t	f	9 years	Denmark
5	Transit Visas	f	f	9 years	Denmark
6	Family and Dependent Visas	t	f	10 years	Denmark
7	Immigrant Visas	t	t	5 years	Denmark
8	Refugee and Asylum Visas	t	f	10 years	Denmark
9	Special Purpose Visas	t	f	6 years	Denmark
1	Tourist Visas	f	f	7 years	Djibouti
2	Business Visas	t	f	8 years	Djibouti
3	Work Visas	t	f	9 years	Djibouti
4	Student Visas	t	f	5 years	Djibouti
5	Transit Visas	f	f	10 years	Djibouti
6	Family and Dependent Visas	t	f	6 years	Djibouti
7	Immigrant Visas	t	t	9 years	Djibouti
8	Refugee and Asylum Visas	t	f	6 years	Djibouti
9	Special Purpose Visas	t	f	8 years	Djibouti
1	Tourist Visas	f	f	6 years	Dominica
2	Business Visas	t	f	10 years	Dominica
3	Work Visas	t	f	5 years	Dominica
4	Student Visas	t	f	9 years	Dominica
5	Transit Visas	f	f	9 years	Dominica
6	Family and Dependent Visas	t	f	9 years	Dominica
7	Immigrant Visas	t	t	5 years	Dominica
8	Refugee and Asylum Visas	t	f	10 years	Dominica
9	Special Purpose Visas	t	f	5 years	Dominica
1	Tourist Visas	f	f	5 years	Ecuador
2	Business Visas	t	f	7 years	Ecuador
3	Work Visas	t	f	10 years	Ecuador
4	Student Visas	t	f	6 years	Ecuador
5	Transit Visas	f	f	5 years	Ecuador
6	Family and Dependent Visas	t	f	9 years	Ecuador
7	Immigrant Visas	t	t	10 years	Ecuador
8	Refugee and Asylum Visas	t	f	9 years	Ecuador
9	Special Purpose Visas	t	f	7 years	Ecuador
1	Tourist Visas	f	f	8 years	Egypt
2	Business Visas	t	f	5 years	Egypt
3	Work Visas	t	f	9 years	Egypt
4	Student Visas	t	f	9 years	Egypt
5	Transit Visas	f	f	8 years	Egypt
6	Family and Dependent Visas	t	f	7 years	Egypt
7	Immigrant Visas	t	t	10 years	Egypt
8	Refugee and Asylum Visas	t	f	7 years	Egypt
9	Special Purpose Visas	t	f	6 years	Egypt
1	Tourist Visas	f	f	6 years	Eritrea
2	Business Visas	t	f	7 years	Eritrea
3	Work Visas	t	f	8 years	Eritrea
4	Student Visas	t	f	6 years	Eritrea
5	Transit Visas	f	f	7 years	Eritrea
6	Family and Dependent Visas	t	f	9 years	Eritrea
7	Immigrant Visas	t	t	9 years	Eritrea
8	Refugee and Asylum Visas	t	f	7 years	Eritrea
9	Special Purpose Visas	t	f	8 years	Eritrea
1	Tourist Visas	f	f	10 years	Estonia
2	Business Visas	t	f	8 years	Estonia
3	Work Visas	t	f	9 years	Estonia
4	Student Visas	t	f	9 years	Estonia
5	Transit Visas	f	f	10 years	Estonia
6	Family and Dependent Visas	t	f	10 years	Estonia
7	Immigrant Visas	t	t	8 years	Estonia
8	Refugee and Asylum Visas	t	f	10 years	Estonia
9	Special Purpose Visas	t	f	8 years	Estonia
1	Tourist Visas	f	f	7 years	Ethiopia
2	Business Visas	t	f	6 years	Ethiopia
3	Work Visas	t	f	7 years	Ethiopia
4	Student Visas	t	f	6 years	Ethiopia
5	Transit Visas	f	f	10 years	Ethiopia
6	Family and Dependent Visas	t	f	9 years	Ethiopia
7	Immigrant Visas	t	t	8 years	Ethiopia
8	Refugee and Asylum Visas	t	f	7 years	Ethiopia
9	Special Purpose Visas	t	f	6 years	Ethiopia
1	Tourist Visas	f	f	8 years	Fiji
2	Business Visas	t	f	7 years	Fiji
3	Work Visas	t	f	8 years	Fiji
4	Student Visas	t	f	7 years	Fiji
5	Transit Visas	f	f	8 years	Fiji
6	Family and Dependent Visas	t	f	7 years	Fiji
7	Immigrant Visas	t	t	6 years	Fiji
8	Refugee and Asylum Visas	t	f	10 years	Fiji
9	Special Purpose Visas	t	f	7 years	Fiji
1	Tourist Visas	f	f	10 years	Finland
2	Business Visas	t	f	5 years	Finland
3	Work Visas	t	f	5 years	Finland
4	Student Visas	t	f	8 years	Finland
5	Transit Visas	f	f	6 years	Finland
6	Family and Dependent Visas	t	f	7 years	Finland
7	Immigrant Visas	t	t	9 years	Finland
8	Refugee and Asylum Visas	t	f	9 years	Finland
9	Special Purpose Visas	t	f	9 years	Finland
1	Tourist Visas	f	f	5 years	France
2	Business Visas	t	f	7 years	France
3	Work Visas	t	f	8 years	France
4	Student Visas	t	f	6 years	France
5	Transit Visas	f	f	6 years	France
6	Family and Dependent Visas	t	f	9 years	France
7	Immigrant Visas	t	t	5 years	France
8	Refugee and Asylum Visas	t	f	8 years	France
9	Special Purpose Visas	t	f	8 years	France
1	Tourist Visas	f	f	5 years	Gabon
2	Business Visas	t	f	10 years	Gabon
3	Work Visas	t	f	9 years	Gabon
4	Student Visas	t	f	5 years	Gabon
5	Transit Visas	f	f	6 years	Gabon
6	Family and Dependent Visas	t	f	5 years	Gabon
7	Immigrant Visas	t	t	6 years	Gabon
8	Refugee and Asylum Visas	t	f	5 years	Gabon
9	Special Purpose Visas	t	f	5 years	Gabon
1	Tourist Visas	f	f	5 years	Gambia
2	Business Visas	t	f	5 years	Gambia
3	Work Visas	t	f	5 years	Gambia
4	Student Visas	t	f	6 years	Gambia
5	Transit Visas	f	f	9 years	Gambia
6	Family and Dependent Visas	t	f	6 years	Gambia
7	Immigrant Visas	t	t	7 years	Gambia
8	Refugee and Asylum Visas	t	f	6 years	Gambia
9	Special Purpose Visas	t	f	7 years	Gambia
1	Tourist Visas	f	f	8 years	Georgia
2	Business Visas	t	f	7 years	Georgia
3	Work Visas	t	f	8 years	Georgia
4	Student Visas	t	f	9 years	Georgia
5	Transit Visas	f	f	9 years	Georgia
6	Family and Dependent Visas	t	f	5 years	Georgia
7	Immigrant Visas	t	t	10 years	Georgia
8	Refugee and Asylum Visas	t	f	5 years	Georgia
9	Special Purpose Visas	t	f	9 years	Georgia
1	Tourist Visas	f	f	6 years	Germany
2	Business Visas	t	f	8 years	Germany
3	Work Visas	t	f	9 years	Germany
4	Student Visas	t	f	9 years	Germany
5	Transit Visas	f	f	7 years	Germany
6	Family and Dependent Visas	t	f	10 years	Germany
7	Immigrant Visas	t	t	10 years	Germany
8	Refugee and Asylum Visas	t	f	10 years	Germany
9	Special Purpose Visas	t	f	6 years	Germany
1	Tourist Visas	f	f	5 years	Ghana
2	Business Visas	t	f	9 years	Ghana
3	Work Visas	t	f	9 years	Ghana
4	Student Visas	t	f	6 years	Ghana
5	Transit Visas	f	f	10 years	Ghana
6	Family and Dependent Visas	t	f	8 years	Ghana
7	Immigrant Visas	t	t	5 years	Ghana
8	Refugee and Asylum Visas	t	f	5 years	Ghana
9	Special Purpose Visas	t	f	8 years	Ghana
1	Tourist Visas	f	f	5 years	Gibraltar
2	Business Visas	t	f	7 years	Gibraltar
3	Work Visas	t	f	6 years	Gibraltar
4	Student Visas	t	f	7 years	Gibraltar
5	Transit Visas	f	f	5 years	Gibraltar
6	Family and Dependent Visas	t	f	6 years	Gibraltar
7	Immigrant Visas	t	t	6 years	Gibraltar
8	Refugee and Asylum Visas	t	f	9 years	Gibraltar
9	Special Purpose Visas	t	f	10 years	Gibraltar
1	Tourist Visas	f	f	10 years	Greece
2	Business Visas	t	f	10 years	Greece
3	Work Visas	t	f	8 years	Greece
4	Student Visas	t	f	7 years	Greece
5	Transit Visas	f	f	9 years	Greece
6	Family and Dependent Visas	t	f	8 years	Greece
7	Immigrant Visas	t	t	6 years	Greece
8	Refugee and Asylum Visas	t	f	9 years	Greece
9	Special Purpose Visas	t	f	10 years	Greece
1	Tourist Visas	f	f	10 years	Greenland
2	Business Visas	t	f	8 years	Greenland
3	Work Visas	t	f	8 years	Greenland
4	Student Visas	t	f	6 years	Greenland
5	Transit Visas	f	f	9 years	Greenland
6	Family and Dependent Visas	t	f	7 years	Greenland
7	Immigrant Visas	t	t	6 years	Greenland
8	Refugee and Asylum Visas	t	f	8 years	Greenland
9	Special Purpose Visas	t	f	5 years	Greenland
1	Tourist Visas	f	f	10 years	Guatemala
2	Business Visas	t	f	8 years	Guatemala
3	Work Visas	t	f	8 years	Guatemala
4	Student Visas	t	f	6 years	Guatemala
5	Transit Visas	f	f	9 years	Guatemala
6	Family and Dependent Visas	t	f	5 years	Guatemala
7	Immigrant Visas	t	t	10 years	Guatemala
8	Refugee and Asylum Visas	t	f	10 years	Guatemala
9	Special Purpose Visas	t	f	10 years	Guatemala
1	Tourist Visas	f	f	8 years	Guinea
2	Business Visas	t	f	9 years	Guinea
3	Work Visas	t	f	7 years	Guinea
4	Student Visas	t	f	6 years	Guinea
5	Transit Visas	f	f	6 years	Guinea
6	Family and Dependent Visas	t	f	8 years	Guinea
7	Immigrant Visas	t	t	9 years	Guinea
8	Refugee and Asylum Visas	t	f	8 years	Guinea
9	Special Purpose Visas	t	f	9 years	Guinea
1	Tourist Visas	f	f	7 years	Guyana
2	Business Visas	t	f	9 years	Guyana
3	Work Visas	t	f	7 years	Guyana
4	Student Visas	t	f	8 years	Guyana
5	Transit Visas	f	f	10 years	Guyana
6	Family and Dependent Visas	t	f	6 years	Guyana
7	Immigrant Visas	t	t	8 years	Guyana
8	Refugee and Asylum Visas	t	f	8 years	Guyana
9	Special Purpose Visas	t	f	6 years	Guyana
1	Tourist Visas	f	f	5 years	Haiti
2	Business Visas	t	f	5 years	Haiti
3	Work Visas	t	f	9 years	Haiti
4	Student Visas	t	f	5 years	Haiti
5	Transit Visas	f	f	5 years	Haiti
6	Family and Dependent Visas	t	f	9 years	Haiti
7	Immigrant Visas	t	t	8 years	Haiti
8	Refugee and Asylum Visas	t	f	6 years	Haiti
9	Special Purpose Visas	t	f	10 years	Haiti
1	Tourist Visas	f	f	10 years	Honduras
2	Business Visas	t	f	8 years	Honduras
3	Work Visas	t	f	10 years	Honduras
4	Student Visas	t	f	8 years	Honduras
5	Transit Visas	f	f	6 years	Honduras
6	Family and Dependent Visas	t	f	10 years	Honduras
7	Immigrant Visas	t	t	5 years	Honduras
8	Refugee and Asylum Visas	t	f	8 years	Honduras
9	Special Purpose Visas	t	f	7 years	Honduras
1	Tourist Visas	f	f	9 years	Hungary
2	Business Visas	t	f	9 years	Hungary
3	Work Visas	t	f	10 years	Hungary
4	Student Visas	t	f	9 years	Hungary
5	Transit Visas	f	f	10 years	Hungary
6	Family and Dependent Visas	t	f	7 years	Hungary
7	Immigrant Visas	t	t	9 years	Hungary
8	Refugee and Asylum Visas	t	f	10 years	Hungary
9	Special Purpose Visas	t	f	5 years	Hungary
1	Tourist Visas	f	f	6 years	Iceland
2	Business Visas	t	f	7 years	Iceland
3	Work Visas	t	f	10 years	Iceland
4	Student Visas	t	f	6 years	Iceland
5	Transit Visas	f	f	7 years	Iceland
6	Family and Dependent Visas	t	f	10 years	Iceland
7	Immigrant Visas	t	t	6 years	Iceland
8	Refugee and Asylum Visas	t	f	9 years	Iceland
9	Special Purpose Visas	t	f	5 years	Iceland
1	Tourist Visas	f	f	6 years	India
2	Business Visas	t	f	9 years	India
3	Work Visas	t	f	9 years	India
4	Student Visas	t	f	5 years	India
5	Transit Visas	f	f	9 years	India
6	Family and Dependent Visas	t	f	9 years	India
7	Immigrant Visas	t	t	5 years	India
8	Refugee and Asylum Visas	t	f	6 years	India
9	Special Purpose Visas	t	f	9 years	India
1	Tourist Visas	f	f	10 years	Indonesia
2	Business Visas	t	f	6 years	Indonesia
3	Work Visas	t	f	8 years	Indonesia
4	Student Visas	t	f	9 years	Indonesia
5	Transit Visas	f	f	8 years	Indonesia
6	Family and Dependent Visas	t	f	9 years	Indonesia
7	Immigrant Visas	t	t	8 years	Indonesia
8	Refugee and Asylum Visas	t	f	8 years	Indonesia
9	Special Purpose Visas	t	f	8 years	Indonesia
1	Tourist Visas	f	f	10 years	Iran
2	Business Visas	t	f	9 years	Iran
3	Work Visas	t	f	6 years	Iran
4	Student Visas	t	f	5 years	Iran
5	Transit Visas	f	f	9 years	Iran
6	Family and Dependent Visas	t	f	10 years	Iran
7	Immigrant Visas	t	t	6 years	Iran
8	Refugee and Asylum Visas	t	f	7 years	Iran
9	Special Purpose Visas	t	f	6 years	Iran
1	Tourist Visas	f	f	9 years	Iraq
2	Business Visas	t	f	7 years	Iraq
3	Work Visas	t	f	6 years	Iraq
4	Student Visas	t	f	10 years	Iraq
5	Transit Visas	f	f	6 years	Iraq
6	Family and Dependent Visas	t	f	8 years	Iraq
7	Immigrant Visas	t	t	7 years	Iraq
8	Refugee and Asylum Visas	t	f	5 years	Iraq
9	Special Purpose Visas	t	f	6 years	Iraq
1	Tourist Visas	f	f	5 years	Ireland
2	Business Visas	t	f	6 years	Ireland
3	Work Visas	t	f	8 years	Ireland
4	Student Visas	t	f	10 years	Ireland
5	Transit Visas	f	f	7 years	Ireland
6	Family and Dependent Visas	t	f	5 years	Ireland
7	Immigrant Visas	t	t	8 years	Ireland
8	Refugee and Asylum Visas	t	f	5 years	Ireland
9	Special Purpose Visas	t	f	7 years	Ireland
1	Tourist Visas	f	f	10 years	Israel
2	Business Visas	t	f	8 years	Israel
3	Work Visas	t	f	7 years	Israel
4	Student Visas	t	f	5 years	Israel
5	Transit Visas	f	f	6 years	Israel
6	Family and Dependent Visas	t	f	7 years	Israel
7	Immigrant Visas	t	t	10 years	Israel
8	Refugee and Asylum Visas	t	f	9 years	Israel
9	Special Purpose Visas	t	f	9 years	Israel
1	Tourist Visas	f	f	8 years	Italy
2	Business Visas	t	f	9 years	Italy
3	Work Visas	t	f	5 years	Italy
4	Student Visas	t	f	6 years	Italy
5	Transit Visas	f	f	10 years	Italy
6	Family and Dependent Visas	t	f	9 years	Italy
7	Immigrant Visas	t	t	5 years	Italy
8	Refugee and Asylum Visas	t	f	9 years	Italy
9	Special Purpose Visas	t	f	5 years	Italy
1	Tourist Visas	f	f	5 years	Jamaica
2	Business Visas	t	f	10 years	Jamaica
3	Work Visas	t	f	7 years	Jamaica
4	Student Visas	t	f	9 years	Jamaica
5	Transit Visas	f	f	6 years	Jamaica
6	Family and Dependent Visas	t	f	8 years	Jamaica
7	Immigrant Visas	t	t	7 years	Jamaica
8	Refugee and Asylum Visas	t	f	8 years	Jamaica
9	Special Purpose Visas	t	f	6 years	Jamaica
1	Tourist Visas	f	f	5 years	Japan
2	Business Visas	t	f	10 years	Japan
3	Work Visas	t	f	6 years	Japan
4	Student Visas	t	f	8 years	Japan
5	Transit Visas	f	f	9 years	Japan
6	Family and Dependent Visas	t	f	5 years	Japan
7	Immigrant Visas	t	t	8 years	Japan
8	Refugee and Asylum Visas	t	f	8 years	Japan
9	Special Purpose Visas	t	f	5 years	Japan
1	Tourist Visas	f	f	10 years	Jordan
2	Business Visas	t	f	6 years	Jordan
3	Work Visas	t	f	10 years	Jordan
4	Student Visas	t	f	5 years	Jordan
5	Transit Visas	f	f	10 years	Jordan
6	Family and Dependent Visas	t	f	10 years	Jordan
7	Immigrant Visas	t	t	10 years	Jordan
8	Refugee and Asylum Visas	t	f	5 years	Jordan
9	Special Purpose Visas	t	f	10 years	Jordan
1	Tourist Visas	f	f	6 years	Kazakhstan
2	Business Visas	t	f	7 years	Kazakhstan
3	Work Visas	t	f	5 years	Kazakhstan
4	Student Visas	t	f	7 years	Kazakhstan
5	Transit Visas	f	f	6 years	Kazakhstan
6	Family and Dependent Visas	t	f	8 years	Kazakhstan
7	Immigrant Visas	t	t	9 years	Kazakhstan
8	Refugee and Asylum Visas	t	f	9 years	Kazakhstan
9	Special Purpose Visas	t	f	8 years	Kazakhstan
1	Tourist Visas	f	f	7 years	Kenya
2	Business Visas	t	f	5 years	Kenya
3	Work Visas	t	f	6 years	Kenya
4	Student Visas	t	f	7 years	Kenya
5	Transit Visas	f	f	8 years	Kenya
6	Family and Dependent Visas	t	f	6 years	Kenya
7	Immigrant Visas	t	t	10 years	Kenya
8	Refugee and Asylum Visas	t	f	7 years	Kenya
9	Special Purpose Visas	t	f	9 years	Kenya
1	Tourist Visas	f	f	9 years	Kiribati
2	Business Visas	t	f	5 years	Kiribati
3	Work Visas	t	f	8 years	Kiribati
4	Student Visas	t	f	8 years	Kiribati
5	Transit Visas	f	f	9 years	Kiribati
6	Family and Dependent Visas	t	f	7 years	Kiribati
7	Immigrant Visas	t	t	8 years	Kiribati
8	Refugee and Asylum Visas	t	f	6 years	Kiribati
9	Special Purpose Visas	t	f	9 years	Kiribati
1	Tourist Visas	f	f	9 years	Kosovo
2	Business Visas	t	f	5 years	Kosovo
3	Work Visas	t	f	10 years	Kosovo
4	Student Visas	t	f	7 years	Kosovo
5	Transit Visas	f	f	6 years	Kosovo
6	Family and Dependent Visas	t	f	7 years	Kosovo
7	Immigrant Visas	t	t	10 years	Kosovo
8	Refugee and Asylum Visas	t	f	5 years	Kosovo
9	Special Purpose Visas	t	f	5 years	Kosovo
1	Tourist Visas	f	f	8 years	Kyrgyzstan
2	Business Visas	t	f	10 years	Kyrgyzstan
3	Work Visas	t	f	8 years	Kyrgyzstan
4	Student Visas	t	f	6 years	Kyrgyzstan
5	Transit Visas	f	f	7 years	Kyrgyzstan
6	Family and Dependent Visas	t	f	9 years	Kyrgyzstan
7	Immigrant Visas	t	t	6 years	Kyrgyzstan
8	Refugee and Asylum Visas	t	f	5 years	Kyrgyzstan
9	Special Purpose Visas	t	f	10 years	Kyrgyzstan
1	Tourist Visas	f	f	5 years	Laos
2	Business Visas	t	f	9 years	Laos
3	Work Visas	t	f	10 years	Laos
4	Student Visas	t	f	8 years	Laos
5	Transit Visas	f	f	9 years	Laos
6	Family and Dependent Visas	t	f	10 years	Laos
7	Immigrant Visas	t	t	10 years	Laos
8	Refugee and Asylum Visas	t	f	9 years	Laos
9	Special Purpose Visas	t	f	8 years	Laos
1	Tourist Visas	f	f	7 years	Latvia
2	Business Visas	t	f	9 years	Latvia
3	Work Visas	t	f	10 years	Latvia
4	Student Visas	t	f	9 years	Latvia
5	Transit Visas	f	f	5 years	Latvia
6	Family and Dependent Visas	t	f	9 years	Latvia
7	Immigrant Visas	t	t	8 years	Latvia
8	Refugee and Asylum Visas	t	f	6 years	Latvia
9	Special Purpose Visas	t	f	8 years	Latvia
1	Tourist Visas	f	f	10 years	Lebanon
2	Business Visas	t	f	5 years	Lebanon
3	Work Visas	t	f	10 years	Lebanon
4	Student Visas	t	f	7 years	Lebanon
5	Transit Visas	f	f	5 years	Lebanon
6	Family and Dependent Visas	t	f	8 years	Lebanon
7	Immigrant Visas	t	t	9 years	Lebanon
8	Refugee and Asylum Visas	t	f	6 years	Lebanon
9	Special Purpose Visas	t	f	6 years	Lebanon
1	Tourist Visas	f	f	5 years	Lesotho
2	Business Visas	t	f	10 years	Lesotho
3	Work Visas	t	f	8 years	Lesotho
4	Student Visas	t	f	9 years	Lesotho
5	Transit Visas	f	f	5 years	Lesotho
6	Family and Dependent Visas	t	f	9 years	Lesotho
7	Immigrant Visas	t	t	8 years	Lesotho
8	Refugee and Asylum Visas	t	f	8 years	Lesotho
9	Special Purpose Visas	t	f	5 years	Lesotho
1	Tourist Visas	f	f	10 years	Liberia
2	Business Visas	t	f	9 years	Liberia
3	Work Visas	t	f	10 years	Liberia
4	Student Visas	t	f	10 years	Liberia
5	Transit Visas	f	f	10 years	Liberia
6	Family and Dependent Visas	t	f	10 years	Liberia
7	Immigrant Visas	t	t	7 years	Liberia
8	Refugee and Asylum Visas	t	f	7 years	Liberia
9	Special Purpose Visas	t	f	8 years	Liberia
1	Tourist Visas	f	f	7 years	Libya
2	Business Visas	t	f	5 years	Libya
3	Work Visas	t	f	6 years	Libya
4	Student Visas	t	f	10 years	Libya
5	Transit Visas	f	f	5 years	Libya
6	Family and Dependent Visas	t	f	8 years	Libya
7	Immigrant Visas	t	t	8 years	Libya
8	Refugee and Asylum Visas	t	f	10 years	Libya
9	Special Purpose Visas	t	f	7 years	Libya
1	Tourist Visas	f	f	6 years	Liechtenstein
2	Business Visas	t	f	8 years	Liechtenstein
3	Work Visas	t	f	9 years	Liechtenstein
4	Student Visas	t	f	8 years	Liechtenstein
5	Transit Visas	f	f	8 years	Liechtenstein
6	Family and Dependent Visas	t	f	9 years	Liechtenstein
7	Immigrant Visas	t	t	7 years	Liechtenstein
8	Refugee and Asylum Visas	t	f	8 years	Liechtenstein
9	Special Purpose Visas	t	f	10 years	Liechtenstein
1	Tourist Visas	f	f	10 years	Lithuania
2	Business Visas	t	f	9 years	Lithuania
3	Work Visas	t	f	9 years	Lithuania
4	Student Visas	t	f	8 years	Lithuania
5	Transit Visas	f	f	10 years	Lithuania
6	Family and Dependent Visas	t	f	10 years	Lithuania
7	Immigrant Visas	t	t	7 years	Lithuania
8	Refugee and Asylum Visas	t	f	6 years	Lithuania
9	Special Purpose Visas	t	f	6 years	Lithuania
1	Tourist Visas	f	f	7 years	Luxembourg
2	Business Visas	t	f	7 years	Luxembourg
3	Work Visas	t	f	9 years	Luxembourg
4	Student Visas	t	f	10 years	Luxembourg
5	Transit Visas	f	f	7 years	Luxembourg
6	Family and Dependent Visas	t	f	5 years	Luxembourg
7	Immigrant Visas	t	t	5 years	Luxembourg
8	Refugee and Asylum Visas	t	f	8 years	Luxembourg
9	Special Purpose Visas	t	f	9 years	Luxembourg
1	Tourist Visas	f	f	6 years	Macao
2	Business Visas	t	f	8 years	Macao
3	Work Visas	t	f	5 years	Macao
4	Student Visas	t	f	5 years	Macao
5	Transit Visas	f	f	7 years	Macao
6	Family and Dependent Visas	t	f	10 years	Macao
7	Immigrant Visas	t	t	7 years	Macao
8	Refugee and Asylum Visas	t	f	10 years	Macao
9	Special Purpose Visas	t	f	7 years	Macao
1	Tourist Visas	f	f	6 years	Macedonia
2	Business Visas	t	f	10 years	Macedonia
3	Work Visas	t	f	9 years	Macedonia
4	Student Visas	t	f	10 years	Macedonia
5	Transit Visas	f	f	5 years	Macedonia
6	Family and Dependent Visas	t	f	10 years	Macedonia
7	Immigrant Visas	t	t	5 years	Macedonia
8	Refugee and Asylum Visas	t	f	5 years	Macedonia
9	Special Purpose Visas	t	f	5 years	Macedonia
1	Tourist Visas	f	f	5 years	Madagascar
2	Business Visas	t	f	10 years	Madagascar
3	Work Visas	t	f	9 years	Madagascar
4	Student Visas	t	f	5 years	Madagascar
5	Transit Visas	f	f	6 years	Madagascar
6	Family and Dependent Visas	t	f	9 years	Madagascar
7	Immigrant Visas	t	t	5 years	Madagascar
8	Refugee and Asylum Visas	t	f	8 years	Madagascar
9	Special Purpose Visas	t	f	10 years	Madagascar
1	Tourist Visas	f	f	9 years	Malawi
2	Business Visas	t	f	5 years	Malawi
3	Work Visas	t	f	5 years	Malawi
4	Student Visas	t	f	5 years	Malawi
5	Transit Visas	f	f	5 years	Malawi
6	Family and Dependent Visas	t	f	5 years	Malawi
7	Immigrant Visas	t	t	9 years	Malawi
8	Refugee and Asylum Visas	t	f	9 years	Malawi
9	Special Purpose Visas	t	f	5 years	Malawi
1	Tourist Visas	f	f	8 years	Malaysia
2	Business Visas	t	f	6 years	Malaysia
3	Work Visas	t	f	6 years	Malaysia
4	Student Visas	t	f	9 years	Malaysia
5	Transit Visas	f	f	7 years	Malaysia
6	Family and Dependent Visas	t	f	7 years	Malaysia
7	Immigrant Visas	t	t	7 years	Malaysia
8	Refugee and Asylum Visas	t	f	9 years	Malaysia
9	Special Purpose Visas	t	f	7 years	Malaysia
1	Tourist Visas	f	f	10 years	Maldives
2	Business Visas	t	f	10 years	Maldives
3	Work Visas	t	f	8 years	Maldives
4	Student Visas	t	f	6 years	Maldives
5	Transit Visas	f	f	9 years	Maldives
6	Family and Dependent Visas	t	f	10 years	Maldives
7	Immigrant Visas	t	t	9 years	Maldives
8	Refugee and Asylum Visas	t	f	6 years	Maldives
9	Special Purpose Visas	t	f	7 years	Maldives
1	Tourist Visas	f	f	8 years	Mali
2	Business Visas	t	f	8 years	Mali
3	Work Visas	t	f	6 years	Mali
4	Student Visas	t	f	5 years	Mali
5	Transit Visas	f	f	6 years	Mali
6	Family and Dependent Visas	t	f	8 years	Mali
7	Immigrant Visas	t	t	6 years	Mali
8	Refugee and Asylum Visas	t	f	8 years	Mali
9	Special Purpose Visas	t	f	5 years	Mali
1	Tourist Visas	f	f	8 years	Malta
2	Business Visas	t	f	8 years	Malta
3	Work Visas	t	f	9 years	Malta
4	Student Visas	t	f	10 years	Malta
5	Transit Visas	f	f	9 years	Malta
6	Family and Dependent Visas	t	f	8 years	Malta
7	Immigrant Visas	t	t	10 years	Malta
8	Refugee and Asylum Visas	t	f	5 years	Malta
9	Special Purpose Visas	t	f	9 years	Malta
1	Tourist Visas	f	f	5 years	Martinique
2	Business Visas	t	f	9 years	Martinique
3	Work Visas	t	f	7 years	Martinique
4	Student Visas	t	f	6 years	Martinique
5	Transit Visas	f	f	5 years	Martinique
6	Family and Dependent Visas	t	f	7 years	Martinique
7	Immigrant Visas	t	t	9 years	Martinique
8	Refugee and Asylum Visas	t	f	5 years	Martinique
9	Special Purpose Visas	t	f	10 years	Martinique
1	Tourist Visas	f	f	10 years	Mauritania
2	Business Visas	t	f	9 years	Mauritania
3	Work Visas	t	f	5 years	Mauritania
4	Student Visas	t	f	5 years	Mauritania
5	Transit Visas	f	f	6 years	Mauritania
6	Family and Dependent Visas	t	f	6 years	Mauritania
7	Immigrant Visas	t	t	8 years	Mauritania
8	Refugee and Asylum Visas	t	f	9 years	Mauritania
9	Special Purpose Visas	t	f	7 years	Mauritania
1	Tourist Visas	f	f	9 years	Mauritius
2	Business Visas	t	f	6 years	Mauritius
3	Work Visas	t	f	7 years	Mauritius
4	Student Visas	t	f	9 years	Mauritius
5	Transit Visas	f	f	9 years	Mauritius
6	Family and Dependent Visas	t	f	6 years	Mauritius
7	Immigrant Visas	t	t	5 years	Mauritius
8	Refugee and Asylum Visas	t	f	10 years	Mauritius
9	Special Purpose Visas	t	f	5 years	Mauritius
1	Tourist Visas	f	f	8 years	Mayotte
2	Business Visas	t	f	10 years	Mayotte
3	Work Visas	t	f	5 years	Mayotte
4	Student Visas	t	f	5 years	Mayotte
5	Transit Visas	f	f	9 years	Mayotte
6	Family and Dependent Visas	t	f	8 years	Mayotte
7	Immigrant Visas	t	t	9 years	Mayotte
8	Refugee and Asylum Visas	t	f	7 years	Mayotte
9	Special Purpose Visas	t	f	6 years	Mayotte
1	Tourist Visas	f	f	7 years	Mexico
2	Business Visas	t	f	5 years	Mexico
3	Work Visas	t	f	7 years	Mexico
4	Student Visas	t	f	5 years	Mexico
5	Transit Visas	f	f	6 years	Mexico
6	Family and Dependent Visas	t	f	5 years	Mexico
7	Immigrant Visas	t	t	10 years	Mexico
8	Refugee and Asylum Visas	t	f	6 years	Mexico
9	Special Purpose Visas	t	f	5 years	Mexico
1	Tourist Visas	f	f	10 years	Moldova
2	Business Visas	t	f	8 years	Moldova
3	Work Visas	t	f	8 years	Moldova
4	Student Visas	t	f	9 years	Moldova
5	Transit Visas	f	f	9 years	Moldova
6	Family and Dependent Visas	t	f	9 years	Moldova
7	Immigrant Visas	t	t	10 years	Moldova
8	Refugee and Asylum Visas	t	f	8 years	Moldova
9	Special Purpose Visas	t	f	5 years	Moldova
1	Tourist Visas	f	f	8 years	Monaco
2	Business Visas	t	f	8 years	Monaco
3	Work Visas	t	f	6 years	Monaco
4	Student Visas	t	f	5 years	Monaco
5	Transit Visas	f	f	10 years	Monaco
6	Family and Dependent Visas	t	f	8 years	Monaco
7	Immigrant Visas	t	t	9 years	Monaco
8	Refugee and Asylum Visas	t	f	9 years	Monaco
9	Special Purpose Visas	t	f	8 years	Monaco
1	Tourist Visas	f	f	5 years	Mongolia
2	Business Visas	t	f	10 years	Mongolia
3	Work Visas	t	f	8 years	Mongolia
4	Student Visas	t	f	8 years	Mongolia
5	Transit Visas	f	f	6 years	Mongolia
6	Family and Dependent Visas	t	f	10 years	Mongolia
7	Immigrant Visas	t	t	6 years	Mongolia
8	Refugee and Asylum Visas	t	f	6 years	Mongolia
9	Special Purpose Visas	t	f	6 years	Mongolia
1	Tourist Visas	f	f	9 years	Montenegro
2	Business Visas	t	f	9 years	Montenegro
3	Work Visas	t	f	9 years	Montenegro
4	Student Visas	t	f	10 years	Montenegro
5	Transit Visas	f	f	6 years	Montenegro
6	Family and Dependent Visas	t	f	7 years	Montenegro
7	Immigrant Visas	t	t	6 years	Montenegro
8	Refugee and Asylum Visas	t	f	5 years	Montenegro
9	Special Purpose Visas	t	f	6 years	Montenegro
1	Tourist Visas	f	f	10 years	Montserrat
2	Business Visas	t	f	9 years	Montserrat
3	Work Visas	t	f	5 years	Montserrat
4	Student Visas	t	f	9 years	Montserrat
5	Transit Visas	f	f	7 years	Montserrat
6	Family and Dependent Visas	t	f	8 years	Montserrat
7	Immigrant Visas	t	t	9 years	Montserrat
8	Refugee and Asylum Visas	t	f	9 years	Montserrat
9	Special Purpose Visas	t	f	8 years	Montserrat
1	Tourist Visas	f	f	10 years	Morocco
2	Business Visas	t	f	9 years	Morocco
3	Work Visas	t	f	6 years	Morocco
4	Student Visas	t	f	9 years	Morocco
5	Transit Visas	f	f	7 years	Morocco
6	Family and Dependent Visas	t	f	9 years	Morocco
7	Immigrant Visas	t	t	6 years	Morocco
8	Refugee and Asylum Visas	t	f	6 years	Morocco
9	Special Purpose Visas	t	f	9 years	Morocco
1	Tourist Visas	f	f	10 years	Mozambique
2	Business Visas	t	f	7 years	Mozambique
3	Work Visas	t	f	6 years	Mozambique
4	Student Visas	t	f	10 years	Mozambique
5	Transit Visas	f	f	8 years	Mozambique
6	Family and Dependent Visas	t	f	10 years	Mozambique
7	Immigrant Visas	t	t	7 years	Mozambique
8	Refugee and Asylum Visas	t	f	10 years	Mozambique
9	Special Purpose Visas	t	f	8 years	Mozambique
1	Tourist Visas	f	f	10 years	Myanmar
2	Business Visas	t	f	6 years	Myanmar
3	Work Visas	t	f	9 years	Myanmar
4	Student Visas	t	f	9 years	Myanmar
5	Transit Visas	f	f	9 years	Myanmar
6	Family and Dependent Visas	t	f	9 years	Myanmar
7	Immigrant Visas	t	t	5 years	Myanmar
8	Refugee and Asylum Visas	t	f	8 years	Myanmar
9	Special Purpose Visas	t	f	7 years	Myanmar
1	Tourist Visas	f	f	7 years	Namibia
2	Business Visas	t	f	7 years	Namibia
3	Work Visas	t	f	9 years	Namibia
4	Student Visas	t	f	8 years	Namibia
5	Transit Visas	f	f	8 years	Namibia
6	Family and Dependent Visas	t	f	9 years	Namibia
7	Immigrant Visas	t	t	7 years	Namibia
8	Refugee and Asylum Visas	t	f	9 years	Namibia
9	Special Purpose Visas	t	f	9 years	Namibia
1	Tourist Visas	f	f	6 years	Nauru
2	Business Visas	t	f	6 years	Nauru
3	Work Visas	t	f	8 years	Nauru
4	Student Visas	t	f	10 years	Nauru
5	Transit Visas	f	f	6 years	Nauru
6	Family and Dependent Visas	t	f	7 years	Nauru
7	Immigrant Visas	t	t	5 years	Nauru
8	Refugee and Asylum Visas	t	f	6 years	Nauru
9	Special Purpose Visas	t	f	9 years	Nauru
1	Tourist Visas	f	f	10 years	Nepal
2	Business Visas	t	f	9 years	Nepal
3	Work Visas	t	f	9 years	Nepal
4	Student Visas	t	f	5 years	Nepal
5	Transit Visas	f	f	9 years	Nepal
6	Family and Dependent Visas	t	f	10 years	Nepal
7	Immigrant Visas	t	t	9 years	Nepal
8	Refugee and Asylum Visas	t	f	10 years	Nepal
9	Special Purpose Visas	t	f	5 years	Nepal
1	Tourist Visas	f	f	7 years	Netherlands
2	Business Visas	t	f	6 years	Netherlands
3	Work Visas	t	f	5 years	Netherlands
4	Student Visas	t	f	8 years	Netherlands
5	Transit Visas	f	f	8 years	Netherlands
6	Family and Dependent Visas	t	f	7 years	Netherlands
7	Immigrant Visas	t	t	10 years	Netherlands
8	Refugee and Asylum Visas	t	f	9 years	Netherlands
9	Special Purpose Visas	t	f	10 years	Netherlands
1	Tourist Visas	f	f	5 years	Nicaragua
2	Business Visas	t	f	6 years	Nicaragua
3	Work Visas	t	f	6 years	Nicaragua
4	Student Visas	t	f	7 years	Nicaragua
5	Transit Visas	f	f	10 years	Nicaragua
6	Family and Dependent Visas	t	f	5 years	Nicaragua
7	Immigrant Visas	t	t	6 years	Nicaragua
8	Refugee and Asylum Visas	t	f	8 years	Nicaragua
9	Special Purpose Visas	t	f	9 years	Nicaragua
1	Tourist Visas	f	f	10 years	Niger
2	Business Visas	t	f	7 years	Niger
3	Work Visas	t	f	6 years	Niger
4	Student Visas	t	f	5 years	Niger
5	Transit Visas	f	f	8 years	Niger
6	Family and Dependent Visas	t	f	6 years	Niger
7	Immigrant Visas	t	t	9 years	Niger
8	Refugee and Asylum Visas	t	f	8 years	Niger
9	Special Purpose Visas	t	f	9 years	Niger
1	Tourist Visas	f	f	6 years	Nigeria
2	Business Visas	t	f	10 years	Nigeria
3	Work Visas	t	f	5 years	Nigeria
4	Student Visas	t	f	8 years	Nigeria
5	Transit Visas	f	f	6 years	Nigeria
6	Family and Dependent Visas	t	f	8 years	Nigeria
7	Immigrant Visas	t	t	8 years	Nigeria
8	Refugee and Asylum Visas	t	f	6 years	Nigeria
9	Special Purpose Visas	t	f	9 years	Nigeria
1	Tourist Visas	f	f	7 years	Niue
2	Business Visas	t	f	9 years	Niue
3	Work Visas	t	f	10 years	Niue
4	Student Visas	t	f	5 years	Niue
5	Transit Visas	f	f	10 years	Niue
6	Family and Dependent Visas	t	f	5 years	Niue
7	Immigrant Visas	t	t	5 years	Niue
8	Refugee and Asylum Visas	t	f	10 years	Niue
9	Special Purpose Visas	t	f	6 years	Niue
1	Tourist Visas	f	f	6 years	Norway
2	Business Visas	t	f	8 years	Norway
3	Work Visas	t	f	10 years	Norway
4	Student Visas	t	f	10 years	Norway
5	Transit Visas	f	f	10 years	Norway
6	Family and Dependent Visas	t	f	7 years	Norway
7	Immigrant Visas	t	t	7 years	Norway
8	Refugee and Asylum Visas	t	f	9 years	Norway
9	Special Purpose Visas	t	f	10 years	Norway
1	Tourist Visas	f	f	10 years	Oman
2	Business Visas	t	f	9 years	Oman
3	Work Visas	t	f	5 years	Oman
4	Student Visas	t	f	8 years	Oman
5	Transit Visas	f	f	6 years	Oman
6	Family and Dependent Visas	t	f	7 years	Oman
7	Immigrant Visas	t	t	7 years	Oman
8	Refugee and Asylum Visas	t	f	9 years	Oman
9	Special Purpose Visas	t	f	9 years	Oman
1	Tourist Visas	f	f	7 years	Pakistan
2	Business Visas	t	f	9 years	Pakistan
3	Work Visas	t	f	5 years	Pakistan
4	Student Visas	t	f	6 years	Pakistan
5	Transit Visas	f	f	7 years	Pakistan
6	Family and Dependent Visas	t	f	7 years	Pakistan
7	Immigrant Visas	t	t	9 years	Pakistan
8	Refugee and Asylum Visas	t	f	5 years	Pakistan
9	Special Purpose Visas	t	f	8 years	Pakistan
1	Tourist Visas	f	f	10 years	Palau
2	Business Visas	t	f	8 years	Palau
3	Work Visas	t	f	10 years	Palau
4	Student Visas	t	f	8 years	Palau
5	Transit Visas	f	f	7 years	Palau
6	Family and Dependent Visas	t	f	5 years	Palau
7	Immigrant Visas	t	t	5 years	Palau
8	Refugee and Asylum Visas	t	f	9 years	Palau
9	Special Purpose Visas	t	f	9 years	Palau
1	Tourist Visas	f	f	5 years	Panama
2	Business Visas	t	f	5 years	Panama
3	Work Visas	t	f	6 years	Panama
4	Student Visas	t	f	7 years	Panama
5	Transit Visas	f	f	10 years	Panama
6	Family and Dependent Visas	t	f	10 years	Panama
7	Immigrant Visas	t	t	9 years	Panama
8	Refugee and Asylum Visas	t	f	8 years	Panama
9	Special Purpose Visas	t	f	9 years	Panama
1	Tourist Visas	f	f	10 years	Paraguay
2	Business Visas	t	f	9 years	Paraguay
3	Work Visas	t	f	5 years	Paraguay
4	Student Visas	t	f	6 years	Paraguay
5	Transit Visas	f	f	8 years	Paraguay
6	Family and Dependent Visas	t	f	5 years	Paraguay
7	Immigrant Visas	t	t	6 years	Paraguay
8	Refugee and Asylum Visas	t	f	5 years	Paraguay
9	Special Purpose Visas	t	f	5 years	Paraguay
1	Tourist Visas	f	f	9 years	Peru
2	Business Visas	t	f	7 years	Peru
3	Work Visas	t	f	9 years	Peru
4	Student Visas	t	f	8 years	Peru
5	Transit Visas	f	f	9 years	Peru
6	Family and Dependent Visas	t	f	5 years	Peru
7	Immigrant Visas	t	t	7 years	Peru
8	Refugee and Asylum Visas	t	f	5 years	Peru
9	Special Purpose Visas	t	f	7 years	Peru
1	Tourist Visas	f	f	6 years	Philippines
2	Business Visas	t	f	6 years	Philippines
3	Work Visas	t	f	8 years	Philippines
4	Student Visas	t	f	5 years	Philippines
5	Transit Visas	f	f	5 years	Philippines
6	Family and Dependent Visas	t	f	6 years	Philippines
7	Immigrant Visas	t	t	6 years	Philippines
8	Refugee and Asylum Visas	t	f	5 years	Philippines
9	Special Purpose Visas	t	f	7 years	Philippines
1	Tourist Visas	f	f	9 years	Pitcairn
2	Business Visas	t	f	8 years	Pitcairn
3	Work Visas	t	f	5 years	Pitcairn
4	Student Visas	t	f	8 years	Pitcairn
5	Transit Visas	f	f	5 years	Pitcairn
6	Family and Dependent Visas	t	f	9 years	Pitcairn
7	Immigrant Visas	t	t	7 years	Pitcairn
8	Refugee and Asylum Visas	t	f	7 years	Pitcairn
9	Special Purpose Visas	t	f	5 years	Pitcairn
1	Tourist Visas	f	f	8 years	Poland
2	Business Visas	t	f	8 years	Poland
3	Work Visas	t	f	7 years	Poland
4	Student Visas	t	f	10 years	Poland
5	Transit Visas	f	f	8 years	Poland
6	Family and Dependent Visas	t	f	5 years	Poland
7	Immigrant Visas	t	t	9 years	Poland
8	Refugee and Asylum Visas	t	f	7 years	Poland
9	Special Purpose Visas	t	f	5 years	Poland
1	Tourist Visas	f	f	5 years	Portugal
2	Business Visas	t	f	10 years	Portugal
3	Work Visas	t	f	6 years	Portugal
4	Student Visas	t	f	8 years	Portugal
5	Transit Visas	f	f	6 years	Portugal
6	Family and Dependent Visas	t	f	8 years	Portugal
7	Immigrant Visas	t	t	7 years	Portugal
8	Refugee and Asylum Visas	t	f	8 years	Portugal
9	Special Purpose Visas	t	f	10 years	Portugal
1	Tourist Visas	f	f	8 years	Qatar
2	Business Visas	t	f	5 years	Qatar
3	Work Visas	t	f	7 years	Qatar
4	Student Visas	t	f	8 years	Qatar
5	Transit Visas	f	f	8 years	Qatar
6	Family and Dependent Visas	t	f	9 years	Qatar
7	Immigrant Visas	t	t	8 years	Qatar
8	Refugee and Asylum Visas	t	f	7 years	Qatar
9	Special Purpose Visas	t	f	8 years	Qatar
1	Tourist Visas	f	f	8 years	Romania
2	Business Visas	t	f	7 years	Romania
3	Work Visas	t	f	9 years	Romania
4	Student Visas	t	f	10 years	Romania
5	Transit Visas	f	f	7 years	Romania
6	Family and Dependent Visas	t	f	7 years	Romania
7	Immigrant Visas	t	t	6 years	Romania
8	Refugee and Asylum Visas	t	f	6 years	Romania
9	Special Purpose Visas	t	f	10 years	Romania
1	Tourist Visas	f	f	10 years	Russia
2	Business Visas	t	f	7 years	Russia
3	Work Visas	t	f	9 years	Russia
4	Student Visas	t	f	10 years	Russia
5	Transit Visas	f	f	9 years	Russia
6	Family and Dependent Visas	t	f	5 years	Russia
7	Immigrant Visas	t	t	5 years	Russia
8	Refugee and Asylum Visas	t	f	9 years	Russia
9	Special Purpose Visas	t	f	7 years	Russia
1	Tourist Visas	f	f	9 years	Rwanda
2	Business Visas	t	f	5 years	Rwanda
3	Work Visas	t	f	8 years	Rwanda
4	Student Visas	t	f	9 years	Rwanda
5	Transit Visas	f	f	9 years	Rwanda
6	Family and Dependent Visas	t	f	8 years	Rwanda
7	Immigrant Visas	t	t	8 years	Rwanda
8	Refugee and Asylum Visas	t	f	5 years	Rwanda
9	Special Purpose Visas	t	f	10 years	Rwanda
1	Tourist Visas	f	f	8 years	Samoa
2	Business Visas	t	f	8 years	Samoa
3	Work Visas	t	f	6 years	Samoa
4	Student Visas	t	f	9 years	Samoa
5	Transit Visas	f	f	6 years	Samoa
6	Family and Dependent Visas	t	f	7 years	Samoa
7	Immigrant Visas	t	t	7 years	Samoa
8	Refugee and Asylum Visas	t	f	9 years	Samoa
9	Special Purpose Visas	t	f	6 years	Samoa
1	Tourist Visas	f	f	8 years	Senegal
2	Business Visas	t	f	6 years	Senegal
3	Work Visas	t	f	5 years	Senegal
4	Student Visas	t	f	6 years	Senegal
5	Transit Visas	f	f	6 years	Senegal
6	Family and Dependent Visas	t	f	6 years	Senegal
7	Immigrant Visas	t	t	7 years	Senegal
8	Refugee and Asylum Visas	t	f	9 years	Senegal
9	Special Purpose Visas	t	f	6 years	Senegal
1	Tourist Visas	f	f	10 years	Serbia
2	Business Visas	t	f	9 years	Serbia
3	Work Visas	t	f	10 years	Serbia
4	Student Visas	t	f	10 years	Serbia
5	Transit Visas	f	f	8 years	Serbia
6	Family and Dependent Visas	t	f	9 years	Serbia
7	Immigrant Visas	t	t	9 years	Serbia
8	Refugee and Asylum Visas	t	f	9 years	Serbia
9	Special Purpose Visas	t	f	5 years	Serbia
1	Tourist Visas	f	f	8 years	Seychelles
2	Business Visas	t	f	7 years	Seychelles
3	Work Visas	t	f	9 years	Seychelles
4	Student Visas	t	f	8 years	Seychelles
5	Transit Visas	f	f	7 years	Seychelles
6	Family and Dependent Visas	t	f	7 years	Seychelles
7	Immigrant Visas	t	t	10 years	Seychelles
8	Refugee and Asylum Visas	t	f	7 years	Seychelles
9	Special Purpose Visas	t	f	9 years	Seychelles
1	Tourist Visas	f	f	6 years	Singapore
2	Business Visas	t	f	5 years	Singapore
3	Work Visas	t	f	6 years	Singapore
4	Student Visas	t	f	10 years	Singapore
5	Transit Visas	f	f	9 years	Singapore
6	Family and Dependent Visas	t	f	8 years	Singapore
7	Immigrant Visas	t	t	6 years	Singapore
8	Refugee and Asylum Visas	t	f	9 years	Singapore
9	Special Purpose Visas	t	f	7 years	Singapore
1	Tourist Visas	f	f	8 years	Slovakia
2	Business Visas	t	f	6 years	Slovakia
3	Work Visas	t	f	7 years	Slovakia
4	Student Visas	t	f	7 years	Slovakia
5	Transit Visas	f	f	7 years	Slovakia
6	Family and Dependent Visas	t	f	8 years	Slovakia
7	Immigrant Visas	t	t	5 years	Slovakia
8	Refugee and Asylum Visas	t	f	7 years	Slovakia
9	Special Purpose Visas	t	f	9 years	Slovakia
1	Tourist Visas	f	f	7 years	Slovenia
2	Business Visas	t	f	6 years	Slovenia
3	Work Visas	t	f	10 years	Slovenia
4	Student Visas	t	f	8 years	Slovenia
5	Transit Visas	f	f	6 years	Slovenia
6	Family and Dependent Visas	t	f	6 years	Slovenia
7	Immigrant Visas	t	t	8 years	Slovenia
8	Refugee and Asylum Visas	t	f	6 years	Slovenia
9	Special Purpose Visas	t	f	8 years	Slovenia
1	Tourist Visas	f	f	8 years	Somalia
2	Business Visas	t	f	6 years	Somalia
3	Work Visas	t	f	8 years	Somalia
4	Student Visas	t	f	7 years	Somalia
5	Transit Visas	f	f	9 years	Somalia
6	Family and Dependent Visas	t	f	7 years	Somalia
7	Immigrant Visas	t	t	7 years	Somalia
8	Refugee and Asylum Visas	t	f	8 years	Somalia
9	Special Purpose Visas	t	f	6 years	Somalia
1	Tourist Visas	f	f	6 years	Spain
2	Business Visas	t	f	8 years	Spain
3	Work Visas	t	f	9 years	Spain
4	Student Visas	t	f	10 years	Spain
5	Transit Visas	f	f	10 years	Spain
6	Family and Dependent Visas	t	f	7 years	Spain
7	Immigrant Visas	t	t	6 years	Spain
8	Refugee and Asylum Visas	t	f	5 years	Spain
9	Special Purpose Visas	t	f	9 years	Spain
1	Tourist Visas	f	f	10 years	Sudan
2	Business Visas	t	f	8 years	Sudan
3	Work Visas	t	f	10 years	Sudan
4	Student Visas	t	f	10 years	Sudan
5	Transit Visas	f	f	6 years	Sudan
6	Family and Dependent Visas	t	f	9 years	Sudan
7	Immigrant Visas	t	t	7 years	Sudan
8	Refugee and Asylum Visas	t	f	9 years	Sudan
9	Special Purpose Visas	t	f	7 years	Sudan
1	Tourist Visas	f	f	7 years	Suriname
2	Business Visas	t	f	5 years	Suriname
3	Work Visas	t	f	7 years	Suriname
4	Student Visas	t	f	6 years	Suriname
5	Transit Visas	f	f	5 years	Suriname
6	Family and Dependent Visas	t	f	7 years	Suriname
7	Immigrant Visas	t	t	10 years	Suriname
8	Refugee and Asylum Visas	t	f	8 years	Suriname
9	Special Purpose Visas	t	f	5 years	Suriname
1	Tourist Visas	f	f	7 years	Swaziland
2	Business Visas	t	f	9 years	Swaziland
3	Work Visas	t	f	9 years	Swaziland
4	Student Visas	t	f	7 years	Swaziland
5	Transit Visas	f	f	10 years	Swaziland
6	Family and Dependent Visas	t	f	10 years	Swaziland
7	Immigrant Visas	t	t	5 years	Swaziland
8	Refugee and Asylum Visas	t	f	8 years	Swaziland
9	Special Purpose Visas	t	f	10 years	Swaziland
1	Tourist Visas	f	f	5 years	Sweden
2	Business Visas	t	f	8 years	Sweden
3	Work Visas	t	f	8 years	Sweden
4	Student Visas	t	f	9 years	Sweden
5	Transit Visas	f	f	6 years	Sweden
6	Family and Dependent Visas	t	f	9 years	Sweden
7	Immigrant Visas	t	t	10 years	Sweden
8	Refugee and Asylum Visas	t	f	10 years	Sweden
9	Special Purpose Visas	t	f	7 years	Sweden
1	Tourist Visas	f	f	7 years	Switzerland
2	Business Visas	t	f	10 years	Switzerland
3	Work Visas	t	f	10 years	Switzerland
4	Student Visas	t	f	9 years	Switzerland
5	Transit Visas	f	f	9 years	Switzerland
6	Family and Dependent Visas	t	f	9 years	Switzerland
7	Immigrant Visas	t	t	10 years	Switzerland
8	Refugee and Asylum Visas	t	f	6 years	Switzerland
9	Special Purpose Visas	t	f	7 years	Switzerland
1	Tourist Visas	f	f	8 years	Syria
2	Business Visas	t	f	9 years	Syria
3	Work Visas	t	f	10 years	Syria
4	Student Visas	t	f	6 years	Syria
5	Transit Visas	f	f	9 years	Syria
6	Family and Dependent Visas	t	f	9 years	Syria
7	Immigrant Visas	t	t	5 years	Syria
8	Refugee and Asylum Visas	t	f	10 years	Syria
9	Special Purpose Visas	t	f	9 years	Syria
1	Tourist Visas	f	f	7 years	Taiwan
2	Business Visas	t	f	6 years	Taiwan
3	Work Visas	t	f	7 years	Taiwan
4	Student Visas	t	f	10 years	Taiwan
5	Transit Visas	f	f	8 years	Taiwan
6	Family and Dependent Visas	t	f	7 years	Taiwan
7	Immigrant Visas	t	t	8 years	Taiwan
8	Refugee and Asylum Visas	t	f	5 years	Taiwan
9	Special Purpose Visas	t	f	9 years	Taiwan
1	Tourist Visas	f	f	9 years	Tajikistan
2	Business Visas	t	f	10 years	Tajikistan
3	Work Visas	t	f	10 years	Tajikistan
4	Student Visas	t	f	6 years	Tajikistan
5	Transit Visas	f	f	8 years	Tajikistan
6	Family and Dependent Visas	t	f	8 years	Tajikistan
7	Immigrant Visas	t	t	7 years	Tajikistan
8	Refugee and Asylum Visas	t	f	10 years	Tajikistan
9	Special Purpose Visas	t	f	5 years	Tajikistan
1	Tourist Visas	f	f	8 years	Tanzania
2	Business Visas	t	f	5 years	Tanzania
3	Work Visas	t	f	5 years	Tanzania
4	Student Visas	t	f	5 years	Tanzania
5	Transit Visas	f	f	5 years	Tanzania
6	Family and Dependent Visas	t	f	10 years	Tanzania
7	Immigrant Visas	t	t	7 years	Tanzania
8	Refugee and Asylum Visas	t	f	10 years	Tanzania
9	Special Purpose Visas	t	f	9 years	Tanzania
1	Tourist Visas	f	f	7 years	Thailand
2	Business Visas	t	f	7 years	Thailand
3	Work Visas	t	f	8 years	Thailand
4	Student Visas	t	f	7 years	Thailand
5	Transit Visas	f	f	5 years	Thailand
6	Family and Dependent Visas	t	f	5 years	Thailand
7	Immigrant Visas	t	t	9 years	Thailand
8	Refugee and Asylum Visas	t	f	5 years	Thailand
9	Special Purpose Visas	t	f	6 years	Thailand
1	Tourist Visas	f	f	8 years	Togo
2	Business Visas	t	f	10 years	Togo
3	Work Visas	t	f	10 years	Togo
4	Student Visas	t	f	8 years	Togo
5	Transit Visas	f	f	10 years	Togo
6	Family and Dependent Visas	t	f	8 years	Togo
7	Immigrant Visas	t	t	8 years	Togo
8	Refugee and Asylum Visas	t	f	7 years	Togo
9	Special Purpose Visas	t	f	5 years	Togo
1	Tourist Visas	f	f	8 years	Tunisia
2	Business Visas	t	f	7 years	Tunisia
3	Work Visas	t	f	5 years	Tunisia
4	Student Visas	t	f	7 years	Tunisia
5	Transit Visas	f	f	8 years	Tunisia
6	Family and Dependent Visas	t	f	8 years	Tunisia
7	Immigrant Visas	t	t	9 years	Tunisia
8	Refugee and Asylum Visas	t	f	6 years	Tunisia
9	Special Purpose Visas	t	f	7 years	Tunisia
1	Tourist Visas	f	f	10 years	Turkey
2	Business Visas	t	f	10 years	Turkey
3	Work Visas	t	f	6 years	Turkey
4	Student Visas	t	f	9 years	Turkey
5	Transit Visas	f	f	6 years	Turkey
6	Family and Dependent Visas	t	f	5 years	Turkey
7	Immigrant Visas	t	t	8 years	Turkey
8	Refugee and Asylum Visas	t	f	6 years	Turkey
9	Special Purpose Visas	t	f	8 years	Turkey
1	Tourist Visas	f	f	7 years	Turkmenistan
2	Business Visas	t	f	6 years	Turkmenistan
3	Work Visas	t	f	10 years	Turkmenistan
4	Student Visas	t	f	5 years	Turkmenistan
5	Transit Visas	f	f	8 years	Turkmenistan
6	Family and Dependent Visas	t	f	9 years	Turkmenistan
7	Immigrant Visas	t	t	7 years	Turkmenistan
8	Refugee and Asylum Visas	t	f	8 years	Turkmenistan
9	Special Purpose Visas	t	f	7 years	Turkmenistan
1	Tourist Visas	f	f	9 years	Tuvalu
2	Business Visas	t	f	5 years	Tuvalu
3	Work Visas	t	f	8 years	Tuvalu
4	Student Visas	t	f	9 years	Tuvalu
5	Transit Visas	f	f	8 years	Tuvalu
6	Family and Dependent Visas	t	f	6 years	Tuvalu
7	Immigrant Visas	t	t	10 years	Tuvalu
8	Refugee and Asylum Visas	t	f	7 years	Tuvalu
9	Special Purpose Visas	t	f	10 years	Tuvalu
1	Tourist Visas	f	f	9 years	Uganda
2	Business Visas	t	f	6 years	Uganda
3	Work Visas	t	f	7 years	Uganda
4	Student Visas	t	f	6 years	Uganda
5	Transit Visas	f	f	9 years	Uganda
6	Family and Dependent Visas	t	f	5 years	Uganda
7	Immigrant Visas	t	t	9 years	Uganda
8	Refugee and Asylum Visas	t	f	5 years	Uganda
9	Special Purpose Visas	t	f	7 years	Uganda
1	Tourist Visas	f	f	8 years	Ukraine
2	Business Visas	t	f	9 years	Ukraine
3	Work Visas	t	f	7 years	Ukraine
4	Student Visas	t	f	7 years	Ukraine
5	Transit Visas	f	f	6 years	Ukraine
6	Family and Dependent Visas	t	f	10 years	Ukraine
7	Immigrant Visas	t	t	7 years	Ukraine
8	Refugee and Asylum Visas	t	f	5 years	Ukraine
9	Special Purpose Visas	t	f	10 years	Ukraine
1	Tourist Visas	f	f	5 years	Uruguay
2	Business Visas	t	f	6 years	Uruguay
3	Work Visas	t	f	7 years	Uruguay
4	Student Visas	t	f	9 years	Uruguay
5	Transit Visas	f	f	9 years	Uruguay
6	Family and Dependent Visas	t	f	9 years	Uruguay
7	Immigrant Visas	t	t	6 years	Uruguay
8	Refugee and Asylum Visas	t	f	10 years	Uruguay
9	Special Purpose Visas	t	f	5 years	Uruguay
1	Tourist Visas	f	f	7 years	Uzbekistan
2	Business Visas	t	f	7 years	Uzbekistan
3	Work Visas	t	f	9 years	Uzbekistan
4	Student Visas	t	f	9 years	Uzbekistan
5	Transit Visas	f	f	5 years	Uzbekistan
6	Family and Dependent Visas	t	f	6 years	Uzbekistan
7	Immigrant Visas	t	t	6 years	Uzbekistan
8	Refugee and Asylum Visas	t	f	8 years	Uzbekistan
9	Special Purpose Visas	t	f	6 years	Uzbekistan
1	Tourist Visas	f	f	7 years	Venezuela
2	Business Visas	t	f	7 years	Venezuela
3	Work Visas	t	f	8 years	Venezuela
4	Student Visas	t	f	8 years	Venezuela
5	Transit Visas	f	f	5 years	Venezuela
6	Family and Dependent Visas	t	f	5 years	Venezuela
7	Immigrant Visas	t	t	7 years	Venezuela
8	Refugee and Asylum Visas	t	f	7 years	Venezuela
9	Special Purpose Visas	t	f	5 years	Venezuela
1	Tourist Visas	f	f	5 years	Vietnam
2	Business Visas	t	f	9 years	Vietnam
3	Work Visas	t	f	8 years	Vietnam
4	Student Visas	t	f	8 years	Vietnam
5	Transit Visas	f	f	10 years	Vietnam
6	Family and Dependent Visas	t	f	10 years	Vietnam
7	Immigrant Visas	t	t	6 years	Vietnam
8	Refugee and Asylum Visas	t	f	6 years	Vietnam
9	Special Purpose Visas	t	f	8 years	Vietnam
1	Tourist Visas	f	f	8 years	Yemen
2	Business Visas	t	f	8 years	Yemen
3	Work Visas	t	f	7 years	Yemen
4	Student Visas	t	f	8 years	Yemen
5	Transit Visas	f	f	10 years	Yemen
6	Family and Dependent Visas	t	f	5 years	Yemen
7	Immigrant Visas	t	t	10 years	Yemen
8	Refugee and Asylum Visas	t	f	7 years	Yemen
9	Special Purpose Visas	t	f	8 years	Yemen
1	Tourist Visas	f	f	6 years	Zambia
2	Business Visas	t	f	8 years	Zambia
3	Work Visas	t	f	7 years	Zambia
4	Student Visas	t	f	9 years	Zambia
5	Transit Visas	f	f	8 years	Zambia
6	Family and Dependent Visas	t	f	5 years	Zambia
7	Immigrant Visas	t	t	9 years	Zambia
8	Refugee and Asylum Visas	t	f	8 years	Zambia
9	Special Purpose Visas	t	f	5 years	Zambia
1	Tourist Visas	f	f	5 years	Zimbabwe
2	Business Visas	t	f	8 years	Zimbabwe
3	Work Visas	t	f	7 years	Zimbabwe
4	Student Visas	t	f	10 years	Zimbabwe
5	Transit Visas	f	f	7 years	Zimbabwe
6	Family and Dependent Visas	t	f	10 years	Zimbabwe
7	Immigrant Visas	t	t	6 years	Zimbabwe
8	Refugee and Asylum Visas	t	f	6 years	Zimbabwe
9	Special Purpose Visas	t	f	9 years	Zimbabwe
1	Tourist Visas	f	f	7 years	USA
2	Business Visas	t	f	10 years	USA
3	Work Visas	t	f	9 years	USA
4	Student Visas	t	f	7 years	USA
5	Transit Visas	f	f	5 years	USA
6	Family and Dependent Visas	t	f	10 years	USA
7	Immigrant Visas	t	t	7 years	USA
8	Refugee and Asylum Visas	t	f	10 years	USA
9	Special Purpose Visas	t	f	8 years	USA
\.


--
-- Data for Name: visas; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visas (id, type, passport, issue_date, inner_issuer, country) FROM stdin;
1	3	1	2008-11-04	655	Liberia
2	5	2	1978-02-13	453	Kiribati
3	5	3	1984-01-10	1194	Honduras
4	8	4	1954-04-27	21	Kiribati
5	2	5	1958-05-05	568	Finland
6	5	6	1960-06-26	844	Chile
7	8	7	1954-02-25	405	Gambia
8	7	8	1932-05-22	24	Syria
9	3	9	1934-08-01	296	Montserrat
10	7	10	1934-01-06	278	Angola
11	4	11	1931-05-01	565	Nauru
12	9	12	1931-06-14	945	Azerbaijan
13	5	13	1929-06-09	131	Laos
14	9	14	1934-03-14	452	Hungary
15	8	15	1931-08-12	736	Kenya
16	5	16	1908-04-09	524	Mexico
17	9	17	1906-10-07	90	Laos
18	7	18	1909-08-09	969	Gabon
19	2	19	1909-11-14	454	Kyrgyzstan
20	9	20	1905-05-02	1021	Turkey
21	8	21	1904-04-11	288	Latvia
22	8	22	1905-05-19	79	Israel
23	9	23	1905-05-25	650	Haiti
24	1	24	1908-09-24	600	Albania
25	1	25	1909-03-23	736	Ireland
26	7	26	1909-12-10	1087	Poland
27	3	27	1910-08-04	29	Bermuda
28	3	28	1908-07-02	130	Sudan
29	2	29	1903-01-10	523	Singapore
30	2	30	1907-08-23	547	Romania
31	2	31	1906-06-17	267	Austria
32	2	32	1882-06-18	905	Gabon
33	4	33	1881-03-28	1218	Pitcairn
34	4	34	1884-01-18	235	Comoros
35	8	35	1880-03-21	23	Philippines
36	5	36	1881-08-05	707	Austria
37	3	37	1881-02-18	663	Nicaragua
38	8	38	1879-06-15	692	Zambia
39	3	39	1886-08-18	1099	Montserrat
40	2	40	1881-02-11	853	Oman
41	4	41	1884-03-10	1103	Somalia
42	4	42	1884-03-09	885	Belize
43	7	43	1880-03-27	794	Libya
44	7	44	1880-08-18	130	Maldives
45	3	45	1884-07-05	879	Mali
46	2	46	1880-02-06	1171	Brazil
47	3	47	1885-06-04	387	Syria
48	6	48	1883-06-27	44	Jamaica
49	7	49	1881-04-07	573	Macedonia
50	7	50	1881-04-26	724	Kiribati
51	8	51	1881-02-02	1099	Moldova
52	9	52	1883-03-27	520	Monaco
53	7	53	1882-02-18	979	Gambia
54	7	54	1886-02-11	351	Montserrat
55	2	55	1881-12-17	132	Nauru
56	1	56	1886-07-02	194	Georgia
57	1	57	1878-06-05	47	Cameroon
58	1	58	1882-12-18	546	Cambodia
59	2	59	1878-07-01	485	Iraq
60	1	60	1881-05-05	486	Angola
61	9	61	1883-07-01	1058	Serbia
62	4	62	1880-05-18	1196	Oman
63	6	63	1881-07-21	546	Austria
64	3	64	1855-10-03	961	Liberia
65	6	65	1854-02-08	1142	Cambodia
66	2	66	1861-10-07	93	Dominica
67	3	67	1855-06-06	853	Morocco
68	1	68	1859-09-05	500	Bangladesh
69	7	69	1857-03-13	258	Croatia
70	1	70	1857-03-28	1044	Uganda
71	8	71	1854-01-08	679	Greenland
72	8	72	1854-08-27	1212	Canada
73	1	73	1853-05-17	788	Tuvalu
74	8	74	1857-02-20	824	Mauritania
75	4	75	1859-12-28	347	Algeria
76	8	76	1857-11-01	378	Mexico
77	8	77	1859-11-17	580	Eritrea
78	2	78	1857-07-09	641	Netherlands
79	2	79	1860-02-15	1075	Kyrgyzstan
80	6	80	1857-09-24	461	Cyprus
81	3	81	1859-03-12	457	Martinique
82	9	82	1857-04-20	1027	Martinique
83	5	83	1855-06-18	459	Djibouti
84	5	84	1859-02-03	980	Bahrain
85	5	85	1858-08-04	231	Lebanon
86	5	86	1857-04-16	817	Switzerland
87	7	87	1855-03-15	1023	Portugal
88	5	88	1857-06-02	276	Finland
89	8	89	1853-06-01	974	Botswana
90	8	90	1858-01-16	743	Macedonia
91	9	91	1858-10-16	417	Colombia
92	3	92	1856-07-21	187	Somalia
93	1	93	1856-02-27	399	Venezuela
94	1	94	1858-11-04	1154	Norway
95	6	95	1855-12-03	779	Bolivia
96	1	96	1857-03-24	1170	Gibraltar
97	9	97	1857-07-23	499	Sweden
98	6	98	1855-07-02	1034	France
99	2	99	1854-09-11	877	Sweden
100	2	100	1856-04-27	36	Botswana
101	5	101	1857-04-14	49	Hungary
102	6	102	1859-05-09	833	Yemen
103	2	103	1857-12-23	1018	Portugal
104	6	104	1857-03-19	899	Brazil
105	4	105	1853-09-02	1056	Niger
106	9	106	1855-08-15	214	Maldives
107	7	107	1856-02-11	581	Slovakia
108	5	108	1860-04-10	1009	Venezuela
109	3	109	1853-08-11	399	Mauritius
110	2	110	1858-02-14	773	Oman
111	8	111	1854-04-16	544	Maldives
112	5	112	1856-05-14	1212	Pakistan
113	5	113	1858-03-21	602	Panama
114	5	114	1861-03-11	679	Barbados
115	2	115	1857-11-19	1232	Chile
116	8	116	1856-05-05	742	Madagascar
117	4	117	1855-05-25	748	Bangladesh
118	9	118	1860-04-26	359	Maldives
119	8	119	1860-05-26	108	Dominica
120	9	120	1856-12-17	86	China
121	1	121	1854-12-08	376	Uzbekistan
122	2	122	1859-06-01	241	Guinea
123	8	123	1861-12-09	929	Aruba
124	3	124	1854-04-02	529	Ethiopia
125	9	125	1854-07-21	434	Syria
126	4	126	1857-07-09	165	Albania
127	9	127	1855-04-05	411	Jamaica
128	2	128	1830-12-26	469	Brazil
129	7	129	1835-05-22	805	Guatemala
130	5	130	1829-05-01	327	Djibouti
131	9	131	1831-07-21	399	Yemen
132	9	132	1835-02-26	97	Yemen
133	6	133	1831-04-10	1089	Tajikistan
134	2	134	1832-02-08	696	Italy
135	8	135	1829-05-27	786	Sudan
136	8	136	1828-06-27	762	Benin
137	3	137	1832-03-12	748	Ghana
138	9	138	1829-12-10	964	Tanzania
139	4	139	1835-11-24	583	India
140	3	140	1835-04-05	454	Egypt
141	9	141	1828-10-24	202	Niger
142	6	142	1832-02-19	1125	Bulgaria
143	2	143	1830-09-08	291	Laos
144	6	144	1836-06-07	809	Haiti
145	5	145	1831-12-07	875	Paraguay
146	6	146	1834-08-25	478	Latvia
147	9	147	1833-08-22	127	Bahrain
148	4	148	1833-11-11	1048	Gabon
149	3	149	1833-03-01	650	Mauritius
150	2	150	1829-07-11	44	Sudan
151	3	151	1828-09-11	6	Samoa
152	2	152	1831-01-06	536	Malaysia
153	2	153	1835-09-11	146	Curacao
154	8	154	1829-10-21	153	Macao
155	5	155	1829-02-10	1054	Kiribati
156	6	156	1833-02-18	779	Lebanon
157	4	157	1834-08-12	1234	Tunisia
158	1	158	1830-10-16	214	Gibraltar
159	9	159	1830-12-01	350	Cyprus
160	7	160	1831-01-13	1089	Poland
161	3	161	1833-02-18	301	Kyrgyzstan
162	2	162	1832-10-07	1103	Bermuda
163	5	163	1836-03-28	342	Turkey
164	2	164	1832-11-08	257	Mexico
165	2	165	1829-04-14	394	Bahamas
166	7	166	1831-04-18	82	Barbados
167	3	167	1832-05-19	465	Guatemala
168	1	168	1828-03-08	1105	Namibia
169	6	169	1833-02-23	342	Germany
170	9	170	1834-10-06	325	Martinique
171	5	171	1829-09-06	582	Botswana
172	4	172	1830-07-18	592	Liechtenstein
173	9	173	1828-08-15	308	Kiribati
174	6	174	1829-03-26	1144	Jamaica
175	3	175	1829-07-18	1140	Malta
176	8	176	1833-03-24	969	Bhutan
177	2	177	1834-07-04	1106	Denmark
178	4	178	1832-09-21	144	Mali
179	7	179	1832-07-13	899	Nauru
180	7	180	1830-01-09	765	Macao
181	6	181	1832-02-10	465	Jamaica
182	7	182	1834-12-24	1074	Tajikistan
183	2	183	1832-03-20	14	Slovenia
184	7	184	1829-02-08	1121	Guyana
185	1	185	1834-02-16	404	Martinique
186	5	186	1830-01-20	1095	Laos
187	6	187	1830-02-03	594	Italy
188	4	188	1831-03-28	498	Ethiopia
189	4	189	1828-11-12	805	Libya
190	4	190	1829-07-11	1101	Portugal
191	4	191	1828-03-16	308	Madagascar
192	8	192	1831-01-11	734	Ecuador
193	9	193	1832-01-05	756	Zambia
194	2	194	1831-05-12	349	Guinea
195	3	195	1831-10-13	902	Mozambique
196	3	196	1830-04-28	1194	Bahrain
197	3	197	1835-07-13	961	Slovenia
198	3	198	1835-01-13	954	Burundi
199	4	199	1830-07-27	411	Guatemala
200	7	200	1834-01-12	962	Barbados
201	1	201	1828-05-17	87	Brunei
202	9	202	1829-02-25	764	Bolivia
203	2	203	1833-11-27	258	Cuba
204	2	204	1830-01-19	584	Comoros
205	7	205	1833-09-20	965	Somalia
206	7	206	1829-09-27	920	Ethiopia
207	3	207	1835-12-16	911	Italy
208	3	208	1834-12-14	489	Finland
209	1	209	1835-01-04	1111	Turkmenistan
210	3	210	1831-04-16	1230	Cameroon
211	4	211	1836-06-26	1043	Malaysia
212	2	212	1836-01-10	671	Afghanistan
213	3	213	1832-02-23	235	Liberia
214	8	214	1832-05-16	93	Senegal
215	2	215	1834-03-11	1208	Paraguay
216	3	216	1833-06-07	481	Malaysia
217	4	217	1834-11-08	335	Ukraine
218	5	218	1833-07-16	430	Suriname
219	8	219	1835-12-12	882	Iceland
220	4	220	1833-04-16	404	Slovenia
221	6	221	1830-10-09	577	Ukraine
222	7	222	1831-07-11	1008	Lebanon
223	7	223	1833-11-14	1082	Gambia
224	6	224	1830-09-05	840	Bangladesh
225	2	225	1830-03-16	7	Nauru
226	7	226	1833-04-18	740	Ghana
227	3	227	1829-12-11	556	Swaziland
228	6	228	1830-03-10	993	Turkmenistan
229	1	229	1835-10-21	608	Monaco
230	4	230	1830-02-27	803	Togo
231	8	231	1834-01-23	187	Latvia
232	3	232	1830-08-25	742	Germany
233	8	233	1833-07-27	700	Cameroon
234	6	234	1828-06-02	875	Tanzania
235	4	235	1830-05-23	1050	Algeria
236	4	236	1834-12-06	693	Maldives
237	8	237	1830-06-25	383	Fiji
238	6	238	1831-12-11	917	Brunei
239	5	239	1831-05-03	573	Italy
240	2	240	1828-10-08	973	France
241	1	241	1833-09-11	249	Cameroon
242	8	242	1828-08-24	1158	Uruguay
243	5	243	1831-08-15	210	Portugal
244	1	244	1830-06-16	336	Mauritius
245	5	245	1831-04-11	582	Maldives
246	2	246	1833-12-27	26	Djibouti
247	8	247	1831-12-23	789	Tuvalu
248	6	248	1836-10-23	174	Afghanistan
249	2	249	1835-09-27	798	Brazil
250	8	250	1830-03-22	1076	Argentina
251	5	251	1830-09-11	965	Slovenia
252	9	252	1834-05-02	137	Iran
253	3	253	1833-02-03	1144	Liechtenstein
254	8	254	1831-12-03	705	Lesotho
255	1	255	1834-02-26	565	Kenya
256	1	256	1805-10-25	43	Cuba
257	8	257	1809-09-11	570	Aruba
258	7	258	1807-05-04	239	Cambodia
259	3	259	1807-09-02	879	Madagascar
260	6	260	1805-12-24	372	Taiwan
261	7	261	1811-01-20	724	Malta
262	4	262	1810-02-19	378	Maldives
263	7	263	1804-11-22	18	Curacao
264	9	264	1805-01-21	934	Gibraltar
265	5	265	1804-05-01	1082	Iceland
266	1	266	1804-12-10	652	Seychelles
267	7	267	1807-12-12	519	Chile
268	6	268	1804-11-24	966	Azerbaijan
269	6	269	1807-05-13	132	Macao
270	7	270	1807-12-19	1098	Liechtenstein
271	8	271	1809-12-11	318	Cameroon
272	8	272	1809-01-28	584	Thailand
273	3	273	1809-10-09	592	Colombia
274	7	274	1811-01-10	1187	Aruba
275	3	275	1806-08-05	438	Tajikistan
276	1	276	1808-06-25	488	Algeria
277	2	277	1806-03-01	742	Kyrgyzstan
278	8	278	1807-02-10	1085	Turkey
279	9	279	1805-03-23	727	Nicaragua
280	8	280	1808-10-03	591	Moldova
281	5	281	1806-11-05	842	Uruguay
282	8	282	1809-05-20	394	Togo
283	8	283	1805-11-19	845	Oman
284	8	284	1810-11-26	446	Argentina
285	9	285	1809-01-15	358	Denmark
286	6	286	1807-11-10	301	Dominica
287	9	287	1811-02-23	1211	Mayotte
288	3	288	1804-03-06	1206	Rwanda
289	8	289	1805-10-17	1151	Algeria
290	3	290	1809-05-23	221	Bolivia
291	4	291	1808-02-15	117	Russia
292	6	292	1810-12-14	127	Uganda
293	1	293	1808-04-15	686	Bhutan
294	4	294	1807-08-11	13	Lebanon
295	1	295	1809-06-26	842	Martinique
296	7	296	1804-05-14	965	Armenia
297	4	297	1809-01-20	147	Nicaragua
298	3	298	1806-04-14	36	Australia
299	1	299	1811-01-21	1052	Colombia
300	1	300	1806-11-22	800	Kiribati
301	6	301	1805-06-12	966	Bulgaria
302	1	302	1807-07-15	230	Mali
303	8	303	1803-01-13	781	Italy
304	3	304	1808-01-08	817	Laos
305	1	305	1805-12-05	1248	Brunei
306	1	306	1808-06-01	1218	Morocco
307	5	307	1806-10-03	1018	Sweden
308	6	308	1805-04-03	205	Ghana
309	8	309	1806-09-22	524	Macedonia
310	7	310	1805-04-06	578	Tanzania
311	9	311	1806-10-10	1154	Malawi
312	3	312	1806-09-20	1076	Chile
313	2	313	1807-05-17	789	Seychelles
314	4	314	1811-12-24	1105	Sweden
315	4	315	1808-12-23	697	Bolivia
316	3	316	1808-08-23	51	Indonesia
317	4	317	1805-02-13	758	Benin
318	6	318	1809-05-21	393	Sudan
319	1	319	1806-05-12	546	Slovakia
320	9	320	1808-09-25	713	Indonesia
321	1	321	1804-05-06	596	Croatia
322	3	322	1807-02-06	798	Jordan
323	8	323	1809-07-09	710	Uganda
324	3	324	1809-07-04	429	Cameroon
325	4	325	1807-05-20	226	Liberia
326	8	326	1807-10-15	824	Haiti
327	8	327	1807-01-11	474	Liberia
328	4	328	1804-05-01	442	Benin
329	3	329	1803-08-11	234	Venezuela
330	4	330	1803-01-19	595	Thailand
331	7	331	1809-02-24	482	Swaziland
332	8	332	1805-06-04	1203	USA
333	8	333	1804-09-10	752	Bahrain
334	9	334	1805-12-01	3	Argentina
335	5	335	1805-11-25	966	Slovakia
336	5	336	1809-06-06	776	Kazakhstan
337	2	337	1807-02-27	954	Barbados
338	3	338	1807-10-18	38	Bermuda
339	6	339	1808-10-10	185	Uruguay
340	6	340	1806-03-21	1195	Senegal
341	7	341	1805-10-12	613	Pitcairn
342	7	342	1810-11-07	829	Hungary
343	3	343	1804-03-18	1181	Uganda
344	5	344	1803-05-23	39	Honduras
345	1	345	1808-06-25	862	Egypt
346	1	346	1809-04-05	554	Austria
347	9	347	1804-11-05	49	Philippines
348	3	348	1808-12-10	36	Montenegro
349	4	349	1809-11-27	394	Mauritius
350	6	350	1809-10-10	818	Latvia
351	1	351	1806-06-22	677	Uzbekistan
352	4	352	1805-11-20	221	Senegal
353	3	353	1805-04-06	204	Bahamas
354	1	354	1807-03-03	9	Lebanon
355	3	355	1807-07-01	657	Myanmar
356	9	356	1808-09-08	781	Niue
357	5	357	1804-04-10	498	Poland
358	2	358	1805-09-16	779	Austria
359	3	359	1809-01-25	348	Morocco
360	7	360	1809-12-23	596	Mozambique
361	5	361	1807-01-23	461	Egypt
362	4	362	1808-12-05	610	Luxembourg
363	6	363	1811-04-28	659	Yemen
364	7	364	1809-11-23	648	Nauru
365	8	365	1810-08-06	740	Pitcairn
366	3	366	1805-11-02	568	Niger
367	3	367	1806-06-03	642	Lithuania
368	3	368	1804-02-20	715	Germany
369	2	369	1805-06-10	550	Martinique
370	3	370	1805-02-06	127	Namibia
371	5	371	1805-12-24	21	Iceland
372	7	372	1807-08-17	798	Botswana
373	4	373	1808-09-02	1183	Honduras
374	1	374	1810-10-18	1207	Kenya
375	5	375	1804-06-28	901	Macedonia
376	8	376	1805-05-02	1248	Armenia
377	2	377	1809-11-27	423	Iran
378	2	378	1803-12-15	493	Sudan
379	4	379	1810-07-17	729	Nicaragua
380	1	380	1803-09-11	602	Denmark
381	9	381	1809-05-28	738	Estonia
382	7	382	1809-05-08	293	Germany
383	8	383	1805-01-15	1098	Peru
384	1	384	1805-09-20	823	Haiti
385	5	385	1806-06-27	348	Azerbaijan
386	7	386	1808-07-07	1101	Djibouti
387	7	387	1809-09-04	785	Egypt
388	8	388	1806-10-13	176	Gibraltar
389	3	389	1804-06-17	742	Japan
390	1	390	1807-06-06	36	Iceland
391	6	391	1808-04-09	954	Panama
392	3	392	1806-05-08	844	Poland
393	2	393	1808-08-18	898	Lebanon
394	7	394	1807-03-05	596	Poland
395	9	395	1807-06-19	390	Suriname
396	7	396	1809-10-18	821	Bahamas
397	3	397	1809-12-26	668	Cameroon
398	9	398	1805-06-27	137	Comoros
399	5	399	1809-06-06	637	Chile
400	5	400	1807-01-05	118	Chad
401	8	401	1809-05-11	802	Maldives
402	1	402	1808-01-02	37	Laos
403	2	403	1810-01-06	920	Seychelles
404	8	404	1806-11-21	25	Guyana
405	9	405	1804-05-17	496	Nigeria
406	8	406	1806-04-04	1150	Slovakia
407	3	407	1804-06-04	561	Cyprus
408	9	408	1811-04-10	39	Macao
409	2	409	1804-03-08	249	Malaysia
410	5	410	1806-10-07	664	Liechtenstein
411	3	411	1809-12-06	99	Mauritius
412	8	412	1805-02-18	244	Samoa
413	6	413	1808-10-16	481	Kosovo
414	6	414	1811-03-11	862	Rwanda
415	9	415	1804-09-14	56	Libya
416	5	416	1807-10-13	155	Niger
417	5	417	1806-07-07	608	Guatemala
418	2	418	1806-02-21	72	Liechtenstein
419	8	419	1811-05-16	778	Colombia
420	1	420	1808-11-03	735	Ecuador
421	3	421	1810-07-09	25	Moldova
422	7	422	1805-05-25	1051	Colombia
423	3	423	1807-03-03	52	Mexico
424	8	424	1807-04-05	855	Taiwan
425	7	425	1808-03-27	637	Bangladesh
426	4	426	1804-08-11	485	Venezuela
427	6	427	1806-01-12	1050	Cambodia
428	9	428	1809-04-20	645	Niue
429	1	429	1808-02-16	247	Netherlands
430	1	430	1809-01-15	3	Ecuador
431	7	431	1809-05-06	578	Chile
432	3	432	1803-06-23	646	Niger
433	3	433	1808-12-17	137	Uganda
434	5	434	1808-11-28	734	Peru
435	8	435	1809-11-13	768	Mozambique
436	2	436	1808-07-09	1183	Montserrat
437	5	437	1806-10-10	592	Belarus
438	8	438	1806-03-14	644	Ethiopia
439	1	439	1809-08-01	821	Australia
440	7	440	1805-05-07	6	Colombia
441	2	441	1805-02-25	963	Niger
442	1	442	1806-07-20	650	Greenland
443	2	443	1804-07-27	1120	Singapore
444	1	444	1807-04-11	488	Sweden
445	2	445	1806-05-17	425	Mayotte
446	3	446	1809-03-21	90	Bahamas
447	6	447	1806-12-27	582	Honduras
448	9	448	1811-03-22	1103	Maldives
449	6	449	1809-02-27	306	Mexico
450	1	450	1806-02-02	153	Belize
451	2	451	1810-04-08	203	Germany
452	1	452	1808-08-19	869	Venezuela
453	2	453	1805-07-12	137	Chad
454	6	454	1810-01-11	496	Canada
455	8	455	1807-08-10	846	Finland
456	2	456	1804-09-22	542	Nauru
457	6	457	1807-11-04	742	Fiji
458	6	458	1807-10-09	311	Panama
459	9	459	1809-04-20	940	Tunisia
460	2	460	1806-04-07	306	Colombia
461	2	461	1810-04-02	880	Kiribati
462	3	462	1809-12-18	1006	Angola
463	1	463	1811-08-14	849	Portugal
464	2	464	1809-12-06	498	Bulgaria
465	1	465	1804-07-20	846	Martinique
466	4	466	1805-05-23	590	Gambia
467	5	467	1804-12-19	223	Gibraltar
468	6	468	1806-07-12	127	Spain
469	8	469	1807-10-11	519	Samoa
470	8	470	1808-10-11	86	Colombia
471	9	471	1808-05-27	91	Tanzania
472	2	472	1807-09-02	56	Liechtenstein
473	1	473	1806-04-20	227	Philippines
474	3	474	1804-09-22	1074	Montserrat
475	8	475	1803-07-23	142	Liechtenstein
476	6	476	1809-03-21	357	Peru
477	2	477	1808-04-05	176	Fiji
478	6	478	1804-04-19	86	Ghana
479	9	479	1804-07-16	547	Russia
480	2	480	1809-12-25	570	Jordan
481	6	481	1809-06-01	425	Thailand
482	3	482	1804-03-19	504	Mexico
483	1	483	1809-10-24	354	Palau
484	5	484	1809-11-27	1082	Ethiopia
485	5	485	1807-01-16	21	Qatar
486	3	486	1806-02-14	25	Afghanistan
487	7	487	1808-08-23	1193	Malaysia
488	1	488	1806-09-06	461	Belize
489	4	489	1803-08-09	1097	Algeria
490	8	490	1811-05-26	481	Bermuda
491	8	491	1810-12-25	920	USA
492	9	492	1804-09-05	298	Djibouti
493	4	493	1805-09-17	619	Tajikistan
494	2	494	1809-08-07	119	Chad
495	1	495	1804-03-24	500	Niue
496	3	496	1809-02-22	226	USA
497	9	497	1809-12-18	586	Chile
498	8	498	1808-04-13	486	Cameroon
499	4	499	1810-04-14	1018	Belarus
500	9	500	1804-03-07	1160	Germany
\.


--
-- Name: educational_certificates_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.educational_certificates_types_id_seq', 1, false);


--
-- Name: accounts pk_accounts; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT pk_accounts PRIMARY KEY (id);


--
-- Name: administrators pk_administrators; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT pk_administrators PRIMARY KEY (user_id, office_id);


--
-- Name: pet_passports pk_animal_passports; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT pk_animal_passports PRIMARY KEY (id);


--
-- Name: birth_certificates pk_birth_certificate; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT pk_birth_certificate PRIMARY KEY (id);


--
-- Name: cities pk_cities; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT pk_cities PRIMARY KEY (id);


--
-- Name: countries pk_countries; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT pk_countries PRIMARY KEY (id);


--
-- Name: death_certificates pk_death_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT pk_death_certificates PRIMARY KEY (id);


--
-- Name: divorce_certificates pk_divorce_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT pk_divorce_certificates PRIMARY KEY (id);


--
-- Name: divorces pk_divorces; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT pk_divorces PRIMARY KEY (id);


--
-- Name: document_types pk_document_types; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.document_types
    ADD CONSTRAINT pk_document_types PRIMARY KEY (id);


--
-- Name: drivers_licences pk_drivers_licence; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT pk_drivers_licence PRIMARY KEY (id);


--
-- Name: educational_certificates pk_educational_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT pk_educational_certificates PRIMARY KEY (id);


--
-- Name: educational_certificates_types pk_educational_certificates_types; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates_types
    ADD CONSTRAINT pk_educational_certificates_types PRIMARY KEY (id);


--
-- Name: educational_instances pk_educational_instances; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances
    ADD CONSTRAINT pk_educational_instances PRIMARY KEY (id);


--
-- Name: educational_instances_types_relation pk_educational_instances_types_relation; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances_types_relation
    ADD CONSTRAINT pk_educational_instances_types_relation PRIMARY KEY (instance_id, type_id);


--
-- Name: passports pk_id_cards; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT pk_id_cards PRIMARY KEY (id);


--
-- Name: international_passports pk_international_passports; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT pk_international_passports PRIMARY KEY (id);


--
-- Name: marriages pk_marriage_certificates; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT pk_marriage_certificates PRIMARY KEY (id);


--
-- Name: marriage_certificates pk_marriage_certificates_0; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT pk_marriage_certificates_0 PRIMARY KEY (id);


--
-- Name: office_kinds_documents pk_office_kinds_documents; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.office_kinds_documents
    ADD CONSTRAINT pk_office_kinds_documents PRIMARY KEY (document_id, kind_id);


--
-- Name: offices pk_offices; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT pk_offices PRIMARY KEY (id);


--
-- Name: offices_kinds pk_offices_kinds; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds
    ADD CONSTRAINT pk_offices_kinds PRIMARY KEY (kind);


--
-- Name: offices_kinds_relations pk_offices_kinds_relations; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT pk_offices_kinds_relations PRIMARY KEY (office_id, kind_id);


--
-- Name: people pk_users; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT pk_users PRIMARY KEY (id);


--
-- Name: visa_categories pk_visa_categories; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visa_categories
    ADD CONSTRAINT pk_visa_categories PRIMARY KEY (type, country);


--
-- Name: visas pk_visas; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT pk_visas PRIMARY KEY (id);


--
-- Name: cities unq_cities_country_city; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT unq_cities_country_city UNIQUE (country, city);


--
-- Name: countries unq_countries_country; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT unq_countries_country UNIQUE (country);


--
-- Name: divorces unq_divorces_marriage_id; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT unq_divorces_marriage_id UNIQUE (marriage_id);


--
-- Name: educational_certificates_types unq_educational_certificates_types_kind; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates_types
    ADD CONSTRAINT unq_educational_certificates_types_kind UNIQUE (name);


--
-- Name: divorce_certificates_view insert_divorce_certificates; Type: RULE; Schema: public; Owner: admin
--

CREATE RULE insert_divorce_certificates AS
    ON INSERT TO public.divorce_certificates_view DO INSTEAD  INSERT INTO public.divorce_certificates (divorce_id, issuer, issue_date)
  VALUES (( SELECT divorces.id
           FROM public.divorces
          WHERE (divorces.marriage_id = new."Marriage ID")), new."Issuer", now());


--
-- Name: educational_certificates_view insert_educational_certificates; Type: RULE; Schema: public; Owner: admin
--

CREATE RULE insert_educational_certificates AS
    ON INSERT TO public.educational_certificates_view DO INSTEAD  INSERT INTO public.educational_certificates (holder, kind, issuer, issue_date)
  VALUES (new.holder, ( SELECT educational_certificates_types.id
           FROM public.educational_certificates_types
          WHERE ((educational_certificates_types.name)::text = (new."Level of Education")::text)), ( SELECT educational_instances.id
           FROM public.educational_instances
          WHERE ((educational_instances.name)::text = (new."Issuer Instance")::text)), now());


--
-- Name: educational_certificates_types check_for_cycle; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER check_for_cycle BEFORE INSERT OR UPDATE ON public.educational_certificates_types FOR EACH ROW EXECUTE FUNCTION public.check_for_cycle();


--
-- Name: birth_certificates verify_birth_certificate_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_birth_certificate_issue_date BEFORE INSERT ON public.birth_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: birth_certificates verify_birth_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_birth_certificate_issuer BEFORE INSERT ON public.birth_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_birth_certificate_issuer();


--
-- Name: birth_certificates verify_birth_certificate_parents; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_birth_certificate_parents BEFORE INSERT ON public.birth_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_birth_certificate_parents();


--
-- Name: birth_certificates verify_birth_certificate_parents_cycle; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_birth_certificate_parents_cycle BEFORE INSERT ON public.birth_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_birth_certificate_parents_cycle();


--
-- Name: death_certificates verify_death_certificate_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_death_certificate_issue_date BEFORE INSERT ON public.death_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: death_certificates verify_death_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_death_certificate_issuer BEFORE INSERT ON public.death_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_death_certificate_issuer();


--
-- Name: divorce_certificates verify_divorce_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_certificate_date BEFORE INSERT ON public.divorce_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_certificate_date();


--
-- Name: divorce_certificates verify_divorce_certificate_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_certificate_issue_date BEFORE INSERT ON public.divorce_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: divorce_certificates verify_divorce_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_certificate_issuer BEFORE INSERT ON public.divorce_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_certificate_issuer();


--
-- Name: divorces verify_divorce_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_date BEFORE INSERT ON public.divorces FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_date();


--
-- Name: divorces verify_divorce_unique; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_unique BEFORE INSERT ON public.divorces FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_unique();


--
-- Name: drivers_licences verify_driver_license_age; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_driver_license_age BEFORE INSERT ON public.drivers_licences FOR EACH ROW EXECUTE FUNCTION public.verify_driver_license_age();


--
-- Name: drivers_licences verify_driver_license_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_driver_license_issuer BEFORE INSERT ON public.drivers_licences FOR EACH ROW EXECUTE FUNCTION public.verify_driver_license_issuer();


--
-- Name: drivers_licences verify_drivers_licence_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_drivers_licence_issue_date BEFORE INSERT ON public.drivers_licences FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: educational_certificates verify_educational_certificate_birth_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_birth_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_birth_date();


--
-- Name: educational_certificates verify_educational_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_date();


--
-- Name: educational_certificates verify_educational_certificate_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_death_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_death_date();


--
-- Name: educational_certificates verify_educational_certificate_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_issue_date BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: educational_certificates verify_educational_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_issuer BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_issuer();


--
-- Name: educational_certificates verify_educational_certificate_kind; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_kind BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_kind();


--
-- Name: educational_certificates verify_educational_certificate_prerequisites; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_educational_certificate_prerequisites BEFORE INSERT ON public.educational_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_educational_certificate_prerequisites();


--
-- Name: international_passports verify_international_passport_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_international_passport_issue_date BEFORE INSERT ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: international_passports verify_international_passport_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_international_passport_issuer BEFORE INSERT ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_international_passport_issuer();


--
-- Name: international_passports verify_international_passport_number; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_international_passport_number BEFORE INSERT ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_international_passport_number();


--
-- Name: marriage_certificates verify_marriage_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_certificate_date BEFORE INSERT ON public.marriage_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_marriage_certificate_date();


--
-- Name: marriage_certificates verify_marriage_certificate_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_certificate_issue_date BEFORE INSERT ON public.marriage_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: marriage_certificates verify_marriage_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_certificate_issuer BEFORE INSERT ON public.marriage_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_marriage_certificate_issuer();


--
-- Name: marriages verify_marriage_unique; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_marriage_unique BEFORE INSERT ON public.marriages FOR EACH ROW EXECUTE FUNCTION public.verify_marriage_unique();


--
-- Name: international_passports verify_passport_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_death_date BEFORE UPDATE ON public.international_passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_death_date();


--
-- Name: passports verify_passport_death_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_death_date BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_death_date();


--
-- Name: passports verify_passport_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_issue_date BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: passports verify_passport_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_issuer BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_issuer();


--
-- Name: passports verify_passport_number; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_number BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_number();


--
-- Name: visas verify_visa_issue_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_visa_issue_date BEFORE INSERT ON public.visas FOR EACH ROW EXECUTE FUNCTION public.verify_certificate_issue_date();


--
-- Name: visas verify_visa_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_visa_issuer BEFORE INSERT ON public.visas FOR EACH ROW EXECUTE FUNCTION public.verify_visa_issuer();


--
-- Name: accounts fk_accounts_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_accounts_people FOREIGN KEY (id) REFERENCES public.people(id);


--
-- Name: administrators fk_administrators_accounts; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT fk_administrators_accounts FOREIGN KEY (user_id) REFERENCES public.accounts(id);


--
-- Name: administrators fk_administrators_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.administrators
    ADD CONSTRAINT fk_administrators_offices FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: birth_certificates fk_birth_certificate_people_father; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificate_people_father FOREIGN KEY (father) REFERENCES public.people(id);


--
-- Name: birth_certificates fk_birth_certificate_people_mother; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificate_people_mother FOREIGN KEY (mother) REFERENCES public.people(id);


--
-- Name: birth_certificates fk_birth_certificates_cities; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificates_cities FOREIGN KEY (city_of_birth, country_of_birth) REFERENCES public.cities(city, country);


--
-- Name: birth_certificates fk_birth_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.birth_certificates
    ADD CONSTRAINT fk_birth_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: cities fk_cities_countries; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT fk_cities_countries FOREIGN KEY (country) REFERENCES public.countries(country);


--
-- Name: death_certificates fk_death_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT fk_death_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: death_certificates fk_death_certificates_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.death_certificates
    ADD CONSTRAINT fk_death_certificates_people FOREIGN KEY (person) REFERENCES public.people(id);


--
-- Name: divorce_certificates fk_divorce_certificates_marriage; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT fk_divorce_certificates_marriage FOREIGN KEY (divorce_id) REFERENCES public.divorces(id);


--
-- Name: divorce_certificates fk_divorce_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorce_certificates
    ADD CONSTRAINT fk_divorce_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: divorces fk_divorces_marriage; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.divorces
    ADD CONSTRAINT fk_divorces_marriage FOREIGN KEY (marriage_id) REFERENCES public.marriages(id);


--
-- Name: drivers_licences fk_drivers_licences_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT fk_drivers_licences_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: drivers_licences fk_drivers_licences_people; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.drivers_licences
    ADD CONSTRAINT fk_drivers_licences_people FOREIGN KEY (person) REFERENCES public.people(id);


--
-- Name: educational_certificates fk_educational_certificates_educational_certificates_types; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_educational_certificates_types FOREIGN KEY (kind) REFERENCES public.educational_certificates_types(id);


--
-- Name: educational_certificates fk_educational_certificates_holder; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_holder FOREIGN KEY (holder) REFERENCES public.people(id);


--
-- Name: educational_certificates fk_educational_certificates_issuer; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_issuer FOREIGN KEY (issuer) REFERENCES public.educational_instances(id);


--
-- Name: educational_certificates_types fk_educational_certificates_types; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates_types
    ADD CONSTRAINT fk_educational_certificates_types FOREIGN KEY (prerequirement) REFERENCES public.educational_certificates_types(id);


--
-- Name: educational_instances fk_educational_instances; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances
    ADD CONSTRAINT fk_educational_instances FOREIGN KEY (country, city) REFERENCES public.cities(country, city);


--
-- Name: educational_instances_types_relation fk_educational_instances_types_relation_educational_certificate; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances_types_relation
    ADD CONSTRAINT fk_educational_instances_types_relation_educational_certificate FOREIGN KEY (type_id) REFERENCES public.educational_certificates_types(id);


--
-- Name: educational_instances_types_relation fk_educational_instances_types_relation_educational_instances; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_instances_types_relation
    ADD CONSTRAINT fk_educational_instances_types_relation_educational_instances FOREIGN KEY (instance_id) REFERENCES public.educational_instances(id);


--
-- Name: international_passports fk_international_passports_countries; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT fk_international_passports_countries FOREIGN KEY (country) REFERENCES public.countries(country);


--
-- Name: international_passports fk_international_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT fk_international_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: international_passports fk_international_passports_owner; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.international_passports
    ADD CONSTRAINT fk_international_passports_owner FOREIGN KEY (passport_owner) REFERENCES public.people(id);


--
-- Name: marriage_certificates fk_marriage_certificates; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT fk_marriage_certificates FOREIGN KEY (marriage_id) REFERENCES public.marriages(id);


--
-- Name: marriage_certificates fk_marriage_certificates_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriage_certificates
    ADD CONSTRAINT fk_marriage_certificates_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: marriages fk_marriage_certificates_person1; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT fk_marriage_certificates_person1 FOREIGN KEY (person1) REFERENCES public.people(id);


--
-- Name: marriages fk_marriage_certificates_person2; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.marriages
    ADD CONSTRAINT fk_marriage_certificates_person2 FOREIGN KEY (person2) REFERENCES public.people(id);


--
-- Name: office_kinds_documents fk_office_kinds_documents_document_types; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.office_kinds_documents
    ADD CONSTRAINT fk_office_kinds_documents_document_types FOREIGN KEY (document_id) REFERENCES public.document_types(id);


--
-- Name: office_kinds_documents fk_office_kinds_documents_offices_kinds; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.office_kinds_documents
    ADD CONSTRAINT fk_office_kinds_documents_offices_kinds FOREIGN KEY (kind_id) REFERENCES public.offices_kinds(kind);


--
-- Name: offices fk_offices_cities; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT fk_offices_cities FOREIGN KEY (country, city) REFERENCES public.cities(country, city);


--
-- Name: offices_kinds_relations fk_offices_kinds_relations_kind; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT fk_offices_kinds_relations_kind FOREIGN KEY (kind_id) REFERENCES public.offices_kinds(kind);


--
-- Name: offices_kinds_relations fk_offices_kinds_relations_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.offices_kinds_relations
    ADD CONSTRAINT fk_offices_kinds_relations_offices FOREIGN KEY (office_id) REFERENCES public.offices(id);


--
-- Name: passports fk_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT fk_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: passports fk_passports_person; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.passports
    ADD CONSTRAINT fk_passports_person FOREIGN KEY (passport_owner) REFERENCES public.people(id);


--
-- Name: pet_passports fk_pet_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT fk_pet_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


--
-- Name: pet_passports fk_pet_passports_owner; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT fk_pet_passports_owner FOREIGN KEY (pet_owner) REFERENCES public.people(id);


--
-- Name: visa_categories fk_visa_categories_countries; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visa_categories
    ADD CONSTRAINT fk_visa_categories_countries FOREIGN KEY (country) REFERENCES public.countries(country);


--
-- Name: visas fk_visas_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_offices FOREIGN KEY (inner_issuer) REFERENCES public.offices(id);


--
-- Name: visas fk_visas_passport; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_passport FOREIGN KEY (passport) REFERENCES public.international_passports(id);


--
-- Name: visas fk_visas_visa_categories; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.visas
    ADD CONSTRAINT fk_visas_visa_categories FOREIGN KEY (type, country) REFERENCES public.visa_categories(type, country);


--
-- PostgreSQL database dump complete
--

