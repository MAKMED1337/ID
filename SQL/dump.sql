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
 SELECT id,
    divorce_id,
    ( SELECT divorces.marriage_id
           FROM public.divorces
          WHERE (divorces.id = div_cert.divorce_id)) AS marriage_id,
    ( SELECT marriages.person1
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS first_person,
    ( SELECT marriages.person2
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS second_person,
    ( SELECT marriages.marriage_date
           FROM public.marriages
          WHERE (marriages.id = ( SELECT divorces.marriage_id
                   FROM public.divorces
                  WHERE (divorces.id = div_cert.divorce_id)))) AS marriage_date,
    ( SELECT divorces.divorce_date
           FROM public.divorces
          WHERE (divorces.id = div_cert.divorce_id)) AS divorce_date,
    issue_date,
    issuer
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
          WHERE (educational_certificates_types.id = edu_cert.kind)) AS level_of_education,
    ( SELECT educational_instances.name
           FROM public.educational_instances
          WHERE (educational_instances.id = edu_cert.issuer)) AS issuer_instance,
    issue_date AS date_of_issue
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
    lost boolean NOT NULL,
    invalidated boolean NOT NULL,
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
 SELECT id,
    marriage_id,
    ( SELECT marriages.person1
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS first_person,
    ( SELECT marriages.person2
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS second_person,
    ( SELECT marriages.marriage_date
           FROM public.marriages
          WHERE (marriages.id = mar_cert.marriage_id)) AS marriage_date,
    issuer,
    issue_date
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
    lost boolean NOT NULL,
    invalidated boolean NOT NULL,
    CONSTRAINT cns_passports_issue_expiry CHECK ((issue_date < expiration_date)),
    CONSTRAINT cns_passports_sex CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])))
);


ALTER TABLE public.passports OWNER TO admin;

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
-- Name: educational_certificates_types id; Type: DEFAULT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates_types ALTER COLUMN id SET DEFAULT nextval('public.educational_certificates_types_id_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.accounts (id, login, hashed_password) FROM stdin;
1	user1	$2a$06$aIN8.zGAv/01peJcJP9pe.9wwyCUMhXwrGMSHLlmXuJXczJmoCVBW
2	user2	$2a$06$qsLOMrlPVyIzSz37weoeLOvT1G1izQ6yGLQ2Trf1NSeLbLYMK7xRS
3	user3	$2a$06$Pf0qje2ZeqbhQ13/KEZ0RufbJma.JGWa9a2aaG2S9fgDJv33FiL6C
4	user4	$2a$06$wcMvmxZt5HIM4iofjnXahuP/nJ4hkp96V7fJ3e4Ek3nGDeDh5HQIa
5	user5	$2a$06$QSgn4vsT0SHdXg72vsu8Zu9o1XWu.TIlXnB5lWEALLfAEPj9vp/ge
6	user6	$2a$06$CbelF9OCOm9g9FUZsX4rpOghdLyqs1973xhG57YskMEfi5qEVwX9K
7	user7	$2a$06$gPVJ75AixTqR6gJ6otazbOpGcdkq5n2XAOOH5R1MWXVFOK9NRTa0S
8	user8	$2a$06$mVXxAaaTa4SqRcMkUByfwOZdYHcfRRHtjp7n9uB3zAxec4aANIKOK
9	user9	$2a$06$0tH/JlKBEvwlfjfK64UW4ukdQuW7dUSCc7CqT6tdtMqLiGNTCxrPa
10	user10	$2a$06$fDKm5FVSI4T8aEPGBLrHg.1PsuTakmuSdYrwkNHvqn7./RyH/mXKe
11	user11	$2a$06$CXQuSKKaReIMSc4IpaMcZudBQG1F2shhcy9b3u0AZX94YTQ4nKdtO
12	user12	$2a$06$Bv6BkYyMxeGwtmdeOhRzB..Fr8HO6y/KWpty/1D6vWxX.UKIhRGfK
13	user13	$2a$06$1ol3M.0xXuktQcZQQTwG2uBlvsp1DS2.qCVf1WDZLSqhUE./7kz/.
14	user14	$2a$06$9QQAdxa6ZFUHVURJ5pu.IeTAhKK2YFI7oLsJxHEE2NK6rcK.CjGX.
15	user15	$2a$06$uAimk8f6MgmKo/0zEJmHLurJHO1ZeFMFiC1bEgj0ukLsqc.rstSfy
16	user16	$2a$06$2Q5iYDsx48SHXh.b2baEtOlox9juP/n5dpU.VtjdU1q77bXVd45yO
17	user17	$2a$06$sjlj8C4xbvfFTV4PH3Cgcu8M7AjwhXe2PugX.jFrCr90.kuRsWNxa
18	user18	$2a$06$HefIaa8A97JzMVz3.F/4Auxq2SI8HQfVTe6LOB6CO5RYFTJ83fzMW
19	user19	$2a$06$jRafo..2ZvOT1.S7/bXD9O01Vnx0wdaPx9IYUtCo3zdN7CXZnx6Hy
20	user20	$2a$06$PnDXMx7LmYd38kAgvpNKnekLzHI7ZKKl.kYhXb9ItcnpNu4hRJaZG
21	user21	$2a$06$BS.oP.hSieMJlHFKxlJq0eY5SZN0IUFZuNpIUizUiW9XC7tseaAC2
22	user22	$2a$06$ZNsn8s5j.FPkqfbEnHrvd.D/.bM5z9ryjbJ62Z31xmVqc1PB82BFK
23	user23	$2a$06$374vdLvCYCclr6uBFFlmJ.9xKzQg1/dPsxWatCxxszDGzFIHYy/Um
24	user24	$2a$06$Qdyx0I80bq4ATJgKzPQsPucZpJJEQut78rr51/F2A4chKvefVuDni
25	user25	$2a$06$Vd/khzlyVfryMaVC.C1lZO4bDVqAZenFq32xWJ19ohAlkZz8oADfW
26	user26	$2a$06$BmMEMWPXVxXzxVVilNTr/O7Lajs7zznMfahbZhNsQbj1GfnlcStvq
27	user27	$2a$06$ZMMvky4bjtqpNHaKQMgRKeC4hZU.zevyJDRbeKxhTx84hIRgGRjgS
28	user28	$2a$06$9T7GVIZbfn.xUfbYtWWal.ls6gVuELMik2OtVFDqTUhr/GYwTpdmC
29	user29	$2a$06$sJzEkFXqVUYBC6PQEJTyguS6cOU1EGyrB1kq3IVuqonj/OdMLWOk2
30	user30	$2a$06$UdmsOpcRih9cY4kGOYNF9.NY4O3IguCyJ9TdeYfPETBf7YceY0Saa
31	user31	$2a$06$E22vv93YqUZU7Vb0TTrhyuo2TNF1mTq3qQVRu.E/s3D0wtHfhrn9.
32	user32	$2a$06$LqG2pK0C.z3C4MPbGx0CieLWVw6f6wLOt7MhlCP.1eABtJBw4T7BW
33	user33	$2a$06$bi9c5LBUSadt6dm1VIkxBugR1BB6eOxkIXXDbWYar4KAC5iZlF6TG
34	user34	$2a$06$CdKIikEuHN35OU7vrU9LOeCeLn0HmUcbSnOv0CF1ghKtI27E9TWeS
35	user35	$2a$06$hDVS25Pcr3o6TiYv//bZsuYqzreqqQUlIUDT85QboWogwmq.admn2
36	user36	$2a$06$bXxA7qecbHgcyoEvUBCRyetw6vddHoZjhh6x44Ymr1cnJ6rFx0Vb.
37	user37	$2a$06$o9UE7QYN55zA7p6.zj2ztevoygxrnfkWtghL2xHcLI0Am7D13MXem
38	user38	$2a$06$Nu.2KkQGzhEfL8KlJny5GeCI7lszYx20XbYEWc0cMRKxde3NeWRxi
39	user39	$2a$06$2570sKg6Fp8MkK8WTGXi4OdJWHow0ZGerkXSx.SA29S.Y92wNwQNe
40	user40	$2a$06$bhm/ZsniV3NJWoaargVdg.gHn3twz9T5nvj8VNT1dwUdn9XHqyJxG
41	user41	$2a$06$aP7Njwd3cWMnP5dopV1kRuPXTTvia9HXiM4fSiGeKLfL04gjJ/eCm
42	user42	$2a$06$zToBlSYo4bG0hL8/wUd2meUtcuLoL6PZJUOW0jpUV1kjoThoGaTpW
43	user43	$2a$06$tke6PrN2CKV0H93nxcaY3uj/lb2IRz6Iychsz53EhPowQmRSNb7xa
44	user44	$2a$06$C9UrqU1pOur9rlZ0m82HjeoAVYXCTOYJDh2WR4jv381BSKp3T7xX6
45	user45	$2a$06$2IprPCh0NkFW/pvpAv19fe9Xj6kiw4471K5IULhHChyisS.2tutEG
46	user46	$2a$06$fmsNNPu.cneQQsjLpzQINelAdxl2jolAksKCrq80fYEvSUBF8nUTe
47	user47	$2a$06$nKhtlOEdAFEDxDVJkA32KOrme2vfvYF0AhFjLq2hTF4kRuP0seT8u
48	user48	$2a$06$PtLiMo3Lzq3.6iucPu6tuOaOAP3Kv4c5MF9.uS/DT3/Jw.XKe3wFa
49	user49	$2a$06$vEf/1OqpIB.z/.bLDggNB..U0E4c/mQb0T/oCSu4rbhvoknnIzW4.
50	user50	$2a$06$z//CxpUVocpriRu.wcgP.OgwUAy9nIwzu5yurReKyX6EGG/xoOYvS
51	user51	$2a$06$dQfukzpWxiap31prRX1yFu.RCYGD/D4MCbhNHY1bjdAwIZf18vUZW
52	user52	$2a$06$8l4.sQGBb5vrZvOQiHRrieIJXSRyk6poPSuHMOkUWnB.hsTXfuNyy
53	user53	$2a$06$hT67dxPguU9AzM.DericUuVIE/SA9zXfgNEtc6LR1R0b3IUYPkKeO
54	user54	$2a$06$.wIsA25H8W..BHWvQOkOce7CQk/UjwM8SH5p4x/b9yUzaC5mxsZQi
55	user55	$2a$06$qysoJ7ElXh6vPLOcFcVHLe3iBR.wLLna4G8JoX.yTxsWdnmUUh.6K
56	user56	$2a$06$zExJAsdcS9OQhjLf5DVjv.QZYB.M3r9IAQIxAtgeg1pUhqpflRF1q
57	user57	$2a$06$6ftn/aUDJhEJF61C9eR0tuUZozFI2iF5GuVd1ba3iDG3BpKgdCxXK
58	user58	$2a$06$C8TYk8QCp.XFItUEIQZiNeLBUx0vB8r2qE45pCWcVdcJuTikW8LN6
59	user59	$2a$06$0JQ5pSw4HvTzlmdEpfAySOpk.NjfgHodvmGYOvYRN.JjoizbpMBuy
60	user60	$2a$06$mwNmELoQdakxTHG7l2SVz.pmb.kE7sGCNEPF1dQ7h/dl4RJmsHKhe
61	user61	$2a$06$1v9MyGy4F4i/kJkWb6hDtO4nhtGHLn1v1PI2sSpnka2zG26KpV2jC
62	user62	$2a$06$CmYHFmff1C5n6pWKHRF4kuFDvJQK3.k3Qmn6QgzaL3HsCnMjtKwPa
63	user63	$2a$06$HPCXizhAVDkY7loUL3i9COe0EDWDrIdp3XwvO9Y2uz4ZdqWyp0CTe
64	user64	$2a$06$99ycPjN4fKsIBKjgu7cVjeG5qty7NUvsWG5oovSzk3tGwBCgoz.e2
65	user65	$2a$06$oRj5xeHG23H0yLN.EN/Es.tXKfUuTXHTYkAfFOVtedVVT9q3LxnRW
66	user66	$2a$06$oBNXR/7guGIjJjANNtcvDeRWGPLvkqWky0munJcvrw.WbGbRA4ASa
67	user67	$2a$06$gEsMePmFKIuYszNqL41BbuGJqjiRY1MADQQv2pvXUbMTgQhptUbPm
68	user68	$2a$06$2xHoYhj7prl1oAQwtItnGO6DH9B2O4MhfRF9t83y8bOcPtw89Irva
69	user69	$2a$06$ARxSSeJKgalbGYlaenK.wOOQO2YlcZXEQCqQQmkP/h/9TJ./PcmN6
70	user70	$2a$06$cm3eOfoOlF0Nw5PNETiAwOWttTCaBtl9kFHL1wdinBe8j/o41XtrW
71	user71	$2a$06$3HxW7W093fgeAvBz9wjCY.e0Rk/W2JPKtAUCBix9vwnjHF2tHF2SW
72	user72	$2a$06$W7t3AV1kpOJxG15KZaC2o.fAaPol53b61LHrCXLFYQZFC.i0dPzZe
73	user73	$2a$06$pvoxPbu5zhGFd7bBQX6Q0.nR97wpArp33en84LWKQRqS4Zw2tXIkm
74	user74	$2a$06$lhVWlIaJIU2RvZXa0YHVleNC3.9zUf/h8v8gyZETNzm.qmAI69gYS
75	user75	$2a$06$14v/npJXrH.b7beKW29LoubKYkjFWbF5BZSY8d6cQIP1igDlIX7Wa
76	user76	$2a$06$0XWqTvK1j5mNU67k5BXj7ukR/GQeP0gOtuonvgB3x7/0OpR.cqZWC
77	user77	$2a$06$nT04zyAteixAb8V3YZkAIugS3lMyPtyR30TqxTDFOYwdTDPgEx5h.
78	user78	$2a$06$EMoRGRYIRz1l7Ng24XFXLOyyH2H3ZOabBlypmBOb/RbJqQFhQ1iyu
79	user79	$2a$06$.YV7h/8VId5UUixJecrnoetL73XTJEoKxM5f3OqQ9kMaAVXPDW9P.
80	user80	$2a$06$MiiJ3H4n8tYKMNLpbznxD.s82OTGE1uDSXkCeGTnLKw2cWmr6aKpG
81	user81	$2a$06$VvThmXDfCa2/WcvFCQk5muxNuvUMiZsaRfy9YG8x1dmfwo0TfNJly
82	user82	$2a$06$W8dKVmGKEEtH13AOchrjwe1J6.IezuSPQrj3BE1jQRo4TexVEBq9S
83	user83	$2a$06$6JLlHWwlhGDpZh1PkfldMOaAZJIkyxwORZgj9LtsCBLEWuM.W2LMi
84	user84	$2a$06$qFHcAaMti3kZ6WE/ljXMRe0TeZ0ecNgApCCB.s4poae5A2U5Zo.7K
85	user85	$2a$06$4M4t9svLNRnLU6/YcpHNlu5YUSaBMC577MCNeIRpn/lJkrJRlhJWu
86	user86	$2a$06$ZcxAsvZCpOdKIJ3tj4SD3uH4Qsvb5fxtrzHIWOf/OGDSH5uXkxZqu
87	user87	$2a$06$85B0PL7SprbvIVtbNmHEieP3v/XAUNdwu0YWwX0p/ulOEDIK42L8y
88	user88	$2a$06$PfiGABTp9kYUvin8nEGnh.FmL4rORzw4LaQiAx3K92.2wfQzrl.Cq
89	user89	$2a$06$WjrSHbD/RVz0qPueCI9p5OCyfcBZIskfn9MOU4YHXkyp34qjbjD0C
90	user90	$2a$06$zmJjNpmRR8.okzep5.0dGOCl6aB8mEs5lGPxoZ4v9OgHMtVENKY/O
91	user91	$2a$06$UeF/xKtcPmLOji.WMK/a7uq0ooAumH/NrrPWI4egAMX97ytLRHqVu
92	user92	$2a$06$eQpqn/do5j73MdiBkhyVcOElRuTyHX3E4aFJtEmbxstxg5Ph88Zfu
93	user93	$2a$06$x6ZKopK1De25PY60LKO7qOZHRefxJKRfvumFA9rCQogYpodmcX6eC
94	user94	$2a$06$LUeXuGBH7QWC1.DoONQ9JOntDp1DgNUCCK7WGQvIBksvjXA7jEe0.
95	user95	$2a$06$FDes3bQREI4JvlpBjXa9gO9tfqm9yU/aHQccBM2ksGsUaE/SwFP1u
96	user96	$2a$06$eCWyhA5HLi.ZQLf7zjUsSeEPqq2wEVqzHv9kMBIRC18tJG9CYg3a6
97	user97	$2a$06$.tZhSKnFQCqJJTJwn.T8RexdU5UyZeQXeqYts0J9rSuHikza.eqlW
98	user98	$2a$06$SabLF6gSneaVqxGyk3hoceFAuYGmoCiM88X2slz8TyZpb3jUVQmeC
99	user99	$2a$06$xAg7pTivwnmeGNHtcu5Yte6E.UjHg/FMWQGuPmQLCGmUH5ZjeTRb6
100	user100	$2a$06$MDLB9uEp06IbNc689D5Dz.3ObB8kn5lKPMwfYofP.R7vec6.hISjK
101	user101	$2a$06$.EIRciPXTlt.IpKOtgqpZOpPwuzzTnsgTdmupilIwKdtHlL9F5.Qe
102	user102	$2a$06$FDN/FWBKYBuDCdPZAbnVxOmM4rnSrpIHEee/6ndLCPHbX6K51I/Gy
103	user103	$2a$06$f2XEIe7vYA8RS9w8Ezgx6ehsBooOOQZYNIUvHwjDyv54VNu/Kc9Gu
104	user104	$2a$06$0ZV66Rog7e5y7IKmglpZ7eSFpguoob1Na6q.wWIakOfHYmZ6S9djC
105	user105	$2a$06$0Khh5zr7ZLXwyDkENOAudeJugIOph/fY.gPpLiFc1S6ua3oEtbSGO
106	user106	$2a$06$ZzjMeYQ6UYie1RFgU79UaOhrtUe7EOQVR.QtUDm8upJWjZo0kfJDu
107	user107	$2a$06$JxakS4EQMlKZ/o4Nw/9mBejpkjZ0W4lbS1lc4BCtMP1i3Vc/zcSb.
108	user108	$2a$06$apcfVqUfu.sTifzuwArqAudb9aumjZSJ9EbLmV.HCu1kcViC4SyPW
109	user109	$2a$06$9KA3QMttwSv.C9cOZ6JoquhyF8z2/9.iJVIZQK6RQ74ZuQKpOshNm
110	user110	$2a$06$hDU5v6APYijWxik5hdU9GetjlGHtBwRXBcUiaF/1Lq0clb2yw5zHq
111	user111	$2a$06$3YxDqmZzbIxVO7tZO4GVr.QKK4o2k1S9TKrIkR01iINENVH5R8W1G
112	user112	$2a$06$MRZfBekDVLhrUUQcw/jUSeyMnpVSqcISn0Vbh1bxCK7JTc4FjIi4m
113	user113	$2a$06$JyTezsPJk0GKpEXljbSLju7N.MowZXylVAups6dJrRFtyPM3bTz0i
114	user114	$2a$06$.uMaa8q1RtgpxEXU0.mfhOlhY6orTzbnGMvjVTMkeSkr/idB8V5v.
115	user115	$2a$06$4NkEjFPtqVihv5JaaOVgtuYqsKjH3d/XmvLSBl3F1FCVEEjdqp7pe
116	user116	$2a$06$8CtZgV.ZXoxbM8dg0mFH7ejC.uC5ci3Soxb.CbXOnmtr0hUQIP5hK
117	user117	$2a$06$VCFS1rpQrZjrIEJ6mXnvdu8THXPZyGQZDheBQZPvesp5wmyujByW2
118	user118	$2a$06$uNGYj1VqqK5Pu4LOWzY.sulX3rxAP1wDwm8ny.tbcbfEoy.z6wJuG
119	user119	$2a$06$A1xaCfq6OZ4hTOmkGw4OleKEXnXPUCH5EZn6dFF3KfP/WUrREbmdW
120	user120	$2a$06$Ag1GXlcjvpUvHYa7UdWBBeWAbcSo7f2tBlel5UL4yd1vFyBldbFyi
121	user121	$2a$06$LrANaK69mNZ1e/bLaQrXeOh6ywKf0QIq1gE33Jhyp7IbiFyA8stsK
122	user122	$2a$06$p1K1yII4kRd4.cIB/pKdzOJQk9amNdtiKk79IrxIrGPhyIVi3NGJa
123	user123	$2a$06$2V7oUvQ3PlFHyQw6poDCZ.F9/8ySNGkGypFe22/iWK8rdNnB/SSnq
124	user124	$2a$06$32NTg3dCPx1YnoUk7U8APOUBXv5Ci7ZnpQSN69G5zkX27WgIvwtGm
125	user125	$2a$06$gPocgDQlUUoF8M58VpCKoeXrs.W2H4dmW7BVuiIgtnsSbl8rInGSO
126	user126	$2a$06$7ghvLq8hFrLEVHrTABOVCu5PUK4wR8nasCFUxlVrOIlgMu2twaekq
127	user127	$2a$06$/5DEzstUF3Cmsy.Ibf9HDOr/vPB9bok957.WOD33floecYMe88S1m
128	user128	$2a$06$fGIeI734rDRK5oPWdvqVl.F3rG1fmJ4Nfdyuz6alCR0.K8BDqsprO
129	user129	$2a$06$K4P5X/iE3m9/F99RG7Lk0ufE8baDppjSqam7sJK8K61sxvoX2Ymr.
130	user130	$2a$06$.v5GWvwshjSfzeMV5Oq91.MkqF2wtOaBb7nQQJSPSvbLpe6P2hoQu
131	user131	$2a$06$i36MUz429CJlWHNg0Iw34u3U5OFeFeOPSDSjgcPdh6KeKqWX31ZVO
132	user132	$2a$06$Dq6MXG6gwoyArNRORZIWGe9KIf9dC9jyFCv87t0P5UDg8orKlP5i6
133	user133	$2a$06$9cU6xdUd440GJNs7RACHi.3XgXW2VNwKFDwzouqn25oH0Gm26jyxi
134	user134	$2a$06$uqN0U1BGGB5MSyM2IME./ONiZ9LZ5GHnAsjeKRT20KuyTjwnLg/bu
135	user135	$2a$06$/46KF5Ykqz/pjdnnrtLAPuxlvlDTRhHpKrK/LBe45yN21K.xNn6OW
136	user136	$2a$06$4onFE3DQ6beWj5s1Vkm.Me1s3w47qxk4jtmD4DrbSoCf0yJByWcEK
137	user137	$2a$06$bHLR4mvrR3ofeKSughE3OuxD/migHBnM3iOlAxNYwdVi1xeue7mBW
138	user138	$2a$06$FShhV4e3y.rHftGKuIsB5e0FvPBZysVtu5cX4M55NL/2f.0cz6Hoy
139	user139	$2a$06$s5imd8rukT2rIOfX0jt2TeaQkGqaJPendMwJRLMNEv701bmd4lQqe
140	user140	$2a$06$2FKc/5TSsxCmxQsPzc9iW.3Tt1lU/8dX9Gc9uXyE1DkDvYECnAqoK
141	user141	$2a$06$7rXMDzlPUOSeQKruxjSUx.VNspiICtU56ZIuJe5GaKMJ.hSbEkJbG
142	user142	$2a$06$omMNJ3Z3wohhVECsQQMxFuB9QKuaQbpSpWbXZtp7lvyOdYyJ50CkK
143	user143	$2a$06$BSk2FJjwIIrfoa5pYbYfUuim2ilFOHGvWAQCK2jJiVT5RsnX2Kdqu
144	user144	$2a$06$.ulE4ggUr0iNC9WtfCvLI.XzCkrz1azkNWGZIoQeklP9M5mdX3Yb2
145	user145	$2a$06$2GVwjuRzvHUcaMk6N/sZwOBti6M7PuBIZffU/uLZ3PU2LjOxrXLWm
146	user146	$2a$06$Tq1EoeLMOrzamrSLPzYF/OxwzLj7xL0w16JlC92A/REFFDbusiSwi
147	user147	$2a$06$oKvC40f3dCIPQtTjYHRIuuaPeg08F4.VenZ9pXjtpPzPs/DISodmK
148	user148	$2a$06$c4tnmP/Ju96GfdQtEusjcetHoz1s0PXS4ZlCxw/XUkkx6DGQGlXem
149	user149	$2a$06$BcT9.TacBMCrTxusuDrgROy5fH5.mFWq2VcsTyQkHjR0B5FpmhcvS
150	user150	$2a$06$qpN/LSK.QDLr/QokhHvGG.LlqObC46OoQjds/8g1nzI29vImUZ7US
151	user151	$2a$06$/WL3HF9Hxe5z7IJIXloace/n0LySuvBPy4.SQfzgzS7B2H7LrEIPO
152	user152	$2a$06$AZNee0aLLL8E.yW4p9eLHOpzW9D2Q1Zj7V6JwGCaEf3Zp0cURYjF2
153	user153	$2a$06$42i25XtZqT/erswbumJKfedYS3EpqnFthOd9Cr8Mziq5LOAg3iK06
154	user154	$2a$06$.iJyKHXCQ3Yqv380AHSFW.T6rDoH9eYRPfEazrVFTX59JXYd0QtO6
155	user155	$2a$06$LlKCpUrrU6PJjhf4PRFyhO5fI5VmKk8a4vcfLaMkBt0kWN8IhuDK6
156	user156	$2a$06$bdkdFv9ZNexXOAmyIjnWTOIP61FZ363FEHys5rMm7PZukP.kwmq0G
157	user157	$2a$06$vCTTq7PqQuPz.cFTacGuE.HXSM4y5s5N86ez7zd61ARWxhvND6kQe
158	user158	$2a$06$zGhXDUwsFxqzvJX0YuNDqOfERUxm0mPasCJXAC417dBoZrFv7gYIy
159	user159	$2a$06$wm.V122S1cctcLAf6BF8veWSzwdHAev.lDW7crLv6xfnJktqdSGy.
160	user160	$2a$06$XvISboULGOnO48DgDE.VUesXNm.vcZmhLnHKYZNfc5FZbyQsPm4Vy
161	user161	$2a$06$MOq3tzpKW.H4YLpzLAbZ6ufLNnfYicIASwldKIB/T1W2efsh/0bW.
162	user162	$2a$06$WW/5nEhaeYeMBedczubBG.97qwKV21p3Am/ye9/IKQys4ypKppv8G
163	user163	$2a$06$sh6jJgEny9y5h5KBoaKFnuuOdNqI1YGH3qRPIMVq401XpoOYJ3cgK
164	user164	$2a$06$klB4PhPxEj2isrbiOp6z1OezKbf4NhLRUSNIbZ.twscmQPVmPbl6K
165	user165	$2a$06$UDFv.iN6LcFtRPT8cbfgXeIFQHJHo5SW.6QPLM2ZjrAfXqGstcf4.
166	user166	$2a$06$qgDhJKXCqlQeiM35iPp73.Nj5XkiIlUBNnZymPuf/5i63/V4Mc3vS
167	user167	$2a$06$jYuiyV6Bm0Apa7l7NGXAlupqkaRUG97x3p2hw/6qFWOOEDdw5vrFW
168	user168	$2a$06$gSkJDZYj864Nq/z4GUAOuuBHLPBrUUHgLjhoLT0/rzlpSu1AYEBI2
169	user169	$2a$06$tRUOC7Sj4WjDz66W4zahpebO1uTFLENzh0uf2gpsRvfmecNPwFO7C
170	user170	$2a$06$YQOHX04iYDi3oIam9lgnnO3HNwcI8stRt2N2pyGrr96Vhexr47c.C
171	user171	$2a$06$omqtxaxwsn6XY90pmu8ssexfFKfdwkcu0PdSwutdVGY5tEg9wziq6
172	user172	$2a$06$TEiTqLxLmMLbctsW4Qx0nOd3pXbZHPatghcn2QY4n6v0ooHwOeoke
173	user173	$2a$06$cTL/PFBSG.vKzW5YWsPa7eREk/KZsqexQNUtLSIVAkJOmHT2pQ6YC
174	user174	$2a$06$oxmpYY96baEGBQYPOwmz4u9YyTRxlOBF7C0tn9G29Vg2KmhaO.ZNW
175	user175	$2a$06$PYDeVJYi9s2E7a8L8vs5Ces6APzuRX8qJ7BdMayzlMYDu5m2gjDS2
176	user176	$2a$06$1d1Qy3Kutc3LhsbaiCwDEO42bvXHO49PLXXd0I8KkNU530POHvTP6
177	user177	$2a$06$cCu/PwJ99NDLg89MrvkdGOozAg6fYf08F2cME1TbVGVRNzLHfZSta
178	user178	$2a$06$RKzhRPp9KMyDBwGBpZQzEOyfsFR653G9y0e1PhCz/7rMQtbsZvioK
179	user179	$2a$06$4PDjwupMnlTVtvVCv31VteM/AZ9LMHx7nZTXL7vM1zdqoYVvZDMJC
180	user180	$2a$06$HuspGSEIVyUN3YOeT2meIeZYOZULfMkti.BysRmya5TWZAl05fKha
181	user181	$2a$06$1GaCDYYPzo6Xwqjx0fP5k.00DBV8hCrrW4WoSs96Riwy3BZ.3kIFG
182	user182	$2a$06$RlHP2AqaHOYr8xNj2/HJM.mh718T80T026S2WAdf1mbRSN4Ob//1u
183	user183	$2a$06$BquIYHbo6Q4BktrBcFjV1OlQf4BT.rQlDlP0jQ4HKXaBttK2oADPa
184	user184	$2a$06$UpQ1YN0FofEn0OTtQUywoup47ykrBl6qfO6XBTNo5ElDmOR7gltM.
185	user185	$2a$06$dOisVmD/YngYBDiJ7UPWoeczIgGfpCZvvNDoN0K1bxkpfCGx0UrHi
186	user186	$2a$06$tr6rhVrWl.dAIfdDvEzVbuTIjdIVxwr7FlEzo21fw5VzrHfr4z68a
187	user187	$2a$06$dMQ/c3dDAKhauVT88Cm77uwZEyvOKCUG.XHRE2lDa4qzEsVfuvCym
188	user188	$2a$06$gwZzymXf7xt7AUI7Dz8W0u9QwUcb9.QI0WD3nzbKX8aQJw3FTRxN2
189	user189	$2a$06$vVuiitb1ZFjrZjOpG/H0D.iwyBN3hjD0Xqy99KNjk7QUlICA1oSLW
190	user190	$2a$06$iVIlSisxeTHd6S308jgzzeFJ4kQ2S06UWFNI91YQZnyYOVdbphFjS
191	user191	$2a$06$IOPEqfbQVtiR1HTG4D0IIuDV/hcFyHcBLoGDlNbvwc6509ZcmROjy
192	user192	$2a$06$l1jBWJUCAuBooeEmeHaereGAGggJwgXERkZA34uKourh4An289XOq
193	user193	$2a$06$AmPn4JLYws9NcDS30zvgPuR9Cmgww8nQ425s42mbf/6oy8kj6nOC6
194	user194	$2a$06$Cpn1TPnFIsdhh/TbIjeueO.jjsB2tFcxGhHsc5RGCnDylmMMP4kxO
195	user195	$2a$06$HkCwL83oYLUeQrN7FugtKOdOnvb8Ha.Nxg9My/aYKWTV/.uEi3RWO
196	user196	$2a$06$smuJqouuH5dy8QtjEGiXtOfPLWh8VDSYhDMyp7eNEvWy2/wzAok16
197	user197	$2a$06$rcvXidZntvaglR7kcmq/BeC2AyBORl7CyvwoeIceVLsYRF1GeyhAm
198	user198	$2a$06$7r.lHE0.E61j0D8txRKbqeHLkrmNCgJPPXNuOfEvhD4eFt18ugp56
199	user199	$2a$06$mZyaF9BqNceUP7oApxRb7u1uK28kaGkUZ8jLd1gwm4a2HNHWg8Yuq
200	user200	$2a$06$zQ1gcQYCDAMhY212JiHV6O8nMMjLh.uDRdMq0N.spzLmrebXImKjy
201	user201	$2a$06$IwBxcmeqqzWRbYDtTd/xxeQd3nSzTqImPP3QoD1zhw4cCXuY61gou
202	user202	$2a$06$N2ZvcQSJv2yvM2/RgkP2I.ms12Kju2ZwCSeKVjjDpeaNsSYtj0VSS
203	user203	$2a$06$PGAe93XP10126AlczDxN0erKPDjO1vmZZRIIKMcTIC4XmP0cgqchq
204	user204	$2a$06$bS20xJ72pvuHlm49dpezn.fKbVXvg5uMVBiXTePI.tcWdIDyehs6i
205	user205	$2a$06$meqGMlwgb9uOyW1fgBmu/OVfP4aPNOjJPPgZYIEr/Jr6VsTa99WLK
206	user206	$2a$06$tao.EFZ5LHOkExDdlk17oO/Bt42WSULWGACXTGVNUwiknAk3uwOTK
207	user207	$2a$06$rIHGKMEC6iK.ivVYbFh2YekguwlbH23YCFOz54JuXtSQXNS6f1WI2
208	user208	$2a$06$bsXsX1AM30DHrjFJudJiP.mnUlsoZQ/3GhHk.pRv7ElkesVjU5YDS
209	user209	$2a$06$Dc9SJdZAXnOGQRU1P22xSOKp0UZ7UXXUytVCtZ1BrN7rG6DMEFNyC
210	user210	$2a$06$pPGQ5FiPMpAUFwR5vFtorexxBZwPneQe7UGhijVESd7mi/f0aRjp.
211	user211	$2a$06$SE0g8dgiVqLhq6BAQh/EVe4Qlz.f3pwNB5SzEIs1q.KEPq8HHcNum
212	user212	$2a$06$awvTLZJlZmoVueCS9FhziOkf4Yp.z9QzFUSwP0btLbYK5BRlvPocK
213	user213	$2a$06$cBQc9k8XGYce9gsjCCuEM.gY4ssLk32r1UYc1yOeZKvKkFlrVaFPK
214	user214	$2a$06$0xZH6/2EBrS4UABcdfTFver4feI5sjgX5GxFJbuGWaHFAclMFO616
215	user215	$2a$06$OTeHYjEu5SoLQ.08rEymdeXnoehluC/X0BIdpGMM7MF72x7JfVaYO
216	user216	$2a$06$hfdgnUpX.KNfks2SJEid1OgkOhK6NxtAalPajoXC9ahNpd8OHezZm
217	user217	$2a$06$Fp5dE9RbxkeOLWC92onK1OUKgH3qU3x1wRuCadxC389wqwyhrexg6
218	user218	$2a$06$k.jyhAF81CVuSaU24OUrueUXlBHJZp81AkUF0bLzqqTizQ8jMaBN.
219	user219	$2a$06$gonW6rL9UlLMiPtWcmhQ4OuDjLW0CHCOrfcuxizsPyWj/F6s910..
220	user220	$2a$06$L7U4B/8yuC1v3zGu4Ba6eeQgbj5L0OaGcHXOCjL5yMaISVXfgh9E2
221	user221	$2a$06$SKwuBim8GB5bpHbqwi28surzdYky/SPmVafCi4o9Bax6kLTItIeGu
222	user222	$2a$06$zVnp8yj5.olj6MHsrerIke3QiGcIqcIDPDGc9fOrQx6w4ZR8H/fba
223	user223	$2a$06$S01dQ86aO1ayeFym5Xcy...kRVnahiIb/kC8hfJpd/6tPUf2MkRcq
224	user224	$2a$06$v3okITF6YXrghgGC4.gyCe7fhrZNyxZ41..p0EqDGQuhFkJcqRYLG
225	user225	$2a$06$VdpBhucnYJjohpAwH/fKN.V3DoaNSICaWD0gjfpOWpJ870jd7Vk.u
226	user226	$2a$06$famN..q0I40F1BzL2n09cetiYref.EXCVgNK0xmvIpwg3u8ARvEsy
227	user227	$2a$06$yGePiKL1tkUbTyKtzTJmS.qtksBWH5jDhO05gJVCb8BHTLQZbZNmq
228	user228	$2a$06$TkcBf1X1yExtRdfx3nOsYeagXWW/uFD8HRAyEZ.PGsNK48h7LrElW
229	user229	$2a$06$7fCzbNqhriZdNpgAmiSQKOn3XofHXYg/7Bi.tJqaGXjm5ABTpEGmi
230	user230	$2a$06$wvORO5nGHcAzcaoTsU7mk.pqsQ08fi3TU7mIyP.I6xBWG7a6AjxGy
231	user231	$2a$06$sbD9DHnK94cOHcI4W3JTR.kj33Q0pLDwc5jvmvVqcRNuNVkMzeqtu
232	user232	$2a$06$rZv6mBkzZIdZLqM0LawRbONr3Q2d5pM1/OmQ2YMN4XWNsODN2Fzx2
233	user233	$2a$06$iCoJ/bfoUqgIQGIcRzxSCepIll/lBLRW.880Z1Bx/tF84mr0TqqwG
234	user234	$2a$06$wkFHjDuGTIWA2tw3N6XIUOPpJYygPMdHayeVnK8r2ZHrnN8Z.4nse
235	user235	$2a$06$OJCzxki2FBdznSBvC7LdOeAvgg4DxA4409zSYJG7..8MHLgM.jeAm
236	user236	$2a$06$je/IR7qqhQ1vgfqLrlIQMe8407GfUtzBfXmakhPUbpAWLSYnVgtFm
237	user237	$2a$06$qddNBZ4Eedxjhw02177qPuXpV6XTOMmUIfUIHw0WyTrBNOay62o9q
238	user238	$2a$06$EW.fKkpnGJ2nqtiHX3gKau5h53nF.MJ0Llc2hjDOEpvSyBtLORXu.
239	user239	$2a$06$kjc5eRwcTU45OOvuSlJjke.1fZjv5EwOJrlXZ29jZa4jPfmje0QRq
240	user240	$2a$06$3cLtEqBfYQSBz6gZByEQ2.LvMN58VpE9alGb1RElbQu7nigg/MI.i
241	user241	$2a$06$QScVLDpMYK0sE3PMS4kqj./FUJ9STG0QEYxsOR0KVjPoUHH8tAGb2
242	user242	$2a$06$/MVkuI3usSIR87yLQxw4mOibr/SJ4SQqNG3frI27.DLSO13Awzq1.
243	user243	$2a$06$uPxyjsCrxNKsFFncaqo/ouaJA2x4oMALzP9GXEj7qqYsH4bCCHk3W
244	user244	$2a$06$xBce56MhZA5f7rPYsZSCUeZ3dFOAtxKliI81k2aWY5/PBicxFy4aG
245	user245	$2a$06$UtNTB0Z1.h2hW.nqL6xQTOoPY/.ofNmwIxHcBsQHS5Y0hjndxeb32
246	user246	$2a$06$B0YPzY1kSMjbj1aNA9DYk.ObxkjYNtnqQ66.SJIFG6etuZvUN6.c6
247	user247	$2a$06$Numj.CiH8Sc4uc7cNIqfzOVyHVpjWaKJebPWEluVYRrW9/4io.kw.
248	user248	$2a$06$Bxtc50b9/bhzRllWmTjAoe8QgcFZ9gD1rTcEk/s.ws1NU5dOwrM9W
249	user249	$2a$06$LnNSfW7J84HcoLNud6.xEOhdiKOPT4PmIOcgaqMHzQ4r1EmY/3m0a
250	user250	$2a$06$.xOrvVFzkXdjNnPmUHjXduIXl9B6oegU/JVdbfMLbKvJvmlJReveq
251	user251	$2a$06$./8JQAyE7YIlZeK7Qjtu0umz/JTnW1StJd4Tm7z.3PBZ0Z.Ir.YOS
252	user252	$2a$06$wK.zjEzb.brOZqost1wWKOFKYvLdbBeeR1HEmfqLJiLz21Q5kwIfe
253	user253	$2a$06$rhLoqhUfTWk9suaugaoCCu3DQUTMwTYbAuZrwhCwmaGzdPlnBI9gy
254	user254	$2a$06$VXkf1vGj4Voev1G.Il3qHOD/3foH4DR2sfN2as7PoJk4YdNaMLXp.
255	user255	$2a$06$s8U99d.USG1nL57rlYDUXeoBd/T7Qb0VQnnQZSZH/1uRs1rJJZ1RO
256	user256	$2a$06$dOpxcLtW9/NG4IlSI0hs7ODD06c7.Jiw9HJ66hvbyCTONDUcmlKb6
257	user257	$2a$06$G1CLxYYzyvG/iVRWku1xkODxKYDxYnHQhyxU7Ly0ctFFb/GN1eMou
258	user258	$2a$06$9hRI47.CJcJNLEJHKSQIB.c83JHWxDoGMiU2kAIrqKV2C2LObodMe
259	user259	$2a$06$hcy8G1c9ud9slN.PA7km7uIQYHT1YQizQyCDtSArDUSqNbCSrHgPS
260	user260	$2a$06$venEbhf2pBRPTy/EthdHu.7YIF1koY0PqH7Lp4TL97YjhaLOZs0Zm
261	user261	$2a$06$hlWaBxiQ4AJUGLywgAHKTOgs3v6VP4bP7uwF9GYCxhimz7YWaI2/a
262	user262	$2a$06$llFRMLjz/dj4scEzzS.r..3z42I7ENHuDRxW5KAIdGst0QCDPR51q
263	user263	$2a$06$Ia6oFadZ7IzEJ9A/GSEQ6.h4PI4jHJoD8Lvh4adgX8PqxUd5.3hm6
264	user264	$2a$06$nEd1KGwBj1T75y1YFNAluuRBV27rku315sOGOgls.9Rpoqe2vvTbm
265	user265	$2a$06$BX3kmj8lysbw6IPgm4B/0.caTcHM35gCMx5WfAqvRWUhFpD6FXs.6
266	user266	$2a$06$bN6ulff3zc4i0hmqMYBIZe00JZ5sySlIUXSCGlAILXla/a5OgvEEO
267	user267	$2a$06$niinGOtf.E0GBlYeNnPcT.W2Ha1Gpcx2PFvxayjBURsLHLNgec7YW
268	user268	$2a$06$rsKWWh8FEwmt29K73uHyBeZukEkdkLNX8JnLr4GgJnMDMcaEhZuZu
269	user269	$2a$06$yaJUYw5que0yyKcZ4BdcM.NStoYVcfCkK9mBiTJmpgtZ5Ptf2FHtW
270	user270	$2a$06$kOehX3XpMj0U1.t0uMyf3u2uBkufPbhBRuVWhwE4dnJXIWKrCPOp.
271	user271	$2a$06$QVigFgNcGAUH0uAn8eMOGeQod367QqkfETfvm/97Pr1g1ebMHGY3G
272	user272	$2a$06$awbnxjswf668r3fCpNhPmO89/VBDaTqIcbKQmDXdAZKGnWp.Qf12y
273	user273	$2a$06$imj5sxD/fMtJk2nHdbOt1.33e.2Co3am1YLdNs4Bq9gcQUk3Ma4xC
274	user274	$2a$06$ccW4fkf6bQh9gXYEdEr9RuQG3pD1y/YkRCAeu8f4fHBxA.aqJgJwe
275	user275	$2a$06$MloOIb15x52YXvwtI9rft.RawAN8lCWGfhs2lpfh7RFZqcDpMUYMm
276	user276	$2a$06$FhZzA8hiSbyaX/yeGGQdU.Cb5C9tF2FHgvacnOG6uAABfiz70.4Om
277	user277	$2a$06$iNDL1obu6rBa4pN7fWMUW.hmo8uAnoMR7gyw26wDH9aSzXmaXFhtW
278	user278	$2a$06$dEItKvaWuKITnuASNrYzy.APaE42CRZwntFOqVgUc3NJvff3aOQfu
279	user279	$2a$06$xEm./eex84BpeaVuMZgoke7znkVgK9x2kPW7OLnI1/Avz6NSYRWn2
280	user280	$2a$06$HnPj421CHTozyS7Zw08RueExQmnGXC5q8ZkAQrt6YiwRjXV46EJGG
281	user281	$2a$06$gE6abKG/Se3p67/VJN//8usRcZdxyXblnB6i7nCYj80e6ddG1ot8K
282	user282	$2a$06$I/L6MxWBJ3167Q8Iur5iSOcrMAABa18k/ZYPk9ZTlzSV3NiI.yNCS
283	user283	$2a$06$9WOcsYTNwdz/Mp2mJOfKDeFYKJMOW5540h0Um1hEwQ2kZDGu/dg1i
284	user284	$2a$06$ynWDtPU76uR9MYVifwKpN.h629IWwSYFKV2KxvXpV05V8aqk/QavW
285	user285	$2a$06$2IWuNW1y/IDYUziOG7lLoO6nKCW6JMsSvQYc5WMASyyk2GTBJ36hK
286	user286	$2a$06$nTtfgsUGa6N7qHLGxop9Y.637Bd2/tiCP14ESq8PHi9eAC9RBlmTS
287	user287	$2a$06$2JxfiIWagmInsDTeKKnCk.joIT/1FvExx24o.CJgB8YMWzok/8PW6
288	user288	$2a$06$.6aXVHmbdt3hT06ogkUN9OJyOngCa3BA0rBdItA/b4mnle0s42AFe
289	user289	$2a$06$Syk.lQw7DYBDJUhdKejgnOqmOI4tGBNb1uAH4S2ffV0K9oggpRb7a
290	user290	$2a$06$tYtdkHnOMNhLgcoVsJcPeuoplMPC1zmyacTZJnN5Jt5kwseoHEL36
291	user291	$2a$06$XJ.P1ZNcaItC8PITwre8LuoiAhlVyHPofTpJlNaA3JVDPW3puRFHq
292	user292	$2a$06$0DUzAuh/9wlAX3DBtf0eGOdQ7xHWtxAQTdgUNMUWnT4NIwCVoxZMS
293	user293	$2a$06$mDTKBAWBRxkXM8yndUEUDeXdJ5k3ueFbCknjdubqNGbb.1Kurv4sW
294	user294	$2a$06$Zuq9E6fbDIJ/r.4z2xypmuOCSVDgDUcwV9xsF8BAGcCE9kcLGP6JW
295	user295	$2a$06$wdbUWOzQijjXgH6BsC7L6u8Dwcgc6ilBguC1mb7q5I.2kpNRXt42q
296	user296	$2a$06$S8zFasvH67zfOyVpgpY8zuy5Id5V4sYBtp7fzuiaaUN7mMDnYKeSq
297	user297	$2a$06$jcbsFeNzvCMmaUkVvDfyVuRGy0gvBykio2w.jamRcPtnAkr5P.6xy
298	user298	$2a$06$FKZNPrbwBqxFvNNohy3SPu1zOXI47TVo3dgII8jGgfIZInK8AJXZm
299	user299	$2a$06$2oBTKwQGbd7fkD6UeQwTBuu870js6Lt/TCQYpFm8p9m6UlCOej4kS
300	user300	$2a$06$HCwCX7QdYj0JwSsAQ.jgxO0ggBNt0LHeBNFSTCsBmSBnvcIN41Ct.
301	user301	$2a$06$vD6dhwSfANZGWJP/ArNJWOeppM3zBiU/wA3Rmp8HGdttdOdyI9KSi
302	user302	$2a$06$5FNZkRmnz6fzbRvfCrOqveisp2admIj9p.8om..wSwDu5wddHFSxi
303	user303	$2a$06$.mmPTEq3DPPpTRLB5roCVOszAQxUF.x/b1g3a7ET0a85EaU3NxUg.
304	user304	$2a$06$FH357bCn7r.dgXlYN9lChO.7IGmA41EA3Tp9wzIQFiTdie9n2NgPq
305	user305	$2a$06$Jkdr1fZ2wzXC5Z7bkR9XReCz0u8j6Zjjm8dwxA3OB64PSnkYjhhhe
306	user306	$2a$06$hA.oi2LedBessxvwLfklfeyWpOYZhELiNOs7RImmuzG.iPtlSVfWS
307	user307	$2a$06$wHv5Y8R6Yz2nF1a7A2.Ehusldzi33/8cieU2wWYp0MCIqZNkXrVBq
308	user308	$2a$06$tkMLb/T1I.NhQR/p5sxXWeRu4bsL7iCKKQ2wASTzyK4XpTCMW3YPK
309	user309	$2a$06$0b6r2a4AMUSMl/NKGgMVz.aRx97MdZeTdr8yuETr4kLYhlZk3LJTO
310	user310	$2a$06$Ubl0ytMe0rM7UyXrG8fQgun9n1KS6p57zOQ.RwjjctYwAqfmKCy0.
311	user311	$2a$06$N4q.MYCrfzcRuvvfXNLENOOiDWvZg7XpRJfp5bh4sXhyeTB0K5mn2
312	user312	$2a$06$fh.O/udYuZ3XEcKPJgM78ummZLLbQ.2B0dZx5NlGBQFev1I1d1JXC
313	user313	$2a$06$FzcFzKrJVRsMHXbPGSPJ3eTIbjB5oranev52ZKSHQD0Fx6nIRg1Z.
314	user314	$2a$06$qLNPmF8Nya7zTiyl71KS0uIk0wxQHHXaanDoCBywb0RW.7Udyypue
315	user315	$2a$06$MGTDVcOBzbcv43iX8371I.ZIiQfscrOfqoV09vTZNr845UQIEBmSW
316	user316	$2a$06$6Ch/5P4MfLBEE5EtZ5ik9esaii1WKVZ7c1rhNOEGw4lf/Ac.4RBGK
317	user317	$2a$06$K1uwM/0X/wxlKXtw4ajVh.owXJIc4EgBer2LfP9LouRFoEqNWn1QO
318	user318	$2a$06$Z/Yi8a731iTOF28qS6qLMe4myyBE43u5sNWIDRRPAzJN/fKQO2JtW
319	user319	$2a$06$Wisb1X1PypwGVuLiWA0XoOpRD66Q0y1fQPdWBO092rYUorQrAycnO
320	user320	$2a$06$x8pgVYr1fb12sMA3nZzg7et.ArtQiHU66oZAJorTC.GDNH.gzs4J.
321	user321	$2a$06$R4dBAG2wqK/aMKbz/n7F2OcJp2xQFtLlFmwsyRWhEnD9u1Pkcu/Hq
322	user322	$2a$06$4Zau8l1UQuLobKkE6H.Dr.haSJS0Uoffy3pBo941nrS1n7j1.sOsq
323	user323	$2a$06$t5EqexL.bTd8KGqHPgJjk.y4iDJN12gWzvi12c7.EFG02/xBk/dcq
324	user324	$2a$06$2A3HFhQbkYtrUBt9TIzal.faA2ZljcuZt7mx.Q70jtnQDVJlORvIW
325	user325	$2a$06$QCZ8K35Mtw7JjmVF2QVex.LS9sW1Bpsb1aPi90Aa7vbnoBM/14nla
326	user326	$2a$06$/imgq.SmXDo/QB0CYX2Rz.bZjBGVXY.BmB2YT/dLYPA5GKVhZ/upe
327	user327	$2a$06$0TRzg3J3tUXK6hT5k5oOR.c6Ec86MtoPR1pe8vmbKpJjsIYV3SHB6
328	user328	$2a$06$JW8hedHJ9OXlVLBmsqH9oes1u3CJO9GA.kBknZhDl7fmYMhlZkQlG
329	user329	$2a$06$wfR3lZuTi1GpBj3xlVMBgug57JOZK93IkbZFh6n.LgGLYSV3tse0G
330	user330	$2a$06$tMaV1qgmE6H88N0lp9JT2.rWStIhgTLewCcUrWlm/4XZbx5khdN/O
331	user331	$2a$06$m6ejOZ1H.wtwwSo0CYHYY.02SqICE9bTGNp6EnsvfZlhOC.khQSlO
332	user332	$2a$06$rvpPBcSW4P.csx5t/oW.7.Fy74Mr06H1KFV/CJ/7mXZc2GOQQ/vDq
333	user333	$2a$06$lDagUOrzwRfL16uNOl3llONNebJnZayO54QZOGg72lPCBu/x0MXTm
334	user334	$2a$06$7hPNiKuQEAHLoV21VLU5ye.QvDcbOnshqnWNfp2812qkaNX.DYZhi
335	user335	$2a$06$SLWoxdHOVhqBL56L.Q58Mun/tTZSOuQwD5pEit1FnqrOqwCGYEN6a
336	user336	$2a$06$iUNwCGPi/ZYiX6.xf/vVouXd8hdOUSs6kiORe47A4pSN60cdKYKoO
337	user337	$2a$06$R1VwNsAsL99Qzp28Qj8Cqe3nUnGfyMxDxDJNPewQe2zuyA.whiuwy
338	user338	$2a$06$NQ/9KTm9idIM3nMJ4t5Zk.DR..DczECWLKY04hkLUJcT115WhQE1C
339	user339	$2a$06$nqemRge.TiPC7nqMxvYvj..vGDNKmu/KaB5qLQG3ln9VwNKfzbdFu
340	user340	$2a$06$OeGJp2E/Kqvlip.ebU4Gjutz6UQsj/LOvLPMbyfAhLfseLKZmX2cS
341	user341	$2a$06$vZ8f9KzubBnV1lA.5e3NCe/F46Zk9eL1Mk2Cfc38wVgjNXm9YaEEe
342	user342	$2a$06$TmMwk/DLJ9JeQQq64WH.Du8KJ/Owtf8ECESY4oUjesjEUcuBDfnmC
343	user343	$2a$06$epB5T8sMuzgGBjRSbCPloeBLTQutpdRQPJqkkVtEytwAtENWjcyGS
344	user344	$2a$06$KrBpxcg5Z.uB.54wPoAvyeLXpZke0r8mLdLIgzFenhZLvs38CMnk6
345	user345	$2a$06$PoX7HuR.SRrzKtNxOAcb7O/XR3FxwqgvfRfYc4kbvHECsvHc/s9o.
346	user346	$2a$06$j5ZGkNOzw8PO8TIiepeEcO4umV1wFIGvvNqhXnbIiS0Ebn4HYVtBu
347	user347	$2a$06$ejHutW3.jtzwDH6NBJ/pr.z7nAoew8rUVEcSQCVOzP7HKTfBi804S
348	user348	$2a$06$hry8zT3zPV/XhB06xZvwEuxOZwGEM.HLfSXkLZHgIU73006JZvayK
349	user349	$2a$06$MGxqCbMCO/1supZDBPYScesC9dWJkNELNzmZE/5qRmD1/OiMfwJhW
350	user350	$2a$06$yI8ubnqV3u4M/2eWuRnTOeX2MZ1DPPm1P3coOrk9Wxhgf7endzk02
351	user351	$2a$06$8NXHfcI1mF4CXLOHk44Rcun8kLLWqPZw1QtTy7gTbkckJXmGgowTG
352	user352	$2a$06$WVKMncotYSDafXwD87UaseRXbtZRDcDcwWcWbpqQ3g9b6Nc0O3vcW
353	user353	$2a$06$hcAOpTiJcZOPuY1AIGYRX.ILr.OKZYCuhFBIo33dvrb5sUH1CPBpe
354	user354	$2a$06$dHloqH1Ds5rXV8Csuje6M.eX/E79nykV2Q0lMEt7BHpCtGyssQJDq
355	user355	$2a$06$pdSGA1kOc17RcIU22rlqpOqH/rvnSY5VHtPh3u2wBVxDyLfLfGTZ.
356	user356	$2a$06$JPbPP1CkxeLP2CQx2iAM8.PbzOm.4P8any9t6.nBf/zYJ8ol00R/K
357	user357	$2a$06$nUobG/oEPxDpXtrd9RRane9QPkzVNo3ivAXZfo9O8m5tJAD3CFo6u
358	user358	$2a$06$TIpDK52oSdf/0xelC6ICyuPCe.QXPXr6sAHBwNxDPEgaOF7HG5BFi
359	user359	$2a$06$yK9FIsgiulcnVLsYnYud5uvsmVfAlxDND4CJPD5TODfVWIX8BgpKa
360	user360	$2a$06$FAH7l98R70mHVO2hebsh6O.5WZAET3sswvzZblxnK8pE6ZxRvD.lq
361	user361	$2a$06$3I5PpJ1qCPr5EINRSI/1puYK.6U0Toh2FihpjZFHO9A7heteTXgoq
362	user362	$2a$06$q9dKEETDB87r5iQmZQc43ObyDrYTDC/fIZu0X/ro4SjqI16fq3OyO
363	user363	$2a$06$umMb6XBFDzUNLXQN7udy.e9Mghx/VfWuX4lfog.bQK8CegmwtWObm
364	user364	$2a$06$G5c/k8ApNj0zAxn4vviaa.s3E83cLWs/IdY84DA.NXiYzn66jvUYi
365	user365	$2a$06$HWdH9LknKzIFifOLgQ1u/eazz9f81IUxYNUlRa13/s1LJdR5Q/VBm
366	user366	$2a$06$DDL.N6ROAF3yFl/6tX26behVDQ7bIwDZTgkGfa1QZuDIuMFSx9XCy
367	user367	$2a$06$LQpzbclP/R65MVdlKdzZ..equdwFAJPjknNvooMkXgwKrGk6vNZIW
368	user368	$2a$06$SH4UajGCPbNw6un7Bm3ZQOdgomdVVLDsYU0HUvDCjIU0rNT7c95Gq
369	user369	$2a$06$tNeJ.tRqb7NL4hG98/TDDuJWh7Kj/eAQQfI4QMKoffa4MUSJQVbgy
370	user370	$2a$06$lSk./bo.HS.fJAGXZzHePut.7ycgkFHdiVPqXSaTZvgf9vkKIqgPy
371	user371	$2a$06$I/x.7DVkudkMf.BW0d6AwOhcPQB/LzkbQ4zmw8u9aKQfIvO1UW5WS
372	user372	$2a$06$U9bIxNIkByfvB67brBH56Oyv1hcQ0mXVl5CGUjdIv5yEb7GsQAbEq
373	user373	$2a$06$QUNv1RJgwFHltvl//hgUXed69Y5BoRlC2MOe5t3.6ngmOa9CyoLUy
374	user374	$2a$06$zzAFHn8HGa9rOc6ja3stXuANoyN37dpyEnvw07F4tBtH.5ZOgfKba
375	user375	$2a$06$Hix1fLB9z35uz6jfIpgUzu6uYXK1QHAFMeG1NjFI9Qx5JKbMCy.ye
376	user376	$2a$06$R6t5swSJ7a4WdOnuGfPmme0RMnMdp814J1iEwiHgXhmaOVXt/S50u
377	user377	$2a$06$zMssxny2NUHgiMkg./.byukWfPTpjL2DEYyYdNQPrYeZE/OiYbtB.
378	user378	$2a$06$av3wnldHaF6LYLhtYgB6ceNAHrygc8RJV0redN3aWPSN/p.Qjfuda
379	user379	$2a$06$15vh67xaEDaJQHtozb0jIeHLMh40Aur6k7NGkaBbuHbO0ds4gDBZ2
380	user380	$2a$06$8yQQ/DTyDjJh1hbaSGtWIuZ/g.ri9a9vIYDpg5lwRxnX17Ovw1QUe
381	user381	$2a$06$Q1VGYie9FAwhvhZX.HV3VecoKRuFpa51BFzUwlVbtOoMVyAoOVOma
382	user382	$2a$06$P2V3UhZG3uhqdNkD7g7.VOLxfubYGGRmEuLErDkU4zhq9eok41NJO
383	user383	$2a$06$D1cf.fLIgNMvG6tU6M19/O5lISGHV.34OoBuZu976WMCnj6F6aazG
384	user384	$2a$06$0.4j0ll5g7CXmi3Y5jQU1uIYMVb8edvfT6E50BbYnG8wofdfkJVyW
385	user385	$2a$06$OXfflw2KfD2hboHsMMfjtuerKs6iv95hC85XlSGgHAfRHWUlMUzDK
386	user386	$2a$06$FzyIZfSdc4QfNPyhUlAihOcCi98ctmodZ9gxqnZEwopDRhg7z5leK
387	user387	$2a$06$PXXFkUWIOWEZp5q.Sw2W.eIPzpBu681zDrq5ny.Gl.sHPT88IR81a
388	user388	$2a$06$ewqt5ZD0.vH8tEQT/A1.s.H5S6lIbKkU9SDuALrx4H9k.cC99evCy
389	user389	$2a$06$f.GX3pv.1emRHVw61Jq8m.E6aKJcuNQpzA3ihTOBOuGKYwo9F5TfG
390	user390	$2a$06$u4jl0FUa1ss/sbDFZMY17.c3zcrozSvc7y.7BzzbMXzPu7HIGxXde
391	user391	$2a$06$A1IB2vwpTEh1qiRNHX35BeU1E8zlyiK9WpS9N5sFOJdE5AFSxOXc6
392	user392	$2a$06$blR3kSPFQajgszwnA6NZLODhPY2pJt62ziggNrTGWJKXYcFuWeyKm
393	user393	$2a$06$gOeonaUXhmDVSk03jJH43.IUJwr9pIfdpJ8tES5lqCpzCg9Crt3e.
394	user394	$2a$06$xfiHuNJDXTnJ0nrAuYXt4efVCM.2JpRKMLkz1MkPVJFQyV0KxGYvS
395	user395	$2a$06$.JDL8Pgb2/5XCGQta1kvHe61dszrFgqOrp81Ipt6qp/fAZv47j3hC
396	user396	$2a$06$Z1zBQalKfR9RQjrn1CfLJ.vz/KD/JioyutHWr5ckhgeg.xP7tJ0e6
397	user397	$2a$06$384nrNJ9lkb1PK7eqtBake/HvZMiUxzojI3WdXVSuiIxUA/k/FvHy
398	user398	$2a$06$bk7gLsOzvxyj6IACJStpIO9dKGKBqbuA2RcsdlsZevM0HLvfx9bYi
399	user399	$2a$06$9Xb.GoW7sIRMSYAofVOdTeHe/5oBKx4.KraTTqaABA.rzTNSaaLTS
400	user400	$2a$06$y6Lu6MkeqUoTqiaEGpYwx.o9.hxHIcOHO/jFcvXk54cKhJajcEb4m
401	user401	$2a$06$BsSPZNft/jxhc4AnlTFEXe3q9J/DwvAUmqe.LuEf2uFgDkHfIJXUK
402	user402	$2a$06$lsFOlpACuzqmvIemKTbQmuauOANCQm2kHBR6fw3B.6lhGmPBju7QK
403	user403	$2a$06$4SLd2XB/hQ0aV2UkmEwrnuM/MPxb4yhliY1KjdzcS6VwiweUIj7P6
404	user404	$2a$06$LGFou8j1DzhMoMHk3cDh/.DzDPGW4S/HF3R2wdNr4FlYpt/ibTCBi
405	user405	$2a$06$ikG.SeVfGZrESrxo.I8UZ.gHY00jMMpJE7A64DCS3XuAeiFeZrK3m
406	user406	$2a$06$NZn6pYhbg01qf9G4Gu5IB.tCYBaJQvxIXxJj.7sf7m1Y4mQstMJuK
407	user407	$2a$06$FwqQf9v8mAobSEC0xqytX.ubIV/xQOqCHfRRmr10MGscs6rwXblTK
408	user408	$2a$06$ogokks3Zqw2RjVJz5JTwrezqM.qwkmM.JZRqqw0ZQXlET2Uugdx0i
409	user409	$2a$06$Vabn7b945FIUDtKtCWlHnui1bbvgsgtX9lqfI4PvYiSPbCuND5RtK
410	user410	$2a$06$EA9al9z4OPZoL/7Up.4cC.apO2.7orCGKOhjWQqiV7u5LqK8mHsr2
411	user411	$2a$06$7Sb5uw8T59Z4WJ8SyT19s.GhWPMY3cfN4.oSvOd6.0CdH7L0IpVRe
412	user412	$2a$06$HCIoSlAsjSzlnQ1IqFgJeOsnbwGWaFcfA6b.OL05669Mt5HDBe/YK
413	user413	$2a$06$8mgObf2RvdvWGynJps0gbu.E49y.cjnTmNsHEHIAZgQWVds3nIWkO
414	user414	$2a$06$f7nPPx6RXdDOhewzvWiXK.OcUJWgSKLGBAI8xYreKjwI4ksf3dasq
415	user415	$2a$06$gj1AiTxqCnlBW5zKQQWUQOVz.q3m7GQFLEjo.2U6PCzvE6Tezl.tO
416	user416	$2a$06$tODf3m0MlSKI..Iac0gC1OFjpQFgLI8CV4PArR17NU7WNK.aRenKi
417	user417	$2a$06$.f4Dr1YneyoEfX.GRng7ZuEo8XDWXbnpPt1e3lkRlqPB5mFcONsF.
418	user418	$2a$06$DY/d2ar4QzC3DSOSDmR3DuCpz0t1ScTTe03ZNTWvql4wzFIf9U1eO
419	user419	$2a$06$p4BPj1sWsufvigJtqI4fE.N5lfF8LEuX2wqLAx3r6qDHrI4vddhyq
420	user420	$2a$06$6PWx5Jnajc/9DWtUnGhhMe14.ZYJRNA/5IjjGeOhEvwzN9Bh3q5IG
421	user421	$2a$06$Apuee/VB9COi3zQLgCRXXeg9TNJOfawM9A1V9GI/Sl/zRBtsKIkWy
422	user422	$2a$06$OBm/C6lB.xpCJRulfnX2QuvigRWqNmk7MMNFjqlkHyKHNcBTUI.XG
423	user423	$2a$06$c9avFx1a7L1jMDv.OdcBTu.Oj1H/BS8Cmp3eKgveaMD7NBLEedf0K
424	user424	$2a$06$ZZV9W3Q9QBjy37TqaWPYFe4w8aifOL4r2fX8kmUrWQxx5Tbhb5fwy
425	user425	$2a$06$2EXhIawkft4Rnkz6RSrGq.qPFnwAdnFwfCbaXB2N2fs2ifW9Tbj2q
426	user426	$2a$06$U2nnEr4EWXf373Ia0HlYkOzwdC6WArBgX7RfSyzzYswh1pZyD0wkW
427	user427	$2a$06$8HDq4iDj0i5QjqNHghD9QuivNT3/zQyK.nTOEj1mtTDpj5PEZ3PbO
428	user428	$2a$06$icRQyXP75.ufJ7D8nGSHyulxmDw1yJnHa.X4tRhvGU7YMHk8Hud8a
429	user429	$2a$06$YqDysUCnEpui4SRuV3IQpus.QGxk3RDM.QWKyMbwnTj0xfTZF322W
430	user430	$2a$06$lUSFV3R1EYrCtkw4QgucNua7iZT4ZasMJbHSPd1zMarpH6mCkxD/W
431	user431	$2a$06$wRs.ah8gS7irAx8Mwrpz4.vvBBvzwdxXIZa8/t94JNHRYGBoEGjBm
432	user432	$2a$06$6.tYqiBenpjME.j6DMOEPOU9Coyakt0xMos7zco4eGLbz27w.aqi2
433	user433	$2a$06$GRkUBaJC8UhZVDmsZC912.vunI/W2S98NHz1QD9UMKXNwgZNlxd7C
434	user434	$2a$06$u.jlLrLUTZ2cJ.BfS1ME3u7hW0dKWbDhUZjr4lx72IUptaKV/YEmy
435	user435	$2a$06$xdd8VaKHdIxqpTEumqSLme1O0JCNBJt5O/DKNrALtqKaTl/Yqd/KG
436	user436	$2a$06$1uqQD5rGmx2naePQUgIlMeoUsJW1G.PrTYPff0eL0d4urzhasrOqO
437	user437	$2a$06$xyWlO/UIDXFiYOgr8tXF9OpFmhw4Gn8wwGrqH3QudhldNcOu8e7MC
438	user438	$2a$06$ka1X1.bdvPPWMiCj9h/0oeaJaM5GPJvH.eYTqflRIugRF9izSpdYi
439	user439	$2a$06$Oo41nNM3WbW.2nh9IoYo4OfwQtM0IbrcdBUquTojiLOhufHfVGsuS
440	user440	$2a$06$8qBzOrGobhdfr440UgHF.u43f/qkIdwiSL1S5Pyuf0YoN9rR0UaKK
441	user441	$2a$06$capqSd7Cc68VEqHLETtn8.UJsadd6mBm9M.cC7.y38hTaNwVCKeLK
442	user442	$2a$06$VQr3mWPIFFn0l94U/fAIS.xpifxXGY/S88wLtQn6.4Qqdw3O.kYje
443	user443	$2a$06$p8ZaPRMBbKikcmqJcasETODQp2TVvc4PM.demlgQV4hbBX.IuKX3K
444	user444	$2a$06$gdlIMZcMDfs.LGyU2R0Xr.DFAdnCwzDmxy2RKF8zAUXRBciueQhHO
445	user445	$2a$06$umEBL0JkjbdkBuJ6.9CNs.CrZPmYwKS2GHDPksebTMO5XybB33oFi
446	user446	$2a$06$2a4ljFOqjTDqfhUubqEZ9u8zAC9xI9aWuyts/DdjHKNgT7QGJtWLO
447	user447	$2a$06$y98IpJeUCQHuxzdV.VqsSOGmKsETqIjhT.FuDPdVPAjxfCEgDnFkC
448	user448	$2a$06$1KxqFAyOk2oVvLfx7sWKFOFqKht63gOpaonUvk59sB0hqvhYHiUR2
449	user449	$2a$06$RDevYnwfc9JDeoU8ZZjnQ.1addw3fsKmFCXBgq7HlvcDfltsJvDmq
450	user450	$2a$06$UX0QWMvVl5pTpvVW9yGczuCQPMVAx6PzwP4wKbjFIQPR8QawrXDP6
451	user451	$2a$06$iMUS5aqs8GeyRxAsdzl//.B1/hRC4bjawPeP8aPJuGKOPjmfjNp9u
452	user452	$2a$06$5oFFcEL/GyCkdpPiBZIb8u3lZlOO1Rb9sepUe5i8GJROoqMIqqw1K
453	user453	$2a$06$LjVre3Mb8b5foluFj1yu6eqiFUDXWt5MTG8qFi3OfjNHKeNhOoATC
454	user454	$2a$06$B8SMlrs2wnJ/gSwgUiz.4O95had/3g5ydyEiIcnOh/hh6MaZnJssm
455	user455	$2a$06$ihCbVVySWDtiS9Yisj7l6eCE3Ja6z1HZzy/LEVsdQA82oAqiyoCk2
456	user456	$2a$06$qHiH2e/pLzLowsRf5BqI2u71TjN/Y2Kl8UoccP6te0u8JYcj0Nkxq
457	user457	$2a$06$Z.aZTHJXaM9Mv/pnEPt32OLPNNT2KUAQSS77OyNhe4/RkvxKEYn52
458	user458	$2a$06$UBkwgcTPqITJSzcizJ.SQ.Yh7bVi5kwrnV9XE0sFcoo6NDEYEkDey
459	user459	$2a$06$rjmlUGEY7jr1OtlyyxtlKOo8dwOqKA.XXizgf4tA5xcd2dgFjtnDm
460	user460	$2a$06$qEhjoJDxf1azI0dEhfaREuNt10Lw6TjqObgA1qAeoJ4PZheCVu9kq
461	user461	$2a$06$dalMVW5jLU44JXaQvZwz9uvyfC.SlWMnrE4RcclqnO6rmOemqSuca
462	user462	$2a$06$toXff7LFK0Xfa6z/JzlpN.mxY5XeonA5/2.CDAmIzzqQD/r6hd2Xm
463	user463	$2a$06$Gd8Sh.Xfyp8lJiCkqLhS7./.j6grMg.DhvbSLj3yVLE/yk4QMqWNW
464	user464	$2a$06$/uxb4M6f8/vpA.nwUIrWYugAM5hJsUhrHhlQiX2vi2/o5wgCkdSQ2
465	user465	$2a$06$H0Si9iIbXpB6VtR1XNXoH.X/TktRHlIbyeQuFaSrEEZuYGWdzQbi.
466	user466	$2a$06$UHFoeA9MpFSE.9j0oZOk7ehsYACDcsliThupPfEd485zlFWiCoNka
467	user467	$2a$06$BlyCHhDa50WldU30GivvXuCRq.i16eIGHLqQLESQDTXpf8bD1y6u6
468	user468	$2a$06$g5/a4Ouc3kGg4ODN3/maT.ZYv7zc2TNflph.0p0w8Sgkh6BHEjw/C
469	user469	$2a$06$wT4jdZJ6j91Aunz0.qBmQOO4rWZS.bM6NsF5bPYA4TojNR/tJ.GjK
470	user470	$2a$06$c.EZDRPrAcqJNei3RJOoMeps14Mo3wEnHTpNuYXYEWHbTHYBpQzjq
471	user471	$2a$06$mOKuWnAJzExxTMYYWATRjOMH4Wjy9RCqdj0BKnYfAorxjB3YOtHPa
472	user472	$2a$06$DyPHzQUyNQJjq3NTmTV/eOLiDpRMwIXrKxP7WJjqGVGI0KsXyzmza
473	user473	$2a$06$5n4fQAn86JTVLKizeamG8OxSpEvKDUW44rDr7asVPvx2F746LH2Tq
474	user474	$2a$06$NMRusAq65VvxUJkKyM2MeO6f5HCsyaVaGYJUXvuw6x7sIaO20zHmW
475	user475	$2a$06$0uE85TJcD/sTq6mf.H/aheWQDPQjWbbwbEnUKJpm.qRTPGwdjcLqW
476	user476	$2a$06$r.5fEv0y3I4H5U8en0IR2OoorqfRjOD/mbJ2UYsq2Beq9I83FDHtO
477	user477	$2a$06$3hTF.zFibGSUoKbtXgSGQOmXMY2/W6zCGzjzgRe8RoHcbNiupwefu
478	user478	$2a$06$nIoEzIK.KyLSmni6gOVXI.UpvQz9sjAFdX0qIqylGkEt0mKKH42Z2
479	user479	$2a$06$3GUkEimzuNauPpkkOOU8r.YhHP43OjJMsNgvJeNCgPrSug5jYUG5K
480	user480	$2a$06$qx.WYyP3y39LMdEjtikDEej6/z7EyVOJbaJtTHGD0YAMHiVujhLea
481	user481	$2a$06$EvXEAkV0uTyFSjIXRTdQ0O/r8djA5XS/BsEuJ/pzROVaoHh0arFam
482	user482	$2a$06$aSaaHudk5SCiPD98uBEDf.YV0msFBn0ZNE0P8B3b3Zd1FNWZz0aAu
483	user483	$2a$06$xGd4SXP4oPHP7pRboAHaLuyRx5/MfdUGLOxqd6EjKe6//.Lyj1gyS
484	user484	$2a$06$d13CCBFcQyR2NwA9LA2QPua3xPCxGR.f9qSPWp51lUakznmU0u/eO
485	user485	$2a$06$rvDDl3M5Jj.kHHGTtLv14OVs7tz1n6tx3gjTzwpfIRPgy6LRMdrXm
486	user486	$2a$06$1WC.q8.XXrYEnk3YViE4UOlYz4ErBBHBztwCquCaQswJD2i3Aiz.O
487	user487	$2a$06$Q0gxc/LdnRkrqxgnR5ewGOY3ZT.ZO3nQRII4E8.1bgGvrKFCE2P3y
488	user488	$2a$06$ganelkcReW9tnxC77TpE2.KF0vUvmFPU7jjPjmmlo9Pd3OEIV1El6
489	user489	$2a$06$NInvgw8NFEpx66T2J.1JHu8GcX2m1s8MeTNEuCIIVufZo9scaewHq
490	user490	$2a$06$NyOZbKfaTgVIZXgN407sCerIVsgVnxiDnbtuUHUKeDvDaD3EFdWFW
491	user491	$2a$06$lVBcs.E.SbeImhm4Sr0DGelC6ydpDLMCGGuPaSNQVPRZO.FNiQucG
492	user492	$2a$06$GIZKF4pWrc5gFQIoacFSLuux5hRKhdNUHoYZRsQJ37kpq.IaavJEC
493	user493	$2a$06$IxnmefcT5vUSm7.WuDdbtOcAA7naIkk5yLsqD6iRzKHXpmZi5HFVO
494	user494	$2a$06$UX.OlABEK4kMZuZUFKsHS.wEeNNdC/ftIS/838HcoNA8up36ilsqm
495	user495	$2a$06$QS1IKldB0jpLlXwT2aPIVu9Sh.oXt5V4tAK3lpAYt/QAXoKbN0hAq
496	user496	$2a$06$5IY1jQ7ZPeQ3s0Kkon4sgu/XGaBaiCaUlU6xSCMLJ9FyFgbRlgUGu
497	user497	$2a$06$OniI92ZOd/VB6joeDsFSGO7BLHY0buw2ywitSw2juIMmhScDi72rq
498	user498	$2a$06$DnEn6M4U2wIg2jrx7VJkheOn7cAu7zane12aOTjGcLP4Uk8HzEaSq
499	user499	$2a$06$Om9KpOgzTByk0FBaIqa07uJsHl37gr36RR.T3SM22.X5b.DSsHsoC
500	user500	$2a$06$LTQa03LXxSvP6b5B2.oiTeDnWueKp6uBErITbB277TUB4g1kNJT5a
\.


--
-- Data for Name: administrators; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.administrators (user_id, office_id) FROM stdin;
261	1004
276	719
461	669
350	29
197	483
325	1057
118	746
80	1022
464	1112
181	528
299	1152
456	175
380	846
242	1077
392	816
386	1222
109	83
444	806
434	1052
174	283
346	888
415	52
378	1235
397	658
144	1149
326	881
473	386
459	1068
478	178
280	810
330	168
141	1173
308	1108
156	269
25	1107
366	1063
417	186
55	249
315	517
188	1115
63	1241
329	543
498	780
377	745
95	151
403	350
341	674
460	495
241	509
467	710
352	369
185	936
10	260
178	590
431	654
340	362
468	916
452	214
445	252
199	988
21	17
91	341
1	366
295	332
455	1171
336	525
493	270
120	973
11	995
399	441
213	913
211	416
347	756
345	302
230	12
484	975
123	787
13	614
406	844
191	1183
37	1013
221	785
279	499
442	560
323	383
294	820
224	951
125	55
175	765
30	840
232	473
418	923
28	734
210	307
138	67
124	456
179	741
34	998
458	22
383	601
186	1082
250	1120
314	960
376	137
177	774
343	1088
102	804
172	318
435	79
318	679
256	345
130	848
407	606
465	983
83	408
271	577
391	857
97	979
338	356
94	1247
394	1073
187	821
218	363
164	588
371	1245
129	322
\.


--
-- Data for Name: birth_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.birth_certificates (id, father, mother, person, issuer, country_of_birth, city_of_birth, issue_date) FROM stdin;
1	2	3	1	573	Egypt	Fuwwah	1990-05-02
2	4	5	2	1046	Nigeria	Damboa	1965-08-26
3	6	7	3	909	Bangladesh	Gaurnadi	1965-09-16
4	8	9	4	1211	Albania	Elbasan	1940-12-25
5	10	11	5	869	Monaco	Monaco	1940-12-11
6	12	13	6	486	Montenegro	Bar	1940-06-21
7	14	15	7	516	Niue	Alofi	1940-08-27
8	16	17	8	802	Montserrat	Brades	1915-05-27
9	18	19	9	710	Macao	Macau	1915-02-27
10	20	21	10	1213	Syria	Tadmur	1915-09-03
11	22	23	11	768	Uganda	Mbale	1915-06-15
12	24	25	12	131	Samoa	Apia	1915-06-10
13	26	27	13	852	Gibraltar	Gibraltar	1915-06-01
14	28	29	14	124	Sweden	Huskvarna	1915-01-12
15	30	31	15	626	Bulgaria	Shumen	1915-01-07
16	32	33	16	540	Tuvalu	Funafuti	1890-07-08
17	34	35	17	298	Switzerland	Baar	1890-12-20
18	36	37	18	778	Azerbaijan	Yelenendorf	1890-11-11
19	38	39	19	1010	Japan	Kishiwada	1890-05-08
20	40	41	20	353	Barbados	Bridgetown	1890-10-26
21	42	43	21	1067	Somalia	Wanlaweyn	1890-11-12
22	44	45	22	643	Turkey	Sinop	1890-08-01
23	46	47	23	196	Brazil	Barcarena	1890-03-05
24	48	49	24	928	Uganda	Kotido	1890-03-02
25	50	51	25	1181	Pitcairn	Adamstown	1890-08-19
26	52	53	26	812	Dominica	Roseau	1890-11-06
27	54	55	27	573	Niue	Alofi	1890-03-15
28	56	57	28	749	Fiji	Labasa	1890-07-02
29	58	59	29	1145	Afghanistan	Zaranj	1890-08-02
30	60	61	30	916	Austria	Wolfsberg	1890-12-13
31	62	63	31	549	France	Cugnaux	1890-05-02
32	64	65	32	533	Aruba	Oranjestad	1865-03-06
33	66	67	33	625	Morocco	Settat	1865-09-11
34	68	69	34	1125	Portugal	Arrentela	1865-12-01
35	70	71	35	1005	Liberia	Bensonville	1865-02-03
36	72	73	36	695	Sudan	Shendi	1865-07-28
37	74	75	37	319	India	Nautanwa	1865-07-01
38	76	77	38	46	Greece	Corfu	1865-06-09
39	78	79	39	30	Libya	Sirte	1865-03-17
40	80	81	40	1071	Spain	Alzira	1865-04-02
41	82	83	41	1250	Chad	Ati	1865-03-09
42	84	85	42	247	Russia	Ilanskiy	1865-05-18
43	86	87	43	1128	Uzbekistan	Beshkent	1865-09-21
44	88	89	44	359	Senegal	Bignona	1865-07-05
45	90	91	45	1147	Zimbabwe	Marondera	1865-03-12
46	92	93	46	1062	Estonia	Viljandi	1865-05-01
47	94	95	47	627	Kiribati	Tarawa	1865-06-01
48	96	97	48	689	Libya	Murzuq	1865-04-20
49	98	99	49	481	Pitcairn	Adamstown	1865-11-10
50	100	101	50	182	Belgium	Riemst	1865-05-18
51	102	103	51	84	Bangladesh	Saidpur	1865-11-14
52	104	105	52	92	Madagascar	Ambositra	1865-08-15
53	106	107	53	287	Greece	Rethymno	1865-11-19
54	108	109	54	117	Netherlands	Delft	1865-07-05
55	110	111	55	816	Montenegro	Cetinje	1865-05-07
56	112	113	56	452	Latvia	Jelgava	1865-01-22
57	114	115	57	819	Chile	Ovalle	1865-04-28
58	116	117	58	924	Burundi	Rutana	1865-07-19
59	118	119	59	1021	Angola	Luau	1865-01-17
60	120	121	60	1027	Montenegro	Pljevlja	1865-02-10
61	122	123	61	619	Kyrgyzstan	Balykchy	1865-12-06
62	124	125	62	925	Ecuador	Cuenca	1865-06-19
63	126	127	63	462	Brazil	Igarapava	1865-02-05
64	128	129	64	1001	Kosovo	Ferizaj	1840-05-23
65	130	131	65	341	Guatemala	Mixco	1840-08-07
66	132	133	66	958	Norway	Kongsberg	1840-11-20
67	134	135	67	847	Sudan	Khartoum	1840-02-27
68	136	137	68	859	Tajikistan	Istaravshan	1840-03-22
69	138	139	69	155	Netherlands	Vianen	1840-07-24
70	140	141	70	1226	Cameroon	Lagdo	1840-07-02
71	142	143	71	459	Mongolia	Ulaangom	1840-12-13
72	144	145	72	906	Martinique	Ducos	1840-11-22
73	146	147	73	926	Namibia	Grootfontein	1840-08-15
74	148	149	74	852	Cameroon	Lagdo	1840-12-08
75	150	151	75	692	Mozambique	Tete	1840-06-16
76	152	153	76	462	Iceland	Akureyri	1840-04-28
77	154	155	77	501	Martinique	Ducos	1840-01-06
78	156	157	78	464	Belarus	Krychaw	1840-12-04
79	158	159	79	109	Eritrea	Asmara	1840-03-19
80	160	161	80	308	Angola	Luau	1840-03-03
81	162	163	81	1099	Ethiopia	Mekele	1840-11-02
82	164	165	82	1236	Seychelles	Victoria	1840-01-21
83	166	167	83	328	Netherlands	Venray	1840-01-02
84	168	169	84	145	Barbados	Bridgetown	1840-12-24
85	170	171	85	421	Niue	Alofi	1840-05-16
86	172	173	86	884	Malawi	Dedza	1840-04-09
87	174	175	87	1	Cyprus	Famagusta	1840-02-06
88	176	177	88	471	Georgia	Kobuleti	1840-09-11
89	178	179	89	106	Egypt	Hurghada	1840-09-07
90	180	181	90	1045	Armenia	Ararat	1840-07-20
91	182	183	91	1179	Austria	Innsbruck	1840-06-11
92	184	185	92	150	Tanzania	Shelui	1840-08-07
93	186	187	93	16	Macao	Macau	1840-08-05
94	188	189	94	783	Jordan	Aqaba	1840-11-07
95	190	191	95	1146	Niger	Matamey	1840-04-20
96	192	193	96	469	Algeria	Algiers	1840-05-24
97	194	195	97	892	Niger	Alaghsas	1840-01-24
98	196	197	98	759	Slovakia	Martin	1840-09-12
99	198	199	99	683	Vietnam	Pleiku	1840-02-09
100	200	201	100	495	Seychelles	Victoria	1840-04-19
101	202	203	101	895	Philippines	Cogan	1840-09-09
102	204	205	102	580	Suriname	Paramaribo	1840-06-19
103	206	207	103	815	Jamaica	Portmore	1840-01-17
104	208	209	104	143	Bahamas	Lucaya	1840-09-06
105	210	211	105	459	Somalia	Jamaame	1840-06-15
106	212	213	106	858	Chad	Kelo	1840-04-08
107	214	215	107	802	Singapore	Singapore	1840-03-23
108	216	217	108	831	Slovenia	Maribor	1840-02-12
109	218	219	109	1010	India	Godhra	1840-05-04
110	220	221	110	651	Sweden	Kalmar	1840-04-26
111	222	223	111	903	Norway	Kristiansand	1840-05-17
112	224	225	112	711	Mozambique	Maputo	1840-12-19
113	226	227	113	695	Paraguay	Nemby	1840-02-25
114	228	229	114	810	Peru	Pisco	1840-04-23
115	230	231	115	77	Gambia	Brikama	1840-03-25
116	232	233	116	1142	Lithuania	Kretinga	1840-02-03
117	234	235	117	332	Niger	Mayahi	1840-03-24
118	236	237	118	861	Mexico	Teoloyucan	1840-05-04
119	238	239	119	392	Lebanon	Djounie	1840-12-03
120	240	241	120	983	Sudan	Zalingei	1840-05-09
121	242	243	121	153	Cameroon	Bafoussam	1840-04-10
122	244	245	122	220	Bolivia	Villamontes	1840-04-04
123	246	247	123	930	Ireland	Naas	1840-03-04
124	248	249	124	852	Israel	Beersheba	1840-09-15
125	250	251	125	409	Kazakhstan	Temirtau	1840-06-12
126	252	253	126	844	Philippines	Burgos	1840-07-01
127	254	255	127	469	Tanzania	Tarime	1840-11-11
128	256	257	128	785	Netherlands	Vlaardingen	1815-10-15
129	258	259	129	606	Laos	Vangviang	1815-10-20
130	260	261	130	316	Mauritius	Vacoas	1815-12-10
131	262	263	131	245	Jamaica	Mandeville	1815-02-26
132	264	265	132	615	Cyprus	Protaras	1815-05-11
133	266	267	133	546	Nepal	Jaleswar	1815-11-12
134	268	269	134	50	Senegal	Kolda	1815-01-28
135	270	271	135	1031	Chad	Moussoro	1815-05-09
136	272	273	136	838	Guatemala	Colomba	1815-09-27
137	274	275	137	916	Dominica	Roseau	1815-11-01
138	276	277	138	412	Brazil	Alenquer	1815-12-28
139	278	279	139	663	Mali	San	1815-06-01
140	280	281	140	669	Cameroon	Akonolinga	1815-10-06
141	282	283	141	793	Tanzania	Magole	1815-10-05
142	284	285	142	459	Libya	Brak	1815-06-13
143	286	287	143	215	Brunei	Seria	1815-01-19
144	288	289	144	400	Ecuador	Calceta	1815-10-01
145	290	291	145	320	Samoa	Apia	1815-06-14
146	292	293	146	220	Macedonia	Brvenica	1815-01-14
147	294	295	147	1104	Indonesia	Rangkasbitung	1815-03-04
148	296	297	148	385	Turkey	Ceyhan	1815-12-11
149	298	299	149	343	Romania	Turda	1815-10-05
150	300	301	150	500	Germany	Vlotho	1815-03-20
151	302	303	151	499	Bahrain	Sitrah	1815-11-15
152	304	305	152	967	Lebanon	Beirut	1815-10-23
153	306	307	153	1032	Rwanda	Gisenyi	1815-10-04
154	308	309	154	199	Liberia	Bensonville	1815-10-25
155	310	311	155	84	Denmark	Hvidovre	1815-09-13
156	312	313	156	943	Turkmenistan	Balkanabat	1815-02-07
157	314	315	157	592	Algeria	Brezina	1815-07-11
158	316	317	158	309	India	Indi	1815-03-27
159	318	319	159	270	Belarus	Rahachow	1815-12-10
160	320	321	160	1022	Iceland	Akureyri	1815-10-04
161	322	323	161	252	Turkey	Biga	1815-09-17
162	324	325	162	82	Tunisia	Siliana	1815-12-26
163	326	327	163	1225	Azerbaijan	Aghsu	1815-05-20
164	328	329	164	53	Ghana	Apam	1815-06-08
165	330	331	165	673	Colombia	Sogamoso	1815-05-21
166	332	333	166	702	Niue	Alofi	1815-08-07
167	334	335	167	309	Egypt	Bilbays	1815-06-01
168	336	337	168	235	Spain	Jumilla	1815-11-08
169	338	339	169	557	Bermuda	Hamilton	1815-06-15
170	340	341	170	215	Gabon	Franceville	1815-04-19
171	342	343	171	323	Curacao	Willemstad	1815-05-03
172	344	345	172	385	Singapore	Singapore	1815-10-27
173	346	347	173	548	Malta	Mosta	1815-08-22
174	348	349	174	831	Cyprus	Kyrenia	1815-09-15
175	350	351	175	1146	Montenegro	Budva	1815-01-10
176	352	353	176	811	Djibouti	Tadjoura	1815-06-01
177	354	355	177	255	Martinique	Ducos	1815-10-27
178	356	357	178	289	Nigeria	Kabba	1815-07-25
179	358	359	179	265	Peru	Chongoyape	1815-09-12
180	360	361	180	358	Switzerland	Grenchen	1815-03-02
181	362	363	181	1100	Maldives	Male	1815-07-18
182	364	365	182	1006	Monaco	Monaco	1815-04-04
183	366	367	183	335	Venezuela	Coro	1815-06-02
184	368	369	184	147	Japan	Namie	1815-05-09
185	370	371	185	1246	Bahrain	Manama	1815-09-13
186	372	373	186	1074	Martinique	Ducos	1815-07-08
187	374	375	187	757	Azerbaijan	Nakhchivan	1815-11-24
188	376	377	188	335	Syria	Satita	1815-06-09
189	378	379	189	1250	Bahamas	Nassau	1815-03-05
190	380	381	190	170	Guyana	Linden	1815-12-26
191	382	383	191	1185	Russia	Glazov	1815-04-26
192	384	385	192	296	Uruguay	Trinidad	1815-02-28
193	386	387	193	481	Denmark	Farum	1815-08-14
194	388	389	194	1241	Guyana	Georgetown	1815-06-12
195	390	391	195	1044	Mayotte	Dzaoudzi	1815-11-02
196	392	393	196	773	Ethiopia	Nejo	1815-12-20
197	394	395	197	94	Panama	David	1815-02-22
198	396	397	198	964	Kosovo	Orahovac	1815-02-19
199	398	399	199	1151	Bangladesh	Azimpur	1815-01-11
200	400	401	200	1234	Norway	Fredrikstad	1815-05-02
201	402	403	201	554	Rwanda	Gisenyi	1815-06-07
202	404	405	202	1010	Greece	Chios	1815-11-02
203	406	407	203	777	Russia	Neftekumsk	1815-11-19
204	408	409	204	926	Switzerland	Meyrin	1815-04-06
205	410	411	205	507	Poland	Krapkowice	1815-11-20
206	412	413	206	905	Djibouti	Obock	1815-05-06
207	414	415	207	541	Greece	Vrilissia	1815-03-27
208	416	417	208	482	Bhutan	Tsirang	1815-04-22
209	418	419	209	287	Zambia	Siavonga	1815-02-08
210	420	421	210	430	Afghanistan	Karukh	1815-06-06
211	422	423	211	250	Tajikistan	Proletar	1815-05-14
212	424	425	212	330	China	Jiangguanchi	1815-06-09
213	426	427	213	326	Luxembourg	Luxembourg	1815-03-25
214	428	429	214	154	Japan	Mitsuke	1815-07-20
215	430	431	215	939	Denmark	Viborg	1815-10-26
216	432	433	216	1099	Gabon	Franceville	1815-12-09
217	434	435	217	1100	Suriname	Paramaribo	1815-12-24
218	436	437	218	854	Jamaica	Portmore	1815-01-26
219	438	439	219	811	Ecuador	Guaranda	1815-01-24
220	440	441	220	598	Singapore	Singapore	1815-12-08
221	442	443	221	1040	Colombia	Espinal	1815-02-16
222	444	445	222	1242	Lithuania	Palanga	1815-09-26
223	446	447	223	1037	Afghanistan	Ghormach	1815-12-03
224	448	449	224	287	Monaco	Monaco	1815-02-20
225	450	451	225	907	Iraq	Ramadi	1815-01-03
226	452	453	226	1230	Uganda	Kyenjojo	1815-03-19
227	454	455	227	370	Laos	Vangviang	1815-03-28
228	456	457	228	1026	Ethiopia	Dodola	1815-06-08
229	458	459	229	520	Luxembourg	Dudelange	1815-09-17
230	460	461	230	870	Mali	Sikasso	1815-02-09
231	462	463	231	470	Argentina	Quitilipi	1815-11-27
232	464	465	232	1168	Finland	Rauma	1815-03-28
233	466	467	233	1051	Bahamas	Lucaya	1815-07-26
234	468	469	234	10	Cuba	Cienfuegos	1815-11-05
235	470	471	235	638	Zimbabwe	Epworth	1815-01-25
236	472	473	236	149	Comoros	Moutsamoudou	1815-12-08
237	474	475	237	234	Palau	Melekeok	1815-06-02
238	476	477	238	349	Cameroon	Buea	1815-04-12
239	478	479	239	385	Bhutan	Phuntsholing	1815-03-22
240	480	481	240	735	Germany	Schwalbach	1815-11-20
241	482	483	241	219	Honduras	Siguatepeque	1815-12-08
242	484	485	242	3	Ukraine	Hlukhiv	1815-02-28
243	486	487	243	778	Haiti	Lenbe	1815-08-05
244	488	489	244	556	Tanzania	Arusha	1815-02-18
245	490	491	245	940	Mauritius	Vacoas	1815-06-03
246	492	493	246	1229	Poland	Choszczno	1815-05-28
247	494	495	247	1168	Chad	Pala	1815-03-10
248	496	497	248	673	Indonesia	Wanaraja	1815-03-23
249	498	499	249	1179	Bulgaria	Kyustendil	1815-12-10
250	500	\N	250	1113	Uganda	Entebbe	1815-08-01
251	\N	\N	251	399	India	Srivilliputhur	1815-01-01
252	\N	\N	252	952	Mayotte	Koungou	1815-03-03
253	\N	\N	253	355	Gibraltar	Gibraltar	1815-02-04
254	\N	\N	254	1113	Slovenia	Ptuj	1815-06-23
255	\N	\N	255	790	Swaziland	Lobamba	1815-07-25
256	\N	\N	256	685	Spain	Roses	1790-06-25
257	\N	\N	257	892	Bangladesh	Sarankhola	1790-01-12
258	\N	\N	258	825	Niger	Dogondoutchi	1790-11-08
259	\N	\N	259	469	Mayotte	Dzaoudzi	1790-11-11
260	\N	\N	260	9	Zambia	Monze	1790-05-28
261	\N	\N	261	348	Serbia	Senta	1790-06-06
262	\N	\N	262	846	Haiti	Jacmel	1790-10-27
263	\N	\N	263	921	Angola	Benguela	1790-01-21
264	\N	\N	264	831	Russia	Teykovo	1790-10-21
265	\N	\N	265	528	China	Zhaoyuan	1790-10-02
266	\N	\N	266	525	Bulgaria	Haskovo	1790-03-19
267	\N	\N	267	1030	Belgium	Lille	1790-06-05
268	\N	\N	268	1002	Rwanda	Byumba	1790-08-08
269	\N	\N	269	374	Suriname	Paramaribo	1790-12-15
270	\N	\N	270	148	Bhutan	Tsirang	1790-11-06
271	\N	\N	271	1140	Afghanistan	Gereshk	1790-03-23
272	\N	\N	272	149	Sweden	Karlskoga	1790-12-08
273	\N	\N	273	695	Bolivia	Riberalta	1790-08-24
274	\N	\N	274	182	Macedonia	Bogovinje	1790-07-18
275	\N	\N	275	659	Kosovo	Prizren	1790-09-17
276	\N	\N	276	963	Tuvalu	Funafuti	1790-05-01
277	\N	\N	277	1205	Rwanda	Byumba	1790-03-24
278	\N	\N	278	774	Gambia	Lamin	1790-12-12
279	\N	\N	279	912	Sudan	Omdurman	1790-08-28
280	\N	\N	280	906	Mexico	Salvatierra	1790-01-26
281	\N	\N	281	41	Jamaica	Linstead	1790-02-25
282	\N	\N	282	702	Iran	Khomeyn	1790-05-19
283	\N	\N	283	663	Kazakhstan	Lisakovsk	1790-01-23
284	\N	\N	284	415	Djibouti	Djibouti	1790-07-16
285	\N	\N	285	416	Palau	Melekeok	1790-03-03
286	\N	\N	286	987	Belarus	Mahilyow	1790-03-26
287	\N	\N	287	193	Iran	Yazd	1790-01-10
288	\N	\N	288	488	Liechtenstein	Vaduz	1790-06-10
289	\N	\N	289	1079	Ireland	Blanchardstown	1790-01-18
290	\N	\N	290	751	Suriname	Paramaribo	1790-02-07
291	\N	\N	291	481	Madagascar	Vohibinany	1790-02-14
292	\N	\N	292	690	Cuba	Mariel	1790-03-28
293	\N	\N	293	1187	Niger	Magaria	1790-12-10
294	\N	\N	294	815	Argentina	Barranqueras	1790-12-06
295	\N	\N	295	946	Ethiopia	Sebeta	1790-08-08
296	\N	\N	296	439	Azerbaijan	Barda	1790-05-06
297	\N	\N	297	754	Monaco	Monaco	1790-06-01
298	\N	\N	298	770	Ghana	Aburi	1790-09-26
299	\N	\N	299	412	Montenegro	Bar	1790-02-11
300	\N	\N	300	206	Comoros	Moroni	1790-12-26
301	\N	\N	301	687	Mauritania	Rosso	1790-11-08
302	\N	\N	302	591	Romania	Zimnicea	1790-05-21
303	\N	\N	303	110	Mayotte	Koungou	1790-02-09
304	\N	\N	304	318	Brazil	Itapeva	1790-08-08
305	\N	\N	305	511	Martinique	Ducos	1790-05-20
306	\N	\N	306	674	Seychelles	Victoria	1790-09-09
307	\N	\N	307	706	Germany	Herborn	1790-07-19
308	\N	\N	308	851	Seychelles	Victoria	1790-11-04
309	\N	\N	309	1147	Israel	Yehud	1790-10-16
310	\N	\N	310	384	Tuvalu	Funafuti	1790-08-19
311	\N	\N	311	790	Montserrat	Brades	1790-09-09
312	\N	\N	312	1024	Suriname	Lelydorp	1790-08-15
313	\N	\N	313	186	Luxembourg	Luxembourg	1790-09-20
314	\N	\N	314	816	Kosovo	Leposaviq	1790-08-17
315	\N	\N	315	512	Tunisia	Msaken	1790-09-23
316	\N	\N	316	489	Nauru	Yaren	1790-04-07
317	\N	\N	317	595	Haiti	Okap	1790-06-12
318	\N	\N	318	1121	Brazil	Castanhal	1790-04-05
319	\N	\N	319	50	Curacao	Willemstad	1790-01-08
320	\N	\N	320	1167	Mongolia	Dalandzadgad	1790-02-25
321	\N	\N	321	561	Zambia	Chililabombwe	1790-02-08
322	\N	\N	322	932	Kyrgyzstan	Karakol	1790-01-16
323	\N	\N	323	430	Australia	Mosman	1790-05-25
324	\N	\N	324	349	Guatemala	Coatepeque	1790-02-21
325	\N	\N	325	960	India	Bellampalli	1790-02-08
326	\N	\N	326	950	Swaziland	Mbabane	1790-08-26
327	\N	\N	327	1036	Uruguay	Carmelo	1790-11-11
328	\N	\N	328	685	Spain	Natahoyo	1790-02-25
329	\N	\N	329	777	Qatar	Doha	1790-10-11
330	\N	\N	330	257	Swaziland	Mbabane	1790-10-01
331	\N	\N	331	484	Austria	Hallein	1790-04-03
332	\N	\N	332	427	Afghanistan	Kabul	1790-06-12
333	\N	\N	333	1054	Kenya	Wajir	1790-10-27
334	\N	\N	334	402	Zambia	Livingstone	1790-02-26
335	\N	\N	335	270	Thailand	Chaiyaphum	1790-03-28
336	\N	\N	336	848	Togo	Kara	1790-02-18
337	\N	\N	337	1123	Tuvalu	Funafuti	1790-05-13
338	\N	\N	338	1045	Barbados	Bridgetown	1790-04-02
339	\N	\N	339	319	Togo	Dapaong	1790-11-27
340	\N	\N	340	7	Taiwan	Puli	1790-01-16
341	\N	\N	341	80	Zimbabwe	Marondera	1790-02-21
342	\N	\N	342	792	Belize	Belmopan	1790-12-01
343	\N	\N	343	815	France	Forbach	1790-11-20
344	\N	\N	344	499	Brazil	Piraju	1790-11-09
345	\N	\N	345	416	Nigeria	Geidam	1790-09-10
346	\N	\N	346	218	Serbia	Apatin	1790-05-16
347	\N	\N	347	69	Moldova	Cahul	1790-06-18
348	\N	\N	348	41	Iran	Qom	1790-01-14
349	\N	\N	349	992	Ukraine	Fastiv	1790-04-21
350	\N	\N	350	316	Maldives	Male	1790-10-16
351	\N	\N	351	1021	Liberia	Bensonville	1790-02-26
352	\N	\N	352	512	Rwanda	Cyangugu	1790-11-28
353	\N	\N	353	895	Sudan	Kosti	1790-05-10
354	\N	\N	354	967	Iraq	Kufa	1790-08-28
355	\N	\N	355	1167	Bhutan	Thimphu	1790-04-21
356	\N	\N	356	27	Austria	Kufstein	1790-04-19
357	\N	\N	357	250	Tanzania	Matiri	1790-11-28
358	\N	\N	358	196	Togo	Dapaong	1790-08-02
359	\N	\N	359	849	Zambia	Mbala	1790-02-19
360	\N	\N	360	1195	Spain	Melilla	1790-09-01
361	\N	\N	361	1123	Greenland	Nuuk	1790-07-15
362	\N	\N	362	1250	Martinique	Ducos	1790-11-24
363	\N	\N	363	837	Nigeria	Akure	1790-09-28
364	\N	\N	364	48	Maldives	Male	1790-12-03
365	\N	\N	365	696	China	Changsha	1790-12-05
366	\N	\N	366	51	Burundi	Makamba	1790-06-20
367	\N	\N	367	745	Macao	Macau	1790-09-01
368	\N	\N	368	296	Gambia	Bakau	1790-06-15
369	\N	\N	369	246	Norway	Halden	1790-10-27
370	\N	\N	370	690	Nigeria	Pankshin	1790-07-04
371	\N	\N	371	1151	Mayotte	Mamoudzou	1790-04-03
372	\N	\N	372	481	Palau	Melekeok	1790-11-03
373	\N	\N	373	286	Montserrat	Brades	1790-12-26
374	\N	\N	374	1247	Nauru	Yaren	1790-07-21
375	\N	\N	375	867	Morocco	Taounate	1790-03-01
376	\N	\N	376	696	Ireland	Dublin	1790-02-14
377	\N	\N	377	1109	Nicaragua	Tipitapa	1790-05-13
378	\N	\N	378	126	Uruguay	Melo	1790-12-01
379	\N	\N	379	827	Cambodia	Sihanoukville	1790-08-26
380	\N	\N	380	1040	Eritrea	Massawa	1790-11-02
381	\N	\N	381	1024	Denmark	Kalundborg	1790-01-04
382	\N	\N	382	676	Nicaragua	Boaco	1790-09-26
383	\N	\N	383	752	Mauritius	Triolet	1790-09-06
384	\N	\N	384	929	Ethiopia	Korem	1790-12-15
385	\N	\N	385	1029	Ethiopia	Dubti	1790-03-24
386	\N	\N	386	995	Morocco	Casablanca	1790-06-27
387	\N	\N	387	1106	Aruba	Angochi	1790-05-13
388	\N	\N	388	1238	Laos	Vangviang	1790-10-11
389	\N	\N	389	667	Laos	Phonsavan	1790-12-05
390	\N	\N	390	921	Mauritania	Zouerate	1790-10-12
391	\N	\N	391	40	Comoros	Moroni	1790-04-03
392	\N	\N	392	540	Azerbaijan	Shamkhor	1790-02-01
393	\N	\N	393	1200	Egypt	Juhaynah	1790-07-26
394	\N	\N	394	743	Austria	Leonding	1790-02-08
395	\N	\N	395	1211	Russia	Salekhard	1790-12-10
396	\N	\N	396	1112	Macao	Macau	1790-03-22
397	\N	\N	397	785	Denmark	Slagelse	1790-08-17
398	\N	\N	398	821	Nicaragua	Nandaime	1790-02-27
399	\N	\N	399	905	Maldives	Male	1790-02-09
400	\N	\N	400	988	Iran	Khvoy	1790-02-23
401	\N	\N	401	790	Indonesia	Cikarang	1790-07-01
402	\N	\N	402	1156	Moldova	Bender	1790-07-27
403	\N	\N	403	1053	Ukraine	Kreminna	1790-02-22
404	\N	\N	404	17	Pakistan	Haveli	1790-10-01
405	\N	\N	405	172	Morocco	Dakhla	1790-10-03
406	\N	\N	406	308	Romania	Alexandria	1790-07-02
407	\N	\N	407	542	Pitcairn	Adamstown	1790-04-10
408	\N	\N	408	559	India	Hukeri	1790-11-15
409	\N	\N	409	1104	Turkmenistan	Boldumsaz	1790-12-06
410	\N	\N	410	636	Iceland	Akureyri	1790-07-25
411	\N	\N	411	52	Thailand	Lamphun	1790-06-18
412	\N	\N	412	416	Belgium	Seraing	1790-01-20
413	\N	\N	413	1220	Lithuania	Naujamiestis	1790-07-09
414	\N	\N	414	230	Djibouti	Tadjoura	1790-05-28
415	\N	\N	415	1058	Ethiopia	Korem	1790-09-01
416	\N	\N	416	710	Israel	Lod	1790-06-21
417	\N	\N	417	410	Malta	Valletta	1790-10-23
418	\N	\N	418	101	Slovakia	Nitra	1790-08-09
419	\N	\N	419	1246	Peru	Chongoyape	1790-06-24
420	\N	\N	420	199	Bulgaria	Kardzhali	1790-12-26
421	\N	\N	421	206	Aruba	Babijn	1790-11-20
422	\N	\N	422	217	Tajikistan	Hisor	1790-08-05
423	\N	\N	423	30	Djibouti	Tadjoura	1790-07-23
424	\N	\N	424	676	Uzbekistan	Denov	1790-05-21
425	\N	\N	425	335	Albania	Fier	1790-08-11
426	\N	\N	426	507	France	Pontivy	1790-01-10
427	\N	\N	427	194	Nepal	Malangwa	1790-08-05
428	\N	\N	428	837	Japan	Akune	1790-06-22
429	\N	\N	429	3	Armenia	Hrazdan	1790-07-09
430	\N	\N	430	549	Niger	Matamey	1790-05-09
431	\N	\N	431	827	Morocco	Nador	1790-10-07
432	\N	\N	432	359	Norway	Horten	1790-05-24
433	\N	\N	433	314	Dominica	Roseau	1790-08-24
434	\N	\N	434	851	Greece	Vrilissia	1790-12-04
435	\N	\N	435	752	Lebanon	Baalbek	1790-08-14
436	\N	\N	436	780	Maldives	Male	1790-09-27
437	\N	\N	437	469	Martinique	Ducos	1790-10-23
438	\N	\N	438	724	Bangladesh	Bhola	1790-07-03
439	\N	\N	439	475	Mongolia	Erdenet	1790-12-24
440	\N	\N	440	447	Montenegro	Bar	1790-06-06
441	\N	\N	441	854	Mauritania	Aleg	1790-05-09
442	\N	\N	442	1175	Germany	Eppingen	1790-08-06
443	\N	\N	443	1074	Cyprus	Nicosia	1790-03-17
444	\N	\N	444	852	Lesotho	Mafeteng	1790-05-23
445	\N	\N	445	893	Jordan	Irbid	1790-03-06
446	\N	\N	446	565	Kenya	Garissa	1790-12-28
447	\N	\N	447	788	Chile	Rancagua	1790-03-06
448	\N	\N	448	666	Ecuador	Puyo	1790-06-13
449	\N	\N	449	633	Portugal	Loures	1790-02-22
450	\N	\N	450	941	Angola	Lobito	1790-01-03
451	\N	\N	451	389	Madagascar	Antsohimbondrona	1790-07-08
452	\N	\N	452	14	Norway	Horten	1790-08-23
453	\N	\N	453	844	Sweden	Sollentuna	1790-03-15
454	\N	\N	454	1121	Somalia	Baardheere	1790-03-01
455	\N	\N	455	936	Montserrat	Plymouth	1790-06-09
456	\N	\N	456	585	Dominica	Roseau	1790-02-15
457	\N	\N	457	486	Afghanistan	Khanabad	1790-09-07
458	\N	\N	458	649	Lithuania	Palanga	1790-11-28
459	\N	\N	459	166	Lithuania	Eiguliai	1790-02-18
460	\N	\N	460	244	Mali	Markala	1790-06-23
461	\N	\N	461	1139	Armenia	Gavarr	1790-10-23
462	\N	\N	462	1046	Uruguay	Maldonado	1790-12-24
463	\N	\N	463	420	Australia	Wollongong	1790-07-20
464	\N	\N	464	125	Tunisia	Zouila	1790-08-01
465	\N	\N	465	1234	Philippines	Ipil	1790-10-20
466	\N	\N	466	954	Serbia	Senta	1790-02-07
467	\N	\N	467	385	Belize	Belmopan	1790-02-18
468	\N	\N	468	472	Zambia	Siavonga	1790-12-11
469	\N	\N	469	452	Belarus	Mazyr	1790-03-27
470	\N	\N	470	1206	Tunisia	Kairouan	1790-05-01
471	\N	\N	471	343	Djibouti	Tadjoura	1790-08-07
472	\N	\N	472	1155	Hungary	Dabas	1790-04-11
473	\N	\N	473	1042	Maldives	Male	1790-08-10
474	\N	\N	474	852	Argentina	Esquina	1790-11-18
475	\N	\N	475	526	Laos	Phonsavan	1790-02-20
476	\N	\N	476	714	Rwanda	Gitarama	1790-09-24
477	\N	\N	477	1142	Fiji	Nadi	1790-12-17
478	\N	\N	478	57	Mongolia	Uliastay	1790-08-04
479	\N	\N	479	143	Yemen	Aden	1790-11-01
480	\N	\N	480	83	Ukraine	Vasylkiv	1790-02-24
481	\N	\N	481	126	Belize	Belmopan	1790-10-23
482	\N	\N	482	771	Nigeria	Nkpor	1790-05-22
483	\N	\N	483	1010	Uzbekistan	Toshloq	1790-09-04
484	\N	\N	484	834	Argentina	Allen	1790-08-08
485	\N	\N	485	1112	Turkey	Tosya	1790-10-04
486	\N	\N	486	969	Peru	Tacna	1790-10-12
487	\N	\N	487	1203	Cambodia	Kampot	1790-03-25
488	\N	\N	488	429	Martinique	Ducos	1790-09-22
489	\N	\N	489	181	Benin	Djougou	1790-09-19
490	\N	\N	490	2	Malta	Birkirkara	1790-08-02
491	\N	\N	491	591	Gabon	Koulamoutou	1790-05-28
492	\N	\N	492	178	Pitcairn	Adamstown	1790-11-18
493	\N	\N	493	799	Bulgaria	Velingrad	1790-02-20
494	\N	\N	494	699	Cameroon	Bafoussam	1790-03-12
495	\N	\N	495	567	Brunei	Seria	1790-08-07
496	\N	\N	496	98	Gibraltar	Gibraltar	1790-02-01
497	\N	\N	497	635	Sweden	Karlskoga	1790-02-12
498	\N	\N	498	265	Qatar	Doha	1790-06-24
499	\N	\N	499	917	Palau	Melekeok	1790-08-02
500	\N	\N	500	304	Afghanistan	Karukh	1790-01-09
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
1	939	5	2009-12-16
2	1041	6	2014-12-01
3	10	7	1991-02-20
4	559	8	2015-04-14
5	118	9	1967-03-16
6	1041	10	1982-10-20
7	391	11	1995-01-19
8	194	12	1973-11-14
9	580	13	1986-12-12
10	407	14	1969-08-14
11	99	15	2008-10-06
12	228	16	1942-01-10
13	807	17	1946-05-20
14	803	18	1968-03-03
15	552	19	1988-01-06
16	1224	20	1973-12-12
17	1205	21	1972-08-11
18	851	22	1970-05-02
19	595	23	1947-02-06
20	427	24	1948-07-04
21	1219	25	1970-05-02
22	676	26	1948-02-10
23	1233	27	1950-09-13
24	179	28	1965-11-23
25	367	29	1979-02-17
26	792	30	1957-03-18
27	493	31	1963-04-21
28	392	32	1960-02-03
29	131	33	1928-07-13
30	923	34	1961-09-05
31	289	35	1959-02-14
32	525	36	1943-10-15
33	434	37	1919-01-22
34	1169	38	1918-02-22
35	1175	39	1953-12-15
36	542	40	1941-06-27
37	1224	41	1958-10-08
38	7	42	1935-05-04
39	703	43	1962-08-18
40	796	44	1934-05-13
41	30	45	1919-07-07
42	1133	46	1965-07-14
43	141	47	1924-09-01
44	353	48	1949-09-23
45	355	49	1929-08-13
46	1142	50	1957-05-06
47	32	51	1941-05-07
48	499	52	1956-01-15
49	1190	53	1954-06-08
50	318	54	1942-12-17
51	585	55	1921-12-23
52	674	56	1932-08-18
53	445	57	1965-12-25
54	348	58	1948-05-12
55	629	59	1945-09-04
56	861	60	1950-12-11
57	48	61	1965-01-14
58	831	62	1938-03-01
59	36	63	1915-06-25
60	869	64	1909-05-07
61	12	65	1932-08-25
62	106	66	1925-01-19
63	590	67	1914-02-09
64	783	68	1919-01-13
65	1107	69	1926-03-06
66	957	70	1896-09-14
67	132	71	1908-07-15
68	952	72	1903-04-17
69	696	73	1927-08-05
70	358	74	1926-11-10
71	82	75	1935-06-03
72	1062	76	1924-11-05
73	1121	77	1914-01-23
74	153	78	1935-01-16
75	704	79	1911-05-22
76	1226	80	1922-05-06
77	167	81	1906-02-24
78	1242	82	1896-06-21
79	1218	83	1905-11-17
80	141	84	1913-04-21
81	332	85	1922-01-16
82	1234	86	1895-11-09
83	989	87	1921-08-27
84	1179	88	1919-06-16
85	977	89	1940-10-09
86	785	90	1925-02-12
87	898	91	1913-05-11
88	1226	92	1916-08-20
89	936	93	1938-06-14
90	726	94	1932-05-24
91	523	95	1910-12-27
92	239	96	1930-01-11
93	770	97	1915-10-01
94	364	98	1940-02-14
95	503	99	1926-06-19
96	128	100	1894-11-17
97	265	101	1921-10-28
98	117	102	1924-08-21
99	656	103	1924-11-27
100	27	104	1907-05-04
101	143	105	1892-06-23
102	697	106	1902-04-26
103	779	107	1939-12-07
104	1011	108	1900-11-28
105	849	109	1918-12-25
106	507	110	1914-03-24
107	757	111	1896-11-24
108	20	112	1915-10-14
109	156	113	1928-04-18
110	482	114	1925-03-25
111	816	115	1932-03-23
112	1018	116	1896-01-20
113	172	117	1914-11-09
114	1179	118	1926-08-23
115	618	119	1896-07-07
116	416	120	1899-06-11
117	518	121	1895-03-12
118	1079	122	1916-07-02
119	295	123	1891-08-17
120	1070	124	1912-09-25
121	1158	125	1899-05-28
122	677	126	1921-06-08
123	40	127	1901-07-19
124	919	128	1903-03-28
125	347	129	1902-11-24
126	239	130	1905-12-17
127	315	131	1871-05-23
128	364	132	1891-11-16
129	352	133	1874-02-19
130	277	134	1899-07-13
131	149	135	1909-08-11
132	883	136	1889-11-05
133	1012	137	1866-10-11
134	478	138	1867-06-03
135	564	139	1882-12-28
136	1100	140	1909-07-26
137	193	141	1881-07-10
138	892	142	1885-09-04
139	324	143	1912-05-17
140	561	144	1892-09-11
141	215	145	1880-04-21
142	980	146	1911-01-22
143	207	147	1870-04-13
144	390	148	1912-11-19
145	907	149	1885-04-02
146	141	150	1879-08-27
147	563	151	1880-08-24
148	519	152	1894-09-18
149	613	153	1867-01-18
150	1058	154	1903-06-08
151	1244	155	1877-04-12
152	690	156	1867-04-23
153	189	157	1874-05-20
154	392	158	1901-06-24
155	308	159	1908-10-19
156	969	160	1872-12-06
157	1245	161	1869-05-16
158	1145	162	1905-12-04
159	69	163	1901-01-13
160	711	164	1902-05-04
161	397	165	1895-12-16
162	1133	166	1905-09-07
163	148	167	1873-03-27
164	2	168	1905-02-17
165	1091	169	1866-08-08
166	94	170	1892-11-15
167	1022	171	1909-02-19
168	925	172	1873-06-09
169	606	173	1874-10-26
170	714	174	1900-06-14
171	1064	175	1891-03-12
172	921	176	1879-03-20
173	41	177	1866-10-18
174	995	178	1898-08-13
175	245	179	1915-07-10
176	940	180	1905-09-04
177	579	181	1887-08-26
178	318	182	1903-06-04
179	1171	183	1872-11-06
180	923	184	1872-01-13
181	170	185	1876-06-28
182	520	186	1874-02-03
183	539	187	1872-04-03
184	726	188	1911-11-04
185	642	189	1899-01-28
186	544	190	1879-03-17
187	301	191	1872-03-02
188	110	192	1898-01-17
189	299	193	1889-05-26
190	346	194	1894-04-05
191	677	195	1912-04-18
192	95	196	1868-09-28
193	754	197	1885-11-09
194	470	198	1892-05-23
195	520	199	1910-09-20
196	861	200	1909-02-16
197	480	201	1880-03-24
198	1021	202	1885-01-17
199	1097	203	1890-04-16
200	898	204	1879-01-14
201	713	205	1868-01-09
202	781	206	1893-12-25
203	919	207	1898-08-25
204	83	208	1901-08-20
205	536	209	1866-05-08
206	1109	210	1885-01-15
207	207	211	1902-02-27
208	172	212	1872-05-02
209	1043	213	1887-04-15
210	318	214	1909-09-28
211	336	215	1889-05-26
212	125	216	1915-12-07
213	695	217	1905-09-20
214	63	218	1895-07-03
215	153	219	1883-10-05
216	554	220	1871-06-19
217	1128	221	1896-10-07
218	414	222	1879-05-18
219	202	223	1872-10-10
220	767	224	1868-08-10
221	602	225	1877-04-04
222	1030	226	1883-02-15
223	639	227	1889-06-13
224	781	228	1908-07-12
225	1003	229	1892-04-02
226	807	230	1898-07-17
227	958	231	1882-05-04
228	748	232	1902-01-16
229	23	233	1873-12-12
230	92	234	1865-07-21
231	493	235	1914-03-26
232	397	236	1875-04-25
233	207	237	1892-10-04
234	312	238	1903-01-23
235	1212	239	1893-01-16
236	713	240	1907-01-19
237	459	241	1866-01-11
238	1024	242	1869-03-04
239	816	243	1891-07-23
240	1104	244	1908-12-25
241	1153	245	1908-07-06
242	713	246	1872-02-26
243	624	247	1873-01-19
244	418	248	1886-09-26
245	650	249	1902-11-06
246	1096	250	1872-07-14
247	869	251	1905-01-10
248	655	252	1910-12-16
249	1220	253	1876-03-05
250	923	254	1913-05-01
251	1127	255	1892-11-27
252	141	256	1884-10-21
253	542	257	1887-05-15
254	38	258	1881-03-24
255	475	259	1845-10-14
256	1121	260	1850-02-22
257	833	261	1868-04-06
258	78	262	1856-12-14
259	1004	263	1870-06-19
260	541	264	1890-08-14
261	1215	265	1889-09-10
262	1	266	1862-02-28
263	415	267	1869-12-17
264	355	268	1845-08-16
265	558	269	1887-10-21
266	624	270	1850-08-05
267	635	271	1885-04-16
268	58	272	1886-03-07
269	286	273	1851-12-16
270	1221	274	1853-07-10
271	234	275	1874-12-28
272	758	276	1878-08-17
273	103	277	1849-01-07
274	907	278	1848-11-09
275	539	279	1865-12-19
276	1221	280	1847-02-17
277	1193	281	1858-04-16
278	956	282	1844-05-10
279	924	283	1871-12-04
280	952	284	1850-05-24
281	1051	285	1865-05-08
282	872	286	1869-03-09
283	958	287	1890-03-18
284	760	288	1856-04-16
285	55	289	1875-11-04
286	860	290	1878-03-06
287	1208	291	1887-04-09
288	1236	292	1862-05-24
289	352	293	1866-02-05
290	860	294	1874-09-15
291	409	295	1868-09-06
292	814	296	1865-05-05
293	16	297	1890-08-12
294	1242	298	1865-07-14
295	413	299	1865-08-23
296	272	300	1843-11-24
297	123	301	1862-10-28
298	153	302	1840-08-11
299	444	303	1876-12-17
300	1236	304	1858-07-14
301	906	305	1864-08-25
302	430	306	1865-06-23
303	519	307	1859-02-04
304	368	308	1872-03-08
305	218	309	1878-04-28
306	650	310	1871-07-18
307	1155	311	1866-09-21
308	1077	312	1869-09-01
309	967	313	1879-12-15
310	27	314	1843-07-20
311	298	315	1885-01-21
312	846	316	1888-12-07
313	1123	317	1890-07-22
314	901	318	1890-06-17
315	234	319	1853-06-13
316	330	320	1877-09-24
317	840	321	1890-06-06
318	597	322	1876-04-28
319	1128	323	1875-08-07
320	152	324	1888-03-25
321	106	325	1854-10-02
322	353	326	1853-04-01
323	405	327	1883-09-15
324	3	328	1847-04-18
325	892	329	1887-08-04
326	97	330	1844-01-11
327	1098	331	1863-09-05
328	133	332	1855-04-28
329	92	333	1855-07-04
330	414	334	1870-07-11
331	453	335	1844-09-20
332	768	336	1885-10-24
333	921	337	1854-11-02
334	1070	338	1865-09-06
335	1190	339	1870-08-11
336	245	340	1880-09-14
337	131	341	1851-08-04
338	711	342	1882-06-15
339	36	343	1862-01-15
340	7	344	1869-01-28
341	682	345	1869-06-19
342	1103	346	1886-01-10
343	893	347	1847-05-18
344	827	348	1880-04-21
345	434	349	1854-02-15
346	369	350	1850-09-09
347	1146	351	1864-02-02
348	930	352	1882-09-24
349	7	353	1868-09-10
350	550	354	1868-03-05
351	1123	355	1871-11-20
352	1165	356	1856-02-28
353	957	357	1888-10-21
354	99	358	1863-11-08
355	562	359	1883-01-02
356	391	360	1855-09-01
357	1137	361	1890-02-12
358	1248	362	1889-07-15
359	949	363	1880-04-01
360	205	364	1884-04-01
361	239	365	1871-12-24
362	676	366	1861-05-23
363	472	367	1882-02-09
364	789	368	1843-05-05
365	559	369	1851-11-16
366	989	370	1866-12-12
367	99	371	1841-11-08
368	999	372	1853-05-12
369	841	373	1886-01-01
370	441	374	1846-09-20
371	308	375	1875-01-25
372	768	376	1847-10-11
373	36	377	1876-06-10
374	370	378	1849-06-14
375	547	379	1840-12-02
376	591	380	1883-02-05
377	1112	381	1848-12-14
378	826	382	1872-06-20
379	1067	383	1884-11-01
380	684	384	1864-10-25
381	1104	385	1881-11-06
382	117	386	1872-06-10
383	194	387	1883-01-03
384	992	388	1873-07-19
385	565	389	1841-10-21
386	367	390	1854-09-22
387	345	391	1885-07-07
388	348	392	1879-10-28
389	1227	393	1854-12-18
390	1006	394	1840-01-21
391	1151	395	1875-08-09
392	31	396	1869-07-13
393	997	397	1865-04-09
394	1179	398	1879-01-25
395	770	399	1860-02-16
396	905	400	1871-08-02
397	573	401	1851-03-03
398	742	402	1866-02-01
399	771	403	1864-11-21
400	758	404	1850-07-08
401	340	405	1877-01-19
402	557	406	1869-06-27
403	1052	407	1848-12-19
404	30	408	1847-04-12
405	126	409	1880-01-22
406	378	410	1889-10-07
407	151	411	1879-04-22
408	859	412	1850-07-15
409	635	413	1867-02-12
410	452	414	1852-09-23
411	60	415	1865-07-04
412	210	416	1873-10-15
413	395	417	1870-11-25
414	212	418	1884-02-24
415	1221	419	1865-03-06
416	918	420	1856-01-06
417	228	421	1848-05-12
418	303	422	1862-07-26
419	260	423	1845-09-14
420	1146	424	1870-04-28
421	314	425	1889-09-11
422	598	426	1844-08-09
423	262	427	1851-12-25
424	710	428	1866-11-16
425	847	429	1864-03-22
426	523	430	1845-02-12
427	1092	431	1862-03-08
428	869	432	1868-10-26
429	1037	433	1862-02-11
430	950	434	1850-02-22
431	29	435	1876-06-04
432	399	436	1873-08-21
433	885	437	1847-06-19
434	912	438	1888-12-23
435	1213	439	1844-01-15
436	622	440	1877-08-10
437	1168	441	1857-03-04
438	2	442	1855-06-21
439	150	443	1863-04-06
440	386	444	1843-06-05
441	38	445	1882-11-26
442	62	446	1885-08-16
443	361	447	1890-11-20
444	556	448	1844-11-04
445	699	449	1840-08-06
446	1068	450	1849-08-21
447	769	451	1855-11-10
448	941	452	1878-10-12
449	1185	453	1849-07-01
450	414	454	1855-07-19
451	939	455	1867-05-17
452	745	456	1874-12-07
453	407	457	1864-10-15
454	370	458	1846-04-03
455	1058	459	1862-11-06
456	1226	460	1861-10-01
457	644	461	1885-04-14
458	148	462	1866-12-04
459	702	463	1859-09-10
460	1153	464	1883-10-24
461	409	465	1846-11-24
462	1238	466	1841-09-10
463	1158	467	1854-07-13
464	519	468	1878-05-11
465	640	469	1890-03-28
466	871	470	1870-11-24
467	844	471	1848-12-21
468	156	472	1889-02-10
469	1212	473	1868-07-19
470	389	474	1856-10-01
471	552	475	1848-11-03
472	114	476	1849-07-25
473	386	477	1879-01-14
474	495	478	1855-02-11
475	235	479	1855-12-05
476	449	480	1859-03-21
477	167	481	1861-10-09
478	1140	482	1870-10-14
479	642	483	1889-04-27
480	768	484	1873-09-08
481	1037	485	1868-07-15
482	563	486	1846-04-19
483	1022	487	1873-01-02
484	346	488	1869-10-16
485	1225	489	1883-01-11
486	563	490	1848-09-08
487	478	491	1846-06-07
488	625	492	1852-10-18
489	591	493	1890-03-21
490	481	494	1862-03-15
491	1027	495	1881-05-02
492	493	496	1865-06-25
493	153	497	1878-07-28
494	481	498	1849-04-07
495	1226	499	1863-08-07
496	118	500	1846-05-07
\.


--
-- Data for Name: divorce_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorce_certificates (id, divorce_id, issue_date, issuer) FROM stdin;
1	1	2000-09-13	407
2	2	1973-12-16	645
3	3	1968-02-26	674
4	4	1954-12-12	1121
5	5	1952-04-19	683
6	6	1947-01-02	1136
7	7	1939-05-20	852
8	8	1918-07-08	604
9	9	1914-06-27	496
10	10	1915-11-16	338
11	11	1917-04-24	1025
12	12	1926-08-25	453
13	13	1897-06-08	687
14	14	1903-06-21	1084
15	15	1884-10-02	1210
16	16	1896-04-12	830
17	17	1892-07-12	577
18	18	1903-08-25	110
19	19	1902-01-12	447
20	20	1892-05-16	225
21	21	1900-11-04	936
22	22	1893-07-09	222
23	23	1883-07-23	624
24	24	1903-01-27	501
25	25	1898-12-21	277
26	26	1875-11-19	531
27	27	1866-05-23	180
28	28	1877-10-13	1006
29	29	1873-08-26	897
30	30	1872-03-10	1121
31	31	1882-05-20	995
32	32	1865-09-26	519
33	33	1870-02-04	943
34	34	1864-07-19	566
35	35	1865-04-25	208
36	36	1871-11-04	1241
37	37	1870-06-11	1080
38	38	1865-03-12	251
39	39	1873-09-04	525
40	40	1875-04-15	928
41	41	1871-01-15	1099
42	42	1867-01-16	694
43	43	1872-02-27	575
44	44	1883-06-13	311
45	45	1880-07-22	342
46	46	1863-05-03	189
47	47	1850-07-25	314
48	48	1848-09-14	1039
49	49	1834-07-06	630
50	50	1850-01-21	906
51	51	1843-07-17	1176
52	52	1846-09-08	2
53	53	1837-01-19	358
54	54	1851-04-05	215
55	55	1851-10-05	774
56	56	1840-07-28	900
57	57	1854-03-05	1060
58	58	1841-09-18	826
59	59	1851-09-21	19
60	60	1839-07-25	220
61	61	1836-10-24	1074
62	62	1839-09-28	337
63	63	1853-11-21	889
64	64	1847-03-20	1226
65	65	1858-03-13	906
66	66	1845-11-11	574
67	67	1851-02-14	338
68	68	1842-11-11	1213
69	69	1850-11-03	342
70	70	1843-11-24	1156
71	71	1838-08-23	234
72	72	1841-09-17	1122
73	73	1854-01-04	499
74	74	1851-08-07	684
75	75	1832-03-25	851
76	76	1852-05-27	430
77	77	1836-01-19	457
78	78	1847-06-19	598
79	79	1849-08-13	856
80	80	1851-06-06	242
81	81	1850-02-15	1204
82	82	1855-02-25	1154
83	83	1854-11-23	413
84	84	1850-11-25	242
85	85	1844-06-21	936
86	86	1840-05-14	453
87	87	1840-11-18	464
88	88	1819-03-24	802
89	89	1827-02-17	1003
90	90	1816-11-20	949
91	91	1821-01-07	1210
92	92	1813-12-16	218
93	93	1826-01-01	84
94	94	1820-11-08	77
95	95	1818-07-09	1190
96	96	1816-11-04	447
97	97	1814-01-08	103
98	98	1821-10-13	1214
99	99	1811-02-13	299
100	100	1818-06-18	622
101	101	1812-11-26	938
102	102	1827-02-06	1163
103	103	1818-02-21	638
104	104	1810-05-19	192
105	105	1812-08-05	41
106	106	1811-04-16	503
107	107	1810-11-20	486
108	108	1812-12-02	2
109	109	1817-02-21	586
110	110	1829-10-08	849
111	111	1829-09-20	976
112	112	1827-10-13	931
113	113	1824-10-22	180
114	114	1814-01-06	474
115	115	1826-03-28	425
116	116	1826-04-12	1161
117	117	1819-02-14	1233
118	118	1816-02-18	66
119	119	1821-11-17	61
120	120	1827-05-11	1198
121	121	1823-11-28	997
122	122	1815-01-26	506
123	123	1814-12-27	1213
124	124	1813-05-17	830
125	125	1822-05-22	46
126	126	1814-11-13	245
127	127	1821-10-16	1213
128	128	1819-03-13	445
129	129	1830-11-25	170
130	130	1827-10-25	921
131	131	1820-02-11	328
132	132	1816-01-20	66
133	133	1820-02-08	856
134	134	1816-04-09	303
135	135	1825-03-16	389
136	136	1831-02-04	554
137	137	1827-04-08	60
138	138	1815-02-26	854
139	139	1824-04-15	1031
140	140	1822-04-22	642
141	141	1813-09-28	941
142	142	1821-08-08	787
143	143	1810-02-21	918
144	144	1829-07-15	678
145	145	1826-09-08	473
146	146	1824-04-26	430
147	147	1828-04-11	931
148	148	1816-01-04	192
149	149	1810-02-27	389
150	150	1814-04-06	291
151	151	1824-03-26	529
152	152	1825-12-22	941
153	153	1809-11-09	729
154	154	1829-07-16	302
155	155	1815-05-16	349
156	156	1826-12-03	318
157	157	1813-09-14	168
158	158	1812-10-25	1094
159	159	1823-10-04	581
160	160	1810-10-06	31
161	161	1821-05-27	377
162	162	1822-02-04	1228
163	163	1813-06-07	642
164	164	1827-12-07	1013
165	165	1818-02-09	1191
166	166	1810-02-19	1084
167	167	1808-02-04	922
168	168	1823-01-11	1212
169	169	1809-06-14	501
170	170	1817-05-26	117
171	171	1814-07-10	425
172	172	1824-08-21	1055
173	173	1821-05-17	139
174	174	1829-10-12	277
175	175	1823-11-14	772
176	176	1812-01-04	342
\.


--
-- Data for Name: divorces; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorces (id, marriage_id, divorce_date) FROM stdin;
1	1	2000-09-13
2	2	1973-12-16
3	3	1968-02-26
4	4	1954-12-12
5	5	1952-04-19
6	6	1947-01-02
7	7	1939-05-20
8	9	1918-07-08
9	10	1914-06-27
10	11	1915-11-16
11	13	1917-04-24
12	15	1926-08-25
13	16	1897-06-08
14	17	1903-06-21
15	18	1884-10-02
16	20	1896-04-12
17	22	1892-07-12
18	23	1903-08-25
19	24	1902-01-12
20	25	1892-05-16
21	26	1900-11-04
22	27	1893-07-09
23	29	1883-07-23
24	30	1903-01-27
25	31	1898-12-21
26	32	1875-11-19
27	33	1866-05-23
28	34	1877-10-13
29	37	1873-08-26
30	39	1872-03-10
31	40	1882-05-20
32	42	1865-09-26
33	43	1870-02-04
34	44	1864-07-19
35	45	1865-04-25
36	46	1871-11-04
37	47	1870-06-11
38	48	1865-03-12
39	51	1873-09-04
40	52	1875-04-15
41	54	1871-01-15
42	56	1867-01-16
43	58	1872-02-27
44	59	1883-06-13
45	61	1880-07-22
46	62	1863-05-03
47	64	1850-07-25
48	65	1848-09-14
49	67	1834-07-06
50	69	1850-01-21
51	71	1843-07-17
52	72	1846-09-08
53	73	1837-01-19
54	74	1851-04-05
55	76	1851-10-05
56	77	1840-07-28
57	78	1854-03-05
58	81	1841-09-18
59	82	1851-09-21
60	87	1839-07-25
61	89	1836-10-24
62	93	1839-09-28
63	95	1853-11-21
64	97	1847-03-20
65	99	1858-03-13
66	101	1845-11-11
67	102	1851-02-14
68	103	1842-11-11
69	104	1850-11-03
70	106	1843-11-24
71	108	1838-08-23
72	110	1841-09-17
73	111	1854-01-04
74	112	1851-08-07
75	113	1832-03-25
76	115	1852-05-27
77	116	1836-01-19
78	117	1847-06-19
79	118	1849-08-13
80	119	1851-06-06
81	120	1850-02-15
82	121	1855-02-25
83	122	1854-11-23
84	123	1850-11-25
85	124	1844-06-21
86	125	1840-05-14
87	126	1840-11-18
88	128	1819-03-24
89	129	1827-02-17
90	130	1816-11-20
91	131	1821-01-07
92	133	1813-12-16
93	135	1826-01-01
94	136	1820-11-08
95	137	1818-07-09
96	138	1816-11-04
97	139	1814-01-08
98	140	1821-10-13
99	141	1811-02-13
100	143	1818-06-18
101	144	1812-11-26
102	145	1827-02-06
103	146	1818-02-21
104	147	1810-05-19
105	148	1812-08-05
106	149	1811-04-16
107	150	1810-11-20
108	151	1812-12-02
109	152	1817-02-21
110	153	1829-10-08
111	154	1829-09-20
112	155	1827-10-13
113	156	1824-10-22
114	157	1814-01-06
115	158	1826-03-28
116	159	1826-04-12
117	160	1819-02-14
118	161	1816-02-18
119	162	1821-11-17
120	164	1827-05-11
121	165	1823-11-28
122	166	1815-01-26
123	167	1814-12-27
124	168	1813-05-17
125	169	1822-05-22
126	170	1814-11-13
127	171	1821-10-16
128	172	1819-03-13
129	174	1830-11-25
130	176	1827-10-25
131	177	1820-02-11
132	178	1816-01-20
133	179	1820-02-08
134	180	1816-04-09
135	182	1825-03-16
136	184	1831-02-04
137	186	1827-04-08
138	188	1815-02-26
139	189	1824-04-15
140	191	1822-04-22
141	192	1813-09-28
142	193	1821-08-08
143	195	1810-02-21
144	196	1829-07-15
145	197	1826-09-08
146	200	1824-04-26
147	201	1828-04-11
148	202	1816-01-04
149	204	1810-02-27
150	205	1814-04-06
151	207	1824-03-26
152	208	1825-12-22
153	209	1809-11-09
154	210	1829-07-16
155	215	1815-05-16
156	218	1826-12-03
157	219	1813-09-14
158	220	1812-10-25
159	221	1823-10-04
160	223	1810-10-06
161	225	1821-05-27
162	226	1822-02-04
163	230	1813-06-07
164	232	1827-12-07
165	233	1818-02-09
166	234	1810-02-19
167	240	1808-02-04
168	241	1823-01-11
169	242	1809-06-14
170	243	1817-05-26
171	244	1814-07-10
172	245	1824-08-21
173	246	1821-05-17
174	247	1829-10-12
175	248	1823-11-14
176	249	1812-01-04
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
1	D1	179	803	1910-02-24	1920-02-24
2	D	310	512	1866-02-25	1876-02-25
3	B1	224	339	1984-07-02	1994-07-02
4	B1	184	1067	1836-03-19	1846-03-19
5	B1	59	790	1895-12-15	1905-12-15
6	B1	259	1196	1858-07-01	1868-07-01
7	C	491	215	2013-08-09	2023-08-09
8	D1	356	861	1867-05-01	1877-05-01
9	C1	321	1151	2020-10-06	2030-10-06
10	B1	495	191	1848-09-26	1858-09-26
11	B1	451	568	1835-08-06	1845-08-06
12	D	120	176	1892-06-15	1902-06-15
13	C1	336	1248	2019-10-03	2029-10-03
14	D	469	763	1959-04-11	1969-04-11
15	C	409	25	1965-02-28	1975-02-28
16	D1	380	775	1878-09-27	1888-09-27
17	C1	206	1133	1901-09-17	1911-09-17
18	A	129	599	1941-08-28	1951-08-28
19	B1	33	1092	1895-04-05	1905-04-05
20	B1	313	1036	2008-05-14	2018-05-14
21	C1	449	856	1856-04-24	1866-04-24
22	D1	292	1219	1871-12-05	1881-12-05
23	B1	210	649	1970-08-20	1980-08-20
24	A	164	650	2013-04-16	2023-04-16
25	D	400	1158	1915-10-27	1925-10-27
26	A	448	443	1950-04-24	1960-04-24
27	D1	307	372	1839-12-21	1849-12-21
28	D	498	476	1845-04-01	1855-04-01
29	D1	492	777	1825-07-05	1835-07-05
30	A	471	275	1916-02-07	1926-02-07
31	D1	130	1099	1922-10-01	1932-10-01
32	D	221	1040	1837-09-26	1847-09-26
33	D	331	159	1835-09-16	1845-09-16
34	C1	72	518	1951-04-23	1961-04-23
35	D1	99	140	2002-11-14	2012-11-14
36	B1	160	494	1901-04-11	1911-04-11
37	C	478	125	1959-05-04	1969-05-04
38	D	253	176	1922-06-04	1932-06-04
39	B1	375	541	1828-03-28	1838-03-28
40	C1	194	461	2015-01-22	2025-01-22
41	B1	386	767	1963-01-27	1973-01-27
42	C1	248	340	1910-09-24	1920-09-24
43	C	373	396	1937-08-08	1947-08-08
44	D1	394	1229	1941-08-14	1951-08-14
45	D1	112	959	1922-07-03	1932-07-03
46	D	416	53	1907-03-21	1917-03-21
47	B1	43	622	2021-07-17	2031-07-17
48	C1	173	804	1985-06-07	1995-06-07
49	B1	152	792	1931-08-14	1941-08-14
50	C1	243	1148	2022-07-17	2032-07-17
51	D	336	1219	1945-02-07	1955-02-07
52	C1	179	1247	1985-04-14	1995-04-14
53	B1	283	934	1869-08-07	1879-08-07
54	C	337	733	1966-05-27	1976-05-27
55	A	304	57	1881-02-08	1891-02-08
56	B1	170	696	1857-12-27	1867-12-27
57	D1	457	1070	1884-05-13	1894-05-13
58	C1	120	923	1948-07-11	1958-07-11
59	B1	87	234	1889-06-24	1899-06-24
60	D	415	1131	1919-01-10	1929-01-10
61	B1	115	1057	1862-11-24	1872-11-24
62	D	283	550	1999-05-07	2009-05-07
63	C	180	128	1926-03-19	1936-03-19
64	A	133	1238	2015-01-15	2025-01-15
65	B1	191	816	1834-02-21	1844-02-21
66	D	237	684	1880-10-16	1890-10-16
67	A	22	724	1978-04-11	1988-04-11
68	C1	195	735	1971-03-17	1981-03-17
69	D1	175	136	1901-08-14	1911-08-14
70	D1	318	836	1935-12-15	1945-12-15
71	C1	390	655	1819-10-11	1829-10-11
72	C1	460	1227	1959-08-03	1969-08-03
73	D	145	25	1876-02-17	1886-02-17
74	C	430	220	1838-11-18	1848-11-18
75	B1	397	278	1953-05-28	1963-05-28
76	B1	342	963	1959-11-18	1969-11-18
77	A	265	316	1969-01-15	1979-01-15
78	B1	100	814	1963-03-09	1973-03-09
79	C	68	852	1925-07-28	1935-07-28
80	C1	329	1158	1884-12-28	1894-12-28
81	D1	226	955	2023-09-27	2033-09-27
82	C1	370	1181	1858-02-13	1868-02-13
83	C	256	347	1981-08-05	1991-08-05
84	A	380	613	1891-10-10	1901-10-10
85	B1	247	549	1888-06-28	1898-06-28
86	C1	267	292	1974-09-04	1984-09-04
87	B1	328	308	1951-06-21	1961-06-21
88	D1	148	959	1964-12-19	1974-12-19
89	C	285	768	1960-04-08	1970-04-08
90	C	153	876	1870-09-04	1880-09-04
91	B1	452	225	1971-07-25	1981-07-25
92	C	108	1175	1978-02-22	1988-02-22
93	C	445	1072	1994-05-22	2004-05-22
94	D1	194	328	1975-06-02	1985-06-02
95	A	442	384	1861-03-09	1871-03-09
96	A	37	1167	1889-03-27	1899-03-27
97	D1	231	888	1958-10-21	1968-10-21
98	D1	319	712	1997-09-27	2007-09-27
99	C	127	1243	1983-11-16	1993-11-16
100	D1	58	140	1895-09-24	1905-09-24
101	D	349	991	1815-05-28	1825-05-28
102	C	185	936	1864-01-28	1874-01-28
103	D1	208	416	1850-07-11	1860-07-11
104	D1	364	331	1871-05-25	1881-05-25
105	B1	133	91	1883-11-21	1893-11-21
106	A	12	1230	1979-06-01	1989-06-01
107	C	337	158	1926-05-20	1936-05-20
108	C	493	709	1841-02-19	1851-02-19
109	A	11	451	1967-05-02	1977-05-02
110	D1	434	451	1972-05-11	1982-05-11
111	A	352	1189	1911-06-26	1921-06-26
112	D1	234	635	1946-05-05	1956-05-05
113	C1	196	1080	1864-11-02	1874-11-02
114	D	496	750	1970-02-15	1980-02-15
115	B1	312	941	1815-08-02	1825-08-02
116	D	238	187	2021-12-16	2031-12-16
117	C1	311	1106	2001-07-02	2011-07-02
118	C1	194	12	1986-02-19	1996-02-19
119	C1	328	245	1833-01-24	1843-01-24
120	C1	134	871	1995-05-12	2005-05-12
121	D	182	994	1963-04-18	1973-04-18
122	B1	316	406	1892-06-20	1902-06-20
123	A	399	388	1909-05-11	1919-05-11
124	C1	375	722	1906-05-23	1916-05-23
125	C	216	899	1961-10-22	1971-10-22
126	B1	302	1240	1912-07-12	1922-07-12
127	D	113	931	1900-09-18	1910-09-18
128	C1	278	285	1860-07-03	1870-07-03
129	A	359	1180	2007-12-13	2017-12-13
130	B1	155	30	1898-02-23	1908-02-23
131	C1	251	853	1973-12-26	1983-12-26
132	D	18	799	1972-08-19	1982-08-19
133	C	221	602	1926-10-17	1936-10-17
134	C1	149	899	1877-07-09	1887-07-09
135	B1	382	558	1915-01-24	1925-01-24
136	D	345	586	1918-01-18	1928-01-18
137	D1	203	614	1896-03-18	1906-03-18
138	A	458	62	2018-07-16	2028-07-16
139	D	348	1178	1945-08-24	1955-08-24
140	C	481	119	2002-05-01	2012-05-01
141	D1	453	416	1936-11-16	1946-11-16
142	B1	262	603	1883-01-28	1893-01-28
143	D	204	663	1838-03-26	1848-03-26
144	C	413	233	1940-10-12	1950-10-12
145	D1	350	923	1816-04-21	1826-04-21
146	C1	448	1214	1857-12-28	1867-12-28
147	A	248	385	1910-02-20	1920-02-20
148	D	415	495	1846-01-05	1856-01-05
149	D1	15	1074	2014-07-22	2024-07-22
150	D1	154	511	1880-03-06	1890-03-06
151	D1	4	433	1972-08-06	1982-08-06
152	B1	326	374	1884-01-06	1894-01-06
153	C1	251	758	1961-02-22	1971-02-22
154	A	469	229	1987-07-20	1997-07-20
155	D	384	723	1968-02-03	1978-02-03
156	C	8	437	1995-12-04	2005-12-04
157	C1	74	604	1983-05-04	1993-05-04
158	A	352	1102	1854-02-26	1864-02-26
159	A	8	739	1972-01-28	1982-01-28
160	C1	158	926	2000-08-17	2010-08-17
161	A	320	921	2009-09-08	2019-09-08
162	C	70	510	1959-12-11	1969-12-11
163	D1	28	1193	1922-03-04	1932-03-04
164	D	262	10	1855-07-10	1865-07-10
165	D1	441	663	1846-10-28	1856-10-28
166	C1	23	158	2011-12-10	2021-12-10
167	D1	384	1131	1856-09-05	1866-09-05
168	B1	253	167	1947-03-10	1957-03-10
169	D1	319	172	1908-12-14	1918-12-14
170	C1	366	195	1969-09-23	1979-09-23
171	C1	489	995	1833-06-02	1843-06-02
172	A	381	640	1924-02-01	1934-02-01
173	D	319	74	1992-10-23	2002-10-23
174	D1	18	34	1916-04-12	1926-04-12
175	C1	194	266	1875-01-23	1885-01-23
176	A	341	91	1860-03-14	1870-03-14
177	C	416	1168	1994-05-28	2004-05-28
178	B1	451	1102	1882-09-10	1892-09-10
179	C1	196	897	1839-02-15	1849-02-15
180	D1	63	1053	1958-03-21	1968-03-21
181	D	470	1250	2010-04-25	2020-04-25
182	C	217	957	1919-09-26	1929-09-26
183	D	72	904	1866-07-16	1876-07-16
184	C	146	1067	1883-04-06	1893-04-06
185	C1	456	985	1949-02-13	1959-02-13
186	D1	264	497	1975-08-25	1985-08-25
187	B1	50	225	1906-03-24	1916-03-24
188	A	250	511	2004-05-12	2014-05-12
189	D	338	253	1912-07-19	1922-07-19
190	A	431	426	1830-12-02	1840-12-02
191	C1	164	252	1976-04-11	1986-04-11
192	D1	159	21	1967-01-25	1977-01-25
193	C1	162	648	1923-06-11	1933-06-11
194	C1	121	652	1900-02-15	1910-02-15
195	C	406	743	1895-01-18	1905-01-18
196	D	411	488	1963-10-28	1973-10-28
197	A	68	646	1895-12-04	1905-12-04
198	A	212	1115	1915-03-24	1925-03-24
199	A	97	1137	2020-08-24	2030-08-24
200	D	239	1181	1885-01-25	1895-01-25
\.


--
-- Data for Name: educational_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificates (id, issuer, holder, issue_date, kind) FROM stdin;
1	22	1	2004-09-06	1
2	39	1	2004-12-11	3
3	23	3	1982-03-15	1
4	22	3	1980-05-20	2
5	30	4	1954-10-12	1
6	25	4	1954-02-07	2
7	16	4	1956-09-14	5
8	29	5	1954-05-21	1
9	21	5	1954-03-19	2
10	24	6	1955-04-27	1
11	38	6	1956-01-03	3
12	20	6	1954-09-01	6
13	24	7	1956-03-09	1
14	40	7	1954-02-12	3
15	26	9	1929-11-12	1
16	36	9	1931-09-28	3
17	29	10	1929-02-19	1
18	29	11	1930-06-15	1
19	40	11	1932-10-13	3
20	26	12	1929-08-01	1
21	25	12	1932-08-09	2
22	30	13	1932-09-02	1
23	32	13	1929-11-03	3
24	9	13	1932-08-09	7
25	27	14	1930-10-21	1
26	21	14	1932-10-21	2
27	28	15	1929-03-11	1
28	40	15	1931-09-12	3
29	19	15	1930-02-10	7
30	29	16	1907-10-06	1
31	24	16	1906-01-03	2
32	22	18	1907-06-08	1
33	38	18	1905-07-17	3
34	22	19	1904-01-14	1
35	36	19	1904-09-10	3
36	3	19	1906-06-12	7
37	24	20	1905-05-09	1
38	39	20	1907-05-26	3
39	29	21	1906-11-23	1
40	28	22	1904-03-12	1
41	37	22	1904-01-08	3
42	22	24	1905-03-15	1
43	22	25	1904-07-23	1
44	26	25	1904-02-25	2
45	6	25	1906-09-20	4
46	30	26	1907-09-28	1
47	29	26	1906-11-12	2
48	10	26	1907-07-25	5
49	26	27	1906-05-28	1
50	23	27	1905-10-10	2
51	23	28	1907-03-11	1
52	23	28	1905-07-26	2
53	2	28	1907-02-05	5
54	29	30	1906-11-08	1
55	29	30	1904-06-03	2
56	7	30	1906-02-10	4
57	29	31	1906-10-04	1
58	26	31	1904-03-18	2
59	1	31	1906-02-19	4
60	29	32	1881-02-04	1
61	23	32	1882-07-07	2
62	5	32	1879-04-20	5
63	24	33	1880-01-26	1
64	31	33	1882-08-14	3
65	5	33	1880-08-24	7
66	23	34	1881-01-15	1
67	27	36	1879-06-01	1
68	27	36	1881-03-04	2
69	24	37	1880-03-08	1
70	28	39	1879-07-05	1
71	25	40	1881-08-13	1
72	29	41	1882-12-13	1
73	28	41	1882-08-28	2
74	28	42	1882-12-04	1
75	27	44	1882-01-03	1
76	31	44	1880-06-13	3
77	4	44	1879-11-26	7
78	21	45	1880-01-24	1
79	23	45	1880-10-28	2
80	5	45	1882-12-07	4
81	21	46	1880-04-02	1
82	30	46	1882-12-27	2
83	12	46	1882-01-16	4
84	23	48	1880-11-04	1
85	38	48	1882-04-25	3
86	18	48	1881-12-28	6
87	25	49	1881-07-24	1
88	38	49	1881-04-02	3
89	21	50	1882-03-07	1
90	35	50	1879-08-28	3
91	22	51	1881-06-25	1
92	30	52	1879-11-25	1
93	31	52	1879-12-08	3
94	6	52	1881-09-12	6
95	25	55	1881-04-02	1
96	35	55	1879-11-17	3
97	3	55	1879-05-08	6
98	24	56	1880-11-04	1
99	23	56	1882-09-16	2
100	18	56	1882-03-27	4
101	26	57	1882-10-09	1
102	27	58	1879-02-25	1
103	32	58	1879-03-20	3
104	24	59	1879-12-23	1
105	26	61	1882-07-13	1
106	26	62	1880-10-14	1
107	24	62	1882-07-12	2
108	26	63	1880-08-17	1
109	40	63	1879-08-27	3
110	27	64	1856-06-19	1
111	22	64	1854-02-16	2
112	12	64	1854-07-11	4
113	26	65	1856-08-21	1
114	21	66	1856-08-10	1
115	22	69	1856-07-03	1
116	21	69	1857-09-21	2
117	10	69	1854-07-22	4
118	26	70	1857-02-18	1
119	34	70	1855-02-27	3
120	24	71	1856-05-10	1
121	25	71	1856-11-04	2
122	22	72	1857-01-03	1
123	25	73	1855-12-21	1
124	24	73	1854-11-15	2
125	24	74	1856-05-09	1
126	27	75	1856-12-08	1
127	29	75	1855-03-16	2
128	29	76	1854-08-07	1
129	28	76	1855-05-20	2
130	2	76	1857-04-15	5
131	21	77	1857-03-11	1
132	26	79	1855-06-01	1
133	36	79	1854-10-03	3
134	29	81	1854-12-11	1
135	30	81	1855-06-20	2
136	5	81	1855-03-13	5
137	30	82	1857-02-09	1
138	22	82	1856-07-24	2
139	26	83	1854-05-14	1
140	30	83	1855-08-26	2
141	27	85	1855-07-19	1
142	28	85	1854-09-03	2
143	21	86	1854-09-11	1
144	32	86	1855-01-11	3
145	7	86	1855-09-13	7
146	27	87	1854-08-17	1
147	35	87	1854-07-23	3
148	20	87	1856-06-13	7
149	24	88	1854-12-01	1
150	28	88	1855-03-02	2
151	13	88	1855-03-21	4
152	21	89	1857-11-26	1
153	33	89	1857-08-21	3
154	26	91	1856-04-13	1
155	25	93	1857-06-08	1
156	28	93	1854-05-20	2
157	25	94	1855-07-17	1
158	27	94	1855-01-28	2
159	23	95	1855-02-05	1
160	39	95	1855-04-15	3
161	25	96	1855-03-09	1
162	27	97	1856-10-21	1
163	30	98	1855-06-03	1
164	31	98	1857-09-19	3
165	4	98	1857-09-21	7
166	27	99	1856-09-21	1
167	27	100	1854-08-03	1
168	24	100	1856-03-28	2
169	25	101	1854-03-06	1
170	22	104	1854-10-22	1
171	26	104	1854-09-07	2
172	18	104	1855-08-26	4
173	22	105	1856-01-08	1
174	33	105	1855-07-22	3
175	20	105	1856-02-04	6
176	25	108	1857-08-04	1
177	22	109	1856-03-26	1
178	30	110	1855-01-03	1
179	30	111	1855-06-26	1
180	29	112	1856-10-13	1
181	21	114	1854-10-24	1
182	27	114	1857-11-20	2
183	27	116	1855-12-24	1
184	26	117	1854-06-05	1
185	28	119	1854-04-15	1
186	22	119	1855-04-13	2
187	18	119	1856-02-20	5
188	26	121	1855-06-24	1
189	26	122	1855-11-06	1
190	36	122	1857-11-21	3
191	18	122	1857-10-26	6
192	21	124	1857-11-01	1
193	21	126	1856-02-09	1
194	22	128	1831-07-28	1
195	24	128	1829-10-02	2
196	30	129	1832-03-15	1
197	29	132	1830-10-14	1
198	31	132	1832-10-23	3
199	14	132	1832-04-17	7
200	28	133	1831-11-10	1
201	29	135	1830-05-14	1
202	30	135	1830-06-04	2
203	2	135	1829-08-01	4
204	29	136	1829-09-28	1
205	40	136	1831-07-21	3
206	18	136	1830-03-27	7
207	22	137	1832-10-18	1
208	27	137	1831-02-18	2
209	24	139	1831-08-03	1
210	21	139	1830-11-25	2
211	25	140	1831-12-23	1
212	33	140	1831-08-02	3
213	14	140	1829-05-24	6
214	28	141	1829-05-11	1
215	39	141	1829-07-16	3
216	12	141	1831-09-12	6
217	28	142	1830-08-17	1
218	36	142	1832-02-10	3
219	30	143	1829-05-05	1
220	37	143	1832-03-03	3
221	20	143	1831-05-12	7
222	27	146	1831-07-01	1
223	37	146	1829-11-07	3
224	15	146	1831-06-10	7
225	25	147	1829-11-12	1
226	23	149	1832-12-10	1
227	36	149	1829-10-05	3
228	30	150	1829-06-07	1
229	21	150	1831-05-25	2
230	26	152	1830-10-15	1
231	31	152	1831-08-03	3
232	29	153	1831-08-21	1
233	30	155	1830-02-16	1
234	23	155	1831-09-12	2
235	30	156	1832-05-23	1
236	23	157	1829-05-28	1
237	24	157	1830-12-19	2
238	14	157	1831-03-08	4
239	22	158	1829-03-15	1
240	23	158	1832-11-07	2
241	11	158	1829-07-11	4
242	21	159	1829-09-26	1
243	22	159	1829-01-20	2
244	27	160	1831-06-23	1
245	23	161	1832-07-23	1
246	37	161	1830-05-25	3
247	13	161	1829-03-14	6
248	24	162	1830-03-27	1
249	27	162	1830-03-09	2
250	28	163	1830-06-03	1
251	21	164	1829-01-15	1
252	28	165	1831-04-03	1
253	27	167	1832-05-03	1
254	38	167	1830-07-15	3
255	29	168	1832-06-20	1
256	22	168	1831-04-22	2
257	2	168	1832-04-10	4
258	22	169	1832-03-03	1
259	28	170	1829-06-05	1
260	36	170	1832-10-18	3
261	21	171	1830-04-27	1
262	29	172	1830-01-17	1
263	38	172	1829-03-07	3
264	12	172	1829-01-10	6
265	28	173	1832-12-06	1
266	30	174	1831-10-16	1
267	39	174	1830-06-27	3
268	30	175	1831-07-18	1
269	26	177	1829-12-20	1
270	29	177	1831-12-27	2
271	16	177	1829-08-20	5
272	27	178	1832-03-01	1
273	27	179	1830-12-19	1
274	24	179	1832-03-07	2
275	8	179	1832-01-23	4
276	30	180	1829-11-20	1
277	33	180	1829-06-19	3
278	7	180	1829-10-02	7
279	21	183	1831-03-13	1
280	22	184	1832-04-10	1
281	23	184	1831-05-20	2
282	22	186	1829-11-04	1
283	27	191	1830-01-07	1
284	33	191	1832-10-10	3
285	18	191	1831-08-26	6
286	28	192	1830-10-01	1
287	33	192	1832-08-05	3
288	12	192	1832-03-03	6
289	24	194	1829-10-18	1
290	33	194	1830-08-27	3
291	20	194	1830-03-04	7
292	22	195	1830-06-18	1
293	22	196	1831-03-10	1
294	25	199	1831-04-14	1
295	21	203	1832-08-20	1
296	21	204	1831-11-26	1
297	30	205	1830-08-18	1
298	21	205	1832-04-12	2
299	2	205	1832-06-24	5
300	23	207	1830-08-09	1
301	29	208	1829-04-24	1
302	23	208	1830-06-14	2
303	2	208	1832-02-07	4
304	23	211	1829-02-14	1
305	34	211	1829-03-23	3
306	13	211	1830-10-10	6
307	26	212	1829-05-15	1
308	28	212	1830-08-12	2
309	9	212	1829-04-03	5
310	26	213	1832-03-11	1
311	31	213	1830-08-09	3
312	24	214	1832-02-05	1
313	22	216	1831-03-02	1
314	27	216	1829-05-09	2
315	4	216	1829-05-12	4
316	25	217	1831-11-10	1
317	25	217	1830-06-08	2
318	22	218	1830-01-16	1
319	25	218	1832-12-06	2
320	6	218	1831-05-24	5
321	30	219	1829-07-22	1
322	39	219	1830-08-22	3
323	23	220	1831-04-15	1
324	40	220	1829-03-04	3
325	13	220	1831-06-06	7
326	24	221	1832-07-24	1
327	29	221	1831-12-06	2
328	8	221	1831-07-13	5
329	24	222	1830-01-03	1
330	26	222	1829-06-17	2
331	11	222	1830-02-06	4
332	26	223	1832-12-28	1
333	31	223	1832-07-04	3
334	3	223	1829-01-12	7
335	30	224	1830-08-12	1
336	25	224	1831-03-26	2
337	3	224	1829-07-04	4
338	25	225	1832-11-17	1
339	27	225	1832-05-11	2
340	30	227	1829-12-14	1
341	29	227	1829-04-21	2
342	16	227	1832-08-16	4
343	30	229	1831-06-23	1
344	27	230	1829-01-12	1
345	27	230	1832-07-03	2
346	28	232	1829-05-02	1
347	37	232	1829-09-17	3
348	19	232	1832-12-09	6
349	23	233	1829-02-23	1
350	30	234	1832-11-22	1
351	24	235	1829-08-02	1
352	26	235	1830-02-02	2
353	4	235	1829-09-11	4
354	25	236	1830-10-21	1
355	29	236	1832-01-13	2
356	25	237	1829-10-07	1
357	40	237	1830-07-24	3
358	23	238	1831-05-28	1
359	29	239	1832-08-18	1
360	21	239	1831-07-14	2
361	25	240	1831-03-22	1
362	34	240	1831-09-28	3
363	29	242	1830-10-23	1
364	37	242	1832-05-27	3
365	17	242	1829-01-25	7
366	25	243	1832-12-05	1
367	30	243	1832-08-15	2
368	30	245	1830-12-16	1
369	30	245	1831-06-18	2
370	10	245	1832-07-23	5
371	21	246	1831-05-19	1
372	22	247	1830-12-14	1
373	37	247	1831-01-12	3
374	9	247	1832-09-26	6
375	22	248	1830-08-17	1
376	25	248	1832-12-07	2
377	30	249	1832-09-14	1
378	32	249	1831-12-12	3
379	7	249	1831-10-10	6
380	24	251	1829-09-07	1
381	23	251	1831-03-21	2
382	20	251	1829-08-14	5
383	30	252	1829-04-25	1
384	25	252	1832-12-13	2
385	22	253	1832-09-17	1
386	22	254	1829-12-10	1
387	27	254	1830-06-06	2
388	23	255	1831-08-08	1
389	36	255	1829-11-05	3
390	2	255	1829-06-02	6
391	27	256	1806-01-08	1
392	40	256	1807-06-19	3
393	26	257	1804-11-24	1
394	27	257	1805-12-19	2
395	21	260	1807-06-24	1
396	35	260	1806-07-07	3
397	4	260	1806-03-04	7
398	27	261	1805-05-01	1
399	21	261	1807-02-28	2
400	9	261	1806-11-23	4
401	27	262	1807-06-02	1
402	24	262	1806-12-06	2
403	29	263	1806-02-17	1
404	23	264	1804-09-15	1
405	24	264	1806-04-10	2
406	21	265	1805-04-01	1
407	34	265	1806-10-08	3
408	27	266	1806-05-15	1
409	24	267	1805-12-27	1
410	40	267	1806-11-12	3
411	7	267	1807-12-03	6
412	21	269	1805-09-09	1
413	35	269	1807-02-10	3
414	28	270	1804-08-15	1
415	40	270	1804-03-22	3
416	9	270	1804-03-13	6
417	26	271	1804-10-14	1
418	26	272	1807-05-19	1
419	26	273	1805-06-16	1
420	22	274	1805-03-23	1
421	29	275	1805-11-27	1
422	23	275	1806-03-18	2
423	16	275	1805-11-19	4
424	21	276	1804-05-25	1
425	22	276	1804-05-24	2
426	19	276	1804-12-15	4
427	29	277	1805-11-17	1
428	23	277	1804-07-05	2
429	15	277	1805-08-19	4
430	27	278	1804-02-11	1
431	32	278	1804-02-16	3
432	18	278	1804-01-22	6
433	29	279	1804-07-25	1
434	35	279	1807-12-03	3
435	28	280	1806-08-20	1
436	26	281	1807-04-16	1
437	23	281	1804-09-20	2
438	26	283	1804-09-12	1
439	40	283	1806-08-21	3
440	28	284	1806-05-03	1
441	24	284	1806-12-07	2
442	17	284	1807-12-21	5
443	23	286	1807-07-14	1
444	29	287	1805-04-11	1
445	28	288	1804-06-23	1
446	28	288	1804-12-22	2
447	7	288	1805-09-18	4
448	23	289	1804-08-12	1
449	36	289	1805-02-16	3
450	26	290	1804-02-18	1
451	35	290	1807-04-25	3
452	26	292	1805-05-01	1
453	40	292	1804-07-03	3
454	5	292	1805-11-12	6
455	27	293	1807-07-16	1
456	40	293	1804-08-01	3
457	24	294	1804-06-25	1
458	22	294	1806-02-24	2
459	1	294	1806-01-12	5
460	21	295	1805-03-01	1
461	26	295	1806-11-25	2
462	22	296	1805-02-04	1
463	29	296	1804-02-20	2
464	6	296	1806-08-21	4
465	28	297	1806-07-28	1
466	37	297	1806-10-07	3
467	26	298	1807-05-17	1
468	24	298	1804-10-24	2
469	30	300	1806-11-03	1
470	24	301	1804-01-13	1
471	28	301	1806-12-22	2
472	29	302	1805-09-28	1
473	34	302	1805-10-06	3
474	19	302	1807-08-11	7
475	23	303	1804-07-16	1
476	25	304	1806-07-13	1
477	28	307	1804-03-19	1
478	32	307	1807-03-17	3
479	12	307	1806-03-10	6
480	27	308	1807-07-12	1
481	33	308	1804-05-23	3
482	26	309	1807-03-14	1
483	34	309	1807-02-09	3
484	2	309	1805-02-01	6
485	25	310	1804-08-26	1
486	33	310	1806-11-27	3
487	22	311	1806-06-17	1
488	23	311	1807-09-06	2
489	16	311	1806-01-02	4
490	30	312	1806-12-19	1
491	28	312	1804-04-14	2
492	15	312	1806-02-15	5
493	29	313	1807-06-27	1
494	24	314	1805-09-16	1
495	25	315	1805-08-07	1
496	28	316	1806-08-05	1
497	34	316	1807-01-09	3
498	14	316	1806-12-20	7
499	25	317	1807-06-25	1
500	21	319	1804-02-03	1
501	37	319	1804-10-18	3
502	3	319	1804-04-08	7
503	26	320	1806-06-23	1
504	27	320	1807-02-15	2
505	25	321	1805-12-24	1
506	25	322	1807-09-28	1
507	30	322	1806-06-21	2
508	5	322	1806-08-06	4
509	27	323	1806-07-27	1
510	26	324	1806-09-06	1
511	25	324	1805-01-11	2
512	6	324	1805-01-19	5
513	22	325	1806-03-15	1
514	24	326	1805-09-17	1
515	40	326	1804-07-06	3
516	14	326	1804-06-25	7
517	23	327	1804-07-22	1
518	28	327	1807-03-09	2
519	26	328	1806-05-03	1
520	24	328	1805-09-23	2
521	17	328	1804-02-09	4
522	25	329	1805-01-22	1
523	30	329	1806-01-05	2
524	20	329	1807-06-26	4
525	25	330	1805-07-03	1
526	23	330	1807-08-11	2
527	19	330	1805-08-24	5
528	21	331	1804-10-22	1
529	22	332	1805-06-10	1
530	22	333	1807-05-15	1
531	32	333	1805-07-26	3
532	27	336	1806-03-02	1
533	33	336	1807-10-23	3
534	9	336	1804-08-11	6
535	30	337	1805-04-07	1
536	26	338	1807-11-09	1
537	22	341	1807-04-08	1
538	34	341	1806-10-02	3
539	23	342	1804-05-02	1
540	21	342	1806-06-24	2
541	18	342	1807-03-22	5
542	25	343	1807-05-13	1
543	25	347	1806-08-16	1
544	39	347	1807-02-12	3
545	19	347	1805-03-14	7
546	26	348	1806-04-08	1
547	30	348	1804-08-08	2
548	18	348	1806-07-16	4
549	24	349	1806-08-08	1
550	34	349	1806-01-21	3
551	29	352	1807-09-11	1
552	36	352	1805-08-07	3
553	24	353	1807-01-21	1
554	23	354	1806-01-28	1
555	33	354	1807-12-07	3
556	27	355	1806-02-06	1
557	27	357	1805-04-02	1
558	32	357	1807-10-13	3
559	1	357	1805-06-21	7
560	27	359	1804-09-11	1
561	36	359	1807-01-04	3
562	6	359	1807-03-16	6
563	24	360	1807-02-08	1
564	29	362	1806-05-27	1
565	21	363	1807-02-13	1
566	31	363	1804-09-21	3
567	23	364	1807-01-21	1
568	34	364	1807-07-10	3
569	8	364	1806-08-22	7
570	24	365	1807-04-06	1
571	22	365	1805-07-17	2
572	27	366	1804-01-23	1
573	33	366	1804-03-07	3
574	23	367	1807-05-07	1
575	24	368	1805-03-26	1
576	31	368	1806-09-21	3
577	21	370	1806-04-21	1
578	23	370	1804-11-03	2
579	20	370	1804-07-27	5
580	27	372	1806-04-10	1
581	21	373	1807-12-02	1
582	28	374	1804-09-06	1
583	26	375	1806-12-02	1
584	34	375	1806-08-02	3
585	24	376	1807-09-09	1
586	39	376	1806-08-02	3
587	21	377	1806-05-23	1
588	26	378	1804-03-12	1
589	30	380	1806-09-05	1
590	36	380	1805-10-02	3
591	18	380	1806-11-02	6
592	21	381	1807-10-22	1
593	27	381	1807-06-13	2
594	3	381	1806-11-03	5
595	25	382	1807-12-15	1
596	22	383	1804-09-10	1
597	29	383	1806-07-04	2
598	23	384	1806-01-19	1
599	29	385	1807-09-25	1
600	34	385	1807-05-06	3
601	1	385	1804-04-03	6
602	27	386	1806-12-23	1
603	28	387	1806-10-25	1
604	33	387	1805-03-01	3
605	23	388	1805-04-19	1
606	26	389	1806-08-12	1
607	34	389	1804-06-10	3
608	22	391	1806-05-09	1
609	21	391	1804-03-05	2
610	12	391	1805-06-01	5
611	28	392	1807-06-10	1
612	30	392	1805-09-01	2
613	8	392	1806-02-16	5
614	27	395	1804-09-28	1
615	21	396	1807-06-13	1
616	26	397	1806-10-15	1
617	24	397	1805-03-19	2
618	24	399	1807-08-04	1
619	25	400	1804-12-09	1
620	30	400	1804-05-03	2
621	26	401	1805-03-25	1
622	21	401	1806-06-28	2
623	17	401	1805-12-13	4
624	30	402	1807-03-14	1
625	21	402	1807-01-08	2
626	3	402	1806-06-05	4
627	26	403	1807-03-14	1
628	26	403	1805-01-01	2
629	17	403	1807-09-12	5
630	29	404	1805-09-16	1
631	21	404	1807-07-15	2
632	24	405	1806-06-03	1
633	26	405	1807-07-16	2
634	5	405	1807-06-09	5
635	30	407	1807-02-24	1
636	26	407	1807-11-08	2
637	12	407	1805-03-10	5
638	28	408	1804-09-24	1
639	25	408	1806-02-15	2
640	5	408	1804-10-15	4
641	26	410	1804-07-14	1
642	21	411	1805-10-10	1
643	28	412	1806-04-15	1
644	37	412	1806-06-04	3
645	22	413	1806-12-19	1
646	39	413	1807-06-04	3
647	27	414	1806-01-20	1
648	30	415	1805-04-06	1
649	23	415	1804-04-04	2
650	23	416	1806-01-19	1
651	22	417	1804-03-19	1
652	35	417	1806-05-14	3
653	21	418	1807-07-22	1
654	21	419	1805-03-09	1
655	30	419	1807-08-03	2
656	24	420	1807-07-20	1
657	31	420	1807-02-07	3
658	21	422	1804-08-04	1
659	24	423	1806-10-05	1
660	37	423	1806-10-06	3
661	21	424	1804-10-01	1
662	26	426	1805-06-20	1
663	29	427	1807-04-26	1
664	25	427	1804-10-12	2
665	2	427	1806-05-23	5
666	27	428	1804-08-13	1
667	25	429	1805-11-22	1
668	29	430	1805-01-20	1
669	22	430	1804-12-06	2
670	16	430	1804-11-05	4
671	24	431	1806-02-08	1
672	28	432	1806-09-24	1
673	25	432	1804-09-21	2
674	26	433	1805-11-24	1
675	30	433	1804-05-24	2
676	23	434	1804-07-05	1
677	38	434	1807-01-27	3
678	13	434	1804-04-11	7
679	23	435	1807-09-15	1
680	28	436	1804-10-10	1
681	23	436	1805-07-19	2
682	11	436	1805-06-25	4
683	24	437	1807-02-26	1
684	22	437	1806-03-18	2
685	19	437	1806-06-13	4
686	22	438	1806-09-28	1
687	34	438	1805-05-25	3
688	21	439	1807-02-28	1
689	31	439	1804-07-03	3
690	3	439	1805-12-21	6
691	22	440	1804-08-17	1
692	28	440	1804-04-16	2
693	29	441	1805-01-23	1
694	33	441	1804-10-08	3
695	8	441	1806-07-24	6
696	21	442	1804-02-05	1
697	22	443	1805-06-06	1
698	24	443	1805-05-07	2
699	26	444	1804-05-19	1
700	25	444	1804-03-16	2
701	24	445	1804-04-19	1
702	27	445	1807-05-02	2
703	16	445	1806-07-15	5
704	21	446	1806-10-06	1
705	36	446	1804-06-20	3
706	23	448	1806-01-04	1
707	22	449	1805-09-16	1
708	29	450	1804-10-26	1
709	23	451	1804-11-23	1
710	23	453	1805-04-19	1
711	22	453	1806-12-09	2
712	1	453	1807-12-25	4
713	25	455	1804-01-17	1
714	33	455	1804-05-07	3
715	29	456	1804-01-11	1
716	26	456	1804-09-15	2
717	13	456	1806-07-25	5
718	28	457	1804-06-23	1
719	24	457	1807-12-21	2
720	19	457	1805-10-19	5
721	28	458	1804-12-23	1
722	35	458	1804-04-24	3
723	11	458	1804-07-15	7
724	23	460	1804-05-18	1
725	40	460	1805-11-25	3
726	6	460	1806-11-21	7
727	23	461	1807-09-10	1
728	35	461	1806-02-22	3
729	25	463	1806-02-07	1
730	38	463	1806-04-02	3
731	20	463	1804-11-20	7
732	28	464	1804-01-07	1
733	24	465	1804-03-07	1
734	21	465	1806-06-10	2
735	30	468	1804-04-12	1
736	36	468	1805-07-10	3
737	29	471	1806-04-09	1
738	24	472	1807-12-12	1
739	29	474	1804-10-05	1
740	22	475	1807-11-09	1
741	33	475	1804-08-20	3
742	2	475	1805-10-11	7
743	24	476	1804-05-16	1
744	27	476	1806-04-16	2
745	11	476	1807-10-18	4
746	29	477	1807-06-10	1
747	24	477	1805-05-21	2
748	28	478	1807-04-07	1
749	34	478	1804-05-20	3
750	4	478	1805-04-22	6
751	21	480	1804-03-24	1
752	21	480	1806-01-25	2
753	21	481	1805-09-12	1
754	26	483	1807-06-04	1
755	22	483	1806-04-26	2
756	28	484	1804-12-01	1
757	28	485	1806-04-21	1
758	21	485	1807-03-13	2
759	24	486	1805-10-18	1
760	31	486	1807-04-05	3
761	24	487	1804-04-20	1
762	24	487	1805-04-16	2
763	27	488	1807-04-06	1
764	39	488	1804-10-02	3
765	27	489	1805-01-22	1
766	27	490	1807-03-13	1
767	37	490	1805-01-10	3
768	19	490	1807-02-12	6
769	24	491	1806-12-12	1
770	38	491	1804-02-13	3
771	12	491	1804-02-26	7
772	26	492	1807-07-19	1
773	29	492	1806-09-23	2
774	17	492	1806-06-21	5
775	27	493	1806-09-27	1
776	32	493	1807-08-15	3
777	6	493	1804-08-13	7
778	27	494	1805-04-16	1
779	37	494	1807-09-23	3
780	27	496	1804-05-18	1
781	26	497	1804-04-07	1
782	36	497	1806-07-11	3
783	9	497	1804-11-05	7
784	21	498	1805-07-04	1
785	34	498	1806-03-02	3
786	21	499	1806-03-15	1
787	23	499	1806-10-13	2
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
1	Sandra	Frye	Sandra	Frye	804	2008-09-04	2028-07-16	F	1	Serbia	f	f	BK
2	Tyler	Brandt	Tyler	Brandt	174	1978-06-12	1998-11-14	M	2	Liberia	f	f	BR
3	Amanda	Hayes	Amanda	Hayes	251	1980-10-22	2000-10-24	F	3	Australia	f	f	OZ
4	Anthony	Knight	Anthony	Knight	517	1955-03-09	1975-05-10	M	4	Bulgaria	f	f	TN
5	Lawrence	Suarez	Lawrence	Suarez	989	1956-05-17	1976-01-25	F	5	Sudan	f	f	YJ
6	Tamara	Snyder	Tamara	Snyder	523	1952-04-02	1972-04-03	M	6	Bermuda	f	f	KG
7	Timothy	Elliott	Timothy	Elliott	659	1952-04-23	1972-02-20	F	7	Montserrat	f	f	NW
8	Jamie	Smith	Jamie	Smith	1026	1933-08-24	1953-09-09	M	8	Brunei	f	f	OT
9	Nicole	Martinez	Nicole	Martinez	493	1932-11-27	1952-02-19	F	9	Turkey	f	f	NO
10	Kyle	Foster	Kyle	Foster	1194	1929-11-22	1949-07-12	M	10	Nauru	f	f	GX
11	Logan	Adams	Logan	Adams	21	1930-06-14	1950-03-12	F	11	Seychelles	f	f	WE
12	Paul	Hanson	Paul	Hanson	931	1927-08-26	1947-02-21	M	12	Oman	f	f	DB
13	Michael	Cole	Michael	Cole	288	1927-11-15	1947-09-15	F	13	Bulgaria	f	f	RS
14	Robert	Foster	Robert	Foster	613	1930-07-19	1950-04-04	M	14	Nepal	f	f	WI
15	Brandon	Rodriguez	Brandon	Rodriguez	735	1930-07-15	1950-01-01	F	15	Togo	f	f	LN
16	Melinda	Evans	Melinda	Evans	377	1903-10-19	1923-03-12	M	16	Belgium	f	f	WW
17	Emily	George	Emily	George	436	1902-11-24	1922-12-11	F	17	Seychelles	f	f	PE
18	John	Nelson	John	Nelson	240	1906-09-04	1926-03-27	M	18	Burundi	f	f	GV
19	Julie	Crane	Julie	Crane	611	1903-03-13	1923-02-18	F	19	Uganda	f	f	PK
20	Sandra	Smith	Sandra	Smith	436	1906-01-23	1926-01-14	M	20	Peru	f	f	UZ
21	Tony	Harris	Tony	Harris	653	1906-02-26	1926-03-03	F	21	Niue	f	f	RR
22	Calvin	Garza	Calvin	Garza	869	1908-09-18	1928-10-11	M	22	Montserrat	f	f	RV
23	Aaron	Calhoun	Aaron	Calhoun	472	1907-01-10	1927-10-23	F	23	Zambia	f	f	NH
24	Crystal	Scott	Crystal	Scott	780	1902-07-10	1922-02-05	M	24	Liechtenstein	f	f	DS
25	Walter	Bowen	Walter	Bowen	532	1905-01-14	1925-11-02	F	25	India	f	f	SA
26	Lucas	Austin	Lucas	Austin	185	1907-10-11	1927-01-09	M	26	Japan	f	f	PT
27	Kristen	Long	Kristen	Long	242	1906-06-17	1926-02-18	F	27	Guyana	f	f	JH
28	Christina	Taylor	Christina	Taylor	112	1904-09-28	1924-08-26	M	28	Iran	f	f	JD
29	Melissa	Thomas	Melissa	Thomas	1153	1902-08-09	1922-08-04	F	29	Sudan	f	f	JU
30	Robert	Fuller	Robert	Fuller	886	1902-10-03	1922-07-23	M	30	Oman	f	f	VY
31	Whitney	Harris	Whitney	Harris	563	1904-10-13	1924-05-19	F	31	Taiwan	f	f	BP
32	Andrea	Shepard	Andrea	Shepard	1051	1877-10-27	1897-04-15	M	32	Kiribati	f	f	IS
33	Luis	Barron	Luis	Barron	561	1879-06-15	1899-12-26	F	33	Greece	f	f	PH
34	David	Weaver	David	Weaver	562	1881-08-18	1901-11-14	M	34	Mongolia	f	f	HN
35	Emma	Matthews	Emma	Matthews	193	1882-02-11	1902-10-21	F	35	Albania	f	f	CX
36	Allen	Gallagher	Allen	Gallagher	340	1878-09-19	1898-10-02	M	36	Japan	f	f	YX
37	Ryan	Luna	Ryan	Luna	531	1878-02-03	1898-12-18	F	37	Paraguay	f	f	GB
38	Alejandro	Brown	Alejandro	Brown	845	1882-01-04	1902-09-06	M	38	Syria	f	f	RE
39	Emily	Ayers	Emily	Ayers	273	1881-11-28	1901-09-18	F	39	Benin	f	f	EC
40	Gina	Clay	Gina	Clay	861	1882-08-07	1902-12-09	M	40	Myanmar	f	f	DO
41	Amanda	Davenport	Amanda	Davenport	709	1880-11-12	1900-09-07	F	41	Nigeria	f	f	IH
42	Toni	Miller	Toni	Miller	1113	1879-02-16	1899-05-24	M	42	Canada	f	f	OM
43	Jeffrey	Ryan	Jeffrey	Ryan	779	1879-02-07	1899-09-28	F	43	Mauritius	f	f	CJ
44	John	Smith	John	Smith	796	1881-01-18	1901-09-09	M	44	Canada	f	f	RF
45	Kristin	Williams	Kristin	Williams	878	1879-12-14	1899-02-01	F	45	Maldives	f	f	PZ
46	Tracy	Caldwell	Tracy	Caldwell	1224	1881-03-05	1901-12-21	M	46	Belarus	f	f	OS
47	Alan	Nunez	Alan	Nunez	619	1883-02-09	1903-01-04	F	47	Sudan	f	f	TI
48	Amber	Green	Amber	Green	1049	1883-12-05	1903-10-12	M	48	Canada	f	f	RR
49	Darryl	Olson	Darryl	Olson	1118	1878-10-15	1898-09-27	F	49	Latvia	f	f	AP
50	Brenda	Rollins	Brenda	Rollins	524	1879-02-22	1899-01-18	M	50	Jamaica	f	f	YA
51	Grant	Roberson	Grant	Roberson	774	1877-11-18	1897-08-17	F	51	Bahrain	f	f	PI
52	Lauren	Wood	Lauren	Wood	2	1882-08-17	1902-11-25	M	52	Nigeria	f	f	WO
53	Jon	Dickson	Jon	Dickson	913	1877-03-09	1897-07-15	F	53	Morocco	f	f	HT
54	Kyle	Gonzales	Kyle	Gonzales	991	1883-07-09	1903-02-18	M	54	Zimbabwe	f	f	AG
55	Jessica	White	Jessica	White	225	1882-08-27	1902-07-24	F	55	Vietnam	f	f	UQ
56	Tyler	Salazar	Tyler	Salazar	603	1882-04-20	1902-02-11	M	56	Namibia	f	f	GW
57	Paul	Wheeler	Paul	Wheeler	1242	1883-09-26	1903-07-26	F	57	Greece	f	f	ZB
58	Kyle	Blake	Kyle	Blake	273	1878-08-02	1898-01-10	M	58	Angola	f	f	BZ
59	Nicholas	Bowen	Nicholas	Bowen	694	1878-12-15	1898-12-20	F	59	Portugal	f	f	SF
60	Kristopher	Hancock	Kristopher	Hancock	268	1881-05-17	1901-03-01	M	60	Ireland	f	f	MT
61	Hector	Edwards	Hector	Edwards	352	1881-07-09	1901-09-24	F	61	Azerbaijan	f	f	RK
62	Cindy	Marquez	Cindy	Marquez	1175	1878-03-03	1898-06-25	M	62	Indonesia	f	f	PC
63	John	Simmons	John	Simmons	475	1878-01-27	1898-05-15	F	63	Belarus	f	f	TT
64	Edward	Grant	Edward	Grant	596	1856-03-15	1876-07-07	M	64	Nauru	f	f	GL
65	Samuel	Nielsen	Samuel	Nielsen	647	1858-09-13	1878-05-07	F	65	Benin	f	f	EF
66	Scott	Guerrero	Scott	Guerrero	273	1854-12-12	1874-12-19	M	66	Malaysia	f	f	BU
67	Jennifer	Jones	Jennifer	Jones	1230	1854-01-19	1874-03-08	F	67	Afghanistan	f	f	ZA
68	Thomas	Neal	Thomas	Neal	561	1857-03-14	1877-07-11	M	68	Iran	f	f	YF
69	Steven	Morgan	Steven	Morgan	793	1854-07-19	1874-12-03	F	69	Israel	f	f	II
70	Stephen	Bender	Stephen	Bender	388	1855-03-11	1875-05-28	M	70	India	f	f	GH
71	Rebecca	Haynes	Rebecca	Haynes	1200	1852-01-04	1872-06-27	F	71	Belgium	f	f	ZM
72	Corey	Daniels	Corey	Daniels	851	1854-03-01	1874-06-19	M	72	Albania	f	f	CX
73	Julie	Martinez	Julie	Martinez	376	1856-01-16	1876-10-25	F	73	Armenia	f	f	UU
74	Kyle	Tucker	Kyle	Tucker	733	1853-07-17	1873-08-18	M	74	Honduras	f	f	CL
75	Nathan	Martin	Nathan	Martin	5	1856-07-16	1876-11-10	F	75	Eritrea	f	f	FP
76	Levi	Long	Levi	Long	854	1856-11-11	1876-02-05	M	76	Namibia	f	f	IZ
77	Zachary	Jackson	Zachary	Jackson	102	1858-04-13	1878-03-20	F	77	Kosovo	f	f	IO
78	Juan	Smith	Juan	Smith	963	1856-02-21	1876-07-24	M	78	China	f	f	PN
79	Michael	Young	Michael	Young	752	1858-11-01	1878-01-19	F	79	Greenland	f	f	XS
80	Carolyn	Rivera	Carolyn	Rivera	588	1856-01-28	1876-05-14	M	80	Guyana	f	f	JY
81	John	Robinson	John	Robinson	618	1852-09-10	1872-09-24	F	81	Bermuda	f	f	OC
82	Justin	Hughes	Justin	Hughes	1017	1857-12-24	1877-12-24	M	82	Russia	f	f	NO
83	Michael	Murillo	Michael	Murillo	433	1855-07-17	1875-10-26	F	83	Eritrea	f	f	JO
84	Wyatt	Brennan	Wyatt	Brennan	1200	1858-07-09	1878-05-24	M	84	Afghanistan	f	f	AU
85	Christy	Obrien	Christy	Obrien	1090	1853-09-18	1873-10-22	F	85	Albania	f	f	IX
86	Martin	Greer	Martin	Greer	478	1856-01-01	1876-08-09	M	86	Sweden	f	f	AQ
87	Cynthia	Walker	Cynthia	Walker	829	1856-07-16	1876-09-24	F	87	Kiribati	f	f	SF
88	Adam	Hunt	Adam	Hunt	108	1857-08-24	1877-01-13	M	88	Slovenia	f	f	KE
89	Joseph	Nelson	Joseph	Nelson	552	1854-08-21	1874-07-22	F	89	Palau	f	f	CM
90	Damon	Valenzuela	Damon	Valenzuela	114	1858-08-17	1878-09-01	M	90	Canada	f	f	NY
91	Linda	Golden	Linda	Golden	262	1855-01-19	1875-12-21	F	91	Togo	f	f	IX
92	Richard	Flores	Richard	Flores	879	1858-09-13	1878-08-22	M	92	Eritrea	f	f	MO
93	Matthew	Tucker	Matthew	Tucker	119	1855-09-05	1875-03-13	F	93	Seychelles	f	f	EK
94	Rebecca	Hughes	Rebecca	Hughes	47	1857-09-04	1877-09-12	M	94	Croatia	f	f	LP
95	Jennifer	Nelson	Jennifer	Nelson	77	1855-10-02	1875-05-04	F	95	Zambia	f	f	FA
96	Megan	Davis	Megan	Davis	899	1856-04-12	1876-01-15	M	96	Macao	f	f	NS
97	Daniel	Wilson	Daniel	Wilson	105	1857-01-18	1877-06-21	F	97	Australia	f	f	NL
98	Henry	Carrillo	Henry	Carrillo	1203	1856-04-26	1876-05-07	M	98	Swaziland	f	f	BG
99	Dalton	Henderson	Dalton	Henderson	1154	1856-09-10	1876-04-21	F	99	Gabon	f	f	BZ
100	James	Hill	James	Hill	550	1857-06-11	1877-06-27	M	100	Seychelles	f	f	TJ
101	Patricia	Garcia	Patricia	Garcia	10	1852-08-03	1872-09-01	F	101	Ghana	f	f	GD
102	John	Hawkins	John	Hawkins	748	1855-03-02	1875-06-02	M	102	Aruba	f	f	YB
103	Danielle	Phillips	Danielle	Phillips	648	1855-10-18	1875-06-13	F	103	Bahamas	f	f	QX
104	Michael	Davis	Michael	Davis	1232	1857-04-26	1877-11-08	M	104	Comoros	f	f	CJ
105	Danielle	Anderson	Danielle	Anderson	117	1854-12-22	1874-04-08	F	105	Cyprus	f	f	TH
106	Lisa	Rodriguez	Lisa	Rodriguez	811	1855-08-04	1875-04-20	M	106	Senegal	f	f	ID
107	Ryan	Jenkins	Ryan	Jenkins	593	1857-03-12	1877-06-27	F	107	Montenegro	f	f	PB
108	Scott	Patterson	Scott	Patterson	243	1858-02-15	1878-01-23	M	108	Eritrea	f	f	CR
109	John	Gonzalez	John	Gonzalez	190	1852-09-09	1872-11-25	F	109	Brunei	f	f	QW
110	Kathy	Fry	Kathy	Fry	620	1853-09-09	1873-08-19	M	110	Pakistan	f	f	XA
111	Kelly	Mejia	Kelly	Mejia	1086	1855-09-28	1875-07-17	F	111	Cambodia	f	f	YC
112	Lisa	Le	Lisa	Le	709	1853-11-17	1873-04-20	M	112	Belarus	f	f	VQ
113	John	Nelson	John	Nelson	28	1852-04-01	1872-09-11	F	113	Iran	f	f	NL
114	Angela	Marsh	Angela	Marsh	779	1855-09-17	1875-08-04	M	114	Bahrain	f	f	ZU
115	Jonathan	Edwards	Jonathan	Edwards	651	1855-05-13	1875-02-10	F	115	Djibouti	f	f	LU
116	David	Williams	David	Williams	510	1857-05-24	1877-07-20	M	116	Malta	f	f	FU
117	Kristin	Gonzalez	Kristin	Gonzalez	1068	1856-08-20	1876-02-25	F	117	Ecuador	f	f	NT
118	Susan	Neal	Susan	Neal	806	1857-07-04	1877-07-06	M	118	Seychelles	f	f	AS
119	Lucas	Gilbert	Lucas	Gilbert	328	1852-05-14	1872-10-05	F	119	Tuvalu	f	f	XZ
120	Cody	Meyer	Cody	Meyer	1109	1854-05-14	1874-03-13	M	120	Togo	f	f	PA
121	Michelle	Ross	Michelle	Ross	550	1857-03-13	1877-12-27	F	121	Myanmar	f	f	MK
122	Donna	Daniels	Donna	Daniels	230	1858-06-13	1878-11-06	M	122	Qatar	f	f	IM
123	Joel	Miller	Joel	Miller	804	1853-03-20	1873-06-01	F	123	Barbados	f	f	CC
124	Jennifer	Johnson	Jennifer	Johnson	1104	1858-02-10	1878-05-02	M	124	Mozambique	f	f	TL
125	Maurice	Smith	Maurice	Smith	210	1856-09-26	1876-07-14	F	125	Suriname	f	f	BW
126	Ryan	Matthews	Ryan	Matthews	792	1852-01-24	1872-05-17	M	126	Switzerland	f	f	NQ
127	Sharon	Perry	Sharon	Perry	1086	1856-05-21	1876-04-13	F	127	Martinique	f	f	AZ
128	Ashley	Reed	Ashley	Reed	584	1833-11-12	1853-04-23	M	128	Kiribati	f	f	GI
129	Teresa	Shaw	Teresa	Shaw	1069	1828-02-01	1848-03-06	F	129	Djibouti	f	f	ZO
130	Stacy	Jenkins	Stacy	Jenkins	808	1831-09-03	1851-05-13	M	130	Poland	f	f	GA
131	David	Brooks	David	Brooks	342	1827-08-26	1847-07-20	F	131	Bermuda	f	f	OK
132	Angelica	Reyes	Angelica	Reyes	872	1832-10-10	1852-01-06	M	132	Cuba	f	f	WD
133	Natalie	Holmes	Natalie	Holmes	715	1828-06-02	1848-02-15	F	133	Afghanistan	f	f	MT
134	Joshua	Flores	Joshua	Flores	624	1832-10-19	1852-07-04	M	134	Argentina	f	f	CS
135	Melissa	Young	Melissa	Young	1102	1831-01-13	1851-07-22	F	135	Zimbabwe	f	f	HR
136	Tracey	Williams	Tracey	Williams	60	1832-04-15	1852-02-14	M	136	Laos	f	f	DN
137	Jessica	Rubio	Jessica	Rubio	5	1828-01-16	1848-06-23	F	137	Samoa	f	f	CB
138	Darlene	Kelley	Darlene	Kelley	266	1828-10-23	1848-06-26	M	138	Guatemala	f	f	WR
139	Sherry	Melton	Sherry	Melton	537	1832-12-12	1852-03-26	F	139	Bolivia	f	f	UR
140	Emily	Garner	Emily	Garner	940	1828-06-20	1848-08-27	M	140	Lebanon	f	f	BQ
141	Amber	Dickerson	Amber	Dickerson	552	1831-03-15	1851-06-19	F	141	Canada	f	f	VW
142	Kathryn	Leach	Kathryn	Leach	712	1829-12-15	1849-03-09	M	142	Kazakhstan	f	f	BS
143	Andrew	Scott	Andrew	Scott	925	1833-06-26	1853-09-09	F	143	Seychelles	f	f	GD
144	Jerry	Grant	Jerry	Grant	441	1832-02-16	1852-08-09	M	144	Ecuador	f	f	QV
145	Wesley	Cross	Wesley	Cross	855	1831-09-16	1851-11-12	F	145	Montenegro	f	f	UA
146	Randy	Miller	Randy	Miller	271	1830-09-08	1850-04-19	M	146	Ghana	f	f	FI
147	Jamie	Vaughn	Jamie	Vaughn	1176	1833-11-08	1853-05-06	F	147	Luxembourg	f	f	HT
148	Melissa	Callahan	Melissa	Callahan	696	1829-11-11	1849-12-25	M	148	Greece	f	f	VG
149	Samantha	Williams	Samantha	Williams	180	1829-05-10	1849-11-26	F	149	Cambodia	f	f	TH
150	Cathy	Michael	Cathy	Michael	320	1829-08-21	1849-02-01	M	150	Afghanistan	f	f	UL
151	Abigail	Patterson	Abigail	Patterson	34	1828-02-21	1848-01-02	F	151	Belize	f	f	CK
152	Allison	Dudley	Allison	Dudley	846	1830-06-07	1850-05-02	M	152	Germany	f	f	ZZ
153	Kaitlyn	Peters	Kaitlyn	Peters	855	1830-12-08	1850-09-20	F	153	Sudan	f	f	HV
154	Darlene	Byrd	Darlene	Byrd	1140	1828-04-10	1848-05-16	M	154	Kyrgyzstan	f	f	ES
155	David	Huang	David	Huang	512	1831-05-25	1851-10-14	F	155	Liechtenstein	f	f	XS
156	Phillip	Sullivan	Phillip	Sullivan	1097	1827-02-12	1847-07-22	M	156	Swaziland	f	f	WY
157	Morgan	Duncan	Morgan	Duncan	1197	1831-08-16	1851-08-10	F	157	Zambia	f	f	PF
158	Danielle	Martinez	Danielle	Martinez	414	1831-06-15	1851-01-21	M	158	Denmark	f	f	TR
159	Natasha	Grant	Natasha	Grant	309	1827-07-20	1847-11-07	F	159	Niue	f	f	AR
160	Stephanie	Wheeler	Stephanie	Wheeler	1190	1833-08-17	1853-12-20	M	160	Guatemala	f	f	EH
161	Raymond	Terrell	Raymond	Terrell	1136	1827-03-11	1847-11-06	F	161	Libya	f	f	NZ
162	Krista	Marquez	Krista	Marquez	66	1833-10-26	1853-09-24	M	162	Mayotte	f	f	ZT
163	Tamara	Tucker	Tamara	Tucker	975	1830-03-20	1850-08-03	F	163	Azerbaijan	f	f	PT
164	Connie	Garza	Connie	Garza	5	1828-09-13	1848-07-11	M	164	Cuba	f	f	VN
165	David	King	David	King	48	1827-06-26	1847-02-14	F	165	Colombia	f	f	OQ
166	Tracey	Ponce	Tracey	Ponce	399	1833-06-14	1853-01-16	M	166	Palau	f	f	IZ
167	Michael	Morrow	Michael	Morrow	113	1833-05-20	1853-01-19	F	167	Chad	f	f	IT
168	Laura	Richardson	Laura	Richardson	852	1832-09-05	1852-01-23	M	168	Switzerland	f	f	ZJ
169	Melinda	Atkins	Melinda	Atkins	318	1828-08-01	1848-05-02	F	169	Afghanistan	f	f	CI
170	Pamela	Robinson	Pamela	Robinson	1043	1829-12-28	1849-09-03	M	170	Switzerland	f	f	LY
171	Tara	Murray	Tara	Murray	328	1832-05-09	1852-07-03	F	171	Rwanda	f	f	QN
172	Elizabeth	Glover	Elizabeth	Glover	487	1830-07-25	1850-08-17	M	172	Peru	f	f	ZF
173	Dennis	Gomez	Dennis	Gomez	747	1827-03-06	1847-07-24	F	173	Haiti	f	f	TB
174	Jenna	Schroeder	Jenna	Schroeder	1120	1831-03-04	1851-03-07	M	174	Jamaica	f	f	CG
175	Amber	Hill	Amber	Hill	787	1831-04-27	1851-02-17	F	175	Mauritania	f	f	VY
176	Brittany	Kim	Brittany	Kim	1051	1830-03-17	1850-03-10	M	176	Canada	f	f	MN
177	Diana	Hall	Diana	Hall	816	1833-11-25	1853-09-23	F	177	Bhutan	f	f	QI
178	Logan	Morris	Logan	Morris	590	1828-05-01	1848-05-24	M	178	Uruguay	f	f	GV
179	Ashley	Delgado	Ashley	Delgado	1092	1833-01-25	1853-02-28	F	179	Barbados	f	f	NT
180	Rachel	Frederick	Rachel	Frederick	1154	1831-11-14	1851-09-11	M	180	Iran	f	f	UB
181	Rachel	Andrews	Rachel	Andrews	713	1827-05-01	1847-09-27	F	181	Niue	f	f	QG
182	Mario	Harris	Mario	Harris	475	1829-08-19	1849-03-22	M	182	Bhutan	f	f	WV
183	Scott	Martin	Scott	Martin	776	1827-06-12	1847-02-22	F	183	Lebanon	f	f	KL
184	Alyssa	Williams	Alyssa	Williams	1149	1827-08-07	1847-06-18	M	184	Colombia	f	f	NL
185	Steven	Silva	Steven	Silva	570	1833-12-22	1853-11-15	F	185	Iraq	f	f	QU
186	John	Knox	John	Knox	503	1831-01-17	1851-08-26	M	186	Slovenia	f	f	KL
187	Donna	Green	Donna	Green	150	1830-05-15	1850-04-26	F	187	Belarus	f	f	PG
188	Natalie	Taylor	Natalie	Taylor	49	1829-08-21	1849-11-11	M	188	Laos	f	f	HB
189	Robert	Lam	Robert	Lam	985	1830-04-02	1850-04-15	F	189	China	f	f	XL
190	Nathan	Campbell	Nathan	Campbell	766	1827-07-07	1847-06-07	M	190	Macedonia	f	f	SB
191	Crystal	Meza	Crystal	Meza	585	1829-02-27	1849-03-04	F	191	Taiwan	f	f	EQ
192	Robert	Lane	Robert	Lane	328	1831-12-11	1851-01-13	M	192	Slovenia	f	f	OU
193	Valerie	Wade	Valerie	Wade	464	1833-01-03	1853-09-04	F	193	Lebanon	f	f	CK
194	Tiffany	Patterson	Tiffany	Patterson	923	1830-09-05	1850-12-19	M	194	Gabon	f	f	HG
195	Stephanie	Garza	Stephanie	Garza	349	1830-05-15	1850-08-16	F	195	India	f	f	YI
196	Kimberly	Shields	Kimberly	Shields	440	1829-01-26	1849-03-26	M	196	Belarus	f	f	YV
197	Austin	Martinez	Austin	Martinez	952	1829-06-09	1849-11-15	F	197	Jamaica	f	f	KJ
198	Timothy	Carter	Timothy	Carter	226	1828-02-04	1848-02-16	M	198	Belize	f	f	JC
199	Timothy	Harris	Timothy	Harris	758	1828-10-14	1848-01-17	F	199	Morocco	f	f	BX
200	Martin	Riley	Martin	Riley	14	1829-01-08	1849-12-19	M	200	Peru	f	f	UC
201	Walter	Clarke	Walter	Clarke	522	1827-09-23	1847-08-09	F	201	Kosovo	f	f	XN
202	Kayla	Herrera	Kayla	Herrera	1176	1830-07-26	1850-10-16	M	202	Mauritius	f	f	IG
203	William	Adams	William	Adams	752	1833-02-22	1853-04-27	F	203	Croatia	f	f	CN
204	Bryan	Blackwell	Bryan	Blackwell	323	1829-02-08	1849-10-06	M	204	Tuvalu	f	f	BY
205	Donald	Anderson	Donald	Anderson	104	1832-05-22	1852-12-12	F	205	Mali	f	f	DE
206	Jonathan	Gutierrez	Jonathan	Gutierrez	1178	1833-02-14	1853-06-21	M	206	Mexico	f	f	CO
207	Jennifer	Marquez	Jennifer	Marquez	615	1832-10-17	1852-10-17	F	207	Slovenia	f	f	CO
208	Kelsey	Smith	Kelsey	Smith	287	1831-08-05	1851-06-19	M	208	Venezuela	f	f	QF
209	Mark	Ware	Mark	Ware	779	1833-08-17	1853-04-01	F	209	Nicaragua	f	f	VC
210	Jonathan	Haynes	Jonathan	Haynes	39	1829-08-05	1849-03-22	M	210	Uganda	f	f	DL
211	Sandra	Kirk	Sandra	Kirk	1011	1829-10-17	1849-12-18	F	211	Poland	f	f	RX
212	Elizabeth	Pope	Elizabeth	Pope	700	1829-04-27	1849-11-18	M	212	Swaziland	f	f	WH
213	Misty	Hart	Misty	Hart	737	1829-07-28	1849-01-10	F	213	Montserrat	f	f	HG
214	Darrell	Moyer	Darrell	Moyer	640	1833-09-17	1853-01-25	M	214	Montserrat	f	f	SX
215	Bernard	Mann	Bernard	Mann	208	1829-12-07	1849-01-06	F	215	Monaco	f	f	AV
216	Jerry	Huffman	Jerry	Huffman	772	1832-07-26	1852-10-17	M	216	Algeria	f	f	YW
217	Chad	Park	Chad	Park	604	1830-11-07	1850-11-21	F	217	Algeria	f	f	KF
218	Pamela	Wagner	Pamela	Wagner	725	1829-01-26	1849-10-22	M	218	Angola	f	f	JC
219	Lauren	Lamb	Lauren	Lamb	878	1830-02-09	1850-07-17	F	219	Pitcairn	f	f	JF
220	Sandra	Wright	Sandra	Wright	579	1833-12-23	1853-01-21	M	220	Palau	f	f	ZW
221	Kathryn	Cain	Kathryn	Cain	1173	1833-08-09	1853-02-28	F	221	Spain	f	f	SN
222	Molly	Newman	Molly	Newman	1036	1828-09-05	1848-02-16	M	222	Nepal	f	f	OP
223	Keith	Wallace	Keith	Wallace	1224	1833-05-01	1853-05-23	F	223	Lebanon	f	f	OX
224	Rebecca	Hogan	Rebecca	Hogan	1209	1830-07-16	1850-01-17	M	224	Portugal	f	f	OF
225	Daniel	Chen	Daniel	Chen	1046	1831-06-12	1851-01-20	F	225	Cuba	f	f	TI
226	Jason	Stewart	Jason	Stewart	363	1829-04-03	1849-04-16	M	226	Afghanistan	f	f	YS
227	Christopher	Bailey	Christopher	Bailey	260	1828-04-09	1848-08-21	F	227	Monaco	f	f	ZI
228	Phillip	Martin	Phillip	Martin	1203	1829-11-24	1849-06-24	M	228	Seychelles	f	f	LU
229	Kelsey	Mayo	Kelsey	Mayo	613	1831-05-08	1851-05-19	F	229	Malawi	f	f	AH
230	Karen	Thompson	Karen	Thompson	62	1833-11-08	1853-10-15	M	230	Nepal	f	f	WZ
231	Jamie	Atkins	Jamie	Atkins	970	1831-09-18	1851-08-10	F	231	Malaysia	f	f	EN
232	Edward	Strong	Edward	Strong	954	1831-11-17	1851-08-15	M	232	Norway	f	f	UW
233	Stacy	Kim	Stacy	Kim	85	1833-01-22	1853-02-05	F	233	Namibia	f	f	BZ
234	Bryan	Ross	Bryan	Ross	740	1830-10-15	1850-11-24	M	234	Portugal	f	f	TE
235	David	Kirby	David	Kirby	822	1832-08-13	1852-12-03	F	235	Laos	f	f	TI
236	Andrew	Freeman	Andrew	Freeman	1077	1832-07-11	1852-01-27	M	236	Angola	f	f	SP
237	Jennifer	Hudson	Jennifer	Hudson	411	1828-08-17	1848-07-19	F	237	Afghanistan	f	f	ES
238	Scott	Moreno	Scott	Moreno	626	1831-08-25	1851-10-21	M	238	Iceland	f	f	NM
239	Shannon	King	Shannon	King	71	1830-12-04	1850-02-17	F	239	Curacao	f	f	YF
240	Kristen	Thomas	Kristen	Thomas	804	1831-02-08	1851-09-21	M	240	Spain	f	f	FR
241	Brittany	Dickerson	Brittany	Dickerson	423	1830-05-28	1850-07-09	F	241	Argentina	f	f	YU
242	Laura	Robles	Laura	Robles	536	1830-01-16	1850-01-01	M	242	Samoa	f	f	FH
243	Rick	Murphy	Rick	Murphy	605	1827-06-23	1847-01-14	F	243	Tuvalu	f	f	OE
244	Jennifer	Black	Jennifer	Black	624	1833-01-04	1853-11-20	M	244	Paraguay	f	f	CC
245	Janet	Nelson	Janet	Nelson	881	1827-04-17	1847-07-19	F	245	Georgia	f	f	FM
246	Susan	Smith	Susan	Smith	821	1832-09-03	1852-08-24	M	246	Guinea	f	f	IB
247	Chad	Nelson	Chad	Nelson	287	1830-11-03	1850-09-19	F	247	Taiwan	f	f	VL
248	Cesar	Peterson	Cesar	Peterson	291	1829-01-19	1849-09-11	M	248	India	f	f	QL
249	Amanda	Green	Amanda	Green	106	1832-02-06	1852-06-14	F	249	Liberia	f	f	VN
250	Jennifer	Brown	Jennifer	Brown	445	1832-04-06	1852-04-02	M	250	Bulgaria	f	f	HK
251	Rebecca	Novak	Rebecca	Novak	145	1830-03-06	1850-12-15	F	251	Albania	f	f	PR
252	Michael	Smith	Michael	Smith	332	1827-06-18	1847-03-07	M	252	Algeria	f	f	CP
253	Melissa	Barron	Melissa	Barron	229	1831-04-20	1851-09-04	F	253	Gambia	f	f	PJ
254	Aaron	Richardson	Aaron	Richardson	268	1831-07-19	1851-06-03	M	254	Qatar	f	f	IA
255	Patrick	Jacobs	Patrick	Jacobs	1175	1830-04-19	1850-11-18	F	255	Pitcairn	f	f	QO
256	Crystal	Braun	Crystal	Braun	657	1804-01-08	1824-08-01	M	256	Uruguay	f	f	WT
257	John	Mullen	John	Mullen	638	1804-08-06	1824-03-11	F	257	Georgia	f	f	QG
258	Rachel	Martinez	Rachel	Martinez	45	1803-10-28	1823-05-07	M	258	Iran	f	f	CR
259	Joseph	Lawson	Joseph	Lawson	771	1804-03-17	1824-02-21	F	259	Maldives	f	f	UX
260	Dana	Hicks	Dana	Hicks	460	1808-09-10	1828-09-01	M	260	Macedonia	f	f	SA
261	Jillian	Russell	Jillian	Russell	839	1803-07-26	1823-06-26	F	261	Chile	f	f	EV
262	Scott	Williams	Scott	Williams	620	1808-04-18	1828-10-26	M	262	Algeria	f	f	QW
263	Ronald	Sharp	Ronald	Sharp	78	1806-04-19	1826-02-20	F	263	Finland	f	f	EV
264	Ronald	Rodriguez	Ronald	Rodriguez	15	1803-05-19	1823-08-26	M	264	Cuba	f	f	JB
265	Christopher	Davis	Christopher	Davis	662	1806-02-22	1826-02-16	F	265	Fiji	f	f	MW
266	Maria	Fletcher	Maria	Fletcher	526	1806-12-12	1826-09-20	M	266	Jordan	f	f	QX
267	James	Chambers	James	Chambers	1242	1804-11-15	1824-10-01	F	267	Moldova	f	f	HJ
268	Michael	Morris	Michael	Morris	395	1804-03-25	1824-07-25	M	268	Oman	f	f	KF
269	Deborah	Williams	Deborah	Williams	963	1803-02-19	1823-04-01	F	269	Gambia	f	f	EK
270	Patrick	Jimenez	Patrick	Jimenez	536	1805-10-26	1825-08-14	M	270	Canada	f	f	IJ
271	Debra	Rojas	Debra	Rojas	888	1804-06-08	1824-04-08	F	271	Kenya	f	f	JJ
272	Amy	Mitchell	Amy	Mitchell	450	1806-04-22	1826-06-12	M	272	Botswana	f	f	WZ
273	Angela	Macias	Angela	Macias	1115	1808-10-28	1828-02-24	F	273	Cyprus	f	f	NS
274	Jessica	Young	Jessica	Young	1116	1808-11-21	1828-08-20	M	274	Hungary	f	f	XZ
275	Lance	Evans	Lance	Evans	195	1806-03-13	1826-03-05	F	275	Austria	f	f	AN
276	Nicholas	Phillips	Nicholas	Phillips	937	1807-08-12	1827-06-18	M	276	Cuba	f	f	HE
277	Robert	Smith	Robert	Smith	1125	1803-08-18	1823-03-08	F	277	Kenya	f	f	UJ
278	Lori	Kennedy	Lori	Kennedy	100	1802-02-19	1822-02-12	M	278	Italy	f	f	IB
279	Wesley	Williams	Wesley	Williams	1107	1803-01-06	1823-04-28	F	279	Ireland	f	f	CA
280	Kevin	Bailey	Kevin	Bailey	128	1802-05-07	1822-04-20	M	280	Taiwan	f	f	FS
281	Kimberly	Finley	Kimberly	Finley	161	1805-03-22	1825-09-12	F	281	Azerbaijan	f	f	GE
282	Mitchell	Madden	Mitchell	Madden	949	1802-12-05	1822-12-23	M	282	Niger	f	f	EB
283	Sophia	Williams	Sophia	Williams	161	1802-06-11	1822-05-27	F	283	Macedonia	f	f	KI
284	Craig	Luna	Craig	Luna	1218	1802-06-08	1822-10-21	M	284	Georgia	f	f	CI
285	Jeff	Ramirez	Jeff	Ramirez	875	1806-04-12	1826-10-24	F	285	Armenia	f	f	TK
286	Angelica	Owens	Angelica	Owens	962	1808-12-22	1828-11-03	M	286	Turkey	f	f	VY
287	Crystal	Mitchell	Crystal	Mitchell	420	1804-09-02	1824-08-15	F	287	Croatia	f	f	JD
288	Carrie	Holloway	Carrie	Holloway	1241	1807-11-19	1827-08-06	M	288	Madagascar	f	f	TA
289	Alicia	Clark	Alicia	Clark	766	1806-10-24	1826-02-26	F	289	Fiji	f	f	EM
290	Michael	Gonzalez	Michael	Gonzalez	849	1804-01-16	1824-06-15	M	290	Thailand	f	f	EV
291	Carlos	Griffith	Carlos	Griffith	918	1807-06-06	1827-01-08	F	291	Greenland	f	f	EZ
292	Gary	Dean	Gary	Dean	145	1805-06-27	1825-05-07	M	292	Mauritius	f	f	KR
293	Kevin	Smith	Kevin	Smith	373	1808-03-11	1828-06-01	F	293	Indonesia	f	f	KZ
294	Travis	Jensen	Travis	Jensen	901	1808-12-13	1828-09-01	M	294	Honduras	f	f	VK
295	Elizabeth	Nichols	Elizabeth	Nichols	667	1806-07-10	1826-03-14	F	295	Colombia	f	f	KG
296	Sean	Castillo	Sean	Castillo	735	1806-01-07	1826-12-25	M	296	Italy	f	f	QD
297	David	Yu	David	Yu	362	1802-12-22	1822-10-13	F	297	Montserrat	f	f	YK
298	Edward	Davis	Edward	Davis	599	1808-02-24	1828-11-24	M	298	Maldives	f	f	LU
299	Donna	David	Donna	David	645	1803-08-12	1823-08-09	F	299	Guinea	f	f	ML
300	Lisa	Moss	Lisa	Moss	1212	1803-03-26	1823-03-16	M	300	Nigeria	f	f	JD
301	Frank	Robinson	Frank	Robinson	138	1803-08-25	1823-11-16	F	301	Greece	f	f	EC
302	Courtney	Moore	Courtney	Moore	578	1808-09-11	1828-06-10	M	302	Serbia	f	f	XG
303	Samantha	Gill	Samantha	Gill	1194	1805-09-17	1825-03-09	F	303	Argentina	f	f	ED
304	Betty	Bauer	Betty	Bauer	612	1805-08-16	1825-02-23	M	304	Lesotho	f	f	FC
305	Matthew	Vang	Matthew	Vang	616	1802-03-18	1822-10-24	F	305	Cuba	f	f	CZ
306	Jessica	Mata	Jessica	Mata	873	1805-09-20	1825-07-20	M	306	Somalia	f	f	KQ
307	Karen	Jones	Karen	Jones	926	1803-11-06	1823-12-16	F	307	Rwanda	f	f	YZ
308	Robert	Garza	Robert	Garza	963	1808-07-08	1828-04-07	M	308	Estonia	f	f	IW
309	Charles	Norton	Charles	Norton	1068	1806-06-19	1826-01-15	F	309	Mali	f	f	WX
310	Daniel	Garner	Daniel	Garner	631	1805-04-05	1825-04-07	M	310	Barbados	f	f	CD
311	David	Singleton	David	Singleton	138	1806-11-06	1826-10-17	F	311	Israel	f	f	JT
312	Justin	Baker	Justin	Baker	985	1808-11-21	1828-12-13	M	312	Seychelles	f	f	QP
313	Heather	Taylor	Heather	Taylor	857	1805-04-03	1825-02-20	F	313	Peru	f	f	YT
314	Brandon	Velasquez	Brandon	Velasquez	491	1802-03-20	1822-05-13	M	314	Slovakia	f	f	UN
315	Adam	Black	Adam	Black	958	1803-11-25	1823-08-09	F	315	Belize	f	f	IC
316	Albert	Smith	Albert	Smith	99	1804-03-02	1824-05-15	M	316	Laos	f	f	TT
317	David	Barnes	David	Barnes	854	1805-11-15	1825-07-14	F	317	Curacao	f	f	IE
318	Katherine	Benjamin	Katherine	Benjamin	1184	1805-07-01	1825-09-23	M	318	Myanmar	f	f	HE
319	Amber	Lopez	Amber	Lopez	1121	1805-05-23	1825-10-04	F	319	Seychelles	f	f	DT
320	Cynthia	Phelps	Cynthia	Phelps	296	1806-10-20	1826-03-11	M	320	Morocco	f	f	MJ
321	Jonathon	Hurley	Jonathon	Hurley	1079	1802-01-15	1822-08-18	F	321	Colombia	f	f	IU
322	Evan	Bowers	Evan	Bowers	1115	1806-09-08	1826-08-18	M	322	India	f	f	LO
323	Kristen	Wolfe	Kristen	Wolfe	30	1802-01-12	1822-11-03	F	323	Kenya	f	f	UW
324	Christopher	Lee	Christopher	Lee	1212	1802-09-01	1822-12-25	M	324	Madagascar	f	f	JV
325	Kristin	Sawyer	Kristin	Sawyer	869	1802-12-25	1822-03-03	F	325	Slovakia	f	f	AI
326	Nicholas	Dickerson	Nicholas	Dickerson	377	1804-12-10	1824-11-18	M	326	Malaysia	f	f	KI
327	Katherine	Figueroa	Katherine	Figueroa	1245	1802-07-12	1822-08-24	F	327	Kosovo	f	f	DJ
328	Lisa	Le	Lisa	Le	1215	1806-07-19	1826-05-10	M	328	Kenya	f	f	WU
329	Jon	Thornton	Jon	Thornton	1178	1804-04-25	1824-07-22	F	329	Honduras	f	f	EH
330	David	Wilkins	David	Wilkins	997	1804-07-14	1824-09-21	M	330	Burundi	f	f	JV
331	Michael	Nash	Michael	Nash	509	1804-08-16	1824-08-04	F	331	Bahamas	f	f	UU
332	Olivia	George	Olivia	George	592	1807-02-07	1827-10-09	M	332	Vietnam	f	f	YW
333	Benjamin	Oneill	Benjamin	Oneill	1180	1805-04-26	1825-04-15	F	333	Slovenia	f	f	ST
334	Scott	Ashley	Scott	Ashley	458	1807-12-20	1827-03-12	M	334	Libya	f	f	LO
335	Edward	Frank	Edward	Frank	1182	1808-12-03	1828-11-13	F	335	Burundi	f	f	XX
336	Tamara	Flores	Tamara	Flores	658	1803-06-08	1823-11-28	M	336	Somalia	f	f	BV
337	Jerry	Ramsey	Jerry	Ramsey	386	1802-11-12	1822-09-03	F	337	Thailand	f	f	QI
338	Anna	Merritt	Anna	Merritt	649	1807-01-16	1827-03-28	M	338	Brazil	f	f	AL
339	Laurie	Benson	Laurie	Benson	444	1804-07-12	1824-02-24	F	339	Uzbekistan	f	f	NA
340	Matthew	Sandoval	Matthew	Sandoval	1184	1806-02-14	1826-12-18	M	340	Ecuador	f	f	KK
341	Jerry	Taylor	Jerry	Taylor	216	1802-11-16	1822-10-25	F	341	Egypt	f	f	OM
342	Robert	Garcia	Robert	Garcia	1047	1806-02-23	1826-01-17	M	342	Switzerland	f	f	BO
343	Ashley	Keller	Ashley	Keller	104	1807-10-17	1827-07-28	F	343	Pakistan	f	f	OZ
344	Melissa	Thompson	Melissa	Thompson	177	1808-08-28	1828-04-23	M	344	Switzerland	f	f	JG
345	Kathleen	Gray	Kathleen	Gray	320	1806-02-28	1826-04-21	F	345	Nauru	f	f	NF
346	Ryan	Cochran	Ryan	Cochran	892	1806-08-09	1826-05-01	M	346	Australia	f	f	IX
347	Ashley	Wilkinson	Ashley	Wilkinson	834	1802-10-18	1822-01-24	F	347	Lebanon	f	f	XO
348	Jacqueline	Yates	Jacqueline	Yates	60	1807-07-24	1827-03-19	M	348	Spain	f	f	FN
349	Erin	Fisher	Erin	Fisher	376	1806-10-23	1826-04-15	F	349	Russia	f	f	MF
350	Christine	Garcia	Christine	Garcia	1191	1803-11-25	1823-05-07	M	350	Angola	f	f	CI
351	David	Bowman	David	Bowman	725	1803-10-16	1823-10-01	F	351	Oman	f	f	QH
352	Lance	Mosley	Lance	Mosley	1153	1807-09-28	1827-08-16	M	352	Belgium	f	f	AX
353	Kim	Rodriguez	Kim	Rodriguez	852	1805-11-27	1825-02-07	F	353	Niue	f	f	SG
354	Erin	Erickson	Erin	Erickson	56	1806-04-21	1826-05-27	M	354	Kosovo	f	f	CH
355	Rachel	Robbins	Rachel	Robbins	724	1808-09-01	1828-05-15	F	355	Mayotte	f	f	WE
356	Jake	Reilly	Jake	Reilly	484	1807-01-26	1827-08-22	M	356	Russia	f	f	PV
357	Christian	Thomas	Christian	Thomas	631	1806-12-18	1826-04-12	F	357	Israel	f	f	RD
358	Leonard	Michael	Leonard	Michael	353	1804-02-03	1824-10-18	M	358	Tajikistan	f	f	VU
359	Alyssa	Ellison	Alyssa	Ellison	150	1806-11-05	1826-05-05	F	359	Albania	f	f	LW
360	Amber	Lee	Amber	Lee	210	1804-11-17	1824-10-26	M	360	Greece	f	f	LS
361	Barbara	Jones	Barbara	Jones	472	1805-10-16	1825-04-21	F	361	Peru	f	f	WO
362	Michael	Pierce	Michael	Pierce	413	1807-10-08	1827-09-25	M	362	Bahrain	f	f	IO
363	David	Dean	David	Dean	233	1808-12-15	1828-04-03	F	363	Greenland	f	f	DM
364	Samantha	Evans	Samantha	Evans	501	1805-07-18	1825-12-01	M	364	Greece	f	f	RX
365	Carla	Lyons	Carla	Lyons	517	1802-02-23	1822-01-25	F	365	Macao	f	f	UA
366	Taylor	Williams	Taylor	Williams	586	1802-10-14	1822-01-03	M	366	Angola	f	f	YG
367	Charles	Madden	Charles	Madden	622	1805-07-21	1825-03-13	F	367	Denmark	f	f	BK
368	Michael	Davis	Michael	Davis	372	1805-09-23	1825-10-15	M	368	Tunisia	f	f	VI
369	Donna	Nelson	Donna	Nelson	550	1805-09-14	1825-10-24	F	369	Canada	f	f	RH
370	Shari	Jimenez	Shari	Jimenez	919	1808-05-09	1828-06-22	M	370	Cambodia	f	f	AZ
371	Raymond	Lopez	Raymond	Lopez	742	1806-10-19	1826-11-25	F	371	Maldives	f	f	NK
372	Amanda	Levy	Amanda	Levy	661	1807-08-13	1827-05-17	M	372	Montenegro	f	f	MZ
373	Keith	Rowland	Keith	Rowland	869	1805-01-21	1825-05-07	F	373	Benin	f	f	TN
374	Robert	Shelton	Robert	Shelton	1247	1806-02-27	1826-08-08	M	374	Lesotho	f	f	JM
375	Robert	Hutchinson	Robert	Hutchinson	795	1808-05-04	1828-06-16	F	375	Norway	f	f	EN
376	Tammy	Gomez	Tammy	Gomez	510	1806-03-18	1826-01-11	M	376	Kyrgyzstan	f	f	SZ
377	Randy	Herrera	Randy	Herrera	343	1804-01-11	1824-07-04	F	377	Armenia	f	f	PJ
378	Wendy	Oneal	Wendy	Oneal	511	1805-12-24	1825-06-22	M	378	Myanmar	f	f	GJ
379	Caitlin	Wright	Caitlin	Wright	827	1803-08-12	1823-11-24	F	379	Jamaica	f	f	PA
380	Joshua	Jones	Joshua	Jones	1061	1808-02-02	1828-02-09	M	380	Hungary	f	f	PU
381	Chris	Moore	Chris	Moore	248	1803-12-21	1823-01-20	F	381	Portugal	f	f	GO
382	Daniel	Anderson	Daniel	Anderson	970	1806-06-08	1826-02-11	M	382	Philippines	f	f	FP
383	Erin	Johnson	Erin	Johnson	1153	1804-01-08	1824-08-01	F	383	Macao	f	f	HN
384	Erika	Diaz	Erika	Diaz	352	1803-06-05	1823-02-12	M	384	Qatar	f	f	KZ
385	Angela	Wood	Angela	Wood	112	1807-11-12	1827-08-12	F	385	Liberia	f	f	BO
386	Shaun	Gates	Shaun	Gates	150	1803-09-09	1823-04-28	M	386	Iran	f	f	FL
387	Jessica	Garza	Jessica	Garza	841	1802-10-06	1822-08-27	F	387	Israel	f	f	VW
388	Margaret	Henderson	Margaret	Henderson	1002	1806-07-05	1826-06-25	M	388	Monaco	f	f	UH
389	Rebecca	Miller	Rebecca	Miller	45	1807-08-03	1827-08-17	F	389	Armenia	f	f	UW
390	Lori	Wright	Lori	Wright	924	1804-03-22	1824-11-25	M	390	Malta	f	f	SF
391	Mark	Jenkins	Mark	Jenkins	888	1802-08-04	1822-10-26	F	391	Iran	f	f	QB
392	Elizabeth	Pierce	Elizabeth	Pierce	93	1802-07-19	1822-09-12	M	392	Gabon	f	f	SW
393	Thomas	Davis	Thomas	Davis	1005	1802-05-18	1822-08-16	F	393	Djibouti	f	f	PX
394	Kenneth	Gaines	Kenneth	Gaines	1131	1803-12-23	1823-12-28	M	394	Jordan	f	f	LK
395	Jennifer	Wall	Jennifer	Wall	1113	1802-03-26	1822-02-26	F	395	Azerbaijan	f	f	QJ
396	Elizabeth	Robertson	Elizabeth	Robertson	1089	1808-03-25	1828-02-08	M	396	Algeria	f	f	PD
397	Kristin	Todd	Kristin	Todd	465	1803-02-23	1823-02-02	F	397	Belize	f	f	WD
398	Sarah	Haynes	Sarah	Haynes	752	1806-10-12	1826-07-08	M	398	Turkey	f	f	GN
399	Margaret	Beard	Margaret	Beard	97	1802-08-18	1822-12-14	F	399	Madagascar	f	f	DK
400	Jonathan	Garza	Jonathan	Garza	921	1803-11-05	1823-10-11	M	400	Cambodia	f	f	GA
401	Kristi	Stewart	Kristi	Stewart	1126	1808-01-28	1828-06-26	F	401	Vietnam	f	f	WU
402	Dwayne	Mcgee	Dwayne	Mcgee	45	1807-06-18	1827-11-25	M	402	Guatemala	f	f	FG
403	Richard	Jones	Richard	Jones	1239	1807-07-20	1827-09-22	F	403	Lebanon	f	f	YX
404	Alexandria	Alvarado	Alexandria	Alvarado	292	1807-12-23	1827-08-12	M	404	Belize	f	f	CF
405	Christina	Smith	Christina	Smith	260	1808-11-10	1828-02-19	F	405	Mexico	f	f	TT
406	Michael	Trujillo	Michael	Trujillo	127	1805-11-24	1825-03-24	M	406	Macedonia	f	f	JM
407	Jennifer	Gutierrez	Jennifer	Gutierrez	40	1806-03-17	1826-10-13	F	407	Samoa	f	f	AC
408	Christian	Cooper	Christian	Cooper	285	1805-11-13	1825-01-22	M	408	Italy	f	f	AC
409	Anthony	Jones	Anthony	Jones	174	1807-02-20	1827-01-07	F	409	Croatia	f	f	WZ
410	Pedro	Skinner	Pedro	Skinner	966	1805-12-27	1825-04-18	M	410	Monaco	f	f	KA
411	Dean	Griffin	Dean	Griffin	807	1803-06-25	1823-01-20	F	411	Philippines	f	f	BD
412	Sharon	Wells	Sharon	Wells	1010	1804-04-06	1824-05-28	M	412	Pakistan	f	f	AQ
413	Kristy	Blake	Kristy	Blake	834	1803-08-05	1823-05-22	F	413	Tanzania	f	f	MM
414	Stephen	Morales	Stephen	Morales	98	1807-11-10	1827-11-09	M	414	Gibraltar	f	f	PO
415	Meghan	Patton	Meghan	Patton	386	1807-07-10	1827-10-16	F	415	Georgia	f	f	CE
416	Debra	Rivera	Debra	Rivera	892	1808-09-25	1828-04-23	M	416	Slovakia	f	f	EJ
417	Chad	White	Chad	White	1131	1804-08-20	1824-11-24	F	417	Spain	f	f	WT
418	Darrell	Pace	Darrell	Pace	210	1802-02-24	1822-01-23	M	418	Canada	f	f	VY
419	Paul	Miller	Paul	Miller	1213	1807-10-16	1827-05-07	F	419	Dominica	f	f	EL
420	Martha	Ware	Martha	Ware	379	1802-12-21	1822-03-18	M	420	Uganda	f	f	RG
421	Leslie	Roberts	Leslie	Roberts	318	1803-02-09	1823-06-26	F	421	Zambia	f	f	QJ
422	Phillip	Nelson	Phillip	Nelson	680	1804-03-28	1824-06-28	M	422	Germany	f	f	DP
423	Jack	Miller	Jack	Miller	58	1805-10-21	1825-04-06	F	423	Moldova	f	f	GI
424	Justin	Williams	Justin	Williams	16	1802-01-04	1822-10-20	M	424	Tanzania	f	f	OU
425	Marcia	Mcdonald	Marcia	Mcdonald	1197	1805-06-28	1825-03-03	F	425	Venezuela	f	f	ZB
426	Erin	Cox	Erin	Cox	513	1806-10-09	1826-12-10	M	426	Turkey	f	f	DB
427	Richard	Barker	Richard	Barker	847	1804-05-18	1824-07-02	F	427	Somalia	f	f	LX
428	Meredith	Woodward	Meredith	Woodward	239	1806-08-11	1826-05-24	M	428	Spain	f	f	XW
429	Emma	Mendez	Emma	Mendez	503	1806-07-25	1826-09-21	F	429	Maldives	f	f	HW
430	John	Guzman	John	Guzman	728	1808-05-22	1828-08-20	M	430	Chile	f	f	IH
431	Kelly	Medina	Kelly	Medina	500	1806-03-16	1826-11-28	F	431	Malta	f	f	CP
432	Erica	Middleton	Erica	Middleton	478	1806-05-01	1826-10-06	M	432	Canada	f	f	MC
433	Natalie	Mata	Natalie	Mata	1086	1807-06-02	1827-07-19	F	433	Honduras	f	f	JQ
434	Monique	Harris	Monique	Harris	839	1805-04-01	1825-03-08	M	434	Luxembourg	f	f	EG
435	Amber	Williams	Amber	Williams	526	1802-12-15	1822-06-17	F	435	China	f	f	QC
436	Jessica	Gibson	Jessica	Gibson	1106	1806-06-16	1826-11-14	M	436	Suriname	f	f	TG
437	Jennifer	Woods	Jennifer	Woods	1085	1805-12-23	1825-02-02	F	437	Bahrain	f	f	MJ
438	Stacie	Burns	Stacie	Burns	857	1806-12-03	1826-06-08	M	438	Liechtenstein	f	f	RE
439	Tyler	Martinez	Tyler	Martinez	425	1803-01-21	1823-08-20	F	439	Nigeria	f	f	WW
440	Ana	Douglas	Ana	Douglas	509	1802-09-21	1822-04-03	M	440	Burundi	f	f	KR
441	Alan	Frazier	Alan	Frazier	1165	1807-09-23	1827-01-02	F	441	Indonesia	f	f	BF
442	Stephen	Murphy	Stephen	Murphy	1144	1807-04-11	1827-06-12	M	442	Suriname	f	f	QZ
443	Jeffrey	Miller	Jeffrey	Miller	542	1807-12-02	1827-03-21	F	443	Turkmenistan	f	f	JX
444	Emily	Mooney	Emily	Mooney	96	1804-07-05	1824-03-17	M	444	Brunei	f	f	ET
445	Justin	Palmer	Justin	Palmer	655	1807-07-07	1827-11-15	F	445	Libya	f	f	VX
446	Christy	Robbins	Christy	Robbins	1086	1803-12-13	1823-04-01	M	446	Bhutan	f	f	ZI
447	Joseph	Kennedy	Joseph	Kennedy	413	1802-10-20	1822-03-05	F	447	Nauru	f	f	LP
448	Veronica	Waters	Veronica	Waters	995	1804-08-10	1824-12-01	M	448	Azerbaijan	f	f	IA
449	Benjamin	Blair	Benjamin	Blair	733	1807-05-10	1827-03-11	F	449	Suriname	f	f	EL
450	Amanda	Morgan	Amanda	Morgan	416	1807-09-04	1827-10-04	M	450	Uruguay	f	f	UG
451	Nathaniel	Jackson	Nathaniel	Jackson	561	1804-02-18	1824-02-17	F	451	Nauru	f	f	ZR
452	John	Hensley	John	Hensley	1015	1807-04-09	1827-04-16	M	452	Mozambique	f	f	JH
453	Veronica	Hart	Veronica	Hart	494	1805-06-22	1825-01-14	F	453	Mauritius	f	f	ZM
454	Jeremy	Snyder	Jeremy	Snyder	349	1804-10-23	1824-10-05	M	454	Turkmenistan	f	f	JJ
455	Amanda	Lambert	Amanda	Lambert	513	1804-11-16	1824-03-19	F	455	Chad	f	f	KW
456	Christopher	Stark	Christopher	Stark	592	1804-03-21	1824-04-04	M	456	Finland	f	f	SU
457	Daniel	Duran	Daniel	Duran	1112	1807-10-18	1827-02-01	F	457	Panama	f	f	RU
458	Kevin	Mcconnell	Kevin	Mcconnell	1209	1808-12-22	1828-03-16	M	458	Moldova	f	f	XX
459	Troy	Montes	Troy	Montes	1238	1808-06-25	1828-11-21	F	459	Jamaica	f	f	RH
460	Jose	Smith	Jose	Smith	661	1805-06-07	1825-02-17	M	460	Togo	f	f	XK
461	Kevin	Kramer	Kevin	Kramer	433	1805-05-25	1825-08-17	F	461	Liberia	f	f	FL
462	Elizabeth	Carter	Elizabeth	Carter	423	1804-12-26	1824-07-05	M	462	Uganda	f	f	SE
463	Anthony	Woods	Anthony	Woods	876	1806-12-16	1826-01-25	F	463	Azerbaijan	f	f	NL
464	Jennifer	Shaffer	Jennifer	Shaffer	882	1807-04-08	1827-08-23	M	464	Philippines	f	f	UX
465	Erika	Tran	Erika	Tran	1003	1803-01-12	1823-05-17	F	465	Senegal	f	f	JO
466	Colleen	Hampton	Colleen	Hampton	634	1804-11-28	1824-08-17	M	466	Fiji	f	f	CG
467	Allison	Johnson	Allison	Johnson	441	1802-11-22	1822-12-26	F	467	Madagascar	f	f	AA
468	Donald	Mcguire	Donald	Mcguire	627	1803-06-15	1823-06-15	M	468	Montenegro	f	f	TM
469	Elizabeth	Snyder	Elizabeth	Snyder	243	1803-03-14	1823-06-19	F	469	Laos	f	f	HW
470	Nathan	Elliott	Nathan	Elliott	655	1808-01-08	1828-02-02	M	470	Montserrat	f	f	BH
471	Ana	Ford	Ana	Ford	918	1803-11-05	1823-04-20	F	471	Malta	f	f	EA
472	Matthew	Juarez	Matthew	Juarez	243	1805-02-03	1825-05-20	M	472	Montenegro	f	f	WG
473	Monica	Stewart	Monica	Stewart	1086	1802-11-15	1822-12-17	F	473	Macao	f	f	XM
474	Preston	Jensen	Preston	Jensen	1000	1803-06-26	1823-06-10	M	474	Libya	f	f	VV
475	Valerie	Strickland	Valerie	Strickland	541	1802-04-01	1822-12-06	F	475	Tuvalu	f	f	NV
476	Amy	Murphy	Amy	Murphy	966	1804-07-01	1824-08-21	M	476	Honduras	f	f	SL
477	Krista	Morgan	Krista	Morgan	622	1805-03-13	1825-06-13	F	477	Uganda	f	f	FM
478	Samuel	Le	Samuel	Le	843	1803-10-28	1823-08-01	M	478	Chile	f	f	HP
479	Sierra	Bentley	Sierra	Bentley	1125	1806-11-15	1826-07-08	F	479	Thailand	f	f	DT
480	Wyatt	Nelson	Wyatt	Nelson	199	1807-07-09	1827-03-27	M	480	Bangladesh	f	f	HG
481	Steven	Ramos	Steven	Ramos	1061	1802-03-02	1822-12-16	F	481	Jamaica	f	f	HY
482	Jason	Peters	Jason	Peters	839	1807-11-24	1827-03-17	M	482	Fiji	f	f	HW
483	Frank	Sanchez	Frank	Sanchez	834	1806-01-27	1826-02-01	F	483	China	f	f	MW
484	James	Sloan	James	Sloan	1111	1803-09-21	1823-08-24	M	484	Seychelles	f	f	BG
485	Thomas	Anderson	Thomas	Anderson	77	1806-02-13	1826-09-23	F	485	Singapore	f	f	LY
486	Samuel	Cuevas	Samuel	Cuevas	701	1808-03-13	1828-11-01	M	486	Singapore	f	f	OB
487	Ian	Hoffman	Ian	Hoffman	343	1806-08-21	1826-03-24	F	487	Maldives	f	f	VT
488	Derek	Blair	Derek	Blair	125	1805-07-09	1825-03-07	M	488	Hungary	f	f	TK
489	Alexandria	Richard	Alexandria	Richard	687	1802-09-19	1822-12-01	F	489	Turkey	f	f	GE
490	Craig	Blake	Craig	Blake	247	1806-12-18	1826-12-03	M	490	Jamaica	f	f	JA
491	Jonathan	Alvarado	Jonathan	Alvarado	1182	1802-10-10	1822-10-10	F	491	Tajikistan	f	f	AX
492	Steven	Miranda	Steven	Miranda	95	1803-07-22	1823-09-08	M	492	Taiwan	f	f	BR
493	Dennis	Wiggins	Dennis	Wiggins	1114	1804-07-13	1824-11-19	F	493	Belize	f	f	GZ
494	Elizabeth	Bailey	Elizabeth	Bailey	1051	1808-04-10	1828-05-18	M	494	Gambia	f	f	QP
495	Cheryl	Henry	Cheryl	Henry	1112	1805-11-09	1825-10-20	F	495	Barbados	f	f	WH
496	Jacqueline	Bailey	Jacqueline	Bailey	514	1805-12-16	1825-10-16	M	496	Indonesia	f	f	IH
497	Ashley	Baker	Ashley	Baker	662	1808-11-17	1828-06-26	F	497	Netherlands	f	f	CJ
498	Kenneth	Williams	Kenneth	Williams	354	1808-02-02	1828-02-19	M	498	Bulgaria	f	f	VS
499	Donald	Mejia	Donald	Mejia	316	1804-10-12	1824-11-05	F	499	Suriname	f	f	UU
500					796	1808-08-08	1828-10-19	M	500	Turkmenistan	f	f	NY
\.


--
-- Data for Name: marriage_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriage_certificates (id, marriage_id, issuer, issue_date) FROM stdin;
1	1	1217	1984-05-17
2	2	1062	1959-10-23
3	3	713	1963-05-22
4	4	987	1938-06-05
5	5	347	1938-11-17
6	6	1235	1932-06-05
7	7	616	1937-04-05
8	8	985	1910-02-18
9	9	578	1910-03-14
10	10	111	1906-03-22
11	11	727	1913-04-05
12	12	311	1912-12-02
13	13	235	1908-03-19
14	14	949	1911-09-13
15	15	892	1906-05-26
16	16	360	1882-04-06
17	17	1110	1883-10-10
18	18	611	1881-12-11
19	19	99	1888-01-03
20	20	1049	1886-04-18
21	21	316	1883-04-04
22	22	138	1888-09-13
23	23	234	1884-05-14
24	24	678	1886-11-22
25	25	124	1887-04-14
26	26	931	1882-09-22
27	27	1137	1883-09-19
28	28	564	1887-04-05
29	29	209	1881-06-09
30	30	1011	1884-01-23
31	31	943	1885-03-20
32	32	624	1863-12-07
33	33	338	1856-07-09
34	34	90	1863-06-11
35	35	125	1859-08-17
36	36	1056	1860-05-09
37	37	38	1859-09-09
38	38	613	1863-11-09
39	39	638	1859-10-20
40	40	430	1863-07-20
41	41	616	1861-06-24
42	42	223	1860-04-23
43	43	580	1858-08-28
44	44	1077	1863-04-16
45	45	545	1856-03-07
46	46	1196	1862-08-02
47	47	927	1857-02-19
48	48	1191	1863-10-27
49	49	772	1857-05-13
50	50	729	1863-08-28
51	51	711	1856-01-18
52	52	54	1856-10-20
53	53	1181	1862-03-18
54	54	761	1862-01-01
55	55	446	1862-12-16
56	56	168	1858-08-01
57	57	669	1863-06-22
58	58	384	1862-04-15
59	59	1226	1863-05-06
60	60	1041	1857-08-11
61	61	1047	1860-07-12
62	62	730	1862-02-22
63	63	1116	1860-03-16
64	64	958	1837-11-27
65	65	114	1837-05-22
66	66	1099	1833-02-01
67	67	481	1833-02-22
68	68	552	1834-08-05
69	69	57	1832-12-04
70	70	670	1832-04-22
71	71	813	1834-02-19
72	72	1094	1835-08-16
73	73	1094	1836-01-13
74	74	1158	1838-03-14
75	75	822	1835-05-18
76	76	511	1835-11-07
77	77	730	1832-12-09
78	78	1241	1836-09-10
79	79	716	1838-08-01
80	80	204	1834-10-17
81	81	496	1833-07-13
82	82	769	1835-08-26
83	83	433	1836-12-14
84	84	1023	1836-09-07
85	85	872	1832-02-26
86	86	109	1837-09-10
87	87	159	1838-12-16
88	88	1037	1832-04-01
89	89	165	1834-11-26
90	90	817	1836-05-28
91	91	161	1835-09-04
92	92	225	1837-04-28
93	93	819	1833-10-12
94	94	794	1836-12-23
95	95	961	1833-05-12
96	96	1003	1837-08-19
97	97	879	1833-06-16
98	98	854	1833-06-26
99	99	73	1838-11-26
100	100	433	1835-08-06
101	101	1173	1836-03-21
102	102	645	1834-06-04
103	103	1115	1837-10-08
104	104	347	1831-01-18
105	105	1188	1831-07-14
106	106	1047	1836-05-22
107	107	893	1835-09-05
108	108	1231	1831-03-02
109	109	953	1834-11-27
110	110	186	1834-11-19
111	111	832	1834-09-11
112	112	251	1838-08-13
113	113	997	1831-05-10
114	114	363	1831-10-07
115	115	799	1838-11-01
116	116	1000	1834-06-21
117	117	90	1834-01-11
118	118	501	1836-12-16
119	119	565	1833-01-14
120	120	184	1837-09-09
121	121	251	1837-06-03
122	122	216	1834-07-26
123	123	995	1833-07-10
124	124	457	1838-09-12
125	125	554	1831-05-25
126	126	1104	1836-02-19
127	127	367	1833-08-26
128	128	367	1812-02-10
129	129	695	1809-06-06
130	130	434	1812-10-11
131	131	1016	1813-04-25
132	132	333	1808-06-06
133	133	217	1807-08-04
134	134	1121	1807-06-24
135	135	394	1807-04-06
136	136	220	1808-12-20
137	137	1023	1810-10-25
138	138	1016	1810-01-04
139	139	880	1810-10-17
140	140	145	1809-11-17
141	141	1112	1807-12-25
142	142	1130	1807-04-17
143	143	337	1806-08-06
144	144	558	1807-03-22
145	145	1042	1812-03-19
146	146	119	1808-03-21
147	147	1120	1809-06-03
148	148	12	1809-09-22
149	149	215	1807-03-05
150	150	949	1808-02-13
151	151	1157	1807-08-24
152	152	690	1809-01-02
153	153	207	1811-11-08
154	154	942	1810-07-27
155	155	1120	1809-10-12
156	156	31	1812-10-27
157	157	91	1809-07-20
158	158	265	1809-07-02
159	159	291	1811-10-03
160	160	934	1809-01-01
161	161	694	1810-02-14
162	162	1070	1808-07-28
163	163	1077	1806-02-15
164	164	118	1811-06-26
165	165	1035	1810-06-08
166	166	432	1809-01-16
167	167	7	1806-04-16
168	168	942	1810-06-25
169	169	1195	1809-09-21
170	170	716	1812-07-19
171	171	811	1812-04-22
172	172	251	1810-09-05
173	173	1124	1813-02-26
174	174	286	1812-10-06
175	175	813	1809-05-18
176	176	61	1809-08-27
177	177	213	1807-02-20
178	178	674	1812-02-28
179	179	205	1813-12-05
180	180	166	1808-05-09
181	181	1002	1812-10-17
182	182	656	1807-10-22
183	183	58	1811-03-16
184	184	1161	1813-03-27
185	185	235	1813-12-03
186	186	902	1808-03-08
187	187	148	1809-04-17
188	188	1144	1809-05-06
189	189	440	1810-09-19
190	190	1091	1813-11-10
191	191	425	1813-02-02
192	192	333	1809-02-26
193	193	338	1812-04-05
194	194	635	1807-01-05
195	195	592	1806-08-01
196	196	323	1811-11-25
197	197	1195	1807-12-21
198	198	66	1808-05-26
199	199	958	1812-12-25
200	200	434	1809-07-27
201	201	936	1808-08-12
202	202	157	1810-08-26
203	203	291	1807-01-04
204	204	158	1809-02-02
205	205	479	1813-01-21
206	206	924	1809-11-14
207	207	564	1812-02-13
208	208	1121	1813-02-10
209	209	193	1806-10-01
210	210	1136	1809-12-05
211	211	1114	1813-08-14
212	212	507	1806-11-12
213	213	1100	1813-10-18
214	214	264	1806-06-09
215	215	457	1811-09-15
216	216	488	1812-05-15
217	217	1088	1808-04-25
218	218	1121	1808-12-12
219	219	500	1806-03-19
220	220	880	1809-05-24
221	221	1003	1811-12-05
222	222	192	1813-06-08
223	223	761	1808-11-27
224	224	388	1807-10-14
225	225	1248	1809-01-11
226	226	925	1812-01-04
227	227	1113	1813-10-20
228	228	1156	1807-12-19
229	229	924	1812-04-08
230	230	1248	1809-12-02
231	231	533	1813-02-10
232	232	38	1812-09-03
233	233	216	1813-06-12
234	234	599	1809-08-28
235	235	1088	1806-10-09
236	236	91	1806-10-14
237	237	1027	1811-04-14
238	238	265	1807-09-09
239	239	496	1808-07-21
240	240	799	1807-07-28
241	241	56	1807-12-17
242	242	778	1808-11-11
243	243	1112	1813-11-20
244	244	1168	1810-08-11
245	245	630	1808-12-23
246	246	1241	1810-03-15
247	247	19	1811-05-25
248	248	71	1810-12-23
249	249	1191	1808-01-09
\.


--
-- Data for Name: marriages; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriages (id, person1, person2, marriage_date) FROM stdin;
1	2	3	1984-05-17
2	4	5	1959-10-23
3	6	7	1963-05-22
4	8	9	1938-06-05
5	10	11	1938-11-17
6	12	13	1932-06-05
7	14	15	1937-04-05
8	16	17	1910-02-18
9	18	19	1910-03-14
10	20	21	1906-03-22
11	22	23	1913-04-05
12	24	25	1912-12-02
13	26	27	1908-03-19
14	28	29	1911-09-13
15	30	31	1906-05-26
16	32	33	1882-04-06
17	34	35	1883-10-10
18	36	37	1881-12-11
19	38	39	1888-01-03
20	40	41	1886-04-18
21	42	43	1883-04-04
22	44	45	1888-09-13
23	46	47	1884-05-14
24	48	49	1886-11-22
25	50	51	1887-04-14
26	52	53	1882-09-22
27	54	55	1883-09-19
28	56	57	1887-04-05
29	58	59	1881-06-09
30	60	61	1884-01-23
31	62	63	1885-03-20
32	64	65	1863-12-07
33	66	67	1856-07-09
34	68	69	1863-06-11
35	70	71	1859-08-17
36	72	73	1860-05-09
37	74	75	1859-09-09
38	76	77	1863-11-09
39	78	79	1859-10-20
40	80	81	1863-07-20
41	82	83	1861-06-24
42	84	85	1860-04-23
43	86	87	1858-08-28
44	88	89	1863-04-16
45	90	91	1856-03-07
46	92	93	1862-08-02
47	94	95	1857-02-19
48	96	97	1863-10-27
49	98	99	1857-05-13
50	100	101	1863-08-28
51	102	103	1856-01-18
52	104	105	1856-10-20
53	106	107	1862-03-18
54	108	109	1862-01-01
55	110	111	1862-12-16
56	112	113	1858-08-01
57	114	115	1863-06-22
58	116	117	1862-04-15
59	118	119	1863-05-06
60	120	121	1857-08-11
61	122	123	1860-07-12
62	124	125	1862-02-22
63	126	127	1860-03-16
64	128	129	1837-11-27
65	130	131	1837-05-22
66	132	133	1833-02-01
67	134	135	1833-02-22
68	136	137	1834-08-05
69	138	139	1832-12-04
70	140	141	1832-04-22
71	142	143	1834-02-19
72	144	145	1835-08-16
73	146	147	1836-01-13
74	148	149	1838-03-14
75	150	151	1835-05-18
76	152	153	1835-11-07
77	154	155	1832-12-09
78	156	157	1836-09-10
79	158	159	1838-08-01
80	160	161	1834-10-17
81	162	163	1833-07-13
82	164	165	1835-08-26
83	166	167	1836-12-14
84	168	169	1836-09-07
85	170	171	1832-02-26
86	172	173	1837-09-10
87	174	175	1838-12-16
88	176	177	1832-04-01
89	178	179	1834-11-26
90	180	181	1836-05-28
91	182	183	1835-09-04
92	184	185	1837-04-28
93	186	187	1833-10-12
94	188	189	1836-12-23
95	190	191	1833-05-12
96	192	193	1837-08-19
97	194	195	1833-06-16
98	196	197	1833-06-26
99	198	199	1838-11-26
100	200	201	1835-08-06
101	202	203	1836-03-21
102	204	205	1834-06-04
103	206	207	1837-10-08
104	208	209	1831-01-18
105	210	211	1831-07-14
106	212	213	1836-05-22
107	214	215	1835-09-05
108	216	217	1831-03-02
109	218	219	1834-11-27
110	220	221	1834-11-19
111	222	223	1834-09-11
112	224	225	1838-08-13
113	226	227	1831-05-10
114	228	229	1831-10-07
115	230	231	1838-11-01
116	232	233	1834-06-21
117	234	235	1834-01-11
118	236	237	1836-12-16
119	238	239	1833-01-14
120	240	241	1837-09-09
121	242	243	1837-06-03
122	244	245	1834-07-26
123	246	247	1833-07-10
124	248	249	1838-09-12
125	250	251	1831-05-25
126	252	253	1836-02-19
127	254	255	1833-08-26
128	256	257	1812-02-10
129	258	259	1809-06-06
130	260	261	1812-10-11
131	262	263	1813-04-25
132	264	265	1808-06-06
133	266	267	1807-08-04
134	268	269	1807-06-24
135	270	271	1807-04-06
136	272	273	1808-12-20
137	274	275	1810-10-25
138	276	277	1810-01-04
139	278	279	1810-10-17
140	280	281	1809-11-17
141	282	283	1807-12-25
142	284	285	1807-04-17
143	286	287	1806-08-06
144	288	289	1807-03-22
145	290	291	1812-03-19
146	292	293	1808-03-21
147	294	295	1809-06-03
148	296	297	1809-09-22
149	298	299	1807-03-05
150	300	301	1808-02-13
151	302	303	1807-08-24
152	304	305	1809-01-02
153	306	307	1811-11-08
154	308	309	1810-07-27
155	310	311	1809-10-12
156	312	313	1812-10-27
157	314	315	1809-07-20
158	316	317	1809-07-02
159	318	319	1811-10-03
160	320	321	1809-01-01
161	322	323	1810-02-14
162	324	325	1808-07-28
163	326	327	1806-02-15
164	328	329	1811-06-26
165	330	331	1810-06-08
166	332	333	1809-01-16
167	334	335	1806-04-16
168	336	337	1810-06-25
169	338	339	1809-09-21
170	340	341	1812-07-19
171	342	343	1812-04-22
172	344	345	1810-09-05
173	346	347	1813-02-26
174	348	349	1812-10-06
175	350	351	1809-05-18
176	352	353	1809-08-27
177	354	355	1807-02-20
178	356	357	1812-02-28
179	358	359	1813-12-05
180	360	361	1808-05-09
181	362	363	1812-10-17
182	364	365	1807-10-22
183	366	367	1811-03-16
184	368	369	1813-03-27
185	370	371	1813-12-03
186	372	373	1808-03-08
187	374	375	1809-04-17
188	376	377	1809-05-06
189	378	379	1810-09-19
190	380	381	1813-11-10
191	382	383	1813-02-02
192	384	385	1809-02-26
193	386	387	1812-04-05
194	388	389	1807-01-05
195	390	391	1806-08-01
196	392	393	1811-11-25
197	394	395	1807-12-21
198	396	397	1808-05-26
199	398	399	1812-12-25
200	400	401	1809-07-27
201	402	403	1808-08-12
202	404	405	1810-08-26
203	406	407	1807-01-04
204	408	409	1809-02-02
205	410	411	1813-01-21
206	412	413	1809-11-14
207	414	415	1812-02-13
208	416	417	1813-02-10
209	418	419	1806-10-01
210	420	421	1809-12-05
211	422	423	1813-08-14
212	424	425	1806-11-12
213	426	427	1813-10-18
214	428	429	1806-06-09
215	430	431	1811-09-15
216	432	433	1812-05-15
217	434	435	1808-04-25
218	436	437	1808-12-12
219	438	439	1806-03-19
220	440	441	1809-05-24
221	442	443	1811-12-05
222	444	445	1813-06-08
223	446	447	1808-11-27
224	448	449	1807-10-14
225	450	451	1809-01-11
226	452	453	1812-01-04
227	454	455	1813-10-20
228	456	457	1807-12-19
229	458	459	1812-04-08
230	460	461	1809-12-02
231	462	463	1813-02-10
232	464	465	1812-09-03
233	466	467	1813-06-12
234	468	469	1809-08-28
235	470	471	1806-10-09
236	472	473	1806-10-14
237	474	475	1811-04-14
238	476	477	1807-09-09
239	478	479	1808-07-21
240	480	481	1807-07-28
241	482	483	1807-12-17
242	484	485	1808-11-11
243	486	487	1813-11-20
244	488	489	1810-08-11
245	490	491	1808-12-23
246	492	493	1810-03-15
247	494	495	1811-05-25
248	496	497	1810-12-23
249	498	499	1808-01-09
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
1	5
1	2
1	4
2	1
2	3
2	4
2	5
2	2
3	5
3	1
3	4
3	2
4	1
5	1
6	5
7	3
7	1
7	4
7	2
8	4
8	5
8	1
9	1
9	5
9	3
9	4
9	2
10	5
10	3
10	4
10	2
10	1
11	5
12	5
12	3
12	4
12	1
12	2
13	3
13	2
13	5
14	3
14	1
14	4
15	5
15	1
16	1
16	4
16	5
17	3
17	4
18	5
18	4
19	2
19	1
19	3
20	4
20	3
21	3
21	2
21	1
22	2
23	2
23	4
23	5
23	3
23	1
24	1
25	3
26	5
26	4
27	4
27	2
27	1
27	5
28	3
28	1
28	5
29	4
29	5
29	1
30	1
30	4
30	3
31	1
31	3
31	4
31	2
31	5
32	2
32	4
33	3
33	2
33	5
34	3
34	1
34	5
34	4
35	5
35	4
36	1
36	4
36	5
37	4
37	5
38	5
38	4
38	2
38	3
39	3
39	1
39	4
39	5
40	4
40	1
40	5
41	2
41	3
41	5
41	4
42	2
43	2
44	2
44	5
45	1
45	5
45	3
45	2
46	3
46	5
46	1
46	4
46	2
47	2
47	5
47	4
47	1
48	5
48	4
48	1
49	1
49	2
49	5
49	3
50	4
50	3
50	2
51	5
51	4
51	3
52	4
52	2
53	3
53	4
53	1
53	5
53	2
54	1
54	2
55	4
56	1
56	5
56	2
56	3
57	5
57	2
57	4
57	3
57	1
58	2
58	3
58	5
58	4
58	1
59	4
59	2
59	3
60	4
60	2
60	1
60	5
61	3
61	4
61	2
62	1
62	3
62	5
62	2
62	4
63	1
63	4
63	3
64	1
65	1
65	2
66	2
66	4
66	1
67	5
68	2
68	1
68	4
69	4
69	1
69	2
69	5
69	3
70	5
71	2
71	1
71	4
72	4
72	3
72	1
72	5
73	2
73	1
73	4
74	3
75	3
75	2
75	1
76	4
76	2
76	3
77	1
77	4
77	2
77	5
78	3
78	5
78	1
78	4
79	5
79	3
80	5
80	2
80	3
80	4
81	1
82	3
82	5
82	4
83	1
83	3
83	4
83	2
84	4
84	2
84	3
85	1
85	5
85	4
86	3
87	2
88	2
88	1
88	5
88	3
89	3
89	5
90	1
90	3
90	5
90	2
91	1
91	4
91	2
91	3
91	5
92	5
92	2
92	3
92	4
93	1
94	5
94	4
95	1
95	3
95	5
95	4
96	1
97	3
97	1
97	5
97	4
98	1
98	3
98	5
98	4
98	2
99	4
99	5
99	2
99	1
99	3
100	3
100	5
100	1
101	1
101	2
101	4
101	5
101	3
102	1
102	4
102	3
103	1
103	3
103	5
103	4
103	2
104	1
104	3
104	5
104	2
105	1
105	2
105	5
106	4
106	2
106	1
106	5
106	3
107	5
108	5
108	2
108	3
108	1
109	5
109	2
109	4
110	2
110	3
110	1
110	4
111	5
111	4
111	2
111	3
111	1
112	1
113	1
114	1
114	4
114	5
114	2
115	1
115	3
116	1
117	2
117	4
117	1
117	3
118	1
118	2
118	5
118	3
118	4
119	3
119	1
119	2
120	5
120	1
120	2
121	1
121	5
122	2
123	4
123	3
124	4
124	1
124	3
124	2
124	5
125	3
125	1
125	2
125	4
125	5
126	4
126	1
126	3
127	5
127	4
127	2
127	3
127	1
128	5
128	1
128	2
128	3
128	4
129	5
130	5
130	1
131	5
131	4
131	2
131	3
132	5
132	4
133	2
133	4
134	1
135	1
135	5
136	5
136	3
137	3
138	5
138	1
138	4
138	3
138	2
139	1
139	3
139	2
140	2
140	3
140	1
140	5
140	4
141	4
142	3
142	1
143	4
143	2
143	3
144	2
145	4
145	5
145	1
145	2
145	3
146	1
146	3
146	4
146	2
147	3
147	1
147	4
147	2
147	5
148	2
148	4
149	4
150	2
150	4
150	1
151	2
151	5
151	1
151	4
151	3
152	3
152	4
152	2
152	5
153	4
153	1
154	3
154	5
154	2
154	4
155	3
155	1
155	4
155	2
156	5
156	4
156	3
156	2
156	1
157	2
157	5
158	3
158	2
158	1
159	3
159	1
159	2
159	4
159	5
160	5
161	3
161	1
161	2
162	1
162	2
162	5
163	5
163	3
164	3
165	4
165	1
165	2
165	3
165	5
166	2
166	4
167	1
167	3
167	4
167	2
168	5
168	2
169	3
170	5
170	2
170	1
170	3
170	4
171	1
172	4
172	3
172	2
173	2
174	3
174	1
174	5
174	4
175	2
176	4
176	3
176	5
176	2
176	1
177	1
177	5
177	3
178	4
179	2
179	1
179	4
179	3
179	5
180	5
180	1
180	3
180	2
181	3
181	4
181	2
181	5
182	1
182	3
182	2
182	4
183	4
183	1
183	2
183	5
184	5
184	2
184	3
185	2
185	5
185	1
186	1
186	2
186	3
186	4
187	2
187	3
188	2
189	3
189	1
189	2
189	5
189	4
190	5
190	1
190	2
191	3
192	5
192	2
193	2
193	3
193	4
193	5
193	1
194	5
194	2
194	3
194	4
195	3
195	1
195	2
195	4
195	5
196	4
196	5
196	3
197	5
197	4
197	3
197	1
198	1
198	5
198	2
198	4
198	3
199	4
199	1
199	5
200	5
200	4
200	3
201	1
202	2
202	5
202	4
203	4
204	2
204	4
204	1
204	5
204	3
205	1
205	5
205	2
205	4
205	3
206	4
206	5
206	3
206	1
207	4
207	1
207	3
207	2
207	5
208	5
208	1
208	3
208	4
208	2
209	4
209	5
209	3
209	2
210	1
210	3
210	5
210	4
211	3
212	2
212	4
212	3
213	5
213	3
213	2
213	1
214	2
214	5
215	2
215	4
215	5
215	3
216	2
216	5
216	4
216	3
216	1
217	3
217	2
217	4
217	5
218	2
218	4
218	3
218	1
219	5
219	4
219	3
220	2
220	1
220	5
220	3
220	4
221	4
222	2
222	5
223	3
223	1
223	2
224	1
225	3
225	4
225	1
225	2
225	5
226	1
226	5
227	2
227	3
228	5
228	2
228	4
229	3
229	1
230	4
230	1
230	2
230	5
230	3
231	2
231	1
231	3
231	5
232	1
232	3
232	5
232	2
233	3
233	1
233	2
234	1
234	2
234	3
234	4
234	5
235	1
235	5
235	2
235	4
236	4
237	5
237	1
238	2
238	3
238	5
239	4
239	3
239	1
239	5
240	1
240	5
240	2
241	2
242	3
242	1
242	2
242	5
242	4
243	1
243	5
244	5
244	2
244	1
244	3
244	4
245	4
245	1
245	3
245	2
245	5
246	4
246	3
246	5
247	5
247	2
247	4
247	3
247	1
248	5
248	1
249	1
250	4
251	1
251	2
251	3
251	5
252	4
252	3
253	3
253	2
253	5
253	1
254	5
255	5
255	4
255	2
256	3
256	2
257	3
257	4
258	2
258	3
259	5
260	1
260	3
260	4
260	5
260	2
261	5
261	3
261	4
262	1
262	4
263	1
263	5
264	3
264	2
264	1
264	5
264	4
265	4
265	2
265	1
265	5
265	3
266	4
266	3
266	1
266	5
266	2
267	2
267	3
268	1
269	5
270	4
270	3
270	1
270	5
271	1
271	5
272	5
272	4
272	3
272	1
273	2
273	1
273	5
274	5
274	4
274	3
275	3
275	2
276	1
277	5
277	3
277	4
277	2
277	1
278	5
278	3
278	4
278	1
279	5
280	4
280	5
280	2
280	3
280	1
281	4
281	5
282	5
282	4
282	2
282	3
283	1
283	2
284	5
285	2
285	3
285	1
286	4
286	2
287	2
287	4
287	5
287	1
288	5
288	1
288	3
289	2
289	3
289	5
289	1
289	4
290	1
290	5
290	4
290	3
291	3
291	1
291	2
292	1
292	2
292	3
293	3
293	5
294	1
294	5
294	3
295	4
295	5
295	1
296	2
296	4
296	1
297	5
297	1
298	4
298	3
298	5
298	2
299	2
299	1
299	4
300	2
300	1
300	5
300	3
301	3
301	2
301	4
301	5
302	2
303	4
303	2
304	3
304	4
304	5
304	2
305	1
305	3
306	3
307	4
307	3
308	5
308	2
308	3
308	4
309	5
309	2
309	3
309	4
309	1
310	1
310	3
310	5
311	5
311	2
312	3
312	2
312	4
312	1
313	3
313	5
313	1
313	2
314	2
314	1
314	4
315	5
315	3
315	1
315	2
315	4
316	1
316	2
316	4
316	3
316	5
317	3
318	4
318	2
318	5
318	3
318	1
319	2
319	4
319	5
319	3
320	5
320	1
320	4
320	3
321	4
321	3
321	2
321	5
322	5
323	1
323	2
323	4
323	3
324	1
324	4
325	1
325	3
326	1
326	4
326	5
326	3
326	2
327	3
327	1
327	5
328	1
328	4
328	3
328	2
328	5
329	1
329	2
329	3
329	4
329	5
330	5
330	4
331	2
331	1
331	4
331	3
332	2
332	3
332	4
332	1
332	5
333	4
333	2
333	1
334	4
334	5
334	3
335	2
335	4
336	5
336	4
337	3
337	2
337	5
338	2
339	5
339	2
339	4
339	3
340	2
340	4
340	5
340	3
340	1
341	3
341	1
341	4
341	5
342	2
342	1
343	5
343	3
343	2
343	4
343	1
344	5
345	4
345	3
345	1
345	2
345	5
346	2
346	1
346	5
346	4
347	3
347	1
347	2
347	5
347	4
348	4
348	5
349	3
349	4
349	5
349	2
349	1
350	5
350	3
351	5
352	4
352	5
352	1
352	2
353	3
353	1
353	2
353	4
353	5
354	3
354	1
355	1
355	4
355	3
356	3
357	5
357	1
357	4
357	3
358	4
358	1
358	2
358	5
358	3
359	4
359	1
359	3
359	2
359	5
360	3
360	5
360	2
361	4
361	2
361	5
362	1
362	2
363	2
363	1
364	3
364	1
364	2
364	4
364	5
365	3
366	4
367	2
367	1
367	4
367	5
368	1
368	4
368	5
369	2
369	5
369	1
369	4
370	3
370	4
370	1
371	5
372	3
372	1
373	5
373	1
374	4
374	1
374	2
374	3
374	5
375	4
376	2
376	1
376	3
376	5
377	2
377	1
377	5
377	3
378	5
378	2
378	3
378	4
378	1
379	3
379	1
380	1
381	5
382	3
383	3
384	4
384	1
384	5
384	3
384	2
385	3
385	4
385	1
386	4
386	2
386	3
386	5
386	1
387	2
388	5
388	2
388	3
388	1
389	4
389	5
389	2
389	1
390	1
390	4
391	4
392	4
392	5
392	1
393	3
393	1
394	1
394	2
395	3
395	2
395	5
395	4
395	1
396	1
396	3
397	4
397	2
397	5
397	1
397	3
398	2
398	5
398	4
398	1
399	4
399	3
399	5
399	1
399	2
400	5
400	3
400	4
401	3
401	5
401	4
401	1
402	4
402	5
403	1
403	2
403	4
403	5
404	4
405	5
405	3
405	2
405	4
406	4
406	3
407	5
407	2
407	3
407	4
408	4
408	5
409	4
409	3
409	2
409	5
410	2
410	3
410	1
410	5
410	4
411	1
412	4
412	5
412	1
412	2
412	3
413	4
413	1
413	3
413	2
413	5
414	5
414	1
414	4
414	3
414	2
415	5
415	3
415	2
415	4
415	1
416	2
416	5
416	4
416	1
416	3
417	3
418	4
418	5
418	3
419	3
420	3
420	4
420	1
420	5
420	2
421	4
421	1
422	5
423	1
423	3
423	5
423	2
424	5
425	1
425	2
425	3
425	5
425	4
426	4
426	3
426	2
426	5
426	1
427	4
427	2
428	5
428	1
429	5
429	4
429	3
430	1
430	2
430	4
430	5
430	3
431	5
432	1
432	5
432	2
432	4
433	3
433	1
433	2
433	4
434	2
434	4
434	5
434	1
434	3
435	5
435	1
436	5
436	4
436	1
436	3
437	3
437	2
438	5
438	3
438	1
438	4
439	2
439	4
440	3
440	5
440	2
440	1
441	3
441	1
441	5
441	4
441	2
442	1
442	5
442	3
442	4
443	2
443	5
443	4
443	3
443	1
444	3
444	4
444	1
444	5
445	3
445	1
445	2
445	4
445	5
446	4
446	2
446	5
447	5
447	2
447	4
447	1
447	3
448	1
448	3
449	4
449	5
449	2
449	3
449	1
450	2
450	1
450	3
450	5
451	5
451	1
451	2
451	3
452	2
452	1
452	4
452	5
452	3
453	1
453	5
453	4
453	2
453	3
454	1
454	5
455	5
455	2
456	4
457	2
458	3
458	4
458	2
458	5
458	1
459	3
459	1
459	4
459	2
460	1
461	5
461	3
461	2
461	4
462	5
462	3
462	4
463	3
464	1
464	3
464	2
464	4
465	1
465	5
466	5
466	4
466	3
466	2
467	1
467	5
467	3
468	3
468	5
468	1
468	2
469	3
469	1
469	4
470	4
470	2
471	5
471	1
471	3
471	4
472	4
472	5
472	1
472	2
472	3
473	2
474	2
474	5
475	1
475	2
475	4
475	5
476	5
476	3
476	4
477	5
478	5
478	3
478	4
478	2
478	1
479	5
479	3
479	2
479	1
480	4
481	5
481	2
481	4
481	3
481	1
482	4
483	4
483	1
483	2
483	3
484	3
484	1
484	4
484	5
484	2
485	2
485	5
486	4
486	5
486	2
486	1
486	3
487	5
487	3
487	1
488	3
488	4
488	2
488	5
489	4
489	3
489	2
489	1
489	5
490	3
490	5
490	2
491	1
492	3
492	1
493	1
493	2
493	3
493	5
493	4
494	5
494	2
494	1
494	3
495	5
495	3
495	4
496	5
496	2
497	2
497	1
497	4
497	3
497	5
498	4
499	3
499	2
499	1
499	4
499	5
500	5
500	1
500	4
500	2
501	4
501	2
501	5
501	3
501	1
502	3
502	4
502	2
503	5
503	2
503	3
503	1
503	4
504	3
504	1
505	2
505	5
505	1
506	5
506	2
507	2
507	4
507	3
507	1
507	5
508	5
508	3
508	2
509	3
509	1
509	4
509	2
510	3
510	1
510	5
511	4
511	2
511	3
511	5
511	1
512	5
512	3
512	1
512	4
513	3
513	4
513	5
513	1
513	2
514	3
514	1
514	4
515	5
515	3
515	4
515	2
515	1
516	3
516	4
516	1
517	1
517	2
518	5
518	2
518	4
518	1
518	3
519	3
519	5
519	4
519	2
519	1
520	4
520	5
520	1
520	2
521	3
521	1
521	2
522	1
522	4
522	5
522	3
522	2
523	4
523	3
523	2
523	5
523	1
524	1
525	2
525	4
525	5
525	1
525	3
526	2
526	4
526	3
526	1
526	5
527	5
528	2
528	4
528	3
529	3
529	4
529	5
529	2
530	5
530	2
530	3
531	3
531	1
531	4
531	2
532	5
532	1
532	3
533	5
533	1
533	3
533	4
533	2
534	4
534	2
534	3
534	5
534	1
535	4
536	1
536	3
536	4
536	5
537	1
537	4
538	2
538	3
538	1
539	2
539	1
539	5
539	4
539	3
540	2
540	5
540	4
541	2
541	1
541	3
541	4
541	5
542	2
542	4
542	1
542	3
542	5
543	1
544	5
544	4
545	2
546	5
546	4
547	4
548	1
548	4
548	5
549	1
549	2
549	5
549	4
549	3
550	1
550	2
550	4
550	3
551	1
551	3
552	2
552	3
552	1
552	4
552	5
553	2
553	5
554	4
554	1
554	2
554	3
554	5
555	5
556	2
556	5
556	4
556	3
557	4
557	5
557	3
558	5
558	4
558	2
558	3
558	1
559	1
559	5
559	4
560	2
561	4
561	5
561	3
561	1
561	2
562	2
562	1
562	4
562	5
563	1
563	4
563	2
564	5
564	2
564	3
564	4
565	1
565	5
565	4
565	2
565	3
566	4
566	5
566	1
566	2
567	2
567	4
567	1
568	3
568	4
568	5
569	1
569	2
570	3
570	2
570	4
570	5
570	1
571	3
572	3
573	1
573	4
574	3
574	2
575	1
575	2
575	4
576	4
577	1
577	5
577	2
578	3
578	2
578	1
578	4
579	5
579	4
579	2
579	1
580	1
580	5
580	2
580	3
580	4
581	5
581	1
581	4
581	2
582	3
583	4
583	5
583	3
584	1
585	3
585	1
585	4
585	2
585	5
586	2
586	1
586	5
586	3
587	5
587	2
587	1
587	3
588	3
588	2
588	5
588	1
589	3
590	4
590	2
590	3
590	1
590	5
591	1
591	5
591	2
591	4
592	2
592	5
592	1
592	3
592	4
593	1
594	3
595	3
595	4
596	4
596	3
596	2
596	1
596	5
597	3
597	4
597	5
597	2
598	4
598	2
599	5
599	1
599	3
599	2
600	5
600	3
601	5
602	1
602	3
602	4
602	5
603	5
603	1
603	3
603	2
604	2
604	1
604	3
604	4
604	5
605	3
605	5
605	1
606	5
606	2
606	4
607	5
607	4
608	3
608	5
608	1
609	4
610	2
611	1
611	2
611	3
611	5
612	5
612	1
613	1
613	3
613	4
613	5
613	2
614	3
615	2
615	1
615	5
615	4
616	2
616	4
616	3
616	5
616	1
617	1
617	4
617	2
617	5
618	1
618	2
618	4
619	2
619	3
619	5
619	1
619	4
620	1
620	3
621	1
621	3
622	1
622	3
622	5
622	2
622	4
623	5
623	3
624	4
624	1
624	3
624	5
624	2
625	4
626	4
626	3
626	1
627	3
627	4
627	2
627	1
627	5
628	1
628	5
629	3
629	4
630	3
630	1
630	5
630	2
631	3
631	1
631	5
631	2
632	3
632	2
632	1
633	4
634	1
634	2
634	3
634	5
635	3
635	1
635	2
635	4
635	5
636	4
636	5
636	2
636	3
637	1
638	3
638	4
638	2
638	1
639	1
639	4
639	3
639	5
640	2
640	3
640	4
640	5
640	1
641	3
641	1
642	4
642	3
642	2
642	5
643	1
643	4
644	1
644	5
644	3
644	2
644	4
645	1
645	2
646	5
646	3
646	1
646	4
646	2
647	5
647	2
647	1
648	1
648	3
649	5
649	4
649	3
649	1
649	2
650	1
650	4
650	5
650	3
651	5
651	1
651	3
651	4
652	3
653	3
653	5
653	1
654	1
654	5
655	1
655	3
655	4
656	5
656	4
656	2
656	3
657	2
657	3
657	5
657	1
658	1
658	5
658	3
659	4
659	3
659	1
660	5
661	1
662	4
662	3
662	2
662	1
663	4
663	3
664	1
664	2
664	3
664	5
665	4
665	5
665	3
666	4
666	1
667	5
667	4
667	1
667	3
668	3
668	2
668	5
669	4
669	2
670	2
671	3
672	5
672	2
672	4
673	5
673	2
673	4
674	3
674	4
674	2
675	5
675	4
675	2
675	3
676	4
676	1
676	2
677	4
677	1
677	5
678	5
678	1
678	2
679	4
679	2
680	1
681	1
682	4
682	2
682	1
682	3
683	4
683	1
683	5
683	2
684	2
684	1
684	4
684	3
685	4
686	3
686	1
687	1
687	4
687	2
687	5
688	3
689	4
689	2
689	3
689	1
690	4
690	2
691	2
692	4
692	2
692	3
693	1
693	5
694	3
694	2
694	1
695	3
695	1
695	2
695	4
695	5
696	1
696	2
696	3
696	4
696	5
697	5
697	3
697	4
697	1
698	1
698	4
699	4
700	1
701	1
701	3
701	5
702	5
702	1
702	4
703	2
703	5
703	4
703	1
703	3
704	4
704	3
705	2
705	1
706	4
707	3
708	3
708	1
708	5
709	2
709	1
709	3
710	4
710	2
710	5
710	3
711	2
711	1
711	4
711	5
712	4
712	2
712	3
712	5
712	1
713	5
713	4
713	2
713	3
713	1
714	5
714	4
714	2
715	1
716	3
716	1
716	5
716	2
717	3
717	5
717	2
718	3
718	5
719	1
719	3
719	2
720	5
720	1
720	2
721	3
721	2
722	5
722	3
723	4
723	3
724	1
724	3
724	4
724	2
725	3
725	1
726	3
726	4
726	5
727	3
727	4
727	2
727	1
727	5
728	4
728	1
728	5
729	2
730	3
730	2
731	3
731	1
732	3
732	2
732	5
733	1
733	3
734	2
735	1
735	5
735	4
735	2
735	3
736	5
736	1
736	3
736	2
737	5
737	1
738	2
739	3
740	3
740	1
740	5
740	2
740	4
741	4
742	4
742	5
742	1
743	4
743	5
743	2
743	3
744	3
745	2
745	3
745	4
745	1
745	5
746	2
747	3
747	5
747	1
748	2
748	5
748	1
748	4
749	4
750	3
750	1
750	5
751	4
752	4
752	1
753	3
753	4
753	2
753	1
754	2
754	3
754	1
754	4
755	4
755	5
756	3
756	2
757	5
757	1
757	4
757	2
757	3
758	5
758	1
758	2
758	3
758	4
759	4
759	3
760	3
760	5
760	4
761	1
761	2
762	3
763	5
763	1
763	3
764	3
765	2
766	1
766	2
766	3
766	4
767	3
767	5
767	2
767	4
767	1
768	5
768	3
768	1
768	4
769	3
769	2
769	4
769	5
770	3
770	5
770	2
770	4
770	1
771	2
771	3
771	1
771	5
771	4
772	2
772	5
772	1
773	1
773	5
773	4
774	5
774	1
774	4
774	3
774	2
775	5
775	2
775	3
775	1
776	1
776	2
777	4
777	1
777	2
777	3
777	5
778	4
778	5
778	1
778	3
778	2
779	2
779	3
779	5
779	1
779	4
780	5
780	2
780	3
780	4
780	1
781	4
781	3
782	5
783	4
783	2
783	5
784	1
784	5
785	1
785	4
786	2
787	3
787	1
787	2
788	2
788	1
788	4
789	4
789	5
789	2
789	1
790	3
790	4
791	3
791	1
791	2
791	5
792	4
792	5
792	2
792	1
792	3
793	1
793	4
793	2
794	2
795	4
795	2
795	3
795	1
795	5
796	4
796	3
796	2
796	5
796	1
797	3
797	5
798	1
799	3
799	2
799	4
800	2
800	5
801	1
801	4
802	4
802	2
803	4
803	3
803	2
804	1
804	3
804	5
805	3
806	3
806	1
807	1
807	3
807	4
807	2
807	5
808	3
808	1
809	5
809	1
809	2
810	4
810	2
811	2
811	1
811	3
811	5
811	4
812	3
812	4
813	2
814	4
814	5
814	3
815	5
815	1
815	4
815	2
816	3
816	4
816	1
816	2
816	5
817	2
818	2
819	2
819	1
819	3
819	4
820	2
820	1
820	5
820	4
820	3
821	5
821	1
821	2
821	4
821	3
822	1
822	5
822	4
822	2
823	1
823	5
823	2
824	2
824	3
824	5
825	2
825	3
825	4
825	1
825	5
826	4
826	2
826	3
827	4
827	5
827	1
828	5
828	1
829	1
829	4
830	2
831	4
832	5
832	2
833	4
833	2
833	5
833	3
833	1
834	5
834	3
834	2
834	4
834	1
835	3
835	5
836	3
837	3
837	1
837	4
837	5
838	2
838	4
839	1
839	5
840	4
840	2
841	2
841	5
841	4
841	1
842	3
843	1
843	3
843	5
843	4
844	4
844	2
844	1
844	3
845	1
845	2
846	1
846	4
846	5
846	2
846	3
847	1
847	5
847	4
848	4
848	5
848	1
849	4
849	3
849	2
849	1
849	5
850	1
851	3
851	4
851	5
851	2
851	1
852	4
852	2
852	3
852	5
852	1
853	3
853	2
853	1
854	2
854	5
854	4
854	3
854	1
855	1
855	3
855	4
855	2
855	5
856	4
856	3
856	2
857	4
857	5
857	1
858	3
858	1
858	4
858	5
859	1
859	4
859	2
859	5
860	4
861	2
861	3
861	4
861	1
861	5
862	1
862	4
862	2
863	1
864	5
865	2
865	1
865	5
866	2
866	1
866	5
866	3
867	4
868	3
869	4
869	2
869	3
869	5
869	1
870	4
871	3
871	5
871	4
871	2
871	1
872	3
872	5
872	4
872	1
872	2
873	1
874	3
874	4
874	5
874	1
875	1
875	4
876	3
876	1
876	5
876	2
876	4
877	2
877	5
878	1
878	5
879	2
879	5
879	4
879	1
880	5
880	2
880	3
881	1
882	3
882	1
882	5
883	1
883	3
883	2
883	5
883	4
884	2
884	4
884	1
885	3
885	5
885	2
885	4
886	1
887	3
887	2
888	1
888	3
888	2
888	4
888	5
889	2
889	5
890	5
890	4
890	2
890	1
891	5
891	1
892	1
892	4
892	2
892	5
893	5
893	4
893	1
893	2
893	3
894	4
895	5
895	4
895	1
896	5
897	1
897	3
897	5
897	2
897	4
898	4
899	5
899	3
899	1
899	2
900	3
900	5
900	2
901	2
901	1
901	3
901	4
902	5
902	1
902	4
902	2
903	4
904	4
904	3
904	5
905	1
905	4
905	2
906	2
906	5
906	4
907	5
907	2
907	4
908	3
908	5
908	4
909	3
909	4
909	1
910	3
911	3
911	2
911	1
912	3
912	1
912	5
912	4
912	2
913	2
913	1
913	5
914	5
915	5
916	4
916	5
917	3
917	1
917	2
917	4
917	5
918	5
918	1
918	4
918	3
918	2
919	2
919	4
919	1
919	3
919	5
920	1
921	1
921	4
921	2
921	5
921	3
922	5
922	4
922	3
922	2
922	1
923	4
923	1
923	2
923	3
924	5
924	4
924	1
924	3
924	2
925	5
925	4
925	2
925	1
926	3
926	1
926	5
926	4
927	1
927	5
927	2
928	2
928	1
928	4
928	3
928	5
929	2
929	4
929	1
929	3
930	4
930	1
930	5
930	2
930	3
931	3
931	4
931	5
931	2
931	1
932	2
932	4
933	5
933	3
933	1
934	5
934	2
934	4
934	3
934	1
935	2
936	2
936	4
936	3
936	1
937	5
937	2
937	4
937	1
938	1
938	3
938	2
939	2
939	1
939	4
940	4
940	1
940	5
940	3
940	2
941	2
941	5
941	1
941	4
941	3
942	2
942	3
942	4
942	5
942	1
943	2
943	3
943	4
943	1
943	5
944	3
945	5
946	5
946	4
946	3
947	5
948	4
948	5
948	3
949	5
949	2
949	4
949	1
950	1
950	4
951	3
951	4
952	4
952	5
952	3
952	2
952	1
953	2
954	4
954	1
954	5
954	3
954	2
955	2
955	3
956	4
956	2
957	3
957	4
957	1
958	4
958	2
958	1
958	3
958	5
959	1
959	3
960	5
960	4
961	2
961	5
962	1
963	5
963	4
963	1
963	3
964	1
964	3
964	4
965	5
965	3
966	1
966	3
966	5
966	4
967	3
967	5
967	1
967	4
967	2
968	5
968	3
969	3
969	4
969	5
969	2
970	2
970	1
970	5
970	4
971	2
972	4
973	5
974	3
974	5
975	1
976	4
976	2
976	5
977	5
977	4
977	3
978	3
979	2
980	4
981	3
982	5
982	3
983	4
983	2
983	3
983	1
983	5
984	5
985	1
985	2
985	3
985	5
986	5
987	4
987	1
987	3
987	2
988	4
989	4
989	2
989	3
989	1
990	1
991	1
991	3
992	3
992	1
992	4
992	5
993	3
993	2
994	3
994	1
994	5
995	1
995	2
995	5
995	4
995	3
996	1
996	2
996	3
996	4
996	5
997	1
997	5
997	4
997	3
997	2
998	1
998	3
999	5
999	4
1000	3
1000	4
1000	2
1000	1
1000	5
1001	3
1001	4
1002	5
1002	1
1002	2
1002	3
1002	4
1003	1
1003	2
1003	4
1004	4
1005	5
1005	2
1005	4
1005	1
1006	4
1006	1
1006	2
1006	3
1007	5
1008	5
1008	3
1008	4
1009	4
1009	3
1009	5
1010	1
1010	5
1010	3
1010	4
1010	2
1011	2
1011	3
1011	5
1011	1
1011	4
1012	1
1012	4
1012	2
1012	5
1013	2
1013	5
1014	1
1015	1
1016	3
1016	4
1016	2
1016	5
1017	1
1017	4
1018	4
1018	5
1019	2
1020	5
1020	3
1021	3
1021	4
1022	4
1022	3
1022	1
1023	4
1023	3
1023	1
1023	2
1024	2
1024	4
1024	5
1024	1
1025	1
1025	2
1025	3
1026	4
1026	3
1026	2
1026	5
1026	1
1027	2
1027	1
1027	4
1027	5
1027	3
1028	2
1028	5
1029	4
1029	2
1030	5
1030	4
1031	2
1031	4
1032	5
1032	2
1032	4
1032	1
1032	3
1033	2
1033	5
1034	1
1034	5
1034	4
1035	1
1035	2
1035	3
1035	5
1036	1
1036	2
1036	4
1036	3
1037	1
1037	2
1037	4
1037	5
1037	3
1038	3
1038	5
1039	2
1040	3
1040	5
1040	2
1040	4
1040	1
1041	4
1041	3
1041	2
1041	5
1042	2
1042	1
1042	4
1042	5
1043	2
1043	3
1043	1
1043	5
1043	4
1044	4
1045	3
1045	4
1046	4
1046	1
1047	1
1047	5
1047	2
1048	5
1049	1
1049	4
1049	5
1049	2
1049	3
1050	5
1050	4
1050	3
1051	2
1051	3
1051	4
1051	5
1051	1
1052	4
1052	3
1053	3
1053	5
1053	4
1054	3
1054	4
1055	5
1055	2
1056	3
1056	2
1056	5
1056	4
1057	2
1057	5
1057	3
1058	4
1058	5
1059	5
1060	3
1060	2
1060	1
1061	1
1061	2
1062	4
1062	5
1062	2
1063	1
1063	5
1063	2
1063	3
1064	1
1064	3
1064	4
1064	2
1064	5
1065	2
1065	1
1066	5
1066	3
1067	4
1067	5
1067	2
1067	1
1067	3
1068	4
1068	1
1068	2
1068	5
1068	3
1069	4
1069	1
1069	2
1070	2
1070	3
1070	4
1070	5
1070	1
1071	4
1072	1
1072	3
1073	5
1074	5
1074	2
1074	3
1074	1
1074	4
1075	5
1075	2
1075	3
1076	1
1077	4
1077	3
1077	1
1077	2
1077	5
1078	1
1079	1
1079	4
1079	5
1080	3
1080	2
1081	2
1081	5
1082	1
1082	3
1083	3
1083	2
1083	1
1083	4
1083	5
1084	2
1085	5
1085	2
1085	1
1086	2
1086	5
1086	1
1086	3
1087	5
1088	2
1088	3
1088	4
1088	5
1088	1
1089	5
1089	3
1089	2
1089	4
1089	1
1090	1
1090	3
1091	1
1091	2
1091	3
1091	4
1091	5
1092	3
1092	4
1092	1
1092	5
1093	5
1094	4
1094	2
1094	3
1094	5
1095	5
1095	3
1096	4
1096	5
1096	1
1096	2
1096	3
1097	4
1097	3
1097	5
1097	2
1097	1
1098	4
1098	5
1098	3
1098	1
1098	2
1099	3
1099	1
1099	5
1099	2
1099	4
1100	1
1100	4
1100	5
1100	2
1101	5
1101	3
1101	2
1102	3
1102	2
1102	5
1102	1
1103	3
1103	2
1103	4
1104	3
1104	2
1104	4
1104	1
1105	3
1105	5
1106	1
1106	4
1106	5
1106	3
1106	2
1107	5
1107	1
1107	4
1107	2
1108	1
1108	5
1108	3
1108	4
1109	4
1109	2
1109	3
1109	1
1110	1
1110	3
1110	5
1110	2
1110	4
1111	5
1111	1
1111	3
1111	2
1112	3
1112	5
1112	4
1112	2
1112	1
1113	1
1113	5
1113	2
1113	4
1114	1
1114	5
1114	2
1115	1
1115	5
1115	3
1115	4
1115	2
1116	5
1116	1
1116	2
1116	4
1117	3
1117	2
1117	4
1117	1
1118	1
1119	5
1119	1
1119	3
1120	4
1120	5
1120	3
1120	2
1120	1
1121	5
1121	2
1121	4
1121	1
1122	2
1123	5
1123	4
1123	2
1124	5
1124	2
1125	1
1125	4
1125	2
1125	5
1126	1
1127	2
1127	3
1127	4
1127	5
1127	1
1128	5
1128	4
1129	1
1129	5
1129	2
1130	2
1130	5
1131	1
1131	3
1131	5
1132	1
1132	4
1132	5
1133	4
1133	3
1133	5
1133	1
1133	2
1134	1
1134	2
1135	2
1136	2
1136	1
1136	5
1136	3
1136	4
1137	4
1137	2
1137	3
1137	1
1138	3
1139	4
1140	3
1140	4
1140	2
1140	5
1140	1
1141	1
1141	3
1141	5
1141	2
1142	2
1142	3
1142	4
1143	3
1144	3
1144	4
1144	2
1144	1
1145	3
1145	4
1145	5
1146	2
1146	1
1146	4
1146	3
1147	1
1147	3
1147	2
1147	4
1147	5
1148	3
1148	2
1148	1
1148	5
1149	1
1149	4
1150	3
1151	4
1151	1
1151	5
1151	2
1151	3
1152	3
1152	1
1152	2
1153	1
1153	2
1153	3
1153	4
1153	5
1154	2
1154	1
1154	5
1155	4
1155	2
1155	1
1156	2
1156	5
1156	3
1156	4
1157	2
1158	4
1158	5
1158	2
1158	3
1158	1
1159	4
1160	3
1160	5
1160	2
1161	2
1161	3
1161	5
1161	1
1161	4
1162	2
1163	2
1163	4
1163	5
1163	3
1164	3
1164	1
1165	3
1165	4
1165	2
1165	1
1166	1
1166	5
1166	3
1166	2
1167	5
1167	2
1167	1
1167	4
1167	3
1168	3
1168	2
1168	4
1168	5
1168	1
1169	4
1169	5
1169	2
1170	3
1170	1
1170	4
1170	5
1171	4
1172	5
1172	2
1173	1
1173	5
1173	2
1174	3
1175	1
1175	3
1175	2
1175	4
1176	1
1176	5
1176	2
1177	1
1177	5
1178	5
1178	1
1178	3
1178	4
1179	5
1179	1
1179	2
1179	4
1180	3
1180	2
1180	1
1180	4
1181	2
1181	1
1181	5
1181	4
1181	3
1182	1
1182	3
1183	1
1183	2
1183	5
1184	1
1185	4
1186	3
1186	1
1187	4
1188	5
1188	1
1188	2
1188	3
1189	3
1189	2
1189	1
1189	4
1189	5
1190	5
1190	4
1190	2
1190	1
1191	2
1191	5
1191	1
1192	1
1193	4
1193	3
1194	1
1194	5
1195	4
1195	5
1195	2
1195	1
1196	1
1196	2
1196	5
1196	3
1197	4
1197	3
1197	5
1197	1
1198	1
1198	2
1198	3
1199	3
1200	3
1200	4
1200	1
1201	5
1202	5
1203	4
1203	1
1203	2
1203	5
1204	4
1204	1
1204	2
1204	5
1205	5
1205	4
1206	4
1206	1
1207	4
1208	1
1208	4
1208	5
1209	4
1209	2
1209	5
1209	3
1209	1
1210	2
1210	3
1211	4
1212	3
1212	2
1212	1
1212	4
1212	5
1213	2
1213	3
1213	4
1213	5
1213	1
1214	1
1214	3
1214	4
1214	2
1214	5
1215	3
1215	1
1215	2
1215	4
1215	5
1216	5
1217	2
1217	4
1218	1
1218	4
1218	3
1218	5
1218	2
1219	3
1219	4
1219	5
1220	4
1220	2
1221	1
1221	4
1221	3
1221	5
1222	1
1222	2
1222	3
1222	5
1222	4
1223	2
1224	3
1224	4
1224	1
1224	5
1225	3
1225	2
1225	4
1226	4
1226	5
1226	1
1226	2
1227	4
1227	3
1227	5
1228	2
1229	5
1229	4
1229	3
1230	1
1230	3
1230	2
1230	4
1230	5
1231	2
1232	1
1233	1
1233	3
1233	2
1233	4
1233	5
1234	4
1235	1
1235	5
1235	4
1235	2
1235	3
1236	3
1236	1
1236	4
1237	3
1238	1
1238	3
1238	2
1238	4
1238	5
1239	5
1239	3
1239	2
1239	1
1240	3
1240	2
1241	4
1241	1
1241	3
1241	2
1242	4
1242	1
1242	5
1243	3
1243	1
1243	2
1243	4
1244	3
1244	4
1244	5
1245	5
1245	1
1245	3
1245	2
1245	4
1246	5
1246	4
1246	1
1246	3
1247	4
1247	5
1247	3
1247	1
1247	2
1248	3
1248	2
1248	4
1248	1
1248	5
1249	3
1249	2
1249	1
1249	5
1250	5
1250	3
1250	4
1250	2
1250	1
\.


--
-- Data for Name: passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.passports (id, original_surname, original_name, en_name, en_surname, issue_date, expiration_date, sex, issuer, passport_owner, lost, invalidated) FROM stdin;
1	Sandra	Frye	Sandra	Frye	1998-03-18	2018-03-28	F	58	1	f	f
2	Tyler	Brandt	Tyler	Brandt	1973-07-15	1993-02-05	M	585	2	f	f
3	Amanda	Hayes	Amanda	Hayes	1973-12-23	1993-03-15	F	622	3	f	f
4	Anthony	Knight	Anthony	Knight	1948-12-17	1968-08-19	M	49	4	f	f
5	Lawrence	Suarez	Lawrence	Suarez	1948-11-26	1968-10-14	F	183	5	f	f
6	Tamara	Snyder	Tamara	Snyder	1948-02-28	1968-08-26	M	861	6	f	f
7	Timothy	Elliott	Timothy	Elliott	1948-03-14	1968-10-09	F	373	7	f	f
8	Jamie	Smith	Jamie	Smith	1923-10-28	1943-07-04	M	358	8	f	f
9	Nicole	Martinez	Nicole	Martinez	1923-01-02	1943-07-06	F	127	9	f	f
10	Kyle	Foster	Kyle	Foster	1923-12-02	1943-05-15	M	326	10	f	f
11	Logan	Adams	Logan	Adams	1923-11-10	1943-12-02	F	237	11	f	f
12	Paul	Hanson	Paul	Hanson	1923-03-07	1943-06-28	M	919	12	f	f
13	Michael	Cole	Michael	Cole	1923-10-15	1943-05-07	F	101	13	f	f
14	Robert	Foster	Robert	Foster	1923-08-25	1943-09-08	M	220	14	f	f
15	Brandon	Rodriguez	Brandon	Rodriguez	1923-09-07	1943-12-10	F	1100	15	f	f
16	Melinda	Evans	Melinda	Evans	1898-02-17	1918-09-07	M	113	16	f	f
17	Emily	George	Emily	George	1898-01-05	1918-04-21	F	124	17	f	f
18	John	Nelson	John	Nelson	1898-11-02	1918-08-09	M	355	18	f	f
19	Julie	Crane	Julie	Crane	1898-05-18	1918-10-15	F	57	19	f	f
20	Sandra	Smith	Sandra	Smith	1898-04-25	1918-12-16	M	491	20	f	f
21	Tony	Harris	Tony	Harris	1898-03-07	1918-07-03	F	617	21	f	f
22	Calvin	Garza	Calvin	Garza	1898-01-12	1918-12-27	M	193	22	f	f
23	Aaron	Calhoun	Aaron	Calhoun	1898-02-15	1918-12-17	F	575	23	f	f
24	Crystal	Scott	Crystal	Scott	1898-07-03	1918-08-18	M	156	24	f	f
25	Walter	Bowen	Walter	Bowen	1898-10-19	1918-08-02	F	1149	25	f	f
26	Lucas	Austin	Lucas	Austin	1898-11-28	1918-06-04	M	179	26	f	f
27	Kristen	Long	Kristen	Long	1898-04-23	1918-04-18	F	231	27	f	f
28	Christina	Taylor	Christina	Taylor	1898-04-09	1918-03-02	M	40	28	f	f
29	Melissa	Thomas	Melissa	Thomas	1898-07-22	1918-12-03	F	1065	29	f	f
30	Robert	Fuller	Robert	Fuller	1898-04-18	1918-09-13	M	499	30	f	f
31	Whitney	Harris	Whitney	Harris	1898-05-03	1918-09-14	F	1085	31	f	f
32	Andrea	Shepard	Andrea	Shepard	1873-01-19	1893-02-07	M	449	32	f	f
33	Luis	Barron	Luis	Barron	1873-05-20	1893-10-02	F	150	33	f	f
34	David	Weaver	David	Weaver	1873-02-25	1893-12-22	M	698	34	f	f
35	Emma	Matthews	Emma	Matthews	1873-01-21	1893-01-18	F	713	35	f	f
36	Allen	Gallagher	Allen	Gallagher	1873-10-22	1893-11-05	M	917	36	f	f
37	Ryan	Luna	Ryan	Luna	1873-08-26	1893-07-26	F	264	37	f	f
38	Alejandro	Brown	Alejandro	Brown	1873-10-08	1893-03-21	M	368	38	f	f
39	Emily	Ayers	Emily	Ayers	1873-07-08	1893-01-08	F	182	39	f	f
40	Gina	Clay	Gina	Clay	1873-04-03	1893-03-28	M	859	40	f	f
41	Amanda	Davenport	Amanda	Davenport	1873-10-22	1893-10-03	F	128	41	f	f
42	Toni	Miller	Toni	Miller	1873-06-03	1893-11-27	M	1065	42	f	f
43	Jeffrey	Ryan	Jeffrey	Ryan	1873-08-17	1893-11-09	F	1025	43	f	f
44	John	Smith	John	Smith	1873-07-02	1893-09-11	M	14	44	f	f
45	Kristin	Williams	Kristin	Williams	1873-01-23	1893-11-03	F	923	45	f	f
46	Tracy	Caldwell	Tracy	Caldwell	1873-11-17	1893-07-12	M	754	46	f	f
47	Alan	Nunez	Alan	Nunez	1873-04-11	1893-12-24	F	116	47	f	f
48	Amber	Green	Amber	Green	1873-04-24	1893-02-20	M	853	48	f	f
49	Darryl	Olson	Darryl	Olson	1873-09-21	1893-03-25	F	518	49	f	f
50	Brenda	Rollins	Brenda	Rollins	1873-06-05	1893-06-02	M	1065	50	f	f
51	Grant	Roberson	Grant	Roberson	1873-12-06	1893-09-13	F	145	51	f	f
52	Lauren	Wood	Lauren	Wood	1873-12-21	1893-06-04	M	1131	52	f	f
53	Jon	Dickson	Jon	Dickson	1873-07-12	1893-06-19	F	581	53	f	f
54	Kyle	Gonzales	Kyle	Gonzales	1873-04-16	1893-01-21	M	171	54	f	f
55	Jessica	White	Jessica	White	1873-05-20	1893-07-05	F	849	55	f	f
56	Tyler	Salazar	Tyler	Salazar	1873-03-09	1893-03-25	M	1250	56	f	f
57	Paul	Wheeler	Paul	Wheeler	1873-02-21	1893-10-09	F	112	57	f	f
58	Kyle	Blake	Kyle	Blake	1873-11-24	1893-11-25	M	725	58	f	f
59	Nicholas	Bowen	Nicholas	Bowen	1873-07-20	1893-04-11	F	549	59	f	f
60	Kristopher	Hancock	Kristopher	Hancock	1873-05-16	1893-09-26	M	1032	60	f	f
61	Hector	Edwards	Hector	Edwards	1873-07-07	1893-03-25	F	1155	61	f	f
62	Cindy	Marquez	Cindy	Marquez	1873-05-12	1893-12-13	M	1213	62	f	f
63	John	Simmons	John	Simmons	1873-08-05	1893-08-20	F	716	63	f	f
64	Edward	Grant	Edward	Grant	1848-06-27	1868-01-20	M	412	64	f	f
65	Samuel	Nielsen	Samuel	Nielsen	1848-08-26	1868-04-07	F	1027	65	f	f
66	Scott	Guerrero	Scott	Guerrero	1848-08-02	1868-08-15	M	581	66	f	f
67	Jennifer	Jones	Jennifer	Jones	1848-09-25	1868-04-05	F	742	67	f	f
68	Thomas	Neal	Thomas	Neal	1848-12-20	1868-12-07	M	1167	68	f	f
69	Steven	Morgan	Steven	Morgan	1848-04-10	1868-04-04	F	475	69	f	f
70	Stephen	Bender	Stephen	Bender	1848-12-28	1868-09-11	M	452	70	f	f
71	Rebecca	Haynes	Rebecca	Haynes	1848-04-24	1868-01-12	F	155	71	f	f
72	Corey	Daniels	Corey	Daniels	1848-10-26	1868-05-23	M	145	72	f	f
73	Julie	Martinez	Julie	Martinez	1848-10-13	1868-09-03	F	370	73	f	f
74	Kyle	Tucker	Kyle	Tucker	1848-01-23	1868-06-17	M	435	74	f	f
75	Nathan	Martin	Nathan	Martin	1848-01-27	1868-02-15	F	1194	75	f	f
76	Levi	Long	Levi	Long	1848-12-25	1868-08-13	M	14	76	f	f
77	Zachary	Jackson	Zachary	Jackson	1848-07-06	1868-04-02	F	1006	77	f	f
78	Juan	Smith	Juan	Smith	1848-05-18	1868-03-04	M	48	78	f	f
79	Michael	Young	Michael	Young	1848-08-05	1868-03-28	F	882	79	f	f
80	Carolyn	Rivera	Carolyn	Rivera	1848-02-06	1868-01-12	M	140	80	f	f
81	John	Robinson	John	Robinson	1848-01-24	1868-07-22	F	423	81	f	f
82	Justin	Hughes	Justin	Hughes	1848-03-24	1868-03-22	M	81	82	f	f
83	Michael	Murillo	Michael	Murillo	1848-12-28	1868-07-24	F	768	83	f	f
84	Wyatt	Brennan	Wyatt	Brennan	1848-06-26	1868-03-13	M	784	84	f	f
85	Christy	Obrien	Christy	Obrien	1848-03-01	1868-04-14	F	234	85	f	f
86	Martin	Greer	Martin	Greer	1848-08-23	1868-12-23	M	499	86	f	f
87	Cynthia	Walker	Cynthia	Walker	1848-10-15	1868-12-24	F	531	87	f	f
88	Adam	Hunt	Adam	Hunt	1848-08-05	1868-10-03	M	1068	88	f	f
89	Joseph	Nelson	Joseph	Nelson	1848-04-07	1868-10-10	F	363	89	f	f
90	Damon	Valenzuela	Damon	Valenzuela	1848-04-01	1868-01-12	M	114	90	f	f
91	Linda	Golden	Linda	Golden	1848-08-16	1868-10-12	F	299	91	f	f
92	Richard	Flores	Richard	Flores	1848-05-07	1868-12-22	M	23	92	f	f
93	Matthew	Tucker	Matthew	Tucker	1848-06-05	1868-01-28	F	198	93	f	f
94	Rebecca	Hughes	Rebecca	Hughes	1848-09-24	1868-08-04	M	106	94	f	f
95	Jennifer	Nelson	Jennifer	Nelson	1848-09-18	1868-06-20	F	748	95	f	f
96	Megan	Davis	Megan	Davis	1848-01-09	1868-10-04	M	115	96	f	f
97	Daniel	Wilson	Daniel	Wilson	1848-01-11	1868-10-06	F	681	97	f	f
98	Henry	Carrillo	Henry	Carrillo	1848-09-01	1868-08-01	M	444	98	f	f
99	Dalton	Henderson	Dalton	Henderson	1848-07-08	1868-05-04	F	930	99	f	f
100	James	Hill	James	Hill	1848-11-20	1868-11-27	M	837	100	f	f
101	Patricia	Garcia	Patricia	Garcia	1848-08-23	1868-08-19	F	517	101	f	f
102	John	Hawkins	John	Hawkins	1848-03-14	1868-10-12	M	27	102	f	f
103	Danielle	Phillips	Danielle	Phillips	1848-10-26	1868-09-23	F	1197	103	f	f
104	Michael	Davis	Michael	Davis	1848-07-07	1868-11-08	M	731	104	f	f
105	Danielle	Anderson	Danielle	Anderson	1848-09-07	1868-10-16	F	559	105	f	f
106	Lisa	Rodriguez	Lisa	Rodriguez	1848-09-02	1868-02-14	M	737	106	f	f
107	Ryan	Jenkins	Ryan	Jenkins	1848-09-06	1868-09-04	F	159	107	f	f
108	Scott	Patterson	Scott	Patterson	1848-07-16	1868-09-26	M	634	108	f	f
109	John	Gonzalez	John	Gonzalez	1848-03-16	1868-07-24	F	346	109	f	f
110	Kathy	Fry	Kathy	Fry	1848-01-22	1868-05-28	M	377	110	f	f
111	Kelly	Mejia	Kelly	Mejia	1848-06-18	1868-03-14	F	262	111	f	f
112	Lisa	Le	Lisa	Le	1848-11-22	1868-08-06	M	213	112	f	f
113	John	Nelson	John	Nelson	1848-04-07	1868-07-19	F	114	113	f	f
114	Angela	Marsh	Angela	Marsh	1848-10-02	1868-04-11	M	189	114	f	f
115	Jonathan	Edwards	Jonathan	Edwards	1848-05-17	1868-11-09	F	1089	115	f	f
116	David	Williams	David	Williams	1848-03-19	1868-12-24	M	287	116	f	f
117	Kristin	Gonzalez	Kristin	Gonzalez	1848-08-01	1868-02-06	F	748	117	f	f
118	Susan	Neal	Susan	Neal	1848-03-15	1868-07-28	M	190	118	f	f
119	Lucas	Gilbert	Lucas	Gilbert	1848-10-16	1868-06-10	F	588	119	f	f
120	Cody	Meyer	Cody	Meyer	1848-09-16	1868-09-08	M	878	120	f	f
121	Michelle	Ross	Michelle	Ross	1848-06-03	1868-05-07	F	970	121	f	f
122	Donna	Daniels	Donna	Daniels	1848-01-08	1868-08-01	M	1246	122	f	f
123	Joel	Miller	Joel	Miller	1848-04-08	1868-01-09	F	1233	123	f	f
124	Jennifer	Johnson	Jennifer	Johnson	1848-12-24	1868-10-16	M	364	124	f	f
125	Maurice	Smith	Maurice	Smith	1848-04-07	1868-06-23	F	998	125	f	f
126	Ryan	Matthews	Ryan	Matthews	1848-11-18	1868-08-24	M	249	126	f	f
127	Sharon	Perry	Sharon	Perry	1848-05-10	1868-02-12	F	248	127	f	f
128	Ashley	Reed	Ashley	Reed	1823-01-08	1843-11-02	M	676	128	f	f
129	Teresa	Shaw	Teresa	Shaw	1823-07-14	1843-07-19	F	539	129	f	f
130	Stacy	Jenkins	Stacy	Jenkins	1823-07-03	1843-12-18	M	475	130	f	f
131	David	Brooks	David	Brooks	1823-06-02	1843-07-15	F	985	131	f	f
132	Angelica	Reyes	Angelica	Reyes	1823-05-04	1843-05-14	M	998	132	f	f
133	Natalie	Holmes	Natalie	Holmes	1823-12-26	1843-04-27	F	787	133	f	f
134	Joshua	Flores	Joshua	Flores	1823-10-19	1843-10-20	M	1035	134	f	f
135	Melissa	Young	Melissa	Young	1823-08-14	1843-12-13	F	561	135	f	f
136	Tracey	Williams	Tracey	Williams	1823-09-22	1843-09-01	M	95	136	f	f
137	Jessica	Rubio	Jessica	Rubio	1823-11-06	1843-02-03	F	71	137	f	f
138	Darlene	Kelley	Darlene	Kelley	1823-07-08	1843-08-09	M	1222	138	f	f
139	Sherry	Melton	Sherry	Melton	1823-04-07	1843-06-11	F	1043	139	f	f
140	Emily	Garner	Emily	Garner	1823-05-09	1843-04-13	M	881	140	f	f
141	Amber	Dickerson	Amber	Dickerson	1823-12-11	1843-03-18	F	1011	141	f	f
142	Kathryn	Leach	Kathryn	Leach	1823-06-08	1843-11-02	M	532	142	f	f
143	Andrew	Scott	Andrew	Scott	1823-04-28	1843-07-08	F	139	143	f	f
144	Jerry	Grant	Jerry	Grant	1823-08-17	1843-04-06	M	939	144	f	f
145	Wesley	Cross	Wesley	Cross	1823-03-28	1843-11-16	F	693	145	f	f
146	Randy	Miller	Randy	Miller	1823-10-20	1843-07-22	M	1091	146	f	f
147	Jamie	Vaughn	Jamie	Vaughn	1823-05-07	1843-07-03	F	839	147	f	f
148	Melissa	Callahan	Melissa	Callahan	1823-10-18	1843-07-15	M	1118	148	f	f
149	Samantha	Williams	Samantha	Williams	1823-08-03	1843-03-21	F	135	149	f	f
150	Cathy	Michael	Cathy	Michael	1823-11-17	1843-12-26	M	931	150	f	f
151	Abigail	Patterson	Abigail	Patterson	1823-06-28	1843-06-04	F	491	151	f	f
152	Allison	Dudley	Allison	Dudley	1823-04-18	1843-06-13	M	839	152	f	f
153	Kaitlyn	Peters	Kaitlyn	Peters	1823-03-27	1843-01-04	F	248	153	f	f
154	Darlene	Byrd	Darlene	Byrd	1823-05-15	1843-01-16	M	1100	154	f	f
155	David	Huang	David	Huang	1823-02-11	1843-07-01	F	1063	155	f	f
156	Phillip	Sullivan	Phillip	Sullivan	1823-10-17	1843-03-03	M	593	156	f	f
157	Morgan	Duncan	Morgan	Duncan	1823-05-18	1843-05-14	F	863	157	f	f
158	Danielle	Martinez	Danielle	Martinez	1823-03-17	1843-09-21	M	677	158	f	f
159	Natasha	Grant	Natasha	Grant	1823-03-20	1843-02-18	F	234	159	f	f
160	Stephanie	Wheeler	Stephanie	Wheeler	1823-10-25	1843-08-27	M	752	160	f	f
161	Raymond	Terrell	Raymond	Terrell	1823-08-04	1843-03-26	F	543	161	f	f
162	Krista	Marquez	Krista	Marquez	1823-03-08	1843-03-21	M	551	162	f	f
163	Tamara	Tucker	Tamara	Tucker	1823-12-20	1843-04-19	F	450	163	f	f
164	Connie	Garza	Connie	Garza	1823-12-19	1843-09-04	M	398	164	f	f
165	David	King	David	King	1823-04-19	1843-01-25	F	231	165	f	f
166	Tracey	Ponce	Tracey	Ponce	1823-10-06	1843-12-15	M	218	166	f	f
167	Michael	Morrow	Michael	Morrow	1823-04-05	1843-08-14	F	541	167	f	f
168	Laura	Richardson	Laura	Richardson	1823-04-19	1843-02-03	M	60	168	f	f
169	Melinda	Atkins	Melinda	Atkins	1823-02-03	1843-02-17	F	952	169	f	f
170	Pamela	Robinson	Pamela	Robinson	1823-09-05	1843-03-01	M	441	170	f	f
171	Tara	Murray	Tara	Murray	1823-10-17	1843-12-24	F	651	171	f	f
172	Elizabeth	Glover	Elizabeth	Glover	1823-03-25	1843-11-15	M	869	172	f	f
173	Dennis	Gomez	Dennis	Gomez	1823-06-09	1843-04-16	F	899	173	f	f
174	Jenna	Schroeder	Jenna	Schroeder	1823-12-04	1843-02-13	M	451	174	f	f
175	Amber	Hill	Amber	Hill	1823-08-21	1843-01-17	F	1040	175	f	f
176	Brittany	Kim	Brittany	Kim	1823-11-25	1843-05-10	M	1096	176	f	f
177	Diana	Hall	Diana	Hall	1823-01-16	1843-07-22	F	778	177	f	f
178	Logan	Morris	Logan	Morris	1823-04-05	1843-02-21	M	333	178	f	f
179	Ashley	Delgado	Ashley	Delgado	1823-12-18	1843-11-04	F	385	179	f	f
180	Rachel	Frederick	Rachel	Frederick	1823-12-17	1843-01-12	M	525	180	f	f
181	Rachel	Andrews	Rachel	Andrews	1823-09-02	1843-07-19	F	748	181	f	f
182	Mario	Harris	Mario	Harris	1823-12-12	1843-01-07	M	784	182	f	f
183	Scott	Martin	Scott	Martin	1823-06-04	1843-09-05	F	788	183	f	f
184	Alyssa	Williams	Alyssa	Williams	1823-02-02	1843-08-17	M	40	184	f	f
185	Steven	Silva	Steven	Silva	1823-10-28	1843-02-08	F	585	185	f	f
186	John	Knox	John	Knox	1823-06-06	1843-08-24	M	996	186	f	f
187	Donna	Green	Donna	Green	1823-04-18	1843-12-25	F	657	187	f	f
188	Natalie	Taylor	Natalie	Taylor	1823-12-18	1843-05-27	M	389	188	f	f
189	Robert	Lam	Robert	Lam	1823-08-05	1843-08-26	F	682	189	f	f
190	Nathan	Campbell	Nathan	Campbell	1823-04-13	1843-04-17	M	325	190	f	f
191	Crystal	Meza	Crystal	Meza	1823-04-10	1843-12-10	F	299	191	f	f
192	Robert	Lane	Robert	Lane	1823-12-19	1843-09-20	M	1233	192	f	f
193	Valerie	Wade	Valerie	Wade	1823-03-22	1843-11-27	F	628	193	f	f
194	Tiffany	Patterson	Tiffany	Patterson	1823-04-02	1843-05-22	M	1061	194	f	f
195	Stephanie	Garza	Stephanie	Garza	1823-08-21	1843-01-10	F	702	195	f	f
196	Kimberly	Shields	Kimberly	Shields	1823-09-06	1843-05-24	M	65	196	f	f
197	Austin	Martinez	Austin	Martinez	1823-05-28	1843-08-18	F	1181	197	f	f
198	Timothy	Carter	Timothy	Carter	1823-08-28	1843-11-18	M	106	198	f	f
199	Timothy	Harris	Timothy	Harris	1823-02-08	1843-10-20	F	91	199	f	f
200	Martin	Riley	Martin	Riley	1823-08-21	1843-09-14	M	411	200	f	f
201	Walter	Clarke	Walter	Clarke	1823-04-12	1843-10-10	F	27	201	f	f
202	Kayla	Herrera	Kayla	Herrera	1823-03-09	1843-02-21	M	230	202	f	f
203	William	Adams	William	Adams	1823-02-21	1843-02-19	F	888	203	f	f
204	Bryan	Blackwell	Bryan	Blackwell	1823-07-18	1843-08-02	M	552	204	f	f
205	Donald	Anderson	Donald	Anderson	1823-05-23	1843-11-26	F	1010	205	f	f
206	Jonathan	Gutierrez	Jonathan	Gutierrez	1823-09-07	1843-07-15	M	213	206	f	f
207	Jennifer	Marquez	Jennifer	Marquez	1823-02-09	1843-01-06	F	440	207	f	f
208	Kelsey	Smith	Kelsey	Smith	1823-05-01	1843-02-06	M	24	208	f	f
209	Mark	Ware	Mark	Ware	1823-05-09	1843-12-03	F	1189	209	f	f
210	Jonathan	Haynes	Jonathan	Haynes	1823-05-03	1843-09-04	M	174	210	f	f
211	Sandra	Kirk	Sandra	Kirk	1823-02-25	1843-08-06	F	314	211	f	f
212	Elizabeth	Pope	Elizabeth	Pope	1823-02-10	1843-10-19	M	492	212	f	f
213	Misty	Hart	Misty	Hart	1823-12-21	1843-01-13	F	918	213	f	f
214	Darrell	Moyer	Darrell	Moyer	1823-02-01	1843-04-23	M	1035	214	f	f
215	Bernard	Mann	Bernard	Mann	1823-10-14	1843-10-16	F	684	215	f	f
216	Jerry	Huffman	Jerry	Huffman	1823-06-09	1843-01-12	M	305	216	f	f
217	Chad	Park	Chad	Park	1823-11-05	1843-10-02	F	603	217	f	f
218	Pamela	Wagner	Pamela	Wagner	1823-05-14	1843-03-18	M	430	218	f	f
219	Lauren	Lamb	Lauren	Lamb	1823-07-09	1843-08-01	F	352	219	f	f
220	Sandra	Wright	Sandra	Wright	1823-06-19	1843-10-23	M	767	220	f	f
221	Kathryn	Cain	Kathryn	Cain	1823-05-25	1843-03-13	F	290	221	f	f
222	Molly	Newman	Molly	Newman	1823-03-05	1843-06-03	M	16	222	f	f
223	Keith	Wallace	Keith	Wallace	1823-03-23	1843-07-02	F	270	223	f	f
224	Rebecca	Hogan	Rebecca	Hogan	1823-12-15	1843-09-26	M	231	224	f	f
225	Daniel	Chen	Daniel	Chen	1823-06-04	1843-09-23	F	12	225	f	f
226	Jason	Stewart	Jason	Stewart	1823-12-12	1843-06-24	M	177	226	f	f
227	Christopher	Bailey	Christopher	Bailey	1823-07-07	1843-09-11	F	526	227	f	f
228	Phillip	Martin	Phillip	Martin	1823-12-03	1843-12-07	M	619	228	f	f
229	Kelsey	Mayo	Kelsey	Mayo	1823-01-11	1843-05-20	F	58	229	f	f
230	Karen	Thompson	Karen	Thompson	1823-12-11	1843-10-02	M	882	230	f	f
231	Jamie	Atkins	Jamie	Atkins	1823-03-25	1843-03-08	F	471	231	f	f
232	Edward	Strong	Edward	Strong	1823-11-04	1843-06-19	M	1037	232	f	f
233	Stacy	Kim	Stacy	Kim	1823-02-26	1843-11-28	F	780	233	f	f
234	Bryan	Ross	Bryan	Ross	1823-09-24	1843-05-14	M	958	234	f	f
235	David	Kirby	David	Kirby	1823-09-18	1843-09-17	F	245	235	f	f
236	Andrew	Freeman	Andrew	Freeman	1823-11-05	1843-01-03	M	820	236	f	f
237	Jennifer	Hudson	Jennifer	Hudson	1823-09-05	1843-12-17	F	873	237	f	f
238	Scott	Moreno	Scott	Moreno	1823-01-23	1843-12-09	M	604	238	f	f
239	Shannon	King	Shannon	King	1823-07-24	1843-05-23	F	57	239	f	f
240	Kristen	Thomas	Kristen	Thomas	1823-05-06	1843-09-11	M	103	240	f	f
241	Brittany	Dickerson	Brittany	Dickerson	1823-02-12	1843-02-23	F	2	241	f	f
242	Laura	Robles	Laura	Robles	1823-07-18	1843-05-05	M	593	242	f	f
243	Rick	Murphy	Rick	Murphy	1823-09-16	1843-04-16	F	815	243	f	f
244	Jennifer	Black	Jennifer	Black	1823-08-16	1843-12-16	M	139	244	f	f
245	Janet	Nelson	Janet	Nelson	1823-11-09	1843-08-28	F	1092	245	f	f
246	Susan	Smith	Susan	Smith	1823-06-26	1843-08-22	M	299	246	f	f
247	Chad	Nelson	Chad	Nelson	1823-08-12	1843-06-15	F	578	247	f	f
248	Cesar	Peterson	Cesar	Peterson	1823-03-18	1843-05-17	M	372	248	f	f
249	Amanda	Green	Amanda	Green	1823-05-12	1843-06-26	F	975	249	f	f
250	Jennifer	Brown	Jennifer	Brown	1823-03-04	1843-12-10	M	1017	250	f	f
251	Rebecca	Novak	Rebecca	Novak	1823-05-13	1843-12-19	F	53	251	f	f
252	Michael	Smith	Michael	Smith	1823-12-06	1843-09-15	M	711	252	f	f
253	Melissa	Barron	Melissa	Barron	1823-05-19	1843-05-13	F	300	253	f	f
254	Aaron	Richardson	Aaron	Richardson	1823-12-07	1843-11-01	M	562	254	f	f
255	Patrick	Jacobs	Patrick	Jacobs	1823-07-25	1843-03-20	F	807	255	f	f
256	Crystal	Braun	Crystal	Braun	1798-11-26	1818-09-13	M	16	256	f	f
257	John	Mullen	John	Mullen	1798-12-11	1818-07-05	F	886	257	f	f
258	Rachel	Martinez	Rachel	Martinez	1798-11-27	1818-04-06	M	7	258	f	f
259	Joseph	Lawson	Joseph	Lawson	1798-08-03	1818-02-02	F	569	259	f	f
260	Dana	Hicks	Dana	Hicks	1798-11-16	1818-02-20	M	1061	260	f	f
261	Jillian	Russell	Jillian	Russell	1798-01-20	1818-05-03	F	384	261	f	f
262	Scott	Williams	Scott	Williams	1798-11-13	1818-04-13	M	450	262	f	f
263	Ronald	Sharp	Ronald	Sharp	1798-11-21	1818-08-06	F	296	263	f	f
264	Ronald	Rodriguez	Ronald	Rodriguez	1798-08-21	1818-02-19	M	1190	264	f	f
265	Christopher	Davis	Christopher	Davis	1798-04-18	1818-11-12	F	753	265	f	f
266	Maria	Fletcher	Maria	Fletcher	1798-06-09	1818-10-06	M	358	266	f	f
267	James	Chambers	James	Chambers	1798-09-11	1818-05-15	F	346	267	f	f
268	Michael	Morris	Michael	Morris	1798-03-15	1818-08-06	M	963	268	f	f
269	Deborah	Williams	Deborah	Williams	1798-06-16	1818-11-06	F	602	269	f	f
270	Patrick	Jimenez	Patrick	Jimenez	1798-01-23	1818-09-25	M	552	270	f	f
271	Debra	Rojas	Debra	Rojas	1798-02-20	1818-11-19	F	121	271	f	f
272	Amy	Mitchell	Amy	Mitchell	1798-12-04	1818-07-11	M	566	272	f	f
273	Angela	Macias	Angela	Macias	1798-07-01	1818-08-19	F	332	273	f	f
274	Jessica	Young	Jessica	Young	1798-08-12	1818-08-02	M	1085	274	f	f
275	Lance	Evans	Lance	Evans	1798-11-19	1818-02-06	F	854	275	f	f
276	Nicholas	Phillips	Nicholas	Phillips	1798-12-24	1818-09-12	M	318	276	f	f
277	Robert	Smith	Robert	Smith	1798-01-09	1818-01-20	F	849	277	f	f
278	Lori	Kennedy	Lori	Kennedy	1798-12-03	1818-08-11	M	565	278	f	f
279	Wesley	Williams	Wesley	Williams	1798-07-06	1818-04-28	F	541	279	f	f
280	Kevin	Bailey	Kevin	Bailey	1798-06-24	1818-06-18	M	513	280	f	f
281	Kimberly	Finley	Kimberly	Finley	1798-06-04	1818-06-27	F	15	281	f	f
282	Mitchell	Madden	Mitchell	Madden	1798-10-25	1818-09-21	M	912	282	f	f
283	Sophia	Williams	Sophia	Williams	1798-05-12	1818-01-26	F	345	283	f	f
284	Craig	Luna	Craig	Luna	1798-07-23	1818-06-20	M	1107	284	f	f
285	Jeff	Ramirez	Jeff	Ramirez	1798-07-11	1818-08-13	F	1179	285	f	f
286	Angelica	Owens	Angelica	Owens	1798-09-18	1818-04-04	M	388	286	f	f
287	Crystal	Mitchell	Crystal	Mitchell	1798-02-07	1818-07-20	F	226	287	f	f
288	Carrie	Holloway	Carrie	Holloway	1798-03-19	1818-09-08	M	1011	288	f	f
289	Alicia	Clark	Alicia	Clark	1798-03-12	1818-01-15	F	1173	289	f	f
290	Michael	Gonzalez	Michael	Gonzalez	1798-01-26	1818-07-04	M	442	290	f	f
291	Carlos	Griffith	Carlos	Griffith	1798-01-27	1818-12-24	F	283	291	f	f
292	Gary	Dean	Gary	Dean	1798-06-18	1818-12-05	M	248	292	f	f
293	Kevin	Smith	Kevin	Smith	1798-04-02	1818-05-27	F	1183	293	f	f
294	Travis	Jensen	Travis	Jensen	1798-11-27	1818-10-15	M	581	294	f	f
295	Elizabeth	Nichols	Elizabeth	Nichols	1798-04-06	1818-02-28	F	559	295	f	f
296	Sean	Castillo	Sean	Castillo	1798-12-23	1818-07-02	M	537	296	f	f
297	David	Yu	David	Yu	1798-10-14	1818-10-13	F	318	297	f	f
298	Edward	Davis	Edward	Davis	1798-10-15	1818-06-26	M	563	298	f	f
299	Donna	David	Donna	David	1798-01-23	1818-10-20	F	1153	299	f	f
300	Lisa	Moss	Lisa	Moss	1798-03-01	1818-06-18	M	372	300	f	f
301	Frank	Robinson	Frank	Robinson	1798-07-07	1818-02-07	F	62	301	f	f
302	Courtney	Moore	Courtney	Moore	1798-04-13	1818-05-06	M	709	302	f	f
303	Samantha	Gill	Samantha	Gill	1798-04-07	1818-01-17	F	449	303	f	f
304	Betty	Bauer	Betty	Bauer	1798-03-01	1818-11-12	M	411	304	f	f
305	Matthew	Vang	Matthew	Vang	1798-01-08	1818-09-20	F	881	305	f	f
306	Jessica	Mata	Jessica	Mata	1798-10-10	1818-06-10	M	592	306	f	f
307	Karen	Jones	Karen	Jones	1798-03-04	1818-01-08	F	874	307	f	f
308	Robert	Garza	Robert	Garza	1798-10-10	1818-06-07	M	591	308	f	f
309	Charles	Norton	Charles	Norton	1798-03-23	1818-07-19	F	359	309	f	f
310	Daniel	Garner	Daniel	Garner	1798-11-09	1818-11-13	M	436	310	f	f
311	David	Singleton	David	Singleton	1798-02-28	1818-03-26	F	75	311	f	f
312	Justin	Baker	Justin	Baker	1798-02-12	1818-12-01	M	845	312	f	f
313	Heather	Taylor	Heather	Taylor	1798-10-06	1818-12-14	F	1230	313	f	f
314	Brandon	Velasquez	Brandon	Velasquez	1798-07-25	1818-10-05	M	393	314	f	f
315	Adam	Black	Adam	Black	1798-11-19	1818-11-26	F	913	315	f	f
316	Albert	Smith	Albert	Smith	1798-01-17	1818-12-09	M	806	316	f	f
317	David	Barnes	David	Barnes	1798-11-04	1818-10-07	F	147	317	f	f
318	Katherine	Benjamin	Katherine	Benjamin	1798-02-27	1818-07-21	M	1070	318	f	f
319	Amber	Lopez	Amber	Lopez	1798-09-06	1818-12-04	F	1224	319	f	f
320	Cynthia	Phelps	Cynthia	Phelps	1798-11-21	1818-07-09	M	56	320	f	f
321	Jonathon	Hurley	Jonathon	Hurley	1798-07-23	1818-01-25	F	975	321	f	f
322	Evan	Bowers	Evan	Bowers	1798-05-09	1818-11-05	M	273	322	f	f
323	Kristen	Wolfe	Kristen	Wolfe	1798-05-21	1818-04-28	F	850	323	f	f
324	Christopher	Lee	Christopher	Lee	1798-04-03	1818-10-13	M	57	324	f	f
325	Kristin	Sawyer	Kristin	Sawyer	1798-07-23	1818-08-04	F	276	325	f	f
326	Nicholas	Dickerson	Nicholas	Dickerson	1798-06-28	1818-03-20	M	750	326	f	f
327	Katherine	Figueroa	Katherine	Figueroa	1798-12-22	1818-04-08	F	151	327	f	f
328	Lisa	Le	Lisa	Le	1798-08-08	1818-03-01	M	1153	328	f	f
329	Jon	Thornton	Jon	Thornton	1798-02-20	1818-06-21	F	708	329	f	f
330	David	Wilkins	David	Wilkins	1798-10-09	1818-07-11	M	378	330	f	f
331	Michael	Nash	Michael	Nash	1798-05-12	1818-01-01	F	315	331	f	f
332	Olivia	George	Olivia	George	1798-05-21	1818-10-24	M	249	332	f	f
333	Benjamin	Oneill	Benjamin	Oneill	1798-07-19	1818-04-28	F	1183	333	f	f
334	Scott	Ashley	Scott	Ashley	1798-01-11	1818-10-02	M	1108	334	f	f
335	Edward	Frank	Edward	Frank	1798-08-13	1818-03-17	F	676	335	f	f
336	Tamara	Flores	Tamara	Flores	1798-03-08	1818-10-01	M	820	336	f	f
337	Jerry	Ramsey	Jerry	Ramsey	1798-01-01	1818-06-01	F	939	337	f	f
338	Anna	Merritt	Anna	Merritt	1798-05-01	1818-10-18	M	112	338	f	f
339	Laurie	Benson	Laurie	Benson	1798-12-04	1818-05-06	F	815	339	f	f
340	Matthew	Sandoval	Matthew	Sandoval	1798-09-28	1818-08-20	M	88	340	f	f
341	Jerry	Taylor	Jerry	Taylor	1798-11-03	1818-05-10	F	312	341	f	f
342	Robert	Garcia	Robert	Garcia	1798-11-10	1818-02-02	M	1114	342	f	f
343	Ashley	Keller	Ashley	Keller	1798-07-27	1818-09-18	F	888	343	f	f
344	Melissa	Thompson	Melissa	Thompson	1798-01-16	1818-01-06	M	891	344	f	f
345	Kathleen	Gray	Kathleen	Gray	1798-02-04	1818-05-06	F	328	345	f	f
346	Ryan	Cochran	Ryan	Cochran	1798-11-17	1818-11-15	M	224	346	f	f
347	Ashley	Wilkinson	Ashley	Wilkinson	1798-08-05	1818-07-09	F	650	347	f	f
348	Jacqueline	Yates	Jacqueline	Yates	1798-06-14	1818-08-21	M	295	348	f	f
349	Erin	Fisher	Erin	Fisher	1798-06-01	1818-03-02	F	1036	349	f	f
350	Christine	Garcia	Christine	Garcia	1798-08-23	1818-10-13	M	399	350	f	f
351	David	Bowman	David	Bowman	1798-10-07	1818-10-13	F	271	351	f	f
352	Lance	Mosley	Lance	Mosley	1798-06-23	1818-11-04	M	878	352	f	f
353	Kim	Rodriguez	Kim	Rodriguez	1798-11-05	1818-10-20	F	888	353	f	f
354	Erin	Erickson	Erin	Erickson	1798-12-19	1818-09-26	M	863	354	f	f
355	Rachel	Robbins	Rachel	Robbins	1798-10-10	1818-12-26	F	808	355	f	f
356	Jake	Reilly	Jake	Reilly	1798-03-13	1818-08-03	M	486	356	f	f
357	Christian	Thomas	Christian	Thomas	1798-10-14	1818-03-13	F	989	357	f	f
358	Leonard	Michael	Leonard	Michael	1798-05-05	1818-05-12	M	526	358	f	f
359	Alyssa	Ellison	Alyssa	Ellison	1798-02-28	1818-04-23	F	193	359	f	f
360	Amber	Lee	Amber	Lee	1798-03-08	1818-01-04	M	135	360	f	f
361	Barbara	Jones	Barbara	Jones	1798-05-17	1818-08-27	F	367	361	f	f
362	Michael	Pierce	Michael	Pierce	1798-04-12	1818-04-07	M	1168	362	f	f
363	David	Dean	David	Dean	1798-08-06	1818-09-07	F	332	363	f	f
364	Samantha	Evans	Samantha	Evans	1798-05-06	1818-01-24	M	774	364	f	f
365	Carla	Lyons	Carla	Lyons	1798-11-25	1818-01-25	F	81	365	f	f
366	Taylor	Williams	Taylor	Williams	1798-09-19	1818-12-09	M	447	366	f	f
367	Charles	Madden	Charles	Madden	1798-07-02	1818-06-27	F	774	367	f	f
368	Michael	Davis	Michael	Davis	1798-06-25	1818-06-25	M	1141	368	f	f
369	Donna	Nelson	Donna	Nelson	1798-06-10	1818-04-09	F	619	369	f	f
370	Shari	Jimenez	Shari	Jimenez	1798-12-07	1818-05-06	M	811	370	f	f
371	Raymond	Lopez	Raymond	Lopez	1798-01-28	1818-07-17	F	198	371	f	f
372	Amanda	Levy	Amanda	Levy	1798-02-11	1818-07-25	M	713	372	f	f
373	Keith	Rowland	Keith	Rowland	1798-03-03	1818-06-18	F	501	373	f	f
374	Robert	Shelton	Robert	Shelton	1798-11-12	1818-03-23	M	111	374	f	f
375	Robert	Hutchinson	Robert	Hutchinson	1798-04-20	1818-05-02	F	825	375	f	f
376	Tammy	Gomez	Tammy	Gomez	1798-04-06	1818-07-17	M	998	376	f	f
377	Randy	Herrera	Randy	Herrera	1798-06-11	1818-07-20	F	445	377	f	f
378	Wendy	Oneal	Wendy	Oneal	1798-03-09	1818-12-14	M	1104	378	f	f
379	Caitlin	Wright	Caitlin	Wright	1798-04-23	1818-08-08	F	958	379	f	f
380	Joshua	Jones	Joshua	Jones	1798-04-27	1818-10-26	M	1082	380	f	f
381	Chris	Moore	Chris	Moore	1798-04-14	1818-05-10	F	451	381	f	f
382	Daniel	Anderson	Daniel	Anderson	1798-05-17	1818-03-19	M	398	382	f	f
383	Erin	Johnson	Erin	Johnson	1798-12-05	1818-07-22	F	736	383	f	f
384	Erika	Diaz	Erika	Diaz	1798-09-15	1818-10-12	M	205	384	f	f
385	Angela	Wood	Angela	Wood	1798-07-05	1818-06-07	F	486	385	f	f
386	Shaun	Gates	Shaun	Gates	1798-06-17	1818-09-18	M	640	386	f	f
387	Jessica	Garza	Jessica	Garza	1798-05-04	1818-01-02	F	658	387	f	f
388	Margaret	Henderson	Margaret	Henderson	1798-08-24	1818-04-12	M	1188	388	f	f
389	Rebecca	Miller	Rebecca	Miller	1798-11-19	1818-02-23	F	448	389	f	f
390	Lori	Wright	Lori	Wright	1798-11-21	1818-12-11	M	891	390	f	f
391	Mark	Jenkins	Mark	Jenkins	1798-12-23	1818-12-20	F	703	391	f	f
392	Elizabeth	Pierce	Elizabeth	Pierce	1798-02-22	1818-04-17	M	1146	392	f	f
393	Thomas	Davis	Thomas	Davis	1798-03-28	1818-05-10	F	139	393	f	f
394	Kenneth	Gaines	Kenneth	Gaines	1798-11-20	1818-11-15	M	561	394	f	f
395	Jennifer	Wall	Jennifer	Wall	1798-11-16	1818-11-15	F	189	395	f	f
396	Elizabeth	Robertson	Elizabeth	Robertson	1798-07-05	1818-07-12	M	1125	396	f	f
397	Kristin	Todd	Kristin	Todd	1798-10-26	1818-05-07	F	565	397	f	f
398	Sarah	Haynes	Sarah	Haynes	1798-06-25	1818-07-09	M	62	398	f	f
399	Margaret	Beard	Margaret	Beard	1798-02-07	1818-08-18	F	551	399	f	f
400	Jonathan	Garza	Jonathan	Garza	1798-06-06	1818-04-24	M	45	400	f	f
401	Kristi	Stewart	Kristi	Stewart	1798-12-20	1818-05-03	F	966	401	f	f
402	Dwayne	Mcgee	Dwayne	Mcgee	1798-12-10	1818-06-22	M	170	402	f	f
403	Richard	Jones	Richard	Jones	1798-06-05	1818-03-19	F	719	403	f	f
404	Alexandria	Alvarado	Alexandria	Alvarado	1798-10-24	1818-03-03	M	954	404	f	f
405	Christina	Smith	Christina	Smith	1798-07-05	1818-08-19	F	1191	405	f	f
406	Michael	Trujillo	Michael	Trujillo	1798-07-26	1818-05-18	M	611	406	f	f
407	Jennifer	Gutierrez	Jennifer	Gutierrez	1798-02-19	1818-10-23	F	587	407	f	f
408	Christian	Cooper	Christian	Cooper	1798-03-25	1818-10-05	M	1083	408	f	f
409	Anthony	Jones	Anthony	Jones	1798-04-20	1818-12-21	F	925	409	f	f
410	Pedro	Skinner	Pedro	Skinner	1798-05-18	1818-04-06	M	715	410	f	f
411	Dean	Griffin	Dean	Griffin	1798-01-20	1818-11-20	F	224	411	f	f
412	Sharon	Wells	Sharon	Wells	1798-07-24	1818-04-22	M	563	412	f	f
413	Kristy	Blake	Kristy	Blake	1798-01-27	1818-02-19	F	465	413	f	f
414	Stephen	Morales	Stephen	Morales	1798-07-27	1818-12-13	M	937	414	f	f
415	Meghan	Patton	Meghan	Patton	1798-11-15	1818-09-01	F	959	415	f	f
416	Debra	Rivera	Debra	Rivera	1798-05-13	1818-01-07	M	34	416	f	f
417	Chad	White	Chad	White	1798-11-01	1818-07-16	F	854	417	f	f
418	Darrell	Pace	Darrell	Pace	1798-11-05	1818-09-04	M	1133	418	f	f
419	Paul	Miller	Paul	Miller	1798-06-01	1818-07-18	F	1046	419	f	f
420	Martha	Ware	Martha	Ware	1798-03-28	1818-07-23	M	1212	420	f	f
421	Leslie	Roberts	Leslie	Roberts	1798-12-26	1818-05-23	F	349	421	f	f
422	Phillip	Nelson	Phillip	Nelson	1798-10-02	1818-09-02	M	886	422	f	f
423	Jack	Miller	Jack	Miller	1798-04-06	1818-11-24	F	158	423	f	f
424	Justin	Williams	Justin	Williams	1798-06-26	1818-04-26	M	468	424	f	f
425	Marcia	Mcdonald	Marcia	Mcdonald	1798-09-02	1818-04-09	F	95	425	f	f
426	Erin	Cox	Erin	Cox	1798-05-21	1818-11-27	M	1167	426	f	f
427	Richard	Barker	Richard	Barker	1798-03-21	1818-02-28	F	19	427	f	f
428	Meredith	Woodward	Meredith	Woodward	1798-05-25	1818-03-02	M	436	428	f	f
429	Emma	Mendez	Emma	Mendez	1798-07-09	1818-07-24	F	622	429	f	f
430	John	Guzman	John	Guzman	1798-03-22	1818-07-14	M	684	430	f	f
431	Kelly	Medina	Kelly	Medina	1798-03-28	1818-05-14	F	465	431	f	f
432	Erica	Middleton	Erica	Middleton	1798-09-04	1818-12-06	M	1092	432	f	f
433	Natalie	Mata	Natalie	Mata	1798-11-03	1818-05-22	F	464	433	f	f
434	Monique	Harris	Monique	Harris	1798-05-09	1818-12-01	M	347	434	f	f
435	Amber	Williams	Amber	Williams	1798-10-27	1818-10-03	F	1023	435	f	f
436	Jessica	Gibson	Jessica	Gibson	1798-12-24	1818-06-27	M	54	436	f	f
437	Jennifer	Woods	Jennifer	Woods	1798-03-21	1818-01-27	F	1108	437	f	f
438	Stacie	Burns	Stacie	Burns	1798-09-21	1818-08-15	M	1221	438	f	f
439	Tyler	Martinez	Tyler	Martinez	1798-01-09	1818-11-02	F	354	439	f	f
440	Ana	Douglas	Ana	Douglas	1798-09-02	1818-09-01	M	239	440	f	f
441	Alan	Frazier	Alan	Frazier	1798-09-11	1818-08-08	F	787	441	f	f
442	Stephen	Murphy	Stephen	Murphy	1798-02-17	1818-08-06	M	130	442	f	f
443	Jeffrey	Miller	Jeffrey	Miller	1798-05-16	1818-02-08	F	599	443	f	f
444	Emily	Mooney	Emily	Mooney	1798-01-07	1818-10-12	M	128	444	f	f
445	Justin	Palmer	Justin	Palmer	1798-04-16	1818-08-03	F	519	445	f	f
446	Christy	Robbins	Christy	Robbins	1798-03-26	1818-08-13	M	747	446	f	f
447	Joseph	Kennedy	Joseph	Kennedy	1798-08-13	1818-08-05	F	590	447	f	f
448	Veronica	Waters	Veronica	Waters	1798-10-25	1818-01-24	M	511	448	f	f
449	Benjamin	Blair	Benjamin	Blair	1798-11-09	1818-11-10	F	100	449	f	f
450	Amanda	Morgan	Amanda	Morgan	1798-06-06	1818-03-26	M	1089	450	f	f
451	Nathaniel	Jackson	Nathaniel	Jackson	1798-01-10	1818-05-15	F	554	451	f	f
452	John	Hensley	John	Hensley	1798-03-11	1818-02-15	M	223	452	f	f
453	Veronica	Hart	Veronica	Hart	1798-05-23	1818-11-24	F	592	453	f	f
454	Jeremy	Snyder	Jeremy	Snyder	1798-01-15	1818-02-22	M	484	454	f	f
455	Amanda	Lambert	Amanda	Lambert	1798-12-05	1818-08-10	F	505	455	f	f
456	Christopher	Stark	Christopher	Stark	1798-06-01	1818-08-19	M	1047	456	f	f
457	Daniel	Duran	Daniel	Duran	1798-11-18	1818-12-18	F	1168	457	f	f
458	Kevin	Mcconnell	Kevin	Mcconnell	1798-04-26	1818-04-06	M	248	458	f	f
459	Troy	Montes	Troy	Montes	1798-03-05	1818-03-04	F	1085	459	f	f
460	Jose	Smith	Jose	Smith	1798-02-08	1818-08-08	M	118	460	f	f
461	Kevin	Kramer	Kevin	Kramer	1798-08-14	1818-01-22	F	299	461	f	f
462	Elizabeth	Carter	Elizabeth	Carter	1798-09-26	1818-01-17	M	442	462	f	f
463	Anthony	Woods	Anthony	Woods	1798-06-13	1818-08-17	F	892	463	f	f
464	Jennifer	Shaffer	Jennifer	Shaffer	1798-11-17	1818-06-16	M	433	464	f	f
465	Erika	Tran	Erika	Tran	1798-02-28	1818-03-27	F	539	465	f	f
466	Colleen	Hampton	Colleen	Hampton	1798-09-11	1818-12-04	M	278	466	f	f
467	Allison	Johnson	Allison	Johnson	1798-03-23	1818-06-23	F	1098	467	f	f
468	Donald	Mcguire	Donald	Mcguire	1798-12-14	1818-07-10	M	1034	468	f	f
469	Elizabeth	Snyder	Elizabeth	Snyder	1798-09-17	1818-02-12	F	1221	469	f	f
470	Nathan	Elliott	Nathan	Elliott	1798-01-08	1818-08-19	M	151	470	f	f
471	Ana	Ford	Ana	Ford	1798-02-14	1818-03-10	F	412	471	f	f
472	Matthew	Juarez	Matthew	Juarez	1798-09-04	1818-07-28	M	183	472	f	f
473	Monica	Stewart	Monica	Stewart	1798-05-14	1818-08-14	F	876	473	f	f
474	Preston	Jensen	Preston	Jensen	1798-01-13	1818-10-23	M	844	474	f	f
475	Valerie	Strickland	Valerie	Strickland	1798-04-10	1818-06-24	F	851	475	f	f
476	Amy	Murphy	Amy	Murphy	1798-07-09	1818-09-23	M	752	476	f	f
477	Krista	Morgan	Krista	Morgan	1798-03-04	1818-10-08	F	499	477	f	f
478	Samuel	Le	Samuel	Le	1798-06-24	1818-12-14	M	518	478	f	f
479	Sierra	Bentley	Sierra	Bentley	1798-08-27	1818-05-12	F	1035	479	f	f
480	Wyatt	Nelson	Wyatt	Nelson	1798-04-15	1818-08-27	M	745	480	f	f
481	Steven	Ramos	Steven	Ramos	1798-01-08	1818-01-10	F	697	481	f	f
482	Jason	Peters	Jason	Peters	1798-03-08	1818-10-05	M	355	482	f	f
483	Frank	Sanchez	Frank	Sanchez	1798-07-05	1818-07-17	F	975	483	f	f
484	James	Sloan	James	Sloan	1798-05-10	1818-10-09	M	913	484	f	f
485	Thomas	Anderson	Thomas	Anderson	1798-03-06	1818-04-22	F	577	485	f	f
486	Samuel	Cuevas	Samuel	Cuevas	1798-05-23	1818-08-17	M	56	486	f	f
487	Ian	Hoffman	Ian	Hoffman	1798-12-10	1818-07-20	F	852	487	f	f
488	Derek	Blair	Derek	Blair	1798-08-11	1818-07-11	M	171	488	f	f
489	Alexandria	Richard	Alexandria	Richard	1798-10-19	1818-03-17	F	536	489	f	f
490	Craig	Blake	Craig	Blake	1798-10-27	1818-10-24	M	728	490	f	f
491	Jonathan	Alvarado	Jonathan	Alvarado	1798-05-16	1818-08-06	F	573	491	f	f
492	Steven	Miranda	Steven	Miranda	1798-09-03	1818-07-06	M	1120	492	f	f
493	Dennis	Wiggins	Dennis	Wiggins	1798-10-28	1818-06-20	F	349	493	f	f
494	Elizabeth	Bailey	Elizabeth	Bailey	1798-04-14	1818-03-09	M	296	494	f	f
495	Cheryl	Henry	Cheryl	Henry	1798-01-28	1818-04-18	F	1072	495	f	f
496	Jacqueline	Bailey	Jacqueline	Bailey	1798-04-16	1818-11-01	M	1108	496	f	f
497	Ashley	Baker	Ashley	Baker	1798-11-13	1818-11-24	F	95	497	f	f
498	Kenneth	Williams	Kenneth	Williams	1798-02-04	1818-02-01	M	639	498	f	f
499	Donald	Mejia	Donald	Mejia	1798-11-12	1818-10-20	F	1192	499	f	f
500					1798-02-03	1818-09-06	M	697	500	f	f
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.people (id, date_of_birth, date_of_death, name, surname) FROM stdin;
1	1990-05-02	\N	Ralph	Mahoney
2	1965-08-26	\N	Sandra	Frye
3	1965-09-16	\N	Tyler	Brandt
4	1940-12-25	\N	Amanda	Hayes
5	1940-12-11	\N	Anthony	Knight
6	1940-06-21	\N	Lawrence	Suarez
7	1940-08-27	\N	Tamara	Snyder
8	1915-05-27	\N	Timothy	Elliott
9	1915-02-27	\N	Jamie	Smith
10	1915-09-03	\N	Nicole	Martinez
11	1915-06-15	\N	Kyle	Foster
12	1915-06-10	\N	Logan	Adams
13	1915-06-01	\N	Paul	Hanson
14	1915-01-12	\N	Michael	Cole
15	1915-01-07	\N	Robert	Foster
16	1890-07-08	\N	Brandon	Rodriguez
17	1890-12-20	\N	Melinda	Evans
18	1890-11-11	\N	Emily	George
19	1890-05-08	\N	John	Nelson
20	1890-10-26	\N	Julie	Crane
21	1890-11-12	\N	Sandra	Smith
22	1890-08-01	\N	Tony	Harris
23	1890-03-05	\N	Calvin	Garza
24	1890-03-02	\N	Aaron	Calhoun
25	1890-08-19	\N	Crystal	Scott
26	1890-11-06	\N	Walter	Bowen
27	1890-03-15	\N	Lucas	Austin
28	1890-07-02	\N	Kristen	Long
29	1890-08-02	\N	Christina	Taylor
30	1890-12-13	\N	Melissa	Thomas
31	1890-05-02	\N	Robert	Fuller
32	1865-03-06	\N	Whitney	Harris
33	1865-09-11	\N	Andrea	Shepard
34	1865-12-01	\N	Luis	Barron
35	1865-02-03	\N	David	Weaver
36	1865-07-28	\N	Emma	Matthews
37	1865-07-01	\N	Allen	Gallagher
38	1865-06-09	\N	Ryan	Luna
39	1865-03-17	\N	Alejandro	Brown
40	1865-04-02	\N	Emily	Ayers
41	1865-03-09	\N	Gina	Clay
42	1865-05-18	\N	Amanda	Davenport
43	1865-09-21	\N	Toni	Miller
44	1865-07-05	\N	Jeffrey	Ryan
45	1865-03-12	\N	John	Smith
46	1865-05-01	\N	Kristin	Williams
47	1865-06-01	\N	Tracy	Caldwell
48	1865-04-20	\N	Alan	Nunez
49	1865-11-10	\N	Amber	Green
50	1865-05-18	\N	Darryl	Olson
51	1865-11-14	\N	Brenda	Rollins
52	1865-08-15	\N	Grant	Roberson
53	1865-11-19	\N	Lauren	Wood
54	1865-07-05	\N	Jon	Dickson
55	1865-05-07	\N	Kyle	Gonzales
56	1865-01-22	\N	Jessica	White
57	1865-04-28	\N	Tyler	Salazar
58	1865-07-19	\N	Paul	Wheeler
59	1865-01-17	\N	Kyle	Blake
60	1865-02-10	\N	Nicholas	Bowen
61	1865-12-06	\N	Kristopher	Hancock
62	1865-06-19	\N	Hector	Edwards
63	1865-02-05	\N	Cindy	Marquez
64	1840-05-23	\N	John	Simmons
65	1840-08-07	\N	Edward	Grant
66	1840-11-20	\N	Samuel	Nielsen
67	1840-02-27	\N	Scott	Guerrero
68	1840-03-22	\N	Jennifer	Jones
69	1840-07-24	\N	Thomas	Neal
70	1840-07-02	\N	Steven	Morgan
71	1840-12-13	\N	Stephen	Bender
72	1840-11-22	\N	Rebecca	Haynes
73	1840-08-15	\N	Corey	Daniels
74	1840-12-08	\N	Julie	Martinez
75	1840-06-16	\N	Kyle	Tucker
76	1840-04-28	\N	Nathan	Martin
77	1840-01-06	\N	Levi	Long
78	1840-12-04	\N	Zachary	Jackson
79	1840-03-19	\N	Juan	Smith
80	1840-03-03	\N	Michael	Young
81	1840-11-02	\N	Carolyn	Rivera
82	1840-01-21	\N	John	Robinson
83	1840-01-02	\N	Justin	Hughes
84	1840-12-24	\N	Michael	Murillo
85	1840-05-16	\N	Wyatt	Brennan
86	1840-04-09	\N	Christy	Obrien
87	1840-02-06	\N	Martin	Greer
88	1840-09-11	\N	Cynthia	Walker
89	1840-09-07	\N	Adam	Hunt
90	1840-07-20	\N	Joseph	Nelson
91	1840-06-11	\N	Damon	Valenzuela
92	1840-08-07	\N	Linda	Golden
93	1840-08-05	\N	Richard	Flores
94	1840-11-07	\N	Matthew	Tucker
95	1840-04-20	\N	Rebecca	Hughes
96	1840-05-24	\N	Jennifer	Nelson
97	1840-01-24	\N	Megan	Davis
98	1840-09-12	\N	Daniel	Wilson
99	1840-02-09	\N	Henry	Carrillo
100	1840-04-19	\N	Dalton	Henderson
101	1840-09-09	\N	James	Hill
102	1840-06-19	\N	Patricia	Garcia
103	1840-01-17	\N	John	Hawkins
104	1840-09-06	\N	Danielle	Phillips
105	1840-06-15	\N	Michael	Davis
106	1840-04-08	\N	Danielle	Anderson
107	1840-03-23	\N	Lisa	Rodriguez
108	1840-02-12	\N	Ryan	Jenkins
109	1840-05-04	\N	Scott	Patterson
110	1840-04-26	\N	John	Gonzalez
111	1840-05-17	\N	Kathy	Fry
112	1840-12-19	\N	Kelly	Mejia
113	1840-02-25	\N	Lisa	Le
114	1840-04-23	\N	John	Nelson
115	1840-03-25	\N	Angela	Marsh
116	1840-02-03	\N	Jonathan	Edwards
117	1840-03-24	\N	David	Williams
118	1840-05-04	\N	Kristin	Gonzalez
119	1840-12-03	\N	Susan	Neal
120	1840-05-09	\N	Lucas	Gilbert
121	1840-04-10	\N	Cody	Meyer
122	1840-04-04	\N	Michelle	Ross
123	1840-03-04	\N	Donna	Daniels
124	1840-09-15	\N	Joel	Miller
125	1840-06-12	\N	Jennifer	Johnson
126	1840-07-01	\N	Maurice	Smith
127	1840-11-11	\N	Ryan	Matthews
128	1815-10-15	\N	Sharon	Perry
129	1815-10-20	\N	Ashley	Reed
130	1815-12-10	\N	Teresa	Shaw
131	1815-02-26	\N	Stacy	Jenkins
132	1815-05-11	\N	David	Brooks
133	1815-11-12	\N	Angelica	Reyes
134	1815-01-28	\N	Natalie	Holmes
135	1815-05-09	\N	Joshua	Flores
136	1815-09-27	\N	Melissa	Young
137	1815-11-01	\N	Tracey	Williams
138	1815-12-28	\N	Jessica	Rubio
139	1815-06-01	\N	Darlene	Kelley
140	1815-10-06	\N	Sherry	Melton
141	1815-10-05	\N	Emily	Garner
142	1815-06-13	\N	Amber	Dickerson
143	1815-01-19	\N	Kathryn	Leach
144	1815-10-01	\N	Andrew	Scott
145	1815-06-14	\N	Jerry	Grant
146	1815-01-14	\N	Wesley	Cross
147	1815-03-04	\N	Randy	Miller
148	1815-12-11	\N	Jamie	Vaughn
149	1815-10-05	\N	Melissa	Callahan
150	1815-03-20	\N	Samantha	Williams
151	1815-11-15	\N	Cathy	Michael
152	1815-10-23	\N	Abigail	Patterson
153	1815-10-04	\N	Allison	Dudley
154	1815-10-25	\N	Kaitlyn	Peters
155	1815-09-13	\N	Darlene	Byrd
156	1815-02-07	\N	David	Huang
157	1815-07-11	\N	Phillip	Sullivan
158	1815-03-27	\N	Morgan	Duncan
159	1815-12-10	\N	Danielle	Martinez
160	1815-10-04	\N	Natasha	Grant
161	1815-09-17	\N	Stephanie	Wheeler
162	1815-12-26	\N	Raymond	Terrell
163	1815-05-20	\N	Krista	Marquez
164	1815-06-08	\N	Tamara	Tucker
165	1815-05-21	\N	Connie	Garza
166	1815-08-07	\N	David	King
167	1815-06-01	\N	Tracey	Ponce
168	1815-11-08	\N	Michael	Morrow
169	1815-06-15	\N	Laura	Richardson
170	1815-04-19	\N	Melinda	Atkins
171	1815-05-03	\N	Pamela	Robinson
172	1815-10-27	\N	Tara	Murray
173	1815-08-22	\N	Elizabeth	Glover
174	1815-09-15	\N	Dennis	Gomez
175	1815-01-10	\N	Jenna	Schroeder
176	1815-06-01	\N	Amber	Hill
177	1815-10-27	\N	Brittany	Kim
178	1815-07-25	\N	Diana	Hall
179	1815-09-12	\N	Logan	Morris
180	1815-03-02	\N	Ashley	Delgado
181	1815-07-18	\N	Rachel	Frederick
182	1815-04-04	\N	Rachel	Andrews
183	1815-06-02	\N	Mario	Harris
184	1815-05-09	\N	Scott	Martin
185	1815-09-13	\N	Alyssa	Williams
186	1815-07-08	\N	Steven	Silva
187	1815-11-24	\N	John	Knox
188	1815-06-09	\N	Donna	Green
189	1815-03-05	\N	Natalie	Taylor
190	1815-12-26	\N	Robert	Lam
191	1815-04-26	\N	Nathan	Campbell
192	1815-02-28	\N	Crystal	Meza
193	1815-08-14	\N	Robert	Lane
194	1815-06-12	\N	Valerie	Wade
195	1815-11-02	\N	Tiffany	Patterson
196	1815-12-20	\N	Stephanie	Garza
197	1815-02-22	\N	Kimberly	Shields
198	1815-02-19	\N	Austin	Martinez
199	1815-01-11	\N	Timothy	Carter
200	1815-05-02	\N	Timothy	Harris
201	1815-06-07	\N	Martin	Riley
202	1815-11-02	\N	Walter	Clarke
203	1815-11-19	\N	Kayla	Herrera
204	1815-04-06	\N	William	Adams
205	1815-11-20	\N	Bryan	Blackwell
206	1815-05-06	\N	Donald	Anderson
207	1815-03-27	\N	Jonathan	Gutierrez
208	1815-04-22	\N	Jennifer	Marquez
209	1815-02-08	\N	Kelsey	Smith
210	1815-06-06	\N	Mark	Ware
211	1815-05-14	\N	Jonathan	Haynes
212	1815-06-09	\N	Sandra	Kirk
213	1815-03-25	\N	Elizabeth	Pope
214	1815-07-20	\N	Misty	Hart
215	1815-10-26	\N	Darrell	Moyer
216	1815-12-09	\N	Bernard	Mann
217	1815-12-24	\N	Jerry	Huffman
218	1815-01-26	\N	Chad	Park
219	1815-01-24	\N	Pamela	Wagner
220	1815-12-08	\N	Lauren	Lamb
221	1815-02-16	\N	Sandra	Wright
222	1815-09-26	\N	Kathryn	Cain
223	1815-12-03	\N	Molly	Newman
224	1815-02-20	\N	Keith	Wallace
225	1815-01-03	\N	Rebecca	Hogan
226	1815-03-19	\N	Daniel	Chen
227	1815-03-28	\N	Jason	Stewart
228	1815-06-08	\N	Christopher	Bailey
229	1815-09-17	\N	Phillip	Martin
230	1815-02-09	\N	Kelsey	Mayo
231	1815-11-27	\N	Karen	Thompson
232	1815-03-28	\N	Jamie	Atkins
233	1815-07-26	\N	Edward	Strong
234	1815-11-05	\N	Stacy	Kim
235	1815-01-25	\N	Bryan	Ross
236	1815-12-08	\N	David	Kirby
237	1815-06-02	\N	Andrew	Freeman
238	1815-04-12	\N	Jennifer	Hudson
239	1815-03-22	\N	Scott	Moreno
240	1815-11-20	\N	Shannon	King
241	1815-12-08	\N	Kristen	Thomas
242	1815-02-28	\N	Brittany	Dickerson
243	1815-08-05	\N	Laura	Robles
244	1815-02-18	\N	Rick	Murphy
245	1815-06-03	\N	Jennifer	Black
246	1815-05-28	\N	Janet	Nelson
247	1815-03-10	\N	Susan	Smith
248	1815-03-23	\N	Chad	Nelson
249	1815-12-10	\N	Cesar	Peterson
250	1815-08-01	\N	Amanda	Green
251	1815-01-01	\N	Jennifer	Brown
252	1815-03-03	\N	Rebecca	Novak
253	1815-02-04	\N	Michael	Smith
254	1815-06-23	\N	Melissa	Barron
255	1815-07-25	\N	Aaron	Richardson
256	1790-06-25	\N	Patrick	Jacobs
257	1790-01-12	\N	Crystal	Braun
258	1790-11-08	\N	John	Mullen
259	1790-11-11	\N	Rachel	Martinez
260	1790-05-28	\N	Joseph	Lawson
261	1790-06-06	\N	Dana	Hicks
262	1790-10-27	\N	Jillian	Russell
263	1790-01-21	\N	Scott	Williams
264	1790-10-21	\N	Ronald	Sharp
265	1790-10-02	\N	Ronald	Rodriguez
266	1790-03-19	\N	Christopher	Davis
267	1790-06-05	\N	Maria	Fletcher
268	1790-08-08	\N	James	Chambers
269	1790-12-15	\N	Michael	Morris
270	1790-11-06	\N	Deborah	Williams
271	1790-03-23	\N	Patrick	Jimenez
272	1790-12-08	\N	Debra	Rojas
273	1790-08-24	\N	Amy	Mitchell
274	1790-07-18	\N	Angela	Macias
275	1790-09-17	\N	Jessica	Young
276	1790-05-01	\N	Lance	Evans
277	1790-03-24	\N	Nicholas	Phillips
278	1790-12-12	\N	Robert	Smith
279	1790-08-28	\N	Lori	Kennedy
280	1790-01-26	\N	Wesley	Williams
281	1790-02-25	\N	Kevin	Bailey
282	1790-05-19	\N	Kimberly	Finley
283	1790-01-23	\N	Mitchell	Madden
284	1790-07-16	\N	Sophia	Williams
285	1790-03-03	\N	Craig	Luna
286	1790-03-26	\N	Jeff	Ramirez
287	1790-01-10	\N	Angelica	Owens
288	1790-06-10	\N	Crystal	Mitchell
289	1790-01-18	\N	Carrie	Holloway
290	1790-02-07	\N	Alicia	Clark
291	1790-02-14	\N	Michael	Gonzalez
292	1790-03-28	\N	Carlos	Griffith
293	1790-12-10	\N	Gary	Dean
294	1790-12-06	\N	Kevin	Smith
295	1790-08-08	\N	Travis	Jensen
296	1790-05-06	\N	Elizabeth	Nichols
297	1790-06-01	\N	Sean	Castillo
298	1790-09-26	\N	David	Yu
299	1790-02-11	\N	Edward	Davis
300	1790-12-26	\N	Donna	David
301	1790-11-08	\N	Lisa	Moss
302	1790-05-21	\N	Frank	Robinson
303	1790-02-09	\N	Courtney	Moore
304	1790-08-08	\N	Samantha	Gill
305	1790-05-20	\N	Betty	Bauer
306	1790-09-09	\N	Matthew	Vang
307	1790-07-19	\N	Jessica	Mata
308	1790-11-04	\N	Karen	Jones
309	1790-10-16	\N	Robert	Garza
310	1790-08-19	\N	Charles	Norton
311	1790-09-09	\N	Daniel	Garner
312	1790-08-15	\N	David	Singleton
313	1790-09-20	\N	Justin	Baker
314	1790-08-17	\N	Heather	Taylor
315	1790-09-23	\N	Brandon	Velasquez
316	1790-04-07	\N	Adam	Black
317	1790-06-12	\N	Albert	Smith
318	1790-04-05	\N	David	Barnes
319	1790-01-08	\N	Katherine	Benjamin
320	1790-02-25	\N	Amber	Lopez
321	1790-02-08	\N	Cynthia	Phelps
322	1790-01-16	\N	Jonathon	Hurley
323	1790-05-25	\N	Evan	Bowers
324	1790-02-21	\N	Kristen	Wolfe
325	1790-02-08	\N	Christopher	Lee
326	1790-08-26	\N	Kristin	Sawyer
327	1790-11-11	\N	Nicholas	Dickerson
328	1790-02-25	\N	Katherine	Figueroa
329	1790-10-11	\N	Lisa	Le
330	1790-10-01	\N	Jon	Thornton
331	1790-04-03	\N	David	Wilkins
332	1790-06-12	\N	Michael	Nash
333	1790-10-27	\N	Olivia	George
334	1790-02-26	\N	Benjamin	Oneill
335	1790-03-28	\N	Scott	Ashley
336	1790-02-18	\N	Edward	Frank
337	1790-05-13	\N	Tamara	Flores
338	1790-04-02	\N	Jerry	Ramsey
339	1790-11-27	\N	Anna	Merritt
340	1790-01-16	\N	Laurie	Benson
341	1790-02-21	\N	Matthew	Sandoval
342	1790-12-01	\N	Jerry	Taylor
343	1790-11-20	\N	Robert	Garcia
344	1790-11-09	\N	Ashley	Keller
345	1790-09-10	\N	Melissa	Thompson
346	1790-05-16	\N	Kathleen	Gray
347	1790-06-18	\N	Ryan	Cochran
348	1790-01-14	\N	Ashley	Wilkinson
349	1790-04-21	\N	Jacqueline	Yates
350	1790-10-16	\N	Erin	Fisher
351	1790-02-26	\N	Christine	Garcia
352	1790-11-28	\N	David	Bowman
353	1790-05-10	\N	Lance	Mosley
354	1790-08-28	\N	Kim	Rodriguez
355	1790-04-21	\N	Erin	Erickson
356	1790-04-19	\N	Rachel	Robbins
357	1790-11-28	\N	Jake	Reilly
358	1790-08-02	\N	Christian	Thomas
359	1790-02-19	\N	Leonard	Michael
360	1790-09-01	\N	Alyssa	Ellison
361	1790-07-15	\N	Amber	Lee
362	1790-11-24	\N	Barbara	Jones
363	1790-09-28	\N	Michael	Pierce
364	1790-12-03	\N	David	Dean
365	1790-12-05	\N	Samantha	Evans
366	1790-06-20	\N	Carla	Lyons
367	1790-09-01	\N	Taylor	Williams
368	1790-06-15	\N	Charles	Madden
369	1790-10-27	\N	Michael	Davis
370	1790-07-04	\N	Donna	Nelson
371	1790-04-03	\N	Shari	Jimenez
372	1790-11-03	\N	Raymond	Lopez
373	1790-12-26	\N	Amanda	Levy
374	1790-07-21	\N	Keith	Rowland
375	1790-03-01	\N	Robert	Shelton
376	1790-02-14	\N	Robert	Hutchinson
377	1790-05-13	\N	Tammy	Gomez
378	1790-12-01	\N	Randy	Herrera
379	1790-08-26	\N	Wendy	Oneal
380	1790-11-02	\N	Caitlin	Wright
381	1790-01-04	\N	Joshua	Jones
382	1790-09-26	\N	Chris	Moore
383	1790-09-06	\N	Daniel	Anderson
384	1790-12-15	\N	Erin	Johnson
385	1790-03-24	\N	Erika	Diaz
386	1790-06-27	\N	Angela	Wood
387	1790-05-13	\N	Shaun	Gates
388	1790-10-11	\N	Jessica	Garza
389	1790-12-05	\N	Margaret	Henderson
390	1790-10-12	\N	Rebecca	Miller
391	1790-04-03	\N	Lori	Wright
392	1790-02-01	\N	Mark	Jenkins
393	1790-07-26	\N	Elizabeth	Pierce
394	1790-02-08	\N	Thomas	Davis
395	1790-12-10	\N	Kenneth	Gaines
396	1790-03-22	\N	Jennifer	Wall
397	1790-08-17	\N	Elizabeth	Robertson
398	1790-02-27	\N	Kristin	Todd
399	1790-02-09	\N	Sarah	Haynes
400	1790-02-23	\N	Margaret	Beard
401	1790-07-01	\N	Jonathan	Garza
402	1790-07-27	\N	Kristi	Stewart
403	1790-02-22	\N	Dwayne	Mcgee
404	1790-10-01	\N	Richard	Jones
405	1790-10-03	\N	Alexandria	Alvarado
406	1790-07-02	\N	Christina	Smith
407	1790-04-10	\N	Michael	Trujillo
408	1790-11-15	\N	Jennifer	Gutierrez
409	1790-12-06	\N	Christian	Cooper
410	1790-07-25	\N	Anthony	Jones
411	1790-06-18	\N	Pedro	Skinner
412	1790-01-20	\N	Dean	Griffin
413	1790-07-09	\N	Sharon	Wells
414	1790-05-28	\N	Kristy	Blake
415	1790-09-01	\N	Stephen	Morales
416	1790-06-21	\N	Meghan	Patton
417	1790-10-23	\N	Debra	Rivera
418	1790-08-09	\N	Chad	White
419	1790-06-24	\N	Darrell	Pace
420	1790-12-26	\N	Paul	Miller
421	1790-11-20	\N	Martha	Ware
422	1790-08-05	\N	Leslie	Roberts
423	1790-07-23	\N	Phillip	Nelson
424	1790-05-21	\N	Jack	Miller
425	1790-08-11	\N	Justin	Williams
426	1790-01-10	\N	Marcia	Mcdonald
427	1790-08-05	\N	Erin	Cox
428	1790-06-22	\N	Richard	Barker
429	1790-07-09	\N	Meredith	Woodward
430	1790-05-09	\N	Emma	Mendez
431	1790-10-07	\N	John	Guzman
432	1790-05-24	\N	Kelly	Medina
433	1790-08-24	\N	Erica	Middleton
434	1790-12-04	\N	Natalie	Mata
435	1790-08-14	\N	Monique	Harris
436	1790-09-27	\N	Amber	Williams
437	1790-10-23	\N	Jessica	Gibson
438	1790-07-03	\N	Jennifer	Woods
439	1790-12-24	\N	Stacie	Burns
440	1790-06-06	\N	Tyler	Martinez
441	1790-05-09	\N	Ana	Douglas
442	1790-08-06	\N	Alan	Frazier
443	1790-03-17	\N	Stephen	Murphy
444	1790-05-23	\N	Jeffrey	Miller
445	1790-03-06	\N	Emily	Mooney
446	1790-12-28	\N	Justin	Palmer
447	1790-03-06	\N	Christy	Robbins
448	1790-06-13	\N	Joseph	Kennedy
449	1790-02-22	\N	Veronica	Waters
450	1790-01-03	\N	Benjamin	Blair
451	1790-07-08	\N	Amanda	Morgan
452	1790-08-23	\N	Nathaniel	Jackson
453	1790-03-15	\N	John	Hensley
454	1790-03-01	\N	Veronica	Hart
455	1790-06-09	\N	Jeremy	Snyder
456	1790-02-15	\N	Amanda	Lambert
457	1790-09-07	\N	Christopher	Stark
458	1790-11-28	\N	Daniel	Duran
459	1790-02-18	\N	Kevin	Mcconnell
460	1790-06-23	\N	Troy	Montes
461	1790-10-23	\N	Jose	Smith
462	1790-12-24	\N	Kevin	Kramer
463	1790-07-20	\N	Elizabeth	Carter
464	1790-08-01	\N	Anthony	Woods
465	1790-10-20	\N	Jennifer	Shaffer
466	1790-02-07	\N	Erika	Tran
467	1790-02-18	\N	Colleen	Hampton
468	1790-12-11	\N	Allison	Johnson
469	1790-03-27	\N	Donald	Mcguire
470	1790-05-01	\N	Elizabeth	Snyder
471	1790-08-07	\N	Nathan	Elliott
472	1790-04-11	\N	Ana	Ford
473	1790-08-10	\N	Matthew	Juarez
474	1790-11-18	\N	Monica	Stewart
475	1790-02-20	\N	Preston	Jensen
476	1790-09-24	\N	Valerie	Strickland
477	1790-12-17	\N	Amy	Murphy
478	1790-08-04	\N	Krista	Morgan
479	1790-11-01	\N	Samuel	Le
480	1790-02-24	\N	Sierra	Bentley
481	1790-10-23	\N	Wyatt	Nelson
482	1790-05-22	\N	Steven	Ramos
483	1790-09-04	\N	Jason	Peters
484	1790-08-08	\N	Frank	Sanchez
485	1790-10-04	\N	James	Sloan
486	1790-10-12	\N	Thomas	Anderson
487	1790-03-25	\N	Samuel	Cuevas
488	1790-09-22	\N	Ian	Hoffman
489	1790-09-19	\N	Derek	Blair
490	1790-08-02	\N	Alexandria	Richard
491	1790-05-28	\N	Craig	Blake
492	1790-11-18	\N	Jonathan	Alvarado
493	1790-02-20	\N	Steven	Miranda
494	1790-03-12	\N	Dennis	Wiggins
495	1790-08-07	\N	Elizabeth	Bailey
496	1790-02-01	\N	Cheryl	Henry
497	1790-02-12	\N	Jacqueline	Bailey
498	1790-06-24	\N	Ashley	Baker
499	1790-08-02	\N	Kenneth	Williams
500	1790-01-09	\N	Donald	Mejia
\.


--
-- Data for Name: pet_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.pet_passports (id, name, pet_owner, issuer, date_of_birth, species) FROM stdin;
0	Charlie	1	977	2006-12-26	Pogona vitticeps
1	Luna	2	1008	1982-09-25	Betta splendens
2	Charlie	5	67	1954-11-16	Eublepharis macularius
3	Bailey	6	39	1959-09-07	Mesocricetus auratus
4	Zoey	10	247	1932-10-28	Mesocricetus auratus
5	Chloe	11	839	1928-08-26	Psittacus erithacus
6	Charlie	14	426	1928-05-19	Chinchilla lanigera
7	Cooper	15	315	1932-09-01	Serinus canaria domestica
8	Chloe	22	861	1908-03-12	Pogona vitticeps
9	Toby	24	1208	1905-09-08	Rattus norvegicus domestica
10	Rocky	25	238	1904-02-12	Testudo hermanni
11	Chloe	26	152	1902-05-27	Carassius auratus
12	Lucy	33	436	1875-06-14	Chinchilla lanigera
13	Sadie	34	902	1884-09-22	Canis lupus familiaris
14	Lola	37	1100	1885-02-11	Nymphicus hollandicus
15	Zoey	38	969	1876-03-22	Acanthoscurria geniculata
16	Toby	41	401	1879-04-14	Testudo hermanni
17	Rocky	47	326	1882-01-02	Felis catus
18	Luna	52	468	1881-11-09	Oryctolagus cuniculus
19	Zoey	53	915	1876-03-11	Rattus norvegicus domestica
20	Toby	55	559	1885-11-04	Mesocricetus auratus
21	Buddy	60	1169	1875-09-24	Ctenosaura similis
22	Max	66	1156	1860-08-20	Serinus canaria domestica
23	Toby	72	1089	1852-03-15	Oryctolagus cuniculus
24	Luna	74	246	1860-01-12	Oryctolagus cuniculus
25	Cooper	75	763	1854-01-24	Testudo hermanni
26	Toby	76	837	1852-09-02	Python regius
27	Oliver	79	1168	1857-12-10	Felis catus
28	Cooper	81	1064	1853-09-22	Melopsittacus undulatus
29	Milo	82	118	1859-11-19	Oryctolagus cuniculus
30	Oliver	85	9	1850-03-13	Chinchilla lanigera
31	Milo	86	319	1850-01-26	Testudo hermanni
32	Molly	88	1189	1850-06-05	Betta splendens
33	Zoey	89	450	1858-07-14	Oryctolagus cuniculus
34	Daisy	91	623	1853-03-04	Acanthoscurria geniculata
35	Zoey	94	1093	1856-06-23	Rattus norvegicus domestica
36	Luna	100	565	1850-04-21	Cavia porcellus
37	Lola	101	554	1851-12-11	Cavia porcellus
38	Oliver	103	735	1851-09-15	Pogona vitticeps
39	Stella	105	332	1851-04-18	Pogona vitticeps
40	Sadie	110	386	1858-10-22	Melopsittacus undulatus
41	Oliver	122	851	1850-04-17	Testudo hermanni
42	Stella	124	918	1855-01-04	Chinchilla lanigera
43	Luna	125	843	1860-04-20	Felis catus
44	Bentley	131	360	1833-05-21	Psittacus erithacus
45	Bentley	132	771	1833-03-13	Testudo hermanni
46	Toby	139	11	1828-09-21	Python regius
47	Toby	140	841	1826-04-26	Felis catus
48	Buddy	144	2	1833-02-13	Chinchilla lanigera
49	Bella	149	98	1828-08-06	Serinus canaria domestica
50	Cooper	151	908	1826-06-19	Python regius
51	Stella	160	554	1831-05-05	Pogona vitticeps
52	Charlie	161	943	1827-07-23	Oryctolagus cuniculus
53	Bella	163	420	1827-02-11	Testudo hermanni
54	Lucy	164	1	1828-09-25	Pogona vitticeps
55	Daisy	167	156	1832-08-05	Serinus canaria domestica
56	Luna	170	815	1825-03-05	Testudo hermanni
57	Molly	172	361	1828-05-06	Mesocricetus auratus
58	Oliver	173	29	1835-03-17	Serinus canaria domestica
59	Chloe	174	555	1830-07-09	Mesocricetus auratus
60	Zoey	182	494	1825-08-10	Serinus canaria domestica
61	Bailey	184	506	1830-03-14	Rattus norvegicus domestica
62	Zoey	185	1131	1833-05-04	Betta splendens
63	Stella	186	132	1834-10-20	Oryctolagus cuniculus
64	Luna	188	226	1830-01-23	Serinus canaria domestica
65	Toby	191	1239	1826-04-25	Serinus canaria domestica
66	Rocky	193	653	1829-01-20	Serinus canaria domestica
67	Lola	195	1120	1826-10-18	Chinchilla lanigera
68	Daisy	196	453	1835-10-24	Rattus norvegicus domestica
69	Bella	203	928	1830-01-06	Canis lupus familiaris
70	Chloe	209	484	1830-06-19	Melopsittacus undulatus
71	Bella	210	127	1830-02-12	Mesocricetus auratus
72	Rocky	212	763	1830-06-13	Canis lupus familiaris
73	Milo	216	1085	1834-07-16	Serinus canaria domestica
74	Max	217	999	1834-04-18	Canis lupus familiaris
75	Lucy	220	410	1828-10-26	Eublepharis macularius
76	Bailey	222	768	1831-06-27	Melopsittacus undulatus
77	Bailey	226	1131	1833-12-15	Acanthoscurria geniculata
78	Sadie	236	539	1826-08-20	Mesocricetus auratus
79	Bailey	237	336	1826-06-14	Melopsittacus undulatus
80	Bella	238	192	1830-02-16	Melopsittacus undulatus
81	Bentley	239	1205	1829-11-03	Ctenosaura similis
82	Lola	240	592	1832-09-06	Mesocricetus auratus
83	Lucy	247	965	1826-05-01	Testudo hermanni
84	Sadie	254	914	1826-10-15	Felis catus
85	Milo	259	36	1802-11-03	Canis lupus familiaris
86	Daisy	261	264	1809-06-17	Nymphicus hollandicus
87	Sadie	267	607	1810-05-26	Rattus norvegicus domestica
88	Buddy	268	339	1810-01-19	Nymphicus hollandicus
89	Bailey	271	1215	1806-02-20	Carassius auratus
90	Luna	273	301	1801-09-14	Canis lupus familiaris
91	Oliver	274	23	1802-02-16	Serinus canaria domestica
92	Lola	275	1249	1800-03-03	Mesocricetus auratus
93	Oliver	277	1188	1803-10-05	Pogona vitticeps
94	Daisy	285	874	1806-10-08	Cavia porcellus
95	Bella	288	1033	1810-07-08	Betta splendens
96	Lucy	289	1098	1809-06-05	Python regius
97	Oliver	290	908	1805-07-20	Python regius
98	Zoey	292	15	1800-11-20	Mesocricetus auratus
99	Luna	298	635	1804-03-16	Ctenosaura similis
100	Chloe	299	667	1805-12-18	Psittacus erithacus
101	Oliver	301	80	1804-09-03	Melopsittacus undulatus
102	Molly	304	892	1806-02-21	Eublepharis macularius
103	Charlie	305	1177	1802-09-21	Chinchilla lanigera
104	Oliver	306	237	1810-07-01	Oryctolagus cuniculus
105	Stella	308	1032	1802-12-24	Canis lupus familiaris
106	Toby	310	757	1806-01-15	Rattus norvegicus domestica
107	Bentley	311	1110	1802-04-10	Chinchilla lanigera
108	Bailey	314	97	1807-09-02	Mesocricetus auratus
109	Chloe	318	852	1800-07-15	Pogona vitticeps
110	Chloe	319	109	1801-12-02	Pogona vitticeps
111	Luna	322	895	1805-02-18	Melopsittacus undulatus
112	Zoey	327	230	1810-04-05	Betta splendens
113	Stella	329	796	1807-08-07	Psittacus erithacus
114	Zoey	330	1132	1806-10-22	Testudo hermanni
115	Stella	333	474	1802-01-25	Felis catus
116	Milo	336	1087	1805-07-13	Canis lupus familiaris
117	Chloe	341	230	1810-08-08	Python regius
118	Charlie	342	9	1804-01-07	Pogona vitticeps
119	Luna	345	104	1804-10-01	Oryctolagus cuniculus
120	Molly	347	1083	1808-09-14	Eublepharis macularius
121	Toby	349	728	1809-09-06	Pogona vitticeps
122	Stella	350	1166	1801-02-07	Ctenosaura similis
123	Stella	351	1097	1804-05-10	Pogona vitticeps
124	Lucy	352	481	1806-01-28	Ctenosaura similis
125	Lola	355	282	1805-10-11	Ctenosaura similis
126	Chloe	356	1087	1806-07-13	Psittacus erithacus
127	Max	358	176	1805-08-02	Felis catus
128	Buddy	361	848	1804-05-13	Rattus norvegicus domestica
129	Bailey	362	536	1802-01-20	Chinchilla lanigera
130	Stella	370	608	1803-01-10	Cavia porcellus
131	Bentley	373	539	1804-03-17	Ctenosaura similis
132	Charlie	381	400	1809-10-03	Testudo hermanni
133	Chloe	382	553	1803-12-26	Betta splendens
134	Stella	384	444	1805-05-21	Serinus canaria domestica
135	Chloe	386	77	1802-09-07	Ctenosaura similis
136	Lucy	387	231	1801-01-28	Psittacus erithacus
137	Toby	388	405	1810-06-09	Melopsittacus undulatus
138	Bailey	389	947	1809-07-03	Felis catus
139	Milo	392	436	1803-10-21	Chinchilla lanigera
140	Lucy	395	415	1800-11-08	Canis lupus familiaris
141	Toby	399	646	1802-05-27	Eublepharis macularius
142	Stella	400	369	1802-12-07	Testudo hermanni
143	Charlie	402	352	1808-09-03	Chinchilla lanigera
144	Rocky	403	858	1806-10-02	Chinchilla lanigera
145	Bailey	407	29	1805-02-27	Cavia porcellus
146	Lucy	412	449	1809-05-01	Canis lupus familiaris
147	Bella	413	809	1803-07-11	Pogona vitticeps
148	Buddy	415	958	1809-01-12	Betta splendens
149	Luna	416	376	1800-08-06	Canis lupus familiaris
150	Luna	417	1176	1807-04-27	Felis catus
151	Buddy	418	636	1801-03-19	Nymphicus hollandicus
152	Cooper	419	973	1801-05-03	Chinchilla lanigera
153	Chloe	420	430	1801-12-04	Melopsittacus undulatus
154	Toby	429	608	1808-08-13	Mesocricetus auratus
155	Sadie	430	348	1810-04-15	Cavia porcellus
156	Rocky	438	526	1804-09-02	Pogona vitticeps
157	Stella	440	1018	1801-09-25	Betta splendens
158	Lola	445	1047	1810-05-07	Chinchilla lanigera
159	Molly	446	183	1803-03-14	Eublepharis macularius
160	Lola	447	145	1802-12-01	Cavia porcellus
161	Bailey	451	94	1806-01-11	Cavia porcellus
162	Zoey	452	1176	1808-07-02	Canis lupus familiaris
163	Zoey	455	854	1804-06-22	Rattus norvegicus domestica
164	Daisy	463	1110	1803-11-23	Betta splendens
165	Cooper	467	357	1802-09-10	Acanthoscurria geniculata
166	Max	468	1063	1802-03-14	Psittacus erithacus
167	Rocky	469	277	1806-07-02	Pogona vitticeps
168	Oliver	471	1051	1808-08-23	Carassius auratus
169	Charlie	474	346	1810-10-03	Serinus canaria domestica
170	Buddy	475	1108	1802-09-08	Carassius auratus
171	Cooper	477	192	1805-05-12	Ctenosaura similis
172	Bella	478	945	1802-01-05	Mesocricetus auratus
173	Chloe	479	273	1801-06-03	Nymphicus hollandicus
174	Daisy	482	308	1801-06-27	Ctenosaura similis
175	Cooper	483	678	1805-02-01	Eublepharis macularius
176	Bailey	484	449	1801-09-10	Melopsittacus undulatus
177	Luna	498	1213	1805-11-15	Pogona vitticeps
178	Toby	500	199	1801-04-05	Mesocricetus auratus
\.


--
-- Data for Name: visa_categories; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visa_categories (type, description, working_permit, residence_permit, duration, country) FROM stdin;
1	Tourist Visas	f	f	10 years	Afghanistan
2	Business Visas	t	f	9 years	Afghanistan
3	Work Visas	t	f	6 years	Afghanistan
4	Student Visas	t	f	5 years	Afghanistan
5	Transit Visas	f	f	8 years	Afghanistan
6	Family and Dependent Visas	t	f	6 years	Afghanistan
7	Immigrant Visas	t	t	8 years	Afghanistan
8	Refugee and Asylum Visas	t	f	9 years	Afghanistan
9	Special Purpose Visas	t	f	9 years	Afghanistan
1	Tourist Visas	f	f	6 years	Albania
2	Business Visas	t	f	8 years	Albania
3	Work Visas	t	f	9 years	Albania
4	Student Visas	t	f	6 years	Albania
5	Transit Visas	f	f	8 years	Albania
6	Family and Dependent Visas	t	f	9 years	Albania
7	Immigrant Visas	t	t	7 years	Albania
8	Refugee and Asylum Visas	t	f	7 years	Albania
9	Special Purpose Visas	t	f	6 years	Albania
1	Tourist Visas	f	f	6 years	Algeria
2	Business Visas	t	f	7 years	Algeria
3	Work Visas	t	f	5 years	Algeria
4	Student Visas	t	f	8 years	Algeria
5	Transit Visas	f	f	5 years	Algeria
6	Family and Dependent Visas	t	f	10 years	Algeria
7	Immigrant Visas	t	t	9 years	Algeria
8	Refugee and Asylum Visas	t	f	6 years	Algeria
9	Special Purpose Visas	t	f	6 years	Algeria
1	Tourist Visas	f	f	8 years	Angola
2	Business Visas	t	f	5 years	Angola
3	Work Visas	t	f	5 years	Angola
4	Student Visas	t	f	5 years	Angola
5	Transit Visas	f	f	7 years	Angola
6	Family and Dependent Visas	t	f	9 years	Angola
7	Immigrant Visas	t	t	10 years	Angola
8	Refugee and Asylum Visas	t	f	9 years	Angola
9	Special Purpose Visas	t	f	7 years	Angola
1	Tourist Visas	f	f	9 years	Argentina
2	Business Visas	t	f	9 years	Argentina
3	Work Visas	t	f	5 years	Argentina
4	Student Visas	t	f	7 years	Argentina
5	Transit Visas	f	f	10 years	Argentina
6	Family and Dependent Visas	t	f	9 years	Argentina
7	Immigrant Visas	t	t	5 years	Argentina
8	Refugee and Asylum Visas	t	f	5 years	Argentina
9	Special Purpose Visas	t	f	9 years	Argentina
1	Tourist Visas	f	f	7 years	Armenia
2	Business Visas	t	f	5 years	Armenia
3	Work Visas	t	f	8 years	Armenia
4	Student Visas	t	f	7 years	Armenia
5	Transit Visas	f	f	7 years	Armenia
6	Family and Dependent Visas	t	f	7 years	Armenia
7	Immigrant Visas	t	t	5 years	Armenia
8	Refugee and Asylum Visas	t	f	10 years	Armenia
9	Special Purpose Visas	t	f	6 years	Armenia
1	Tourist Visas	f	f	9 years	Aruba
2	Business Visas	t	f	9 years	Aruba
3	Work Visas	t	f	8 years	Aruba
4	Student Visas	t	f	5 years	Aruba
5	Transit Visas	f	f	6 years	Aruba
6	Family and Dependent Visas	t	f	7 years	Aruba
7	Immigrant Visas	t	t	10 years	Aruba
8	Refugee and Asylum Visas	t	f	5 years	Aruba
9	Special Purpose Visas	t	f	8 years	Aruba
1	Tourist Visas	f	f	10 years	Australia
2	Business Visas	t	f	8 years	Australia
3	Work Visas	t	f	10 years	Australia
4	Student Visas	t	f	7 years	Australia
5	Transit Visas	f	f	9 years	Australia
6	Family and Dependent Visas	t	f	5 years	Australia
7	Immigrant Visas	t	t	5 years	Australia
8	Refugee and Asylum Visas	t	f	7 years	Australia
9	Special Purpose Visas	t	f	10 years	Australia
1	Tourist Visas	f	f	5 years	Austria
2	Business Visas	t	f	10 years	Austria
3	Work Visas	t	f	10 years	Austria
4	Student Visas	t	f	7 years	Austria
5	Transit Visas	f	f	10 years	Austria
6	Family and Dependent Visas	t	f	8 years	Austria
7	Immigrant Visas	t	t	6 years	Austria
8	Refugee and Asylum Visas	t	f	6 years	Austria
9	Special Purpose Visas	t	f	7 years	Austria
1	Tourist Visas	f	f	7 years	Azerbaijan
2	Business Visas	t	f	6 years	Azerbaijan
3	Work Visas	t	f	9 years	Azerbaijan
4	Student Visas	t	f	5 years	Azerbaijan
5	Transit Visas	f	f	6 years	Azerbaijan
6	Family and Dependent Visas	t	f	9 years	Azerbaijan
7	Immigrant Visas	t	t	9 years	Azerbaijan
8	Refugee and Asylum Visas	t	f	7 years	Azerbaijan
9	Special Purpose Visas	t	f	10 years	Azerbaijan
1	Tourist Visas	f	f	9 years	Bahamas
2	Business Visas	t	f	9 years	Bahamas
3	Work Visas	t	f	6 years	Bahamas
4	Student Visas	t	f	5 years	Bahamas
5	Transit Visas	f	f	8 years	Bahamas
6	Family and Dependent Visas	t	f	5 years	Bahamas
7	Immigrant Visas	t	t	7 years	Bahamas
8	Refugee and Asylum Visas	t	f	10 years	Bahamas
9	Special Purpose Visas	t	f	7 years	Bahamas
1	Tourist Visas	f	f	8 years	Bahrain
2	Business Visas	t	f	5 years	Bahrain
3	Work Visas	t	f	10 years	Bahrain
4	Student Visas	t	f	5 years	Bahrain
5	Transit Visas	f	f	6 years	Bahrain
6	Family and Dependent Visas	t	f	10 years	Bahrain
7	Immigrant Visas	t	t	7 years	Bahrain
8	Refugee and Asylum Visas	t	f	7 years	Bahrain
9	Special Purpose Visas	t	f	5 years	Bahrain
1	Tourist Visas	f	f	5 years	Bangladesh
2	Business Visas	t	f	9 years	Bangladesh
3	Work Visas	t	f	7 years	Bangladesh
4	Student Visas	t	f	5 years	Bangladesh
5	Transit Visas	f	f	9 years	Bangladesh
6	Family and Dependent Visas	t	f	10 years	Bangladesh
7	Immigrant Visas	t	t	9 years	Bangladesh
8	Refugee and Asylum Visas	t	f	6 years	Bangladesh
9	Special Purpose Visas	t	f	9 years	Bangladesh
1	Tourist Visas	f	f	10 years	Barbados
2	Business Visas	t	f	8 years	Barbados
3	Work Visas	t	f	8 years	Barbados
4	Student Visas	t	f	5 years	Barbados
5	Transit Visas	f	f	5 years	Barbados
6	Family and Dependent Visas	t	f	6 years	Barbados
7	Immigrant Visas	t	t	7 years	Barbados
8	Refugee and Asylum Visas	t	f	9 years	Barbados
9	Special Purpose Visas	t	f	5 years	Barbados
1	Tourist Visas	f	f	9 years	Belarus
2	Business Visas	t	f	9 years	Belarus
3	Work Visas	t	f	9 years	Belarus
4	Student Visas	t	f	9 years	Belarus
5	Transit Visas	f	f	7 years	Belarus
6	Family and Dependent Visas	t	f	5 years	Belarus
7	Immigrant Visas	t	t	10 years	Belarus
8	Refugee and Asylum Visas	t	f	8 years	Belarus
9	Special Purpose Visas	t	f	7 years	Belarus
1	Tourist Visas	f	f	8 years	Belgium
2	Business Visas	t	f	5 years	Belgium
3	Work Visas	t	f	10 years	Belgium
4	Student Visas	t	f	5 years	Belgium
5	Transit Visas	f	f	9 years	Belgium
6	Family and Dependent Visas	t	f	5 years	Belgium
7	Immigrant Visas	t	t	7 years	Belgium
8	Refugee and Asylum Visas	t	f	8 years	Belgium
9	Special Purpose Visas	t	f	5 years	Belgium
1	Tourist Visas	f	f	9 years	Belize
2	Business Visas	t	f	10 years	Belize
3	Work Visas	t	f	6 years	Belize
4	Student Visas	t	f	10 years	Belize
5	Transit Visas	f	f	10 years	Belize
6	Family and Dependent Visas	t	f	7 years	Belize
7	Immigrant Visas	t	t	5 years	Belize
8	Refugee and Asylum Visas	t	f	8 years	Belize
9	Special Purpose Visas	t	f	6 years	Belize
1	Tourist Visas	f	f	5 years	Benin
2	Business Visas	t	f	10 years	Benin
3	Work Visas	t	f	5 years	Benin
4	Student Visas	t	f	7 years	Benin
5	Transit Visas	f	f	5 years	Benin
6	Family and Dependent Visas	t	f	10 years	Benin
7	Immigrant Visas	t	t	5 years	Benin
8	Refugee and Asylum Visas	t	f	10 years	Benin
9	Special Purpose Visas	t	f	6 years	Benin
1	Tourist Visas	f	f	6 years	Bermuda
2	Business Visas	t	f	7 years	Bermuda
3	Work Visas	t	f	5 years	Bermuda
4	Student Visas	t	f	6 years	Bermuda
5	Transit Visas	f	f	10 years	Bermuda
6	Family and Dependent Visas	t	f	6 years	Bermuda
7	Immigrant Visas	t	t	8 years	Bermuda
8	Refugee and Asylum Visas	t	f	5 years	Bermuda
9	Special Purpose Visas	t	f	5 years	Bermuda
1	Tourist Visas	f	f	8 years	Bhutan
2	Business Visas	t	f	6 years	Bhutan
3	Work Visas	t	f	8 years	Bhutan
4	Student Visas	t	f	8 years	Bhutan
5	Transit Visas	f	f	8 years	Bhutan
6	Family and Dependent Visas	t	f	5 years	Bhutan
7	Immigrant Visas	t	t	5 years	Bhutan
8	Refugee and Asylum Visas	t	f	7 years	Bhutan
9	Special Purpose Visas	t	f	9 years	Bhutan
1	Tourist Visas	f	f	7 years	Bolivia
2	Business Visas	t	f	6 years	Bolivia
3	Work Visas	t	f	8 years	Bolivia
4	Student Visas	t	f	7 years	Bolivia
5	Transit Visas	f	f	5 years	Bolivia
6	Family and Dependent Visas	t	f	8 years	Bolivia
7	Immigrant Visas	t	t	8 years	Bolivia
8	Refugee and Asylum Visas	t	f	7 years	Bolivia
9	Special Purpose Visas	t	f	6 years	Bolivia
1	Tourist Visas	f	f	6 years	Botswana
2	Business Visas	t	f	6 years	Botswana
3	Work Visas	t	f	10 years	Botswana
4	Student Visas	t	f	8 years	Botswana
5	Transit Visas	f	f	9 years	Botswana
6	Family and Dependent Visas	t	f	5 years	Botswana
7	Immigrant Visas	t	t	8 years	Botswana
8	Refugee and Asylum Visas	t	f	5 years	Botswana
9	Special Purpose Visas	t	f	5 years	Botswana
1	Tourist Visas	f	f	9 years	Brazil
2	Business Visas	t	f	5 years	Brazil
3	Work Visas	t	f	8 years	Brazil
4	Student Visas	t	f	9 years	Brazil
5	Transit Visas	f	f	7 years	Brazil
6	Family and Dependent Visas	t	f	5 years	Brazil
7	Immigrant Visas	t	t	9 years	Brazil
8	Refugee and Asylum Visas	t	f	10 years	Brazil
9	Special Purpose Visas	t	f	8 years	Brazil
1	Tourist Visas	f	f	5 years	Brunei
2	Business Visas	t	f	9 years	Brunei
3	Work Visas	t	f	6 years	Brunei
4	Student Visas	t	f	10 years	Brunei
5	Transit Visas	f	f	7 years	Brunei
6	Family and Dependent Visas	t	f	10 years	Brunei
7	Immigrant Visas	t	t	7 years	Brunei
8	Refugee and Asylum Visas	t	f	8 years	Brunei
9	Special Purpose Visas	t	f	9 years	Brunei
1	Tourist Visas	f	f	9 years	Bulgaria
2	Business Visas	t	f	7 years	Bulgaria
3	Work Visas	t	f	10 years	Bulgaria
4	Student Visas	t	f	7 years	Bulgaria
5	Transit Visas	f	f	5 years	Bulgaria
6	Family and Dependent Visas	t	f	9 years	Bulgaria
7	Immigrant Visas	t	t	7 years	Bulgaria
8	Refugee and Asylum Visas	t	f	9 years	Bulgaria
9	Special Purpose Visas	t	f	10 years	Bulgaria
1	Tourist Visas	f	f	5 years	Burundi
2	Business Visas	t	f	7 years	Burundi
3	Work Visas	t	f	6 years	Burundi
4	Student Visas	t	f	7 years	Burundi
5	Transit Visas	f	f	9 years	Burundi
6	Family and Dependent Visas	t	f	6 years	Burundi
7	Immigrant Visas	t	t	6 years	Burundi
8	Refugee and Asylum Visas	t	f	10 years	Burundi
9	Special Purpose Visas	t	f	8 years	Burundi
1	Tourist Visas	f	f	5 years	Cambodia
2	Business Visas	t	f	8 years	Cambodia
3	Work Visas	t	f	8 years	Cambodia
4	Student Visas	t	f	6 years	Cambodia
5	Transit Visas	f	f	7 years	Cambodia
6	Family and Dependent Visas	t	f	5 years	Cambodia
7	Immigrant Visas	t	t	10 years	Cambodia
8	Refugee and Asylum Visas	t	f	7 years	Cambodia
9	Special Purpose Visas	t	f	8 years	Cambodia
1	Tourist Visas	f	f	8 years	Cameroon
2	Business Visas	t	f	9 years	Cameroon
3	Work Visas	t	f	8 years	Cameroon
4	Student Visas	t	f	10 years	Cameroon
5	Transit Visas	f	f	10 years	Cameroon
6	Family and Dependent Visas	t	f	6 years	Cameroon
7	Immigrant Visas	t	t	8 years	Cameroon
8	Refugee and Asylum Visas	t	f	6 years	Cameroon
9	Special Purpose Visas	t	f	6 years	Cameroon
1	Tourist Visas	f	f	5 years	Canada
2	Business Visas	t	f	7 years	Canada
3	Work Visas	t	f	10 years	Canada
4	Student Visas	t	f	10 years	Canada
5	Transit Visas	f	f	5 years	Canada
6	Family and Dependent Visas	t	f	8 years	Canada
7	Immigrant Visas	t	t	9 years	Canada
8	Refugee and Asylum Visas	t	f	9 years	Canada
9	Special Purpose Visas	t	f	9 years	Canada
1	Tourist Visas	f	f	8 years	Chad
2	Business Visas	t	f	5 years	Chad
3	Work Visas	t	f	10 years	Chad
4	Student Visas	t	f	9 years	Chad
5	Transit Visas	f	f	10 years	Chad
6	Family and Dependent Visas	t	f	9 years	Chad
7	Immigrant Visas	t	t	7 years	Chad
8	Refugee and Asylum Visas	t	f	6 years	Chad
9	Special Purpose Visas	t	f	10 years	Chad
1	Tourist Visas	f	f	8 years	Chile
2	Business Visas	t	f	8 years	Chile
3	Work Visas	t	f	5 years	Chile
4	Student Visas	t	f	10 years	Chile
5	Transit Visas	f	f	9 years	Chile
6	Family and Dependent Visas	t	f	7 years	Chile
7	Immigrant Visas	t	t	10 years	Chile
8	Refugee and Asylum Visas	t	f	9 years	Chile
9	Special Purpose Visas	t	f	9 years	Chile
1	Tourist Visas	f	f	7 years	China
2	Business Visas	t	f	6 years	China
3	Work Visas	t	f	8 years	China
4	Student Visas	t	f	10 years	China
5	Transit Visas	f	f	9 years	China
6	Family and Dependent Visas	t	f	7 years	China
7	Immigrant Visas	t	t	8 years	China
8	Refugee and Asylum Visas	t	f	9 years	China
9	Special Purpose Visas	t	f	7 years	China
1	Tourist Visas	f	f	6 years	Colombia
2	Business Visas	t	f	6 years	Colombia
3	Work Visas	t	f	5 years	Colombia
4	Student Visas	t	f	7 years	Colombia
5	Transit Visas	f	f	9 years	Colombia
6	Family and Dependent Visas	t	f	9 years	Colombia
7	Immigrant Visas	t	t	6 years	Colombia
8	Refugee and Asylum Visas	t	f	6 years	Colombia
9	Special Purpose Visas	t	f	5 years	Colombia
1	Tourist Visas	f	f	7 years	Comoros
2	Business Visas	t	f	8 years	Comoros
3	Work Visas	t	f	10 years	Comoros
4	Student Visas	t	f	8 years	Comoros
5	Transit Visas	f	f	7 years	Comoros
6	Family and Dependent Visas	t	f	5 years	Comoros
7	Immigrant Visas	t	t	9 years	Comoros
8	Refugee and Asylum Visas	t	f	7 years	Comoros
9	Special Purpose Visas	t	f	10 years	Comoros
1	Tourist Visas	f	f	9 years	Croatia
2	Business Visas	t	f	8 years	Croatia
3	Work Visas	t	f	8 years	Croatia
4	Student Visas	t	f	5 years	Croatia
5	Transit Visas	f	f	8 years	Croatia
6	Family and Dependent Visas	t	f	7 years	Croatia
7	Immigrant Visas	t	t	8 years	Croatia
8	Refugee and Asylum Visas	t	f	5 years	Croatia
9	Special Purpose Visas	t	f	8 years	Croatia
1	Tourist Visas	f	f	8 years	Cuba
2	Business Visas	t	f	6 years	Cuba
3	Work Visas	t	f	10 years	Cuba
4	Student Visas	t	f	10 years	Cuba
5	Transit Visas	f	f	5 years	Cuba
6	Family and Dependent Visas	t	f	8 years	Cuba
7	Immigrant Visas	t	t	9 years	Cuba
8	Refugee and Asylum Visas	t	f	9 years	Cuba
9	Special Purpose Visas	t	f	5 years	Cuba
1	Tourist Visas	f	f	8 years	Curacao
2	Business Visas	t	f	9 years	Curacao
3	Work Visas	t	f	5 years	Curacao
4	Student Visas	t	f	5 years	Curacao
5	Transit Visas	f	f	8 years	Curacao
6	Family and Dependent Visas	t	f	6 years	Curacao
7	Immigrant Visas	t	t	6 years	Curacao
8	Refugee and Asylum Visas	t	f	10 years	Curacao
9	Special Purpose Visas	t	f	9 years	Curacao
1	Tourist Visas	f	f	5 years	Cyprus
2	Business Visas	t	f	9 years	Cyprus
3	Work Visas	t	f	5 years	Cyprus
4	Student Visas	t	f	9 years	Cyprus
5	Transit Visas	f	f	7 years	Cyprus
6	Family and Dependent Visas	t	f	6 years	Cyprus
7	Immigrant Visas	t	t	9 years	Cyprus
8	Refugee and Asylum Visas	t	f	5 years	Cyprus
9	Special Purpose Visas	t	f	6 years	Cyprus
1	Tourist Visas	f	f	6 years	Denmark
2	Business Visas	t	f	10 years	Denmark
3	Work Visas	t	f	10 years	Denmark
4	Student Visas	t	f	5 years	Denmark
5	Transit Visas	f	f	7 years	Denmark
6	Family and Dependent Visas	t	f	10 years	Denmark
7	Immigrant Visas	t	t	8 years	Denmark
8	Refugee and Asylum Visas	t	f	6 years	Denmark
9	Special Purpose Visas	t	f	7 years	Denmark
1	Tourist Visas	f	f	5 years	Djibouti
2	Business Visas	t	f	10 years	Djibouti
3	Work Visas	t	f	7 years	Djibouti
4	Student Visas	t	f	5 years	Djibouti
5	Transit Visas	f	f	5 years	Djibouti
6	Family and Dependent Visas	t	f	7 years	Djibouti
7	Immigrant Visas	t	t	9 years	Djibouti
8	Refugee and Asylum Visas	t	f	10 years	Djibouti
9	Special Purpose Visas	t	f	9 years	Djibouti
1	Tourist Visas	f	f	5 years	Dominica
2	Business Visas	t	f	9 years	Dominica
3	Work Visas	t	f	6 years	Dominica
4	Student Visas	t	f	8 years	Dominica
5	Transit Visas	f	f	8 years	Dominica
6	Family and Dependent Visas	t	f	6 years	Dominica
7	Immigrant Visas	t	t	9 years	Dominica
8	Refugee and Asylum Visas	t	f	7 years	Dominica
9	Special Purpose Visas	t	f	6 years	Dominica
1	Tourist Visas	f	f	5 years	Ecuador
2	Business Visas	t	f	7 years	Ecuador
3	Work Visas	t	f	9 years	Ecuador
4	Student Visas	t	f	5 years	Ecuador
5	Transit Visas	f	f	8 years	Ecuador
6	Family and Dependent Visas	t	f	8 years	Ecuador
7	Immigrant Visas	t	t	7 years	Ecuador
8	Refugee and Asylum Visas	t	f	9 years	Ecuador
9	Special Purpose Visas	t	f	6 years	Ecuador
1	Tourist Visas	f	f	7 years	Egypt
2	Business Visas	t	f	9 years	Egypt
3	Work Visas	t	f	6 years	Egypt
4	Student Visas	t	f	6 years	Egypt
5	Transit Visas	f	f	5 years	Egypt
6	Family and Dependent Visas	t	f	8 years	Egypt
7	Immigrant Visas	t	t	6 years	Egypt
8	Refugee and Asylum Visas	t	f	5 years	Egypt
9	Special Purpose Visas	t	f	9 years	Egypt
1	Tourist Visas	f	f	6 years	Eritrea
2	Business Visas	t	f	9 years	Eritrea
3	Work Visas	t	f	6 years	Eritrea
4	Student Visas	t	f	5 years	Eritrea
5	Transit Visas	f	f	6 years	Eritrea
6	Family and Dependent Visas	t	f	9 years	Eritrea
7	Immigrant Visas	t	t	5 years	Eritrea
8	Refugee and Asylum Visas	t	f	10 years	Eritrea
9	Special Purpose Visas	t	f	5 years	Eritrea
1	Tourist Visas	f	f	6 years	Estonia
2	Business Visas	t	f	6 years	Estonia
3	Work Visas	t	f	9 years	Estonia
4	Student Visas	t	f	10 years	Estonia
5	Transit Visas	f	f	6 years	Estonia
6	Family and Dependent Visas	t	f	6 years	Estonia
7	Immigrant Visas	t	t	5 years	Estonia
8	Refugee and Asylum Visas	t	f	9 years	Estonia
9	Special Purpose Visas	t	f	5 years	Estonia
1	Tourist Visas	f	f	10 years	Ethiopia
2	Business Visas	t	f	9 years	Ethiopia
3	Work Visas	t	f	6 years	Ethiopia
4	Student Visas	t	f	8 years	Ethiopia
5	Transit Visas	f	f	6 years	Ethiopia
6	Family and Dependent Visas	t	f	7 years	Ethiopia
7	Immigrant Visas	t	t	10 years	Ethiopia
8	Refugee and Asylum Visas	t	f	7 years	Ethiopia
9	Special Purpose Visas	t	f	7 years	Ethiopia
1	Tourist Visas	f	f	8 years	Fiji
2	Business Visas	t	f	9 years	Fiji
3	Work Visas	t	f	8 years	Fiji
4	Student Visas	t	f	9 years	Fiji
5	Transit Visas	f	f	10 years	Fiji
6	Family and Dependent Visas	t	f	5 years	Fiji
7	Immigrant Visas	t	t	7 years	Fiji
8	Refugee and Asylum Visas	t	f	10 years	Fiji
9	Special Purpose Visas	t	f	10 years	Fiji
1	Tourist Visas	f	f	6 years	Finland
2	Business Visas	t	f	5 years	Finland
3	Work Visas	t	f	10 years	Finland
4	Student Visas	t	f	8 years	Finland
5	Transit Visas	f	f	7 years	Finland
6	Family and Dependent Visas	t	f	10 years	Finland
7	Immigrant Visas	t	t	7 years	Finland
8	Refugee and Asylum Visas	t	f	9 years	Finland
9	Special Purpose Visas	t	f	8 years	Finland
1	Tourist Visas	f	f	7 years	France
2	Business Visas	t	f	8 years	France
3	Work Visas	t	f	7 years	France
4	Student Visas	t	f	6 years	France
5	Transit Visas	f	f	8 years	France
6	Family and Dependent Visas	t	f	9 years	France
7	Immigrant Visas	t	t	6 years	France
8	Refugee and Asylum Visas	t	f	6 years	France
9	Special Purpose Visas	t	f	10 years	France
1	Tourist Visas	f	f	9 years	Gabon
2	Business Visas	t	f	9 years	Gabon
3	Work Visas	t	f	9 years	Gabon
4	Student Visas	t	f	9 years	Gabon
5	Transit Visas	f	f	5 years	Gabon
6	Family and Dependent Visas	t	f	5 years	Gabon
7	Immigrant Visas	t	t	5 years	Gabon
8	Refugee and Asylum Visas	t	f	6 years	Gabon
9	Special Purpose Visas	t	f	8 years	Gabon
1	Tourist Visas	f	f	6 years	Gambia
2	Business Visas	t	f	8 years	Gambia
3	Work Visas	t	f	7 years	Gambia
4	Student Visas	t	f	9 years	Gambia
5	Transit Visas	f	f	8 years	Gambia
6	Family and Dependent Visas	t	f	5 years	Gambia
7	Immigrant Visas	t	t	8 years	Gambia
8	Refugee and Asylum Visas	t	f	7 years	Gambia
9	Special Purpose Visas	t	f	9 years	Gambia
1	Tourist Visas	f	f	7 years	Georgia
2	Business Visas	t	f	5 years	Georgia
3	Work Visas	t	f	7 years	Georgia
4	Student Visas	t	f	9 years	Georgia
5	Transit Visas	f	f	8 years	Georgia
6	Family and Dependent Visas	t	f	6 years	Georgia
7	Immigrant Visas	t	t	8 years	Georgia
8	Refugee and Asylum Visas	t	f	9 years	Georgia
9	Special Purpose Visas	t	f	9 years	Georgia
1	Tourist Visas	f	f	6 years	Germany
2	Business Visas	t	f	6 years	Germany
3	Work Visas	t	f	10 years	Germany
4	Student Visas	t	f	6 years	Germany
5	Transit Visas	f	f	7 years	Germany
6	Family and Dependent Visas	t	f	7 years	Germany
7	Immigrant Visas	t	t	5 years	Germany
8	Refugee and Asylum Visas	t	f	5 years	Germany
9	Special Purpose Visas	t	f	5 years	Germany
1	Tourist Visas	f	f	10 years	Ghana
2	Business Visas	t	f	6 years	Ghana
3	Work Visas	t	f	7 years	Ghana
4	Student Visas	t	f	10 years	Ghana
5	Transit Visas	f	f	5 years	Ghana
6	Family and Dependent Visas	t	f	7 years	Ghana
7	Immigrant Visas	t	t	10 years	Ghana
8	Refugee and Asylum Visas	t	f	10 years	Ghana
9	Special Purpose Visas	t	f	10 years	Ghana
1	Tourist Visas	f	f	5 years	Gibraltar
2	Business Visas	t	f	8 years	Gibraltar
3	Work Visas	t	f	6 years	Gibraltar
4	Student Visas	t	f	8 years	Gibraltar
5	Transit Visas	f	f	6 years	Gibraltar
6	Family and Dependent Visas	t	f	5 years	Gibraltar
7	Immigrant Visas	t	t	5 years	Gibraltar
8	Refugee and Asylum Visas	t	f	5 years	Gibraltar
9	Special Purpose Visas	t	f	10 years	Gibraltar
1	Tourist Visas	f	f	9 years	Greece
2	Business Visas	t	f	9 years	Greece
3	Work Visas	t	f	10 years	Greece
4	Student Visas	t	f	7 years	Greece
5	Transit Visas	f	f	7 years	Greece
6	Family and Dependent Visas	t	f	10 years	Greece
7	Immigrant Visas	t	t	8 years	Greece
8	Refugee and Asylum Visas	t	f	10 years	Greece
9	Special Purpose Visas	t	f	8 years	Greece
1	Tourist Visas	f	f	7 years	Greenland
2	Business Visas	t	f	6 years	Greenland
3	Work Visas	t	f	8 years	Greenland
4	Student Visas	t	f	5 years	Greenland
5	Transit Visas	f	f	6 years	Greenland
6	Family and Dependent Visas	t	f	9 years	Greenland
7	Immigrant Visas	t	t	7 years	Greenland
8	Refugee and Asylum Visas	t	f	6 years	Greenland
9	Special Purpose Visas	t	f	7 years	Greenland
1	Tourist Visas	f	f	9 years	Guatemala
2	Business Visas	t	f	7 years	Guatemala
3	Work Visas	t	f	5 years	Guatemala
4	Student Visas	t	f	10 years	Guatemala
5	Transit Visas	f	f	6 years	Guatemala
6	Family and Dependent Visas	t	f	7 years	Guatemala
7	Immigrant Visas	t	t	5 years	Guatemala
8	Refugee and Asylum Visas	t	f	10 years	Guatemala
9	Special Purpose Visas	t	f	5 years	Guatemala
1	Tourist Visas	f	f	5 years	Guinea
2	Business Visas	t	f	5 years	Guinea
3	Work Visas	t	f	6 years	Guinea
4	Student Visas	t	f	10 years	Guinea
5	Transit Visas	f	f	6 years	Guinea
6	Family and Dependent Visas	t	f	9 years	Guinea
7	Immigrant Visas	t	t	10 years	Guinea
8	Refugee and Asylum Visas	t	f	7 years	Guinea
9	Special Purpose Visas	t	f	9 years	Guinea
1	Tourist Visas	f	f	7 years	Guyana
2	Business Visas	t	f	8 years	Guyana
3	Work Visas	t	f	6 years	Guyana
4	Student Visas	t	f	6 years	Guyana
5	Transit Visas	f	f	10 years	Guyana
6	Family and Dependent Visas	t	f	7 years	Guyana
7	Immigrant Visas	t	t	9 years	Guyana
8	Refugee and Asylum Visas	t	f	6 years	Guyana
9	Special Purpose Visas	t	f	8 years	Guyana
1	Tourist Visas	f	f	5 years	Haiti
2	Business Visas	t	f	8 years	Haiti
3	Work Visas	t	f	7 years	Haiti
4	Student Visas	t	f	5 years	Haiti
5	Transit Visas	f	f	8 years	Haiti
6	Family and Dependent Visas	t	f	8 years	Haiti
7	Immigrant Visas	t	t	8 years	Haiti
8	Refugee and Asylum Visas	t	f	5 years	Haiti
9	Special Purpose Visas	t	f	6 years	Haiti
1	Tourist Visas	f	f	7 years	Honduras
2	Business Visas	t	f	7 years	Honduras
3	Work Visas	t	f	5 years	Honduras
4	Student Visas	t	f	6 years	Honduras
5	Transit Visas	f	f	10 years	Honduras
6	Family and Dependent Visas	t	f	5 years	Honduras
7	Immigrant Visas	t	t	7 years	Honduras
8	Refugee and Asylum Visas	t	f	5 years	Honduras
9	Special Purpose Visas	t	f	9 years	Honduras
1	Tourist Visas	f	f	6 years	Hungary
2	Business Visas	t	f	5 years	Hungary
3	Work Visas	t	f	6 years	Hungary
4	Student Visas	t	f	5 years	Hungary
5	Transit Visas	f	f	6 years	Hungary
6	Family and Dependent Visas	t	f	6 years	Hungary
7	Immigrant Visas	t	t	6 years	Hungary
8	Refugee and Asylum Visas	t	f	8 years	Hungary
9	Special Purpose Visas	t	f	10 years	Hungary
1	Tourist Visas	f	f	7 years	Iceland
2	Business Visas	t	f	9 years	Iceland
3	Work Visas	t	f	5 years	Iceland
4	Student Visas	t	f	6 years	Iceland
5	Transit Visas	f	f	9 years	Iceland
6	Family and Dependent Visas	t	f	5 years	Iceland
7	Immigrant Visas	t	t	5 years	Iceland
8	Refugee and Asylum Visas	t	f	9 years	Iceland
9	Special Purpose Visas	t	f	7 years	Iceland
1	Tourist Visas	f	f	8 years	India
2	Business Visas	t	f	9 years	India
3	Work Visas	t	f	6 years	India
4	Student Visas	t	f	5 years	India
5	Transit Visas	f	f	10 years	India
6	Family and Dependent Visas	t	f	5 years	India
7	Immigrant Visas	t	t	8 years	India
8	Refugee and Asylum Visas	t	f	6 years	India
9	Special Purpose Visas	t	f	6 years	India
1	Tourist Visas	f	f	8 years	Indonesia
2	Business Visas	t	f	7 years	Indonesia
3	Work Visas	t	f	10 years	Indonesia
4	Student Visas	t	f	6 years	Indonesia
5	Transit Visas	f	f	6 years	Indonesia
6	Family and Dependent Visas	t	f	5 years	Indonesia
7	Immigrant Visas	t	t	10 years	Indonesia
8	Refugee and Asylum Visas	t	f	6 years	Indonesia
9	Special Purpose Visas	t	f	6 years	Indonesia
1	Tourist Visas	f	f	9 years	Iran
2	Business Visas	t	f	10 years	Iran
3	Work Visas	t	f	8 years	Iran
4	Student Visas	t	f	6 years	Iran
5	Transit Visas	f	f	7 years	Iran
6	Family and Dependent Visas	t	f	8 years	Iran
7	Immigrant Visas	t	t	9 years	Iran
8	Refugee and Asylum Visas	t	f	7 years	Iran
9	Special Purpose Visas	t	f	7 years	Iran
1	Tourist Visas	f	f	5 years	Iraq
2	Business Visas	t	f	5 years	Iraq
3	Work Visas	t	f	9 years	Iraq
4	Student Visas	t	f	7 years	Iraq
5	Transit Visas	f	f	8 years	Iraq
6	Family and Dependent Visas	t	f	8 years	Iraq
7	Immigrant Visas	t	t	5 years	Iraq
8	Refugee and Asylum Visas	t	f	10 years	Iraq
9	Special Purpose Visas	t	f	9 years	Iraq
1	Tourist Visas	f	f	7 years	Ireland
2	Business Visas	t	f	6 years	Ireland
3	Work Visas	t	f	7 years	Ireland
4	Student Visas	t	f	7 years	Ireland
5	Transit Visas	f	f	6 years	Ireland
6	Family and Dependent Visas	t	f	5 years	Ireland
7	Immigrant Visas	t	t	5 years	Ireland
8	Refugee and Asylum Visas	t	f	10 years	Ireland
9	Special Purpose Visas	t	f	5 years	Ireland
1	Tourist Visas	f	f	6 years	Israel
2	Business Visas	t	f	5 years	Israel
3	Work Visas	t	f	10 years	Israel
4	Student Visas	t	f	5 years	Israel
5	Transit Visas	f	f	5 years	Israel
6	Family and Dependent Visas	t	f	6 years	Israel
7	Immigrant Visas	t	t	8 years	Israel
8	Refugee and Asylum Visas	t	f	9 years	Israel
9	Special Purpose Visas	t	f	8 years	Israel
1	Tourist Visas	f	f	8 years	Italy
2	Business Visas	t	f	6 years	Italy
3	Work Visas	t	f	10 years	Italy
4	Student Visas	t	f	8 years	Italy
5	Transit Visas	f	f	10 years	Italy
6	Family and Dependent Visas	t	f	7 years	Italy
7	Immigrant Visas	t	t	10 years	Italy
8	Refugee and Asylum Visas	t	f	8 years	Italy
9	Special Purpose Visas	t	f	8 years	Italy
1	Tourist Visas	f	f	7 years	Jamaica
2	Business Visas	t	f	7 years	Jamaica
3	Work Visas	t	f	6 years	Jamaica
4	Student Visas	t	f	8 years	Jamaica
5	Transit Visas	f	f	9 years	Jamaica
6	Family and Dependent Visas	t	f	8 years	Jamaica
7	Immigrant Visas	t	t	7 years	Jamaica
8	Refugee and Asylum Visas	t	f	6 years	Jamaica
9	Special Purpose Visas	t	f	10 years	Jamaica
1	Tourist Visas	f	f	10 years	Japan
2	Business Visas	t	f	6 years	Japan
3	Work Visas	t	f	10 years	Japan
4	Student Visas	t	f	10 years	Japan
5	Transit Visas	f	f	10 years	Japan
6	Family and Dependent Visas	t	f	5 years	Japan
7	Immigrant Visas	t	t	8 years	Japan
8	Refugee and Asylum Visas	t	f	8 years	Japan
9	Special Purpose Visas	t	f	10 years	Japan
1	Tourist Visas	f	f	7 years	Jordan
2	Business Visas	t	f	7 years	Jordan
3	Work Visas	t	f	5 years	Jordan
4	Student Visas	t	f	10 years	Jordan
5	Transit Visas	f	f	8 years	Jordan
6	Family and Dependent Visas	t	f	9 years	Jordan
7	Immigrant Visas	t	t	8 years	Jordan
8	Refugee and Asylum Visas	t	f	5 years	Jordan
9	Special Purpose Visas	t	f	6 years	Jordan
1	Tourist Visas	f	f	7 years	Kazakhstan
2	Business Visas	t	f	5 years	Kazakhstan
3	Work Visas	t	f	10 years	Kazakhstan
4	Student Visas	t	f	10 years	Kazakhstan
5	Transit Visas	f	f	5 years	Kazakhstan
6	Family and Dependent Visas	t	f	9 years	Kazakhstan
7	Immigrant Visas	t	t	9 years	Kazakhstan
8	Refugee and Asylum Visas	t	f	8 years	Kazakhstan
9	Special Purpose Visas	t	f	5 years	Kazakhstan
1	Tourist Visas	f	f	7 years	Kenya
2	Business Visas	t	f	5 years	Kenya
3	Work Visas	t	f	9 years	Kenya
4	Student Visas	t	f	7 years	Kenya
5	Transit Visas	f	f	10 years	Kenya
6	Family and Dependent Visas	t	f	7 years	Kenya
7	Immigrant Visas	t	t	5 years	Kenya
8	Refugee and Asylum Visas	t	f	8 years	Kenya
9	Special Purpose Visas	t	f	6 years	Kenya
1	Tourist Visas	f	f	5 years	Kiribati
2	Business Visas	t	f	6 years	Kiribati
3	Work Visas	t	f	5 years	Kiribati
4	Student Visas	t	f	10 years	Kiribati
5	Transit Visas	f	f	7 years	Kiribati
6	Family and Dependent Visas	t	f	7 years	Kiribati
7	Immigrant Visas	t	t	6 years	Kiribati
8	Refugee and Asylum Visas	t	f	6 years	Kiribati
9	Special Purpose Visas	t	f	7 years	Kiribati
1	Tourist Visas	f	f	5 years	Kosovo
2	Business Visas	t	f	10 years	Kosovo
3	Work Visas	t	f	7 years	Kosovo
4	Student Visas	t	f	7 years	Kosovo
5	Transit Visas	f	f	10 years	Kosovo
6	Family and Dependent Visas	t	f	7 years	Kosovo
7	Immigrant Visas	t	t	6 years	Kosovo
8	Refugee and Asylum Visas	t	f	8 years	Kosovo
9	Special Purpose Visas	t	f	10 years	Kosovo
1	Tourist Visas	f	f	10 years	Kyrgyzstan
2	Business Visas	t	f	8 years	Kyrgyzstan
3	Work Visas	t	f	9 years	Kyrgyzstan
4	Student Visas	t	f	8 years	Kyrgyzstan
5	Transit Visas	f	f	10 years	Kyrgyzstan
6	Family and Dependent Visas	t	f	8 years	Kyrgyzstan
7	Immigrant Visas	t	t	8 years	Kyrgyzstan
8	Refugee and Asylum Visas	t	f	5 years	Kyrgyzstan
9	Special Purpose Visas	t	f	8 years	Kyrgyzstan
1	Tourist Visas	f	f	5 years	Laos
2	Business Visas	t	f	10 years	Laos
3	Work Visas	t	f	7 years	Laos
4	Student Visas	t	f	9 years	Laos
5	Transit Visas	f	f	6 years	Laos
6	Family and Dependent Visas	t	f	7 years	Laos
7	Immigrant Visas	t	t	7 years	Laos
8	Refugee and Asylum Visas	t	f	7 years	Laos
9	Special Purpose Visas	t	f	8 years	Laos
1	Tourist Visas	f	f	6 years	Latvia
2	Business Visas	t	f	7 years	Latvia
3	Work Visas	t	f	9 years	Latvia
4	Student Visas	t	f	8 years	Latvia
5	Transit Visas	f	f	6 years	Latvia
6	Family and Dependent Visas	t	f	5 years	Latvia
7	Immigrant Visas	t	t	9 years	Latvia
8	Refugee and Asylum Visas	t	f	7 years	Latvia
9	Special Purpose Visas	t	f	8 years	Latvia
1	Tourist Visas	f	f	9 years	Lebanon
2	Business Visas	t	f	8 years	Lebanon
3	Work Visas	t	f	8 years	Lebanon
4	Student Visas	t	f	8 years	Lebanon
5	Transit Visas	f	f	10 years	Lebanon
6	Family and Dependent Visas	t	f	8 years	Lebanon
7	Immigrant Visas	t	t	7 years	Lebanon
8	Refugee and Asylum Visas	t	f	7 years	Lebanon
9	Special Purpose Visas	t	f	8 years	Lebanon
1	Tourist Visas	f	f	8 years	Lesotho
2	Business Visas	t	f	10 years	Lesotho
3	Work Visas	t	f	9 years	Lesotho
4	Student Visas	t	f	9 years	Lesotho
5	Transit Visas	f	f	7 years	Lesotho
6	Family and Dependent Visas	t	f	9 years	Lesotho
7	Immigrant Visas	t	t	6 years	Lesotho
8	Refugee and Asylum Visas	t	f	7 years	Lesotho
9	Special Purpose Visas	t	f	10 years	Lesotho
1	Tourist Visas	f	f	10 years	Liberia
2	Business Visas	t	f	8 years	Liberia
3	Work Visas	t	f	9 years	Liberia
4	Student Visas	t	f	9 years	Liberia
5	Transit Visas	f	f	5 years	Liberia
6	Family and Dependent Visas	t	f	5 years	Liberia
7	Immigrant Visas	t	t	9 years	Liberia
8	Refugee and Asylum Visas	t	f	10 years	Liberia
9	Special Purpose Visas	t	f	10 years	Liberia
1	Tourist Visas	f	f	10 years	Libya
2	Business Visas	t	f	6 years	Libya
3	Work Visas	t	f	6 years	Libya
4	Student Visas	t	f	6 years	Libya
5	Transit Visas	f	f	10 years	Libya
6	Family and Dependent Visas	t	f	10 years	Libya
7	Immigrant Visas	t	t	9 years	Libya
8	Refugee and Asylum Visas	t	f	10 years	Libya
9	Special Purpose Visas	t	f	9 years	Libya
1	Tourist Visas	f	f	5 years	Liechtenstein
2	Business Visas	t	f	7 years	Liechtenstein
3	Work Visas	t	f	5 years	Liechtenstein
4	Student Visas	t	f	7 years	Liechtenstein
5	Transit Visas	f	f	8 years	Liechtenstein
6	Family and Dependent Visas	t	f	5 years	Liechtenstein
7	Immigrant Visas	t	t	7 years	Liechtenstein
8	Refugee and Asylum Visas	t	f	7 years	Liechtenstein
9	Special Purpose Visas	t	f	8 years	Liechtenstein
1	Tourist Visas	f	f	9 years	Lithuania
2	Business Visas	t	f	7 years	Lithuania
3	Work Visas	t	f	10 years	Lithuania
4	Student Visas	t	f	7 years	Lithuania
5	Transit Visas	f	f	10 years	Lithuania
6	Family and Dependent Visas	t	f	10 years	Lithuania
7	Immigrant Visas	t	t	10 years	Lithuania
8	Refugee and Asylum Visas	t	f	6 years	Lithuania
9	Special Purpose Visas	t	f	8 years	Lithuania
1	Tourist Visas	f	f	8 years	Luxembourg
2	Business Visas	t	f	7 years	Luxembourg
3	Work Visas	t	f	6 years	Luxembourg
4	Student Visas	t	f	8 years	Luxembourg
5	Transit Visas	f	f	10 years	Luxembourg
6	Family and Dependent Visas	t	f	8 years	Luxembourg
7	Immigrant Visas	t	t	6 years	Luxembourg
8	Refugee and Asylum Visas	t	f	10 years	Luxembourg
9	Special Purpose Visas	t	f	9 years	Luxembourg
1	Tourist Visas	f	f	6 years	Macao
2	Business Visas	t	f	8 years	Macao
3	Work Visas	t	f	9 years	Macao
4	Student Visas	t	f	9 years	Macao
5	Transit Visas	f	f	8 years	Macao
6	Family and Dependent Visas	t	f	5 years	Macao
7	Immigrant Visas	t	t	7 years	Macao
8	Refugee and Asylum Visas	t	f	8 years	Macao
9	Special Purpose Visas	t	f	8 years	Macao
1	Tourist Visas	f	f	5 years	Macedonia
2	Business Visas	t	f	9 years	Macedonia
3	Work Visas	t	f	5 years	Macedonia
4	Student Visas	t	f	8 years	Macedonia
5	Transit Visas	f	f	10 years	Macedonia
6	Family and Dependent Visas	t	f	5 years	Macedonia
7	Immigrant Visas	t	t	7 years	Macedonia
8	Refugee and Asylum Visas	t	f	7 years	Macedonia
9	Special Purpose Visas	t	f	10 years	Macedonia
1	Tourist Visas	f	f	10 years	Madagascar
2	Business Visas	t	f	10 years	Madagascar
3	Work Visas	t	f	7 years	Madagascar
4	Student Visas	t	f	5 years	Madagascar
5	Transit Visas	f	f	9 years	Madagascar
6	Family and Dependent Visas	t	f	8 years	Madagascar
7	Immigrant Visas	t	t	7 years	Madagascar
8	Refugee and Asylum Visas	t	f	9 years	Madagascar
9	Special Purpose Visas	t	f	5 years	Madagascar
1	Tourist Visas	f	f	10 years	Malawi
2	Business Visas	t	f	6 years	Malawi
3	Work Visas	t	f	7 years	Malawi
4	Student Visas	t	f	10 years	Malawi
5	Transit Visas	f	f	9 years	Malawi
6	Family and Dependent Visas	t	f	7 years	Malawi
7	Immigrant Visas	t	t	7 years	Malawi
8	Refugee and Asylum Visas	t	f	8 years	Malawi
9	Special Purpose Visas	t	f	9 years	Malawi
1	Tourist Visas	f	f	8 years	Malaysia
2	Business Visas	t	f	6 years	Malaysia
3	Work Visas	t	f	7 years	Malaysia
4	Student Visas	t	f	10 years	Malaysia
5	Transit Visas	f	f	7 years	Malaysia
6	Family and Dependent Visas	t	f	7 years	Malaysia
7	Immigrant Visas	t	t	7 years	Malaysia
8	Refugee and Asylum Visas	t	f	10 years	Malaysia
9	Special Purpose Visas	t	f	9 years	Malaysia
1	Tourist Visas	f	f	7 years	Maldives
2	Business Visas	t	f	6 years	Maldives
3	Work Visas	t	f	6 years	Maldives
4	Student Visas	t	f	7 years	Maldives
5	Transit Visas	f	f	9 years	Maldives
6	Family and Dependent Visas	t	f	7 years	Maldives
7	Immigrant Visas	t	t	8 years	Maldives
8	Refugee and Asylum Visas	t	f	9 years	Maldives
9	Special Purpose Visas	t	f	8 years	Maldives
1	Tourist Visas	f	f	5 years	Mali
2	Business Visas	t	f	10 years	Mali
3	Work Visas	t	f	9 years	Mali
4	Student Visas	t	f	6 years	Mali
5	Transit Visas	f	f	6 years	Mali
6	Family and Dependent Visas	t	f	5 years	Mali
7	Immigrant Visas	t	t	10 years	Mali
8	Refugee and Asylum Visas	t	f	7 years	Mali
9	Special Purpose Visas	t	f	10 years	Mali
1	Tourist Visas	f	f	9 years	Malta
2	Business Visas	t	f	10 years	Malta
3	Work Visas	t	f	8 years	Malta
4	Student Visas	t	f	10 years	Malta
5	Transit Visas	f	f	9 years	Malta
6	Family and Dependent Visas	t	f	7 years	Malta
7	Immigrant Visas	t	t	10 years	Malta
8	Refugee and Asylum Visas	t	f	7 years	Malta
9	Special Purpose Visas	t	f	7 years	Malta
1	Tourist Visas	f	f	7 years	Martinique
2	Business Visas	t	f	7 years	Martinique
3	Work Visas	t	f	7 years	Martinique
4	Student Visas	t	f	5 years	Martinique
5	Transit Visas	f	f	5 years	Martinique
6	Family and Dependent Visas	t	f	5 years	Martinique
7	Immigrant Visas	t	t	6 years	Martinique
8	Refugee and Asylum Visas	t	f	5 years	Martinique
9	Special Purpose Visas	t	f	7 years	Martinique
1	Tourist Visas	f	f	10 years	Mauritania
2	Business Visas	t	f	10 years	Mauritania
3	Work Visas	t	f	6 years	Mauritania
4	Student Visas	t	f	10 years	Mauritania
5	Transit Visas	f	f	7 years	Mauritania
6	Family and Dependent Visas	t	f	5 years	Mauritania
7	Immigrant Visas	t	t	9 years	Mauritania
8	Refugee and Asylum Visas	t	f	5 years	Mauritania
9	Special Purpose Visas	t	f	7 years	Mauritania
1	Tourist Visas	f	f	9 years	Mauritius
2	Business Visas	t	f	8 years	Mauritius
3	Work Visas	t	f	8 years	Mauritius
4	Student Visas	t	f	9 years	Mauritius
5	Transit Visas	f	f	6 years	Mauritius
6	Family and Dependent Visas	t	f	7 years	Mauritius
7	Immigrant Visas	t	t	7 years	Mauritius
8	Refugee and Asylum Visas	t	f	6 years	Mauritius
9	Special Purpose Visas	t	f	7 years	Mauritius
1	Tourist Visas	f	f	9 years	Mayotte
2	Business Visas	t	f	7 years	Mayotte
3	Work Visas	t	f	9 years	Mayotte
4	Student Visas	t	f	5 years	Mayotte
5	Transit Visas	f	f	8 years	Mayotte
6	Family and Dependent Visas	t	f	6 years	Mayotte
7	Immigrant Visas	t	t	9 years	Mayotte
8	Refugee and Asylum Visas	t	f	6 years	Mayotte
9	Special Purpose Visas	t	f	5 years	Mayotte
1	Tourist Visas	f	f	10 years	Mexico
2	Business Visas	t	f	7 years	Mexico
3	Work Visas	t	f	10 years	Mexico
4	Student Visas	t	f	7 years	Mexico
5	Transit Visas	f	f	5 years	Mexico
6	Family and Dependent Visas	t	f	10 years	Mexico
7	Immigrant Visas	t	t	7 years	Mexico
8	Refugee and Asylum Visas	t	f	5 years	Mexico
9	Special Purpose Visas	t	f	10 years	Mexico
1	Tourist Visas	f	f	8 years	Moldova
2	Business Visas	t	f	9 years	Moldova
3	Work Visas	t	f	8 years	Moldova
4	Student Visas	t	f	6 years	Moldova
5	Transit Visas	f	f	6 years	Moldova
6	Family and Dependent Visas	t	f	9 years	Moldova
7	Immigrant Visas	t	t	9 years	Moldova
8	Refugee and Asylum Visas	t	f	6 years	Moldova
9	Special Purpose Visas	t	f	5 years	Moldova
1	Tourist Visas	f	f	6 years	Monaco
2	Business Visas	t	f	5 years	Monaco
3	Work Visas	t	f	7 years	Monaco
4	Student Visas	t	f	5 years	Monaco
5	Transit Visas	f	f	7 years	Monaco
6	Family and Dependent Visas	t	f	5 years	Monaco
7	Immigrant Visas	t	t	6 years	Monaco
8	Refugee and Asylum Visas	t	f	7 years	Monaco
9	Special Purpose Visas	t	f	10 years	Monaco
1	Tourist Visas	f	f	9 years	Mongolia
2	Business Visas	t	f	7 years	Mongolia
3	Work Visas	t	f	7 years	Mongolia
4	Student Visas	t	f	5 years	Mongolia
5	Transit Visas	f	f	10 years	Mongolia
6	Family and Dependent Visas	t	f	10 years	Mongolia
7	Immigrant Visas	t	t	10 years	Mongolia
8	Refugee and Asylum Visas	t	f	6 years	Mongolia
9	Special Purpose Visas	t	f	9 years	Mongolia
1	Tourist Visas	f	f	10 years	Montenegro
2	Business Visas	t	f	6 years	Montenegro
3	Work Visas	t	f	9 years	Montenegro
4	Student Visas	t	f	6 years	Montenegro
5	Transit Visas	f	f	9 years	Montenegro
6	Family and Dependent Visas	t	f	10 years	Montenegro
7	Immigrant Visas	t	t	10 years	Montenegro
8	Refugee and Asylum Visas	t	f	6 years	Montenegro
9	Special Purpose Visas	t	f	9 years	Montenegro
1	Tourist Visas	f	f	9 years	Montserrat
2	Business Visas	t	f	5 years	Montserrat
3	Work Visas	t	f	9 years	Montserrat
4	Student Visas	t	f	10 years	Montserrat
5	Transit Visas	f	f	5 years	Montserrat
6	Family and Dependent Visas	t	f	5 years	Montserrat
7	Immigrant Visas	t	t	7 years	Montserrat
8	Refugee and Asylum Visas	t	f	6 years	Montserrat
9	Special Purpose Visas	t	f	9 years	Montserrat
1	Tourist Visas	f	f	10 years	Morocco
2	Business Visas	t	f	6 years	Morocco
3	Work Visas	t	f	6 years	Morocco
4	Student Visas	t	f	5 years	Morocco
5	Transit Visas	f	f	5 years	Morocco
6	Family and Dependent Visas	t	f	7 years	Morocco
7	Immigrant Visas	t	t	8 years	Morocco
8	Refugee and Asylum Visas	t	f	9 years	Morocco
9	Special Purpose Visas	t	f	10 years	Morocco
1	Tourist Visas	f	f	9 years	Mozambique
2	Business Visas	t	f	5 years	Mozambique
3	Work Visas	t	f	10 years	Mozambique
4	Student Visas	t	f	7 years	Mozambique
5	Transit Visas	f	f	9 years	Mozambique
6	Family and Dependent Visas	t	f	10 years	Mozambique
7	Immigrant Visas	t	t	6 years	Mozambique
8	Refugee and Asylum Visas	t	f	7 years	Mozambique
9	Special Purpose Visas	t	f	5 years	Mozambique
1	Tourist Visas	f	f	9 years	Myanmar
2	Business Visas	t	f	9 years	Myanmar
3	Work Visas	t	f	7 years	Myanmar
4	Student Visas	t	f	6 years	Myanmar
5	Transit Visas	f	f	8 years	Myanmar
6	Family and Dependent Visas	t	f	9 years	Myanmar
7	Immigrant Visas	t	t	6 years	Myanmar
8	Refugee and Asylum Visas	t	f	5 years	Myanmar
9	Special Purpose Visas	t	f	8 years	Myanmar
1	Tourist Visas	f	f	5 years	Namibia
2	Business Visas	t	f	8 years	Namibia
3	Work Visas	t	f	5 years	Namibia
4	Student Visas	t	f	5 years	Namibia
5	Transit Visas	f	f	5 years	Namibia
6	Family and Dependent Visas	t	f	9 years	Namibia
7	Immigrant Visas	t	t	9 years	Namibia
8	Refugee and Asylum Visas	t	f	6 years	Namibia
9	Special Purpose Visas	t	f	8 years	Namibia
1	Tourist Visas	f	f	9 years	Nauru
2	Business Visas	t	f	10 years	Nauru
3	Work Visas	t	f	9 years	Nauru
4	Student Visas	t	f	9 years	Nauru
5	Transit Visas	f	f	9 years	Nauru
6	Family and Dependent Visas	t	f	8 years	Nauru
7	Immigrant Visas	t	t	5 years	Nauru
8	Refugee and Asylum Visas	t	f	10 years	Nauru
9	Special Purpose Visas	t	f	9 years	Nauru
1	Tourist Visas	f	f	7 years	Nepal
2	Business Visas	t	f	8 years	Nepal
3	Work Visas	t	f	9 years	Nepal
4	Student Visas	t	f	7 years	Nepal
5	Transit Visas	f	f	9 years	Nepal
6	Family and Dependent Visas	t	f	6 years	Nepal
7	Immigrant Visas	t	t	5 years	Nepal
8	Refugee and Asylum Visas	t	f	6 years	Nepal
9	Special Purpose Visas	t	f	10 years	Nepal
1	Tourist Visas	f	f	7 years	Netherlands
2	Business Visas	t	f	7 years	Netherlands
3	Work Visas	t	f	6 years	Netherlands
4	Student Visas	t	f	8 years	Netherlands
5	Transit Visas	f	f	9 years	Netherlands
6	Family and Dependent Visas	t	f	6 years	Netherlands
7	Immigrant Visas	t	t	6 years	Netherlands
8	Refugee and Asylum Visas	t	f	9 years	Netherlands
9	Special Purpose Visas	t	f	6 years	Netherlands
1	Tourist Visas	f	f	8 years	Nicaragua
2	Business Visas	t	f	10 years	Nicaragua
3	Work Visas	t	f	10 years	Nicaragua
4	Student Visas	t	f	5 years	Nicaragua
5	Transit Visas	f	f	9 years	Nicaragua
6	Family and Dependent Visas	t	f	9 years	Nicaragua
7	Immigrant Visas	t	t	7 years	Nicaragua
8	Refugee and Asylum Visas	t	f	7 years	Nicaragua
9	Special Purpose Visas	t	f	8 years	Nicaragua
1	Tourist Visas	f	f	6 years	Niger
2	Business Visas	t	f	8 years	Niger
3	Work Visas	t	f	9 years	Niger
4	Student Visas	t	f	10 years	Niger
5	Transit Visas	f	f	8 years	Niger
6	Family and Dependent Visas	t	f	6 years	Niger
7	Immigrant Visas	t	t	5 years	Niger
8	Refugee and Asylum Visas	t	f	6 years	Niger
9	Special Purpose Visas	t	f	10 years	Niger
1	Tourist Visas	f	f	5 years	Nigeria
2	Business Visas	t	f	9 years	Nigeria
3	Work Visas	t	f	9 years	Nigeria
4	Student Visas	t	f	6 years	Nigeria
5	Transit Visas	f	f	9 years	Nigeria
6	Family and Dependent Visas	t	f	5 years	Nigeria
7	Immigrant Visas	t	t	8 years	Nigeria
8	Refugee and Asylum Visas	t	f	9 years	Nigeria
9	Special Purpose Visas	t	f	9 years	Nigeria
1	Tourist Visas	f	f	5 years	Niue
2	Business Visas	t	f	10 years	Niue
3	Work Visas	t	f	10 years	Niue
4	Student Visas	t	f	10 years	Niue
5	Transit Visas	f	f	5 years	Niue
6	Family and Dependent Visas	t	f	5 years	Niue
7	Immigrant Visas	t	t	6 years	Niue
8	Refugee and Asylum Visas	t	f	6 years	Niue
9	Special Purpose Visas	t	f	8 years	Niue
1	Tourist Visas	f	f	7 years	Norway
2	Business Visas	t	f	5 years	Norway
3	Work Visas	t	f	10 years	Norway
4	Student Visas	t	f	8 years	Norway
5	Transit Visas	f	f	5 years	Norway
6	Family and Dependent Visas	t	f	9 years	Norway
7	Immigrant Visas	t	t	7 years	Norway
8	Refugee and Asylum Visas	t	f	5 years	Norway
9	Special Purpose Visas	t	f	6 years	Norway
1	Tourist Visas	f	f	8 years	Oman
2	Business Visas	t	f	7 years	Oman
3	Work Visas	t	f	8 years	Oman
4	Student Visas	t	f	6 years	Oman
5	Transit Visas	f	f	8 years	Oman
6	Family and Dependent Visas	t	f	6 years	Oman
7	Immigrant Visas	t	t	5 years	Oman
8	Refugee and Asylum Visas	t	f	9 years	Oman
9	Special Purpose Visas	t	f	7 years	Oman
1	Tourist Visas	f	f	5 years	Pakistan
2	Business Visas	t	f	7 years	Pakistan
3	Work Visas	t	f	6 years	Pakistan
4	Student Visas	t	f	7 years	Pakistan
5	Transit Visas	f	f	9 years	Pakistan
6	Family and Dependent Visas	t	f	6 years	Pakistan
7	Immigrant Visas	t	t	8 years	Pakistan
8	Refugee and Asylum Visas	t	f	5 years	Pakistan
9	Special Purpose Visas	t	f	10 years	Pakistan
1	Tourist Visas	f	f	7 years	Palau
2	Business Visas	t	f	9 years	Palau
3	Work Visas	t	f	9 years	Palau
4	Student Visas	t	f	10 years	Palau
5	Transit Visas	f	f	10 years	Palau
6	Family and Dependent Visas	t	f	6 years	Palau
7	Immigrant Visas	t	t	10 years	Palau
8	Refugee and Asylum Visas	t	f	8 years	Palau
9	Special Purpose Visas	t	f	6 years	Palau
1	Tourist Visas	f	f	9 years	Panama
2	Business Visas	t	f	10 years	Panama
3	Work Visas	t	f	7 years	Panama
4	Student Visas	t	f	9 years	Panama
5	Transit Visas	f	f	8 years	Panama
6	Family and Dependent Visas	t	f	6 years	Panama
7	Immigrant Visas	t	t	9 years	Panama
8	Refugee and Asylum Visas	t	f	8 years	Panama
9	Special Purpose Visas	t	f	7 years	Panama
1	Tourist Visas	f	f	5 years	Paraguay
2	Business Visas	t	f	7 years	Paraguay
3	Work Visas	t	f	8 years	Paraguay
4	Student Visas	t	f	6 years	Paraguay
5	Transit Visas	f	f	8 years	Paraguay
6	Family and Dependent Visas	t	f	8 years	Paraguay
7	Immigrant Visas	t	t	7 years	Paraguay
8	Refugee and Asylum Visas	t	f	5 years	Paraguay
9	Special Purpose Visas	t	f	6 years	Paraguay
1	Tourist Visas	f	f	8 years	Peru
2	Business Visas	t	f	9 years	Peru
3	Work Visas	t	f	5 years	Peru
4	Student Visas	t	f	6 years	Peru
5	Transit Visas	f	f	5 years	Peru
6	Family and Dependent Visas	t	f	9 years	Peru
7	Immigrant Visas	t	t	7 years	Peru
8	Refugee and Asylum Visas	t	f	8 years	Peru
9	Special Purpose Visas	t	f	10 years	Peru
1	Tourist Visas	f	f	9 years	Philippines
2	Business Visas	t	f	5 years	Philippines
3	Work Visas	t	f	9 years	Philippines
4	Student Visas	t	f	8 years	Philippines
5	Transit Visas	f	f	5 years	Philippines
6	Family and Dependent Visas	t	f	10 years	Philippines
7	Immigrant Visas	t	t	8 years	Philippines
8	Refugee and Asylum Visas	t	f	10 years	Philippines
9	Special Purpose Visas	t	f	5 years	Philippines
1	Tourist Visas	f	f	6 years	Pitcairn
2	Business Visas	t	f	5 years	Pitcairn
3	Work Visas	t	f	6 years	Pitcairn
4	Student Visas	t	f	7 years	Pitcairn
5	Transit Visas	f	f	7 years	Pitcairn
6	Family and Dependent Visas	t	f	5 years	Pitcairn
7	Immigrant Visas	t	t	8 years	Pitcairn
8	Refugee and Asylum Visas	t	f	8 years	Pitcairn
9	Special Purpose Visas	t	f	5 years	Pitcairn
1	Tourist Visas	f	f	5 years	Poland
2	Business Visas	t	f	7 years	Poland
3	Work Visas	t	f	8 years	Poland
4	Student Visas	t	f	6 years	Poland
5	Transit Visas	f	f	8 years	Poland
6	Family and Dependent Visas	t	f	10 years	Poland
7	Immigrant Visas	t	t	8 years	Poland
8	Refugee and Asylum Visas	t	f	10 years	Poland
9	Special Purpose Visas	t	f	6 years	Poland
1	Tourist Visas	f	f	7 years	Portugal
2	Business Visas	t	f	5 years	Portugal
3	Work Visas	t	f	6 years	Portugal
4	Student Visas	t	f	6 years	Portugal
5	Transit Visas	f	f	9 years	Portugal
6	Family and Dependent Visas	t	f	7 years	Portugal
7	Immigrant Visas	t	t	7 years	Portugal
8	Refugee and Asylum Visas	t	f	5 years	Portugal
9	Special Purpose Visas	t	f	8 years	Portugal
1	Tourist Visas	f	f	9 years	Qatar
2	Business Visas	t	f	9 years	Qatar
3	Work Visas	t	f	10 years	Qatar
4	Student Visas	t	f	9 years	Qatar
5	Transit Visas	f	f	5 years	Qatar
6	Family and Dependent Visas	t	f	5 years	Qatar
7	Immigrant Visas	t	t	6 years	Qatar
8	Refugee and Asylum Visas	t	f	7 years	Qatar
9	Special Purpose Visas	t	f	10 years	Qatar
1	Tourist Visas	f	f	9 years	Romania
2	Business Visas	t	f	10 years	Romania
3	Work Visas	t	f	5 years	Romania
4	Student Visas	t	f	6 years	Romania
5	Transit Visas	f	f	9 years	Romania
6	Family and Dependent Visas	t	f	10 years	Romania
7	Immigrant Visas	t	t	7 years	Romania
8	Refugee and Asylum Visas	t	f	7 years	Romania
9	Special Purpose Visas	t	f	6 years	Romania
1	Tourist Visas	f	f	6 years	Russia
2	Business Visas	t	f	7 years	Russia
3	Work Visas	t	f	10 years	Russia
4	Student Visas	t	f	5 years	Russia
5	Transit Visas	f	f	10 years	Russia
6	Family and Dependent Visas	t	f	5 years	Russia
7	Immigrant Visas	t	t	6 years	Russia
8	Refugee and Asylum Visas	t	f	10 years	Russia
9	Special Purpose Visas	t	f	10 years	Russia
1	Tourist Visas	f	f	10 years	Rwanda
2	Business Visas	t	f	9 years	Rwanda
3	Work Visas	t	f	7 years	Rwanda
4	Student Visas	t	f	10 years	Rwanda
5	Transit Visas	f	f	7 years	Rwanda
6	Family and Dependent Visas	t	f	5 years	Rwanda
7	Immigrant Visas	t	t	8 years	Rwanda
8	Refugee and Asylum Visas	t	f	10 years	Rwanda
9	Special Purpose Visas	t	f	7 years	Rwanda
1	Tourist Visas	f	f	6 years	Samoa
2	Business Visas	t	f	7 years	Samoa
3	Work Visas	t	f	6 years	Samoa
4	Student Visas	t	f	10 years	Samoa
5	Transit Visas	f	f	5 years	Samoa
6	Family and Dependent Visas	t	f	8 years	Samoa
7	Immigrant Visas	t	t	6 years	Samoa
8	Refugee and Asylum Visas	t	f	6 years	Samoa
9	Special Purpose Visas	t	f	5 years	Samoa
1	Tourist Visas	f	f	7 years	Senegal
2	Business Visas	t	f	5 years	Senegal
3	Work Visas	t	f	8 years	Senegal
4	Student Visas	t	f	7 years	Senegal
5	Transit Visas	f	f	5 years	Senegal
6	Family and Dependent Visas	t	f	6 years	Senegal
7	Immigrant Visas	t	t	7 years	Senegal
8	Refugee and Asylum Visas	t	f	5 years	Senegal
9	Special Purpose Visas	t	f	6 years	Senegal
1	Tourist Visas	f	f	10 years	Serbia
2	Business Visas	t	f	8 years	Serbia
3	Work Visas	t	f	9 years	Serbia
4	Student Visas	t	f	9 years	Serbia
5	Transit Visas	f	f	10 years	Serbia
6	Family and Dependent Visas	t	f	7 years	Serbia
7	Immigrant Visas	t	t	9 years	Serbia
8	Refugee and Asylum Visas	t	f	6 years	Serbia
9	Special Purpose Visas	t	f	9 years	Serbia
1	Tourist Visas	f	f	8 years	Seychelles
2	Business Visas	t	f	8 years	Seychelles
3	Work Visas	t	f	8 years	Seychelles
4	Student Visas	t	f	8 years	Seychelles
5	Transit Visas	f	f	10 years	Seychelles
6	Family and Dependent Visas	t	f	10 years	Seychelles
7	Immigrant Visas	t	t	7 years	Seychelles
8	Refugee and Asylum Visas	t	f	7 years	Seychelles
9	Special Purpose Visas	t	f	7 years	Seychelles
1	Tourist Visas	f	f	5 years	Singapore
2	Business Visas	t	f	10 years	Singapore
3	Work Visas	t	f	9 years	Singapore
4	Student Visas	t	f	7 years	Singapore
5	Transit Visas	f	f	8 years	Singapore
6	Family and Dependent Visas	t	f	10 years	Singapore
7	Immigrant Visas	t	t	5 years	Singapore
8	Refugee and Asylum Visas	t	f	7 years	Singapore
9	Special Purpose Visas	t	f	10 years	Singapore
1	Tourist Visas	f	f	8 years	Slovakia
2	Business Visas	t	f	10 years	Slovakia
3	Work Visas	t	f	10 years	Slovakia
4	Student Visas	t	f	6 years	Slovakia
5	Transit Visas	f	f	9 years	Slovakia
6	Family and Dependent Visas	t	f	8 years	Slovakia
7	Immigrant Visas	t	t	8 years	Slovakia
8	Refugee and Asylum Visas	t	f	5 years	Slovakia
9	Special Purpose Visas	t	f	6 years	Slovakia
1	Tourist Visas	f	f	8 years	Slovenia
2	Business Visas	t	f	7 years	Slovenia
3	Work Visas	t	f	7 years	Slovenia
4	Student Visas	t	f	9 years	Slovenia
5	Transit Visas	f	f	5 years	Slovenia
6	Family and Dependent Visas	t	f	10 years	Slovenia
7	Immigrant Visas	t	t	5 years	Slovenia
8	Refugee and Asylum Visas	t	f	9 years	Slovenia
9	Special Purpose Visas	t	f	10 years	Slovenia
1	Tourist Visas	f	f	7 years	Somalia
2	Business Visas	t	f	7 years	Somalia
3	Work Visas	t	f	6 years	Somalia
4	Student Visas	t	f	7 years	Somalia
5	Transit Visas	f	f	5 years	Somalia
6	Family and Dependent Visas	t	f	9 years	Somalia
7	Immigrant Visas	t	t	7 years	Somalia
8	Refugee and Asylum Visas	t	f	7 years	Somalia
9	Special Purpose Visas	t	f	10 years	Somalia
1	Tourist Visas	f	f	10 years	Spain
2	Business Visas	t	f	9 years	Spain
3	Work Visas	t	f	6 years	Spain
4	Student Visas	t	f	8 years	Spain
5	Transit Visas	f	f	6 years	Spain
6	Family and Dependent Visas	t	f	10 years	Spain
7	Immigrant Visas	t	t	10 years	Spain
8	Refugee and Asylum Visas	t	f	8 years	Spain
9	Special Purpose Visas	t	f	10 years	Spain
1	Tourist Visas	f	f	9 years	Sudan
2	Business Visas	t	f	10 years	Sudan
3	Work Visas	t	f	7 years	Sudan
4	Student Visas	t	f	6 years	Sudan
5	Transit Visas	f	f	7 years	Sudan
6	Family and Dependent Visas	t	f	10 years	Sudan
7	Immigrant Visas	t	t	9 years	Sudan
8	Refugee and Asylum Visas	t	f	9 years	Sudan
9	Special Purpose Visas	t	f	8 years	Sudan
1	Tourist Visas	f	f	8 years	Suriname
2	Business Visas	t	f	7 years	Suriname
3	Work Visas	t	f	6 years	Suriname
4	Student Visas	t	f	6 years	Suriname
5	Transit Visas	f	f	8 years	Suriname
6	Family and Dependent Visas	t	f	10 years	Suriname
7	Immigrant Visas	t	t	8 years	Suriname
8	Refugee and Asylum Visas	t	f	7 years	Suriname
9	Special Purpose Visas	t	f	8 years	Suriname
1	Tourist Visas	f	f	9 years	Swaziland
2	Business Visas	t	f	8 years	Swaziland
3	Work Visas	t	f	5 years	Swaziland
4	Student Visas	t	f	6 years	Swaziland
5	Transit Visas	f	f	10 years	Swaziland
6	Family and Dependent Visas	t	f	5 years	Swaziland
7	Immigrant Visas	t	t	8 years	Swaziland
8	Refugee and Asylum Visas	t	f	7 years	Swaziland
9	Special Purpose Visas	t	f	10 years	Swaziland
1	Tourist Visas	f	f	7 years	Sweden
2	Business Visas	t	f	7 years	Sweden
3	Work Visas	t	f	6 years	Sweden
4	Student Visas	t	f	5 years	Sweden
5	Transit Visas	f	f	9 years	Sweden
6	Family and Dependent Visas	t	f	10 years	Sweden
7	Immigrant Visas	t	t	5 years	Sweden
8	Refugee and Asylum Visas	t	f	7 years	Sweden
9	Special Purpose Visas	t	f	7 years	Sweden
1	Tourist Visas	f	f	6 years	Switzerland
2	Business Visas	t	f	10 years	Switzerland
3	Work Visas	t	f	9 years	Switzerland
4	Student Visas	t	f	8 years	Switzerland
5	Transit Visas	f	f	6 years	Switzerland
6	Family and Dependent Visas	t	f	10 years	Switzerland
7	Immigrant Visas	t	t	10 years	Switzerland
8	Refugee and Asylum Visas	t	f	10 years	Switzerland
9	Special Purpose Visas	t	f	5 years	Switzerland
1	Tourist Visas	f	f	8 years	Syria
2	Business Visas	t	f	7 years	Syria
3	Work Visas	t	f	6 years	Syria
4	Student Visas	t	f	9 years	Syria
5	Transit Visas	f	f	9 years	Syria
6	Family and Dependent Visas	t	f	5 years	Syria
7	Immigrant Visas	t	t	8 years	Syria
8	Refugee and Asylum Visas	t	f	5 years	Syria
9	Special Purpose Visas	t	f	6 years	Syria
1	Tourist Visas	f	f	9 years	Taiwan
2	Business Visas	t	f	8 years	Taiwan
3	Work Visas	t	f	9 years	Taiwan
4	Student Visas	t	f	9 years	Taiwan
5	Transit Visas	f	f	6 years	Taiwan
6	Family and Dependent Visas	t	f	9 years	Taiwan
7	Immigrant Visas	t	t	8 years	Taiwan
8	Refugee and Asylum Visas	t	f	7 years	Taiwan
9	Special Purpose Visas	t	f	5 years	Taiwan
1	Tourist Visas	f	f	7 years	Tajikistan
2	Business Visas	t	f	7 years	Tajikistan
3	Work Visas	t	f	10 years	Tajikistan
4	Student Visas	t	f	10 years	Tajikistan
5	Transit Visas	f	f	9 years	Tajikistan
6	Family and Dependent Visas	t	f	5 years	Tajikistan
7	Immigrant Visas	t	t	8 years	Tajikistan
8	Refugee and Asylum Visas	t	f	7 years	Tajikistan
9	Special Purpose Visas	t	f	7 years	Tajikistan
1	Tourist Visas	f	f	10 years	Tanzania
2	Business Visas	t	f	9 years	Tanzania
3	Work Visas	t	f	8 years	Tanzania
4	Student Visas	t	f	9 years	Tanzania
5	Transit Visas	f	f	10 years	Tanzania
6	Family and Dependent Visas	t	f	10 years	Tanzania
7	Immigrant Visas	t	t	9 years	Tanzania
8	Refugee and Asylum Visas	t	f	8 years	Tanzania
9	Special Purpose Visas	t	f	7 years	Tanzania
1	Tourist Visas	f	f	6 years	Thailand
2	Business Visas	t	f	10 years	Thailand
3	Work Visas	t	f	10 years	Thailand
4	Student Visas	t	f	5 years	Thailand
5	Transit Visas	f	f	5 years	Thailand
6	Family and Dependent Visas	t	f	7 years	Thailand
7	Immigrant Visas	t	t	7 years	Thailand
8	Refugee and Asylum Visas	t	f	6 years	Thailand
9	Special Purpose Visas	t	f	9 years	Thailand
1	Tourist Visas	f	f	10 years	Togo
2	Business Visas	t	f	8 years	Togo
3	Work Visas	t	f	5 years	Togo
4	Student Visas	t	f	8 years	Togo
5	Transit Visas	f	f	9 years	Togo
6	Family and Dependent Visas	t	f	5 years	Togo
7	Immigrant Visas	t	t	10 years	Togo
8	Refugee and Asylum Visas	t	f	7 years	Togo
9	Special Purpose Visas	t	f	8 years	Togo
1	Tourist Visas	f	f	6 years	Tunisia
2	Business Visas	t	f	10 years	Tunisia
3	Work Visas	t	f	8 years	Tunisia
4	Student Visas	t	f	6 years	Tunisia
5	Transit Visas	f	f	9 years	Tunisia
6	Family and Dependent Visas	t	f	7 years	Tunisia
7	Immigrant Visas	t	t	7 years	Tunisia
8	Refugee and Asylum Visas	t	f	7 years	Tunisia
9	Special Purpose Visas	t	f	10 years	Tunisia
1	Tourist Visas	f	f	9 years	Turkey
2	Business Visas	t	f	8 years	Turkey
3	Work Visas	t	f	6 years	Turkey
4	Student Visas	t	f	8 years	Turkey
5	Transit Visas	f	f	7 years	Turkey
6	Family and Dependent Visas	t	f	8 years	Turkey
7	Immigrant Visas	t	t	5 years	Turkey
8	Refugee and Asylum Visas	t	f	8 years	Turkey
9	Special Purpose Visas	t	f	7 years	Turkey
1	Tourist Visas	f	f	9 years	Turkmenistan
2	Business Visas	t	f	7 years	Turkmenistan
3	Work Visas	t	f	5 years	Turkmenistan
4	Student Visas	t	f	5 years	Turkmenistan
5	Transit Visas	f	f	9 years	Turkmenistan
6	Family and Dependent Visas	t	f	5 years	Turkmenistan
7	Immigrant Visas	t	t	7 years	Turkmenistan
8	Refugee and Asylum Visas	t	f	9 years	Turkmenistan
9	Special Purpose Visas	t	f	6 years	Turkmenistan
1	Tourist Visas	f	f	10 years	Tuvalu
2	Business Visas	t	f	10 years	Tuvalu
3	Work Visas	t	f	8 years	Tuvalu
4	Student Visas	t	f	9 years	Tuvalu
5	Transit Visas	f	f	7 years	Tuvalu
6	Family and Dependent Visas	t	f	9 years	Tuvalu
7	Immigrant Visas	t	t	10 years	Tuvalu
8	Refugee and Asylum Visas	t	f	6 years	Tuvalu
9	Special Purpose Visas	t	f	6 years	Tuvalu
1	Tourist Visas	f	f	6 years	Uganda
2	Business Visas	t	f	8 years	Uganda
3	Work Visas	t	f	7 years	Uganda
4	Student Visas	t	f	6 years	Uganda
5	Transit Visas	f	f	8 years	Uganda
6	Family and Dependent Visas	t	f	7 years	Uganda
7	Immigrant Visas	t	t	5 years	Uganda
8	Refugee and Asylum Visas	t	f	10 years	Uganda
9	Special Purpose Visas	t	f	6 years	Uganda
1	Tourist Visas	f	f	6 years	Ukraine
2	Business Visas	t	f	10 years	Ukraine
3	Work Visas	t	f	8 years	Ukraine
4	Student Visas	t	f	5 years	Ukraine
5	Transit Visas	f	f	8 years	Ukraine
6	Family and Dependent Visas	t	f	6 years	Ukraine
7	Immigrant Visas	t	t	10 years	Ukraine
8	Refugee and Asylum Visas	t	f	8 years	Ukraine
9	Special Purpose Visas	t	f	7 years	Ukraine
1	Tourist Visas	f	f	9 years	Uruguay
2	Business Visas	t	f	5 years	Uruguay
3	Work Visas	t	f	9 years	Uruguay
4	Student Visas	t	f	8 years	Uruguay
5	Transit Visas	f	f	10 years	Uruguay
6	Family and Dependent Visas	t	f	9 years	Uruguay
7	Immigrant Visas	t	t	8 years	Uruguay
8	Refugee and Asylum Visas	t	f	10 years	Uruguay
9	Special Purpose Visas	t	f	10 years	Uruguay
1	Tourist Visas	f	f	8 years	Uzbekistan
2	Business Visas	t	f	8 years	Uzbekistan
3	Work Visas	t	f	10 years	Uzbekistan
4	Student Visas	t	f	5 years	Uzbekistan
5	Transit Visas	f	f	5 years	Uzbekistan
6	Family and Dependent Visas	t	f	10 years	Uzbekistan
7	Immigrant Visas	t	t	9 years	Uzbekistan
8	Refugee and Asylum Visas	t	f	9 years	Uzbekistan
9	Special Purpose Visas	t	f	7 years	Uzbekistan
1	Tourist Visas	f	f	6 years	Venezuela
2	Business Visas	t	f	9 years	Venezuela
3	Work Visas	t	f	6 years	Venezuela
4	Student Visas	t	f	5 years	Venezuela
5	Transit Visas	f	f	5 years	Venezuela
6	Family and Dependent Visas	t	f	9 years	Venezuela
7	Immigrant Visas	t	t	5 years	Venezuela
8	Refugee and Asylum Visas	t	f	8 years	Venezuela
9	Special Purpose Visas	t	f	8 years	Venezuela
1	Tourist Visas	f	f	6 years	Vietnam
2	Business Visas	t	f	8 years	Vietnam
3	Work Visas	t	f	6 years	Vietnam
4	Student Visas	t	f	8 years	Vietnam
5	Transit Visas	f	f	8 years	Vietnam
6	Family and Dependent Visas	t	f	9 years	Vietnam
7	Immigrant Visas	t	t	10 years	Vietnam
8	Refugee and Asylum Visas	t	f	10 years	Vietnam
9	Special Purpose Visas	t	f	8 years	Vietnam
1	Tourist Visas	f	f	10 years	Yemen
2	Business Visas	t	f	6 years	Yemen
3	Work Visas	t	f	6 years	Yemen
4	Student Visas	t	f	6 years	Yemen
5	Transit Visas	f	f	7 years	Yemen
6	Family and Dependent Visas	t	f	6 years	Yemen
7	Immigrant Visas	t	t	7 years	Yemen
8	Refugee and Asylum Visas	t	f	5 years	Yemen
9	Special Purpose Visas	t	f	8 years	Yemen
1	Tourist Visas	f	f	9 years	Zambia
2	Business Visas	t	f	10 years	Zambia
3	Work Visas	t	f	7 years	Zambia
4	Student Visas	t	f	8 years	Zambia
5	Transit Visas	f	f	8 years	Zambia
6	Family and Dependent Visas	t	f	8 years	Zambia
7	Immigrant Visas	t	t	6 years	Zambia
8	Refugee and Asylum Visas	t	f	6 years	Zambia
9	Special Purpose Visas	t	f	6 years	Zambia
1	Tourist Visas	f	f	10 years	Zimbabwe
2	Business Visas	t	f	5 years	Zimbabwe
3	Work Visas	t	f	5 years	Zimbabwe
4	Student Visas	t	f	9 years	Zimbabwe
5	Transit Visas	f	f	8 years	Zimbabwe
6	Family and Dependent Visas	t	f	5 years	Zimbabwe
7	Immigrant Visas	t	t	8 years	Zimbabwe
8	Refugee and Asylum Visas	t	f	8 years	Zimbabwe
9	Special Purpose Visas	t	f	10 years	Zimbabwe
1	Tourist Visas	f	f	9 years	USA
2	Business Visas	t	f	7 years	USA
3	Work Visas	t	f	8 years	USA
4	Student Visas	t	f	9 years	USA
5	Transit Visas	f	f	5 years	USA
6	Family and Dependent Visas	t	f	7 years	USA
7	Immigrant Visas	t	t	9 years	USA
8	Refugee and Asylum Visas	t	f	9 years	USA
9	Special Purpose Visas	t	f	10 years	USA
\.


--
-- Data for Name: visas; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visas (id, type, passport, issue_date, inner_issuer, country) FROM stdin;
1	6	1	2011-09-03	1192	Tanzania
2	2	2	1981-02-27	153	Pakistan
3	2	3	1982-06-11	492	Croatia
4	2	4	1956-01-26	798	Russia
5	8	5	1957-10-27	420	Monaco
6	1	6	1953-04-02	700	Senegal
7	8	7	1955-03-19	1152	Lebanon
8	9	8	1934-06-13	397	Pitcairn
9	9	9	1934-10-28	1012	Mozambique
10	1	10	1932-09-12	579	Malawi
11	5	11	1931-11-01	638	Venezuela
12	4	12	1928-03-18	1035	France
13	4	13	1929-04-13	40	Benin
14	2	14	1932-05-17	1191	China
15	2	15	1931-05-04	479	Germany
16	3	16	1906-02-01	1155	Colombia
17	2	17	1905-05-23	283	Vietnam
18	8	18	1909-01-23	333	Peru
19	4	19	1906-08-06	1208	Peru
20	6	20	1908-12-21	342	Tunisia
21	9	21	1908-09-24	523	Nepal
22	2	22	1910-12-05	414	Laos
23	5	23	1908-03-25	996	Mayotte
24	5	24	1905-02-16	649	Benin
25	3	25	1908-04-13	190	Austria
26	6	26	1909-04-07	847	Venezuela
27	6	27	1908-07-18	852	Ghana
28	8	28	1906-04-23	479	Sweden
29	7	29	1904-03-10	709	Panama
30	9	30	1903-12-11	224	Cameroon
31	2	31	1905-10-07	522	Iceland
32	4	32	1880-03-27	905	Hungary
33	5	33	1881-08-15	95	Mauritius
34	8	34	1883-12-14	742	Austria
35	3	35	1883-11-06	809	Greece
36	9	36	1880-09-12	683	Somalia
37	5	37	1880-07-28	878	Ireland
38	7	38	1884-12-09	1209	Bangladesh
39	6	39	1884-11-01	49	Burundi
40	2	40	1885-03-06	151	Namibia
41	2	41	1882-10-13	225	Jamaica
42	4	42	1880-09-10	66	Kiribati
43	4	43	1882-09-25	1144	USA
44	7	44	1884-11-18	1098	India
45	1	45	1880-02-26	780	Guinea
46	7	46	1882-05-25	1218	Angola
47	6	47	1885-01-22	1113	Oman
48	6	48	1885-10-19	827	Japan
49	5	49	1881-05-03	367	Uganda
50	8	50	1882-11-10	193	Lesotho
51	7	51	1879-08-17	1146	Suriname
52	2	52	1885-09-24	1155	Sweden
53	3	53	1880-06-13	792	Bolivia
54	2	54	1885-08-27	987	Guyana
55	5	55	1884-06-20	719	Botswana
56	6	56	1883-11-05	108	Macao
57	6	57	1885-09-01	1129	Malaysia
58	1	58	1881-02-25	1188	Ecuador
59	3	59	1881-10-24	509	Seychelles
60	8	60	1884-07-09	1061	China
61	9	61	1883-12-09	1078	Zimbabwe
62	6	62	1881-08-03	21	Laos
63	3	63	1881-07-10	1065	Latvia
64	1	64	1857-06-09	486	Libya
65	9	65	1860-07-06	895	Bermuda
66	2	66	1857-12-15	285	Jordan
67	7	67	1856-03-13	430	Armenia
68	1	68	1859-06-05	1102	Netherlands
69	6	69	1855-10-03	551	USA
70	2	70	1858-09-15	1002	Slovenia
71	8	71	1855-01-16	276	Myanmar
72	7	72	1856-07-04	661	Martinique
73	3	73	1858-11-27	448	Peru
74	4	74	1854-07-20	1042	Argentina
75	7	75	1857-06-20	349	Turkmenistan
76	3	76	1858-05-10	397	Sweden
77	7	77	1861-07-28	158	Tuvalu
78	7	78	1857-03-25	270	Niger
79	6	79	1859-09-03	283	Syria
80	5	80	1858-11-05	1126	Japan
81	4	81	1853-03-13	100	Samoa
82	6	82	1858-01-09	153	Belgium
83	1	83	1857-12-02	938	Gabon
84	4	84	1860-04-28	917	Montenegro
85	5	85	1855-04-08	922	Mozambique
86	6	86	1859-10-15	389	Togo
87	4	87	1857-07-02	1186	Mayotte
88	5	88	1859-03-26	693	Bermuda
89	3	89	1856-04-14	177	Uganda
90	2	90	1859-10-05	333	Martinique
91	1	91	1857-11-11	358	Vietnam
92	2	92	1859-06-15	1224	Bahrain
93	1	93	1856-03-02	64	Lithuania
94	1	94	1858-07-13	879	Panama
95	9	95	1858-08-26	268	Hungary
96	1	96	1857-09-03	140	Cuba
97	1	97	1858-01-14	320	Botswana
98	6	98	1858-02-16	36	Malawi
99	8	99	1857-07-04	713	Austria
100	6	100	1858-01-26	125	Luxembourg
101	5	101	1855-05-21	711	Kiribati
102	8	102	1858-03-11	186	Turkmenistan
103	7	103	1856-12-20	1067	Angola
104	7	104	1858-05-02	905	Uganda
105	1	105	1857-08-18	372	Brazil
106	8	106	1858-06-05	128	Niger
107	6	107	1858-11-15	329	Lebanon
108	6	108	1861-05-08	801	Moldova
109	7	109	1853-11-05	858	Cambodia
110	1	110	1856-03-23	218	Samoa
111	1	111	1856-07-02	110	Haiti
112	9	112	1854-04-23	1133	Eritrea
113	7	113	1853-05-17	822	Kenya
114	7	114	1856-08-09	287	Azerbaijan
115	8	115	1858-08-09	643	Chile
116	6	116	1858-12-21	569	Nigeria
117	9	117	1859-05-16	1088	Brazil
118	6	118	1859-04-10	460	Belgium
119	4	119	1855-12-09	1192	Aruba
120	9	120	1857-01-22	861	Ireland
121	1	121	1859-03-11	64	Sweden
122	9	122	1859-10-23	170	Japan
123	1	123	1854-11-12	627	France
124	4	124	1859-12-02	207	Morocco
125	6	125	1859-03-21	1069	Serbia
126	2	126	1853-11-17	763	Peru
127	2	127	1857-05-15	1051	Niger
128	1	128	1835-12-24	937	Honduras
129	6	129	1829-02-25	411	Chile
130	6	130	1834-07-22	369	Slovenia
131	5	131	1829-08-11	731	Seychelles
132	8	132	1834-02-16	1173	Yemen
133	9	133	1830-12-26	587	Kiribati
134	6	134	1835-10-05	384	Burundi
135	6	135	1833-04-09	1064	Estonia
136	9	136	1835-05-19	3	Niue
137	7	137	1829-10-15	626	Samoa
138	5	138	1831-08-10	14	Tanzania
139	6	139	1834-12-18	1179	France
140	3	140	1831-03-23	1025	Ireland
141	1	141	1834-12-10	347	Bangladesh
142	2	142	1832-02-12	287	Mongolia
143	9	143	1836-10-02	292	Nauru
144	7	144	1835-02-21	516	Lithuania
145	2	145	1832-07-20	771	Finland
146	4	146	1831-11-13	500	Comoros
147	9	147	1836-05-03	415	Gabon
148	1	148	1830-07-28	638	Guatemala
149	6	149	1832-04-07	1078	Mauritius
150	3	150	1832-04-21	112	Poland
151	3	151	1830-02-21	851	Colombia
152	2	152	1832-06-01	635	Morocco
153	3	153	1833-04-12	591	Syria
154	3	154	1831-04-22	430	Cameroon
155	1	155	1832-12-27	346	Guyana
156	7	156	1829-07-02	789	Venezuela
157	6	157	1834-11-14	811	Luxembourg
158	2	158	1833-10-28	401	Russia
159	6	159	1830-03-14	771	Cyprus
160	6	160	1834-01-20	559	Swaziland
161	9	161	1829-06-20	1222	Georgia
162	5	162	1835-11-27	65	Armenia
163	8	163	1832-04-25	637	Algeria
164	2	164	1829-03-02	599	Benin
165	1	165	1829-05-03	245	Nauru
166	7	166	1835-09-02	926	Estonia
167	9	167	1835-08-18	522	Ukraine
168	2	168	1835-06-07	135	Austria
169	4	169	1831-11-17	182	Kiribati
170	9	170	1832-01-01	1127	Gibraltar
171	4	171	1834-05-28	886	Ecuador
172	9	172	1831-11-14	1196	France
173	3	173	1828-02-25	1194	Israel
174	5	174	1832-07-19	774	Uganda
175	3	175	1832-09-09	1197	Russia
176	6	176	1831-04-28	368	Jamaica
177	9	177	1835-11-24	147	Thailand
178	7	178	1831-04-14	643	Israel
179	9	179	1836-11-03	326	Uruguay
180	1	180	1834-01-09	550	Slovakia
181	4	181	1830-12-14	695	Dominica
182	7	182	1831-05-09	24	Belize
183	5	183	1828-07-08	1074	Comoros
184	5	184	1829-11-24	949	Lebanon
185	5	185	1836-12-27	599	Chile
186	7	186	1832-07-20	117	Tuvalu
187	8	187	1831-01-03	627	Moldova
188	1	188	1830-08-19	713	Switzerland
189	6	189	1831-12-13	573	Syria
190	3	190	1828-11-16	388	Mauritius
191	5	191	1830-11-15	640	Portugal
192	4	192	1833-10-01	1239	India
193	5	193	1834-04-25	30	Uzbekistan
194	2	194	1832-12-13	23	Mongolia
195	3	195	1832-07-26	902	Macao
196	9	196	1832-07-21	613	Egypt
197	1	197	1832-10-25	197	Malawi
198	2	198	1831-07-18	1049	Singapore
199	7	199	1829-11-25	1204	Bahamas
200	2	200	1832-09-03	247	Seychelles
201	1	201	1830-01-21	111	Kosovo
202	1	202	1831-10-07	620	Iraq
203	8	203	1835-01-26	922	Mauritania
204	4	204	1831-02-28	380	Bangladesh
205	6	205	1833-09-21	698	Senegal
206	8	206	1835-09-23	511	Samoa
207	5	207	1834-05-16	712	Senegal
208	7	208	1834-08-28	1079	Fiji
209	5	209	1836-09-08	7	Afghanistan
210	7	210	1830-10-16	510	Zimbabwe
211	4	211	1831-03-28	613	Mayotte
212	2	212	1830-03-02	1012	Serbia
213	4	213	1830-04-19	587	Tajikistan
214	4	214	1836-03-02	604	Cyprus
215	1	215	1830-10-18	249	Lithuania
216	1	216	1833-08-15	954	Portugal
217	7	217	1831-06-19	667	Taiwan
218	8	218	1831-09-23	472	Libya
219	6	219	1833-02-20	881	Croatia
220	2	220	1836-12-02	1117	Zimbabwe
221	5	221	1835-02-16	216	Nicaragua
222	2	222	1831-08-04	627	Latvia
223	7	223	1836-07-24	930	Barbados
224	7	224	1831-12-14	929	Venezuela
225	6	225	1834-08-07	36	Indonesia
226	8	226	1831-04-07	413	Finland
227	7	227	1831-02-15	370	Macedonia
228	5	228	1832-02-21	108	Bahrain
229	9	229	1834-11-11	88	China
230	5	230	1835-08-11	876	Bangladesh
231	2	231	1833-05-19	247	Sweden
232	5	232	1833-07-15	292	Mauritania
233	8	233	1834-01-11	1212	Montserrat
234	6	234	1832-01-07	834	Romania
235	2	235	1835-03-16	469	Lebanon
236	9	236	1834-07-23	318	Nauru
237	1	237	1829-10-10	503	Slovakia
238	1	238	1833-12-04	1137	France
239	6	239	1832-05-08	177	Monaco
240	2	240	1834-07-14	220	Bahamas
241	2	241	1833-05-23	127	Pakistan
242	7	242	1832-07-14	850	Barbados
243	2	243	1829-02-13	1077	Gibraltar
244	9	244	1835-02-26	795	Sudan
245	9	245	1830-05-11	662	Togo
246	1	246	1834-04-08	1003	France
247	4	247	1832-04-24	795	Bolivia
248	7	248	1830-06-19	297	Sudan
249	7	249	1834-02-06	7	Cuba
250	7	250	1833-10-21	569	Mauritius
251	9	251	1833-02-04	1149	Ghana
252	9	252	1830-02-14	343	Nauru
253	5	253	1832-09-13	426	Oman
254	9	254	1832-05-09	612	Iraq
255	7	255	1832-10-01	66	Montenegro
256	9	256	1805-01-18	333	Japan
257	4	257	1806-12-12	1200	Syria
258	6	258	1805-05-22	385	Germany
259	6	259	1807-06-24	620	Aruba
260	7	260	1809-11-04	1221	Tanzania
261	7	261	1805-01-08	1113	Peru
262	6	262	1809-03-01	770	Bolivia
263	4	263	1807-06-17	174	Germany
264	7	264	1805-07-28	291	Ethiopia
265	1	265	1807-03-14	159	Vietnam
266	5	266	1809-10-08	58	Brunei
267	1	267	1806-11-04	213	France
268	3	268	1807-01-04	398	Iraq
269	4	269	1804-03-22	1025	Bahrain
270	6	270	1807-07-22	31	Germany
271	4	271	1806-10-09	204	Belgium
272	8	272	1807-07-20	666	Mauritius
273	5	273	1811-04-22	390	Samoa
274	6	274	1810-09-02	72	Guatemala
275	1	275	1807-01-24	208	Nepal
276	8	276	1809-08-18	899	Namibia
277	9	277	1804-04-22	234	Tajikistan
278	5	278	1805-01-09	1189	Cameroon
279	7	279	1804-11-25	1209	Ethiopia
280	4	280	1804-03-11	208	USA
281	7	281	1806-09-07	937	Senegal
282	1	282	1804-03-04	235	Latvia
283	3	283	1803-06-06	791	Bahamas
284	1	284	1803-05-24	1165	Canada
285	8	285	1807-09-05	264	Myanmar
286	4	286	1809-04-13	27	Ghana
287	7	287	1806-10-23	643	Yemen
288	8	288	1809-09-06	358	Mayotte
289	6	289	1807-08-20	1082	Myanmar
290	1	290	1806-06-16	253	Slovenia
291	5	291	1809-04-12	992	Yemen
292	7	292	1806-06-12	635	China
293	8	293	1810-08-22	161	Mongolia
294	4	294	1809-05-09	63	Barbados
295	3	295	1809-07-26	1188	Montserrat
296	9	296	1807-09-06	936	Comoros
297	7	297	1804-10-20	1213	Angola
298	5	298	1810-05-10	34	Aruba
299	5	299	1804-01-17	851	Brunei
300	7	300	1805-12-13	411	Turkmenistan
301	1	301	1806-12-15	1106	Ireland
302	6	302	1809-11-15	289	Martinique
303	1	303	1807-06-05	481	Gabon
304	6	304	1806-01-11	942	Turkmenistan
305	5	305	1803-02-28	484	Mali
306	7	306	1806-12-06	231	Mali
307	3	307	1805-10-21	1090	Iceland
308	4	308	1811-10-08	451	Chile
309	8	309	1809-11-01	512	Belarus
310	6	310	1806-02-26	54	Seychelles
311	4	311	1808-09-24	848	Belarus
312	6	312	1811-12-25	116	Hungary
313	3	313	1807-06-21	1096	Comoros
314	1	314	1804-06-23	725	Ethiopia
315	5	315	1804-11-18	920	Australia
316	2	316	1806-01-11	223	Moldova
317	2	317	1806-09-11	680	Cuba
318	6	318	1808-01-09	516	Moldova
319	8	319	1807-03-26	483	Belgium
320	4	320	1809-11-14	185	Iran
321	7	321	1805-04-26	617	France
322	5	322	1808-01-14	155	Hungary
323	2	323	1803-01-16	593	Dominica
324	9	324	1803-12-03	581	Bhutan
325	4	325	1805-05-10	78	Comoros
326	7	326	1806-04-10	697	Portugal
327	7	327	1804-03-22	91	Yemen
328	2	328	1807-02-14	602	Indonesia
329	7	329	1806-05-13	661	Oman
330	6	330	1805-06-23	72	Turkey
331	5	331	1805-05-07	526	Vietnam
332	5	332	1809-08-15	758	Dominica
333	8	333	1808-03-24	1141	Afghanistan
334	9	334	1810-08-09	393	Syria
335	7	335	1811-09-25	566	Nepal
336	5	336	1805-12-15	99	Comoros
337	8	337	1803-11-02	197	Ukraine
338	4	338	1810-12-23	728	Albania
339	4	339	1805-06-13	532	Russia
340	1	340	1809-06-18	1078	Ecuador
341	1	341	1804-11-26	1208	Kosovo
342	6	342	1808-02-05	874	Burundi
343	9	343	1809-07-08	349	Kiribati
344	5	344	1809-05-07	186	Georgia
345	9	345	1808-06-21	340	Romania
346	5	346	1807-11-27	1167	Niger
347	2	347	1804-05-09	693	Estonia
348	7	348	1808-06-28	863	Mongolia
349	8	349	1808-10-13	1224	Sudan
350	5	350	1804-04-02	1235	Djibouti
351	5	351	1804-04-13	1198	Peru
352	7	352	1809-12-04	1154	Greece
353	2	353	1807-09-20	612	Pakistan
354	8	354	1809-05-25	220	Botswana
355	8	355	1811-08-23	613	Benin
356	8	356	1808-03-14	1152	Pakistan
357	7	357	1809-01-22	757	Colombia
358	4	358	1805-01-25	189	Zambia
359	8	359	1808-01-28	201	Zimbabwe
360	7	360	1805-05-07	536	Austria
361	1	361	1806-05-12	661	Malta
362	2	362	1808-10-03	847	Sudan
363	4	363	1809-01-04	16	Laos
364	5	364	1807-05-26	518	Senegal
365	8	365	1805-05-08	57	Lebanon
366	2	366	1805-10-01	1114	Tuvalu
367	1	367	1807-12-17	1037	Liberia
368	3	368	1806-08-08	105	Macedonia
369	2	369	1806-09-17	927	Bangladesh
370	6	370	1811-08-11	566	Honduras
371	4	371	1808-02-09	165	Turkmenistan
372	2	372	1808-06-12	1121	Mexico
373	8	373	1807-05-19	1137	Honduras
374	9	374	1807-10-03	618	Palau
375	4	375	1810-10-05	410	Mexico
376	1	376	1809-12-07	500	Mali
377	5	377	1807-07-24	1118	Ukraine
378	5	378	1806-10-18	478	Poland
379	6	379	1806-01-18	491	Aruba
380	2	380	1811-01-06	985	Bermuda
381	1	381	1806-08-11	289	Kiribati
382	2	382	1809-03-23	182	Mexico
383	6	383	1807-04-23	359	Vietnam
384	8	384	1806-11-14	1137	Libya
385	3	385	1810-06-23	942	Kosovo
386	1	386	1805-02-27	1208	Azerbaijan
387	4	387	1804-08-06	1178	Estonia
388	7	388	1808-07-12	1111	Niger
389	5	389	1809-01-09	1098	Ghana
390	5	390	1805-11-23	276	Belarus
391	5	391	1805-06-16	928	Thailand
392	4	392	1803-06-01	513	Armenia
393	9	393	1804-06-10	2	Comoros
394	9	394	1804-06-05	1102	Colombia
395	6	395	1804-06-09	1040	Nauru
396	3	396	1811-03-27	750	Austria
397	4	397	1804-08-05	747	Bahrain
398	3	398	1807-03-02	1144	Chile
399	4	399	1803-06-01	251	Afghanistan
400	5	400	1805-10-26	992	Belgium
401	4	401	1809-08-22	224	France
402	6	402	1810-10-14	15	Cuba
403	3	403	1810-10-15	852	Curacao
404	6	404	1808-09-22	91	Tanzania
405	2	405	1810-08-16	332	Spain
406	3	406	1808-09-02	514	Latvia
407	1	407	1809-09-12	185	Monaco
408	6	408	1807-09-11	435	Samoa
409	4	409	1810-12-17	796	Macedonia
410	8	410	1808-08-25	1117	Bhutan
411	6	411	1805-04-21	770	Samoa
412	8	412	1806-08-17	1250	Brunei
413	7	413	1806-03-03	681	Laos
414	6	414	1809-11-06	460	Lithuania
415	5	415	1810-05-15	139	Croatia
416	6	416	1810-02-27	223	Haiti
417	2	417	1806-01-09	459	Palau
418	5	418	1804-01-22	380	Suriname
419	7	419	1808-04-15	369	Swaziland
420	6	420	1805-08-26	1079	Jamaica
421	1	421	1805-11-21	975	Romania
422	4	422	1805-03-07	102	Tuvalu
423	3	423	1808-01-16	9	Greenland
424	4	424	1805-05-25	47	Cambodia
425	2	425	1806-01-17	9	Curacao
426	2	426	1807-07-18	941	Bahamas
427	1	427	1805-12-01	394	Botswana
428	6	428	1808-11-19	1151	Liechtenstein
429	1	429	1809-07-09	100	Honduras
430	5	430	1811-11-13	1175	Nicaragua
431	3	431	1809-01-17	770	Estonia
432	3	432	1809-08-11	766	Suriname
433	6	433	1808-03-17	72	Bolivia
434	5	434	1807-04-14	494	Kazakhstan
435	8	435	1805-05-17	432	Tanzania
436	5	436	1809-08-15	1149	Liechtenstein
437	9	437	1806-08-05	421	Philippines
438	3	438	1808-11-06	1182	Russia
439	7	439	1805-08-27	936	Benin
440	7	440	1803-09-03	1183	Cambodia
441	1	441	1809-07-28	145	Jamaica
442	2	442	1808-05-14	622	Bahamas
443	1	443	1809-02-22	847	Swaziland
444	5	444	1807-05-16	649	Montserrat
445	4	445	1808-06-11	1250	Belgium
446	9	446	1804-07-06	1158	Barbados
447	8	447	1803-12-20	190	Greece
448	6	448	1806-03-26	1213	Hungary
449	5	449	1809-08-20	416	Azerbaijan
450	1	450	1810-12-10	801	Lebanon
451	5	451	1805-03-26	224	Afghanistan
452	2	452	1808-05-16	7	Estonia
453	1	453	1807-11-19	876	Armenia
454	2	454	1806-07-11	328	Hungary
455	6	455	1805-04-26	276	Estonia
456	4	456	1807-08-05	386	Singapore
457	4	457	1809-05-17	231	Lithuania
458	6	458	1810-04-26	994	Venezuela
459	2	459	1811-11-27	145	Albania
460	9	460	1808-10-16	312	Nauru
461	9	461	1807-06-26	1043	Georgia
462	2	462	1807-11-25	646	Samoa
463	9	463	1808-02-14	653	Bahamas
464	3	464	1808-01-05	36	Uzbekistan
465	7	465	1806-12-11	736	Norway
466	9	466	1805-02-20	933	Bahrain
467	5	467	1804-10-11	68	Ireland
468	7	468	1805-03-17	767	Dominica
469	9	469	1806-12-17	627	Libya
470	1	470	1810-09-24	53	Chile
471	8	471	1806-08-02	521	Slovenia
472	8	472	1807-04-24	69	Zambia
473	2	473	1803-09-20	253	Botswana
474	5	474	1806-12-01	340	Afghanistan
475	5	475	1804-03-23	881	Martinique
476	1	476	1806-06-16	1182	Guinea
477	4	477	1807-11-11	913	Kiribati
478	5	478	1804-03-02	15	Kazakhstan
479	4	479	1807-08-19	626	Bahrain
480	2	480	1808-06-27	280	Mayotte
481	6	481	1804-07-08	844	Yemen
482	7	482	1809-09-18	859	Fiji
483	4	483	1807-10-22	1005	Tunisia
484	5	484	1805-04-20	310	Lesotho
485	9	485	1809-03-01	464	China
486	2	486	1809-11-01	615	Tanzania
487	6	487	1808-11-04	290	Zimbabwe
488	5	488	1806-10-22	343	Uzbekistan
489	4	489	1804-10-13	140	Niger
490	9	490	1808-11-24	664	Kazakhstan
491	7	491	1804-06-22	575	Malaysia
492	7	492	1806-06-01	808	Macedonia
493	5	493	1807-12-05	695	Iraq
494	7	494	1811-08-13	459	Oman
495	1	495	1808-09-04	839	Guyana
496	6	496	1806-07-07	705	Honduras
497	3	497	1809-03-17	586	Oman
498	4	498	1810-11-14	580	Cambodia
499	7	499	1806-07-06	621	Rwanda
500	9	500	1810-02-26	693	Turkey
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

