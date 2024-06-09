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
    id integer NOT NULL,
    date_of_birth timestamp without time zone NOT NULL,
    date_of_death timestamp without time zone
);


ALTER TABLE public.people OWNER TO admin;

--
-- Name: people_id_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.people_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.people_id_seq OWNER TO admin;

--
-- Name: people_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: admin
--

ALTER SEQUENCE public.people_id_seq OWNED BY public.people.id;


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
-- Name: people id; Type: DEFAULT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.people ALTER COLUMN id SET DEFAULT nextval('public.people_id_seq'::regclass);


--
-- Data for Name: accounts; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.accounts (id, login, hashed_password) FROM stdin;
1	user1	$2a$06$ZcuTc/Oh5ZqrgHjIitU11u4905sWJozn0a05oUwMndv.ZHRhO1DMS
2	user2	$2a$06$HvGIL/X1loyGD/Fmp3Sc7O6MoQlrxA3U1Rn3Z3M6Nwy.QrFtPteIG
3	user3	$2a$06$qe/EJ7.V4PhZ0Uugrz911.F/WXE5O3IPNkx6au9qR2.2UaMDsnO2m
4	user4	$2a$06$VyHhup9Um2kTEmqdH7YxBO2cmv5nucZRrxiLwER.djahI3BxLA/o.
5	user5	$2a$06$2UN951X.EVHe/CC1B/nSuubl7luw6yORtUt0Drle.iMqa7e0Lzppe
6	user6	$2a$06$T7r9FzBvzcCgrsyv037uzOJBgjzApchJebvbT7xuPZTKJZ7KYKf2W
7	user7	$2a$06$vhWhY/LegzZB76whnyDv4.XHEhizWs1D8fp8IhNizFP68lnuGUi0q
8	user8	$2a$06$Tz2ERXIMd2hGOjiUD3tsGOQ.HgwEzqr7ei6fyYEORyXQWDVhzEM5O
9	user9	$2a$06$MNqQ8cvSGVXxIxp9VcyeS.kBwBR/ZlO9tD3r3A6x8eKh.3meg2uGe
10	user10	$2a$06$mwCbaDXOW8ZD2KMb1QKDiOMO6ui3q08tZc.TKUaa9fiHZbDpEh8ly
11	user11	$2a$06$v.d0LISlkWxsRnKiGJaa2ON8VWFYmHu2O7pTSfrzsdvTaw4gbfkQm
12	user12	$2a$06$sdk4TEoDMaeoDFTzDIRKu.0yBfSMPnPe0gkSXe3cpz6uJgykPpWtO
13	user13	$2a$06$mV9suq8T5Zik3254HVlegu9AeKtkInL5JN6uSdMV93CoSkHELKfWC
14	user14	$2a$06$m4Q2mIb97AI4W6ZxZkV8CePHO8xwaEuDQbagqce/MCXDaQF1QHfze
15	user15	$2a$06$NKyPcooXnO3Bf7FIsr6fFOaNaL.HXkA5g4YXJPqZ3lrIWBz.Mg.Pm
16	user16	$2a$06$Cw4lB9JqKWZ3qQ7s/jFp8uEyXqv9abIBdJLkbNU.kuEF4T2NAUIKm
17	user17	$2a$06$U9FsaSE4CxUszzOiAbyiS.QwKkWj3ZclAcIS7Q6fqdLFOoelFnXiu
18	user18	$2a$06$6k8USFiEA88tZgXCzkyLpOPb9s9eWLwNzLLmO8zwq/4zJTgEsmDRi
19	user19	$2a$06$77mNzUJzVRBSEU0dxai/LOMiJS5C2j8p7dtpmgDE3hLq4i5szD3ne
20	user20	$2a$06$thpqMBPhpN8px0F2Ebsb6eSwP0n/aieQ7rTQGApsGZDwp4ESDS8p.
21	user21	$2a$06$T106TeZMWges8.IBdsHdCev9pqDHe0.p35bxf.Sd0FSFpI0Aq37Yu
22	user22	$2a$06$4ZE3.he9l4R2mFo9ZY29NesBHDpOJqdGyZeNGEO2RIqe1ibOruczG
23	user23	$2a$06$f8TaPAKGMPZwQcAZVYotMOzq/RfCUx2D5ZL/YxodlzIz2dE.ipOFC
24	user24	$2a$06$N9cCnQJTaLqHdEdU6h7jt.W1yEAGY7DBWhATFZ5.V0RKuIEhbU93a
25	user25	$2a$06$oiqsf9NGRWGhOkK8k2Aqm.SzJRlzdnkXCC52CfOuNGc2mL8eLKCu2
26	user26	$2a$06$Kx5MZ9JF3mDVItUoAUsK/u1FvaULwcDM/mzqZIZbvNUdruL5dWp9e
27	user27	$2a$06$Hd03X/E/FGK0qb3GpD4ILeHjN4V7wzwGo9aNYkfHr68ZMMIEGc.B6
28	user28	$2a$06$D7g0vhFHzJX3xsV/h9kNS.v4GBn0x.Jg.ePkfwj6W3LJjVAHNZzn2
29	user29	$2a$06$vvzOcJ27hrGNXLoZzrc2xu3.XSje4xpPY4NfzqYGa/drs57FMQyG.
30	user30	$2a$06$LB860yqndVA9ougrU9iO4uDq4JDqYfEWpgztteVd90LPbLO12JTq.
31	user31	$2a$06$j0czmt9nMQVy66kfZxPvjOvFHdCSsbRit41S8kdzXZXPawK7VIcCi
32	user32	$2a$06$0qRuHBU7m15vAMDFnPde8e.orHbaOCVUZ1G.CoPArGlmz.cXgaFuK
33	user33	$2a$06$qJ7sBorONiEgT/mu/MV0PePD9viIscDkhHe01U53OVrHiUNEMyUse
34	user34	$2a$06$OfcW7JHSL0qmiHhvrVQ05exAd5jDeVWRdLnh7XU2jkK7NgE6qnAiq
35	user35	$2a$06$fv18ryURIXat41ofwk8jXeMQnZWl2L38.b1ZeUwyWJjKb5j2iQk7e
36	user36	$2a$06$n3doM2jNRY.trPnJDr0S2efYbhtJDLkkS3je9BHMCMRdi4.W23E.q
37	user37	$2a$06$./PpxmD.MGQG2cG1VKG0ceJyIMJ6TAyprV2yYzvMTCgZItRaOGoFa
38	user38	$2a$06$fLeWplOUjD.O7OJUg7Dyeeiff/tFRVveUY9vQAzhPS/dDKaVBQczq
39	user39	$2a$06$t.2FNOROVaD3B3a3OrlLY.dURAGfzcMpNEK/.zZhbYaQqxmX.wQKW
40	user40	$2a$06$R1ic96dKKBqIp7XKBN3N0OmNjYfFOBR7Lgn4kkrZ0.wdo3xRR.yWC
41	user41	$2a$06$ZpH98rvI7b7Le1dVecMIEesAaAPvHuuuoME7RIuYbbwtsDjgkWeSq
42	user42	$2a$06$uUO/IfeK1AXaGc6VhkARtuujeWa.xKkgMQRQZOqRf2vn/lyMrypdq
43	user43	$2a$06$HQeEFYQn7Cc2zywup/k7auqR4t5DRFt2P/.iwzK25DZJu4ZCpJ2RS
44	user44	$2a$06$S15gkAVGc4w7O26OdnJVhuEHp89KMJMA3Wbmf4uwcvVtE/f0fGMPu
45	user45	$2a$06$UMFILFF6IETEzyE24h3yvOQJS5ENhKOq08hY1YssRqDx9VCYl5vjK
46	user46	$2a$06$w3yHzkXxatunIYE30Or.6ePC5EJ9Ylmsv8T3WD1oX/xGSPL7dPVrm
47	user47	$2a$06$7spFN1dryeuT7Y6yb8gj7.lTsFsZ7XrKgDGQM/OddUob2x23R4Jjm
48	user48	$2a$06$5RRPUNXFMeDzfagImYNxtuZkQyVo.52761BamBRvo/pSHe4cbsTOK
49	user49	$2a$06$lnDT6sLH4lH7n5l/TL.gKe.MazzN6opjXt4rYmQ0cTmr07uBjA3.e
50	user50	$2a$06$Kv8avdlMk9MAKPxq/5HoIO0ExcGWNNvD7t3tjHuh17NevqZKUfF7W
51	user51	$2a$06$1PzWtzig1Ghz800LdqvTp.nTgY2lFDdScAAZWqTGYNYVe9uH2u9/y
52	user52	$2a$06$8G/qGndRWK2XBzxd5Wplie1hp7RPeSAkZKnMkVCP3.5keQ3Ut3v8S
53	user53	$2a$06$FHG15kxoMGSnGP8iX4QcJu2uMqeb2eGIKbPwOYtk9N71N8WudIsNm
54	user54	$2a$06$nqBEtOOWbssjFA.SJ3eIseCDdUu145p5VNxAhHqwXe38w4LluZmt2
55	user55	$2a$06$cX.dwTc2pOk0ay6QGPWzLOL87avHzy/NbpGOP.e48up1dD4C4.QkO
56	user56	$2a$06$Yz4eNPXUhNbDBVpnr6Ns5.sqLR3f5TKYZvzbMuyjMt/Q4uivTS5Fq
57	user57	$2a$06$AUUjvSLvdnEZeM3j0BwAJOy/VSMCQJ9BTAjQYIJcKqdHyEf74BazO
58	user58	$2a$06$KLbti96ZY0jURWjOAdvr4.4.8wvDgyvcStxE.sbk9GoiFRtCpzuIC
59	user59	$2a$06$6ofWvUj/BEGwwOPwBNaC8elDWRgHBEMXOdeT57pMrZQjeX2kPJYO.
60	user60	$2a$06$Nsm26rAf9X7dGQ2m4qboe.XZ7zIk4aGs51pMPAb8l5YfQsRmYE3xu
61	user61	$2a$06$36kchU1yzTGJAvzs2//PEetNz5n4dYBylLYEb66WSOIy3cyiYH/bi
62	user62	$2a$06$eXjGxLv7wCGLGh7CWEHu0u3TQxjjeNe2iW75/izuNqGW9c1W1Uv3C
63	user63	$2a$06$sQdPPBYfy0rcKz98tyHUyuT7oNjakXY31NGAm2X8FwHR05xxZqeUG
64	user64	$2a$06$mrknHLCGVnA.0C4Faeue4eHV8btJyqebu8peuCyB1oA7NMahczWfa
65	user65	$2a$06$u2fng8vomWv/WBz2PRLvlOq8khWm1V65I/ZB/Cs5S2dTrcd7lN.m6
66	user66	$2a$06$CmGgqulnBdaQRNLt0k6mTuf63Hg.klMnubGKGRuEEerk19GK9y36i
67	user67	$2a$06$E8QvAblPb2O8eMsIPrPbrO1xOXQOwAlrrR4PUg4BIXs0OEP928mxW
68	user68	$2a$06$tK.bm9Q9LMbvJIRZ8Thk3u4FpqKSOupjmbfa0DsJ9aiMoF5w.nMv2
69	user69	$2a$06$JW8tsRMpQrqCY9gZQKI3mOAIhQW288V9aYC5sx1UGFBCqOSEDh7CW
70	user70	$2a$06$BZHpxGKKVY2ut40dj5Px0.LfGZBo/jeHtMJ6zIlS7lJkrNgQx41aq
71	user71	$2a$06$PhXbpsr7gQMkxT66c1FeAeq2MYTy6sSa1yqJ/keB/y16XldlRK4Ai
72	user72	$2a$06$PscS0tSn29KderLxvlMmje7L6L1bD4VochBjWzpF4lsFkTVbZvPSG
73	user73	$2a$06$kiKpdqiGt5mkdEaTHtl7rONgtLIRXudQ2aNJuaIYaEUgrIETW.X/a
74	user74	$2a$06$bkVq7ADgQHwN1.aYeZRMjuyoCxDdkjIg6hJq.7tkbVG6CfgVz1.8O
75	user75	$2a$06$6vJ8SCg0XG3LU0KOslPKk.3TpOFPWPKvRBddfcGhcfSX6uVeXCczu
76	user76	$2a$06$fAMx/hH3Z3KCCxbYXlG7f.bVFAn4Gl8t4YWSZUReWiJ.RGvhFp4IW
77	user77	$2a$06$7RX4URYIaRKMA555nEdigOx0gn2I6sFJtqbBNQW/qi5HWsH7Oxkjq
78	user78	$2a$06$3P7OOGWByVmwFo3xzN9C2OY/mjTjnUlTBVDSQH4y8r8HgvuEhFXoq
79	user79	$2a$06$WIXgfR.6D9BnljsRomQlX.8/N2D/gLACqXTv9I8DKWdS2nOXQs1Gy
80	user80	$2a$06$KSKGgEMHZ685z92v4B01hulSLvebpSEtHpwqIrBh/LZmiIpa38E1K
81	user81	$2a$06$facTV3c7ZYtpLCB4HEjl6uXX0OHHBN0aEb1OBaYwvnaMNE13o9Gpu
82	user82	$2a$06$Msc82QyYy1MtEQvO8JOBp...6B7vOTLVAZq3PtRa7NPGC.VBsOu7q
83	user83	$2a$06$q5Y4FAOzdfXRWI1AmMRFSudli29EeAvSZa0eav1QPBrMVt4eYlDq6
84	user84	$2a$06$oW3gqL3QyAn2ZgVBTxVic.V6sSGm0mG6ZRnyQW5gWbWZa7z0PXWrq
85	user85	$2a$06$Tatl/1ITZ3P7WgbBweIijeYN6noJmUIT/Wa/IFIc4rSMlUL9/yyOO
86	user86	$2a$06$OUVm7O5M8yDqRgxHWSMvbu.2LJvv/y.I6G5BxLq3S2U6c20HDFYfm
87	user87	$2a$06$R5FKEj9guGmKZac3ezX7QOx97WfGFgAvpl4.1eppcqIYwMsRYR8Zi
88	user88	$2a$06$.VUtki3ALpDQRyIjWNCKL.Im8yfTwyd4ivHyB9BeN3N2vDmEmZUUy
89	user89	$2a$06$VexoNbf7fxxP.5OsqhYvYu0hIfyMulHjejv8rESCRzhp3RVIOTMQy
90	user90	$2a$06$FbqIrLk/KyxPs0Fcse.rmePlw8dAYIpDzwiD6XU.lUQZ.L5.1yO4q
91	user91	$2a$06$XC9FO7VaMBuYeTBLGqLgT.0uy3zhOJgq.K2prZAAzE0mQZ9IUJh4S
92	user92	$2a$06$NBvGvmvd79JqvAHNuDuwd.pBKYEk1fc.XZiTrpPvAV3DVJ3qU7Jxm
93	user93	$2a$06$PEyoTAmw6w6F7JhGXV5iNO7TFuFBfQshYV7j7xddDWnXTWBof6J5G
94	user94	$2a$06$nmQlviNuVyt2J77uKv/UhOUcw3h/kPEWsAYxuCelDRV8zX4.hnf5m
95	user95	$2a$06$pr/lN8rozaCu1W.AlmG/iO82UzQuqiMKINJl2ODiATPjIyIHOvI5u
96	user96	$2a$06$bMt6oei592fKDQWDY5VviO81rV9ERITG9O/uSaO65pfvTyYqCgskW
97	user97	$2a$06$qA2fVyLExaEVJ0EySp4uhugV0Xrc5xy0v3qxhqe44dcesaujwDGhK
98	user98	$2a$06$CfV.xvCFWQDMQHgwCNYCPupsFBTTNnFfNbpA2WYubYeGn7nwS5sPi
99	user99	$2a$06$KHNmmO76quVame7G78Js5O6NRldtMhlnn5UXpwNUVwMDcK2zUTn66
100	user100	$2a$06$udwzzS0uPMTF4OjT9k66AeDIEyifIVxJ3OvcoiB2aJ1iunwJ1dhyW
101	user101	$2a$06$jL2MSOruN9GbKp7Lqj61xOYp94iQzS1tLyjdU0TCoMRHFpFoAJjxy
102	user102	$2a$06$uD7scxnWmFAJoQIShMaLAucGWWKKjnHIHzR.cBxFuaAlnDeL9s27S
103	user103	$2a$06$hIxHmsJU9AHq2UmnL7fRtOqtjKaREN/WRDeH5qmXdW75Ehqy76uL.
104	user104	$2a$06$gHhRNJFBSbmaQlMVrhLDVO72M8xueiFX.e7UOpHpTnq98mf8idY6e
105	user105	$2a$06$pn.3GmuCQnkUDTPY.Sp4VuHMLPE/t8rZccZCIDEsoPJoUEFTT.Ckm
106	user106	$2a$06$NClLR8b8oybU2cAyGY/VVufx1d.vogBqZwg3u.d3LoskTK4vZsQU2
107	user107	$2a$06$pHuGlxcoAKz5TJ8KpuEXkuEpZY82LJxQaFmuH7.bUGLUW..vbptgK
108	user108	$2a$06$M1KVH2P6shrtrrV9V/31vehSEUTM4B7A4h5TwErZfrSono51QbM4e
109	user109	$2a$06$gQJu3vql9.vKUh1vTZkEO.QlpAaSScYTGVbCkv2dldwtAsQez7KgC
110	user110	$2a$06$AP4YsygAgy00olBftVvNCOVclxrPnIzXdFojWa9qqGzcKFZfabHv2
111	user111	$2a$06$VedixnJ7qZIzLqlrU9lURe7E0L8rBaXOrwSRru2uNJkZ1mIIeQxUC
112	user112	$2a$06$RDCrqhYmpMliIG9UKo5RM.J2j/YgacNWJ4YcEJ7apwbZf5G/T/Lny
113	user113	$2a$06$gmSGL2SNwXqI.O6YciihceJJi131aMG8Ouxdy0e9G1w7HqLba2.lu
114	user114	$2a$06$vTNgXZrX5ew0TnLTYbywBuWDO6QSCyTqyvq6ko3yzGBICKw3d/ZO2
115	user115	$2a$06$NxC7FwhhtVZZd1yxMw3PN.hwIkuGXThNwoic4BIVpZLKp4Qm8E082
116	user116	$2a$06$VOlSaOe/f3.LVyNn1J1Ubu0lVXwh6rRUxJ4eOtSLF4URA.aHQoyeW
117	user117	$2a$06$4Fyd5lZOKhr4MONyClswJOnyjo6qztcKOlrVM8gD5Y5EyJknCPGP2
118	user118	$2a$06$MXl9mRBglM7Eu2JR7BJ7iuqfBE2F0uOVOjAFFQnWcUxPHBiNRx6nS
119	user119	$2a$06$rDnfrq/WsYHUXk0sBg47yujLIxyOcd9IweAqogs.sDGs2tuRFzJom
120	user120	$2a$06$.hLNKzZAAQvk.LKvSpTBgu.ue5SYSTTw1XAHt5Ls0JFDmFgyK3YWq
121	user121	$2a$06$ukVXe4nLco2h7.xmzBA6V.TOAcoiwACvU.n9mt8uNF8X/1T3HD3PC
122	user122	$2a$06$R/9mjHw58BadL6wOMPjyyOFSE/7z39k.a8KokFxjHEMF/uhgV/paa
123	user123	$2a$06$DekCMAkX99afGwRw6WnLVuyIgPuq0XKfDeoPOOmQPUGw2SqxKw0Py
124	user124	$2a$06$QNAI9Y4imdO3923h06cXMuxVo2E.BJv.HmSAKPbIq7YwNykI6s1t.
125	user125	$2a$06$HYxEISKd8NKfwJZxdnSLBOAMFVHx9xDIUjesMYTGdX8dl5AFYWsCO
126	user126	$2a$06$df1h6KsY/kG4UnNZzZAceOsFjcMYYiyt6yZmrxtJiFyKZnww4GqH2
127	user127	$2a$06$HDdExepPjibGrY.anZDjO.cP59z8x/srriO3dH3mfiB7o3Qu92ISy
128	user128	$2a$06$dp8uJEQcOCIVQ5nEaLzS/e6s/8GZhjZCKDfILCf/.ZxYRlJ0Tkfa.
129	user129	$2a$06$HyrhjbtaP33/VaNsSmR1Y.wBvBEsD1ywp8bI9xrwV2AROp9kPTIga
130	user130	$2a$06$d6ssWdB5MszaRYERITSQAOq5.kILZheIR0GBm1iegWPbqoxmISrT6
131	user131	$2a$06$/BCLQMcS2WG.du9Xz0J6luEdm7chlECb4Bu9BKnIljS/qGHl1HcdK
132	user132	$2a$06$17AoM355vDc6T09v7/q41OLjOXO1A9EhRQtf6FBwVV1Ob7t7q7SFq
133	user133	$2a$06$24ohuW24g8R1BdrXS4lYx.4es5g2qdpMG/qklPUty53JwrLWpu66i
134	user134	$2a$06$QPEGusee5V06ZVukC/P8nuLPIzZ4V.tpsuSQsPkAXhObWq1KDD2vm
135	user135	$2a$06$4cAAuLheTHEoSaMAkJilseKsArbgnVQYl.5H8OkuXq6zNtKBBRIlK
136	user136	$2a$06$bSyKDEgzlNd5sEE2a/c0u.Fvvq5QWLk3J2Vlg9cK.won9YiOOJxDi
137	user137	$2a$06$eCXA0IMvuydShrqyRVYBuufXcq9sIJZyndG0GCU1eXdC5YgMcwK6W
138	user138	$2a$06$kzDkmSltEC/zIhUruL3h2eoHOb5varEU9m0UqrnVU2aMbG4dF5fGq
139	user139	$2a$06$PLp5OTwz/dNjmZFtCGDsYOsnzZzb8KtTM0cwNDsYh2zaI0oI/BjGG
140	user140	$2a$06$Fw.E.NUUa0OLhHfRfKdDGeKBqtRsfBqaegoQko2AU0An/K3Iu8mh6
141	user141	$2a$06$seXQQQ7qnto7smKhg63esuUjQtdnb8Tgq1JNMa78qPrpJHMZrcuMK
142	user142	$2a$06$EduFXOGpZCtr6gyhAz1xUey/twXmobT7ikcJ9eCNlfcoS/av.v3VG
143	user143	$2a$06$WQvloEMKY2AjZAtpGYcZ/uhAqOiu1Z1G1EeM0diMozGFgGz9VKRru
144	user144	$2a$06$F4AIAizcseD51pc938eOD.yuIqN12MaBAIhisWIl5A.hyVzkdXRXO
145	user145	$2a$06$Oej13ApF7PWSGPIfRWdY7OEDAzzvpEMlUP52oUBVT85qIOmQN7/Ny
146	user146	$2a$06$yemyCrVi67Vh49WDuCqp3uITjBboL70zldcQMsS3.0Pf9ktzEJvX.
147	user147	$2a$06$bxRsx8FGD9o.uQIKE0OfnuxBMQGSFrCUUOMjMoC24D/SrCsGjMxOO
148	user148	$2a$06$Tl/9UJ5494Lrkj9rwVgK6e0VK8SXx.vlS3wukmNdfeIa6mTC6pdBq
149	user149	$2a$06$bti3SfBiwdEo2Jg35LQQ6ulllO96eKwVUqujq.NNTqmAEtXT5S6JK
150	user150	$2a$06$pPq1E1w0Z9bnB3NINGu0DOPqBQzjqSrHV1oi3V.UpOyxqc2iKNU7m
151	user151	$2a$06$ptiL9M9qWHFql0nBkOnDUO7408.AwqduRr3ql9bCXlehl/aKXGwdC
152	user152	$2a$06$6fFBYeUmC2aTZuUI1hI5K.kUfRBMEBgRyeynkChi3KJ16rM6O3rG.
153	user153	$2a$06$i79eCPmXxzQzlsXV79oP4uHb/9LU8aqehSE/Li.Z.SzqSUEbf4awK
154	user154	$2a$06$NxV.b/ksQndIfwH6s.VKvOsFvKlGDBj1zGWcoByURusxdfh/Oql96
155	user155	$2a$06$Nhmn94sP6FG47M92FzCp3ulsq.Aj02m2BUdaegEKpWeZsEaDTKeYG
156	user156	$2a$06$Tgt5eAc5W2/gDnLF5tn9pOGsszCd0XlYG678YH7vXI6SdtaEPmBVO
157	user157	$2a$06$lxSANXmx80GqHl0xWC/kWOW88VFVRiTc6N9tglBWNWw9gjrxkKZCi
158	user158	$2a$06$qSRxnsE1OEHxxIutFDONIu4EgZaBcmmhGIUvMtVpmfKt8Yes2BA3q
159	user159	$2a$06$z3PjkTTsX..I5334NgM2TeoVyL9pX3bvBAiey0T1ZXpdCwSvNe8IW
160	user160	$2a$06$oOMM45j6TAQaFSn/CnYwB.Pitkt35pG91xl5LjP0N.PM3wMzgS4wm
161	user161	$2a$06$l97Z20LL2vmH9En4CbvLFe.k1S4AEft0FKlEdMmZei4ruwiO.Jdha
162	user162	$2a$06$Arq7Pjd5KBGGLUFMDKKS5utLsCh3x1uLuU3D3CvebCbpCERXnOQx.
163	user163	$2a$06$E4.lYJmz8gaBthKMQhwQeedllrz57qxz1/B/BvhbPlIIXT9XlMzQa
164	user164	$2a$06$o7lBc05KoxbirhJZWubRc.AkrAcBoIfxjBgZNPe9gD3WQ8TTQtbzS
165	user165	$2a$06$C5rFAJsxYqoxHbLygx/Heee9jqc/T4yKoZx8PYssJddinmsTKRy9O
166	user166	$2a$06$AkUxy1oFQdKhCsLb6f1LpOyEWkIcpdME0Px4.GwcPP9wcUBn2heEy
167	user167	$2a$06$X/hQv9BHzb2oRAd6Qaj7mOww5I1k/hAtt0RpmBNMhxqbVvbdvcbhW
168	user168	$2a$06$apTOoHR8tI0sb9b7LIOXYuIt3rDgVRdOJDAAWCLNixq5jL4iYw2Ui
169	user169	$2a$06$Zh419qC9k0PhBqhcYaVR4OnDArEeK65txKcN2t7LDaS0bjXkU52Dq
170	user170	$2a$06$yVX1xnxruNFUVpcv8hyM3OS5xxqw7CjqN.HshDxHXyQewska0Ty72
171	user171	$2a$06$5qL6lpDR3CySeJKUmJcPU.LfdVUwpyTL4ofCJJK/TA4HUv9wXozGK
172	user172	$2a$06$fbGZaDRrbTHJ5Fm2p.0QUOStELFwQr3zS.4nb5C6nx8WVFdnXw/u2
173	user173	$2a$06$r0h4Qw53taGbunkSwUx09ehZSxwbArY.7V2gkq2M9uZaSdDwXrPE.
174	user174	$2a$06$WALhWagQF5HGOyGr53lKOOnyec3jYeNjFGAmZr5x28lSZK6saSxsi
175	user175	$2a$06$DlEsNZzbXjwzD4tfWNu6QukmfbeSlFlPpQv8dkPUWDkcFHC1iFsUG
176	user176	$2a$06$xhegk.hla3YdrY.iHyOTLO6nP9XegliL9mtS/4RSQSQm1CGf3hTNG
177	user177	$2a$06$GGnStrVv94oJxpVziMol4e5M35DomzmI9WjvDDUlHkZ.gU9C7AnKm
178	user178	$2a$06$VtXfaB..horPVb2h.Hu9xOw2g9EIJUy30jXJuNPzEfdIOeextPYia
179	user179	$2a$06$58qI8aNF1UHEkxt4ubtYNu61R9aJeY1Ywrwkl5YLrS9m4vT0g3uF6
180	user180	$2a$06$kFWLOy7I6FRB6wanS/oonunBrM3zQjVPrOXhWvUrjPNqwoo7CM6LW
181	user181	$2a$06$j3ASu4AR8CN.376w91SXp.vA7xsVVkZvmTQwyipyqj/wKj.5jaZ0e
182	user182	$2a$06$Dpp/zz4g3TM6wzXk7zX8PuEJAarHYuXZiz1.bT.xe4Wtx/XN1hQSW
183	user183	$2a$06$j5CD62aGoxaQA73F5hPV9Ogb4h1dvW6Smkv9bDhgsOFg6F7RRV3rO
184	user184	$2a$06$krjbKwRFH9lc5ohHztlZkOqfU3OvRI.aNHWgXGyP.TxBcsOqVDHWy
185	user185	$2a$06$VOD6DJjcDdtr/ER4OQsZNOkaVFuJTkIUu.eUY73.AmiUXH5d0Nmi.
186	user186	$2a$06$I6BanDLXCOEmc4d1MhJO3.9eFcRgPakyWpqEklR/vtT0Uu8RtiklW
187	user187	$2a$06$sEtfkaTZkM8yru.L0MuknO8MsltsE1WXOUFv1JoHCxpPrPZYSjqnm
188	user188	$2a$06$P8z6/rbX17TDvmi1L3RwnOeUNYJl4NY5FTfcabOgSKsohJTPw3koe
189	user189	$2a$06$gsx3sV87GA1frlXlRNjhiuV7mMs1giuqrXJwVKizEDN1xfr0B2MCi
190	user190	$2a$06$Kj9yJt0RZErGob60v9XmJe90Oa14HS1cd5izexBeeGAII83l.b60S
191	user191	$2a$06$yf2tjXVDyLjQW3VRoMJq2uqD9CB1ThUSzZf/9GLkiPw1bpJxKliqO
192	user192	$2a$06$fvamd7IOWCDxmo55hKGFa.L4Ck/MbpDQA/Td529tNEc8vAtQaT9Eq
193	user193	$2a$06$CAezZu/4Pi6KV5sL5Ce78.y11G109XxhEO2N0hOy6XFGfvFXEd0kW
194	user194	$2a$06$KLUeKLyfJmMmE8mZpn00yeE5AByvtsO2sDbk9y1tyzFEsPZLEZIMO
195	user195	$2a$06$jGJSeiEOlHSzFSjCc4Xv0.1Q.O4UrmsXfG5GAshQ2AF7Y6/laOCiW
196	user196	$2a$06$.5q.Nz1Hm0DHpIDFE.NhSu3EEbDPEnTCQcWDV.dssyCA4HbFy7GWK
197	user197	$2a$06$hOZFgUcb/LkHigJHypAeZeOYyZJcYwDESg9hUa/HvgP4ulUbF7wma
198	user198	$2a$06$/l6t15m.55LULFmZMIEc3Ob9DDM9FLRUk1JE3NxFyX/uUPD5tdHXS
199	user199	$2a$06$6MljRmTA0Odc0xY1GML1C.9vItMCO8Zq1MCluQWzr22WIAL5td.jm
200	user200	$2a$06$wlNMtyCIlfvQaflcKi4xlehYE2WdnUUhw8uYwcz8343hgbKg0loXa
201	user201	$2a$06$rU8Fd2bwzm/3eOiARLg9Ves39MBUJHYKjGEcfRpt/2pTh6Yf1NZ3u
202	user202	$2a$06$6zEvRKKX72SMWKmBr36Fnehk9gqhPc6Pf5jK8i/v1zgkyuv5vEDva
203	user203	$2a$06$k2aQOoEjmW1jk9NBFpH/0O9J4n3bNtTmyycjErp529w2OrHeuGTPS
204	user204	$2a$06$HtzRIpZzfXEiREgB85q2xeqeBcD9H9sGzTqnNvkko4OJBRTypl5s6
205	user205	$2a$06$v5gTIkLfFuN491Gj08qf3uwkBg.JLHkPI/tkHakW3.Czy9qaCELNO
206	user206	$2a$06$k39ZAbwuxSsx32INx.2WD.nYJKlriHLdLZFuVzcT92rhvkW8vFEFy
207	user207	$2a$06$yjwobj6yeeO5gpNtVNoaVev8neZLDkjWi2OEhzDvbMSwAEo0uGAMe
208	user208	$2a$06$NmlX9flS7rVkDbnvnHo51eJdaFlr6eV6IGp2tEQSq4in/SY9PylgG
209	user209	$2a$06$qw0obtm1y0g3fTvEUMRR9OCh9dBLqW6qqXhXyykkcPQY5MDl7ItAi
210	user210	$2a$06$IhQe0AinG.339BcyySJYvOTikdsv4zm9V/GvlI3O9Q5Xygn/Q2D16
211	user211	$2a$06$lEedz4G/isXGeYh2HWehM.h6thxiAYcaLoPMI8GiZV34zi22Wm0Pa
212	user212	$2a$06$R7aX/z78lHm9KBDMa9ezA.aYDk1UeSUtKkH6ZGuaIy/usXJpO9p1q
213	user213	$2a$06$V1VK31q2OOHZLTlJyaEWg.pPj4CrQKzgi6kJgufPIZ84KalBSaJQK
214	user214	$2a$06$xY27jJ1A6pmoNohzj3.ex.3PaUCXGWCXtR6rFzpdtiEsSC2rV/Pce
215	user215	$2a$06$bpIC2WGsk3DlXBS4IgSDHu0YrFaknM46qs9RLv9NYtfaU.7XQv2iO
216	user216	$2a$06$b82sk6YmRV9HGH801MoUUOp8C/HFlYbo6Etpog/0S6Q.6GXWwrRKK
217	user217	$2a$06$l1GdMuOEwqQqyBos4d.GFeoDs0WY2Osft5TNSRU7O2OP/OpT3yje2
218	user218	$2a$06$.7SguwIG.iuhvn2BmQ0zGO7HSvM7we.bUzyddeNewduvCpWHH1x9G
219	user219	$2a$06$YH2QJLu7yomy6SHJbInLZO0RQNZX36YVaE0oWItHyWFiWxr5eMVUC
220	user220	$2a$06$LH6iRDM4JkF0Q6GdreC4vetgJJwDHV.FsIbN6B2wMztsCNteRYSxu
221	user221	$2a$06$dUWVdnBosKTJLdb5jwQ91emMA/uAnvkX2ppqcHQGn3Z4DLiPSYTpu
222	user222	$2a$06$/lAHgoyKadZzRM7YU8Sq5OQrPx4bxtiLv.mkcwJYKhC3URXUsdzam
223	user223	$2a$06$H.ZxT.izMqvWHoSp35gdeeXtPu2.iw6vtAyK7ChAnlanHxi6zJSfi
224	user224	$2a$06$UgFc1NRRhEx4OKs598z5GO/kxSGH0u2tRWphOK4H8xLEtFmTult4m
225	user225	$2a$06$pZFY0GXN2qoUNG3myFdfNuCPQuEAsQAuCla6LOy3wpbR3f5DGQvuy
226	user226	$2a$06$HMdS2Fl825lmD21TKw4hz.dyXSGIm1sQZ0s4pdXFA9d0trgH2uo1m
227	user227	$2a$06$nc6IbPtWdHC7LlK8hffrAeTCR547DJykbmMxno/Frt2sNsq0RFd3G
228	user228	$2a$06$waapWAHhumQNtfoEdRarBuAzXpD2CIbPbURSkumZvKBTWcMkkPyOu
229	user229	$2a$06$Hq8CCBKIkb7T.72w.bI6tOh9aslyME5k.gl915mf4FBq6CYNRxJvK
230	user230	$2a$06$X0MDZkTbytJKT3czpb6h3eUQ3pT3ZjL/LqPd9KSBBsOaamGW3XsTS
231	user231	$2a$06$XX.elS33uJV.ie8GVsogfe.4Lg5UJ6WCHsk4E/Im3qZDbgO8hrhBG
232	user232	$2a$06$KjofeTzuBtPDCmNUHKDiP.0ARYaFZMmEDM46iTuxv/B15rtRUqy6S
233	user233	$2a$06$UNHbhebDw6pwgfNBrh3cC.Tu2NBgpaqlJd/JvlGhRb0dpqQLYnkqS
234	user234	$2a$06$gYtp04G0xAWmEG99uoFqGed3Ed5vsUOL6N56bWCm/s.B6y.y/zzCS
235	user235	$2a$06$VrXwNRKA5QE7iesmdyH9DuBz3jh3Jyt7E2lAmpNRp98iJfxYfyZV6
236	user236	$2a$06$h.l0Lb672v5SuzfY4sAS3eey4L2IA.mhnfkDUbl3K.1EtFN.7oSZ2
237	user237	$2a$06$wJnzKU48KZmkUtvVP.SSFOT74twUy3/fWRJf5jan4vw24anJG4gXi
238	user238	$2a$06$/Rnkb7u2ujjnDyE0Kc0QPeVHjNqUUT1SerMcLkG6iJawuWYFCwXli
239	user239	$2a$06$ekDQcPP6BaGnVKRZuAgW5OTh3aBQ9cjO9nzmhHymj.YhLm6QG6EOW
240	user240	$2a$06$N15EsQXqPKuuACAehVD2IO5R1BlIgIk77fvfXBqMpfK1ARCB5xLfG
241	user241	$2a$06$xTtWsPrN32cKuSQ9s8UBR.48GcBJ3xxNTuZT5VC5SbPwEeF1Xg34S
242	user242	$2a$06$FM0CUJcQdwc7.v4Jdg6WROk3EnzjetQMWrkXK8ok61aYm1XuwJN/y
243	user243	$2a$06$JfLgM6JRqG2uDoDK.Pr8KOVX4f/MgorLlyvDO1tOCLDF1uw7LjDuW
244	user244	$2a$06$PkwJyKB9QAgIa1dJZfsXsulICSw1F07eAk6UEtil0QewT88XPT.Si
245	user245	$2a$06$QPGd72v72onGh3jc9wQHvOWcraerol6phfD3k7DjMbCmdjWXx4VI2
246	user246	$2a$06$usnzIphb6NBzAv8398HkJe.wwBZthWDZVFmjG4vs4KqhwnvIMTWbC
247	user247	$2a$06$vRaBWoYz2q2Wr0tIc5QxX.RDRD2U9hWDd.gzm2xPvpMb5I5yeSzju
248	user248	$2a$06$PV4i5j2P.wNOT66NhefSxuyJ4Q96D3yDM1cGICxn/lmJ/8p69Yz.W
249	user249	$2a$06$xeMGfENfWk8RoJE4Dn8mKuM3MRvt8xdJ9KDubCmELDqv82nPbr9/u
250	user250	$2a$06$IxtHN7gD34zb.Jva5VmuQeRQ787q7.v8/Oy3xCXRxcgdm590TBiXq
251	user251	$2a$06$tf5PRtAIGJl6ocVhoAISf.0oFotkTD5Usej/bOR7D0QEIm83jakNi
252	user252	$2a$06$FC5Uw7m8mNJyPpzbIm6vCutXzBScK5dGF9MIttmRiORDZEFGvv9WC
253	user253	$2a$06$1jSpKl9b/8RpwB0K/8g.bOKQrMWwJAquVbk9GsXx0omI/ne7GF0NC
254	user254	$2a$06$ATkIIKhU57UOZdjWsLJ4aOCm7T5WA0VBmsTDagmN6bCy7Q59XdUUW
255	user255	$2a$06$f474t6dupz84cT.voUopWuTqMfaiOvxzxCODbP9tl9t5XXj9JnXV6
256	user256	$2a$06$NHcfSbGoR7ntByyOcjx36uqyNmFK.uwboYl75HjfaR0H2ZNLtCOSi
257	user257	$2a$06$Iu0Zoo3gQd982WuSvGxBS.G3CMN65iYFXOPTUvPEp1AzChhxelNSC
258	user258	$2a$06$8UFpt0iXl5QlkZnYuvBmm.hr68ZlKM/Xwbz1.c0y99sGamXP4wiSu
259	user259	$2a$06$YH/DQeOe/aqxBRRkWB0FtOg7C2pHF/eDgiqSR98WpM25G2qNzy9jW
260	user260	$2a$06$oPHAd4TyduTWity4OcsI.OWMemeK81CqlLZ3u9bx9JJ..dHh1PklW
261	user261	$2a$06$HmxpTOgdg2oAPqVHU0K8we5SwK6MOvutSvV3UNy1Li.EegvzUgpTS
262	user262	$2a$06$UuxP8jzz9dK56t2SrTTHru9jrjPDoZSulgf13jDn25wbxxhDil6bK
263	user263	$2a$06$1Fu7lu9MD4Uiy0LVoJVmEeXZkC/5jvw9r48Ftu5DUKLyj.eugCmTi
264	user264	$2a$06$3J6cblMd.fD8ShRC7T5eY.G1swyaL6RGKlGw7Vchnw9AKB/x4kRBi
265	user265	$2a$06$Hi1sm2LgjWbfe7Is0MEjR.HEZTtm2a01TcszFAG3RvJc5FoNHq8Cq
266	user266	$2a$06$FZkeUkVyReo3uSf6hLXb0.xGfjjXzSw7ORdCglbwBknXkGCgj4Ptq
267	user267	$2a$06$VUYwmTopt2R2AcV0J4wNKev2i.cRKAeoDMYgpiEqcZbd3GpkuvuCC
268	user268	$2a$06$/Z25lGgFVS5mq9WEzL6oN.I5yxoa9TCqKQy4YGm.1N4OtW2lDDhYO
269	user269	$2a$06$GdPJEIFvhassTmOfUn5D9.yOGBKd73PSbBQ.QvoN7MXrYolkD8Jl6
270	user270	$2a$06$C4SukfpSbxVQyKw4gMBdKOvXt7iigMNLCWc7zmPapjH2wNk6DtczS
271	user271	$2a$06$Vm5ABYJsEPJCluOaIyKK4OtBZXI9N4XHrJcrPpDYL.WdK8ATO1jYG
272	user272	$2a$06$HeUEK3E5iTy0Ad9uZkYUzOEzGJzEwopDNSfdnAsm.dzcryee7hbAC
273	user273	$2a$06$f6Fb61rKBPu7osO1/KYl4.s7qF0GUv2gF9Drur1BNHIw4oj/tacrK
274	user274	$2a$06$bhSriyN5IENVsFUl4QNik.5MT9ei8DMNSZsKIdNIqKAHNSSdX1GqG
275	user275	$2a$06$72sbRbtmq9QInVFR/dghMOygKZ2d45TX9sYR6DGuO5tAh/uhthaS.
276	user276	$2a$06$T1frbsUV2N63OBraHQyCTOl4vcL4qs6e84.xZXgA4EmHBPqkIr/jK
277	user277	$2a$06$SLgGg3lcfwAc1pWYxG1VfOeZlhMg3JHDJH4pTG6TlNoep9X9SY4LO
278	user278	$2a$06$kdGjBUxoJc8zbi2ilsN3BulE7gFPHIAzHxt4izh26.NQ391rFyROK
279	user279	$2a$06$zz4xaaCQuqlCaEoIQa6R0eGwTvbr2oQ3IYlJ68HgbyaVPC.6bFJha
280	user280	$2a$06$KABHjNOUqCm3SJzCz1Z1l.8LdUfcw3eWcJEMQJ3yVf3eG1Ahq79xe
281	user281	$2a$06$s1b3KB7f0Zp4tLXTzgup.uBmXPr.SnjGXMdmgGWcbZ1v3IlOKcC7i
282	user282	$2a$06$/aN/hBJkHUt1caWc71zRyOV1FyKqKjYzGJpn3pGD3OmK0FebCw5Hq
283	user283	$2a$06$fa.nkKnLEvkVyGrxV.GeV.3c3q1vs2NVkp7GN7NDl2ZwxEqIAOXCu
284	user284	$2a$06$tte12QYEGp09d2YXGhh7mOptLtFyvjT/BKn37Ejyt7fkeSqJeK.j6
285	user285	$2a$06$hJ9JGKNvzeBVt.1.7MOS4.CyVFtdu2Fdqd9hYb1V3I6ayDnyssBrO
286	user286	$2a$06$pnAUVLnYqRwsNFQzEEqd/eCITgR5NPo7zpF.2PJOGHso2KpweEX3S
287	user287	$2a$06$oc6FZ.DaQBj11eg6FxzX3OCCz64GLHnXz4BEQAAFE6mjD9q3nBDw6
288	user288	$2a$06$eIWroK/lFxBA7hdtzpeXGOAuCtavqX04PlMU5YoRBd777kLnwhcge
289	user289	$2a$06$NfAjy8aphyJ1w2e3eW258e0e3Qi.Z24SWlrG9KG7yovQ8fRNlZSrm
290	user290	$2a$06$KXiCDbfqdlL9X6PJGWj/kOZMa6avZFiOZzwgh9Y2ATwjzuLKjFu0G
291	user291	$2a$06$Qj1mBjvBkxKmILSolj9sweJ84Yjc9lvg3HZdDqkZ9Ztn.vvMEBYmW
292	user292	$2a$06$9vQljU3Fj3LNLJba7rRdL.ejTyOvTvyuz4Esu4vEzH/YiimtEY1uO
293	user293	$2a$06$jYSLFAi/awTxbKZAxRkj/OVT/5K3N4Sy5eB10shDJbRysKbrsLK8m
294	user294	$2a$06$YcXDZdg5Uk43pav7og/FBuk3MOOdblHZJcZLxkUOZlqlZ2FX1.P1q
295	user295	$2a$06$nWrYJV2y28dYOjfRfArEFeWB4/pQtDc1n5qyrns3Y6Rj/raPq92.e
296	user296	$2a$06$m4n7ycBbv2tIvls8APP6l.eFvyD6J15YcEXRaXymZaDQPwKRCuJFm
297	user297	$2a$06$oqxRKPceQuX8EAq8bfiCqe50.cbn3IvzwXbqp6iWQ.6EpiQpU/AGO
298	user298	$2a$06$ISS9cEcsNb9hMntVD9SUWuV8x7oOLQtXcjpQQ/y4E7lG.hNevA57C
299	user299	$2a$06$OKtoiYOhF0JMp12Hv8QG7OLeXSsJz9OquVC/jL9USc/ljmoRCNuCG
300	user300	$2a$06$whLkOoS5fn6T1fwB.siJRO9SeamV2wTVrZdauX8eu7C5GVajhg3VO
301	user301	$2a$06$TyXZbgAEb6DO.i70VyQ0OuSjJcmbeoVVgjyQNSxwEkFF2q6vvddIO
302	user302	$2a$06$usIOLSOdCyDcPqnqfNShxuepZkpjgsSUTGfj4gntkl.LHhajolWIG
303	user303	$2a$06$Bizay3N9Ef0K/OtIF1w5Q.YjAV6CM16UmINJ7ev853smikPfQ5iu.
304	user304	$2a$06$LE./eamBC5yP8B/rRlsrUurOdSv01LE2XUZScdGwaM9rKX74wmyrO
305	user305	$2a$06$u8M4tBiLwCdejBdCmB/cQe0zBgggckY0IuC5SsOvl.e6sGDj2IWlu
306	user306	$2a$06$AioIee4GcBZwOUiDdN/Tw.VdgxBbeFXbACio4/eTTLsyUpEY6V5.C
307	user307	$2a$06$j2FXKgP40syJ9B.WxTNc0.XkxGXqVJbTwHRxn/IJs4ThAPuPY/JYu
308	user308	$2a$06$htDs5c.P1FvqmaP.7KQd2uEf4YMf9Cuuk2C94F14v0bD3X9L0Q8V.
309	user309	$2a$06$GspDa04qEUJPYMs0WLJtg.bCAGxleI4upcrGvk6UT0FXx5EkKEfJG
310	user310	$2a$06$hXg1fgAzcszdludoknHxNuIgL7B9JD6v0eH9H2WNdg9WvO6orX1WG
311	user311	$2a$06$8nwDoEYBlDhrv9msrfIpp.kQGJ2x8YJG9VYUTYAhqDjK/sUyf317q
312	user312	$2a$06$kwr4chpdF9SJypb0KVJAcOlxeTaH2r1cWs/GDKMeENayIK5g6Xtue
313	user313	$2a$06$mgPYiUFW55xJcvIjJcMYbOp2ipJOHhx2Hs71M0380mb9qAR/WxL9y
314	user314	$2a$06$epQIar7AROrMm38iG3r/ueF96aoIGyPGyOqC5RStMAhJkhd9pw4D6
315	user315	$2a$06$qUUrqEDAzdnvbJviN8F4n.vEzO1K4gc/iSZ5QUr1jCJtAoxich/xy
316	user316	$2a$06$NTy8zq9yNxl0ADTVLy.Ji.kA1o9JuMS99yxhTV0roG/y.vQqnXKPW
317	user317	$2a$06$lDV7s/fQPpUMrTp8pbzgLOJKeMBIneHQyqS08JvTcGql4zbCLtVlW
318	user318	$2a$06$YLfFM5Z5iQZIHgIOVi.uPOeNtBNmC.bYRvUmAn90wZWhJVQkRFFOy
319	user319	$2a$06$KTeUMSC3y9SC4ZyxAFj/huImSFifPH0g2e7psWWcTfCVF.HK25chK
320	user320	$2a$06$ta.FGWzXZVwDViB5qGalt.PyNld1vo4/keTQPdjyUhWjiQ5OJoMn.
321	user321	$2a$06$dktEFoFLs/2ciTPKgnH8jezq3P/DrZMLMY54aJsIjXj0PTZ0xe8HG
322	user322	$2a$06$0VQyCY61o0LuQCu.wXTni.guzPjGJz.FZVgr059gLB5jbCgb6BGmi
323	user323	$2a$06$CXPm7vwvPbA76QYqggqgaOa0EIFn2ODu.nwuFOacDCDwv15NkHqMe
324	user324	$2a$06$kihpsFrsw.5ZixBvcpdYnuWZOMeVXmBFoSl0azlEQObSHNF82AgM6
325	user325	$2a$06$tlUKeeMRuOrLJp7HQcGp2eOpub2sWBj6tAhPIe7JR/CLI8hwt4lWC
326	user326	$2a$06$FgIYJwB0aQtcuL/d.yl5W.K7WgZdBee/knm6s8vEJDk8SwOG0DB7q
327	user327	$2a$06$Sm06eFBJiYS4HacrR2TMgehlFuj6u7pG2WmRclphIg6PjeV.5CVMC
328	user328	$2a$06$d4aWOfGdOXovYK2cc93oouksQBNDk61DDgf/YvQdUuns1Q4Hj1WLS
329	user329	$2a$06$dduLE4TegClZUleh9o2bqeVmlo5lV.Fj2peWoq/oJDuKQa6EOZ8zW
330	user330	$2a$06$97X1Z5bSaTI.S/5ANrKaYuBBocz24OTe./NxeHaJ9aeDjV5CxiAgi
331	user331	$2a$06$j2dmME6S7DPjg.dSPtx5buDVXZppqsiZQQCarXu8ZlJdgRpNiG7gy
332	user332	$2a$06$G9yXiHxayY5yg2Li26YLfOnz1IYHU9WNlLZjv4kVt42vPqnL863s6
333	user333	$2a$06$fSxs9L6qAmhJ1BoIvznV0unRKW4t1gHEg2YxICn.T//lQ5WGqntdm
334	user334	$2a$06$s2qT2Z6R4u115KClCrWNQej3qjmwcebTE1D5F0xQB9aADaAxf1xxG
335	user335	$2a$06$YTNPYquyWtu/qHlyIkA8MuDB3jS6xKmRJmXORLF//oySMQUNdN4oS
336	user336	$2a$06$pd97F2B78GjcVRtgQ6LZH.OhyPWwDhP/UxArloJXRdoP5vM7bvjEW
337	user337	$2a$06$CtAE9jdtdtb1oDrKNQ08.eb5pzbjvqRIYp1IMNki08tBE24sTwJ.e
338	user338	$2a$06$udhMucO3H5B8izEiIXbyjeunDTbev1mPxQ5VYsZuOHOngg30mPjIe
339	user339	$2a$06$erbkt9YEk0fxs11db3c9WujWTang5k6r67OmgcBWE3jvXbUGPiz4y
340	user340	$2a$06$9hAXQtk8ORZU.87vZqo2HeCkgUYPToIP9EHAKeUR1D/8LCx3U5R8W
341	user341	$2a$06$ctI4iN0oUuLKvuflf18F0OS1XOqDXyNq45zOl4tYt586NMyZvFYCK
342	user342	$2a$06$2rOS12plGbONcZ//hzOFH.DscWSQfvv4mzKOpSoIa5M8/IXecN892
343	user343	$2a$06$zcXxSfMuRqev8ylzJNT3mez/KGYIyOY9HHk30T31C8Mo88eBk6PMu
344	user344	$2a$06$RB636rQ.qzhcy0G7FHefBu8HmWR2lMJIHgSzRE/8UGk9woeaGuJ2i
345	user345	$2a$06$jxLfGWDQx4fy.Ez.8hxqceLtggODh6OZaZIe3PUl.0LD3mv0Tx0j6
346	user346	$2a$06$zdr6Cf.dmJxWZ8Uc2KmAdusdC6UxOIFnYnr8LxzISMFCKJezANskS
347	user347	$2a$06$xfNyK5IAktNrqkgfSDiMluiXJ9CwCKykINruVr9aFcWO0sW.Rb/lu
348	user348	$2a$06$KQIv6gpg7xcx0OqXZkw2Ge7Wo/Vl5zglZyUv80Bh2/7ZKnmGqFUm6
349	user349	$2a$06$Vjcz3LrZ5E55vy1nQO5JfOLBy9ATr3SVXHqmHpNILG6eaoTRVTeHO
350	user350	$2a$06$Lp8puH3SsxysRA311Y7MY.4O8eyNiLYmJYC4/xq9OD0YoguP9U0Uq
351	user351	$2a$06$fVD9AaKLJ4OZehmstUiUIOhhiUwxUPA2JRwTAZq54MjGBo0u546.q
352	user352	$2a$06$euEM4pJ2/jITpJFLSzXnkOQqzaobhFHcAal.nIHSeLk9/KCvcUENe
353	user353	$2a$06$ZKNiVdIMwvS5erRDk3kIBuGFEhzXSowdL3J.e9Wb1QX60ixD8Mnam
354	user354	$2a$06$qpwQcLBy.b7BvKOygWzhz.J0YWoiukonp/J..1fxB1Yy0Wutyyclu
355	user355	$2a$06$4eZOzX33sKQRgmqA6OmdR.zh6AEM6VMOrH4Bvxepw9z7XzI9l4PCG
356	user356	$2a$06$.Hw.iezw.dA0zoo38IA4IOg.TcQSjVjAPSJ16fngqj1NCPoXyRL56
357	user357	$2a$06$Rsg/9Y8F6op8U7aXnWJHLO6ti.5koPNeyxb9hb0hdpPHyV4ssvCzi
358	user358	$2a$06$vE6u/w3zIyNp8aTfjEM4Fu3iIdqj5MikoYKUgJ.s6laIWvUdTSa3S
359	user359	$2a$06$UluXAMEDcpd.jZl1ppu2y.LCZGy9nlnmq33mQVNmWSsoXX5qXnkVe
360	user360	$2a$06$pIRQrWIFXqg2uwJUB5hDbu1a0ifCg8TLQDEIJw37qJB2zwIUKGnce
361	user361	$2a$06$u62RdgCDGpIyLhZMlBZyGuoY0zMPPqYXClgdDEh9pAeQcbhXtcc3q
362	user362	$2a$06$F8FATK0PXFOogwrj2yHB1e8wwx0vdHrBQ6LOoylhKIMjox6SVvKsO
363	user363	$2a$06$uK0uYct.G71wOksPJ.A8Rekz2o0qjEb.uu4qrMeq6P9QH1LB7xqbW
364	user364	$2a$06$2y8iQ4bcDHWo1bZGQvI8Uea3IQcBMRzy1JfODGExKQNFwkKFiMZjC
365	user365	$2a$06$dpSZFXcnkED3iadJpj3TpuFgk7Qz5ZU5yOtaQNY8aW7Bszfeqw8M6
366	user366	$2a$06$kBhNNUhLaDhf7XpVRO.k..6eVu1oWzUWLsj2Mju/UwwXsfy04RK4u
367	user367	$2a$06$9q/cg5LgKyclreqwxRY6pONv3S0uOmd3fiksMzBRAlEtfYFmefI/O
368	user368	$2a$06$c./O9l.l4Mci6Y.Shh3DH.iQ8AoJ4mmKPzIk9YoWOIboYma40hfMW
369	user369	$2a$06$V6lYt2GEg94ASyJDVYjWpu.Fl23qfs7TNT2g5FDYzhn8Ql3cBCP1u
370	user370	$2a$06$9ZulTGk9r3jpzZofss0waOPuhcbcl.O/8KsCGrVlco/k.4Peg7H76
371	user371	$2a$06$s1weMQF7Ym.ODLzY6qeghOWsPr8mb1c8ARK0eSRs7DnnC2wZ3V.ce
372	user372	$2a$06$QFpSSV2BlLDdsg9sMEiJDeRmjO3lThORVCz9CpKej18aKkGMROqXe
373	user373	$2a$06$aJDx2UFJqxmqpnptLk3uCOidHEjTWmvdJSjdMrvLWgWChx/PFB3bi
374	user374	$2a$06$9/9CdFFGKZpcgtW9B/RO/u.7LfUe4fsTdovsG8yxidYnp0CHPJCei
375	user375	$2a$06$vu3UXZSk65giS.TN/bL2K.Q/WbnfPGQk6xJpFb0ZkOXxOt1Y3YXwy
376	user376	$2a$06$bbP0n4BEzxKlBJjR2g5fle3g52d2BfkY4AQM51WlW9haMMCjvg/GG
377	user377	$2a$06$7pjW8a6vo97jVAzwCb9SmuJkfdkLTauBEy0JLTulCJfZ8q41eQy4O
378	user378	$2a$06$.v7c1TnNfN7E/M/gh.uuquFW5mzwVKceBvZN3QLXefQMs00D02g2e
379	user379	$2a$06$1oDFxqqvg7H1xw1x0Lp4iec9IhPiXi7ZuPAgmcJoRSN3zgS8gzvZe
380	user380	$2a$06$3N0abT3MK0v.9sNQh.O1FuBdIEMhZu/PJoVGQzZIBZVJU7f/9x3pW
381	user381	$2a$06$yt2O8VKXOkdnHpEniMbnlePpyMtbuWrvBWxn/zQRNDCWlojw3Ndve
382	user382	$2a$06$cYgePqvYOP3FPoz.X.njK.lej1OdZEDGZ9jYxXgYV5sZHdA3dcho6
383	user383	$2a$06$7EbykQ3Zr14Jyq77JJADxeNXkDtSO29LiriHiAMIRSQ5gTm.ksX8G
384	user384	$2a$06$S0PLuyUDmrJ6UL81HhW99..KTu9Om0cXC/PZe76zMzwJHCXu9MtT6
385	user385	$2a$06$CmLq7kC5FyQcjjzgmyXi4uC/22Zn/zJq3pNQS.c10XG2m4x/mxPU.
386	user386	$2a$06$ul1ydNO/727gINPafM27nuzge6Ulggc6TsQfJYFc2NpFPsOJlz7Ba
387	user387	$2a$06$NQN35ygUSycF9oriISD75OarzMI7FJZ14.c5ilXiLF015FoN8bE2K
388	user388	$2a$06$pDfFoQiiG/QF/bOdweESn.EheeihdvqNmQVmYTx8MXr6zhtu3C.CW
389	user389	$2a$06$vBRZfIXOYPtyE6tWBpjK4ud/6cpGNsLrKDH9vWNjQxhPItwGFURGe
390	user390	$2a$06$8nWN9ZyfSdsQqQ2hPw2rXO1o74OoTb9xV9vjVXcYornLElDLPocpa
391	user391	$2a$06$h8yYaPO60N6quwZf1q5a.u379Xk0FzgwBeNCSzVfS.w7wV./WXlNa
392	user392	$2a$06$N3.gC06na/yJVI5NngN/o.xBu/brDRe18kRUOsdefjNXZmHg4NqSi
393	user393	$2a$06$WthaMrTfbel7D3PLzpqKKe08zpLBDeEVq.WrXUr4mSR0U6LCmSwVG
394	user394	$2a$06$KjqZEWRXp9T/DrHvSSp.CuWFnlAiUu9/a1Bry2H89n.qjBXlqx.2i
395	user395	$2a$06$Yu.T3SaA2fGJPaaDlCBktemW0R/5Lu2C/I8rqOjOJhCX1yUZ9Kyyu
396	user396	$2a$06$MD.IdoYQ.pPKvSSlGlhaIeXnX2HYg9jZdm5AvpJGep0IlJW537Beq
397	user397	$2a$06$hO4/sKfROVaUMGqCVRzIvOCfLhAhxF7wEXqNK0kLAssazkW/tG1gm
398	user398	$2a$06$OcILuFC6Ejy6/2BCHVO08Ooc/wI9VGS9tds.O7e87XqwW2B0o65rC
399	user399	$2a$06$V7RrTyVelhSJy0Vvx.F1kec2opxKlfLgin4ed2Q37rGKsq9ph.w7W
400	user400	$2a$06$TjNY3LPpQ2IYCY5PU3xT7eRkYu4u4Ki8hGW1VK4tLbc1dOSOumwBG
401	user401	$2a$06$uMMsWv/rh9j/ld8zw2DCoenKKAc4EKbpnCL4LGvlwMlw7/L4gCVnC
402	user402	$2a$06$CFB4q8seG0pdcEcS4yS4tedLyyztTFFbzW83DlkO5CBh29WZEocp2
403	user403	$2a$06$JFN5UVntbis08KPQ7FEOp.dxhexrauGYVnzZ1EwtMeCd7yc9rMkoK
404	user404	$2a$06$0K4gh8mq6yoCKHC4Isg2xehiKUecJtAjFeAk51YAeon61Oy3sKk0.
405	user405	$2a$06$uZa27JgVcipKqvqDYH2NN.qPYBtM7kAvADH4mFZoWsn9iOrG6Sz7G
406	user406	$2a$06$r/bFuEciT4Z.xK99aiusOuFM.9d3FM4C2mPzlbCuiJrKD1FAl72Fq
407	user407	$2a$06$4Ls/oKu3P6YI/ETTBQFtW.kz2jaMNoNqq5IkajXNtwfoE/IikBWxm
408	user408	$2a$06$RVU2z5QtdYyOe4HP.RV8ueDXtJ.mAGYKBPnVmlqHq/T2Cauw2dA1e
409	user409	$2a$06$rsclHYICT.F3QIorCY9E3O71Ti41NEDAsgpRd325UbZUQ9HQZAAcC
410	user410	$2a$06$oa3TgMXC1H4zG2lsPZhxcuDXfWWa2gl6AOv6Zvc4OZXaq/o8jhpJa
411	user411	$2a$06$mFWpadW3tbOIKJRlNCko5O5Jakv/ekm/0eK4bKL4uedfzumghTdSK
412	user412	$2a$06$rplafNa.IvzpgUM8NKZvJOKpDt6/0euJFTBexG3ebfcP50spN5Udu
413	user413	$2a$06$T60YkwgElF0atEjO/ZihXeC/SvEdXZO6yaT1J4BgfdOgvrE3F19BW
414	user414	$2a$06$5kAmz.w/wGNEfEr5EW8pjeF3SJCYCydwitSl1SAOxr.r4xV3a2IXW
415	user415	$2a$06$8O3dZmqrTCL3WRHMDPNHbORbblDv833DRZvzKBaqZPH5ZsNZmYJEa
416	user416	$2a$06$971yq.sMlGLzvCBwNmNB6u9lPqR5hZRGV5NhgCPAAloBW/U8CiQQO
417	user417	$2a$06$jcuyjKibmBhVCRO6ocoSl.HTXQ5rx/UMC8YYwOP9ap5DNAr0o3NoC
418	user418	$2a$06$jpSp.5RupXyg0l3WIfdhIecczRzMby8HVXJsk.IksKzyJa..xaWXi
419	user419	$2a$06$utcxXvaLFBHBD8EzN0zsbej4EOOxvzyV9l7HP/6/B.YOSdSAimAMW
420	user420	$2a$06$G9LJ1gYpjgaN6UALX9Ru4uBVNLD6JvrAeadQ7qZliZBCK5zAwNh8S
421	user421	$2a$06$C3LHaoFSE1nYm.NuBiFt5edZgjRCHrIt.AywazocbTT06dAUORfC.
422	user422	$2a$06$ohRVHM6hz6QNo6PBVrkzLeKmlilD92WQNSQ1k5a1tEq4c0puHCzmG
423	user423	$2a$06$5QS6ZKevoJuTVmeGaq/QDOKIrwscfIb5DYWqnwMU0CgVYFworUJd2
424	user424	$2a$06$wmCx2GJiXCDc6F857uGTFuvnNVk7AEMXtqYGD5aFE5CDj/bFvKFYu
425	user425	$2a$06$eAy4Vt1IZkMGmWEUdsaPs.0YGREcRv6tqvzjt6DYTWaiKoiC9GgX.
426	user426	$2a$06$7VtdjEcGcUX/kXej6xrqb.UZwdHEllp40iK7s9plmKe2jZczTt3fm
427	user427	$2a$06$IBoH03aymMGtYUOlfbN66eCXniQBlw4MOMTb4UEJ/nD7X4CAh2uUm
428	user428	$2a$06$lxeR3CGg5Ycij1yJfr5AhOooe/wcXQ6KyAjY6kLFe0zsJ72gd.unS
429	user429	$2a$06$RCIpKLyDU6fm1mbGvX2Qwuf0j.csoiQ40KgP0mIllEVJpYwIzSUF2
430	user430	$2a$06$I8MB2sP0Lx5kXLtLpEBhWOFy9w5pG4kuGkp6K3Do/kLuICMyCV11e
431	user431	$2a$06$Vd/DX25rcaaq24/7lvpk9eki/gKnzFReIQQRxkREeDqJij5huUPvS
432	user432	$2a$06$8rzkMiv1DtISVwlHDuzhxuxbPXn8VKoc4luiLiYulWHJ3GshlmPE.
433	user433	$2a$06$mTch1w3Hjkle.aynhmhMOu9r2nuWjclVDrVMs9dVksAZdqfLlQWpm
434	user434	$2a$06$wf0t1e2q3gkEdaNdBqz6kexNHukpLkU5iTp4or7.Mom4LEdjB8J8G
435	user435	$2a$06$lfri79znHO5AmXY9rA7vcuBoEh28NRvVbVFTFPXf7TIgAO51TMLZa
436	user436	$2a$06$iWmPzSiRdg0N.CutNTxJJubvKU5N1n/eNTwUow.YO0VaREMIj/ufK
437	user437	$2a$06$d.tzlQuoCh5zfkXLx7p9K.oICL6AU0mUUuXSgsaf9T4gAfu/DLMOG
438	user438	$2a$06$zcMiFez6VpQsIb5nkzXd8uUNPuFYoRecLd2A4CmNfWNcF29UkIHH.
439	user439	$2a$06$FTzTQhWqiN0X.pFTmLLoQeH/4szMN5Z7/SJBER1UdycUcD43Lpepe
440	user440	$2a$06$36s0E1IUkEsPSThEyy/tB.utsN5uF5GfjwV4DIZvmhdYOPPLwO3BW
441	user441	$2a$06$jjn48SHAtKP9t4HaWCayi.FrIUommScTDo5ml9DHU0fLB2dFvyunO
442	user442	$2a$06$P4hDPDZddswv6LDe2L4oO..bbfKCP9QJIbLGqQKyc2n6ZgeZJY6Ii
443	user443	$2a$06$yLBaTgpcDs5HEctY7LEp9OeiNjGrs3dM3a9YNAIOn/EvXEK7ZGu2u
444	user444	$2a$06$7MVX/DnOiReTGDNq7kBDSuTcYr3f35mirYfj67nohBE0k9y6/YCtO
445	user445	$2a$06$PPXKUzO4ixHOpATsbK48meEM4cPW2SX4uAh2SoayPg5taGRz4hpxW
446	user446	$2a$06$K5.5H08Z2vcxC0BEYoW6seyW9u/F6H6NQj2gJc2oBJqh0J147/MGW
447	user447	$2a$06$nITvREqCFmKSuuCo56DA2ubvoein5vAb6Arktygg.fplrYNL8Mo5y
448	user448	$2a$06$OdHMnKQuoJJotRzIA5fFLOs72c/D7RJbp0bTrrG6S7MGzTK/QoLTi
449	user449	$2a$06$cgPbWdoONg7dh7SpREha3.3ZZ/QnCoTdcSiBEbYn0S5KH.M6bx7sy
450	user450	$2a$06$6iH/LzDYil/MvD54HPA87OFfR1mQwUhZ4Wz6Z8gjqid8KwU1Wh/lK
451	user451	$2a$06$sH8zyVgS./l755kqOFhuB.HCEz7bQKkt3gNABlFx0dEIUS5j7MW.q
452	user452	$2a$06$29s7/AsA.DqX5D2nEZAzf.C3pFAFzg.BUSApyTNDdcvlfWkwMxD2m
453	user453	$2a$06$El8VfSkJyB.BZ1fkNVZSqOBPhv2YyT1kQl1onLF7Pc.uAGEarnNxa
454	user454	$2a$06$kvb/4mQfQ/v82Xk32oWuxe1bKhIomIqTJPYN0mvzg53Eg97Fo/gPq
455	user455	$2a$06$JUBr6F59y3fFnS0QkcfROeHaeERWe.iXlh1QAPCzdoUTYwjFTminW
456	user456	$2a$06$66OyFFyYrxlUKASTsAhXw.IAtA/79fhEX0kHkTCDp1C9Y0cKP1fGq
457	user457	$2a$06$3F6HBIk4DJIf7lNulC/GbegxhvAUIkHANGRx/BiGlSRdY4dpfJVzK
458	user458	$2a$06$dr9guViTSrIIT6cFAQKw9uBDqAlgxdj3yi3i6.o29.kygS4ChDztK
459	user459	$2a$06$5W90JAzxD7WyYx/v6Sajo.v9/oNHQBmyiZeci70IJrP3i5ilf7cQu
460	user460	$2a$06$77R5XdCGBPhFA/Th610tpOAaLx9ID0LA8bxUtsDwKa93Mo1rWpYbK
461	user461	$2a$06$QW881OKex9WmLuWh5qbdNuzbURVL4c.Co2dUOWzGCvm04NBdOPcRq
462	user462	$2a$06$Juv60rGk0H1m4ohTrZrJEOea.SDFXIsoJN5XWc9zI4uU8D0iLEG3G
463	user463	$2a$06$EqesaIwiNZm00OtpVio5eOfh3VXa4/Fg7D5wX2KdEoPX0/DVouSdy
464	user464	$2a$06$XtvmomstM2sgbK4mmgUaaONgsT57.sXpjwTbmsthBCZR6hSDdpLjK
465	user465	$2a$06$602Xl/N46aFF2kfUYLOZXuV84h3nKSO5oFCpePe0ctAcG0FjuFMTO
466	user466	$2a$06$dZzGj82RrciRLUtXtAX/3OCxSE8n1SVpjYGVDGg263ewOi3/qdbXy
467	user467	$2a$06$y4r34N63dkvpWol.ORQRNeKHpb42Urc1aQQIn4Muhzoc95eZSZSBu
468	user468	$2a$06$BCDduCiJYKtr7roxe7.3e.GQvNl1Fyn/4PbBsBfjcjsZdII6.4LR2
469	user469	$2a$06$5aNNOplC9i2CeoDRfkAGy.OG1.BJE6l0E3tt5gINU.BAK4/Q9eMl6
470	user470	$2a$06$sM8NVceJCr./zBokYv5S3eeRQQYZVmpBVccalTsMzws03mgckvoi6
471	user471	$2a$06$m3DKMLCVJkVOUov9dvvaXuUvv0ugJ8FPfPgmzhNwFSoSFmW/nTm5e
472	user472	$2a$06$Mf3/0qwNmHJVEjq7I078le6ajip10QYfA12D/rAXjnaraXUdI7xQy
473	user473	$2a$06$87RnrNfHkmROmLAEhfDeEOOZHyP6JSAiocvZDyoVvk8o1ECkYCLYe
474	user474	$2a$06$awz0tZqs7L5NKwgXhP.q7.VymXUMXyPG6zyjADC1ZfpF6aO75wSr.
475	user475	$2a$06$W67Q67T6qrwjG7K55dWPk.Wvq.GnLTapLAqdBjfBpqejImczM4/Y2
476	user476	$2a$06$anT1M/sZElMSqteLPLlYP.2EGWT0mFGiw/FlFfu.UI1PKCBY7pPxS
477	user477	$2a$06$RKsBTtAvS5wMRaYUR7bJYeKHkxTtgUeFkHSB2ro3bYHHR6x9ZDdBW
478	user478	$2a$06$eNbkx87Dgsh8i5gpFFA/seNAtJpwWP7wDW4aa5vJrPm1TZQZ8Hg.i
479	user479	$2a$06$AnLApq.8CaIEBy9Y4OR3QuDnCdEz2X5kxs2.FLE6iPHFrd0l1rAte
480	user480	$2a$06$/l.pvOrzsHdmSf.XwXP/L.pOgLiQ4qf0TLl2mS6YUj.4oLTFdhQJK
481	user481	$2a$06$wDUBP..pNUGYCqhq.W.bU.7r3H40O3JVI/sR97jdrEMcCWjPy8wN6
482	user482	$2a$06$IHI6oT5ASahsK66DWOb9wuGDoQ75H.oGOAE7xowmgUBCjsbNcy8QO
483	user483	$2a$06$GjZe6/D.MRxf.w6iOi.bke2rXqba.eG.UusAVDvQrpfJPcH6RfgFu
484	user484	$2a$06$IjtCYQ14NCac.ED26jWk.uj17J4ODkZxxwKNzGDgljemBMAeFnpay
485	user485	$2a$06$ZgyjCypoIqyytJBIP/AeAujCFFflppci6ikKG1MNHTjZdWrJOPiMS
486	user486	$2a$06$9tslbj9XmENElxrE8LOZYeEru5B9qPfZQY9wW8U3.THO/uF0ZwMNS
487	user487	$2a$06$RtSQjsQoD0GxYtU6f07CnuQd.ldsZMspgnZkwQJRll3QJB1GFG.vK
488	user488	$2a$06$NREjgEghB0mMm5JM9DC0n.oOoCpmj9hqes.A57cDrOfGHKHJ3mFd.
489	user489	$2a$06$TsLJaGQ7eP75yw5licUuCeCdrhD93lfNDNK.zlR.DlTZMP/75oJ/a
490	user490	$2a$06$qaMPq/dwN3uQC6OFNezqce.P.aOQeSnycU3cbqep4poABRCBWRGbO
491	user491	$2a$06$wI69YqRaDa1desO.m9Mfbu6haAxXboV2BgflmQLotzSZsaYf3jon6
492	user492	$2a$06$XtkLCKZHgdEHMOSNQw.1s.JRrUbkRWL97ZC/gJ5XMxKFko6Z2.TIu
493	user493	$2a$06$sh.5r7G0n8CFcDMtvxnV0edftzAxaWUXsUl6Dd4wO.NOQG./Zx4jq
494	user494	$2a$06$vvBwdZHNf06PUig3atnjCuUsKSgeAB.hhB8TxMLLclj5tu5NJyCpe
495	user495	$2a$06$UEa7dyJVXYY9b0SdmLPdIOPFrbvIXnycwZjKgxUR2T6k.7TrgDVsO
496	user496	$2a$06$eBAcVB6lAtk7LEFfvByiz.L6yf0ZoxC4FwTec6Aq7PXqQDenKo6e2
497	user497	$2a$06$QQl7R9./5K9datGGmqupHOt6OKgr73a8xZcPn0gGdfOYiHX6UPV/W
498	user498	$2a$06$eacf52LT6/lbiWOeMDYlGe4ERKJntqy/u1jrBUwTUiTjW0tVsN.ce
499	user499	$2a$06$dHruIeJiWvERUngfU6xKHe1qS3n3rVvGuqihR/4vncP9EuDVzV/su
500	user500	$2a$06$OOtAxoagq6NPxbHuHePhXu///yFHxXQ3rzrPztXSjQoWwppxt/dP.
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
1	2	3	1	691	Nicaragua	Chinandega	2024-09-11
2	4	5	2	219	Liechtenstein	Vaduz	1999-02-08
3	6	7	3	1233	Albania	Elbasan	1999-04-11
4	8	9	4	637	Russia	Kaspiysk	1974-08-01
5	10	11	5	979	Palau	Melekeok	1974-03-25
6	12	13	6	527	Belarus	Pastavy	1974-04-15
7	14	15	7	1103	Mayotte	Dzaoudzi	1974-12-01
8	16	17	8	711	Bahamas	Freeport	1949-01-18
9	18	19	9	5	Madagascar	Antsohimbondrona	1949-01-28
10	20	21	10	1174	Swaziland	Lobamba	1949-09-09
11	22	23	11	1242	Jordan	Mafraq	1949-05-09
12	24	25	12	828	Senegal	Bignona	1949-12-25
13	26	27	13	417	Honduras	Potrerillos	1949-01-26
14	28	29	14	301	Cambodia	Sihanoukville	1949-04-02
15	30	31	15	802	Bhutan	Tsirang	1949-09-04
16	32	33	16	443	Belgium	Zaventem	1924-09-11
17	34	35	17	1076	Burundi	Bururi	1924-07-08
18	36	37	18	725	Curacao	Willemstad	1924-03-02
19	38	39	19	51	Iraq	Baghdad	1924-08-21
20	40	41	20	39	Finland	Lieto	1924-09-06
21	42	43	21	1135	Egypt	Toukh	1924-05-26
22	44	45	22	680	Nauru	Yaren	1924-10-13
23	46	47	23	835	Mauritania	Atar	1924-12-04
24	48	49	24	256	Monaco	Monaco	1924-03-09
25	50	51	25	1239	Azerbaijan	Yelenendorf	1924-02-10
26	52	53	26	550	Suriname	Lelydorp	1924-10-11
27	54	55	27	517	Malaysia	Simanggang	1924-09-14
28	56	57	28	276	Malaysia	Kulim	1924-12-21
29	58	59	29	988	Slovakia	Bardejov	1924-09-06
30	60	61	30	421	Ukraine	Piatykhatky	1924-04-16
31	62	63	31	242	Armenia	Hrazdan	1924-12-24
32	64	65	32	548	Uganda	Kabale	1899-03-17
33	66	67	33	278	Barbados	Bridgetown	1899-01-13
34	68	69	34	297	Laos	Phonsavan	1899-09-03
35	70	71	35	1041	Latvia	Valmiera	1899-04-26
36	72	73	36	1179	Maldives	Male	1899-11-11
37	74	75	37	217	Honduras	Tegucigalpa	1899-06-24
38	76	77	38	713	Israel	Ofaqim	1899-02-03
39	78	79	39	93	Bermuda	Hamilton	1899-09-19
40	80	81	40	1236	Burundi	Kayanza	1899-12-05
41	82	83	41	575	Panama	Chepo	1899-07-04
42	84	85	42	1102	Guyana	Linden	1899-11-08
43	86	87	43	671	Ecuador	Montalvo	1899-05-24
44	88	89	44	81	Moldova	Ungheni	1899-07-19
45	90	91	45	959	Bolivia	Trinidad	1899-09-15
46	92	93	46	20	Dominica	Roseau	1899-08-06
47	94	95	47	1230	Tajikistan	Norak	1899-07-01
48	96	97	48	405	Niger	Mayahi	1899-07-25
49	98	99	49	591	Moldova	Ungheni	1899-10-07
50	100	101	50	558	Afghanistan	Kabul	1899-11-20
51	102	103	51	1130	Tunisia	Monastir	1899-07-25
52	104	105	52	755	Georgia	Khashuri	1899-06-09
53	106	107	53	657	Pakistan	Kunri	1899-05-15
54	108	109	54	430	Brunei	Seria	1899-11-10
55	110	111	55	356	Germany	Oranienburg	1899-02-25
56	112	113	56	1002	Croatia	Zadar	1899-11-20
57	114	115	57	463	Belarus	Mazyr	1899-08-23
58	116	117	58	736	Jordan	Russeifa	1899-08-26
59	118	119	59	583	Pakistan	Digri	1899-12-01
60	120	121	60	372	Kiribati	Tarawa	1899-07-22
61	122	123	61	492	Mongolia	Hovd	1899-06-25
62	124	125	62	170	Macao	Macau	1899-04-27
63	126	127	63	271	Cameroon	Penja	1899-12-03
64	128	129	64	464	Mozambique	Macia	1874-05-09
65	130	131	65	727	Poland	Jawor	1874-07-01
66	132	133	66	841	Kazakhstan	Saryaghash	1874-04-02
67	134	135	67	767	Russia	Kovdor	1874-04-06
68	136	137	68	209	Singapore	Singapore	1874-12-12
69	138	139	69	818	Belize	Belmopan	1874-10-05
70	140	141	70	805	Panama	Pedregal	1874-02-07
71	142	143	71	1101	Honduras	Juticalpa	1874-05-26
72	144	145	72	597	Somalia	Afgooye	1874-05-19
73	146	147	73	26	Benin	Ouidah	1874-04-02
74	148	149	74	1108	Mauritania	Atar	1874-04-23
75	150	151	75	333	Chile	Arauco	1874-09-18
76	152	153	76	1208	Qatar	Doha	1874-05-10
77	154	155	77	1203	Azerbaijan	Baku	1874-01-06
78	156	157	78	444	Pakistan	Loralai	1874-01-27
79	158	159	79	38	Ethiopia	Mekele	1874-01-02
80	160	161	80	753	Malaysia	Miri	1874-04-06
81	162	163	81	865	Colombia	Lorica	1874-06-12
82	164	165	82	912	Niue	Alofi	1874-02-21
83	166	167	83	1000	Egypt	Zagazig	1874-04-26
84	168	169	84	568	China	Gushu	1874-11-09
85	170	171	85	229	Finland	Pirkkala	1874-03-27
86	172	173	86	452	Kazakhstan	Astana	1874-06-07
87	174	175	87	1185	Ghana	Achiaman	1874-02-27
88	176	177	88	381	Tanzania	Mugumu	1874-06-07
89	178	179	89	793	Niger	Tessaoua	1874-09-21
90	180	181	90	1105	Kyrgyzstan	Isfana	1874-09-02
91	182	183	91	776	Ireland	Dublin	1874-07-06
92	184	185	92	254	Germany	Holzwickede	1874-12-11
93	186	187	93	699	Taiwan	Lugu	1874-12-23
402	\N	\N	402	549	Haiti	Carrefour	1824-04-08
94	188	189	94	376	Japan	Shiroishi	1874-08-10
95	190	191	95	565	Tunisia	Akouda	1874-03-26
96	192	193	96	15	Burundi	Ruyigi	1874-08-07
97	194	195	97	1207	Ireland	Luimneach	1874-06-25
98	196	197	98	637	Kazakhstan	Abay	1874-07-19
99	198	199	99	418	Mexico	Huatabampo	1874-02-04
100	200	201	100	974	Niger	Agadez	1874-07-16
101	202	203	101	674	Guatemala	Chinautla	1874-02-19
102	204	205	102	405	Armenia	Ejmiatsin	1874-01-23
103	206	207	103	1230	Singapore	Singapore	1874-02-02
104	208	209	104	807	Bangladesh	Narsingdi	1874-09-11
105	210	211	105	648	Jamaica	Portmore	1874-10-11
106	212	213	106	607	Jamaica	Mandeville	1874-08-25
107	214	215	107	201	Guinea	Camayenne	1874-07-18
108	216	217	108	402	Guatemala	Tiquisate	1874-04-14
109	218	219	109	505	Spain	Alicante	1874-02-03
110	220	221	110	22	Italy	Siena	1874-09-03
111	222	223	111	54	Iraq	Kufa	1874-08-07
112	224	225	112	695	Greenland	Nuuk	1874-07-09
113	226	227	113	670	Tunisia	Monastir	1874-07-09
114	228	229	114	134	Burundi	Rutana	1874-04-23
115	230	231	115	892	Curacao	Willemstad	1874-03-24
116	232	233	116	435	Pitcairn	Adamstown	1874-10-16
117	234	235	117	887	Niger	Dogondoutchi	1874-12-04
118	236	237	118	294	Honduras	Tegucigalpa	1874-06-08
119	238	239	119	526	Moldova	Soroca	1874-02-15
120	240	241	120	702	Barbados	Bridgetown	1874-09-11
121	242	243	121	928	Iceland	Akureyri	1874-09-22
122	244	245	122	853	Italy	Monterotondo	1874-02-22
123	246	247	123	1155	Lesotho	Quthing	1874-05-15
124	248	249	124	565	Colombia	Aguazul	1874-04-22
125	250	251	125	876	Laos	Vientiane	1874-06-06
126	252	253	126	662	Monaco	Monaco	1874-12-04
127	254	255	127	997	Burundi	Muyinga	1874-11-21
128	256	257	128	700	Niger	Matamey	1849-11-08
129	258	259	129	160	Togo	Kara	1849-05-09
130	260	261	130	1242	Gabon	Franceville	1849-09-07
131	262	263	131	1239	Tuvalu	Funafuti	1849-01-07
132	264	265	132	165	Thailand	Ratchaburi	1849-01-28
133	266	267	133	360	Nigeria	Gummi	1849-02-04
134	268	269	134	330	Pitcairn	Adamstown	1849-11-02
135	270	271	135	403	Togo	Bassar	1849-09-27
136	272	273	136	840	Uruguay	Florida	1849-03-20
137	274	275	137	241	Ireland	Kilkenny	1849-09-06
138	276	277	138	908	Kenya	Molo	1849-09-22
139	278	279	139	256	France	Toulouse	1849-12-20
140	280	281	140	1124	Rwanda	Gisenyi	1849-08-23
141	282	283	141	679	Angola	Cuito	1849-02-12
142	284	285	142	778	Argentina	Coronda	1849-01-15
143	286	287	143	803	Mauritius	Curepipe	1849-03-11
144	288	289	144	656	Denmark	Nyborg	1849-09-06
145	290	291	145	110	Benin	Parakou	1849-05-13
146	292	293	146	490	China	Guixi	1849-07-28
147	294	295	147	721	Djibouti	Obock	1849-11-12
148	296	297	148	818	Lebanon	Tyre	1849-04-25
149	298	299	149	144	Pakistan	Mailsi	1849-11-12
150	300	301	150	682	Uganda	Paidha	1849-01-21
151	302	303	151	1054	Azerbaijan	Mingelchaur	1849-07-05
152	304	305	152	1133	Kyrgyzstan	Kant	1849-12-28
153	306	307	153	1088	Greenland	Nuuk	1849-04-25
154	308	309	154	855	Brazil	Ipubi	1849-11-26
155	310	311	155	226	Madagascar	Ambarakaraka	1849-06-07
156	312	313	156	608	Gambia	Farafenni	1849-09-07
157	314	315	157	844	Tuvalu	Funafuti	1849-11-26
158	316	317	158	721	Pakistan	Johi	1849-06-17
159	318	319	159	939	Japan	Okunoya	1849-08-20
160	320	321	160	479	Libya	Ghat	1849-02-24
161	322	323	161	669	Finland	Haukipudas	1849-04-21
162	324	325	162	1151	Pakistan	Gwadar	1849-01-24
163	326	327	163	1110	Japan	Kanoya	1849-09-22
164	328	329	164	712	Vietnam	Hanoi	1849-04-22
165	330	331	165	632	Mozambique	Manjacaze	1849-03-20
166	332	333	166	541	Mongolia	Uliastay	1849-10-18
167	334	335	167	1135	Latvia	Valmiera	1849-01-03
168	336	337	168	963	Belgium	Geraardsbergen	1849-06-17
169	338	339	169	808	Venezuela	Charallave	1849-05-22
170	340	341	170	412	Myanmar	Yangon	1849-04-16
171	342	343	171	739	Morocco	Guercif	1849-02-15
172	344	345	172	976	Benin	Banikoara	1849-04-19
173	346	347	173	1015	Ecuador	Cuenca	1849-12-23
174	348	349	174	980	Argentina	Dolores	1849-01-21
175	350	351	175	102	Dominica	Roseau	1849-04-10
176	352	353	176	179	Monaco	Monaco	1849-07-19
177	354	355	177	445	Jordan	Amman	1849-10-22
178	356	357	178	425	Poland	Police	1849-07-09
179	358	359	179	910	Canada	Cambridge	1849-03-25
180	360	361	180	7	Greece	Vrilissia	1849-02-20
181	362	363	181	777	Japan	Wakuya	1849-06-19
182	364	365	182	829	Angola	Lucapa	1849-01-01
183	366	367	183	377	Macedonia	Kamenjane	1849-07-16
184	368	369	184	499	Vietnam	Hanoi	1849-12-06
185	370	371	185	1221	Cambodia	Kampot	1849-12-12
186	372	373	186	268	France	Montivilliers	1849-02-01
187	374	375	187	637	Indonesia	Abepura	1849-10-13
188	376	377	188	465	Chile	Cabrero	1849-02-07
189	378	379	189	336	Algeria	Cheraga	1849-02-26
190	380	381	190	230	Bahamas	Freeport	1849-07-15
191	382	383	191	692	Tuvalu	Funafuti	1849-01-12
192	384	385	192	550	Namibia	Grootfontein	1849-06-17
193	386	387	193	1117	Tanzania	Kidodi	1849-01-27
194	388	389	194	583	Turkey	Fethiye	1849-05-17
195	390	391	195	966	Kiribati	Tarawa	1849-06-13
196	392	393	196	942	Malaysia	Ipoh	1849-02-18
197	394	395	197	230	Australia	Randwick	1849-11-18
198	396	397	198	1234	Libya	Mizdah	1849-09-14
199	398	399	199	112	Nigeria	Okigwe	1849-07-28
200	400	401	200	390	Belize	Belmopan	1849-09-17
201	402	403	201	133	Australia	Langwarrin	1849-09-02
202	404	405	202	137	Zimbabwe	Gweru	1849-06-15
203	406	407	203	254	Monaco	Monaco	1849-06-20
204	408	409	204	780	Tajikistan	Khorugh	1849-10-21
205	410	411	205	1006	Chad	Benoy	1849-08-19
206	412	413	206	1244	Ireland	Lucan	1849-04-23
207	414	415	207	481	Uzbekistan	Payshanba	1849-07-22
208	416	417	208	576	Bahrain	Sitrah	1849-04-01
209	418	419	209	1234	Guyana	Georgetown	1849-08-20
210	420	421	210	534	China	Yanjiang	1849-12-24
211	422	423	211	78	Greenland	Nuuk	1849-10-12
212	424	425	212	1239	Gibraltar	Gibraltar	1849-12-09
213	426	427	213	450	Tuvalu	Funafuti	1849-09-02
214	428	429	214	1018	Indonesia	Boyolangu	1849-10-21
215	430	431	215	444	Lebanon	Baalbek	1849-02-17
216	432	433	216	347	Guyana	Linden	1849-10-01
217	434	435	217	861	Belarus	Dzyarzhynsk	1849-12-18
218	436	437	218	395	Nicaragua	Managua	1849-10-07
219	438	439	219	261	Nauru	Yaren	1849-05-03
220	440	441	220	654	Vietnam	Vinh	1849-08-05
221	442	443	221	340	Norway	Kristiansand	1849-09-03
222	444	445	222	1054	Argentina	Fontana	1849-06-12
223	446	447	223	694	Myanmar	Syriam	1849-11-12
224	448	449	224	513	Albania	Tirana	1849-09-10
225	450	451	225	692	Burundi	Kayanza	1849-01-04
226	452	453	226	1156	Guatemala	Cuilapa	1849-09-01
227	454	455	227	1045	Iran	Qeshm	1849-09-11
228	456	457	228	110	Botswana	Janeng	1849-02-01
229	458	459	229	301	Cyprus	Protaras	1849-05-21
230	460	461	230	91	Italy	Triggiano	1849-07-11
231	462	463	231	1045	Lithuania	Taurage	1849-10-17
232	464	465	232	93	Greece	Athens	1849-10-04
233	466	467	233	1043	Mexico	Salamanca	1849-05-06
234	468	469	234	1129	Cuba	Florencia	1849-04-16
235	470	471	235	984	Belarus	Kobryn	1849-01-11
236	472	473	236	270	Ethiopia	Sebeta	1849-12-26
237	474	475	237	1177	Montserrat	Plymouth	1849-02-04
238	476	477	238	434	Bulgaria	Plovdiv	1849-08-20
239	478	479	239	671	Peru	Chulucanas	1849-04-17
240	480	481	240	1170	Uruguay	Dolores	1849-08-09
241	482	483	241	1209	Jordan	Mafraq	1849-06-11
242	484	485	242	955	Denmark	Viborg	1849-10-06
243	486	487	243	964	Switzerland	Zug	1849-08-06
244	488	489	244	845	Kenya	Nairobi	1849-08-01
245	490	491	245	908	Curacao	Willemstad	1849-03-02
246	492	493	246	900	Comoros	Moutsamoudou	1849-02-20
247	494	495	247	798	Slovenia	Ptuj	1849-12-05
248	496	497	248	90	Tanzania	Tanga	1849-03-14
249	498	499	249	11	Chad	Massakory	1849-08-12
250	500	\N	250	459	Albania	Elbasan	1849-04-06
251	\N	\N	251	343	Kenya	Eldoret	1849-12-07
252	\N	\N	252	670	Serbia	Valjevo	1849-11-24
253	\N	\N	253	819	Dominica	Roseau	1849-10-07
254	\N	\N	254	203	Niger	Magaria	1849-05-14
255	\N	\N	255	325	Austria	Linz	1849-12-10
256	\N	\N	256	1242	Bermuda	Hamilton	1824-12-17
257	\N	\N	257	648	Austria	Klosterneuburg	1824-08-03
258	\N	\N	258	527	Israel	Netivot	1824-11-28
259	\N	\N	259	191	Taiwan	Banqiao	1824-08-08
260	\N	\N	260	608	Swaziland	Lobamba	1824-04-03
261	\N	\N	261	490	Mauritania	Kiffa	1824-05-10
262	\N	\N	262	806	Ghana	Nkawkaw	1824-07-10
263	\N	\N	263	1182	Sweden	Kristianstad	1824-07-14
264	\N	\N	264	59	Pakistan	Taunsa	1824-02-09
265	\N	\N	265	781	Iceland	Akureyri	1824-08-12
266	\N	\N	266	695	Gambia	Bakau	1824-07-22
267	\N	\N	267	319	Kenya	Voi	1824-03-19
268	\N	\N	268	1178	Cameroon	Tonga	1824-06-15
269	\N	\N	269	434	Bhutan	Thimphu	1824-04-11
270	\N	\N	270	833	Ecuador	Riobamba	1824-05-10
271	\N	\N	271	1119	Afghanistan	Ghormach	1824-12-26
272	\N	\N	272	511	Mexico	Cardenas	1824-06-07
273	\N	\N	273	357	Yemen	Aden	1824-02-24
274	\N	\N	274	443	Niue	Alofi	1824-02-06
275	\N	\N	275	420	Malaysia	Ranau	1824-08-17
276	\N	\N	276	668	Malaysia	Tampin	1824-10-23
277	\N	\N	277	131	Guinea	Kissidougou	1824-07-11
278	\N	\N	278	1083	Moldova	Cahul	1824-11-25
279	\N	\N	279	119	Taiwan	Keelung	1824-12-19
280	\N	\N	280	202	Thailand	Trat	1824-01-04
281	\N	\N	281	69	Malawi	Lilongwe	1824-01-18
282	\N	\N	282	335	China	Taozhuang	1824-08-22
283	\N	\N	283	356	Kiribati	Tarawa	1824-01-07
284	\N	\N	284	218	Mali	Sagalo	1824-04-24
285	\N	\N	285	166	Greenland	Nuuk	1824-06-10
286	\N	\N	286	472	Brazil	Oliveira	1824-08-19
287	\N	\N	287	1121	India	Aruppukkottai	1824-12-02
288	\N	\N	288	1129	Afghanistan	Taloqan	1824-10-09
289	\N	\N	289	898	Kenya	Muhoroni	1824-08-13
290	\N	\N	290	708	Nicaragua	Bluefields	1824-06-25
291	\N	\N	291	589	Somalia	Beledweyne	1824-11-07
292	\N	\N	292	878	Madagascar	Faratsiho	1824-09-15
293	\N	\N	293	1107	Latvia	Tukums	1824-07-16
294	\N	\N	294	39	Bahrain	Manama	1824-05-19
295	\N	\N	295	51	Gambia	Sukuta	1824-07-20
296	\N	\N	296	720	Angola	Menongue	1824-02-12
297	\N	\N	297	68	China	Taizhou	1824-01-19
298	\N	\N	298	908	Tanzania	Mugumu	1824-02-06
299	\N	\N	299	479	Austria	Wolfsberg	1824-06-05
300	\N	\N	300	1023	Iran	Sirjan	1824-06-28
301	\N	\N	301	850	Zimbabwe	Shurugwi	1824-03-10
302	\N	\N	302	951	Hungary	Szolnok	1824-04-02
303	\N	\N	303	1175	Guatemala	Mazatenango	1824-12-12
304	\N	\N	304	267	Kenya	Kilifi	1824-04-26
305	\N	\N	305	2	Lebanon	Beirut	1824-09-28
306	\N	\N	306	1158	Nigeria	Jos	1824-01-25
307	\N	\N	307	1026	Mexico	Toluca	1824-12-20
308	\N	\N	308	962	Turkmenistan	Gazojak	1824-02-03
309	\N	\N	309	71	Canada	Victoriaville	1824-04-11
310	\N	\N	310	1043	Kazakhstan	Atyrau	1824-06-28
311	\N	\N	311	351	Tajikistan	Danghara	1824-11-03
312	\N	\N	312	870	Mauritania	Zouerate	1824-05-04
313	\N	\N	313	578	Uzbekistan	Chirchiq	1824-02-25
314	\N	\N	314	879	Guatemala	Mixco	1824-02-14
315	\N	\N	315	1159	Nepal	Hetauda	1824-01-24
316	\N	\N	316	883	Bulgaria	Kardzhali	1824-06-06
317	\N	\N	317	29	Iceland	Akureyri	1824-05-02
318	\N	\N	318	1165	Yemen	Ibb	1824-09-07
319	\N	\N	319	841	Djibouti	Obock	1824-07-01
320	\N	\N	320	739	Niger	Madaoua	1824-10-14
321	\N	\N	321	962	Botswana	Kanye	1824-04-04
322	\N	\N	322	19	Hungary	Eger	1824-11-15
323	\N	\N	323	322	France	Osny	1824-06-09
324	\N	\N	324	459	Hungary	Szombathely	1824-12-05
325	\N	\N	325	75	Israel	Tiberias	1824-11-23
326	\N	\N	326	151	Brazil	Barreiros	1824-02-10
327	\N	\N	327	881	Albania	Berat	1824-05-15
328	\N	\N	328	444	Pakistan	Hyderabad	1824-05-20
329	\N	\N	329	294	Namibia	Oshakati	1824-05-17
330	\N	\N	330	1210	Denmark	Esbjerg	1824-03-11
331	\N	\N	331	447	Moldova	Orhei	1824-02-15
332	\N	\N	332	1212	Iceland	Akureyri	1824-10-02
333	\N	\N	333	704	Tunisia	Kebili	1824-08-04
334	\N	\N	334	727	Bolivia	Tupiza	1824-10-09
335	\N	\N	335	818	France	Lens	1824-01-15
336	\N	\N	336	832	Jordan	Jarash	1824-09-21
337	\N	\N	337	791	Madagascar	Ikalamavony	1824-10-28
338	\N	\N	338	224	Oman	Khasab	1824-08-14
339	\N	\N	339	348	Botswana	Mahalapye	1824-01-24
340	\N	\N	340	1129	Niue	Alofi	1824-04-19
341	\N	\N	341	415	Barbados	Bridgetown	1824-05-19
342	\N	\N	342	430	Niger	Dakoro	1824-08-05
343	\N	\N	343	597	Armenia	Gavarr	1824-04-26
344	\N	\N	344	1155	Cameroon	Foumban	1824-05-13
345	\N	\N	345	352	Niue	Alofi	1824-10-13
346	\N	\N	346	1232	Mongolia	Erdenet	1824-10-07
347	\N	\N	347	996	Argentina	Caucete	1824-09-15
348	\N	\N	348	669	Seychelles	Victoria	1824-04-22
349	\N	\N	349	130	India	Afzalgarh	1824-10-11
350	\N	\N	350	647	Tunisia	Metlaoui	1824-07-24
351	\N	\N	351	861	Lithuania	Palanga	1824-12-14
352	\N	\N	352	851	Belize	Belmopan	1824-11-11
353	\N	\N	353	1129	Kosovo	Gjilan	1824-08-07
354	\N	\N	354	239	Tunisia	Tataouine	1824-07-09
355	\N	\N	355	267	Nicaragua	Nagarote	1824-09-17
356	\N	\N	356	1119	Tajikistan	Chkalov	1824-11-13
357	\N	\N	357	1239	Turkey	Kestel	1824-04-27
358	\N	\N	358	515	Romania	Giurgiu	1824-05-14
359	\N	\N	359	411	Lithuania	Alytus	1824-09-15
360	\N	\N	360	512	Qatar	Doha	1824-12-01
361	\N	\N	361	392	Armenia	Armavir	1824-09-10
362	\N	\N	362	294	Nauru	Yaren	1824-03-21
363	\N	\N	363	766	Oman	Seeb	1824-07-26
364	\N	\N	364	1054	Bhutan	Phuntsholing	1824-03-04
365	\N	\N	365	539	Bermuda	Hamilton	1824-04-16
366	\N	\N	366	745	Panama	Pacora	1824-12-19
367	\N	\N	367	984	Russia	Klimovsk	1824-12-04
368	\N	\N	368	271	Montserrat	Brades	1824-10-16
369	\N	\N	369	393	Tunisia	Siliana	1824-12-03
370	\N	\N	370	1211	Bahrain	Sitrah	1824-04-28
371	\N	\N	371	455	Armenia	Masis	1824-11-16
372	\N	\N	372	551	Tanzania	Kidodi	1824-11-10
373	\N	\N	373	736	Georgia	Samtredia	1824-03-07
374	\N	\N	374	1056	Slovenia	Maribor	1824-08-03
375	\N	\N	375	800	Venezuela	Chivacoa	1824-07-19
376	\N	\N	376	597	Bahamas	Lucaya	1824-11-28
377	\N	\N	377	1078	Montserrat	Brades	1824-03-15
378	\N	\N	378	188	Nigeria	Ibi	1824-09-02
379	\N	\N	379	399	Malta	Birkirkara	1824-07-11
380	\N	\N	380	647	Nigeria	Ekpoma	1824-12-17
381	\N	\N	381	485	Georgia	Kobuleti	1824-08-19
382	\N	\N	382	517	Maldives	Male	1824-01-27
383	\N	\N	383	685	Benin	Ouidah	1824-08-18
384	\N	\N	384	802	Senegal	Pourham	1824-11-23
385	\N	\N	385	254	Lesotho	Mafeteng	1824-01-13
386	\N	\N	386	576	Samoa	Apia	1824-02-26
387	\N	\N	387	237	Oman	Muscat	1824-03-19
388	\N	\N	388	833	Comoros	Moroni	1824-02-22
389	\N	\N	389	1205	Belize	Belmopan	1824-09-02
390	\N	\N	390	914	India	Rameswaram	1824-12-23
391	\N	\N	391	936	Lebanon	Sidon	1824-09-08
392	\N	\N	392	778	Laos	Phonsavan	1824-03-03
393	\N	\N	393	531	Italy	Velletri	1824-05-05
394	\N	\N	394	200	Luxembourg	Luxembourg	1824-08-20
395	\N	\N	395	952	Venezuela	Caucaguita	1824-10-11
396	\N	\N	396	1088	Colombia	Tunja	1824-03-18
397	\N	\N	397	1158	Norway	Haugesund	1824-12-02
398	\N	\N	398	682	Zambia	Mansa	1824-07-04
399	\N	\N	399	896	Brunei	Seria	1824-11-24
400	\N	\N	400	1028	Aruba	Angochi	1824-04-07
401	\N	\N	401	578	Pitcairn	Adamstown	1824-11-06
403	\N	\N	403	1002	Samoa	Apia	1824-11-23
404	\N	\N	404	3	Venezuela	Maracaibo	1824-09-25
405	\N	\N	405	877	Taiwan	Puli	1824-12-09
406	\N	\N	406	877	Liechtenstein	Vaduz	1824-09-26
407	\N	\N	407	1159	Lesotho	Mafeteng	1824-11-17
408	\N	\N	408	244	Guatemala	Esquipulas	1824-12-01
409	\N	\N	409	344	Bhutan	Phuntsholing	1824-04-07
410	\N	\N	410	1213	Australia	Coburg	1824-03-16
411	\N	\N	411	663	Tanzania	Isaka	1824-05-04
412	\N	\N	412	731	Pitcairn	Adamstown	1824-03-18
413	\N	\N	413	997	Venezuela	Tucupita	1824-05-21
414	\N	\N	414	575	Mali	Sagalo	1824-05-08
415	\N	\N	415	333	Germany	Gartenstadt	1824-09-19
416	\N	\N	416	554	Ukraine	Vyshhorod	1824-10-05
417	\N	\N	417	664	Kosovo	Podujeva	1824-04-22
418	\N	\N	418	681	Greece	Chios	1824-01-08
419	\N	\N	419	890	Senegal	Matam	1824-07-19
420	\N	\N	420	1063	Cuba	Boyeros	1824-12-27
421	\N	\N	421	894	Belarus	Pastavy	1824-12-16
422	\N	\N	422	767	Germany	Velbert	1824-09-23
423	\N	\N	423	1153	Nepal	Nepalgunj	1824-09-23
424	\N	\N	424	37	Uzbekistan	Showot	1824-05-17
425	\N	\N	425	965	Ecuador	Machala	1824-06-14
426	\N	\N	426	1063	Finland	Pirkkala	1824-07-10
427	\N	\N	427	1232	Belize	Belmopan	1824-08-12
428	\N	\N	428	22	Croatia	Split	1824-03-21
429	\N	\N	429	486	Nigeria	Lalupon	1824-08-17
430	\N	\N	430	272	Ecuador	Cuenca	1824-08-18
431	\N	\N	431	441	Turkmenistan	Seydi	1824-04-28
432	\N	\N	432	571	Canada	Dorval	1824-01-01
433	\N	\N	433	539	Liberia	Greenville	1824-01-01
434	\N	\N	434	153	Panama	Veracruz	1824-07-11
435	\N	\N	435	922	Togo	Badou	1824-06-06
436	\N	\N	436	397	Paraguay	Limpio	1824-09-24
437	\N	\N	437	807	Bangladesh	Tungi	1824-02-01
438	\N	\N	438	1230	Somalia	Buurhakaba	1824-05-17
439	\N	\N	439	588	Latvia	Ventspils	1824-01-13
440	\N	\N	440	737	Finland	Sibbo	1824-07-13
441	\N	\N	441	503	Gabon	Moanda	1824-07-26
442	\N	\N	442	371	Montenegro	Pljevlja	1824-03-24
443	\N	\N	443	532	Barbados	Bridgetown	1824-05-17
444	\N	\N	444	1204	Morocco	Guelmim	1824-10-24
445	\N	\N	445	34	Sweden	Landskrona	1824-01-15
446	\N	\N	446	980	Bahamas	Freeport	1824-11-21
447	\N	\N	447	1231	Liechtenstein	Vaduz	1824-11-08
448	\N	\N	448	297	Zimbabwe	Zvishavane	1824-06-11
449	\N	\N	449	959	Namibia	Swakopmund	1824-09-02
450	\N	\N	450	916	Guyana	Georgetown	1824-03-19
451	\N	\N	451	743	China	Wucheng	1824-10-12
452	\N	\N	452	676	Finland	Lohja	1824-06-09
453	\N	\N	453	1040	Syria	Aleppo	1824-10-04
454	\N	\N	454	1246	Yemen	Ataq	1824-03-10
455	\N	\N	455	896	Suriname	Lelydorp	1824-11-10
456	\N	\N	456	568	Chile	Victoria	1824-01-18
457	\N	\N	457	360	Serbia	Trstenik	1824-07-03
458	\N	\N	458	143	Myanmar	Yangon	1824-05-27
459	\N	\N	459	953	Mayotte	Koungou	1824-09-03
460	\N	\N	460	579	Norway	Molde	1824-11-01
461	\N	\N	461	780	France	Frontignan	1824-01-11
462	\N	\N	462	1234	Tajikistan	Yovon	1824-09-08
463	\N	\N	463	939	Oman	Rustaq	1824-01-28
464	\N	\N	464	648	Poland	Krakow	1824-08-14
465	\N	\N	465	248	Ethiopia	Gondar	1824-05-01
466	\N	\N	466	578	Australia	Mosman	1824-01-21
467	\N	\N	467	1032	Canada	Courtenay	1824-07-03
468	\N	\N	468	139	Estonia	Tartu	1824-11-28
469	\N	\N	469	539	Jamaica	Portmore	1824-04-22
470	\N	\N	470	405	Tajikistan	Tursunzoda	1824-06-24
471	\N	\N	471	51	Slovenia	Velenje	1824-12-01
472	\N	\N	472	411	Nicaragua	Camoapa	1824-06-11
473	\N	\N	473	779	Indonesia	Kutoarjo	1824-09-09
474	\N	\N	474	38	Pakistan	Talamba	1824-01-16
475	\N	\N	475	467	Chad	Kelo	1824-05-06
476	\N	\N	476	1039	India	Narauli	1824-09-26
477	\N	\N	477	131	Gibraltar	Gibraltar	1824-12-25
478	\N	\N	478	100	Greenland	Nuuk	1824-06-26
479	\N	\N	479	599	Tanzania	Kilosa	1824-01-06
480	\N	\N	480	344	Guinea	Kindia	1824-10-21
481	\N	\N	481	664	India	Chennai	1824-02-19
482	\N	\N	482	518	Luxembourg	Luxembourg	1824-06-09
483	\N	\N	483	1117	Panama	Chepo	1824-04-01
484	\N	\N	484	656	Bahamas	Lucaya	1824-01-10
485	\N	\N	485	951	Cyprus	Larnaca	1824-01-05
486	\N	\N	486	1234	Ecuador	Quito	1824-02-11
487	\N	\N	487	969	Estonia	Rakvere	1824-09-19
488	\N	\N	488	584	Hungary	Hatvan	1824-12-21
489	\N	\N	489	816	Liechtenstein	Vaduz	1824-11-28
490	\N	\N	490	610	Moldova	Cahul	1824-06-27
491	\N	\N	491	358	Colombia	Turbaco	1824-09-21
492	\N	\N	492	356	Eritrea	Barentu	1824-09-03
493	\N	\N	493	69	Nepal	Malangwa	1824-06-24
494	\N	\N	494	390	Turkey	Marmaris	1824-04-09
495	\N	\N	495	130	Kiribati	Tarawa	1824-06-12
496	\N	\N	496	734	Belarus	Vawkavysk	1824-09-08
497	\N	\N	497	170	Turkey	Adana	1824-10-18
498	\N	\N	498	959	Liberia	Bensonville	1824-06-06
499	\N	\N	499	93	Zambia	Ndola	1824-05-28
500	\N	\N	500	568	Thailand	Trat	1824-01-21
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
1	519	8	2016-07-22
2	151	11	2007-10-05
3	856	16	1976-09-22
4	147	17	2001-06-27
5	687	18	1998-02-27
6	378	19	1977-03-11
7	97	20	1974-10-13
8	209	21	1989-10-20
9	60	22	2001-02-08
10	1081	23	2002-12-11
11	491	24	1988-06-13
12	110	25	1997-11-16
13	612	26	2001-09-10
14	790	27	2017-10-01
15	1030	28	2003-04-25
16	493	29	2002-08-12
17	1181	30	1991-08-16
18	816	31	1975-03-25
19	411	32	1987-07-26
20	130	33	1995-08-04
21	601	34	1980-07-05
22	1040	35	1966-12-22
23	607	36	1978-03-23
24	685	37	1992-01-09
25	503	38	1995-11-26
26	723	39	1981-08-23
27	63	40	1993-09-04
28	357	41	1974-11-26
29	615	42	1959-01-19
30	283	43	1970-10-06
31	329	44	1958-01-03
32	627	45	1967-06-11
33	704	46	1982-05-12
34	568	47	1963-11-14
35	360	48	1984-03-21
36	1054	49	1976-10-12
37	381	50	1954-10-08
38	340	51	1995-01-13
39	805	52	1993-10-15
40	162	53	1992-11-01
41	1026	54	1963-02-17
42	644	55	1973-02-13
43	944	56	1999-05-24
44	1155	57	1986-05-22
45	1028	58	1994-05-09
46	684	59	1969-06-04
47	237	60	1954-03-02
48	1117	61	1985-07-25
49	200	62	1978-10-08
50	856	63	1973-03-05
51	545	64	1927-09-10
52	795	65	1964-09-17
53	198	66	1937-11-01
54	1179	67	1932-07-15
55	22	68	1933-07-13
56	1006	69	1939-03-12
57	1187	70	1953-03-26
58	293	71	1972-07-15
59	853	72	1967-08-21
60	1220	73	1953-08-19
61	474	74	1969-01-07
62	39	75	1961-07-17
63	715	76	1969-01-28
64	187	77	1942-12-11
65	760	78	1925-03-15
66	1016	79	1944-06-18
67	1156	80	1940-01-28
68	700	81	1928-12-21
69	297	82	1945-03-06
70	948	83	1927-05-09
71	620	84	1955-04-23
72	68	85	1970-12-08
73	559	86	1962-08-06
74	149	87	1962-11-07
75	1170	88	1963-03-08
76	444	89	1928-03-17
77	1179	90	1941-10-15
78	963	91	1934-06-23
79	757	92	1934-08-19
80	800	93	1942-04-17
81	969	94	1938-05-23
82	383	95	1944-05-13
83	892	96	1953-01-19
84	603	97	1972-05-09
85	37	98	1941-02-10
86	381	99	1928-02-06
87	714	100	1931-09-16
88	1205	101	1945-07-09
89	969	102	1971-03-23
90	669	103	1955-01-16
91	436	104	1966-09-03
92	549	105	1963-11-23
93	418	106	1971-01-07
94	1203	107	1974-09-04
95	806	108	1965-12-19
96	495	109	1932-03-19
97	348	110	1966-09-18
98	335	111	1926-07-24
99	677	112	1953-04-04
100	254	113	1931-11-21
101	810	114	1970-01-26
102	162	115	1924-01-01
103	1247	116	1924-01-25
104	652	117	1955-03-18
105	145	118	1940-08-27
106	1060	119	1929-09-14
107	705	120	1970-10-09
108	818	121	1968-05-24
109	1166	122	1927-09-10
110	399	123	1938-04-27
111	1205	124	1952-03-21
112	375	125	1937-09-19
113	30	126	1939-08-26
114	49	127	1930-01-13
115	429	128	1919-08-10
116	1008	129	1908-08-03
117	251	130	1902-09-27
118	727	131	1943-07-11
119	924	132	1944-01-19
120	720	133	1944-02-07
121	294	134	1901-08-27
122	915	135	1944-02-28
123	936	136	1900-07-04
124	219	137	1905-06-20
125	890	138	1942-02-08
126	778	139	1932-04-28
127	181	140	1927-03-02
128	898	141	1900-05-15
129	1175	142	1934-11-10
130	1150	143	1915-12-20
131	63	144	1911-02-05
132	902	145	1946-04-22
133	355	146	1908-03-24
134	1212	147	1949-05-11
135	86	148	1928-09-20
136	992	149	1936-09-26
137	816	150	1935-02-10
138	323	151	1943-04-24
139	850	152	1932-06-15
140	995	153	1935-07-01
141	38	154	1910-01-25
142	531	155	1940-04-01
143	102	156	1901-02-09
144	639	157	1902-09-14
145	124	158	1949-03-20
146	671	159	1906-08-09
147	664	160	1945-11-05
148	907	161	1922-09-03
149	687	162	1909-07-09
150	835	163	1916-06-01
151	396	164	1930-08-28
152	513	165	1906-09-04
153	962	166	1902-01-16
154	1249	167	1913-12-19
155	160	168	1930-10-25
156	383	169	1908-05-28
157	1056	170	1904-03-06
158	779	171	1914-08-16
159	550	172	1938-07-17
160	368	173	1920-11-09
161	805	174	1924-05-21
162	301	175	1942-05-22
163	71	176	1905-09-27
164	232	177	1949-03-14
165	216	178	1939-02-11
166	777	179	1938-12-02
167	1093	180	1907-04-09
168	1219	181	1919-06-14
169	294	182	1948-07-11
170	1109	183	1926-06-03
171	703	184	1945-09-17
172	1175	185	1924-07-26
173	291	186	1909-11-18
174	1020	187	1915-09-26
175	97	188	1933-04-15
176	743	189	1914-12-15
177	905	190	1905-07-23
178	179	191	1917-05-07
179	953	192	1942-09-15
180	790	193	1944-03-09
181	666	194	1937-04-28
182	107	195	1911-01-10
183	40	196	1916-01-16
184	29	197	1907-10-09
185	207	198	1930-01-27
186	130	199	1922-08-11
187	322	200	1917-08-11
188	151	201	1943-07-12
189	112	202	1923-03-26
190	500	203	1913-01-24
191	892	204	1923-04-24
192	34	205	1902-12-01
193	483	206	1935-05-09
194	1049	207	1926-02-19
195	523	208	1929-06-18
196	824	209	1944-04-28
197	1051	210	1924-07-17
198	637	211	1902-08-13
199	241	212	1937-12-12
200	1019	213	1921-02-26
201	631	214	1903-11-06
202	907	215	1899-10-23
203	1220	216	1922-11-17
204	399	217	1913-09-14
205	469	218	1936-03-18
206	1010	219	1926-02-16
207	974	220	1916-03-28
208	1099	221	1904-09-10
209	656	222	1899-10-20
210	311	223	1901-06-14
211	1207	224	1946-03-25
212	545	225	1902-10-05
213	955	226	1926-08-09
214	430	227	1921-10-03
215	1179	228	1927-12-17
216	387	229	1902-05-26
217	1224	230	1918-07-24
218	1234	231	1903-05-06
219	800	232	1914-03-07
220	974	233	1934-12-04
221	1155	234	1909-11-07
222	392	235	1912-08-06
223	85	236	1924-03-09
224	85	237	1927-10-21
225	798	238	1929-07-14
226	721	239	1905-11-22
227	29	240	1920-05-23
228	638	241	1899-08-22
229	1175	242	1942-06-10
230	1188	243	1906-12-27
231	510	244	1920-05-05
232	1207	245	1925-10-25
233	457	246	1905-05-07
234	928	247	1940-03-03
235	523	248	1929-09-07
236	82	249	1935-05-09
237	170	250	1903-12-13
238	578	251	1920-09-12
239	1038	252	1900-09-01
240	1246	253	1906-08-25
241	130	254	1910-09-24
242	649	255	1917-10-01
243	278	256	1914-12-16
244	826	257	1886-08-02
245	96	258	1877-09-21
246	965	259	1888-08-16
247	844	260	1915-01-13
248	431	261	1886-05-03
249	1221	262	1884-08-21
250	359	263	1890-01-22
251	577	264	1884-08-07
252	490	265	1906-12-13
253	515	266	1895-02-02
254	278	267	1921-02-05
255	1016	268	1874-07-20
256	674	269	1894-11-16
257	1021	270	1885-10-22
258	310	271	1880-05-20
259	1203	272	1910-10-06
260	1040	273	1908-07-18
261	137	274	1905-07-14
262	765	275	1878-04-17
263	19	276	1894-12-12
264	145	277	1883-10-15
265	354	278	1882-06-12
266	75	279	1914-05-13
267	637	280	1907-01-16
268	54	281	1896-05-22
269	379	282	1896-02-28
270	661	283	1906-06-22
271	1099	284	1888-01-12
272	269	285	1904-04-17
273	575	286	1917-02-22
274	601	287	1924-02-03
275	472	288	1907-11-22
276	115	289	1894-03-24
277	869	290	1881-04-19
278	360	291	1880-12-13
279	166	292	1875-09-23
280	953	293	1908-08-20
281	296	294	1908-07-09
282	1222	295	1920-03-07
283	1176	296	1917-10-19
284	1068	297	1885-06-18
285	1093	298	1899-07-11
286	810	299	1916-03-05
287	1054	300	1886-07-25
288	922	301	1876-12-25
289	381	302	1916-01-02
290	907	303	1900-08-03
291	418	304	1918-06-04
292	1178	305	1910-11-19
293	841	306	1881-12-08
294	472	307	1892-11-14
295	825	308	1902-12-16
296	697	309	1914-12-09
297	841	310	1877-01-21
298	760	311	1924-09-06
299	1041	312	1906-05-14
300	725	313	1899-05-18
301	524	314	1915-10-14
302	608	315	1909-06-25
303	489	316	1923-02-14
304	963	317	1898-01-18
305	1150	318	1903-11-08
306	1224	319	1880-09-23
307	199	320	1877-07-07
308	22	321	1904-03-09
309	248	322	1924-08-14
310	1212	323	1891-08-08
311	14	324	1874-07-10
312	34	325	1901-09-01
313	425	326	1887-08-11
314	839	327	1874-07-14
315	378	328	1921-05-23
316	52	329	1893-04-08
317	145	330	1885-03-15
318	509	331	1900-11-09
319	647	332	1874-09-23
320	82	333	1874-05-13
321	654	334	1879-04-24
322	964	335	1895-07-13
323	699	336	1894-06-28
324	143	337	1914-06-01
325	941	338	1923-08-01
326	198	339	1894-05-19
327	1032	340	1907-03-15
328	69	341	1884-02-12
329	372	342	1879-11-15
330	714	343	1910-12-21
331	976	344	1906-04-08
332	1041	345	1878-03-17
333	807	346	1900-07-26
334	371	347	1912-10-20
335	793	348	1890-04-24
336	196	349	1874-12-19
337	463	350	1892-02-12
338	423	351	1909-05-06
339	1227	352	1922-06-11
340	697	353	1924-08-27
341	1220	354	1923-04-09
342	825	355	1896-08-01
343	795	356	1890-12-25
344	271	357	1885-02-25
345	376	358	1901-12-01
346	505	359	1877-08-10
347	724	360	1919-07-23
348	796	361	1917-06-04
349	802	362	1902-07-25
350	377	363	1909-07-26
351	265	364	1889-07-28
352	165	365	1917-10-14
353	715	366	1885-08-12
354	916	367	1913-03-05
355	1247	368	1880-02-18
356	144	369	1909-02-22
357	1015	370	1909-04-18
358	983	371	1891-12-22
359	426	372	1917-11-14
360	434	373	1902-01-08
361	415	374	1900-10-02
362	808	375	1884-03-06
363	908	376	1888-11-14
364	1157	377	1913-09-18
365	251	378	1904-03-01
366	1003	379	1900-09-06
367	139	380	1913-11-06
368	919	381	1890-09-01
369	133	382	1890-01-07
370	1107	383	1907-03-17
371	535	384	1905-03-19
372	435	385	1917-09-15
373	191	386	1904-05-13
374	470	387	1914-03-02
375	1232	388	1906-04-14
376	1006	389	1880-10-21
377	393	390	1920-08-09
378	676	391	1914-04-22
379	226	392	1923-05-27
380	372	393	1900-02-21
381	936	394	1910-06-11
382	269	395	1923-12-13
383	1049	396	1876-12-03
384	451	397	1883-02-01
385	890	398	1888-08-16
386	970	399	1908-05-12
387	978	400	1908-02-18
388	200	401	1875-03-23
389	465	402	1890-03-12
390	131	403	1900-01-12
391	891	404	1882-12-20
392	654	405	1924-05-05
393	1039	406	1879-04-14
394	404	407	1921-02-17
395	503	408	1889-11-08
396	415	409	1903-04-16
397	1234	410	1900-12-01
398	200	411	1917-09-20
399	1227	412	1875-03-01
400	1041	413	1904-05-09
401	707	414	1888-03-01
402	1153	415	1909-11-26
403	734	416	1903-08-04
404	405	417	1898-12-04
405	1233	418	1918-04-08
406	50	419	1916-08-02
407	519	420	1903-09-04
408	720	421	1891-07-17
409	816	422	1896-03-19
410	397	423	1879-03-20
411	549	424	1902-01-16
412	1194	425	1905-05-01
413	986	426	1881-08-24
414	1081	427	1921-10-04
415	708	428	1911-05-07
416	230	429	1919-10-16
417	974	430	1906-06-04
418	1164	431	1888-11-02
419	1151	432	1897-04-04
420	687	433	1901-09-19
421	45	434	1914-01-20
422	1086	435	1890-07-16
423	322	436	1887-05-13
424	697	437	1913-10-02
425	1243	438	1922-09-03
426	232	439	1915-02-09
427	583	440	1900-07-21
428	964	441	1917-05-17
429	212	442	1897-06-24
430	914	443	1882-09-22
431	315	444	1911-03-04
432	271	445	1919-07-07
433	926	446	1876-10-13
434	693	447	1902-07-18
435	919	448	1924-06-07
436	9	449	1924-05-28
437	1176	450	1877-06-01
438	36	451	1893-07-20
439	539	452	1911-08-17
440	515	453	1881-08-10
441	151	454	1881-08-13
442	1243	455	1882-04-02
443	568	456	1890-11-10
444	819	457	1881-11-05
445	1247	458	1901-08-21
446	798	459	1898-07-23
447	107	460	1899-11-12
448	241	461	1914-08-18
449	393	462	1882-06-10
450	1008	463	1894-12-26
451	703	464	1882-09-13
452	217	465	1887-03-10
453	1183	466	1920-07-10
454	226	467	1889-07-16
455	411	468	1886-08-02
456	1033	469	1899-02-24
457	1007	470	1896-12-01
458	442	471	1898-10-27
459	1178	472	1899-11-16
460	822	473	1914-01-01
461	894	474	1919-12-08
462	87	475	1905-11-24
463	156	476	1891-03-11
464	518	477	1876-12-04
465	797	478	1917-01-22
466	490	479	1876-02-17
467	1022	480	1903-12-13
468	1246	481	1907-12-05
469	784	482	1912-12-23
470	822	483	1886-11-16
471	493	484	1899-09-03
472	850	485	1916-03-18
473	838	486	1881-04-01
474	869	487	1875-10-13
475	705	488	1912-03-20
476	535	489	1881-03-08
477	598	490	1919-10-23
478	241	491	1914-10-03
479	1218	492	1902-01-17
480	1227	493	1901-04-21
481	955	494	1896-09-13
482	1021	495	1911-06-06
483	623	496	1907-03-08
484	833	497	1920-09-25
485	523	498	1905-08-23
486	144	499	1915-08-14
487	707	500	1919-05-28
\.


--
-- Data for Name: divorce_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorce_certificates (id, divorce_id, issue_date, issuer) FROM stdin;
1	1	2000-04-10	703
2	2	1985-12-14	987
3	3	1988-10-20	516
4	4	1953-10-23	814
5	5	1950-05-11	845
6	6	1951-11-11	34
7	7	1959-02-19	805
8	8	1961-06-23	492
9	9	1925-11-27	292
10	10	1934-02-19	177
11	11	1935-02-28	1122
12	12	1938-06-16	650
13	13	1931-07-07	640
14	14	1923-09-17	663
15	15	1920-04-03	289
16	16	1932-02-10	1197
17	17	1920-04-07	303
18	18	1921-07-08	127
19	19	1939-11-04	1157
20	20	1923-11-05	389
21	21	1935-05-28	355
22	22	1909-11-27	155
23	23	1907-03-08	619
24	24	1896-05-10	829
25	25	1913-02-09	66
26	26	1898-05-27	567
27	27	1895-08-11	678
28	28	1909-01-18	1026
29	29	1896-04-13	455
30	30	1908-12-20	150
31	31	1911-12-11	536
32	32	1901-01-10	33
33	33	1900-07-22	143
34	34	1895-12-09	617
35	35	1905-10-20	234
36	36	1907-08-22	234
37	37	1902-12-25	911
38	38	1900-02-08	282
39	39	1907-03-06	710
40	40	1894-09-13	1072
41	41	1906-06-25	1160
42	42	1915-03-20	707
43	43	1891-04-08	1042
44	44	1870-02-08	96
45	45	1883-09-16	669
46	46	1874-05-02	194
47	47	1891-03-21	510
48	48	1882-01-18	1004
49	49	1879-05-16	568
50	50	1886-12-05	43
51	51	1878-04-09	104
52	52	1883-06-15	317
53	53	1890-12-26	846
54	54	1884-03-12	485
55	55	1885-07-01	887
56	56	1879-12-26	1125
57	57	1874-09-21	155
58	58	1881-08-04	11
59	59	1875-03-18	621
60	60	1887-04-14	415
61	61	1880-07-05	1221
62	62	1877-12-21	1088
63	63	1867-09-24	1210
64	64	1886-11-08	13
65	65	1881-10-19	1089
66	66	1882-09-05	177
67	67	1871-02-16	634
68	68	1885-04-07	464
69	69	1878-07-16	53
70	70	1880-02-18	135
71	71	1883-03-01	1003
72	72	1869-02-12	700
73	73	1878-01-03	636
74	74	1884-04-23	451
75	75	1877-01-26	903
76	76	1877-10-04	1205
77	77	1883-05-02	957
78	78	1868-04-17	167
79	79	1881-11-23	91
80	80	1892-03-03	822
81	81	1871-11-23	678
82	82	1877-08-18	1243
83	83	1879-04-26	487
84	84	1886-12-02	805
85	85	1868-09-28	113
86	86	1885-06-12	344
87	87	1874-07-21	11
88	88	1873-04-11	679
89	89	1883-05-12	377
90	90	1886-02-15	117
91	91	1890-03-12	749
92	92	1871-05-28	516
93	93	1846-05-20	491
94	94	1856-07-13	479
95	95	1849-06-24	665
96	96	1852-12-07	544
97	97	1851-12-08	831
98	98	1863-03-05	732
99	99	1859-04-12	443
100	100	1854-02-20	817
101	101	1863-08-25	790
102	102	1856-07-27	1028
103	103	1864-01-25	481
104	104	1853-04-09	1124
105	105	1859-06-18	139
106	106	1851-09-11	850
107	107	1858-12-28	111
108	108	1851-06-25	904
109	109	1857-09-19	532
110	110	1852-11-22	656
111	111	1855-02-10	689
112	112	1852-05-16	187
113	113	1863-05-12	340
114	114	1848-01-06	220
115	115	1857-09-06	490
116	116	1846-07-10	670
117	117	1858-07-04	495
118	118	1853-03-14	922
119	119	1852-08-26	986
120	120	1851-11-10	464
121	121	1845-05-14	168
122	122	1851-04-20	34
123	123	1847-10-25	435
124	124	1855-06-23	569
125	125	1853-01-28	922
126	126	1848-05-10	138
127	127	1863-11-26	130
128	128	1854-06-01	287
129	129	1860-02-28	165
130	130	1858-04-01	1014
131	131	1867-02-28	639
132	132	1841-03-06	559
133	133	1863-03-09	845
134	134	1855-10-06	229
135	135	1855-12-04	425
136	136	1861-04-17	465
137	137	1845-03-08	734
138	138	1855-11-02	399
139	139	1854-06-07	882
140	140	1856-04-25	704
141	141	1859-12-17	1036
142	142	1854-08-10	143
143	143	1860-10-04	934
144	144	1860-04-25	207
145	145	1851-10-09	720
146	146	1853-01-05	956
147	147	1848-04-01	63
148	148	1865-06-06	349
149	149	1855-04-24	619
150	150	1846-01-18	116
151	151	1851-04-18	1170
152	152	1855-08-28	772
153	153	1862-04-26	557
154	154	1851-04-03	957
155	155	1856-03-23	784
156	156	1860-05-13	357
157	157	1855-11-21	170
158	158	1850-06-12	972
159	159	1847-12-18	708
160	160	1865-04-19	504
161	161	1860-09-22	139
162	162	1862-12-16	1248
163	163	1861-09-27	487
164	164	1858-12-22	684
165	165	1846-06-25	1245
166	166	1861-01-01	686
167	167	1862-04-17	686
168	168	1851-10-25	1063
169	169	1861-11-11	784
170	170	1861-04-04	32
171	171	1855-10-20	286
172	172	1858-03-21	1243
173	173	1861-10-24	305
174	174	1861-02-02	424
175	175	1850-11-05	616
176	176	1856-07-20	883
177	177	1860-09-12	1120
178	178	1858-12-25	716
179	179	1856-08-11	650
\.


--
-- Data for Name: divorces; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.divorces (id, marriage_id, divorce_date) FROM stdin;
1	2	2000-04-10
2	5	1985-12-14
3	6	1988-10-20
4	8	1953-10-23
5	10	1950-05-11
6	12	1951-11-11
7	13	1959-02-19
8	15	1961-06-23
9	16	1925-11-27
10	17	1934-02-19
11	18	1935-02-28
12	19	1938-06-16
13	20	1931-07-07
14	22	1923-09-17
15	24	1920-04-03
16	25	1932-02-10
17	26	1920-04-07
18	27	1921-07-08
19	28	1939-11-04
20	29	1923-11-05
21	30	1935-05-28
22	32	1909-11-27
23	34	1907-03-08
24	35	1896-05-10
25	36	1913-02-09
26	37	1898-05-27
27	40	1895-08-11
28	41	1909-01-18
29	42	1896-04-13
30	45	1908-12-20
31	46	1911-12-11
32	48	1901-01-10
33	49	1900-07-22
34	50	1895-12-09
35	51	1905-10-20
36	52	1907-08-22
37	54	1902-12-25
38	55	1900-02-08
39	57	1907-03-06
40	58	1894-09-13
41	59	1906-06-25
42	63	1915-03-20
43	64	1891-04-08
44	65	1870-02-08
45	67	1883-09-16
46	69	1874-05-02
47	70	1891-03-21
48	71	1882-01-18
49	72	1879-05-16
50	73	1886-12-05
51	75	1878-04-09
52	76	1883-06-15
53	77	1890-12-26
54	80	1884-03-12
55	81	1885-07-01
56	82	1879-12-26
57	84	1874-09-21
58	85	1881-08-04
59	86	1875-03-18
60	87	1887-04-14
61	88	1880-07-05
62	89	1877-12-21
63	92	1867-09-24
64	93	1886-11-08
65	94	1881-10-19
66	95	1882-09-05
67	99	1871-02-16
68	100	1885-04-07
69	102	1878-07-16
70	103	1880-02-18
71	104	1883-03-01
72	105	1869-02-12
73	106	1878-01-03
74	107	1884-04-23
75	108	1877-01-26
76	109	1877-10-04
77	110	1883-05-02
78	111	1868-04-17
79	112	1881-11-23
80	113	1892-03-03
81	114	1871-11-23
82	116	1877-08-18
83	117	1879-04-26
84	119	1886-12-02
85	120	1868-09-28
86	121	1885-06-12
87	122	1874-07-21
88	123	1873-04-11
89	124	1883-05-12
90	125	1886-02-15
91	126	1890-03-12
92	127	1871-05-28
93	128	1846-05-20
94	129	1856-07-13
95	130	1849-06-24
96	133	1852-12-07
97	134	1851-12-08
98	135	1863-03-05
99	136	1859-04-12
100	137	1854-02-20
101	138	1863-08-25
102	139	1856-07-27
103	140	1864-01-25
104	141	1853-04-09
105	142	1859-06-18
106	144	1851-09-11
107	147	1858-12-28
108	148	1851-06-25
109	149	1857-09-19
110	150	1852-11-22
111	151	1855-02-10
112	152	1852-05-16
113	153	1863-05-12
114	155	1848-01-06
115	156	1857-09-06
116	158	1846-07-10
117	161	1858-07-04
118	162	1853-03-14
119	165	1852-08-26
120	166	1851-11-10
121	169	1845-05-14
122	170	1851-04-20
123	173	1847-10-25
124	175	1855-06-23
125	176	1853-01-28
126	177	1848-05-10
127	178	1863-11-26
128	179	1854-06-01
129	180	1860-02-28
130	182	1858-04-01
131	183	1867-02-28
132	184	1841-03-06
133	185	1863-03-09
134	186	1855-10-06
135	187	1855-12-04
136	188	1861-04-17
137	189	1845-03-08
138	192	1855-11-02
139	193	1854-06-07
140	194	1856-04-25
141	195	1859-12-17
142	196	1854-08-10
143	198	1860-10-04
144	199	1860-04-25
145	200	1851-10-09
146	202	1853-01-05
147	203	1848-04-01
148	205	1865-06-06
149	206	1855-04-24
150	207	1846-01-18
151	208	1851-04-18
152	210	1855-08-28
153	211	1862-04-26
154	213	1851-04-03
155	215	1856-03-23
156	216	1860-05-13
157	217	1855-11-21
158	218	1850-06-12
159	220	1847-12-18
160	221	1865-04-19
161	222	1860-09-22
162	223	1862-12-16
163	225	1861-09-27
164	226	1858-12-22
165	231	1846-06-25
166	233	1861-01-01
167	235	1862-04-17
168	236	1851-10-25
169	237	1861-11-11
170	239	1861-04-04
171	240	1855-10-20
172	241	1858-03-21
173	242	1861-10-24
174	243	1861-02-02
175	244	1850-11-05
176	245	1856-07-20
177	247	1860-09-12
178	248	1858-12-25
179	249	1856-08-11
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
3	Visa
\.


--
-- Data for Name: drivers_licences; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.drivers_licences (id, type, person, issuer, issue_date, expiration_date) FROM stdin;
\.


--
-- Data for Name: educational_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.educational_certificates (id, issuer, holder, issue_date, kind) FROM stdin;
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
1	Sandra	Frye	Sandra	Frye	519	2041-02-15	2061-08-21	F	1	Cambodia	f	f	DO
2	Tyler	Brandt	Tyler	Brandt	879	2017-11-11	2037-04-06	M	2	Pitcairn	f	f	KX
3	Amanda	Hayes	Amanda	Hayes	8	2013-11-01	2033-11-14	F	3	Montserrat	f	f	MQ
4	Anthony	Knight	Anthony	Knight	459	1989-09-13	2009-04-13	M	4	Aruba	f	f	BK
5	Lawrence	Suarez	Lawrence	Suarez	980	1987-05-07	2007-01-12	F	5	Benin	f	f	UF
6	Tamara	Snyder	Tamara	Snyder	892	1990-07-20	2010-10-20	M	6	Yemen	f	f	EK
7	Timothy	Elliott	Timothy	Elliott	1043	1991-01-05	2011-10-20	F	7	Nauru	f	f	MR
8	Jamie	Smith	Jamie	Smith	844	1965-02-19	1985-07-18	M	8	Brazil	f	f	ZY
9	Nicole	Martinez	Nicole	Martinez	572	1961-05-02	1981-04-24	F	9	Montenegro	f	f	FE
10	Kyle	Foster	Kyle	Foster	862	1961-07-07	1981-03-20	M	10	Denmark	f	f	NW
11	Logan	Adams	Logan	Adams	838	1966-11-04	1986-06-28	F	11	Belarus	f	f	YN
12	Paul	Hanson	Paul	Hanson	803	1965-09-21	1985-11-08	M	12	Kyrgyzstan	f	f	SY
13	Michael	Cole	Michael	Cole	991	1962-05-01	1982-03-01	F	13	Israel	f	f	NY
14	Robert	Foster	Robert	Foster	734	1964-03-05	1984-07-01	M	14	Cyprus	f	f	FZ
15	Brandon	Rodriguez	Brandon	Rodriguez	1196	1962-08-28	1982-06-06	F	15	Yemen	f	f	GY
16	Melinda	Evans	Melinda	Evans	1238	1941-03-20	1961-09-23	M	16	Mauritius	f	f	YV
17	Emily	George	Emily	George	1039	1938-10-21	1958-06-14	F	17	Bermuda	f	f	DX
18	John	Nelson	John	Nelson	299	1938-02-01	1958-05-19	M	18	Belarus	f	f	SH
19	Julie	Crane	Julie	Crane	592	1939-05-07	1959-08-06	F	19	Gabon	f	f	KV
20	Sandra	Smith	Sandra	Smith	410	1942-09-11	1962-05-19	M	20	Georgia	f	f	UR
21	Tony	Harris	Tony	Harris	443	1939-03-21	1959-09-07	F	21	Madagascar	f	f	ZB
22	Calvin	Garza	Calvin	Garza	253	1939-04-02	1959-11-21	M	22	Togo	f	f	CA
23	Aaron	Calhoun	Aaron	Calhoun	559	1941-01-22	1961-04-25	F	23	Yemen	f	f	CU
24	Crystal	Scott	Crystal	Scott	1148	1938-09-11	1958-07-10	M	24	Benin	f	f	KP
25	Walter	Bowen	Walter	Bowen	1071	1938-05-02	1958-04-03	F	25	Nauru	f	f	DH
26	Lucas	Austin	Lucas	Austin	379	1936-11-20	1956-11-24	M	26	Georgia	f	f	MF
27	Kristen	Long	Kristen	Long	170	1936-08-25	1956-04-11	F	27	Ireland	f	f	YU
28	Christina	Taylor	Christina	Taylor	898	1936-05-19	1956-08-02	M	28	Tajikistan	f	f	WU
29	Melissa	Thomas	Melissa	Thomas	686	1941-01-06	1961-12-21	F	29	Taiwan	f	f	YQ
30	Robert	Fuller	Robert	Fuller	1096	1936-12-18	1956-12-03	M	30	Guatemala	f	f	OT
31	Whitney	Harris	Whitney	Harris	271	1938-09-16	1958-07-01	F	31	Ethiopia	f	f	AU
32	Andrea	Shepard	Andrea	Shepard	980	1917-06-13	1937-01-03	M	32	Poland	f	f	MY
33	Luis	Barron	Luis	Barron	1093	1914-11-10	1934-11-21	F	33	Laos	f	f	ES
34	David	Weaver	David	Weaver	1193	1911-07-09	1931-12-09	M	34	Tuvalu	f	f	MZ
35	Emma	Matthews	Emma	Matthews	1225	1914-08-24	1934-07-17	F	35	Sudan	f	f	HY
36	Allen	Gallagher	Allen	Gallagher	712	1914-01-20	1934-07-02	M	36	Algeria	f	f	UR
37	Ryan	Luna	Ryan	Luna	1057	1911-10-16	1931-07-07	F	37	Belize	f	f	EN
38	Alejandro	Brown	Alejandro	Brown	562	1915-04-06	1935-09-04	M	38	Denmark	f	f	MK
39	Emily	Ayers	Emily	Ayers	849	1913-09-23	1933-10-26	F	39	Bolivia	f	f	KK
40	Gina	Clay	Gina	Clay	227	1915-02-06	1935-02-17	M	40	Turkmenistan	f	f	BX
41	Amanda	Davenport	Amanda	Davenport	866	1914-08-06	1934-03-20	F	41	Gabon	f	f	WY
42	Toni	Miller	Toni	Miller	293	1916-03-18	1936-02-14	M	42	Spain	f	f	DM
43	Jeffrey	Ryan	Jeffrey	Ryan	106	1915-05-09	1935-12-15	F	43	Colombia	f	f	SP
44	John	Smith	John	Smith	378	1916-11-11	1936-08-11	M	44	Switzerland	f	f	ZQ
45	Kristin	Williams	Kristin	Williams	850	1917-12-15	1937-05-01	F	45	Kenya	f	f	JL
46	Tracy	Caldwell	Tracy	Caldwell	313	1917-06-24	1937-08-19	M	46	Mauritania	f	f	JD
47	Alan	Nunez	Alan	Nunez	318	1912-09-16	1932-01-24	F	47	Iran	f	f	WU
48	Amber	Green	Amber	Green	280	1916-06-25	1936-03-17	M	48	Nepal	f	f	JL
49	Darryl	Olson	Darryl	Olson	56	1913-06-26	1933-03-06	F	49	Liberia	f	f	SD
50	Brenda	Rollins	Brenda	Rollins	291	1911-01-09	1931-03-12	M	50	Argentina	f	f	UV
51	Grant	Roberson	Grant	Roberson	135	1915-03-24	1935-05-01	F	51	Brunei	f	f	HR
52	Lauren	Wood	Lauren	Wood	479	1917-04-26	1937-06-18	M	52	Mauritius	f	f	LS
53	Jon	Dickson	Jon	Dickson	266	1917-02-17	1937-03-13	F	53	Indonesia	f	f	IH
54	Kyle	Gonzales	Kyle	Gonzales	471	1912-02-16	1932-09-19	M	54	Cuba	f	f	RT
55	Jessica	White	Jessica	White	26	1916-12-28	1936-02-05	F	55	Tanzania	f	f	QT
56	Tyler	Salazar	Tyler	Salazar	475	1911-07-07	1931-05-09	M	56	Ukraine	f	f	WM
57	Paul	Wheeler	Paul	Wheeler	700	1913-05-11	1933-06-09	F	57	France	f	f	LF
58	Kyle	Blake	Kyle	Blake	415	1914-03-08	1934-09-14	M	58	Serbia	f	f	XU
59	Nicholas	Bowen	Nicholas	Bowen	1056	1917-03-08	1937-02-16	F	59	China	f	f	AI
60	Kristopher	Hancock	Kristopher	Hancock	227	1914-11-16	1934-10-22	M	60	Aruba	f	f	OF
61	Hector	Edwards	Hector	Edwards	323	1917-09-27	1937-12-06	F	61	Lesotho	f	f	DV
62	Cindy	Marquez	Cindy	Marquez	13	1917-06-28	1937-03-09	M	62	Somalia	f	f	HK
63	John	Simmons	John	Simmons	660	1912-11-05	1932-12-14	F	63	Guyana	f	f	NL
64	Edward	Grant	Edward	Grant	1081	1888-05-07	1908-03-26	M	64	Armenia	f	f	CC
65	Samuel	Nielsen	Samuel	Nielsen	588	1886-07-09	1906-05-15	F	65	Thailand	f	f	HC
66	Scott	Guerrero	Scott	Guerrero	908	1888-05-04	1908-12-09	M	66	Guinea	f	f	CL
67	Jennifer	Jones	Jennifer	Jones	190	1889-01-05	1909-07-08	F	67	Bulgaria	f	f	CR
68	Thomas	Neal	Thomas	Neal	227	1886-01-12	1906-11-18	M	68	Israel	f	f	WO
69	Steven	Morgan	Steven	Morgan	902	1892-02-26	1912-03-25	F	69	Singapore	f	f	JE
70	Stephen	Bender	Stephen	Bender	573	1889-08-10	1909-07-11	M	70	Maldives	f	f	XI
71	Rebecca	Haynes	Rebecca	Haynes	982	1888-12-01	1908-01-01	F	71	Germany	f	f	RW
72	Corey	Daniels	Corey	Daniels	99	1886-11-08	1906-01-18	M	72	Hungary	f	f	IC
73	Julie	Martinez	Julie	Martinez	1063	1892-06-10	1912-07-24	F	73	Zimbabwe	f	f	DW
74	Kyle	Tucker	Kyle	Tucker	231	1891-08-02	1911-01-23	M	74	Uganda	f	f	DJ
75	Nathan	Martin	Nathan	Martin	820	1886-02-16	1906-02-23	F	75	Palau	f	f	CP
76	Levi	Long	Levi	Long	771	1886-01-22	1906-08-28	M	76	Argentina	f	f	MN
77	Zachary	Jackson	Zachary	Jackson	1134	1887-05-07	1907-08-05	F	77	Curacao	f	f	RD
78	Juan	Smith	Juan	Smith	988	1888-12-21	1908-02-08	M	78	Cyprus	f	f	JV
79	Michael	Young	Michael	Young	404	1892-10-05	1912-03-10	F	79	Armenia	f	f	ZE
80	Carolyn	Rivera	Carolyn	Rivera	606	1892-04-09	1912-04-10	M	80	Iceland	f	f	OH
81	John	Robinson	John	Robinson	434	1887-04-17	1907-05-05	F	81	Norway	f	f	VR
82	Justin	Hughes	Justin	Hughes	42	1889-01-28	1909-04-12	M	82	Zimbabwe	f	f	RU
83	Michael	Murillo	Michael	Murillo	905	1886-08-10	1906-11-12	F	83	Finland	f	f	WT
84	Wyatt	Brennan	Wyatt	Brennan	722	1892-04-15	1912-08-22	M	84	China	f	f	PA
85	Christy	Obrien	Christy	Obrien	281	1888-05-06	1908-09-19	F	85	France	f	f	EV
86	Martin	Greer	Martin	Greer	692	1890-06-15	1910-08-03	M	86	Qatar	f	f	PH
87	Cynthia	Walker	Cynthia	Walker	974	1890-10-28	1910-06-02	F	87	Barbados	f	f	LS
88	Adam	Hunt	Adam	Hunt	143	1888-08-22	1908-05-22	M	88	Uganda	f	f	MP
89	Joseph	Nelson	Joseph	Nelson	854	1889-04-28	1909-05-28	F	89	Iceland	f	f	DT
90	Damon	Valenzuela	Damon	Valenzuela	903	1889-06-17	1909-04-27	M	90	Austria	f	f	NC
91	Linda	Golden	Linda	Golden	481	1889-09-05	1909-10-12	F	91	Zimbabwe	f	f	BP
92	Richard	Flores	Richard	Flores	556	1889-07-19	1909-05-13	M	92	Israel	f	f	TF
93	Matthew	Tucker	Matthew	Tucker	560	1888-09-15	1908-05-17	F	93	Niue	f	f	PI
94	Rebecca	Hughes	Rebecca	Hughes	397	1891-09-20	1911-05-24	M	94	Iceland	f	f	NX
95	Jennifer	Nelson	Jennifer	Nelson	1206	1892-09-08	1912-03-17	F	95	Aruba	f	f	EC
96	Megan	Davis	Megan	Davis	1142	1889-01-06	1909-01-09	M	96	Indonesia	f	f	SZ
97	Daniel	Wilson	Daniel	Wilson	979	1886-05-13	1906-01-10	F	97	Paraguay	f	f	HN
98	Henry	Carrillo	Henry	Carrillo	438	1889-06-23	1909-11-15	M	98	Paraguay	f	f	QG
99	Dalton	Henderson	Dalton	Henderson	424	1892-10-04	1912-02-20	F	99	Denmark	f	f	PE
100	James	Hill	James	Hill	455	1886-01-13	1906-10-09	M	100	Honduras	f	f	KN
101	Patricia	Garcia	Patricia	Garcia	185	1891-07-01	1911-02-11	F	101	Suriname	f	f	AA
102	John	Hawkins	John	Hawkins	94	1888-06-21	1908-05-14	M	102	Uzbekistan	f	f	JS
103	Danielle	Phillips	Danielle	Phillips	1111	1892-04-22	1912-01-11	F	103	Pakistan	f	f	HW
104	Michael	Davis	Michael	Davis	650	1886-05-26	1906-02-08	M	104	Botswana	f	f	PN
105	Danielle	Anderson	Danielle	Anderson	781	1888-06-20	1908-03-18	F	105	Syria	f	f	PO
106	Lisa	Rodriguez	Lisa	Rodriguez	183	1891-12-12	1911-07-10	M	106	Uganda	f	f	LK
107	Ryan	Jenkins	Ryan	Jenkins	609	1888-03-11	1908-08-10	F	107	Latvia	f	f	BQ
108	Scott	Patterson	Scott	Patterson	438	1892-06-11	1912-04-17	M	108	Rwanda	f	f	GR
109	John	Gonzalez	John	Gonzalez	422	1886-02-16	1906-04-15	F	109	Montserrat	f	f	LC
110	Kathy	Fry	Kathy	Fry	192	1890-07-13	1910-05-28	M	110	Chile	f	f	YT
111	Kelly	Mejia	Kelly	Mejia	523	1891-08-20	1911-01-18	F	111	Comoros	f	f	BB
112	Lisa	Le	Lisa	Le	588	1887-06-03	1907-10-06	M	112	Ecuador	f	f	RZ
113	John	Nelson	John	Nelson	777	1887-09-12	1907-10-10	F	113	Spain	f	f	FY
114	Angela	Marsh	Angela	Marsh	1030	1892-05-12	1912-02-13	M	114	Portugal	f	f	IS
115	Jonathan	Edwards	Jonathan	Edwards	493	1887-05-08	1907-10-22	F	115	Iran	f	f	OC
116	David	Williams	David	Williams	1090	1891-11-04	1911-08-21	M	116	Bangladesh	f	f	WM
117	Kristin	Gonzalez	Kristin	Gonzalez	835	1890-12-10	1910-11-07	F	117	Seychelles	f	f	SR
118	Susan	Neal	Susan	Neal	26	1889-08-16	1909-07-09	M	118	Sweden	f	f	NM
119	Lucas	Gilbert	Lucas	Gilbert	679	1892-11-04	1912-03-17	F	119	Chad	f	f	JK
120	Cody	Meyer	Cody	Meyer	296	1890-05-16	1910-11-06	M	120	Liberia	f	f	ZN
121	Michelle	Ross	Michelle	Ross	1058	1889-01-12	1909-11-19	F	121	Algeria	f	f	WY
122	Donna	Daniels	Donna	Daniels	1139	1890-07-18	1910-01-02	M	122	Martinique	f	f	FQ
123	Joel	Miller	Joel	Miller	631	1892-12-06	1912-11-17	F	123	Yemen	f	f	EC
124	Jennifer	Johnson	Jennifer	Johnson	1022	1887-02-08	1907-08-28	M	124	Ukraine	f	f	ZD
125	Maurice	Smith	Maurice	Smith	239	1888-02-27	1908-12-14	F	125	Estonia	f	f	ZA
126	Ryan	Matthews	Ryan	Matthews	871	1891-09-14	1911-12-19	M	126	Nauru	f	f	BX
127	Sharon	Perry	Sharon	Perry	1180	1886-12-14	1906-01-22	F	127	Germany	f	f	GL
128	Ashley	Reed	Ashley	Reed	162	1867-03-26	1887-10-02	M	128	Bhutan	f	f	SE
129	Teresa	Shaw	Teresa	Shaw	715	1861-03-01	1881-03-27	F	129	Kyrgyzstan	f	f	FB
130	Stacy	Jenkins	Stacy	Jenkins	713	1866-06-16	1886-07-09	M	130	Estonia	f	f	KR
131	David	Brooks	David	Brooks	161	1867-03-15	1887-07-15	F	131	Algeria	f	f	WP
132	Angelica	Reyes	Angelica	Reyes	199	1862-07-24	1882-02-02	M	132	Austria	f	f	CU
133	Natalie	Holmes	Natalie	Holmes	1185	1863-09-22	1883-05-21	F	133	Moldova	f	f	NC
134	Joshua	Flores	Joshua	Flores	627	1866-07-09	1886-03-01	M	134	Mauritius	f	f	UO
135	Melissa	Young	Melissa	Young	29	1861-10-27	1881-06-19	F	135	Greece	f	f	LS
136	Tracey	Williams	Tracey	Williams	281	1864-02-20	1884-09-19	M	136	Switzerland	f	f	ML
137	Jessica	Rubio	Jessica	Rubio	261	1867-08-24	1887-06-02	F	137	Greece	f	f	GY
138	Darlene	Kelley	Darlene	Kelley	692	1864-10-20	1884-02-13	M	138	Cuba	f	f	DX
139	Sherry	Melton	Sherry	Melton	982	1861-05-03	1881-10-25	F	139	Cambodia	f	f	LY
140	Emily	Garner	Emily	Garner	444	1867-12-01	1887-08-26	M	140	Tunisia	f	f	DP
141	Amber	Dickerson	Amber	Dickerson	183	1866-10-18	1886-03-21	F	141	Comoros	f	f	VQ
142	Kathryn	Leach	Kathryn	Leach	1121	1861-08-03	1881-03-23	M	142	Paraguay	f	f	ZY
143	Andrew	Scott	Andrew	Scott	673	1867-05-17	1887-02-22	F	143	Egypt	f	f	BV
144	Jerry	Grant	Jerry	Grant	1085	1863-01-16	1883-09-25	M	144	Belize	f	f	IB
145	Wesley	Cross	Wesley	Cross	170	1864-12-09	1884-05-12	F	145	Cuba	f	f	GS
146	Randy	Miller	Randy	Miller	778	1861-06-08	1881-04-07	M	146	Syria	f	f	WW
147	Jamie	Vaughn	Jamie	Vaughn	638	1862-03-28	1882-06-02	F	147	Cambodia	f	f	KW
148	Melissa	Callahan	Melissa	Callahan	343	1865-07-13	1885-12-21	M	148	Afghanistan	f	f	WI
149	Samantha	Williams	Samantha	Williams	1039	1866-08-22	1886-05-28	F	149	Kiribati	f	f	MM
150	Cathy	Michael	Cathy	Michael	132	1862-02-12	1882-03-08	M	150	Barbados	f	f	ND
151	Abigail	Patterson	Abigail	Patterson	102	1865-06-24	1885-03-10	F	151	Spain	f	f	OE
152	Allison	Dudley	Allison	Dudley	666	1864-07-02	1884-03-17	M	152	Bolivia	f	f	CO
153	Kaitlyn	Peters	Kaitlyn	Peters	565	1862-06-21	1882-07-13	F	153	Nauru	f	f	CD
154	Darlene	Byrd	Darlene	Byrd	12	1867-10-27	1887-10-15	M	154	Mauritius	f	f	JV
155	David	Huang	David	Huang	877	1866-07-15	1886-01-06	F	155	Myanmar	f	f	YT
156	Phillip	Sullivan	Phillip	Sullivan	895	1863-11-20	1883-06-08	M	156	Azerbaijan	f	f	HH
157	Morgan	Duncan	Morgan	Duncan	911	1862-12-19	1882-04-17	F	157	Mozambique	f	f	EM
158	Danielle	Martinez	Danielle	Martinez	478	1867-12-20	1887-08-10	M	158	Luxembourg	f	f	OP
159	Natasha	Grant	Natasha	Grant	1187	1862-09-07	1882-05-15	F	159	Morocco	f	f	QH
160	Stephanie	Wheeler	Stephanie	Wheeler	619	1865-12-28	1885-07-10	M	160	France	f	f	DZ
161	Raymond	Terrell	Raymond	Terrell	1187	1867-10-12	1887-07-13	F	161	Cuba	f	f	FL
162	Krista	Marquez	Krista	Marquez	1208	1861-01-15	1881-07-04	M	162	Mexico	f	f	DQ
163	Tamara	Tucker	Tamara	Tucker	311	1866-01-02	1886-11-01	F	163	Laos	f	f	TA
164	Connie	Garza	Connie	Garza	406	1861-06-28	1881-03-17	M	164	Kiribati	f	f	NO
165	David	King	David	King	435	1861-01-24	1881-09-06	F	165	Guinea	f	f	XS
166	Tracey	Ponce	Tracey	Ponce	466	1866-08-28	1886-03-01	M	166	Malawi	f	f	PO
167	Michael	Morrow	Michael	Morrow	985	1865-04-27	1885-02-02	F	167	Niger	f	f	DU
168	Laura	Richardson	Laura	Richardson	562	1862-12-19	1882-10-10	M	168	Germany	f	f	GE
169	Melinda	Atkins	Melinda	Atkins	879	1867-08-02	1887-01-18	F	169	Mali	f	f	RV
170	Pamela	Robinson	Pamela	Robinson	554	1864-10-19	1884-09-23	M	170	Macedonia	f	f	CH
171	Tara	Murray	Tara	Murray	487	1865-01-16	1885-12-01	F	171	Germany	f	f	MM
172	Elizabeth	Glover	Elizabeth	Glover	221	1867-04-11	1887-01-06	M	172	Morocco	f	f	QW
173	Dennis	Gomez	Dennis	Gomez	293	1861-04-10	1881-08-15	F	173	Curacao	f	f	AM
174	Jenna	Schroeder	Jenna	Schroeder	559	1864-05-27	1884-12-03	M	174	Philippines	f	f	ID
175	Amber	Hill	Amber	Hill	558	1861-08-25	1881-07-09	F	175	Aruba	f	f	DX
176	Brittany	Kim	Brittany	Kim	675	1861-02-17	1881-03-23	M	176	Azerbaijan	f	f	AI
177	Diana	Hall	Diana	Hall	547	1862-10-05	1882-11-02	F	177	Belgium	f	f	AB
178	Logan	Morris	Logan	Morris	459	1866-04-16	1886-03-15	M	178	Curacao	f	f	RX
179	Ashley	Delgado	Ashley	Delgado	838	1862-08-21	1882-09-17	F	179	Qatar	f	f	XE
180	Rachel	Frederick	Rachel	Frederick	1009	1861-09-07	1881-01-22	M	180	Dominica	f	f	PU
181	Rachel	Andrews	Rachel	Andrews	732	1866-07-28	1886-07-25	F	181	Uzbekistan	f	f	JO
182	Mario	Harris	Mario	Harris	502	1863-04-06	1883-11-09	M	182	Canada	f	f	AS
183	Scott	Martin	Scott	Martin	19	1864-05-01	1884-05-10	F	183	Australia	f	f	IU
184	Alyssa	Williams	Alyssa	Williams	216	1861-10-25	1881-10-08	M	184	Nauru	f	f	QS
185	Steven	Silva	Steven	Silva	648	1867-02-09	1887-06-21	F	185	Niger	f	f	QY
186	John	Knox	John	Knox	480	1864-06-23	1884-06-12	M	186	Croatia	f	f	FU
187	Donna	Green	Donna	Green	161	1867-08-16	1887-06-28	F	187	Estonia	f	f	VR
188	Natalie	Taylor	Natalie	Taylor	863	1863-03-03	1883-03-25	M	188	Slovenia	f	f	FT
189	Robert	Lam	Robert	Lam	1239	1862-01-12	1882-05-18	F	189	Nigeria	f	f	CI
190	Nathan	Campbell	Nathan	Campbell	1166	1862-06-24	1882-12-16	M	190	Aruba	f	f	KG
191	Crystal	Meza	Crystal	Meza	322	1866-12-01	1886-11-21	F	191	Spain	f	f	AB
192	Robert	Lane	Robert	Lane	782	1864-10-23	1884-10-15	M	192	Laos	f	f	DM
193	Valerie	Wade	Valerie	Wade	838	1867-09-21	1887-07-01	F	193	Martinique	f	f	BI
194	Tiffany	Patterson	Tiffany	Patterson	952	1865-01-04	1885-09-07	M	194	Uruguay	f	f	KX
195	Stephanie	Garza	Stephanie	Garza	1172	1867-01-05	1887-12-06	F	195	Guyana	f	f	HI
196	Kimberly	Shields	Kimberly	Shields	669	1867-08-13	1887-09-11	M	196	Cameroon	f	f	MH
197	Austin	Martinez	Austin	Martinez	868	1862-03-21	1882-08-19	F	197	Turkey	f	f	KP
198	Timothy	Carter	Timothy	Carter	377	1862-02-14	1882-08-16	M	198	Bermuda	f	f	IV
199	Timothy	Harris	Timothy	Harris	817	1861-03-09	1881-02-09	F	199	Malawi	f	f	ZO
200	Martin	Riley	Martin	Riley	190	1866-03-09	1886-01-01	M	200	Guyana	f	f	YY
201	Walter	Clarke	Walter	Clarke	797	1866-12-27	1886-12-21	F	201	Oman	f	f	HR
202	Kayla	Herrera	Kayla	Herrera	457	1864-09-05	1884-11-07	M	202	Angola	f	f	QS
203	William	Adams	William	Adams	889	1867-02-11	1887-01-24	F	203	Togo	f	f	DM
204	Bryan	Blackwell	Bryan	Blackwell	18	1862-06-19	1882-09-14	M	204	Georgia	f	f	FD
205	Donald	Anderson	Donald	Anderson	28	1864-02-13	1884-01-18	F	205	Suriname	f	f	VA
206	Jonathan	Gutierrez	Jonathan	Gutierrez	687	1864-02-17	1884-09-04	M	206	Croatia	f	f	FY
207	Jennifer	Marquez	Jennifer	Marquez	859	1864-07-04	1884-10-16	F	207	Nicaragua	f	f	RE
208	Kelsey	Smith	Kelsey	Smith	849	1864-10-28	1884-08-13	M	208	Seychelles	f	f	AN
209	Mark	Ware	Mark	Ware	989	1867-07-07	1887-01-19	F	209	Botswana	f	f	XV
210	Jonathan	Haynes	Jonathan	Haynes	600	1862-03-21	1882-08-18	M	210	Denmark	f	f	QL
211	Sandra	Kirk	Sandra	Kirk	889	1866-08-24	1886-02-23	F	211	Ghana	f	f	WI
212	Elizabeth	Pope	Elizabeth	Pope	61	1864-07-19	1884-04-13	M	212	Netherlands	f	f	OE
213	Misty	Hart	Misty	Hart	488	1866-07-08	1886-06-13	F	213	Uruguay	f	f	YT
214	Darrell	Moyer	Darrell	Moyer	840	1867-06-10	1887-03-12	M	214	Syria	f	f	XF
215	Bernard	Mann	Bernard	Mann	336	1867-08-07	1887-09-20	F	215	Angola	f	f	RC
216	Jerry	Huffman	Jerry	Huffman	200	1865-10-23	1885-03-19	M	216	Fiji	f	f	SE
217	Chad	Park	Chad	Park	644	1864-03-26	1884-10-04	F	217	Barbados	f	f	PF
218	Pamela	Wagner	Pamela	Wagner	426	1867-03-16	1887-04-10	M	218	Uganda	f	f	SB
219	Lauren	Lamb	Lauren	Lamb	64	1865-11-18	1885-06-24	F	219	Montenegro	f	f	UN
220	Sandra	Wright	Sandra	Wright	108	1861-08-16	1881-02-08	M	220	Kenya	f	f	UU
221	Kathryn	Cain	Kathryn	Cain	892	1865-11-14	1885-06-09	F	221	Iceland	f	f	XT
222	Molly	Newman	Molly	Newman	324	1866-09-23	1886-06-22	M	222	Bolivia	f	f	NK
223	Keith	Wallace	Keith	Wallace	1094	1866-01-16	1886-11-03	F	223	Tuvalu	f	f	FD
224	Rebecca	Hogan	Rebecca	Hogan	1168	1863-03-17	1883-09-09	M	224	Philippines	f	f	IG
225	Daniel	Chen	Daniel	Chen	985	1863-03-11	1883-06-24	F	225	Libya	f	f	SW
226	Jason	Stewart	Jason	Stewart	959	1861-12-27	1881-10-25	M	226	Kiribati	f	f	GZ
227	Christopher	Bailey	Christopher	Bailey	308	1864-12-21	1884-01-02	F	227	Bahrain	f	f	KO
228	Phillip	Martin	Phillip	Martin	601	1865-02-11	1885-05-07	M	228	Paraguay	f	f	UP
229	Kelsey	Mayo	Kelsey	Mayo	1023	1864-03-16	1884-02-26	F	229	Pitcairn	f	f	CI
230	Karen	Thompson	Karen	Thompson	590	1866-11-09	1886-06-15	M	230	Panama	f	f	CQ
231	Jamie	Atkins	Jamie	Atkins	265	1863-07-26	1883-01-18	F	231	Benin	f	f	VA
232	Edward	Strong	Edward	Strong	19	1864-05-24	1884-08-19	M	232	Fiji	f	f	IY
233	Stacy	Kim	Stacy	Kim	349	1865-01-05	1885-02-14	F	233	Iceland	f	f	WG
234	Bryan	Ross	Bryan	Ross	1080	1866-12-06	1886-08-27	M	234	Colombia	f	f	GM
235	David	Kirby	David	Kirby	15	1866-06-22	1886-10-21	F	235	Rwanda	f	f	UK
236	Andrew	Freeman	Andrew	Freeman	32	1862-12-13	1882-12-24	M	236	Albania	f	f	AF
237	Jennifer	Hudson	Jennifer	Hudson	1164	1861-12-27	1881-03-06	F	237	Iran	f	f	JT
238	Scott	Moreno	Scott	Moreno	1098	1863-02-13	1883-04-02	M	238	Hungary	f	f	ZQ
239	Shannon	King	Shannon	King	354	1863-08-13	1883-08-23	F	239	Australia	f	f	GP
240	Kristen	Thomas	Kristen	Thomas	526	1865-07-11	1885-08-18	M	240	Guinea	f	f	ES
241	Brittany	Dickerson	Brittany	Dickerson	1227	1863-10-25	1883-12-07	F	241	Hungary	f	f	OM
242	Laura	Robles	Laura	Robles	780	1863-08-26	1883-12-13	M	242	Nauru	f	f	BN
243	Rick	Murphy	Rick	Murphy	130	1862-02-12	1882-10-18	F	243	Tunisia	f	f	SZ
244	Jennifer	Black	Jennifer	Black	703	1864-04-20	1884-03-19	M	244	Brazil	f	f	CE
245	Janet	Nelson	Janet	Nelson	782	1863-04-21	1883-03-23	F	245	Rwanda	f	f	JY
246	Susan	Smith	Susan	Smith	248	1863-11-06	1883-01-15	M	246	Spain	f	f	BS
247	Chad	Nelson	Chad	Nelson	1212	1867-09-15	1887-05-19	F	247	Poland	f	f	JD
248	Cesar	Peterson	Cesar	Peterson	781	1861-04-25	1881-04-13	M	248	Israel	f	f	LD
249	Amanda	Green	Amanda	Green	450	1866-05-18	1886-08-02	F	249	Niger	f	f	EX
250	Jennifer	Brown	Jennifer	Brown	1010	1864-10-27	1884-07-20	M	250	Belgium	f	f	YE
251	Rebecca	Novak	Rebecca	Novak	406	1865-10-07	1885-04-19	F	251	Gabon	f	f	ZI
252	Michael	Smith	Michael	Smith	488	1861-11-10	1881-08-14	M	252	Guyana	f	f	CQ
253	Melissa	Barron	Melissa	Barron	783	1861-11-06	1881-10-05	F	253	Canada	f	f	CN
254	Aaron	Richardson	Aaron	Richardson	955	1866-03-01	1886-09-26	M	254	Barbados	f	f	XL
255	Patrick	Jacobs	Patrick	Jacobs	94	1865-02-21	1885-08-11	F	255	Angola	f	f	UC
256	Crystal	Braun	Crystal	Braun	670	1839-02-28	1859-08-18	M	256	Finland	f	f	EL
257	John	Mullen	John	Mullen	1085	1842-11-09	1862-07-18	F	257	Pakistan	f	f	RN
258	Rachel	Martinez	Rachel	Martinez	148	1842-03-25	1862-09-18	M	258	Togo	f	f	JZ
259	Joseph	Lawson	Joseph	Lawson	1156	1836-12-07	1856-01-08	F	259	Panama	f	f	YO
260	Dana	Hicks	Dana	Hicks	1030	1837-12-16	1857-03-06	M	260	Austria	f	f	MO
261	Jillian	Russell	Jillian	Russell	1112	1837-07-03	1857-11-02	F	261	Mongolia	f	f	PJ
262	Scott	Williams	Scott	Williams	428	1836-04-23	1856-03-24	M	262	Morocco	f	f	IO
263	Ronald	Sharp	Ronald	Sharp	898	1836-02-15	1856-11-01	F	263	Azerbaijan	f	f	YH
264	Ronald	Rodriguez	Ronald	Rodriguez	345	1836-03-01	1856-03-21	M	264	Pakistan	f	f	XS
265	Christopher	Davis	Christopher	Davis	900	1839-07-28	1859-08-03	F	265	Portugal	f	f	BZ
266	Maria	Fletcher	Maria	Fletcher	470	1840-03-08	1860-01-17	M	266	Philippines	f	f	CS
267	James	Chambers	James	Chambers	1083	1840-02-11	1860-05-04	F	267	Moldova	f	f	EQ
268	Michael	Morris	Michael	Morris	22	1840-10-09	1860-03-09	M	268	Tunisia	f	f	DA
269	Deborah	Williams	Deborah	Williams	59	1837-09-17	1857-10-17	F	269	Barbados	f	f	RC
270	Patrick	Jimenez	Patrick	Jimenez	129	1839-06-25	1859-09-04	M	270	Armenia	f	f	GK
271	Debra	Rojas	Debra	Rojas	963	1840-06-21	1860-06-01	F	271	Ukraine	f	f	OR
272	Amy	Mitchell	Amy	Mitchell	453	1839-11-05	1859-07-03	M	272	Brazil	f	f	OV
273	Angela	Macias	Angela	Macias	713	1840-01-22	1860-03-19	F	273	Eritrea	f	f	PS
274	Jessica	Young	Jessica	Young	117	1842-10-18	1862-04-21	M	274	China	f	f	WK
275	Lance	Evans	Lance	Evans	112	1837-11-06	1857-12-11	F	275	Australia	f	f	SV
276	Nicholas	Phillips	Nicholas	Phillips	457	1837-09-26	1857-08-19	M	276	Afghanistan	f	f	WO
277	Robert	Smith	Robert	Smith	800	1837-05-27	1857-03-06	F	277	Bangladesh	f	f	KA
278	Lori	Kennedy	Lori	Kennedy	530	1841-01-15	1861-12-16	M	278	India	f	f	SE
279	Wesley	Williams	Wesley	Williams	1098	1836-09-06	1856-03-18	F	279	Swaziland	f	f	GF
280	Kevin	Bailey	Kevin	Bailey	910	1837-05-25	1857-05-19	M	280	Bolivia	f	f	OA
281	Kimberly	Finley	Kimberly	Finley	749	1837-06-12	1857-01-02	F	281	Peru	f	f	FF
282	Mitchell	Madden	Mitchell	Madden	1086	1839-10-04	1859-02-11	M	282	Syria	f	f	MW
283	Sophia	Williams	Sophia	Williams	855	1840-03-05	1860-06-02	F	283	Slovenia	f	f	HE
284	Craig	Luna	Craig	Luna	527	1837-11-22	1857-10-25	M	284	Malaysia	f	f	ZG
285	Jeff	Ramirez	Jeff	Ramirez	339	1836-11-03	1856-07-11	F	285	Tuvalu	f	f	BS
286	Angelica	Owens	Angelica	Owens	849	1837-08-13	1857-09-25	M	286	Malawi	f	f	WG
287	Crystal	Mitchell	Crystal	Mitchell	1178	1837-03-04	1857-12-07	F	287	Curacao	f	f	YN
288	Carrie	Holloway	Carrie	Holloway	465	1841-07-03	1861-11-13	M	288	Qatar	f	f	KL
289	Alicia	Clark	Alicia	Clark	655	1841-12-20	1861-10-18	F	289	Nigeria	f	f	WB
290	Michael	Gonzalez	Michael	Gonzalez	120	1839-01-04	1859-12-23	M	290	Slovakia	f	f	GU
291	Carlos	Griffith	Carlos	Griffith	903	1838-11-23	1858-06-14	F	291	Sudan	f	f	CH
292	Gary	Dean	Gary	Dean	1211	1839-04-06	1859-12-13	M	292	Tajikistan	f	f	XA
293	Kevin	Smith	Kevin	Smith	1003	1838-11-03	1858-06-05	F	293	Haiti	f	f	SQ
294	Travis	Jensen	Travis	Jensen	511	1838-04-17	1858-08-26	M	294	Estonia	f	f	UM
295	Elizabeth	Nichols	Elizabeth	Nichols	1203	1837-12-25	1857-03-23	F	295	France	f	f	LR
296	Sean	Castillo	Sean	Castillo	51	1837-06-28	1857-07-26	M	296	Syria	f	f	NL
297	David	Yu	David	Yu	199	1842-06-10	1862-02-13	F	297	Argentina	f	f	VF
298	Edward	Davis	Edward	Davis	411	1842-11-07	1862-10-22	M	298	Poland	f	f	BK
299	Donna	David	Donna	David	1000	1836-12-28	1856-09-06	F	299	Liechtenstein	f	f	VQ
300	Lisa	Moss	Lisa	Moss	700	1837-08-03	1857-03-10	M	300	Thailand	f	f	JN
301	Frank	Robinson	Frank	Robinson	1236	1842-04-05	1862-08-23	F	301	Greece	f	f	YV
302	Courtney	Moore	Courtney	Moore	599	1841-05-18	1861-02-26	M	302	Zimbabwe	f	f	JR
303	Samantha	Gill	Samantha	Gill	495	1841-09-23	1861-05-21	F	303	Malta	f	f	GT
304	Betty	Bauer	Betty	Bauer	319	1838-07-21	1858-10-27	M	304	Martinique	f	f	LC
305	Matthew	Vang	Matthew	Vang	1170	1838-10-03	1858-03-14	F	305	Belize	f	f	DH
306	Jessica	Mata	Jessica	Mata	267	1839-04-14	1859-06-14	M	306	Swaziland	f	f	OG
307	Karen	Jones	Karen	Jones	863	1842-04-26	1862-11-17	F	307	Mauritius	f	f	DN
308	Robert	Garza	Robert	Garza	799	1842-02-07	1862-08-16	M	308	Mauritania	f	f	VM
309	Charles	Norton	Charles	Norton	736	1840-10-12	1860-04-27	F	309	Seychelles	f	f	IP
310	Daniel	Garner	Daniel	Garner	820	1841-03-23	1861-10-04	M	310	Bangladesh	f	f	JR
311	David	Singleton	David	Singleton	877	1837-10-23	1857-02-15	F	311	Swaziland	f	f	GE
312	Justin	Baker	Justin	Baker	421	1837-10-13	1857-09-28	M	312	France	f	f	JV
313	Heather	Taylor	Heather	Taylor	559	1837-10-14	1857-06-08	F	313	Romania	f	f	JU
314	Brandon	Velasquez	Brandon	Velasquez	422	1839-08-22	1859-06-24	M	314	Nicaragua	f	f	LB
315	Adam	Black	Adam	Black	955	1842-05-16	1862-02-21	F	315	Turkey	f	f	IO
316	Albert	Smith	Albert	Smith	376	1841-10-12	1861-12-28	M	316	Ireland	f	f	YM
317	David	Barnes	David	Barnes	555	1836-03-11	1856-06-17	F	317	Bhutan	f	f	LD
318	Katherine	Benjamin	Katherine	Benjamin	800	1837-03-01	1857-06-16	M	318	Bolivia	f	f	MU
319	Amber	Lopez	Amber	Lopez	423	1840-02-28	1860-09-18	F	319	Sweden	f	f	EX
320	Cynthia	Phelps	Cynthia	Phelps	61	1839-02-16	1859-07-16	M	320	Estonia	f	f	SR
321	Jonathon	Hurley	Jonathon	Hurley	1059	1838-09-05	1858-10-14	F	321	Slovakia	f	f	GM
322	Evan	Bowers	Evan	Bowers	1162	1839-10-11	1859-11-04	M	322	Tanzania	f	f	RB
323	Kristen	Wolfe	Kristen	Wolfe	1138	1839-06-07	1859-10-10	F	323	Australia	f	f	CZ
324	Christopher	Lee	Christopher	Lee	882	1837-08-12	1857-09-09	M	324	Togo	f	f	IF
325	Kristin	Sawyer	Kristin	Sawyer	1009	1839-10-02	1859-08-12	F	325	Egypt	f	f	UH
326	Nicholas	Dickerson	Nicholas	Dickerson	711	1836-10-06	1856-06-20	M	326	Swaziland	f	f	ZQ
327	Katherine	Figueroa	Katherine	Figueroa	752	1839-03-13	1859-05-22	F	327	Russia	f	f	ON
328	Lisa	Le	Lisa	Le	238	1839-01-09	1859-07-19	M	328	Germany	f	f	NB
329	Jon	Thornton	Jon	Thornton	1005	1841-03-10	1861-08-17	F	329	Portugal	f	f	LO
330	David	Wilkins	David	Wilkins	1164	1838-04-09	1858-02-09	M	330	Turkey	f	f	CR
331	Michael	Nash	Michael	Nash	1140	1841-04-26	1861-05-07	F	331	Moldova	f	f	CW
332	Olivia	George	Olivia	George	1182	1840-07-13	1860-12-01	M	332	Canada	f	f	CV
333	Benjamin	Oneill	Benjamin	Oneill	1110	1841-01-26	1861-08-07	F	333	Aruba	f	f	ZR
334	Scott	Ashley	Scott	Ashley	748	1837-07-13	1857-08-17	M	334	Guinea	f	f	KU
335	Edward	Frank	Edward	Frank	343	1837-02-28	1857-07-26	F	335	Mayotte	f	f	AG
336	Tamara	Flores	Tamara	Flores	135	1837-04-11	1857-07-04	M	336	Australia	f	f	AH
337	Jerry	Ramsey	Jerry	Ramsey	1111	1841-03-22	1861-02-17	F	337	Georgia	f	f	GD
338	Anna	Merritt	Anna	Merritt	678	1841-02-02	1861-04-07	M	338	Cameroon	f	f	YO
339	Laurie	Benson	Laurie	Benson	420	1837-12-17	1857-10-26	F	339	Tunisia	f	f	JF
340	Matthew	Sandoval	Matthew	Sandoval	863	1839-03-06	1859-12-22	M	340	Switzerland	f	f	SA
341	Jerry	Taylor	Jerry	Taylor	873	1841-01-26	1861-04-10	F	341	Indonesia	f	f	NN
342	Robert	Garcia	Robert	Garcia	674	1839-08-01	1859-12-14	M	342	Malaysia	f	f	EC
343	Ashley	Keller	Ashley	Keller	922	1842-03-02	1862-10-17	F	343	Mongolia	f	f	IQ
344	Melissa	Thompson	Melissa	Thompson	840	1837-03-24	1857-04-10	M	344	Curacao	f	f	YN
345	Kathleen	Gray	Kathleen	Gray	932	1842-07-21	1862-05-25	F	345	Dominica	f	f	BC
346	Ryan	Cochran	Ryan	Cochran	384	1840-09-13	1860-06-07	M	346	Philippines	f	f	DY
347	Ashley	Wilkinson	Ashley	Wilkinson	12	1840-06-18	1860-09-03	F	347	Panama	f	f	LL
348	Jacqueline	Yates	Jacqueline	Yates	222	1838-10-13	1858-12-13	M	348	Nepal	f	f	ZT
349	Erin	Fisher	Erin	Fisher	568	1837-08-11	1857-12-04	F	349	Oman	f	f	GZ
350	Christine	Garcia	Christine	Garcia	635	1836-10-21	1856-11-08	M	350	Ghana	f	f	SY
351	David	Bowman	David	Bowman	644	1836-04-14	1856-12-10	F	351	Venezuela	f	f	YZ
352	Lance	Mosley	Lance	Mosley	54	1836-11-24	1856-10-10	M	352	Guyana	f	f	XV
353	Kim	Rodriguez	Kim	Rodriguez	1110	1842-01-28	1862-09-26	F	353	Nepal	f	f	GG
354	Erin	Erickson	Erin	Erickson	628	1842-04-15	1862-12-19	M	354	Comoros	f	f	IZ
355	Rachel	Robbins	Rachel	Robbins	882	1839-02-07	1859-07-21	F	355	Kosovo	f	f	CB
356	Jake	Reilly	Jake	Reilly	478	1842-09-15	1862-11-17	M	356	Nepal	f	f	LC
357	Christian	Thomas	Christian	Thomas	892	1838-06-01	1858-10-28	F	357	Croatia	f	f	PA
358	Leonard	Michael	Leonard	Michael	1200	1840-07-09	1860-01-08	M	358	Moldova	f	f	LJ
359	Alyssa	Ellison	Alyssa	Ellison	388	1842-08-28	1862-06-09	F	359	Iceland	f	f	FO
360	Amber	Lee	Amber	Lee	266	1840-01-28	1860-05-15	M	360	Burundi	f	f	KB
361	Barbara	Jones	Barbara	Jones	973	1840-02-20	1860-10-27	F	361	Senegal	f	f	ZI
362	Michael	Pierce	Michael	Pierce	37	1841-12-19	1861-04-07	M	362	Dominica	f	f	TZ
363	David	Dean	David	Dean	544	1839-05-11	1859-11-23	F	363	Greece	f	f	KF
364	Samantha	Evans	Samantha	Evans	1228	1837-05-14	1857-12-07	M	364	Paraguay	f	f	VL
365	Carla	Lyons	Carla	Lyons	705	1837-01-13	1857-10-22	F	365	Greenland	f	f	XY
366	Taylor	Williams	Taylor	Williams	610	1841-01-08	1861-01-03	M	366	Chile	f	f	ZD
367	Charles	Madden	Charles	Madden	76	1838-12-05	1858-10-12	F	367	Djibouti	f	f	TE
368	Michael	Davis	Michael	Davis	280	1837-08-08	1857-04-19	M	368	Mexico	f	f	GL
369	Donna	Nelson	Donna	Nelson	487	1838-12-04	1858-08-01	F	369	USA	f	f	MN
370	Shari	Jimenez	Shari	Jimenez	804	1837-06-12	1857-04-03	M	370	Nepal	f	f	CX
371	Raymond	Lopez	Raymond	Lopez	531	1840-07-24	1860-04-20	F	371	Malta	f	f	JH
372	Amanda	Levy	Amanda	Levy	377	1836-12-14	1856-04-17	M	372	Malawi	f	f	DN
373	Keith	Rowland	Keith	Rowland	438	1839-07-02	1859-03-09	F	373	Belize	f	f	BS
374	Robert	Shelton	Robert	Shelton	204	1841-03-05	1861-10-01	M	374	Fiji	f	f	IF
375	Robert	Hutchinson	Robert	Hutchinson	954	1842-03-19	1862-08-11	F	375	Netherlands	f	f	OT
376	Tammy	Gomez	Tammy	Gomez	415	1838-10-13	1858-05-03	M	376	Maldives	f	f	WJ
377	Randy	Herrera	Randy	Herrera	1079	1842-09-27	1862-03-25	F	377	Venezuela	f	f	GY
378	Wendy	Oneal	Wendy	Oneal	652	1842-10-05	1862-03-09	M	378	Niue	f	f	HX
379	Caitlin	Wright	Caitlin	Wright	307	1840-12-04	1860-08-28	F	379	Philippines	f	f	ZB
380	Joshua	Jones	Joshua	Jones	1164	1836-03-07	1856-04-10	M	380	Germany	f	f	BX
381	Chris	Moore	Chris	Moore	925	1837-07-07	1857-12-04	F	381	Tanzania	f	f	ZM
382	Daniel	Anderson	Daniel	Anderson	466	1840-01-01	1860-03-19	M	382	Curacao	f	f	AA
383	Erin	Johnson	Erin	Johnson	1198	1836-05-03	1856-10-01	F	383	Mayotte	f	f	ZD
384	Erika	Diaz	Erika	Diaz	1218	1837-06-25	1857-11-28	M	384	Ukraine	f	f	PB
385	Angela	Wood	Angela	Wood	607	1842-02-12	1862-04-02	F	385	Senegal	f	f	KD
386	Shaun	Gates	Shaun	Gates	273	1837-04-03	1857-01-03	M	386	Macedonia	f	f	CP
387	Jessica	Garza	Jessica	Garza	170	1837-07-13	1857-11-22	F	387	Togo	f	f	EP
388	Margaret	Henderson	Margaret	Henderson	1056	1840-04-21	1860-05-22	M	388	Austria	f	f	SV
389	Rebecca	Miller	Rebecca	Miller	1188	1842-03-13	1862-06-24	F	389	Montenegro	f	f	SY
390	Lori	Wright	Lori	Wright	139	1838-09-05	1858-07-02	M	390	Cameroon	f	f	GE
391	Mark	Jenkins	Mark	Jenkins	343	1836-09-27	1856-07-19	F	391	Venezuela	f	f	ET
392	Elizabeth	Pierce	Elizabeth	Pierce	535	1837-09-14	1857-12-28	M	392	Kazakhstan	f	f	MW
393	Thomas	Davis	Thomas	Davis	438	1837-03-22	1857-09-12	F	393	Madagascar	f	f	RN
394	Kenneth	Gaines	Kenneth	Gaines	660	1837-02-10	1857-12-15	M	394	Dominica	f	f	FU
395	Jennifer	Wall	Jennifer	Wall	91	1837-01-03	1857-02-28	F	395	Guinea	f	f	VA
396	Elizabeth	Robertson	Elizabeth	Robertson	520	1836-09-01	1856-11-18	M	396	Bhutan	f	f	IS
397	Kristin	Todd	Kristin	Todd	1089	1840-06-04	1860-08-17	F	397	Malta	f	f	QS
398	Sarah	Haynes	Sarah	Haynes	148	1836-10-15	1856-07-01	M	398	Nicaragua	f	f	WK
399	Margaret	Beard	Margaret	Beard	954	1840-03-11	1860-10-25	F	399	Liechtenstein	f	f	TK
400	Jonathan	Garza	Jonathan	Garza	54	1837-04-22	1857-04-23	M	400	Algeria	f	f	CJ
401	Kristi	Stewart	Kristi	Stewart	990	1837-04-14	1857-01-16	F	401	Mongolia	f	f	WO
402	Dwayne	Mcgee	Dwayne	Mcgee	361	1838-01-08	1858-06-12	M	402	Cameroon	f	f	LL
403	Richard	Jones	Richard	Jones	88	1841-06-04	1861-06-09	F	403	Australia	f	f	SU
404	Alexandria	Alvarado	Alexandria	Alvarado	279	1836-05-13	1856-10-19	M	404	Panama	f	f	OE
405	Christina	Smith	Christina	Smith	1152	1842-10-18	1862-11-16	F	405	Mongolia	f	f	TS
406	Michael	Trujillo	Michael	Trujillo	983	1842-01-01	1862-06-06	M	406	Azerbaijan	f	f	MG
407	Jennifer	Gutierrez	Jennifer	Gutierrez	860	1839-06-17	1859-06-19	F	407	Ghana	f	f	EG
408	Christian	Cooper	Christian	Cooper	291	1840-07-10	1860-11-19	M	408	Comoros	f	f	KV
409	Anthony	Jones	Anthony	Jones	243	1837-10-26	1857-11-13	F	409	Montserrat	f	f	AP
410	Pedro	Skinner	Pedro	Skinner	343	1840-10-08	1860-07-15	M	410	Russia	f	f	XE
411	Dean	Griffin	Dean	Griffin	1198	1842-10-14	1862-05-02	F	411	Malawi	f	f	BW
412	Sharon	Wells	Sharon	Wells	527	1838-06-03	1858-04-16	M	412	Ecuador	f	f	HK
413	Kristy	Blake	Kristy	Blake	296	1841-07-01	1861-07-13	F	413	Chad	f	f	ZL
414	Stephen	Morales	Stephen	Morales	1018	1836-08-14	1856-05-23	M	414	Maldives	f	f	DI
415	Meghan	Patton	Meghan	Patton	1058	1838-06-23	1858-10-04	F	415	Armenia	f	f	VX
416	Debra	Rivera	Debra	Rivera	563	1840-03-04	1860-11-08	M	416	Turkmenistan	f	f	ZU
417	Chad	White	Chad	White	498	1838-11-14	1858-07-23	F	417	Cambodia	f	f	BV
418	Darrell	Pace	Darrell	Pace	870	1838-12-21	1858-11-03	M	418	Kiribati	f	f	KO
419	Paul	Miller	Paul	Miller	112	1841-02-12	1861-09-09	F	419	Canada	f	f	FM
420	Martha	Ware	Martha	Ware	844	1837-09-04	1857-04-23	M	420	China	f	f	NY
421	Leslie	Roberts	Leslie	Roberts	885	1840-08-21	1860-07-10	F	421	Germany	f	f	XE
422	Phillip	Nelson	Phillip	Nelson	57	1842-07-06	1862-03-16	M	422	Jordan	f	f	SM
423	Jack	Miller	Jack	Miller	991	1842-12-05	1862-08-25	F	423	Djibouti	f	f	ZB
424	Justin	Williams	Justin	Williams	324	1841-02-23	1861-06-23	M	424	Egypt	f	f	KM
425	Marcia	Mcdonald	Marcia	Mcdonald	330	1839-01-28	1859-08-15	F	425	Oman	f	f	NT
426	Erin	Cox	Erin	Cox	931	1836-11-01	1856-02-23	M	426	Poland	f	f	PK
427	Richard	Barker	Richard	Barker	1026	1838-10-19	1858-08-26	F	427	Kiribati	f	f	UV
428	Meredith	Woodward	Meredith	Woodward	491	1836-12-18	1856-07-15	M	428	Macao	f	f	HC
429	Emma	Mendez	Emma	Mendez	1166	1838-01-08	1858-12-27	F	429	Finland	f	f	HI
430	John	Guzman	John	Guzman	619	1836-07-02	1856-10-06	M	430	Honduras	f	f	XU
431	Kelly	Medina	Kelly	Medina	552	1838-03-07	1858-02-10	F	431	Macao	f	f	RG
432	Erica	Middleton	Erica	Middleton	1174	1840-04-19	1860-04-13	M	432	Peru	f	f	RR
433	Natalie	Mata	Natalie	Mata	495	1836-04-04	1856-02-03	F	433	Cambodia	f	f	PV
434	Monique	Harris	Monique	Harris	55	1841-02-27	1861-12-08	M	434	Argentina	f	f	AU
435	Amber	Williams	Amber	Williams	821	1836-02-07	1856-07-01	F	435	Yemen	f	f	VC
436	Jessica	Gibson	Jessica	Gibson	350	1838-02-09	1858-08-10	M	436	Cuba	f	f	SK
437	Jennifer	Woods	Jennifer	Woods	520	1842-03-22	1862-12-05	F	437	Cameroon	f	f	SM
438	Stacie	Burns	Stacie	Burns	991	1836-12-28	1856-03-21	M	438	Singapore	f	f	RU
439	Tyler	Martinez	Tyler	Martinez	1233	1841-09-25	1861-05-21	F	439	Cambodia	f	f	JZ
440	Ana	Douglas	Ana	Douglas	1178	1837-07-14	1857-12-18	M	440	Yemen	f	f	OW
441	Alan	Frazier	Alan	Frazier	107	1838-04-20	1858-04-17	F	441	Gabon	f	f	PC
442	Stephen	Murphy	Stephen	Murphy	882	1841-03-28	1861-09-19	M	442	Afghanistan	f	f	GU
443	Jeffrey	Miller	Jeffrey	Miller	1000	1838-12-10	1858-09-02	F	443	Belarus	f	f	JH
444	Emily	Mooney	Emily	Mooney	592	1841-10-14	1861-10-12	M	444	Algeria	f	f	OP
445	Justin	Palmer	Justin	Palmer	178	1840-02-15	1860-01-22	F	445	Gabon	f	f	CI
446	Christy	Robbins	Christy	Robbins	248	1839-03-25	1859-09-24	M	446	Nauru	f	f	RI
447	Joseph	Kennedy	Joseph	Kennedy	677	1838-07-23	1858-08-23	F	447	Turkey	f	f	NA
448	Veronica	Waters	Veronica	Waters	675	1838-03-13	1858-11-09	M	448	Sweden	f	f	TT
449	Benjamin	Blair	Benjamin	Blair	850	1836-12-14	1856-01-15	F	449	Greenland	f	f	OK
450	Amanda	Morgan	Amanda	Morgan	247	1840-11-11	1860-08-24	M	450	Denmark	f	f	YF
451	Nathaniel	Jackson	Nathaniel	Jackson	471	1837-09-20	1857-07-28	F	451	Argentina	f	f	YY
452	John	Hensley	John	Hensley	675	1842-06-18	1862-02-26	M	452	Eritrea	f	f	GG
453	Veronica	Hart	Veronica	Hart	133	1841-07-16	1861-12-17	F	453	Somalia	f	f	VE
454	Jeremy	Snyder	Jeremy	Snyder	606	1840-07-19	1860-05-21	M	454	Dominica	f	f	SN
455	Amanda	Lambert	Amanda	Lambert	554	1840-06-22	1860-05-11	F	455	Mauritania	f	f	DM
456	Christopher	Stark	Christopher	Stark	451	1836-03-21	1856-10-22	M	456	Cyprus	f	f	UA
457	Daniel	Duran	Daniel	Duran	28	1836-07-28	1856-10-05	F	457	France	f	f	OU
458	Kevin	Mcconnell	Kevin	Mcconnell	537	1837-04-03	1857-01-23	M	458	Guyana	f	f	AU
459	Troy	Montes	Troy	Montes	686	1839-07-11	1859-01-25	F	459	Nepal	f	f	PV
460	Jose	Smith	Jose	Smith	61	1842-09-09	1862-08-24	M	460	Kenya	f	f	HX
461	Kevin	Kramer	Kevin	Kramer	1144	1838-08-16	1858-09-13	F	461	Seychelles	f	f	RK
462	Elizabeth	Carter	Elizabeth	Carter	60	1841-08-02	1861-05-11	M	462	Ethiopia	f	f	LX
463	Anthony	Woods	Anthony	Woods	933	1842-03-18	1862-06-21	F	463	Dominica	f	f	WS
464	Jennifer	Shaffer	Jennifer	Shaffer	351	1836-12-15	1856-07-22	M	464	Italy	f	f	VO
465	Erika	Tran	Erika	Tran	434	1841-01-15	1861-12-16	F	465	Bermuda	f	f	ZF
466	Colleen	Hampton	Colleen	Hampton	144	1836-08-18	1856-07-07	M	466	Mauritius	f	f	RD
467	Allison	Johnson	Allison	Johnson	781	1841-01-11	1861-06-21	F	467	Mexico	f	f	CK
468	Donald	Mcguire	Donald	Mcguire	789	1838-06-05	1858-01-16	M	468	USA	f	f	IH
469	Elizabeth	Snyder	Elizabeth	Snyder	160	1837-11-19	1857-06-16	F	469	Syria	f	f	ES
470	Nathan	Elliott	Nathan	Elliott	924	1836-11-05	1856-04-02	M	470	Cuba	f	f	KI
471	Ana	Ford	Ana	Ford	392	1839-09-06	1859-04-05	F	471	Kosovo	f	f	HY
472	Matthew	Juarez	Matthew	Juarez	443	1838-01-09	1858-04-19	M	472	Liechtenstein	f	f	VI
473	Monica	Stewart	Monica	Stewart	635	1837-09-15	1857-06-11	F	473	Spain	f	f	ST
474	Preston	Jensen	Preston	Jensen	451	1841-04-11	1861-08-17	M	474	Algeria	f	f	IZ
475	Valerie	Strickland	Valerie	Strickland	276	1836-03-20	1856-09-26	F	475	Denmark	f	f	EY
476	Amy	Murphy	Amy	Murphy	418	1841-10-01	1861-05-18	M	476	Fiji	f	f	EO
477	Krista	Morgan	Krista	Morgan	253	1839-02-01	1859-05-06	F	477	Mauritius	f	f	BB
478	Samuel	Le	Samuel	Le	1187	1841-11-21	1861-11-12	M	478	Gibraltar	f	f	QZ
479	Sierra	Bentley	Sierra	Bentley	889	1839-11-12	1859-08-27	F	479	Benin	f	f	QQ
480	Wyatt	Nelson	Wyatt	Nelson	1136	1836-05-24	1856-02-09	M	480	Ireland	f	f	EK
481	Steven	Ramos	Steven	Ramos	529	1839-05-18	1859-11-25	F	481	Afghanistan	f	f	BC
482	Jason	Peters	Jason	Peters	402	1839-06-12	1859-01-24	M	482	Moldova	f	f	SO
483	Frank	Sanchez	Frank	Sanchez	1206	1842-07-19	1862-01-01	F	483	Namibia	f	f	XF
484	James	Sloan	James	Sloan	915	1841-12-02	1861-09-05	M	484	Mauritania	f	f	DJ
485	Thomas	Anderson	Thomas	Anderson	76	1842-08-18	1862-09-28	F	485	Bangladesh	f	f	SE
486	Samuel	Cuevas	Samuel	Cuevas	452	1842-09-24	1862-07-27	M	486	Malaysia	f	f	WL
487	Ian	Hoffman	Ian	Hoffman	932	1842-03-11	1862-10-26	F	487	Mauritania	f	f	OH
488	Derek	Blair	Derek	Blair	776	1842-12-09	1862-04-22	M	488	Oman	f	f	FB
489	Alexandria	Richard	Alexandria	Richard	655	1836-09-01	1856-04-15	F	489	Belarus	f	f	PV
490	Craig	Blake	Craig	Blake	746	1840-02-01	1860-06-24	M	490	Lithuania	f	f	KZ
491	Jonathan	Alvarado	Jonathan	Alvarado	547	1842-11-03	1862-07-21	F	491	Switzerland	f	f	CR
492	Steven	Miranda	Steven	Miranda	850	1836-09-02	1856-06-28	M	492	Comoros	f	f	ZX
493	Dennis	Wiggins	Dennis	Wiggins	8	1840-10-02	1860-02-04	F	493	Netherlands	f	f	VP
494	Elizabeth	Bailey	Elizabeth	Bailey	760	1842-06-26	1862-09-11	M	494	Syria	f	f	FY
495	Cheryl	Henry	Cheryl	Henry	486	1842-02-10	1862-04-13	F	495	Nepal	f	f	JR
496	Jacqueline	Bailey	Jacqueline	Bailey	895	1840-04-03	1860-11-26	M	496	Qatar	f	f	XP
497	Ashley	Baker	Ashley	Baker	1234	1838-08-24	1858-10-21	F	497	Libya	f	f	DM
498	Kenneth	Williams	Kenneth	Williams	390	1842-08-25	1862-10-01	M	498	Mauritania	f	f	XQ
499	Donald	Mejia	Donald	Mejia	782	1840-11-23	1860-09-16	F	499	Yemen	f	f	WG
500					1157	1839-07-04	1859-11-11	M	500	Brunei	f	f	VM
\.


--
-- Data for Name: marriage_certificates; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriage_certificates (id, marriage_id, issuer, issue_date) FROM stdin;
1	1	244	2015-07-27
2	2	396	1992-01-23
3	3	760	1996-09-08
4	4	1031	1970-08-26
5	5	2	1967-12-15
6	6	446	1969-06-08
7	7	770	1970-11-17
8	8	903	1942-06-09
9	9	341	1944-07-06
10	10	411	1945-06-26
11	11	762	1943-06-27
12	12	682	1940-11-26
13	13	817	1947-07-18
14	14	415	1945-01-23
15	15	1122	1946-09-02
16	16	210	1921-07-13
17	17	944	1920-09-24
18	18	1020	1919-04-05
19	19	1171	1921-01-13
20	20	1057	1919-12-16
21	21	772	1920-09-04
22	22	1194	1919-04-28
23	23	973	1917-10-08
24	24	783	1917-12-04
25	25	414	1919-10-14
26	26	621	1917-02-05
27	27	1214	1918-04-13
28	28	234	1920-02-18
29	29	321	1922-06-25
30	30	1022	1921-12-03
31	31	442	1917-03-27
32	32	671	1897-09-14
33	33	1076	1897-11-12
34	34	745	1894-03-13
35	35	858	1895-11-22
36	36	523	1893-04-07
37	37	1138	1894-06-17
38	38	970	1891-10-04
39	39	1209	1895-12-02
40	40	1196	1894-06-02
41	41	904	1896-09-05
42	42	969	1893-04-19
43	43	724	1897-05-03
44	44	572	1892-03-20
45	45	322	1891-05-24
46	46	542	1896-12-26
47	47	602	1894-03-28
48	48	1012	1893-04-10
49	49	646	1895-12-21
50	50	809	1892-02-03
51	51	1200	1892-01-18
52	52	424	1895-04-26
53	53	321	1896-12-03
54	54	845	1896-11-15
55	55	714	1892-07-06
56	56	902	1893-11-15
57	57	71	1895-09-23
58	58	805	1893-12-20
59	59	601	1895-09-05
60	60	1047	1896-12-16
61	61	481	1892-10-13
62	62	850	1897-11-08
63	63	864	1896-05-11
64	64	455	1871-09-12
65	65	717	1865-03-12
66	66	762	1869-03-06
67	67	1043	1870-05-04
68	68	145	1869-06-02
69	69	1057	1870-10-28
70	70	363	1872-02-01
71	71	474	1872-07-16
72	72	1016	1865-10-28
73	73	751	1869-04-04
74	74	421	1870-12-09
75	75	396	1867-04-09
76	76	561	1870-06-03
77	77	780	1871-07-14
78	78	933	1871-07-02
79	79	194	1865-03-05
80	80	903	1870-03-24
81	81	794	1869-02-05
82	82	406	1867-01-25
83	83	910	1868-10-08
84	84	716	1865-03-25
85	85	1230	1867-07-14
86	86	1246	1865-07-06
87	87	235	1868-08-17
88	88	63	1870-12-09
89	89	1125	1865-09-11
90	90	1122	1869-11-03
91	91	140	1872-09-16
92	92	927	1865-03-28
93	93	504	1867-02-14
94	94	850	1871-05-23
95	95	790	1869-12-04
96	96	707	1869-05-20
97	97	346	1872-07-07
98	98	941	1867-10-20
99	99	439	1866-06-16
100	100	750	1868-09-06
101	101	394	1865-10-28
102	102	214	1872-12-13
103	103	657	1867-06-20
104	104	1222	1866-03-05
105	105	335	1866-10-04
106	106	1154	1871-06-09
107	107	720	1868-07-27
108	108	781	1867-03-28
109	109	1000	1867-08-10
110	110	115	1866-12-17
111	111	566	1867-03-18
112	112	977	1867-01-22
113	113	756	1872-05-01
114	114	234	1865-06-13
115	115	594	1867-12-12
116	116	33	1870-02-22
117	117	97	1869-10-10
118	118	906	1871-09-27
119	119	791	1869-10-09
120	120	548	1867-09-16
121	121	102	1866-12-06
122	122	606	1866-09-22
123	123	241	1871-07-08
124	124	1076	1868-08-21
125	125	716	1869-01-12
126	126	770	1870-05-23
127	127	790	1869-05-04
128	128	307	1844-07-04
129	129	1177	1843-11-02
130	130	435	1845-03-18
131	131	321	1846-02-03
132	132	220	1843-02-04
133	133	1114	1847-01-15
134	134	1151	1842-09-24
135	135	770	1845-10-09
136	136	726	1840-07-28
137	137	1178	1840-07-17
138	138	358	1843-01-27
139	139	949	1845-07-19
140	140	857	1844-12-20
141	141	1217	1847-07-28
142	142	821	1846-11-11
143	143	735	1844-12-13
144	144	382	1846-12-20
145	145	900	1840-10-05
146	146	499	1845-02-05
147	147	75	1842-09-07
148	148	310	1842-10-16
149	149	127	1847-01-12
150	150	1195	1845-03-05
151	151	304	1842-11-17
152	152	711	1843-10-03
153	153	229	1843-03-28
154	154	127	1840-08-08
155	155	363	1844-08-21
156	156	743	1840-04-25
157	157	980	1847-03-23
158	158	956	1843-06-24
159	159	146	1842-01-09
160	160	814	1845-10-17
161	161	676	1847-03-23
162	162	558	1847-03-28
163	163	1019	1845-06-17
164	164	627	1847-04-09
165	165	167	1843-02-12
166	166	569	1846-01-03
167	167	656	1841-01-02
168	168	291	1840-03-20
169	169	660	1844-10-06
170	170	47	1846-01-01
171	171	565	1841-05-04
172	172	699	1840-10-25
173	173	68	1841-03-03
174	174	75	1844-11-15
175	175	875	1840-05-20
176	176	932	1842-05-02
177	177	703	1846-12-05
178	178	559	1847-07-08
179	179	781	1843-12-01
180	180	1158	1840-07-27
181	181	667	1842-02-17
182	182	145	1845-11-13
183	183	1057	1847-11-17
184	184	1170	1840-07-09
185	185	31	1846-01-21
186	186	293	1846-01-23
187	187	146	1844-05-07
188	188	544	1844-08-28
189	189	326	1844-07-06
190	190	532	1845-07-11
191	191	574	1845-06-12
192	192	376	1845-01-17
193	193	750	1840-05-13
194	194	1160	1847-03-20
195	195	1	1847-05-17
196	196	393	1840-12-20
197	197	66	1843-07-15
198	198	382	1843-07-04
199	199	344	1842-03-03
200	200	781	1844-08-06
201	201	464	1842-05-06
202	202	1040	1847-03-20
203	203	568	1845-04-20
204	204	1125	1846-01-10
205	205	1007	1845-11-05
206	206	1156	1840-03-05
207	207	74	1845-11-10
208	208	1034	1846-03-01
209	209	632	1846-07-18
210	210	1109	1840-02-20
211	211	194	1842-12-09
212	212	980	1842-01-25
213	213	590	1843-08-09
214	214	1216	1847-08-12
215	215	790	1845-09-07
216	216	292	1841-09-12
217	217	256	1846-10-20
218	218	341	1844-12-27
219	219	605	1845-02-16
220	220	150	1841-07-14
221	221	608	1847-11-15
222	222	464	1846-05-04
223	223	669	1844-02-06
224	224	1103	1845-04-21
225	225	685	1846-01-14
226	226	113	1841-02-23
227	227	680	1846-12-03
228	228	117	1840-02-24
229	229	1008	1845-12-07
230	230	291	1840-10-22
231	231	361	1845-03-20
232	232	899	1843-08-06
233	233	770	1844-11-23
234	234	909	1841-10-11
235	235	32	1842-10-19
236	236	949	1841-11-22
237	237	996	1843-12-05
238	238	538	1840-12-16
239	239	1177	1841-10-02
240	240	181	1845-08-06
241	241	640	1843-09-18
242	242	933	1846-04-02
243	243	1124	1842-11-19
244	244	1015	1841-12-14
245	245	1194	1841-10-24
246	246	663	1847-03-17
247	247	191	1841-05-03
248	248	289	1842-10-08
249	249	869	1846-11-15
\.


--
-- Data for Name: marriages; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.marriages (id, person1, person2, marriage_date) FROM stdin;
1	2	3	2015-07-27
2	4	5	1992-01-23
3	6	7	1996-09-08
4	8	9	1970-08-26
5	10	11	1967-12-15
6	12	13	1969-06-08
7	14	15	1970-11-17
8	16	17	1942-06-09
9	18	19	1944-07-06
10	20	21	1945-06-26
11	22	23	1943-06-27
12	24	25	1940-11-26
13	26	27	1947-07-18
14	28	29	1945-01-23
15	30	31	1946-09-02
16	32	33	1921-07-13
17	34	35	1920-09-24
18	36	37	1919-04-05
19	38	39	1921-01-13
20	40	41	1919-12-16
21	42	43	1920-09-04
22	44	45	1919-04-28
23	46	47	1917-10-08
24	48	49	1917-12-04
25	50	51	1919-10-14
26	52	53	1917-02-05
27	54	55	1918-04-13
28	56	57	1920-02-18
29	58	59	1922-06-25
30	60	61	1921-12-03
31	62	63	1917-03-27
32	64	65	1897-09-14
33	66	67	1897-11-12
34	68	69	1894-03-13
35	70	71	1895-11-22
36	72	73	1893-04-07
37	74	75	1894-06-17
38	76	77	1891-10-04
39	78	79	1895-12-02
40	80	81	1894-06-02
41	82	83	1896-09-05
42	84	85	1893-04-19
43	86	87	1897-05-03
44	88	89	1892-03-20
45	90	91	1891-05-24
46	92	93	1896-12-26
47	94	95	1894-03-28
48	96	97	1893-04-10
49	98	99	1895-12-21
50	100	101	1892-02-03
51	102	103	1892-01-18
52	104	105	1895-04-26
53	106	107	1896-12-03
54	108	109	1896-11-15
55	110	111	1892-07-06
56	112	113	1893-11-15
57	114	115	1895-09-23
58	116	117	1893-12-20
59	118	119	1895-09-05
60	120	121	1896-12-16
61	122	123	1892-10-13
62	124	125	1897-11-08
63	126	127	1896-05-11
64	128	129	1871-09-12
65	130	131	1865-03-12
66	132	133	1869-03-06
67	134	135	1870-05-04
68	136	137	1869-06-02
69	138	139	1870-10-28
70	140	141	1872-02-01
71	142	143	1872-07-16
72	144	145	1865-10-28
73	146	147	1869-04-04
74	148	149	1870-12-09
75	150	151	1867-04-09
76	152	153	1870-06-03
77	154	155	1871-07-14
78	156	157	1871-07-02
79	158	159	1865-03-05
80	160	161	1870-03-24
81	162	163	1869-02-05
82	164	165	1867-01-25
83	166	167	1868-10-08
84	168	169	1865-03-25
85	170	171	1867-07-14
86	172	173	1865-07-06
87	174	175	1868-08-17
88	176	177	1870-12-09
89	178	179	1865-09-11
90	180	181	1869-11-03
91	182	183	1872-09-16
92	184	185	1865-03-28
93	186	187	1867-02-14
94	188	189	1871-05-23
95	190	191	1869-12-04
96	192	193	1869-05-20
97	194	195	1872-07-07
98	196	197	1867-10-20
99	198	199	1866-06-16
100	200	201	1868-09-06
101	202	203	1865-10-28
102	204	205	1872-12-13
103	206	207	1867-06-20
104	208	209	1866-03-05
105	210	211	1866-10-04
106	212	213	1871-06-09
107	214	215	1868-07-27
108	216	217	1867-03-28
109	218	219	1867-08-10
110	220	221	1866-12-17
111	222	223	1867-03-18
112	224	225	1867-01-22
113	226	227	1872-05-01
114	228	229	1865-06-13
115	230	231	1867-12-12
116	232	233	1870-02-22
117	234	235	1869-10-10
118	236	237	1871-09-27
119	238	239	1869-10-09
120	240	241	1867-09-16
121	242	243	1866-12-06
122	244	245	1866-09-22
123	246	247	1871-07-08
124	248	249	1868-08-21
125	250	251	1869-01-12
126	252	253	1870-05-23
127	254	255	1869-05-04
128	256	257	1844-07-04
129	258	259	1843-11-02
130	260	261	1845-03-18
131	262	263	1846-02-03
132	264	265	1843-02-04
133	266	267	1847-01-15
134	268	269	1842-09-24
135	270	271	1845-10-09
136	272	273	1840-07-28
137	274	275	1840-07-17
138	276	277	1843-01-27
139	278	279	1845-07-19
140	280	281	1844-12-20
141	282	283	1847-07-28
142	284	285	1846-11-11
143	286	287	1844-12-13
144	288	289	1846-12-20
145	290	291	1840-10-05
146	292	293	1845-02-05
147	294	295	1842-09-07
148	296	297	1842-10-16
149	298	299	1847-01-12
150	300	301	1845-03-05
151	302	303	1842-11-17
152	304	305	1843-10-03
153	306	307	1843-03-28
154	308	309	1840-08-08
155	310	311	1844-08-21
156	312	313	1840-04-25
157	314	315	1847-03-23
158	316	317	1843-06-24
159	318	319	1842-01-09
160	320	321	1845-10-17
161	322	323	1847-03-23
162	324	325	1847-03-28
163	326	327	1845-06-17
164	328	329	1847-04-09
165	330	331	1843-02-12
166	332	333	1846-01-03
167	334	335	1841-01-02
168	336	337	1840-03-20
169	338	339	1844-10-06
170	340	341	1846-01-01
171	342	343	1841-05-04
172	344	345	1840-10-25
173	346	347	1841-03-03
174	348	349	1844-11-15
175	350	351	1840-05-20
176	352	353	1842-05-02
177	354	355	1846-12-05
178	356	357	1847-07-08
179	358	359	1843-12-01
180	360	361	1840-07-27
181	362	363	1842-02-17
182	364	365	1845-11-13
183	366	367	1847-11-17
184	368	369	1840-07-09
185	370	371	1846-01-21
186	372	373	1846-01-23
187	374	375	1844-05-07
188	376	377	1844-08-28
189	378	379	1844-07-06
190	380	381	1845-07-11
191	382	383	1845-06-12
192	384	385	1845-01-17
193	386	387	1840-05-13
194	388	389	1847-03-20
195	390	391	1847-05-17
196	392	393	1840-12-20
197	394	395	1843-07-15
198	396	397	1843-07-04
199	398	399	1842-03-03
200	400	401	1844-08-06
201	402	403	1842-05-06
202	404	405	1847-03-20
203	406	407	1845-04-20
204	408	409	1846-01-10
205	410	411	1845-11-05
206	412	413	1840-03-05
207	414	415	1845-11-10
208	416	417	1846-03-01
209	418	419	1846-07-18
210	420	421	1840-02-20
211	422	423	1842-12-09
212	424	425	1842-01-25
213	426	427	1843-08-09
214	428	429	1847-08-12
215	430	431	1845-09-07
216	432	433	1841-09-12
217	434	435	1846-10-20
218	436	437	1844-12-27
219	438	439	1845-02-16
220	440	441	1841-07-14
221	442	443	1847-11-15
222	444	445	1846-05-04
223	446	447	1844-02-06
224	448	449	1845-04-21
225	450	451	1846-01-14
226	452	453	1841-02-23
227	454	455	1846-12-03
228	456	457	1840-02-24
229	458	459	1845-12-07
230	460	461	1840-10-22
231	462	463	1845-03-20
232	464	465	1843-08-06
233	466	467	1844-11-23
234	468	469	1841-10-11
235	470	471	1842-10-19
236	472	473	1841-11-22
237	474	475	1843-12-05
238	476	477	1840-12-16
239	478	479	1841-10-02
240	480	481	1845-08-06
241	482	483	1843-09-18
242	484	485	1846-04-02
243	486	487	1842-11-19
244	488	489	1841-12-14
245	490	491	1841-10-24
246	492	493	1847-03-17
247	494	495	1841-05-03
248	496	497	1842-10-08
249	498	499	1846-11-15
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
\.


--
-- Data for Name: offices_kinds_relations; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.offices_kinds_relations (office_id, kind_id) FROM stdin;
1	2
2	4
2	3
2	2
3	1
3	4
3	3
4	4
5	1
5	2
5	3
5	4
6	2
6	3
7	1
7	3
7	4
7	2
8	1
9	4
9	3
10	2
10	3
11	4
11	2
12	3
12	1
13	3
13	1
13	2
14	3
14	2
14	4
15	4
15	1
15	3
16	2
17	3
17	4
17	1
18	2
18	1
19	1
19	4
20	4
20	3
21	1
22	4
22	1
23	4
23	1
23	3
24	3
24	2
25	4
25	2
26	1
26	2
26	4
26	3
27	2
27	3
28	2
28	1
29	4
29	2
29	3
29	1
30	4
30	3
31	3
31	4
31	2
32	1
32	3
32	2
33	2
33	3
34	2
34	4
34	3
35	3
36	4
36	1
36	2
37	2
37	3
37	1
37	4
38	1
38	4
38	3
38	2
39	3
39	1
39	2
39	4
40	3
40	2
40	4
40	1
41	2
42	1
42	2
43	2
43	1
43	4
43	3
44	2
44	3
44	4
45	3
45	1
45	4
46	2
46	4
46	1
46	3
47	1
47	3
47	2
48	1
48	2
48	3
49	2
49	4
49	3
49	1
50	1
50	4
51	1
51	4
51	3
52	3
52	4
53	2
53	3
54	4
54	2
54	3
54	1
55	1
56	2
56	4
56	1
56	3
57	3
57	1
58	1
58	2
58	4
58	3
59	3
59	2
59	1
59	4
60	4
60	1
60	2
60	3
61	3
61	1
62	1
62	2
63	2
63	1
63	4
64	1
65	2
65	1
65	3
66	3
66	4
66	2
67	2
68	2
68	4
68	1
68	3
69	4
69	3
70	4
71	4
71	2
72	3
72	2
73	4
74	2
74	3
75	1
75	3
75	4
75	2
76	1
77	2
77	3
78	4
78	2
79	1
79	3
80	1
81	3
81	4
82	4
83	2
83	3
84	3
84	1
85	2
85	3
85	4
86	2
86	1
86	4
87	4
87	1
87	2
88	1
89	3
89	2
90	4
90	1
90	2
91	4
91	3
91	1
91	2
92	2
92	4
92	3
92	1
93	4
93	3
94	1
94	4
95	2
96	3
96	4
96	2
96	1
97	3
97	1
97	2
97	4
98	4
98	3
98	2
98	1
99	1
99	3
100	2
100	4
101	2
101	1
101	3
102	4
102	1
102	2
103	1
104	2
104	1
105	3
106	2
106	4
106	1
106	3
107	4
107	1
108	3
108	1
108	2
109	4
110	4
110	3
111	4
111	1
111	2
112	1
112	4
112	3
113	1
113	2
114	2
115	4
115	3
115	1
115	2
116	2
116	4
116	1
116	3
117	2
117	3
117	4
117	1
118	1
118	2
118	3
118	4
119	2
119	3
119	4
120	3
120	1
121	3
121	4
121	1
122	4
123	3
124	3
124	4
124	2
125	2
126	3
126	1
127	3
127	2
127	1
127	4
128	1
129	3
129	1
130	4
130	1
130	2
130	3
131	4
131	2
131	1
132	4
132	2
132	1
133	3
133	4
133	1
134	2
134	4
134	3
135	1
135	4
135	3
135	2
136	1
136	3
137	4
137	2
137	1
137	3
138	2
138	3
138	4
139	2
139	4
139	1
139	3
140	2
141	1
142	4
142	1
142	2
142	3
143	2
143	1
143	3
143	4
144	1
144	4
144	2
144	3
145	4
145	2
145	1
146	3
146	1
146	2
147	1
147	3
147	2
147	4
148	3
148	1
148	2
149	2
149	4
150	2
151	4
151	2
152	3
152	1
153	3
153	2
153	4
153	1
154	2
154	3
155	2
155	1
156	4
156	1
157	4
157	1
158	4
159	3
160	1
160	4
160	2
160	3
161	1
161	3
162	3
162	4
162	2
162	1
163	3
164	3
165	4
165	3
165	2
165	1
166	2
166	3
166	4
167	2
168	2
168	1
169	4
169	2
170	4
170	2
170	3
170	1
171	1
171	3
172	2
173	3
173	2
173	1
174	4
174	2
175	4
175	1
176	2
177	2
177	3
178	1
179	4
180	1
180	2
181	2
181	3
181	4
182	3
182	2
183	4
183	1
183	3
183	2
184	3
184	2
185	4
185	3
185	1
185	2
186	3
187	3
187	2
187	1
187	4
188	1
188	4
189	3
190	1
190	2
190	3
191	2
191	3
191	1
191	4
192	1
192	2
193	3
193	4
193	1
194	1
194	2
194	4
194	3
195	2
196	1
196	4
197	4
198	4
198	1
199	2
199	1
199	3
199	4
200	1
200	4
200	2
200	3
201	1
201	4
201	3
202	4
202	3
202	2
202	1
203	1
203	3
203	2
203	4
204	3
204	4
204	2
204	1
205	3
205	2
206	3
206	1
206	4
206	2
207	3
207	4
207	2
207	1
208	1
208	3
209	4
210	3
210	1
210	4
210	2
211	3
211	2
211	1
212	3
212	4
212	1
213	3
214	3
214	2
214	1
215	4
215	1
216	2
216	3
216	1
216	4
217	3
217	4
218	4
218	1
219	4
220	2
221	2
221	1
222	1
222	3
222	4
223	1
224	1
224	2
224	3
224	4
225	2
225	4
226	4
226	3
227	4
227	3
227	1
227	2
228	3
229	4
229	2
229	3
229	1
230	4
231	1
231	2
231	3
231	4
232	1
232	4
232	2
232	3
233	3
234	3
234	2
234	1
235	2
235	3
235	4
236	3
236	4
237	3
237	4
238	1
238	3
238	2
239	2
239	4
239	1
239	3
240	1
240	2
241	1
241	4
241	2
242	2
242	4
243	1
243	3
243	2
243	4
244	1
244	2
244	3
244	4
245	1
246	2
247	1
248	4
248	3
248	1
248	2
249	3
249	2
250	4
250	2
250	3
250	1
251	4
251	3
251	2
251	1
252	2
253	1
253	4
253	2
254	3
254	4
255	3
255	4
256	2
256	4
257	1
257	3
258	4
258	3
258	2
258	1
259	3
259	2
259	1
260	4
260	3
261	1
261	2
261	4
262	3
263	3
263	4
264	3
265	1
265	3
265	4
266	3
266	4
266	1
266	2
267	3
267	4
267	2
267	1
268	4
268	2
268	1
268	3
269	3
269	4
270	4
270	3
270	1
271	4
271	1
271	3
272	4
272	3
272	2
272	1
273	1
274	2
275	3
276	3
276	4
276	1
276	2
277	1
277	3
278	4
278	3
278	1
279	2
279	1
280	1
280	3
281	1
282	2
282	3
282	1
283	4
284	3
284	4
285	2
286	2
287	3
287	2
287	1
288	3
288	1
288	4
288	2
289	4
289	2
289	3
290	1
290	3
290	2
291	4
291	3
291	2
291	1
292	3
292	2
293	3
293	1
293	4
293	2
294	4
295	2
295	4
296	4
296	2
296	1
296	3
297	4
298	3
298	2
298	1
299	1
300	3
300	1
301	2
301	4
302	1
303	2
303	1
303	3
304	2
304	1
305	3
305	2
306	2
306	1
307	3
307	1
307	2
308	1
309	3
309	1
310	4
310	3
310	2
310	1
311	1
311	4
311	3
311	2
312	3
313	2
313	1
314	2
315	3
315	2
315	4
316	3
317	2
318	1
319	3
319	1
319	2
319	4
320	3
320	2
321	2
322	4
322	2
322	1
322	3
323	3
323	1
323	4
324	3
324	1
325	1
325	3
325	2
325	4
326	4
326	2
326	3
327	3
327	2
328	4
329	4
329	1
329	2
330	4
330	1
330	2
331	4
332	2
332	1
332	4
333	4
333	3
334	3
335	2
335	1
335	4
335	3
336	1
336	2
336	4
337	1
337	3
338	4
338	3
338	1
339	2
339	1
340	4
340	3
340	2
341	2
341	4
341	1
342	3
342	4
343	2
343	1
343	4
344	4
344	2
345	1
345	4
345	2
345	3
346	2
346	1
346	3
347	4
348	2
348	4
348	3
348	1
349	4
349	2
349	1
350	4
350	3
350	2
350	1
351	4
351	1
351	3
351	2
352	1
352	3
352	4
352	2
353	4
354	4
354	2
354	1
355	3
355	1
355	2
355	4
356	4
357	2
357	4
357	3
358	3
358	2
358	1
358	4
359	4
359	1
359	2
359	3
360	2
360	4
360	3
361	3
361	2
361	1
362	4
362	1
363	2
364	1
365	1
366	3
367	4
367	1
367	3
368	3
368	2
368	4
369	2
370	3
370	2
371	4
372	3
372	2
372	4
373	4
373	3
373	1
374	4
374	3
374	2
375	4
375	3
376	4
376	1
376	2
377	1
377	3
377	2
377	4
378	3
378	4
378	1
379	2
379	4
379	1
380	3
381	1
381	4
381	3
382	2
383	3
383	2
383	4
384	1
385	3
386	1
387	4
387	3
387	2
387	1
388	1
388	3
389	2
390	3
390	1
390	4
390	2
391	1
392	3
392	2
392	4
392	1
393	4
393	2
394	2
394	4
395	4
396	1
396	2
396	4
397	3
397	1
397	2
397	4
398	4
398	3
398	2
398	1
399	4
399	2
399	3
399	1
400	3
400	1
401	3
401	1
402	2
402	4
402	1
402	3
403	4
403	3
404	4
404	1
404	2
405	4
406	1
406	2
407	2
408	3
408	2
409	3
409	4
410	1
411	1
411	4
411	2
411	3
412	4
413	1
414	3
414	2
414	4
415	1
415	3
415	4
415	2
416	2
417	4
418	4
418	3
418	2
418	1
419	3
420	1
420	4
421	3
421	2
421	1
421	4
422	1
422	3
422	2
422	4
423	1
423	4
424	2
424	1
425	2
425	1
425	4
425	3
426	4
426	1
427	3
428	3
428	4
428	1
429	2
429	4
429	3
430	4
430	2
430	3
430	1
431	4
432	3
433	4
433	1
433	2
434	2
434	1
434	3
434	4
435	4
435	1
435	2
436	1
436	4
437	1
438	1
438	3
439	2
440	1
440	4
441	4
441	3
441	1
441	2
442	1
442	4
442	2
442	3
443	3
443	2
443	1
443	4
444	4
444	2
444	1
445	4
445	3
446	1
446	2
446	3
447	4
447	3
447	2
448	3
449	2
450	4
450	3
450	2
450	1
451	3
451	4
451	2
451	1
452	2
452	1
452	3
452	4
453	2
453	1
454	3
454	1
455	4
455	3
455	2
455	1
456	3
456	4
457	2
457	1
457	3
457	4
458	3
459	4
459	1
459	2
460	1
460	2
461	1
462	3
462	4
463	1
463	2
463	4
463	3
464	2
464	1
464	3
464	4
465	1
465	3
465	2
465	4
466	3
466	1
466	2
467	4
468	3
468	1
469	2
469	4
469	3
469	1
470	1
470	4
471	3
471	1
472	4
472	3
472	1
472	2
473	1
474	2
474	1
474	4
474	3
475	1
476	1
477	3
477	2
477	1
478	3
478	1
478	4
478	2
479	1
479	2
479	3
479	4
480	2
480	1
480	3
481	2
481	4
481	1
481	3
482	3
482	1
483	4
484	3
485	4
485	1
485	3
485	2
486	1
486	4
487	2
487	4
487	3
487	1
488	2
488	1
489	3
489	1
489	4
490	2
490	4
490	1
491	4
491	2
491	3
491	1
492	4
492	1
492	2
492	3
493	4
493	1
493	2
493	3
494	1
494	2
495	3
495	2
495	4
495	1
496	4
496	3
496	2
496	1
497	2
497	1
498	2
498	4
498	1
498	3
499	4
499	2
499	3
499	1
500	2
500	4
501	4
502	1
503	4
504	4
504	3
504	2
505	4
505	1
505	2
506	3
507	3
507	1
508	2
509	1
509	4
509	3
510	2
510	4
511	1
511	3
511	4
512	3
512	1
512	4
513	2
513	4
513	3
514	3
515	2
515	4
515	1
516	3
516	2
516	1
517	3
517	4
518	3
518	4
518	1
519	1
519	3
519	4
519	2
520	1
520	2
520	3
521	2
521	1
521	3
522	3
523	4
523	2
523	3
523	1
524	2
524	4
524	3
525	1
525	2
525	3
526	3
526	4
526	1
527	2
527	1
527	4
527	3
528	3
529	1
529	2
529	4
529	3
530	4
530	1
530	2
531	4
531	1
531	3
532	1
532	4
532	3
532	2
533	3
533	2
534	3
534	2
534	4
535	1
535	4
536	2
536	4
536	1
537	1
538	3
538	2
538	1
538	4
539	2
539	1
539	4
539	3
540	1
540	4
541	4
542	3
542	2
543	2
544	2
544	3
544	1
545	2
545	1
545	3
545	4
546	1
547	4
547	3
547	1
547	2
548	2
548	3
548	4
548	1
549	1
549	4
549	2
550	2
550	3
550	4
551	4
551	2
552	1
553	4
553	2
553	3
554	1
554	2
554	4
555	3
555	1
555	2
555	4
556	3
556	2
556	1
557	1
557	2
557	3
558	3
558	1
558	2
558	4
559	3
559	4
559	1
559	2
560	2
560	1
561	4
561	2
561	1
561	3
562	1
562	3
563	4
563	3
563	1
563	2
564	3
564	1
565	2
565	1
565	4
566	2
567	2
568	1
568	3
568	2
568	4
569	2
569	1
569	4
570	1
571	2
571	1
571	4
572	1
572	3
572	2
573	1
573	3
574	2
575	3
575	1
575	2
575	4
576	3
576	4
576	1
576	2
577	3
577	2
577	1
577	4
578	4
579	4
579	3
580	2
580	3
581	3
581	1
582	1
583	3
583	4
584	4
584	3
585	2
585	1
585	3
586	3
587	3
587	2
587	4
587	1
588	4
588	2
588	3
588	1
589	2
589	4
589	1
590	1
590	2
591	4
591	2
591	1
591	3
592	4
592	1
592	2
592	3
593	3
594	2
595	2
595	4
596	2
596	1
596	4
596	3
597	3
597	4
598	3
598	2
598	4
599	3
599	1
599	2
599	4
600	1
600	2
600	3
601	3
601	1
601	2
601	4
602	2
603	4
604	3
605	2
605	1
606	1
606	3
606	2
607	4
607	1
607	3
608	3
608	2
608	4
609	1
609	3
610	3
610	4
610	1
611	2
612	3
612	2
612	4
613	3
613	1
614	2
614	1
615	4
616	2
616	1
617	2
618	1
618	3
619	3
619	1
619	2
620	2
620	4
621	3
621	2
622	3
623	2
623	4
623	3
624	4
625	4
626	3
627	4
627	3
627	1
627	2
628	1
628	3
629	1
630	2
631	1
631	4
632	1
632	2
632	3
632	4
633	3
633	2
633	1
633	4
634	3
634	1
634	4
634	2
635	1
636	1
636	2
637	1
637	3
637	2
637	4
638	2
638	1
638	3
638	4
639	1
639	2
639	4
640	2
641	3
642	3
643	3
644	1
644	4
644	2
645	3
646	3
646	4
646	2
647	4
647	3
648	1
648	4
648	3
648	2
649	2
649	1
649	4
649	3
650	3
650	1
650	2
651	2
651	3
652	1
652	4
653	3
654	4
655	3
655	4
655	1
656	1
656	2
656	4
656	3
657	4
657	3
657	1
657	2
658	2
658	3
659	3
659	2
660	3
660	1
660	2
661	4
662	1
662	4
663	4
663	1
663	2
663	3
664	4
664	2
665	2
666	2
666	1
666	4
667	1
667	2
668	4
668	1
668	2
668	3
669	4
669	2
669	3
669	1
670	3
670	4
670	2
670	1
671	4
671	1
671	2
672	2
673	3
673	2
673	1
674	4
674	1
675	1
676	1
676	4
676	2
677	3
677	1
677	4
678	2
678	1
679	4
679	3
679	1
679	2
680	3
680	2
680	1
680	4
681	4
681	3
682	4
682	3
682	2
683	3
683	4
684	2
684	1
684	4
685	2
685	4
686	2
686	4
686	1
687	2
687	4
687	3
687	1
688	2
689	2
690	1
691	4
692	4
692	1
692	3
692	2
693	3
693	4
694	2
694	3
694	4
695	4
696	3
697	3
697	4
697	1
697	2
698	1
699	4
699	2
700	1
700	2
700	4
700	3
701	2
701	3
702	3
702	4
703	2
703	1
703	4
704	4
704	1
704	3
704	2
705	3
705	4
705	1
705	2
706	3
707	2
707	4
707	3
708	3
708	4
708	1
708	2
709	2
710	4
710	1
710	3
710	2
711	2
711	1
711	3
711	4
712	2
712	1
712	3
712	4
713	3
713	1
713	4
713	2
714	3
714	2
714	4
714	1
715	1
715	4
716	2
716	3
717	2
718	1
718	2
718	4
719	1
720	1
720	3
720	2
720	4
721	4
721	2
721	3
721	1
722	3
722	1
723	4
724	3
724	1
724	2
724	4
725	4
725	3
725	2
726	4
726	2
727	1
727	3
727	4
727	2
728	1
728	3
729	2
730	1
731	1
731	4
732	3
732	1
732	2
733	3
734	1
734	4
734	3
734	2
735	2
735	1
736	4
736	1
737	2
737	4
738	1
738	3
739	3
739	4
739	2
740	2
740	3
740	1
741	4
742	3
743	4
743	3
743	2
744	3
744	4
744	2
744	1
745	1
745	2
745	3
745	4
746	1
746	2
747	2
748	1
749	1
749	2
750	2
750	4
750	3
750	1
751	2
751	3
752	1
753	4
754	3
755	4
755	3
756	2
756	1
756	3
756	4
757	4
757	3
757	2
758	3
759	2
760	2
760	1
760	4
760	3
761	3
761	2
762	3
762	2
763	2
764	3
765	3
765	4
765	1
765	2
766	1
766	3
766	2
766	4
767	2
767	4
767	3
767	1
768	1
768	3
769	4
770	2
771	1
771	2
772	2
772	3
773	2
773	3
774	1
775	3
776	1
776	2
776	4
777	4
777	3
777	1
778	1
778	4
778	3
779	2
779	1
779	4
780	4
780	1
780	2
780	3
781	1
781	2
781	3
781	4
782	1
783	2
783	4
783	3
783	1
784	3
784	4
784	2
785	1
785	3
785	4
786	1
786	3
787	2
788	3
789	3
789	2
789	1
790	2
790	4
790	1
791	4
791	2
791	3
791	1
792	1
793	2
793	4
794	1
794	3
794	2
795	4
795	2
796	4
797	1
797	3
797	4
798	2
798	4
798	1
799	1
800	3
800	1
800	2
800	4
801	2
801	3
802	4
803	3
803	4
803	1
804	3
804	1
804	2
805	4
805	3
805	1
805	2
806	1
806	4
807	4
808	4
809	1
809	2
809	3
810	4
811	4
811	3
812	2
813	4
813	3
813	1
814	3
814	1
814	4
814	2
815	4
815	3
815	1
816	2
816	4
817	4
817	3
817	2
817	1
818	2
818	4
818	3
819	4
820	1
820	4
821	1
821	2
821	3
822	3
822	1
822	4
822	2
823	4
823	3
823	1
823	2
824	2
824	4
824	3
825	2
825	4
826	4
827	2
828	4
829	1
829	4
829	2
830	2
831	2
831	3
832	1
832	2
832	4
833	4
833	1
833	2
833	3
834	4
835	4
835	1
836	3
837	1
838	2
838	4
838	1
839	3
839	4
839	2
840	2
840	4
840	1
840	3
841	3
841	4
842	1
842	3
842	2
842	4
843	4
844	4
844	2
844	3
844	1
845	4
845	3
845	2
845	1
846	2
846	1
847	3
848	4
849	3
849	1
849	4
849	2
850	2
850	1
850	4
851	3
851	1
851	4
851	2
852	2
853	4
853	2
854	1
855	2
855	4
855	1
856	3
856	4
856	1
857	2
858	2
859	3
859	1
859	4
859	2
860	1
860	3
861	1
861	3
861	4
862	1
862	3
863	3
863	1
864	2
864	3
864	1
865	4
866	1
866	3
866	2
867	1
867	4
868	1
869	3
869	4
869	2
869	1
870	2
870	3
870	4
870	1
871	2
871	3
871	1
872	1
873	1
874	2
875	3
875	1
875	2
875	4
876	3
876	4
876	2
876	1
877	2
877	3
877	1
877	4
878	3
878	4
878	2
879	2
879	1
879	3
879	4
880	2
880	1
880	4
881	4
881	1
882	4
882	1
882	2
882	3
883	4
883	2
883	3
883	1
884	4
884	3
884	2
884	1
885	2
885	1
886	2
886	4
887	2
887	4
887	1
887	3
888	3
889	1
890	4
891	4
892	4
892	3
892	2
892	1
893	3
894	4
895	1
896	4
897	4
898	4
898	1
899	2
899	1
899	3
900	4
900	1
900	2
901	3
901	4
901	2
901	1
902	2
902	1
902	4
903	1
903	3
903	4
903	2
904	4
904	2
905	1
905	2
905	4
906	3
906	4
906	2
907	1
907	2
907	4
908	2
908	1
908	4
908	3
909	2
910	2
910	1
910	4
910	3
911	2
911	1
911	3
911	4
912	1
912	4
913	1
914	4
915	3
915	2
915	1
915	4
916	4
916	3
917	4
917	2
917	1
917	3
918	2
918	3
919	4
919	3
920	1
921	3
922	4
922	1
922	2
922	3
923	2
924	2
924	4
924	3
924	1
925	3
925	4
925	1
926	2
926	1
926	4
927	2
927	1
927	4
928	1
928	3
928	4
928	2
929	3
929	4
930	1
930	4
931	3
931	1
932	3
932	1
932	2
933	2
933	1
934	2
934	1
935	3
936	4
937	4
938	2
938	1
939	3
939	4
940	2
940	1
940	3
941	2
941	4
941	3
941	1
942	4
943	4
943	2
944	4
944	2
944	1
944	3
945	3
945	2
946	3
946	4
946	2
947	3
948	3
948	4
949	2
949	4
950	2
951	3
951	2
951	4
951	1
952	4
952	1
953	1
953	4
954	4
954	2
954	1
954	3
955	1
955	2
955	4
956	3
956	2
956	1
957	2
958	2
959	2
959	3
959	1
959	4
960	3
961	3
961	4
962	3
962	1
962	4
963	2
963	4
963	1
964	3
964	4
964	1
965	1
965	2
965	3
965	4
966	4
967	2
968	2
969	1
969	2
969	4
969	3
970	4
970	1
970	2
971	3
972	2
972	1
972	3
973	3
973	2
973	4
973	1
974	1
974	3
974	4
975	3
975	2
976	4
976	1
976	3
976	2
977	1
977	3
977	2
978	4
979	1
979	4
979	3
980	3
980	4
980	2
980	1
981	4
982	1
983	1
983	4
984	4
984	3
985	1
985	2
985	3
986	4
986	2
986	1
986	3
987	3
987	2
987	4
988	4
988	2
988	1
989	1
990	1
990	4
990	3
990	2
991	1
992	3
992	4
992	2
992	1
993	2
994	1
995	4
996	3
996	4
996	2
996	1
997	4
998	1
998	2
998	3
999	4
1000	2
1000	1
1000	4
1001	4
1001	1
1001	3
1002	4
1002	1
1002	2
1003	4
1003	3
1003	1
1003	2
1004	2
1005	1
1005	3
1006	3
1006	4
1006	1
1006	2
1007	2
1007	1
1007	3
1007	4
1008	2
1008	4
1008	1
1008	3
1009	2
1009	4
1009	1
1009	3
1010	3
1010	1
1010	4
1011	4
1012	4
1012	3
1012	2
1012	1
1013	3
1013	4
1013	2
1013	1
1014	2
1014	1
1014	4
1015	2
1015	4
1016	3
1016	1
1016	2
1016	4
1017	1
1017	3
1018	3
1018	1
1018	4
1018	2
1019	4
1019	2
1020	2
1020	4
1021	2
1021	4
1022	1
1022	2
1022	4
1023	1
1023	4
1024	2
1024	1
1024	4
1024	3
1025	2
1025	1
1025	3
1026	1
1026	2
1026	3
1026	4
1027	1
1027	4
1027	2
1027	3
1028	1
1028	2
1028	4
1028	3
1029	4
1030	4
1030	1
1030	2
1031	2
1031	4
1031	3
1032	4
1033	4
1034	2
1034	4
1035	2
1035	3
1035	1
1036	2
1037	3
1038	2
1038	3
1038	4
1039	1
1039	4
1040	4
1040	2
1041	4
1041	2
1041	1
1042	2
1042	3
1043	4
1043	2
1043	3
1043	1
1044	3
1044	2
1045	4
1046	3
1046	2
1047	2
1047	3
1048	4
1048	1
1048	3
1048	2
1049	3
1049	4
1049	2
1049	1
1050	3
1051	4
1051	1
1051	2
1052	2
1052	4
1053	3
1054	4
1055	3
1056	1
1056	3
1056	4
1056	2
1057	1
1057	3
1057	2
1058	1
1058	2
1059	3
1059	1
1060	3
1060	4
1060	1
1060	2
1061	1
1061	4
1061	2
1061	3
1062	3
1063	2
1063	3
1063	4
1063	1
1064	2
1064	4
1065	2
1066	2
1066	1
1066	3
1067	4
1067	2
1067	3
1068	4
1069	3
1069	1
1070	2
1071	1
1071	3
1072	2
1072	1
1073	1
1074	3
1074	2
1075	3
1075	2
1075	4
1076	4
1076	3
1076	2
1076	1
1077	4
1077	2
1078	4
1078	3
1079	1
1079	2
1080	1
1080	2
1081	3
1081	4
1081	1
1082	4
1082	1
1082	3
1083	3
1083	4
1083	1
1084	2
1085	1
1085	3
1086	1
1086	4
1086	2
1087	2
1088	2
1088	1
1088	4
1089	2
1089	1
1090	3
1090	1
1091	3
1091	1
1092	4
1093	1
1093	4
1094	3
1094	4
1094	2
1094	1
1095	2
1095	1
1095	3
1096	4
1096	2
1096	1
1097	2
1097	3
1097	1
1098	1
1099	4
1099	1
1099	2
1099	3
1100	3
1101	2
1101	4
1102	4
1103	2
1103	3
1103	1
1103	4
1104	3
1105	4
1105	3
1105	2
1106	1
1107	3
1107	2
1107	1
1107	4
1108	3
1108	4
1109	1
1109	2
1109	4
1109	3
1110	3
1110	1
1110	4
1111	2
1111	3
1111	4
1111	1
1112	3
1112	1
1112	4
1113	3
1114	1
1114	2
1114	3
1115	3
1115	2
1116	1
1117	3
1117	4
1117	1
1117	2
1118	4
1118	3
1119	4
1119	3
1119	2
1119	1
1120	2
1121	1
1121	3
1121	2
1121	4
1122	2
1122	1
1122	4
1122	3
1123	4
1124	2
1124	1
1124	4
1124	3
1125	3
1125	1
1125	2
1126	3
1127	2
1127	4
1128	1
1129	4
1129	1
1129	3
1129	2
1130	4
1130	2
1131	3
1132	1
1132	2
1132	3
1132	4
1133	4
1134	4
1134	3
1134	1
1135	2
1135	4
1135	3
1135	1
1136	2
1136	1
1137	3
1137	1
1137	2
1138	4
1138	2
1138	1
1138	3
1139	1
1140	2
1140	1
1140	3
1140	4
1141	1
1141	3
1142	3
1142	1
1142	2
1142	4
1143	1
1144	1
1144	2
1144	3
1144	4
1145	4
1146	1
1147	2
1147	4
1147	1
1148	1
1148	4
1149	2
1150	4
1150	3
1151	4
1151	2
1151	1
1152	1
1153	2
1153	3
1153	4
1154	1
1154	2
1154	4
1154	3
1155	4
1155	2
1155	1
1155	3
1156	3
1156	1
1156	4
1156	2
1157	1
1157	4
1157	2
1157	3
1158	2
1158	4
1158	3
1158	1
1159	1
1159	4
1160	4
1160	2
1160	3
1160	1
1161	1
1161	3
1162	1
1163	3
1164	2
1164	1
1164	4
1165	4
1165	1
1166	1
1166	3
1166	4
1167	4
1167	3
1168	2
1168	3
1168	1
1169	2
1170	2
1170	1
1170	3
1170	4
1171	1
1171	4
1171	3
1171	2
1172	1
1173	1
1174	1
1174	4
1174	3
1175	4
1176	2
1176	3
1176	1
1176	4
1177	1
1177	2
1177	4
1178	3
1178	2
1178	4
1178	1
1179	4
1179	3
1179	1
1179	2
1180	1
1180	2
1180	3
1181	3
1181	1
1181	2
1181	4
1182	1
1182	2
1182	3
1182	4
1183	2
1183	4
1184	2
1184	4
1185	3
1185	1
1185	4
1186	3
1186	1
1187	2
1187	3
1187	4
1187	1
1188	3
1188	4
1188	1
1189	2
1189	3
1189	1
1190	1
1191	1
1192	2
1193	3
1193	2
1193	1
1194	3
1194	1
1194	2
1194	4
1195	4
1195	2
1196	2
1196	1
1197	2
1198	1
1198	2
1199	4
1199	2
1199	1
1200	3
1200	1
1200	2
1201	2
1202	2
1202	3
1203	1
1203	4
1203	2
1203	3
1204	1
1204	4
1204	3
1205	2
1205	4
1206	1
1206	4
1206	2
1206	3
1207	4
1207	1
1207	2
1208	2
1208	3
1208	4
1208	1
1209	3
1209	4
1209	2
1210	1
1210	2
1210	4
1211	1
1211	4
1211	2
1211	3
1212	4
1212	2
1212	1
1213	1
1213	3
1213	4
1214	2
1214	1
1215	2
1215	3
1216	2
1217	3
1217	2
1218	4
1218	3
1218	2
1218	1
1219	2
1219	4
1219	3
1220	4
1221	2
1221	1
1221	4
1221	3
1222	4
1222	2
1223	4
1223	2
1224	4
1224	2
1225	2
1225	3
1225	1
1226	3
1226	1
1227	4
1227	3
1227	2
1227	1
1228	2
1228	4
1228	3
1228	1
1229	3
1229	1
1230	4
1230	2
1230	3
1230	1
1231	3
1231	4
1232	4
1232	3
1233	4
1233	2
1233	1
1234	4
1234	2
1234	3
1234	1
1235	4
1236	4
1236	3
1236	1
1237	2
1238	3
1238	1
1239	2
1239	4
1239	1
1240	2
1240	1
1240	4
1240	3
1241	3
1242	4
1242	2
1243	3
1243	2
1243	4
1244	2
1244	4
1245	4
1245	2
1246	4
1246	1
1246	2
1247	1
1247	3
1247	2
1247	4
1248	2
1248	1
1248	3
1249	4
1250	1
\.


--
-- Data for Name: passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.passports (id, original_surname, original_name, en_name, en_surname, issue_date, expiration_date, sex, issuer, passport_owner, lost, invalidated) FROM stdin;
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.people (id, date_of_birth, date_of_death) FROM stdin;
\.


--
-- Data for Name: pet_passports; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.pet_passports (id, name, pet_owner, issuer, date_of_birth, species) FROM stdin;
\.


--
-- Data for Name: visa_categories; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visa_categories (type, description, working_permit, residence_permit, duration, country) FROM stdin;
1	Tourist Visas	f	f	8 years	Afghanistan
2	Business Visas	t	f	5 years	Afghanistan
3	Work Visas	t	f	7 years	Afghanistan
4	Student Visas	t	f	5 years	Afghanistan
5	Transit Visas	f	f	10 years	Afghanistan
6	Family and Dependent Visas	t	f	10 years	Afghanistan
7	Immigrant Visas	t	t	5 years	Afghanistan
8	Refugee and Asylum Visas	t	f	10 years	Afghanistan
9	Special Purpose Visas	t	f	7 years	Afghanistan
1	Tourist Visas	f	f	10 years	Albania
2	Business Visas	t	f	6 years	Albania
3	Work Visas	t	f	9 years	Albania
4	Student Visas	t	f	10 years	Albania
5	Transit Visas	f	f	6 years	Albania
6	Family and Dependent Visas	t	f	9 years	Albania
7	Immigrant Visas	t	t	10 years	Albania
8	Refugee and Asylum Visas	t	f	9 years	Albania
9	Special Purpose Visas	t	f	10 years	Albania
1	Tourist Visas	f	f	7 years	Algeria
2	Business Visas	t	f	7 years	Algeria
3	Work Visas	t	f	9 years	Algeria
4	Student Visas	t	f	10 years	Algeria
5	Transit Visas	f	f	8 years	Algeria
6	Family and Dependent Visas	t	f	5 years	Algeria
7	Immigrant Visas	t	t	7 years	Algeria
8	Refugee and Asylum Visas	t	f	7 years	Algeria
9	Special Purpose Visas	t	f	10 years	Algeria
1	Tourist Visas	f	f	6 years	Angola
2	Business Visas	t	f	10 years	Angola
3	Work Visas	t	f	8 years	Angola
4	Student Visas	t	f	6 years	Angola
5	Transit Visas	f	f	6 years	Angola
6	Family and Dependent Visas	t	f	5 years	Angola
7	Immigrant Visas	t	t	5 years	Angola
8	Refugee and Asylum Visas	t	f	8 years	Angola
9	Special Purpose Visas	t	f	9 years	Angola
1	Tourist Visas	f	f	6 years	Argentina
2	Business Visas	t	f	6 years	Argentina
3	Work Visas	t	f	8 years	Argentina
4	Student Visas	t	f	10 years	Argentina
5	Transit Visas	f	f	10 years	Argentina
6	Family and Dependent Visas	t	f	9 years	Argentina
7	Immigrant Visas	t	t	6 years	Argentina
8	Refugee and Asylum Visas	t	f	8 years	Argentina
9	Special Purpose Visas	t	f	5 years	Argentina
1	Tourist Visas	f	f	10 years	Armenia
2	Business Visas	t	f	10 years	Armenia
3	Work Visas	t	f	5 years	Armenia
4	Student Visas	t	f	9 years	Armenia
5	Transit Visas	f	f	9 years	Armenia
6	Family and Dependent Visas	t	f	6 years	Armenia
7	Immigrant Visas	t	t	8 years	Armenia
8	Refugee and Asylum Visas	t	f	7 years	Armenia
9	Special Purpose Visas	t	f	7 years	Armenia
1	Tourist Visas	f	f	7 years	Aruba
2	Business Visas	t	f	7 years	Aruba
3	Work Visas	t	f	6 years	Aruba
4	Student Visas	t	f	10 years	Aruba
5	Transit Visas	f	f	10 years	Aruba
6	Family and Dependent Visas	t	f	10 years	Aruba
7	Immigrant Visas	t	t	9 years	Aruba
8	Refugee and Asylum Visas	t	f	7 years	Aruba
9	Special Purpose Visas	t	f	5 years	Aruba
1	Tourist Visas	f	f	8 years	Australia
2	Business Visas	t	f	5 years	Australia
3	Work Visas	t	f	7 years	Australia
4	Student Visas	t	f	6 years	Australia
5	Transit Visas	f	f	9 years	Australia
6	Family and Dependent Visas	t	f	10 years	Australia
7	Immigrant Visas	t	t	5 years	Australia
8	Refugee and Asylum Visas	t	f	9 years	Australia
9	Special Purpose Visas	t	f	6 years	Australia
1	Tourist Visas	f	f	7 years	Austria
2	Business Visas	t	f	9 years	Austria
3	Work Visas	t	f	7 years	Austria
4	Student Visas	t	f	9 years	Austria
5	Transit Visas	f	f	8 years	Austria
6	Family and Dependent Visas	t	f	5 years	Austria
7	Immigrant Visas	t	t	6 years	Austria
8	Refugee and Asylum Visas	t	f	7 years	Austria
9	Special Purpose Visas	t	f	5 years	Austria
1	Tourist Visas	f	f	9 years	Azerbaijan
2	Business Visas	t	f	7 years	Azerbaijan
3	Work Visas	t	f	10 years	Azerbaijan
4	Student Visas	t	f	10 years	Azerbaijan
5	Transit Visas	f	f	7 years	Azerbaijan
6	Family and Dependent Visas	t	f	6 years	Azerbaijan
7	Immigrant Visas	t	t	7 years	Azerbaijan
8	Refugee and Asylum Visas	t	f	8 years	Azerbaijan
9	Special Purpose Visas	t	f	6 years	Azerbaijan
1	Tourist Visas	f	f	5 years	Bahamas
2	Business Visas	t	f	8 years	Bahamas
3	Work Visas	t	f	5 years	Bahamas
4	Student Visas	t	f	10 years	Bahamas
5	Transit Visas	f	f	7 years	Bahamas
6	Family and Dependent Visas	t	f	5 years	Bahamas
7	Immigrant Visas	t	t	8 years	Bahamas
8	Refugee and Asylum Visas	t	f	10 years	Bahamas
9	Special Purpose Visas	t	f	6 years	Bahamas
1	Tourist Visas	f	f	6 years	Bahrain
2	Business Visas	t	f	8 years	Bahrain
3	Work Visas	t	f	8 years	Bahrain
4	Student Visas	t	f	7 years	Bahrain
5	Transit Visas	f	f	9 years	Bahrain
6	Family and Dependent Visas	t	f	7 years	Bahrain
7	Immigrant Visas	t	t	7 years	Bahrain
8	Refugee and Asylum Visas	t	f	5 years	Bahrain
9	Special Purpose Visas	t	f	8 years	Bahrain
1	Tourist Visas	f	f	7 years	Bangladesh
2	Business Visas	t	f	5 years	Bangladesh
3	Work Visas	t	f	7 years	Bangladesh
4	Student Visas	t	f	8 years	Bangladesh
5	Transit Visas	f	f	7 years	Bangladesh
6	Family and Dependent Visas	t	f	7 years	Bangladesh
7	Immigrant Visas	t	t	8 years	Bangladesh
8	Refugee and Asylum Visas	t	f	5 years	Bangladesh
9	Special Purpose Visas	t	f	10 years	Bangladesh
1	Tourist Visas	f	f	10 years	Barbados
2	Business Visas	t	f	10 years	Barbados
3	Work Visas	t	f	10 years	Barbados
4	Student Visas	t	f	6 years	Barbados
5	Transit Visas	f	f	8 years	Barbados
6	Family and Dependent Visas	t	f	10 years	Barbados
7	Immigrant Visas	t	t	10 years	Barbados
8	Refugee and Asylum Visas	t	f	10 years	Barbados
9	Special Purpose Visas	t	f	7 years	Barbados
1	Tourist Visas	f	f	10 years	Belarus
2	Business Visas	t	f	10 years	Belarus
3	Work Visas	t	f	6 years	Belarus
4	Student Visas	t	f	8 years	Belarus
5	Transit Visas	f	f	6 years	Belarus
6	Family and Dependent Visas	t	f	7 years	Belarus
7	Immigrant Visas	t	t	5 years	Belarus
8	Refugee and Asylum Visas	t	f	7 years	Belarus
9	Special Purpose Visas	t	f	10 years	Belarus
1	Tourist Visas	f	f	8 years	Belgium
2	Business Visas	t	f	10 years	Belgium
3	Work Visas	t	f	5 years	Belgium
4	Student Visas	t	f	9 years	Belgium
5	Transit Visas	f	f	10 years	Belgium
6	Family and Dependent Visas	t	f	5 years	Belgium
7	Immigrant Visas	t	t	7 years	Belgium
8	Refugee and Asylum Visas	t	f	8 years	Belgium
9	Special Purpose Visas	t	f	6 years	Belgium
1	Tourist Visas	f	f	9 years	Belize
2	Business Visas	t	f	6 years	Belize
3	Work Visas	t	f	7 years	Belize
4	Student Visas	t	f	10 years	Belize
5	Transit Visas	f	f	8 years	Belize
6	Family and Dependent Visas	t	f	9 years	Belize
7	Immigrant Visas	t	t	5 years	Belize
8	Refugee and Asylum Visas	t	f	9 years	Belize
9	Special Purpose Visas	t	f	8 years	Belize
1	Tourist Visas	f	f	5 years	Benin
2	Business Visas	t	f	5 years	Benin
3	Work Visas	t	f	5 years	Benin
4	Student Visas	t	f	5 years	Benin
5	Transit Visas	f	f	5 years	Benin
6	Family and Dependent Visas	t	f	8 years	Benin
7	Immigrant Visas	t	t	7 years	Benin
8	Refugee and Asylum Visas	t	f	6 years	Benin
9	Special Purpose Visas	t	f	8 years	Benin
1	Tourist Visas	f	f	9 years	Bermuda
2	Business Visas	t	f	5 years	Bermuda
3	Work Visas	t	f	5 years	Bermuda
4	Student Visas	t	f	5 years	Bermuda
5	Transit Visas	f	f	8 years	Bermuda
6	Family and Dependent Visas	t	f	8 years	Bermuda
7	Immigrant Visas	t	t	5 years	Bermuda
8	Refugee and Asylum Visas	t	f	10 years	Bermuda
9	Special Purpose Visas	t	f	9 years	Bermuda
1	Tourist Visas	f	f	10 years	Bhutan
2	Business Visas	t	f	5 years	Bhutan
3	Work Visas	t	f	7 years	Bhutan
4	Student Visas	t	f	7 years	Bhutan
5	Transit Visas	f	f	9 years	Bhutan
6	Family and Dependent Visas	t	f	8 years	Bhutan
7	Immigrant Visas	t	t	6 years	Bhutan
8	Refugee and Asylum Visas	t	f	7 years	Bhutan
9	Special Purpose Visas	t	f	6 years	Bhutan
1	Tourist Visas	f	f	7 years	Bolivia
2	Business Visas	t	f	10 years	Bolivia
3	Work Visas	t	f	10 years	Bolivia
4	Student Visas	t	f	6 years	Bolivia
5	Transit Visas	f	f	8 years	Bolivia
6	Family and Dependent Visas	t	f	7 years	Bolivia
7	Immigrant Visas	t	t	6 years	Bolivia
8	Refugee and Asylum Visas	t	f	8 years	Bolivia
9	Special Purpose Visas	t	f	5 years	Bolivia
1	Tourist Visas	f	f	10 years	Botswana
2	Business Visas	t	f	7 years	Botswana
3	Work Visas	t	f	10 years	Botswana
4	Student Visas	t	f	8 years	Botswana
5	Transit Visas	f	f	7 years	Botswana
6	Family and Dependent Visas	t	f	8 years	Botswana
7	Immigrant Visas	t	t	5 years	Botswana
8	Refugee and Asylum Visas	t	f	6 years	Botswana
9	Special Purpose Visas	t	f	10 years	Botswana
1	Tourist Visas	f	f	9 years	Brazil
2	Business Visas	t	f	9 years	Brazil
3	Work Visas	t	f	9 years	Brazil
4	Student Visas	t	f	7 years	Brazil
5	Transit Visas	f	f	10 years	Brazil
6	Family and Dependent Visas	t	f	10 years	Brazil
7	Immigrant Visas	t	t	9 years	Brazil
8	Refugee and Asylum Visas	t	f	5 years	Brazil
9	Special Purpose Visas	t	f	7 years	Brazil
1	Tourist Visas	f	f	8 years	Brunei
2	Business Visas	t	f	5 years	Brunei
3	Work Visas	t	f	8 years	Brunei
4	Student Visas	t	f	10 years	Brunei
5	Transit Visas	f	f	8 years	Brunei
6	Family and Dependent Visas	t	f	7 years	Brunei
7	Immigrant Visas	t	t	5 years	Brunei
8	Refugee and Asylum Visas	t	f	9 years	Brunei
9	Special Purpose Visas	t	f	9 years	Brunei
1	Tourist Visas	f	f	5 years	Bulgaria
2	Business Visas	t	f	9 years	Bulgaria
3	Work Visas	t	f	7 years	Bulgaria
4	Student Visas	t	f	6 years	Bulgaria
5	Transit Visas	f	f	7 years	Bulgaria
6	Family and Dependent Visas	t	f	10 years	Bulgaria
7	Immigrant Visas	t	t	8 years	Bulgaria
8	Refugee and Asylum Visas	t	f	6 years	Bulgaria
9	Special Purpose Visas	t	f	5 years	Bulgaria
1	Tourist Visas	f	f	10 years	Burundi
2	Business Visas	t	f	9 years	Burundi
3	Work Visas	t	f	10 years	Burundi
4	Student Visas	t	f	6 years	Burundi
5	Transit Visas	f	f	10 years	Burundi
6	Family and Dependent Visas	t	f	5 years	Burundi
7	Immigrant Visas	t	t	6 years	Burundi
8	Refugee and Asylum Visas	t	f	7 years	Burundi
9	Special Purpose Visas	t	f	10 years	Burundi
1	Tourist Visas	f	f	9 years	Cambodia
2	Business Visas	t	f	5 years	Cambodia
3	Work Visas	t	f	10 years	Cambodia
4	Student Visas	t	f	8 years	Cambodia
5	Transit Visas	f	f	6 years	Cambodia
6	Family and Dependent Visas	t	f	9 years	Cambodia
7	Immigrant Visas	t	t	6 years	Cambodia
8	Refugee and Asylum Visas	t	f	8 years	Cambodia
9	Special Purpose Visas	t	f	9 years	Cambodia
1	Tourist Visas	f	f	5 years	Cameroon
2	Business Visas	t	f	10 years	Cameroon
3	Work Visas	t	f	7 years	Cameroon
4	Student Visas	t	f	7 years	Cameroon
5	Transit Visas	f	f	8 years	Cameroon
6	Family and Dependent Visas	t	f	9 years	Cameroon
7	Immigrant Visas	t	t	10 years	Cameroon
8	Refugee and Asylum Visas	t	f	10 years	Cameroon
9	Special Purpose Visas	t	f	10 years	Cameroon
1	Tourist Visas	f	f	7 years	Canada
2	Business Visas	t	f	10 years	Canada
3	Work Visas	t	f	10 years	Canada
4	Student Visas	t	f	9 years	Canada
5	Transit Visas	f	f	7 years	Canada
6	Family and Dependent Visas	t	f	6 years	Canada
7	Immigrant Visas	t	t	7 years	Canada
8	Refugee and Asylum Visas	t	f	10 years	Canada
9	Special Purpose Visas	t	f	7 years	Canada
1	Tourist Visas	f	f	10 years	Chad
2	Business Visas	t	f	7 years	Chad
3	Work Visas	t	f	5 years	Chad
4	Student Visas	t	f	7 years	Chad
5	Transit Visas	f	f	7 years	Chad
6	Family and Dependent Visas	t	f	5 years	Chad
7	Immigrant Visas	t	t	9 years	Chad
8	Refugee and Asylum Visas	t	f	8 years	Chad
9	Special Purpose Visas	t	f	10 years	Chad
1	Tourist Visas	f	f	9 years	Chile
2	Business Visas	t	f	9 years	Chile
3	Work Visas	t	f	9 years	Chile
4	Student Visas	t	f	5 years	Chile
5	Transit Visas	f	f	5 years	Chile
6	Family and Dependent Visas	t	f	9 years	Chile
7	Immigrant Visas	t	t	10 years	Chile
8	Refugee and Asylum Visas	t	f	9 years	Chile
9	Special Purpose Visas	t	f	8 years	Chile
1	Tourist Visas	f	f	7 years	China
2	Business Visas	t	f	9 years	China
3	Work Visas	t	f	7 years	China
4	Student Visas	t	f	7 years	China
5	Transit Visas	f	f	8 years	China
6	Family and Dependent Visas	t	f	6 years	China
7	Immigrant Visas	t	t	8 years	China
8	Refugee and Asylum Visas	t	f	7 years	China
9	Special Purpose Visas	t	f	6 years	China
1	Tourist Visas	f	f	9 years	Colombia
2	Business Visas	t	f	5 years	Colombia
3	Work Visas	t	f	8 years	Colombia
4	Student Visas	t	f	6 years	Colombia
5	Transit Visas	f	f	7 years	Colombia
6	Family and Dependent Visas	t	f	5 years	Colombia
7	Immigrant Visas	t	t	9 years	Colombia
8	Refugee and Asylum Visas	t	f	9 years	Colombia
9	Special Purpose Visas	t	f	5 years	Colombia
1	Tourist Visas	f	f	6 years	Comoros
2	Business Visas	t	f	10 years	Comoros
3	Work Visas	t	f	9 years	Comoros
4	Student Visas	t	f	7 years	Comoros
5	Transit Visas	f	f	9 years	Comoros
6	Family and Dependent Visas	t	f	7 years	Comoros
7	Immigrant Visas	t	t	7 years	Comoros
8	Refugee and Asylum Visas	t	f	6 years	Comoros
9	Special Purpose Visas	t	f	5 years	Comoros
1	Tourist Visas	f	f	8 years	Croatia
2	Business Visas	t	f	8 years	Croatia
3	Work Visas	t	f	6 years	Croatia
4	Student Visas	t	f	6 years	Croatia
5	Transit Visas	f	f	8 years	Croatia
6	Family and Dependent Visas	t	f	6 years	Croatia
7	Immigrant Visas	t	t	7 years	Croatia
8	Refugee and Asylum Visas	t	f	6 years	Croatia
9	Special Purpose Visas	t	f	10 years	Croatia
1	Tourist Visas	f	f	10 years	Cuba
2	Business Visas	t	f	9 years	Cuba
3	Work Visas	t	f	9 years	Cuba
4	Student Visas	t	f	5 years	Cuba
5	Transit Visas	f	f	6 years	Cuba
6	Family and Dependent Visas	t	f	5 years	Cuba
7	Immigrant Visas	t	t	8 years	Cuba
8	Refugee and Asylum Visas	t	f	10 years	Cuba
9	Special Purpose Visas	t	f	9 years	Cuba
1	Tourist Visas	f	f	6 years	Curacao
2	Business Visas	t	f	8 years	Curacao
3	Work Visas	t	f	9 years	Curacao
4	Student Visas	t	f	8 years	Curacao
5	Transit Visas	f	f	8 years	Curacao
6	Family and Dependent Visas	t	f	8 years	Curacao
7	Immigrant Visas	t	t	8 years	Curacao
8	Refugee and Asylum Visas	t	f	9 years	Curacao
9	Special Purpose Visas	t	f	9 years	Curacao
1	Tourist Visas	f	f	10 years	Cyprus
2	Business Visas	t	f	6 years	Cyprus
3	Work Visas	t	f	6 years	Cyprus
4	Student Visas	t	f	8 years	Cyprus
5	Transit Visas	f	f	10 years	Cyprus
6	Family and Dependent Visas	t	f	8 years	Cyprus
7	Immigrant Visas	t	t	10 years	Cyprus
8	Refugee and Asylum Visas	t	f	5 years	Cyprus
9	Special Purpose Visas	t	f	9 years	Cyprus
1	Tourist Visas	f	f	6 years	Denmark
2	Business Visas	t	f	6 years	Denmark
3	Work Visas	t	f	10 years	Denmark
4	Student Visas	t	f	7 years	Denmark
5	Transit Visas	f	f	10 years	Denmark
6	Family and Dependent Visas	t	f	8 years	Denmark
7	Immigrant Visas	t	t	6 years	Denmark
8	Refugee and Asylum Visas	t	f	7 years	Denmark
9	Special Purpose Visas	t	f	10 years	Denmark
1	Tourist Visas	f	f	9 years	Djibouti
2	Business Visas	t	f	9 years	Djibouti
3	Work Visas	t	f	7 years	Djibouti
4	Student Visas	t	f	9 years	Djibouti
5	Transit Visas	f	f	5 years	Djibouti
6	Family and Dependent Visas	t	f	10 years	Djibouti
7	Immigrant Visas	t	t	6 years	Djibouti
8	Refugee and Asylum Visas	t	f	9 years	Djibouti
9	Special Purpose Visas	t	f	9 years	Djibouti
1	Tourist Visas	f	f	10 years	Dominica
2	Business Visas	t	f	7 years	Dominica
3	Work Visas	t	f	9 years	Dominica
4	Student Visas	t	f	5 years	Dominica
5	Transit Visas	f	f	10 years	Dominica
6	Family and Dependent Visas	t	f	10 years	Dominica
7	Immigrant Visas	t	t	7 years	Dominica
8	Refugee and Asylum Visas	t	f	7 years	Dominica
9	Special Purpose Visas	t	f	9 years	Dominica
1	Tourist Visas	f	f	9 years	Ecuador
2	Business Visas	t	f	9 years	Ecuador
3	Work Visas	t	f	10 years	Ecuador
4	Student Visas	t	f	5 years	Ecuador
5	Transit Visas	f	f	10 years	Ecuador
6	Family and Dependent Visas	t	f	6 years	Ecuador
7	Immigrant Visas	t	t	7 years	Ecuador
8	Refugee and Asylum Visas	t	f	8 years	Ecuador
9	Special Purpose Visas	t	f	9 years	Ecuador
1	Tourist Visas	f	f	5 years	Egypt
2	Business Visas	t	f	10 years	Egypt
3	Work Visas	t	f	6 years	Egypt
4	Student Visas	t	f	9 years	Egypt
5	Transit Visas	f	f	6 years	Egypt
6	Family and Dependent Visas	t	f	8 years	Egypt
7	Immigrant Visas	t	t	6 years	Egypt
8	Refugee and Asylum Visas	t	f	10 years	Egypt
9	Special Purpose Visas	t	f	5 years	Egypt
1	Tourist Visas	f	f	9 years	Eritrea
2	Business Visas	t	f	9 years	Eritrea
3	Work Visas	t	f	9 years	Eritrea
4	Student Visas	t	f	5 years	Eritrea
5	Transit Visas	f	f	10 years	Eritrea
6	Family and Dependent Visas	t	f	5 years	Eritrea
7	Immigrant Visas	t	t	5 years	Eritrea
8	Refugee and Asylum Visas	t	f	7 years	Eritrea
9	Special Purpose Visas	t	f	10 years	Eritrea
1	Tourist Visas	f	f	6 years	Estonia
2	Business Visas	t	f	5 years	Estonia
3	Work Visas	t	f	9 years	Estonia
4	Student Visas	t	f	10 years	Estonia
5	Transit Visas	f	f	9 years	Estonia
6	Family and Dependent Visas	t	f	7 years	Estonia
7	Immigrant Visas	t	t	8 years	Estonia
8	Refugee and Asylum Visas	t	f	5 years	Estonia
9	Special Purpose Visas	t	f	9 years	Estonia
1	Tourist Visas	f	f	9 years	Ethiopia
2	Business Visas	t	f	8 years	Ethiopia
3	Work Visas	t	f	7 years	Ethiopia
4	Student Visas	t	f	10 years	Ethiopia
5	Transit Visas	f	f	7 years	Ethiopia
6	Family and Dependent Visas	t	f	6 years	Ethiopia
7	Immigrant Visas	t	t	6 years	Ethiopia
8	Refugee and Asylum Visas	t	f	7 years	Ethiopia
9	Special Purpose Visas	t	f	8 years	Ethiopia
1	Tourist Visas	f	f	6 years	Fiji
2	Business Visas	t	f	7 years	Fiji
3	Work Visas	t	f	9 years	Fiji
4	Student Visas	t	f	9 years	Fiji
5	Transit Visas	f	f	7 years	Fiji
6	Family and Dependent Visas	t	f	8 years	Fiji
7	Immigrant Visas	t	t	10 years	Fiji
8	Refugee and Asylum Visas	t	f	8 years	Fiji
9	Special Purpose Visas	t	f	9 years	Fiji
1	Tourist Visas	f	f	9 years	Finland
2	Business Visas	t	f	10 years	Finland
3	Work Visas	t	f	10 years	Finland
4	Student Visas	t	f	8 years	Finland
5	Transit Visas	f	f	10 years	Finland
6	Family and Dependent Visas	t	f	8 years	Finland
7	Immigrant Visas	t	t	7 years	Finland
8	Refugee and Asylum Visas	t	f	6 years	Finland
9	Special Purpose Visas	t	f	7 years	Finland
1	Tourist Visas	f	f	6 years	France
2	Business Visas	t	f	10 years	France
3	Work Visas	t	f	9 years	France
4	Student Visas	t	f	8 years	France
5	Transit Visas	f	f	7 years	France
6	Family and Dependent Visas	t	f	6 years	France
7	Immigrant Visas	t	t	8 years	France
8	Refugee and Asylum Visas	t	f	7 years	France
9	Special Purpose Visas	t	f	8 years	France
1	Tourist Visas	f	f	7 years	Gabon
2	Business Visas	t	f	8 years	Gabon
3	Work Visas	t	f	7 years	Gabon
4	Student Visas	t	f	6 years	Gabon
5	Transit Visas	f	f	10 years	Gabon
6	Family and Dependent Visas	t	f	7 years	Gabon
7	Immigrant Visas	t	t	10 years	Gabon
8	Refugee and Asylum Visas	t	f	5 years	Gabon
9	Special Purpose Visas	t	f	5 years	Gabon
1	Tourist Visas	f	f	8 years	Gambia
2	Business Visas	t	f	6 years	Gambia
3	Work Visas	t	f	7 years	Gambia
4	Student Visas	t	f	9 years	Gambia
5	Transit Visas	f	f	9 years	Gambia
6	Family and Dependent Visas	t	f	9 years	Gambia
7	Immigrant Visas	t	t	5 years	Gambia
8	Refugee and Asylum Visas	t	f	7 years	Gambia
9	Special Purpose Visas	t	f	8 years	Gambia
1	Tourist Visas	f	f	6 years	Georgia
2	Business Visas	t	f	6 years	Georgia
3	Work Visas	t	f	9 years	Georgia
4	Student Visas	t	f	5 years	Georgia
5	Transit Visas	f	f	8 years	Georgia
6	Family and Dependent Visas	t	f	8 years	Georgia
7	Immigrant Visas	t	t	5 years	Georgia
8	Refugee and Asylum Visas	t	f	10 years	Georgia
9	Special Purpose Visas	t	f	9 years	Georgia
1	Tourist Visas	f	f	5 years	Germany
2	Business Visas	t	f	6 years	Germany
3	Work Visas	t	f	5 years	Germany
4	Student Visas	t	f	6 years	Germany
5	Transit Visas	f	f	5 years	Germany
6	Family and Dependent Visas	t	f	5 years	Germany
7	Immigrant Visas	t	t	5 years	Germany
8	Refugee and Asylum Visas	t	f	5 years	Germany
9	Special Purpose Visas	t	f	5 years	Germany
1	Tourist Visas	f	f	6 years	Ghana
2	Business Visas	t	f	9 years	Ghana
3	Work Visas	t	f	6 years	Ghana
4	Student Visas	t	f	7 years	Ghana
5	Transit Visas	f	f	6 years	Ghana
6	Family and Dependent Visas	t	f	7 years	Ghana
7	Immigrant Visas	t	t	8 years	Ghana
8	Refugee and Asylum Visas	t	f	7 years	Ghana
9	Special Purpose Visas	t	f	8 years	Ghana
1	Tourist Visas	f	f	9 years	Gibraltar
2	Business Visas	t	f	9 years	Gibraltar
3	Work Visas	t	f	5 years	Gibraltar
4	Student Visas	t	f	10 years	Gibraltar
5	Transit Visas	f	f	5 years	Gibraltar
6	Family and Dependent Visas	t	f	9 years	Gibraltar
7	Immigrant Visas	t	t	6 years	Gibraltar
8	Refugee and Asylum Visas	t	f	8 years	Gibraltar
9	Special Purpose Visas	t	f	9 years	Gibraltar
1	Tourist Visas	f	f	9 years	Greece
2	Business Visas	t	f	7 years	Greece
3	Work Visas	t	f	10 years	Greece
4	Student Visas	t	f	10 years	Greece
5	Transit Visas	f	f	10 years	Greece
6	Family and Dependent Visas	t	f	6 years	Greece
7	Immigrant Visas	t	t	5 years	Greece
8	Refugee and Asylum Visas	t	f	9 years	Greece
9	Special Purpose Visas	t	f	9 years	Greece
1	Tourist Visas	f	f	6 years	Greenland
2	Business Visas	t	f	10 years	Greenland
3	Work Visas	t	f	8 years	Greenland
4	Student Visas	t	f	5 years	Greenland
5	Transit Visas	f	f	5 years	Greenland
6	Family and Dependent Visas	t	f	8 years	Greenland
7	Immigrant Visas	t	t	5 years	Greenland
8	Refugee and Asylum Visas	t	f	7 years	Greenland
9	Special Purpose Visas	t	f	6 years	Greenland
1	Tourist Visas	f	f	7 years	Guatemala
2	Business Visas	t	f	5 years	Guatemala
3	Work Visas	t	f	6 years	Guatemala
4	Student Visas	t	f	6 years	Guatemala
5	Transit Visas	f	f	9 years	Guatemala
6	Family and Dependent Visas	t	f	10 years	Guatemala
7	Immigrant Visas	t	t	10 years	Guatemala
8	Refugee and Asylum Visas	t	f	10 years	Guatemala
9	Special Purpose Visas	t	f	8 years	Guatemala
1	Tourist Visas	f	f	7 years	Guinea
2	Business Visas	t	f	9 years	Guinea
3	Work Visas	t	f	8 years	Guinea
4	Student Visas	t	f	6 years	Guinea
5	Transit Visas	f	f	9 years	Guinea
6	Family and Dependent Visas	t	f	10 years	Guinea
7	Immigrant Visas	t	t	10 years	Guinea
8	Refugee and Asylum Visas	t	f	8 years	Guinea
9	Special Purpose Visas	t	f	8 years	Guinea
1	Tourist Visas	f	f	6 years	Guyana
2	Business Visas	t	f	9 years	Guyana
3	Work Visas	t	f	7 years	Guyana
4	Student Visas	t	f	6 years	Guyana
5	Transit Visas	f	f	8 years	Guyana
6	Family and Dependent Visas	t	f	5 years	Guyana
7	Immigrant Visas	t	t	10 years	Guyana
8	Refugee and Asylum Visas	t	f	8 years	Guyana
9	Special Purpose Visas	t	f	8 years	Guyana
1	Tourist Visas	f	f	6 years	Haiti
2	Business Visas	t	f	9 years	Haiti
3	Work Visas	t	f	5 years	Haiti
4	Student Visas	t	f	10 years	Haiti
5	Transit Visas	f	f	10 years	Haiti
6	Family and Dependent Visas	t	f	10 years	Haiti
7	Immigrant Visas	t	t	8 years	Haiti
8	Refugee and Asylum Visas	t	f	9 years	Haiti
9	Special Purpose Visas	t	f	7 years	Haiti
1	Tourist Visas	f	f	6 years	Honduras
2	Business Visas	t	f	6 years	Honduras
3	Work Visas	t	f	8 years	Honduras
4	Student Visas	t	f	9 years	Honduras
5	Transit Visas	f	f	8 years	Honduras
6	Family and Dependent Visas	t	f	9 years	Honduras
7	Immigrant Visas	t	t	7 years	Honduras
8	Refugee and Asylum Visas	t	f	9 years	Honduras
9	Special Purpose Visas	t	f	7 years	Honduras
1	Tourist Visas	f	f	8 years	Hungary
2	Business Visas	t	f	10 years	Hungary
3	Work Visas	t	f	6 years	Hungary
4	Student Visas	t	f	8 years	Hungary
5	Transit Visas	f	f	8 years	Hungary
6	Family and Dependent Visas	t	f	6 years	Hungary
7	Immigrant Visas	t	t	5 years	Hungary
8	Refugee and Asylum Visas	t	f	5 years	Hungary
9	Special Purpose Visas	t	f	9 years	Hungary
1	Tourist Visas	f	f	5 years	Iceland
2	Business Visas	t	f	5 years	Iceland
3	Work Visas	t	f	9 years	Iceland
4	Student Visas	t	f	8 years	Iceland
5	Transit Visas	f	f	6 years	Iceland
6	Family and Dependent Visas	t	f	10 years	Iceland
7	Immigrant Visas	t	t	10 years	Iceland
8	Refugee and Asylum Visas	t	f	8 years	Iceland
9	Special Purpose Visas	t	f	10 years	Iceland
1	Tourist Visas	f	f	8 years	India
2	Business Visas	t	f	6 years	India
3	Work Visas	t	f	10 years	India
4	Student Visas	t	f	5 years	India
5	Transit Visas	f	f	8 years	India
6	Family and Dependent Visas	t	f	7 years	India
7	Immigrant Visas	t	t	9 years	India
8	Refugee and Asylum Visas	t	f	9 years	India
9	Special Purpose Visas	t	f	10 years	India
1	Tourist Visas	f	f	9 years	Indonesia
2	Business Visas	t	f	10 years	Indonesia
3	Work Visas	t	f	7 years	Indonesia
4	Student Visas	t	f	9 years	Indonesia
5	Transit Visas	f	f	10 years	Indonesia
6	Family and Dependent Visas	t	f	5 years	Indonesia
7	Immigrant Visas	t	t	6 years	Indonesia
8	Refugee and Asylum Visas	t	f	7 years	Indonesia
9	Special Purpose Visas	t	f	10 years	Indonesia
1	Tourist Visas	f	f	6 years	Iran
2	Business Visas	t	f	7 years	Iran
3	Work Visas	t	f	10 years	Iran
4	Student Visas	t	f	6 years	Iran
5	Transit Visas	f	f	9 years	Iran
6	Family and Dependent Visas	t	f	5 years	Iran
7	Immigrant Visas	t	t	6 years	Iran
8	Refugee and Asylum Visas	t	f	9 years	Iran
9	Special Purpose Visas	t	f	9 years	Iran
1	Tourist Visas	f	f	5 years	Iraq
2	Business Visas	t	f	9 years	Iraq
3	Work Visas	t	f	9 years	Iraq
4	Student Visas	t	f	5 years	Iraq
5	Transit Visas	f	f	6 years	Iraq
6	Family and Dependent Visas	t	f	9 years	Iraq
7	Immigrant Visas	t	t	10 years	Iraq
8	Refugee and Asylum Visas	t	f	6 years	Iraq
9	Special Purpose Visas	t	f	8 years	Iraq
1	Tourist Visas	f	f	9 years	Ireland
2	Business Visas	t	f	8 years	Ireland
3	Work Visas	t	f	9 years	Ireland
4	Student Visas	t	f	8 years	Ireland
5	Transit Visas	f	f	8 years	Ireland
6	Family and Dependent Visas	t	f	8 years	Ireland
7	Immigrant Visas	t	t	10 years	Ireland
8	Refugee and Asylum Visas	t	f	9 years	Ireland
9	Special Purpose Visas	t	f	6 years	Ireland
1	Tourist Visas	f	f	5 years	Israel
2	Business Visas	t	f	9 years	Israel
3	Work Visas	t	f	10 years	Israel
4	Student Visas	t	f	6 years	Israel
5	Transit Visas	f	f	7 years	Israel
6	Family and Dependent Visas	t	f	6 years	Israel
7	Immigrant Visas	t	t	9 years	Israel
8	Refugee and Asylum Visas	t	f	7 years	Israel
9	Special Purpose Visas	t	f	6 years	Israel
1	Tourist Visas	f	f	10 years	Italy
2	Business Visas	t	f	6 years	Italy
3	Work Visas	t	f	8 years	Italy
4	Student Visas	t	f	7 years	Italy
5	Transit Visas	f	f	5 years	Italy
6	Family and Dependent Visas	t	f	6 years	Italy
7	Immigrant Visas	t	t	5 years	Italy
8	Refugee and Asylum Visas	t	f	6 years	Italy
9	Special Purpose Visas	t	f	8 years	Italy
1	Tourist Visas	f	f	10 years	Jamaica
2	Business Visas	t	f	7 years	Jamaica
3	Work Visas	t	f	5 years	Jamaica
4	Student Visas	t	f	8 years	Jamaica
5	Transit Visas	f	f	5 years	Jamaica
6	Family and Dependent Visas	t	f	7 years	Jamaica
7	Immigrant Visas	t	t	10 years	Jamaica
8	Refugee and Asylum Visas	t	f	8 years	Jamaica
9	Special Purpose Visas	t	f	7 years	Jamaica
1	Tourist Visas	f	f	5 years	Japan
2	Business Visas	t	f	6 years	Japan
3	Work Visas	t	f	7 years	Japan
4	Student Visas	t	f	10 years	Japan
5	Transit Visas	f	f	9 years	Japan
6	Family and Dependent Visas	t	f	9 years	Japan
7	Immigrant Visas	t	t	8 years	Japan
8	Refugee and Asylum Visas	t	f	9 years	Japan
9	Special Purpose Visas	t	f	5 years	Japan
1	Tourist Visas	f	f	6 years	Jordan
2	Business Visas	t	f	10 years	Jordan
3	Work Visas	t	f	9 years	Jordan
4	Student Visas	t	f	5 years	Jordan
5	Transit Visas	f	f	9 years	Jordan
6	Family and Dependent Visas	t	f	5 years	Jordan
7	Immigrant Visas	t	t	5 years	Jordan
8	Refugee and Asylum Visas	t	f	10 years	Jordan
9	Special Purpose Visas	t	f	7 years	Jordan
1	Tourist Visas	f	f	9 years	Kazakhstan
2	Business Visas	t	f	6 years	Kazakhstan
3	Work Visas	t	f	8 years	Kazakhstan
4	Student Visas	t	f	7 years	Kazakhstan
5	Transit Visas	f	f	8 years	Kazakhstan
6	Family and Dependent Visas	t	f	6 years	Kazakhstan
7	Immigrant Visas	t	t	5 years	Kazakhstan
8	Refugee and Asylum Visas	t	f	10 years	Kazakhstan
9	Special Purpose Visas	t	f	6 years	Kazakhstan
1	Tourist Visas	f	f	8 years	Kenya
2	Business Visas	t	f	9 years	Kenya
3	Work Visas	t	f	5 years	Kenya
4	Student Visas	t	f	8 years	Kenya
5	Transit Visas	f	f	8 years	Kenya
6	Family and Dependent Visas	t	f	5 years	Kenya
7	Immigrant Visas	t	t	10 years	Kenya
8	Refugee and Asylum Visas	t	f	6 years	Kenya
9	Special Purpose Visas	t	f	10 years	Kenya
1	Tourist Visas	f	f	5 years	Kiribati
2	Business Visas	t	f	10 years	Kiribati
3	Work Visas	t	f	10 years	Kiribati
4	Student Visas	t	f	10 years	Kiribati
5	Transit Visas	f	f	5 years	Kiribati
6	Family and Dependent Visas	t	f	10 years	Kiribati
7	Immigrant Visas	t	t	6 years	Kiribati
8	Refugee and Asylum Visas	t	f	7 years	Kiribati
9	Special Purpose Visas	t	f	5 years	Kiribati
1	Tourist Visas	f	f	7 years	Kosovo
2	Business Visas	t	f	6 years	Kosovo
3	Work Visas	t	f	8 years	Kosovo
4	Student Visas	t	f	9 years	Kosovo
5	Transit Visas	f	f	9 years	Kosovo
6	Family and Dependent Visas	t	f	8 years	Kosovo
7	Immigrant Visas	t	t	7 years	Kosovo
8	Refugee and Asylum Visas	t	f	5 years	Kosovo
9	Special Purpose Visas	t	f	6 years	Kosovo
1	Tourist Visas	f	f	7 years	Kyrgyzstan
2	Business Visas	t	f	8 years	Kyrgyzstan
3	Work Visas	t	f	6 years	Kyrgyzstan
4	Student Visas	t	f	10 years	Kyrgyzstan
5	Transit Visas	f	f	7 years	Kyrgyzstan
6	Family and Dependent Visas	t	f	9 years	Kyrgyzstan
7	Immigrant Visas	t	t	9 years	Kyrgyzstan
8	Refugee and Asylum Visas	t	f	5 years	Kyrgyzstan
9	Special Purpose Visas	t	f	8 years	Kyrgyzstan
1	Tourist Visas	f	f	8 years	Laos
2	Business Visas	t	f	9 years	Laos
3	Work Visas	t	f	7 years	Laos
4	Student Visas	t	f	8 years	Laos
5	Transit Visas	f	f	6 years	Laos
6	Family and Dependent Visas	t	f	9 years	Laos
7	Immigrant Visas	t	t	9 years	Laos
8	Refugee and Asylum Visas	t	f	5 years	Laos
9	Special Purpose Visas	t	f	10 years	Laos
1	Tourist Visas	f	f	7 years	Latvia
2	Business Visas	t	f	6 years	Latvia
3	Work Visas	t	f	7 years	Latvia
4	Student Visas	t	f	10 years	Latvia
5	Transit Visas	f	f	5 years	Latvia
6	Family and Dependent Visas	t	f	5 years	Latvia
7	Immigrant Visas	t	t	8 years	Latvia
8	Refugee and Asylum Visas	t	f	10 years	Latvia
9	Special Purpose Visas	t	f	8 years	Latvia
1	Tourist Visas	f	f	6 years	Lebanon
2	Business Visas	t	f	7 years	Lebanon
3	Work Visas	t	f	9 years	Lebanon
4	Student Visas	t	f	6 years	Lebanon
5	Transit Visas	f	f	5 years	Lebanon
6	Family and Dependent Visas	t	f	10 years	Lebanon
7	Immigrant Visas	t	t	5 years	Lebanon
8	Refugee and Asylum Visas	t	f	9 years	Lebanon
9	Special Purpose Visas	t	f	10 years	Lebanon
1	Tourist Visas	f	f	8 years	Lesotho
2	Business Visas	t	f	9 years	Lesotho
3	Work Visas	t	f	10 years	Lesotho
4	Student Visas	t	f	10 years	Lesotho
5	Transit Visas	f	f	9 years	Lesotho
6	Family and Dependent Visas	t	f	8 years	Lesotho
7	Immigrant Visas	t	t	7 years	Lesotho
8	Refugee and Asylum Visas	t	f	9 years	Lesotho
9	Special Purpose Visas	t	f	10 years	Lesotho
1	Tourist Visas	f	f	9 years	Liberia
2	Business Visas	t	f	5 years	Liberia
3	Work Visas	t	f	9 years	Liberia
4	Student Visas	t	f	8 years	Liberia
5	Transit Visas	f	f	6 years	Liberia
6	Family and Dependent Visas	t	f	8 years	Liberia
7	Immigrant Visas	t	t	10 years	Liberia
8	Refugee and Asylum Visas	t	f	5 years	Liberia
9	Special Purpose Visas	t	f	10 years	Liberia
1	Tourist Visas	f	f	7 years	Libya
2	Business Visas	t	f	5 years	Libya
3	Work Visas	t	f	8 years	Libya
4	Student Visas	t	f	9 years	Libya
5	Transit Visas	f	f	6 years	Libya
6	Family and Dependent Visas	t	f	6 years	Libya
7	Immigrant Visas	t	t	5 years	Libya
8	Refugee and Asylum Visas	t	f	10 years	Libya
9	Special Purpose Visas	t	f	8 years	Libya
1	Tourist Visas	f	f	9 years	Liechtenstein
2	Business Visas	t	f	5 years	Liechtenstein
3	Work Visas	t	f	9 years	Liechtenstein
4	Student Visas	t	f	8 years	Liechtenstein
5	Transit Visas	f	f	8 years	Liechtenstein
6	Family and Dependent Visas	t	f	5 years	Liechtenstein
7	Immigrant Visas	t	t	10 years	Liechtenstein
8	Refugee and Asylum Visas	t	f	9 years	Liechtenstein
9	Special Purpose Visas	t	f	10 years	Liechtenstein
1	Tourist Visas	f	f	10 years	Lithuania
2	Business Visas	t	f	10 years	Lithuania
3	Work Visas	t	f	10 years	Lithuania
4	Student Visas	t	f	7 years	Lithuania
5	Transit Visas	f	f	7 years	Lithuania
6	Family and Dependent Visas	t	f	8 years	Lithuania
7	Immigrant Visas	t	t	7 years	Lithuania
8	Refugee and Asylum Visas	t	f	5 years	Lithuania
9	Special Purpose Visas	t	f	6 years	Lithuania
1	Tourist Visas	f	f	10 years	Luxembourg
2	Business Visas	t	f	5 years	Luxembourg
3	Work Visas	t	f	8 years	Luxembourg
4	Student Visas	t	f	8 years	Luxembourg
5	Transit Visas	f	f	10 years	Luxembourg
6	Family and Dependent Visas	t	f	7 years	Luxembourg
7	Immigrant Visas	t	t	6 years	Luxembourg
8	Refugee and Asylum Visas	t	f	8 years	Luxembourg
9	Special Purpose Visas	t	f	9 years	Luxembourg
1	Tourist Visas	f	f	8 years	Macao
2	Business Visas	t	f	8 years	Macao
3	Work Visas	t	f	9 years	Macao
4	Student Visas	t	f	7 years	Macao
5	Transit Visas	f	f	8 years	Macao
6	Family and Dependent Visas	t	f	10 years	Macao
7	Immigrant Visas	t	t	10 years	Macao
8	Refugee and Asylum Visas	t	f	9 years	Macao
9	Special Purpose Visas	t	f	9 years	Macao
1	Tourist Visas	f	f	8 years	Macedonia
2	Business Visas	t	f	10 years	Macedonia
3	Work Visas	t	f	10 years	Macedonia
4	Student Visas	t	f	7 years	Macedonia
5	Transit Visas	f	f	6 years	Macedonia
6	Family and Dependent Visas	t	f	6 years	Macedonia
7	Immigrant Visas	t	t	7 years	Macedonia
8	Refugee and Asylum Visas	t	f	7 years	Macedonia
9	Special Purpose Visas	t	f	9 years	Macedonia
1	Tourist Visas	f	f	10 years	Madagascar
2	Business Visas	t	f	7 years	Madagascar
3	Work Visas	t	f	5 years	Madagascar
4	Student Visas	t	f	5 years	Madagascar
5	Transit Visas	f	f	8 years	Madagascar
6	Family and Dependent Visas	t	f	9 years	Madagascar
7	Immigrant Visas	t	t	6 years	Madagascar
8	Refugee and Asylum Visas	t	f	8 years	Madagascar
9	Special Purpose Visas	t	f	5 years	Madagascar
1	Tourist Visas	f	f	5 years	Malawi
2	Business Visas	t	f	7 years	Malawi
3	Work Visas	t	f	10 years	Malawi
4	Student Visas	t	f	7 years	Malawi
5	Transit Visas	f	f	10 years	Malawi
6	Family and Dependent Visas	t	f	7 years	Malawi
7	Immigrant Visas	t	t	6 years	Malawi
8	Refugee and Asylum Visas	t	f	10 years	Malawi
9	Special Purpose Visas	t	f	9 years	Malawi
1	Tourist Visas	f	f	10 years	Malaysia
2	Business Visas	t	f	5 years	Malaysia
3	Work Visas	t	f	10 years	Malaysia
4	Student Visas	t	f	5 years	Malaysia
5	Transit Visas	f	f	5 years	Malaysia
6	Family and Dependent Visas	t	f	5 years	Malaysia
7	Immigrant Visas	t	t	5 years	Malaysia
8	Refugee and Asylum Visas	t	f	10 years	Malaysia
9	Special Purpose Visas	t	f	9 years	Malaysia
1	Tourist Visas	f	f	5 years	Maldives
2	Business Visas	t	f	6 years	Maldives
3	Work Visas	t	f	9 years	Maldives
4	Student Visas	t	f	5 years	Maldives
5	Transit Visas	f	f	8 years	Maldives
6	Family and Dependent Visas	t	f	10 years	Maldives
7	Immigrant Visas	t	t	9 years	Maldives
8	Refugee and Asylum Visas	t	f	5 years	Maldives
9	Special Purpose Visas	t	f	5 years	Maldives
1	Tourist Visas	f	f	5 years	Mali
2	Business Visas	t	f	5 years	Mali
3	Work Visas	t	f	5 years	Mali
4	Student Visas	t	f	9 years	Mali
5	Transit Visas	f	f	9 years	Mali
6	Family and Dependent Visas	t	f	5 years	Mali
7	Immigrant Visas	t	t	8 years	Mali
8	Refugee and Asylum Visas	t	f	6 years	Mali
9	Special Purpose Visas	t	f	6 years	Mali
1	Tourist Visas	f	f	9 years	Malta
2	Business Visas	t	f	7 years	Malta
3	Work Visas	t	f	7 years	Malta
4	Student Visas	t	f	7 years	Malta
5	Transit Visas	f	f	9 years	Malta
6	Family and Dependent Visas	t	f	7 years	Malta
7	Immigrant Visas	t	t	10 years	Malta
8	Refugee and Asylum Visas	t	f	10 years	Malta
9	Special Purpose Visas	t	f	8 years	Malta
1	Tourist Visas	f	f	6 years	Martinique
2	Business Visas	t	f	9 years	Martinique
3	Work Visas	t	f	10 years	Martinique
4	Student Visas	t	f	9 years	Martinique
5	Transit Visas	f	f	6 years	Martinique
6	Family and Dependent Visas	t	f	7 years	Martinique
7	Immigrant Visas	t	t	8 years	Martinique
8	Refugee and Asylum Visas	t	f	8 years	Martinique
9	Special Purpose Visas	t	f	6 years	Martinique
1	Tourist Visas	f	f	5 years	Mauritania
2	Business Visas	t	f	6 years	Mauritania
3	Work Visas	t	f	8 years	Mauritania
4	Student Visas	t	f	6 years	Mauritania
5	Transit Visas	f	f	8 years	Mauritania
6	Family and Dependent Visas	t	f	5 years	Mauritania
7	Immigrant Visas	t	t	8 years	Mauritania
8	Refugee and Asylum Visas	t	f	8 years	Mauritania
9	Special Purpose Visas	t	f	9 years	Mauritania
1	Tourist Visas	f	f	10 years	Mauritius
2	Business Visas	t	f	9 years	Mauritius
3	Work Visas	t	f	8 years	Mauritius
4	Student Visas	t	f	10 years	Mauritius
5	Transit Visas	f	f	5 years	Mauritius
6	Family and Dependent Visas	t	f	9 years	Mauritius
7	Immigrant Visas	t	t	5 years	Mauritius
8	Refugee and Asylum Visas	t	f	9 years	Mauritius
9	Special Purpose Visas	t	f	7 years	Mauritius
1	Tourist Visas	f	f	6 years	Mayotte
2	Business Visas	t	f	5 years	Mayotte
3	Work Visas	t	f	7 years	Mayotte
4	Student Visas	t	f	9 years	Mayotte
5	Transit Visas	f	f	5 years	Mayotte
6	Family and Dependent Visas	t	f	10 years	Mayotte
7	Immigrant Visas	t	t	10 years	Mayotte
8	Refugee and Asylum Visas	t	f	9 years	Mayotte
9	Special Purpose Visas	t	f	5 years	Mayotte
1	Tourist Visas	f	f	5 years	Mexico
2	Business Visas	t	f	6 years	Mexico
3	Work Visas	t	f	6 years	Mexico
4	Student Visas	t	f	8 years	Mexico
5	Transit Visas	f	f	9 years	Mexico
6	Family and Dependent Visas	t	f	7 years	Mexico
7	Immigrant Visas	t	t	9 years	Mexico
8	Refugee and Asylum Visas	t	f	6 years	Mexico
9	Special Purpose Visas	t	f	7 years	Mexico
1	Tourist Visas	f	f	9 years	Moldova
2	Business Visas	t	f	9 years	Moldova
3	Work Visas	t	f	6 years	Moldova
4	Student Visas	t	f	5 years	Moldova
5	Transit Visas	f	f	10 years	Moldova
6	Family and Dependent Visas	t	f	5 years	Moldova
7	Immigrant Visas	t	t	8 years	Moldova
8	Refugee and Asylum Visas	t	f	10 years	Moldova
9	Special Purpose Visas	t	f	5 years	Moldova
1	Tourist Visas	f	f	5 years	Monaco
2	Business Visas	t	f	9 years	Monaco
3	Work Visas	t	f	8 years	Monaco
4	Student Visas	t	f	9 years	Monaco
5	Transit Visas	f	f	7 years	Monaco
6	Family and Dependent Visas	t	f	6 years	Monaco
7	Immigrant Visas	t	t	7 years	Monaco
8	Refugee and Asylum Visas	t	f	5 years	Monaco
9	Special Purpose Visas	t	f	7 years	Monaco
1	Tourist Visas	f	f	5 years	Mongolia
2	Business Visas	t	f	6 years	Mongolia
3	Work Visas	t	f	5 years	Mongolia
4	Student Visas	t	f	10 years	Mongolia
5	Transit Visas	f	f	6 years	Mongolia
6	Family and Dependent Visas	t	f	5 years	Mongolia
7	Immigrant Visas	t	t	10 years	Mongolia
8	Refugee and Asylum Visas	t	f	8 years	Mongolia
9	Special Purpose Visas	t	f	8 years	Mongolia
1	Tourist Visas	f	f	9 years	Montenegro
2	Business Visas	t	f	9 years	Montenegro
3	Work Visas	t	f	9 years	Montenegro
4	Student Visas	t	f	10 years	Montenegro
5	Transit Visas	f	f	8 years	Montenegro
6	Family and Dependent Visas	t	f	5 years	Montenegro
7	Immigrant Visas	t	t	8 years	Montenegro
8	Refugee and Asylum Visas	t	f	8 years	Montenegro
9	Special Purpose Visas	t	f	6 years	Montenegro
1	Tourist Visas	f	f	5 years	Montserrat
2	Business Visas	t	f	10 years	Montserrat
3	Work Visas	t	f	8 years	Montserrat
4	Student Visas	t	f	9 years	Montserrat
5	Transit Visas	f	f	9 years	Montserrat
6	Family and Dependent Visas	t	f	8 years	Montserrat
7	Immigrant Visas	t	t	5 years	Montserrat
8	Refugee and Asylum Visas	t	f	10 years	Montserrat
9	Special Purpose Visas	t	f	8 years	Montserrat
1	Tourist Visas	f	f	8 years	Morocco
2	Business Visas	t	f	6 years	Morocco
3	Work Visas	t	f	10 years	Morocco
4	Student Visas	t	f	6 years	Morocco
5	Transit Visas	f	f	6 years	Morocco
6	Family and Dependent Visas	t	f	6 years	Morocco
7	Immigrant Visas	t	t	9 years	Morocco
8	Refugee and Asylum Visas	t	f	9 years	Morocco
9	Special Purpose Visas	t	f	9 years	Morocco
1	Tourist Visas	f	f	10 years	Mozambique
2	Business Visas	t	f	6 years	Mozambique
3	Work Visas	t	f	7 years	Mozambique
4	Student Visas	t	f	6 years	Mozambique
5	Transit Visas	f	f	5 years	Mozambique
6	Family and Dependent Visas	t	f	6 years	Mozambique
7	Immigrant Visas	t	t	10 years	Mozambique
8	Refugee and Asylum Visas	t	f	9 years	Mozambique
9	Special Purpose Visas	t	f	5 years	Mozambique
1	Tourist Visas	f	f	9 years	Myanmar
2	Business Visas	t	f	7 years	Myanmar
3	Work Visas	t	f	8 years	Myanmar
4	Student Visas	t	f	9 years	Myanmar
5	Transit Visas	f	f	9 years	Myanmar
6	Family and Dependent Visas	t	f	8 years	Myanmar
7	Immigrant Visas	t	t	10 years	Myanmar
8	Refugee and Asylum Visas	t	f	9 years	Myanmar
9	Special Purpose Visas	t	f	6 years	Myanmar
1	Tourist Visas	f	f	9 years	Namibia
2	Business Visas	t	f	7 years	Namibia
3	Work Visas	t	f	9 years	Namibia
4	Student Visas	t	f	6 years	Namibia
5	Transit Visas	f	f	6 years	Namibia
6	Family and Dependent Visas	t	f	9 years	Namibia
7	Immigrant Visas	t	t	10 years	Namibia
8	Refugee and Asylum Visas	t	f	7 years	Namibia
9	Special Purpose Visas	t	f	6 years	Namibia
1	Tourist Visas	f	f	10 years	Nauru
2	Business Visas	t	f	8 years	Nauru
3	Work Visas	t	f	10 years	Nauru
4	Student Visas	t	f	7 years	Nauru
5	Transit Visas	f	f	10 years	Nauru
6	Family and Dependent Visas	t	f	8 years	Nauru
7	Immigrant Visas	t	t	10 years	Nauru
8	Refugee and Asylum Visas	t	f	6 years	Nauru
9	Special Purpose Visas	t	f	9 years	Nauru
1	Tourist Visas	f	f	9 years	Nepal
2	Business Visas	t	f	9 years	Nepal
3	Work Visas	t	f	9 years	Nepal
4	Student Visas	t	f	5 years	Nepal
5	Transit Visas	f	f	8 years	Nepal
6	Family and Dependent Visas	t	f	7 years	Nepal
7	Immigrant Visas	t	t	7 years	Nepal
8	Refugee and Asylum Visas	t	f	7 years	Nepal
9	Special Purpose Visas	t	f	9 years	Nepal
1	Tourist Visas	f	f	8 years	Netherlands
2	Business Visas	t	f	8 years	Netherlands
3	Work Visas	t	f	9 years	Netherlands
4	Student Visas	t	f	7 years	Netherlands
5	Transit Visas	f	f	9 years	Netherlands
6	Family and Dependent Visas	t	f	9 years	Netherlands
7	Immigrant Visas	t	t	6 years	Netherlands
8	Refugee and Asylum Visas	t	f	6 years	Netherlands
9	Special Purpose Visas	t	f	8 years	Netherlands
1	Tourist Visas	f	f	10 years	Nicaragua
2	Business Visas	t	f	6 years	Nicaragua
3	Work Visas	t	f	7 years	Nicaragua
4	Student Visas	t	f	5 years	Nicaragua
5	Transit Visas	f	f	6 years	Nicaragua
6	Family and Dependent Visas	t	f	9 years	Nicaragua
7	Immigrant Visas	t	t	10 years	Nicaragua
8	Refugee and Asylum Visas	t	f	9 years	Nicaragua
9	Special Purpose Visas	t	f	9 years	Nicaragua
1	Tourist Visas	f	f	5 years	Niger
2	Business Visas	t	f	9 years	Niger
3	Work Visas	t	f	10 years	Niger
4	Student Visas	t	f	9 years	Niger
5	Transit Visas	f	f	10 years	Niger
6	Family and Dependent Visas	t	f	5 years	Niger
7	Immigrant Visas	t	t	7 years	Niger
8	Refugee and Asylum Visas	t	f	6 years	Niger
9	Special Purpose Visas	t	f	5 years	Niger
1	Tourist Visas	f	f	8 years	Nigeria
2	Business Visas	t	f	8 years	Nigeria
3	Work Visas	t	f	7 years	Nigeria
4	Student Visas	t	f	10 years	Nigeria
5	Transit Visas	f	f	9 years	Nigeria
6	Family and Dependent Visas	t	f	10 years	Nigeria
7	Immigrant Visas	t	t	5 years	Nigeria
8	Refugee and Asylum Visas	t	f	6 years	Nigeria
9	Special Purpose Visas	t	f	6 years	Nigeria
1	Tourist Visas	f	f	7 years	Niue
2	Business Visas	t	f	10 years	Niue
3	Work Visas	t	f	5 years	Niue
4	Student Visas	t	f	6 years	Niue
5	Transit Visas	f	f	8 years	Niue
6	Family and Dependent Visas	t	f	9 years	Niue
7	Immigrant Visas	t	t	10 years	Niue
8	Refugee and Asylum Visas	t	f	7 years	Niue
9	Special Purpose Visas	t	f	6 years	Niue
1	Tourist Visas	f	f	5 years	Norway
2	Business Visas	t	f	8 years	Norway
3	Work Visas	t	f	6 years	Norway
4	Student Visas	t	f	9 years	Norway
5	Transit Visas	f	f	8 years	Norway
6	Family and Dependent Visas	t	f	9 years	Norway
7	Immigrant Visas	t	t	6 years	Norway
8	Refugee and Asylum Visas	t	f	10 years	Norway
9	Special Purpose Visas	t	f	5 years	Norway
1	Tourist Visas	f	f	8 years	Oman
2	Business Visas	t	f	6 years	Oman
3	Work Visas	t	f	8 years	Oman
4	Student Visas	t	f	8 years	Oman
5	Transit Visas	f	f	6 years	Oman
6	Family and Dependent Visas	t	f	9 years	Oman
7	Immigrant Visas	t	t	7 years	Oman
8	Refugee and Asylum Visas	t	f	9 years	Oman
9	Special Purpose Visas	t	f	10 years	Oman
1	Tourist Visas	f	f	5 years	Pakistan
2	Business Visas	t	f	10 years	Pakistan
3	Work Visas	t	f	5 years	Pakistan
4	Student Visas	t	f	5 years	Pakistan
5	Transit Visas	f	f	10 years	Pakistan
6	Family and Dependent Visas	t	f	6 years	Pakistan
7	Immigrant Visas	t	t	6 years	Pakistan
8	Refugee and Asylum Visas	t	f	8 years	Pakistan
9	Special Purpose Visas	t	f	10 years	Pakistan
1	Tourist Visas	f	f	10 years	Palau
2	Business Visas	t	f	10 years	Palau
3	Work Visas	t	f	7 years	Palau
4	Student Visas	t	f	7 years	Palau
5	Transit Visas	f	f	9 years	Palau
6	Family and Dependent Visas	t	f	10 years	Palau
7	Immigrant Visas	t	t	10 years	Palau
8	Refugee and Asylum Visas	t	f	9 years	Palau
9	Special Purpose Visas	t	f	5 years	Palau
1	Tourist Visas	f	f	8 years	Panama
2	Business Visas	t	f	6 years	Panama
3	Work Visas	t	f	7 years	Panama
4	Student Visas	t	f	7 years	Panama
5	Transit Visas	f	f	9 years	Panama
6	Family and Dependent Visas	t	f	9 years	Panama
7	Immigrant Visas	t	t	7 years	Panama
8	Refugee and Asylum Visas	t	f	9 years	Panama
9	Special Purpose Visas	t	f	5 years	Panama
1	Tourist Visas	f	f	6 years	Paraguay
2	Business Visas	t	f	7 years	Paraguay
3	Work Visas	t	f	7 years	Paraguay
4	Student Visas	t	f	9 years	Paraguay
5	Transit Visas	f	f	5 years	Paraguay
6	Family and Dependent Visas	t	f	8 years	Paraguay
7	Immigrant Visas	t	t	10 years	Paraguay
8	Refugee and Asylum Visas	t	f	8 years	Paraguay
9	Special Purpose Visas	t	f	10 years	Paraguay
1	Tourist Visas	f	f	8 years	Peru
2	Business Visas	t	f	7 years	Peru
3	Work Visas	t	f	5 years	Peru
4	Student Visas	t	f	5 years	Peru
5	Transit Visas	f	f	9 years	Peru
6	Family and Dependent Visas	t	f	9 years	Peru
7	Immigrant Visas	t	t	5 years	Peru
8	Refugee and Asylum Visas	t	f	5 years	Peru
9	Special Purpose Visas	t	f	6 years	Peru
1	Tourist Visas	f	f	7 years	Philippines
2	Business Visas	t	f	10 years	Philippines
3	Work Visas	t	f	10 years	Philippines
4	Student Visas	t	f	9 years	Philippines
5	Transit Visas	f	f	8 years	Philippines
6	Family and Dependent Visas	t	f	9 years	Philippines
7	Immigrant Visas	t	t	10 years	Philippines
8	Refugee and Asylum Visas	t	f	9 years	Philippines
9	Special Purpose Visas	t	f	5 years	Philippines
1	Tourist Visas	f	f	6 years	Pitcairn
2	Business Visas	t	f	8 years	Pitcairn
3	Work Visas	t	f	5 years	Pitcairn
4	Student Visas	t	f	6 years	Pitcairn
5	Transit Visas	f	f	5 years	Pitcairn
6	Family and Dependent Visas	t	f	5 years	Pitcairn
7	Immigrant Visas	t	t	9 years	Pitcairn
8	Refugee and Asylum Visas	t	f	7 years	Pitcairn
9	Special Purpose Visas	t	f	9 years	Pitcairn
1	Tourist Visas	f	f	8 years	Poland
2	Business Visas	t	f	9 years	Poland
3	Work Visas	t	f	5 years	Poland
4	Student Visas	t	f	7 years	Poland
5	Transit Visas	f	f	5 years	Poland
6	Family and Dependent Visas	t	f	7 years	Poland
7	Immigrant Visas	t	t	6 years	Poland
8	Refugee and Asylum Visas	t	f	6 years	Poland
9	Special Purpose Visas	t	f	8 years	Poland
1	Tourist Visas	f	f	5 years	Portugal
2	Business Visas	t	f	5 years	Portugal
3	Work Visas	t	f	6 years	Portugal
4	Student Visas	t	f	6 years	Portugal
5	Transit Visas	f	f	5 years	Portugal
6	Family and Dependent Visas	t	f	7 years	Portugal
7	Immigrant Visas	t	t	9 years	Portugal
8	Refugee and Asylum Visas	t	f	8 years	Portugal
9	Special Purpose Visas	t	f	5 years	Portugal
1	Tourist Visas	f	f	8 years	Qatar
2	Business Visas	t	f	5 years	Qatar
3	Work Visas	t	f	9 years	Qatar
4	Student Visas	t	f	7 years	Qatar
5	Transit Visas	f	f	7 years	Qatar
6	Family and Dependent Visas	t	f	5 years	Qatar
7	Immigrant Visas	t	t	8 years	Qatar
8	Refugee and Asylum Visas	t	f	8 years	Qatar
9	Special Purpose Visas	t	f	7 years	Qatar
1	Tourist Visas	f	f	10 years	Romania
2	Business Visas	t	f	8 years	Romania
3	Work Visas	t	f	5 years	Romania
4	Student Visas	t	f	9 years	Romania
5	Transit Visas	f	f	7 years	Romania
6	Family and Dependent Visas	t	f	5 years	Romania
7	Immigrant Visas	t	t	5 years	Romania
8	Refugee and Asylum Visas	t	f	10 years	Romania
9	Special Purpose Visas	t	f	6 years	Romania
1	Tourist Visas	f	f	8 years	Russia
2	Business Visas	t	f	6 years	Russia
3	Work Visas	t	f	8 years	Russia
4	Student Visas	t	f	7 years	Russia
5	Transit Visas	f	f	8 years	Russia
6	Family and Dependent Visas	t	f	10 years	Russia
7	Immigrant Visas	t	t	8 years	Russia
8	Refugee and Asylum Visas	t	f	5 years	Russia
9	Special Purpose Visas	t	f	7 years	Russia
1	Tourist Visas	f	f	8 years	Rwanda
2	Business Visas	t	f	8 years	Rwanda
3	Work Visas	t	f	9 years	Rwanda
4	Student Visas	t	f	8 years	Rwanda
5	Transit Visas	f	f	7 years	Rwanda
6	Family and Dependent Visas	t	f	8 years	Rwanda
7	Immigrant Visas	t	t	8 years	Rwanda
8	Refugee and Asylum Visas	t	f	7 years	Rwanda
9	Special Purpose Visas	t	f	9 years	Rwanda
1	Tourist Visas	f	f	10 years	Samoa
2	Business Visas	t	f	7 years	Samoa
3	Work Visas	t	f	7 years	Samoa
4	Student Visas	t	f	6 years	Samoa
5	Transit Visas	f	f	6 years	Samoa
6	Family and Dependent Visas	t	f	10 years	Samoa
7	Immigrant Visas	t	t	10 years	Samoa
8	Refugee and Asylum Visas	t	f	7 years	Samoa
9	Special Purpose Visas	t	f	9 years	Samoa
1	Tourist Visas	f	f	10 years	Senegal
2	Business Visas	t	f	9 years	Senegal
3	Work Visas	t	f	5 years	Senegal
4	Student Visas	t	f	5 years	Senegal
5	Transit Visas	f	f	9 years	Senegal
6	Family and Dependent Visas	t	f	7 years	Senegal
7	Immigrant Visas	t	t	9 years	Senegal
8	Refugee and Asylum Visas	t	f	5 years	Senegal
9	Special Purpose Visas	t	f	8 years	Senegal
1	Tourist Visas	f	f	9 years	Serbia
2	Business Visas	t	f	9 years	Serbia
3	Work Visas	t	f	8 years	Serbia
4	Student Visas	t	f	8 years	Serbia
5	Transit Visas	f	f	5 years	Serbia
6	Family and Dependent Visas	t	f	10 years	Serbia
7	Immigrant Visas	t	t	8 years	Serbia
8	Refugee and Asylum Visas	t	f	8 years	Serbia
9	Special Purpose Visas	t	f	6 years	Serbia
1	Tourist Visas	f	f	9 years	Seychelles
2	Business Visas	t	f	6 years	Seychelles
3	Work Visas	t	f	7 years	Seychelles
4	Student Visas	t	f	7 years	Seychelles
5	Transit Visas	f	f	9 years	Seychelles
6	Family and Dependent Visas	t	f	6 years	Seychelles
7	Immigrant Visas	t	t	8 years	Seychelles
8	Refugee and Asylum Visas	t	f	6 years	Seychelles
9	Special Purpose Visas	t	f	5 years	Seychelles
1	Tourist Visas	f	f	6 years	Singapore
2	Business Visas	t	f	6 years	Singapore
3	Work Visas	t	f	6 years	Singapore
4	Student Visas	t	f	7 years	Singapore
5	Transit Visas	f	f	9 years	Singapore
6	Family and Dependent Visas	t	f	6 years	Singapore
7	Immigrant Visas	t	t	10 years	Singapore
8	Refugee and Asylum Visas	t	f	9 years	Singapore
9	Special Purpose Visas	t	f	10 years	Singapore
1	Tourist Visas	f	f	10 years	Slovakia
2	Business Visas	t	f	8 years	Slovakia
3	Work Visas	t	f	9 years	Slovakia
4	Student Visas	t	f	9 years	Slovakia
5	Transit Visas	f	f	9 years	Slovakia
6	Family and Dependent Visas	t	f	5 years	Slovakia
7	Immigrant Visas	t	t	8 years	Slovakia
8	Refugee and Asylum Visas	t	f	7 years	Slovakia
9	Special Purpose Visas	t	f	9 years	Slovakia
1	Tourist Visas	f	f	8 years	Slovenia
2	Business Visas	t	f	7 years	Slovenia
3	Work Visas	t	f	7 years	Slovenia
4	Student Visas	t	f	10 years	Slovenia
5	Transit Visas	f	f	7 years	Slovenia
6	Family and Dependent Visas	t	f	9 years	Slovenia
7	Immigrant Visas	t	t	6 years	Slovenia
8	Refugee and Asylum Visas	t	f	5 years	Slovenia
9	Special Purpose Visas	t	f	6 years	Slovenia
1	Tourist Visas	f	f	10 years	Somalia
2	Business Visas	t	f	9 years	Somalia
3	Work Visas	t	f	8 years	Somalia
4	Student Visas	t	f	6 years	Somalia
5	Transit Visas	f	f	9 years	Somalia
6	Family and Dependent Visas	t	f	7 years	Somalia
7	Immigrant Visas	t	t	8 years	Somalia
8	Refugee and Asylum Visas	t	f	6 years	Somalia
9	Special Purpose Visas	t	f	7 years	Somalia
1	Tourist Visas	f	f	7 years	Spain
2	Business Visas	t	f	7 years	Spain
3	Work Visas	t	f	8 years	Spain
4	Student Visas	t	f	5 years	Spain
5	Transit Visas	f	f	7 years	Spain
6	Family and Dependent Visas	t	f	9 years	Spain
7	Immigrant Visas	t	t	7 years	Spain
8	Refugee and Asylum Visas	t	f	6 years	Spain
9	Special Purpose Visas	t	f	10 years	Spain
1	Tourist Visas	f	f	8 years	Sudan
2	Business Visas	t	f	6 years	Sudan
3	Work Visas	t	f	6 years	Sudan
4	Student Visas	t	f	8 years	Sudan
5	Transit Visas	f	f	6 years	Sudan
6	Family and Dependent Visas	t	f	8 years	Sudan
7	Immigrant Visas	t	t	8 years	Sudan
8	Refugee and Asylum Visas	t	f	6 years	Sudan
9	Special Purpose Visas	t	f	8 years	Sudan
1	Tourist Visas	f	f	7 years	Suriname
2	Business Visas	t	f	9 years	Suriname
3	Work Visas	t	f	7 years	Suriname
4	Student Visas	t	f	7 years	Suriname
5	Transit Visas	f	f	8 years	Suriname
6	Family and Dependent Visas	t	f	6 years	Suriname
7	Immigrant Visas	t	t	6 years	Suriname
8	Refugee and Asylum Visas	t	f	8 years	Suriname
9	Special Purpose Visas	t	f	9 years	Suriname
1	Tourist Visas	f	f	10 years	Swaziland
2	Business Visas	t	f	10 years	Swaziland
3	Work Visas	t	f	7 years	Swaziland
4	Student Visas	t	f	6 years	Swaziland
5	Transit Visas	f	f	5 years	Swaziland
6	Family and Dependent Visas	t	f	9 years	Swaziland
7	Immigrant Visas	t	t	10 years	Swaziland
8	Refugee and Asylum Visas	t	f	8 years	Swaziland
9	Special Purpose Visas	t	f	10 years	Swaziland
1	Tourist Visas	f	f	10 years	Sweden
2	Business Visas	t	f	6 years	Sweden
3	Work Visas	t	f	9 years	Sweden
4	Student Visas	t	f	7 years	Sweden
5	Transit Visas	f	f	9 years	Sweden
6	Family and Dependent Visas	t	f	7 years	Sweden
7	Immigrant Visas	t	t	7 years	Sweden
8	Refugee and Asylum Visas	t	f	5 years	Sweden
9	Special Purpose Visas	t	f	7 years	Sweden
1	Tourist Visas	f	f	6 years	Switzerland
2	Business Visas	t	f	5 years	Switzerland
3	Work Visas	t	f	7 years	Switzerland
4	Student Visas	t	f	10 years	Switzerland
5	Transit Visas	f	f	8 years	Switzerland
6	Family and Dependent Visas	t	f	5 years	Switzerland
7	Immigrant Visas	t	t	7 years	Switzerland
8	Refugee and Asylum Visas	t	f	9 years	Switzerland
9	Special Purpose Visas	t	f	9 years	Switzerland
1	Tourist Visas	f	f	7 years	Syria
2	Business Visas	t	f	10 years	Syria
3	Work Visas	t	f	10 years	Syria
4	Student Visas	t	f	5 years	Syria
5	Transit Visas	f	f	8 years	Syria
6	Family and Dependent Visas	t	f	10 years	Syria
7	Immigrant Visas	t	t	5 years	Syria
8	Refugee and Asylum Visas	t	f	8 years	Syria
9	Special Purpose Visas	t	f	8 years	Syria
1	Tourist Visas	f	f	9 years	Taiwan
2	Business Visas	t	f	6 years	Taiwan
3	Work Visas	t	f	9 years	Taiwan
4	Student Visas	t	f	10 years	Taiwan
5	Transit Visas	f	f	10 years	Taiwan
6	Family and Dependent Visas	t	f	7 years	Taiwan
7	Immigrant Visas	t	t	7 years	Taiwan
8	Refugee and Asylum Visas	t	f	10 years	Taiwan
9	Special Purpose Visas	t	f	10 years	Taiwan
1	Tourist Visas	f	f	9 years	Tajikistan
2	Business Visas	t	f	9 years	Tajikistan
3	Work Visas	t	f	9 years	Tajikistan
4	Student Visas	t	f	10 years	Tajikistan
5	Transit Visas	f	f	6 years	Tajikistan
6	Family and Dependent Visas	t	f	7 years	Tajikistan
7	Immigrant Visas	t	t	8 years	Tajikistan
8	Refugee and Asylum Visas	t	f	9 years	Tajikistan
9	Special Purpose Visas	t	f	10 years	Tajikistan
1	Tourist Visas	f	f	6 years	Tanzania
2	Business Visas	t	f	9 years	Tanzania
3	Work Visas	t	f	9 years	Tanzania
4	Student Visas	t	f	5 years	Tanzania
5	Transit Visas	f	f	10 years	Tanzania
6	Family and Dependent Visas	t	f	9 years	Tanzania
7	Immigrant Visas	t	t	7 years	Tanzania
8	Refugee and Asylum Visas	t	f	6 years	Tanzania
9	Special Purpose Visas	t	f	7 years	Tanzania
1	Tourist Visas	f	f	10 years	Thailand
2	Business Visas	t	f	8 years	Thailand
3	Work Visas	t	f	7 years	Thailand
4	Student Visas	t	f	8 years	Thailand
5	Transit Visas	f	f	5 years	Thailand
6	Family and Dependent Visas	t	f	9 years	Thailand
7	Immigrant Visas	t	t	9 years	Thailand
8	Refugee and Asylum Visas	t	f	10 years	Thailand
9	Special Purpose Visas	t	f	10 years	Thailand
1	Tourist Visas	f	f	6 years	Togo
2	Business Visas	t	f	8 years	Togo
3	Work Visas	t	f	8 years	Togo
4	Student Visas	t	f	7 years	Togo
5	Transit Visas	f	f	10 years	Togo
6	Family and Dependent Visas	t	f	5 years	Togo
7	Immigrant Visas	t	t	8 years	Togo
8	Refugee and Asylum Visas	t	f	5 years	Togo
9	Special Purpose Visas	t	f	5 years	Togo
1	Tourist Visas	f	f	5 years	Tunisia
2	Business Visas	t	f	5 years	Tunisia
3	Work Visas	t	f	10 years	Tunisia
4	Student Visas	t	f	7 years	Tunisia
5	Transit Visas	f	f	10 years	Tunisia
6	Family and Dependent Visas	t	f	9 years	Tunisia
7	Immigrant Visas	t	t	7 years	Tunisia
8	Refugee and Asylum Visas	t	f	7 years	Tunisia
9	Special Purpose Visas	t	f	8 years	Tunisia
1	Tourist Visas	f	f	7 years	Turkey
2	Business Visas	t	f	5 years	Turkey
3	Work Visas	t	f	5 years	Turkey
4	Student Visas	t	f	9 years	Turkey
5	Transit Visas	f	f	5 years	Turkey
6	Family and Dependent Visas	t	f	6 years	Turkey
7	Immigrant Visas	t	t	8 years	Turkey
8	Refugee and Asylum Visas	t	f	10 years	Turkey
9	Special Purpose Visas	t	f	10 years	Turkey
1	Tourist Visas	f	f	8 years	Turkmenistan
2	Business Visas	t	f	10 years	Turkmenistan
3	Work Visas	t	f	8 years	Turkmenistan
4	Student Visas	t	f	8 years	Turkmenistan
5	Transit Visas	f	f	7 years	Turkmenistan
6	Family and Dependent Visas	t	f	5 years	Turkmenistan
7	Immigrant Visas	t	t	8 years	Turkmenistan
8	Refugee and Asylum Visas	t	f	7 years	Turkmenistan
9	Special Purpose Visas	t	f	5 years	Turkmenistan
1	Tourist Visas	f	f	7 years	Tuvalu
2	Business Visas	t	f	8 years	Tuvalu
3	Work Visas	t	f	8 years	Tuvalu
4	Student Visas	t	f	9 years	Tuvalu
5	Transit Visas	f	f	6 years	Tuvalu
6	Family and Dependent Visas	t	f	7 years	Tuvalu
7	Immigrant Visas	t	t	10 years	Tuvalu
8	Refugee and Asylum Visas	t	f	10 years	Tuvalu
9	Special Purpose Visas	t	f	6 years	Tuvalu
1	Tourist Visas	f	f	9 years	Uganda
2	Business Visas	t	f	6 years	Uganda
3	Work Visas	t	f	5 years	Uganda
4	Student Visas	t	f	8 years	Uganda
5	Transit Visas	f	f	6 years	Uganda
6	Family and Dependent Visas	t	f	8 years	Uganda
7	Immigrant Visas	t	t	7 years	Uganda
8	Refugee and Asylum Visas	t	f	6 years	Uganda
9	Special Purpose Visas	t	f	10 years	Uganda
1	Tourist Visas	f	f	5 years	Ukraine
2	Business Visas	t	f	8 years	Ukraine
3	Work Visas	t	f	9 years	Ukraine
4	Student Visas	t	f	7 years	Ukraine
5	Transit Visas	f	f	8 years	Ukraine
6	Family and Dependent Visas	t	f	7 years	Ukraine
7	Immigrant Visas	t	t	9 years	Ukraine
8	Refugee and Asylum Visas	t	f	5 years	Ukraine
9	Special Purpose Visas	t	f	8 years	Ukraine
1	Tourist Visas	f	f	9 years	Uruguay
2	Business Visas	t	f	8 years	Uruguay
3	Work Visas	t	f	6 years	Uruguay
4	Student Visas	t	f	10 years	Uruguay
5	Transit Visas	f	f	7 years	Uruguay
6	Family and Dependent Visas	t	f	10 years	Uruguay
7	Immigrant Visas	t	t	9 years	Uruguay
8	Refugee and Asylum Visas	t	f	6 years	Uruguay
9	Special Purpose Visas	t	f	7 years	Uruguay
1	Tourist Visas	f	f	6 years	Uzbekistan
2	Business Visas	t	f	9 years	Uzbekistan
3	Work Visas	t	f	5 years	Uzbekistan
4	Student Visas	t	f	9 years	Uzbekistan
5	Transit Visas	f	f	5 years	Uzbekistan
6	Family and Dependent Visas	t	f	7 years	Uzbekistan
7	Immigrant Visas	t	t	8 years	Uzbekistan
8	Refugee and Asylum Visas	t	f	9 years	Uzbekistan
9	Special Purpose Visas	t	f	7 years	Uzbekistan
1	Tourist Visas	f	f	7 years	Venezuela
2	Business Visas	t	f	6 years	Venezuela
3	Work Visas	t	f	10 years	Venezuela
4	Student Visas	t	f	7 years	Venezuela
5	Transit Visas	f	f	5 years	Venezuela
6	Family and Dependent Visas	t	f	10 years	Venezuela
7	Immigrant Visas	t	t	5 years	Venezuela
8	Refugee and Asylum Visas	t	f	6 years	Venezuela
9	Special Purpose Visas	t	f	7 years	Venezuela
1	Tourist Visas	f	f	9 years	Vietnam
2	Business Visas	t	f	9 years	Vietnam
3	Work Visas	t	f	9 years	Vietnam
4	Student Visas	t	f	6 years	Vietnam
5	Transit Visas	f	f	10 years	Vietnam
6	Family and Dependent Visas	t	f	5 years	Vietnam
7	Immigrant Visas	t	t	7 years	Vietnam
8	Refugee and Asylum Visas	t	f	7 years	Vietnam
9	Special Purpose Visas	t	f	9 years	Vietnam
1	Tourist Visas	f	f	9 years	Yemen
2	Business Visas	t	f	5 years	Yemen
3	Work Visas	t	f	6 years	Yemen
4	Student Visas	t	f	6 years	Yemen
5	Transit Visas	f	f	8 years	Yemen
6	Family and Dependent Visas	t	f	6 years	Yemen
7	Immigrant Visas	t	t	7 years	Yemen
8	Refugee and Asylum Visas	t	f	7 years	Yemen
9	Special Purpose Visas	t	f	8 years	Yemen
1	Tourist Visas	f	f	8 years	Zambia
2	Business Visas	t	f	5 years	Zambia
3	Work Visas	t	f	5 years	Zambia
4	Student Visas	t	f	7 years	Zambia
5	Transit Visas	f	f	7 years	Zambia
6	Family and Dependent Visas	t	f	5 years	Zambia
7	Immigrant Visas	t	t	5 years	Zambia
8	Refugee and Asylum Visas	t	f	9 years	Zambia
9	Special Purpose Visas	t	f	8 years	Zambia
1	Tourist Visas	f	f	8 years	Zimbabwe
2	Business Visas	t	f	10 years	Zimbabwe
3	Work Visas	t	f	10 years	Zimbabwe
4	Student Visas	t	f	6 years	Zimbabwe
5	Transit Visas	f	f	6 years	Zimbabwe
6	Family and Dependent Visas	t	f	8 years	Zimbabwe
7	Immigrant Visas	t	t	8 years	Zimbabwe
8	Refugee and Asylum Visas	t	f	8 years	Zimbabwe
9	Special Purpose Visas	t	f	7 years	Zimbabwe
1	Tourist Visas	f	f	8 years	USA
2	Business Visas	t	f	10 years	USA
3	Work Visas	t	f	5 years	USA
4	Student Visas	t	f	10 years	USA
5	Transit Visas	f	f	7 years	USA
6	Family and Dependent Visas	t	f	8 years	USA
7	Immigrant Visas	t	t	6 years	USA
8	Refugee and Asylum Visas	t	f	8 years	USA
9	Special Purpose Visas	t	f	7 years	USA
\.


--
-- Data for Name: visas; Type: TABLE DATA; Schema: public; Owner: admin
--

COPY public.visas (id, type, passport, issue_date, inner_issuer, country) FROM stdin;
1	8	1	2042-04-19	22	Iran
2	9	2	2018-11-24	591	Palau
3	5	3	2014-05-04	17	Macao
4	5	4	1992-12-24	585	Denmark
5	3	5	1990-11-04	637	Liberia
6	5	6	1991-02-13	438	Kiribati
7	5	7	1993-01-10	1191	Honduras
8	8	8	1966-04-27	26	Kiribati
9	2	9	1964-05-05	544	Finland
10	5	10	1963-06-26	854	Chile
11	8	11	1967-02-25	399	Gambia
12	7	12	1967-05-22	32	Syria
13	3	13	1963-08-01	278	Montserrat
14	7	14	1967-01-06	265	Angola
15	4	15	1963-05-01	539	Nauru
16	9	16	1944-06-14	953	Azerbaijan
17	5	17	1939-06-09	132	Laos
18	9	18	1939-03-14	437	Hungary
19	8	19	1942-08-12	731	Kenya
20	5	20	1943-04-09	498	Mexico
21	9	21	1941-10-07	96	Laos
22	7	22	1941-08-09	977	Gabon
23	2	23	1942-11-14	438	Kyrgyzstan
24	9	24	1941-05-02	1025	Turkey
25	8	25	1940-04-11	268	Latvia
26	8	26	1937-05-19	88	Israel
27	9	27	1938-05-25	635	Haiti
28	1	28	1939-09-24	577	Albania
29	1	29	1942-03-23	731	Ireland
30	7	30	1937-12-10	1091	Poland
31	3	31	1940-08-04	39	Bermuda
32	3	32	1920-07-02	131	Sudan
33	2	33	1915-01-10	497	Singapore
34	2	34	1913-08-23	521	Romania
35	2	35	1917-06-17	250	Austria
36	2	36	1916-06-18	905	Gabon
37	4	37	1914-03-28	1214	Pitcairn
38	4	38	1917-01-18	222	Comoros
39	8	39	1915-03-21	29	Philippines
40	5	40	1916-08-05	698	Austria
41	3	41	1916-02-18	652	Nicaragua
42	8	42	1918-06-15	677	Zambia
43	3	43	1918-08-18	1106	Montserrat
44	2	44	1919-02-11	862	Oman
45	4	45	1920-03-10	1109	Somalia
46	4	46	1918-03-09	887	Belize
47	7	47	1913-03-27	798	Libya
48	7	48	1917-08-18	130	Maldives
49	3	49	1915-07-05	880	Mali
50	2	50	1912-02-06	1172	Brazil
51	3	51	1918-06-04	381	Syria
52	6	52	1918-06-27	49	Jamaica
53	7	53	1919-04-07	549	Macedonia
54	7	54	1913-04-26	719	Kiribati
55	8	55	1918-02-02	1107	Moldova
56	9	56	1913-03-27	496	Monaco
57	7	57	1914-02-18	989	Gambia
58	7	58	1917-02-11	338	Montserrat
59	2	59	1919-12-17	132	Nauru
60	1	60	1917-07-02	185	Georgia
61	1	61	1918-06-05	54	Cameroon
62	1	62	1919-12-18	520	Cambodia
63	2	63	1913-07-01	469	Iraq
64	1	64	1890-05-05	470	Angola
65	9	65	1889-07-01	1071	Serbia
66	4	66	1891-05-18	1196	Oman
67	6	67	1892-07-21	520	Austria
68	3	68	1889-10-03	964	Liberia
69	6	69	1894-02-08	1154	Cambodia
70	2	70	1892-10-07	101	Dominica
71	3	71	1889-06-06	862	Morocco
72	1	72	1887-09-05	482	Bangladesh
73	7	73	1893-03-13	244	Croatia
74	1	74	1894-03-28	1049	Uganda
75	8	75	1887-01-08	668	Greenland
76	8	76	1888-08-27	1213	Canada
77	1	77	1888-05-17	790	Tuvalu
78	8	78	1890-02-20	840	Mauritania
79	4	79	1895-12-28	332	Algeria
80	8	80	1895-11-01	367	Mexico
81	8	81	1888-11-17	558	Eritrea
82	2	82	1891-07-09	627	Netherlands
83	2	83	1889-02-15	1083	Kyrgyzstan
84	6	84	1893-09-24	446	Cyprus
85	3	85	1889-03-12	442	Martinique
86	9	86	1891-04-20	1035	Martinique
87	5	87	1892-06-18	443	Djibouti
88	5	88	1891-02-03	989	Bahrain
89	5	89	1892-08-04	216	Lebanon
90	5	90	1891-04-16	823	Switzerland
91	7	91	1891-03-15	1027	Portugal
92	5	92	1891-06-02	261	Finland
93	8	93	1889-06-01	982	Botswana
94	8	94	1892-01-16	738	Macedonia
95	9	95	1894-10-16	404	Colombia
96	3	96	1890-07-21	180	Somalia
97	1	97	1889-02-27	396	Venezuela
98	1	98	1891-11-04	1160	Norway
99	6	99	1894-12-03	780	Bolivia
100	1	100	1887-03-24	1171	Gibraltar
101	9	101	1892-07-23	482	Sweden
102	6	102	1889-07-02	1041	France
103	2	103	1894-09-11	879	Sweden
104	2	104	1888-04-27	43	Botswana
105	5	105	1891-04-14	56	Hungary
106	6	106	1894-05-09	845	Yemen
107	2	107	1889-12-23	1023	Portugal
108	6	108	1895-03-19	900	Brazil
109	4	109	1887-09-02	1066	Niger
110	9	110	1892-08-15	203	Maldives
111	7	111	1892-02-11	559	Slovakia
112	5	112	1889-04-10	1012	Venezuela
113	3	113	1888-08-11	396	Mauritius
114	2	114	1894-02-14	777	Oman
115	8	115	1888-04-16	518	Maldives
116	5	116	1893-05-14	1213	Pakistan
117	5	117	1893-03-21	585	Panama
118	5	118	1892-03-11	669	Barbados
119	2	119	1893-11-19	1236	Chile
120	8	120	1891-05-05	735	Madagascar
121	4	121	1890-05-25	745	Bangladesh
122	9	122	1892-04-26	349	Maldives
123	8	123	1894-05-26	113	Dominica
124	9	124	1890-12-17	92	China
125	1	125	1889-12-08	364	Uzbekistan
126	2	126	1892-06-01	224	Guinea
127	8	127	1889-12-09	931	Aruba
128	3	128	1869-04-02	505	Ethiopia
129	9	129	1862-07-21	421	Syria
130	4	130	1867-07-09	157	Albania
131	9	131	1869-04-05	400	Jamaica
132	2	132	1863-12-26	453	Brazil
133	7	133	1866-05-22	813	Guatemala
134	5	134	1868-05-01	306	Djibouti
135	9	135	1862-07-21	396	Yemen
136	9	136	1867-02-26	103	Yemen
137	6	137	1868-04-10	1094	Tajikistan
138	2	138	1866-02-08	680	Italy
139	8	139	1862-05-27	790	Sudan
140	8	140	1868-06-27	765	Benin
141	3	141	1869-03-12	745	Ghana
142	9	142	1863-12-10	972	Tanzania
143	4	143	1870-11-24	561	India
144	3	144	1865-04-05	440	Egypt
145	9	145	1865-10-24	193	Niger
146	6	146	1864-02-19	1138	Bulgaria
147	2	147	1864-09-08	271	Laos
148	6	148	1868-06-07	820	Haiti
149	5	149	1868-12-07	875	Paraguay
150	6	150	1863-08-25	461	Latvia
151	9	151	1868-08-22	129	Bahrain
152	4	152	1867-11-11	1056	Gabon
153	3	153	1865-03-01	636	Mauritius
154	2	154	1869-07-11	50	Sudan
155	3	155	1867-09-11	8	Samoa
156	2	156	1865-01-06	509	Malaysia
157	2	157	1864-09-11	144	Curacao
158	8	158	1868-10-21	147	Macao
159	5	159	1863-02-10	1061	Kiribati
160	6	160	1868-02-18	780	Lebanon
161	4	161	1870-08-12	1238	Tunisia
162	1	162	1864-10-16	204	Gibraltar
163	9	163	1868-12-01	337	Cyprus
164	7	164	1864-01-13	1094	Poland
165	3	165	1862-02-18	281	Kyrgyzstan
166	2	166	1868-10-07	1110	Bermuda
167	5	167	1868-03-28	323	Turkey
168	2	168	1863-11-08	243	Mexico
169	2	169	1869-04-14	387	Bahamas
170	7	170	1867-04-18	90	Barbados
171	3	171	1866-05-19	451	Guatemala
172	1	172	1868-03-08	1112	Namibia
173	6	173	1864-02-23	322	Germany
174	9	174	1867-10-06	303	Martinique
175	5	175	1863-09-06	559	Botswana
176	4	176	1862-07-18	570	Liechtenstein
177	9	177	1863-08-15	291	Kiribati
178	6	178	1868-03-26	1155	Jamaica
179	3	179	1864-07-18	1152	Malta
180	8	180	1863-03-24	977	Bhutan
181	2	181	1867-07-04	1114	Denmark
182	4	182	1864-09-21	144	Mali
183	7	183	1867-07-13	900	Nauru
184	7	184	1864-01-09	767	Macao
185	6	185	1870-02-10	451	Jamaica
186	7	186	1867-12-24	1082	Tajikistan
187	2	187	1868-03-20	18	Slovenia
188	7	188	1864-02-08	1134	Guyana
189	1	189	1864-02-16	398	Martinique
190	5	190	1864-01-20	1098	Laos
191	6	191	1869-02-03	571	Italy
192	4	192	1866-03-28	480	Ethiopia
193	4	193	1868-11-12	813	Libya
194	4	194	1867-07-11	1107	Portugal
195	4	195	1868-03-16	290	Madagascar
196	8	196	1869-01-11	728	Ecuador
197	9	197	1865-01-05	750	Zambia
198	2	198	1863-05-12	336	Guinea
199	3	199	1863-10-13	902	Mozambique
200	3	200	1867-04-28	1191	Bahrain
201	3	201	1868-07-13	964	Slovenia
202	3	202	1866-01-13	956	Burundi
203	4	203	1869-07-27	400	Guatemala
204	7	204	1865-01-12	969	Barbados
205	1	205	1865-05-17	94	Brunei
206	9	206	1865-02-25	767	Bolivia
207	2	207	1865-11-27	244	Cuba
208	2	208	1866-01-19	562	Comoros
209	7	209	1869-09-20	973	Somalia
210	7	210	1864-09-27	920	Ethiopia
211	3	211	1868-12-16	913	Italy
212	3	212	1867-12-14	473	Finland
213	1	213	1868-01-04	1121	Turkmenistan
214	3	214	1868-04-16	1233	Cameroon
215	4	215	1870-06-26	1048	Malaysia
216	2	216	1868-01-10	662	Afghanistan
217	3	217	1865-02-23	222	Liberia
218	8	218	1868-05-16	99	Senegal
219	2	219	1868-03-11	1210	Paraguay
220	3	220	1862-06-07	465	Malaysia
221	4	221	1867-11-08	310	Ukraine
222	5	222	1867-07-16	418	Suriname
223	8	223	1868-12-12	883	Iceland
224	4	224	1866-04-16	398	Slovenia
225	6	225	1865-10-09	555	Ukraine
226	7	226	1863-07-11	1010	Lebanon
227	7	227	1865-11-14	1089	Gambia
228	6	228	1867-09-05	849	Bangladesh
229	2	229	1865-03-16	12	Nauru
230	7	230	1867-04-18	735	Ghana
231	3	231	1865-12-11	532	Swaziland
232	6	232	1867-03-10	1000	Turkmenistan
233	1	233	1868-10-21	588	Monaco
234	4	234	1867-02-27	806	Togo
235	8	235	1867-01-23	178	Latvia
236	3	236	1864-08-25	735	Germany
237	8	237	1862-07-27	686	Cameroon
238	6	238	1864-06-02	875	Tanzania
239	4	239	1864-05-23	1059	Algeria
240	4	240	1866-12-06	679	Maldives
241	8	241	1865-06-25	377	Fiji
242	6	242	1866-12-11	917	Brunei
243	5	243	1863-05-03	549	Italy
244	2	244	1865-10-08	980	France
245	1	245	1864-09-11	238	Cameroon
246	8	246	1864-08-24	1165	Uruguay
247	5	247	1869-08-15	201	Portugal
248	1	248	1864-06-16	313	Mauritius
249	5	249	1868-04-11	560	Maldives
250	2	250	1867-12-27	37	Djibouti
251	8	251	1868-12-23	791	Tuvalu
252	6	252	1864-10-23	161	Afghanistan
253	2	253	1863-09-27	803	Brazil
254	8	254	1869-03-22	1085	Argentina
255	5	255	1868-09-11	972	Slovenia
256	9	256	1840-05-02	136	Iran
257	3	257	1843-02-03	1155	Liechtenstein
258	8	258	1845-12-03	697	Lesotho
259	1	259	1839-02-26	539	Kenya
260	1	260	1838-10-25	49	Cuba
261	8	261	1838-09-11	546	Aruba
262	7	262	1838-05-04	223	Cambodia
263	3	263	1837-09-02	880	Madagascar
264	6	264	1837-12-24	359	Taiwan
265	7	265	1842-01-20	719	Malta
266	4	266	1842-02-19	367	Maldives
267	7	267	1842-11-22	21	Curacao
268	9	268	1843-01-21	933	Gibraltar
269	5	269	1838-05-01	1089	Iceland
270	1	270	1840-12-10	636	Seychelles
271	7	271	1841-12-12	494	Chile
272	6	272	1840-11-24	973	Azerbaijan
273	6	273	1842-05-13	132	Macao
274	7	274	1844-12-19	1106	Liechtenstein
275	8	275	1840-12-11	299	Cameroon
276	8	276	1839-01-28	561	Thailand
277	3	277	1839-10-09	570	Colombia
278	7	278	1844-01-10	1187	Aruba
279	3	279	1838-08-05	423	Tajikistan
280	1	280	1839-06-25	472	Algeria
281	2	281	1840-03-01	735	Kyrgyzstan
282	8	282	1841-02-10	1089	Turkey
283	9	283	1842-03-23	722	Nicaragua
284	8	284	1840-10-03	570	Moldova
285	5	285	1838-11-05	850	Uruguay
286	8	286	1838-05-20	387	Togo
287	8	287	1840-11-19	855	Oman
288	8	288	1843-11-26	433	Argentina
289	9	289	1842-01-15	346	Denmark
290	6	290	1842-11-10	281	Dominica
291	9	291	1841-02-23	1211	Mayotte
292	3	292	1840-03-06	1206	Rwanda
293	8	293	1841-10-17	1158	Algeria
294	3	294	1839-05-23	207	Bolivia
295	4	295	1839-02-15	118	Russia
296	6	296	1840-12-14	130	Uganda
297	1	297	1845-04-15	676	Bhutan
298	4	298	1844-08-11	17	Lebanon
299	1	299	1838-06-26	851	Martinique
300	7	300	1839-05-14	973	Armenia
301	4	301	1844-01-20	145	Nicaragua
302	3	302	1843-04-14	45	Australia
303	1	303	1844-01-21	1061	Colombia
304	1	304	1840-11-22	804	Kiribati
305	6	305	1840-06-12	974	Bulgaria
306	1	306	1841-07-15	215	Mali
307	8	307	1843-01-13	782	Italy
308	3	308	1845-01-08	829	Laos
309	1	309	1843-12-05	1250	Brunei
310	1	310	1842-06-01	1214	Morocco
311	5	311	1839-10-03	1023	Sweden
312	6	312	1838-04-03	198	Ghana
313	8	313	1840-09-22	499	Macedonia
314	7	314	1840-04-06	556	Tanzania
315	9	315	1844-10-10	1160	Malawi
316	3	316	1842-09-20	1086	Chile
317	2	317	1839-05-17	792	Seychelles
318	4	318	1840-12-24	1112	Sweden
319	4	319	1843-12-23	684	Bolivia
320	3	320	1842-08-23	57	Indonesia
321	4	321	1840-02-13	752	Benin
322	6	322	1841-05-21	386	Sudan
323	1	323	1842-05-12	520	Slovakia
324	9	324	1839-09-25	711	Indonesia
325	1	325	1841-05-06	573	Croatia
326	3	326	1839-02-06	800	Jordan
327	8	327	1841-07-09	704	Uganda
328	3	328	1840-07-04	418	Cameroon
329	4	329	1843-05-20	211	Liberia
330	8	330	1840-10-15	840	Haiti
331	8	331	1843-01-11	459	Liberia
332	4	332	1842-05-01	428	Benin
333	3	333	1842-08-11	221	Venezuela
334	4	334	1838-01-19	573	Thailand
335	7	335	1838-02-24	468	Swaziland
336	8	336	1838-06-04	1206	USA
337	8	337	1843-09-10	748	Bahrain
338	9	338	1844-12-01	5	Argentina
339	5	339	1839-11-25	974	Slovakia
340	5	340	1840-06-06	778	Kazakhstan
341	2	341	1844-02-27	959	Barbados
342	3	342	1840-10-18	46	Bermuda
343	6	343	1845-10-10	175	Uruguay
344	6	344	1840-03-21	1193	Senegal
345	7	345	1843-10-12	592	Pitcairn
346	7	346	1842-11-07	845	Hungary
347	3	347	1842-03-18	1181	Uganda
348	5	348	1839-05-23	47	Honduras
349	1	349	1840-06-25	869	Egypt
350	1	350	1837-04-05	530	Austria
351	9	351	1837-11-05	56	Philippines
352	3	352	1838-12-10	45	Montenegro
353	4	353	1843-11-27	388	Mauritius
354	6	354	1843-10-10	832	Latvia
355	1	355	1842-06-22	667	Uzbekistan
356	4	356	1843-11-20	206	Senegal
357	3	357	1841-04-06	196	Bahamas
358	1	358	1842-03-03	13	Lebanon
359	3	359	1843-07-01	639	Myanmar
360	9	360	1843-09-08	783	Niue
361	5	361	1841-04-10	480	Poland
362	2	362	1842-09-16	780	Austria
363	3	363	1840-01-25	335	Morocco
364	7	364	1839-12-23	575	Mozambique
365	5	365	1840-01-23	446	Egypt
366	4	366	1842-12-05	590	Luxembourg
367	6	367	1841-04-28	649	Yemen
368	7	368	1838-11-23	633	Nauru
369	8	369	1841-08-06	734	Pitcairn
370	3	370	1839-11-02	540	Niger
371	3	371	1841-06-03	627	Lithuania
372	3	372	1838-02-20	713	Germany
373	2	373	1840-06-10	525	Martinique
374	3	374	1844-02-06	129	Namibia
375	5	375	1845-12-24	26	Iceland
376	7	376	1841-08-17	803	Botswana
377	4	377	1845-09-02	1185	Honduras
378	1	378	1845-10-18	1207	Kenya
379	5	379	1841-06-28	902	Macedonia
380	8	380	1838-05-02	1250	Armenia
381	2	381	1838-11-27	410	Iran
382	2	382	1841-12-15	476	Sudan
383	4	383	1838-07-17	727	Nicaragua
384	1	384	1838-09-11	582	Denmark
385	9	385	1843-05-28	734	Estonia
386	7	386	1840-05-08	276	Germany
387	8	387	1838-01-15	1106	Peru
388	1	388	1843-09-20	837	Haiti
389	5	389	1845-06-27	335	Azerbaijan
390	7	390	1840-07-07	1109	Djibouti
391	7	391	1838-09-04	786	Egypt
392	8	392	1840-10-13	168	Gibraltar
393	3	393	1838-06-17	736	Japan
394	1	394	1839-06-06	45	Iceland
395	6	395	1839-04-09	956	Panama
396	3	396	1839-05-08	855	Poland
397	2	397	1841-08-18	899	Lebanon
398	7	398	1839-03-05	573	Poland
399	9	399	1841-06-19	384	Suriname
400	7	400	1838-10-18	833	Bahamas
401	3	401	1839-12-26	657	Cameroon
402	9	402	1841-06-27	135	Comoros
403	5	403	1842-06-06	614	Chile
404	5	404	1838-01-05	120	Chad
405	8	405	1845-05-11	805	Maldives
406	1	406	1845-01-02	46	Laos
407	2	407	1842-01-06	920	Seychelles
408	8	408	1841-11-21	37	Guyana
409	9	409	1838-05-17	479	Nigeria
410	8	410	1842-04-04	1157	Slovakia
411	3	411	1844-06-04	537	Cyprus
412	9	412	1841-04-10	48	Macao
413	2	413	1843-03-08	238	Malaysia
414	5	414	1839-10-07	656	Liechtenstein
415	3	415	1839-12-06	106	Mauritius
416	8	416	1842-02-18	229	Samoa
417	6	417	1839-10-16	466	Kosovo
418	6	418	1841-03-11	870	Rwanda
419	9	419	1843-09-14	61	Libya
420	5	420	1840-10-13	152	Niger
421	5	421	1843-07-07	588	Guatemala
422	2	422	1843-02-21	80	Liechtenstein
423	8	423	1845-05-16	779	Colombia
424	1	424	1842-11-03	730	Ecuador
425	3	425	1841-07-09	36	Moldova
426	7	426	1837-05-25	1059	Colombia
427	3	427	1840-03-03	58	Mexico
428	8	428	1837-04-05	863	Taiwan
429	7	429	1839-03-27	614	Bangladesh
430	4	430	1837-08-11	469	Venezuela
431	6	431	1840-01-12	1059	Cambodia
432	9	432	1841-04-20	631	Niue
433	1	433	1838-02-16	234	Netherlands
434	1	434	1844-01-15	5	Ecuador
435	7	435	1839-05-06	557	Chile
436	3	436	1839-06-23	632	Niger
437	3	437	1843-12-17	136	Uganda
438	5	438	1837-11-28	730	Peru
439	8	439	1844-11-13	776	Mozambique
440	2	440	1839-07-09	1185	Montserrat
441	5	441	1840-10-10	570	Belarus
442	8	442	1842-03-14	629	Ethiopia
443	1	443	1841-08-01	835	Australia
444	7	444	1843-05-07	12	Colombia
445	2	445	1841-02-25	969	Niger
446	1	446	1840-07-20	635	Greenland
447	2	447	1840-07-27	1132	Singapore
448	1	448	1839-04-11	472	Sweden
449	2	449	1837-05-17	413	Mayotte
450	3	450	1842-03-21	96	Bahamas
451	6	451	1838-12-27	560	Honduras
452	9	452	1845-03-22	1110	Maldives
453	6	453	1842-02-27	287	Mexico
454	1	454	1843-02-02	148	Belize
455	2	455	1843-04-08	194	Germany
456	1	456	1838-08-19	872	Venezuela
457	2	457	1839-07-12	136	Chad
458	6	458	1840-01-11	479	Canada
459	8	459	1841-08-10	856	Finland
460	2	460	1844-09-22	516	Nauru
461	6	461	1839-11-04	736	Fiji
462	6	462	1844-10-09	296	Panama
463	9	463	1845-04-20	940	Tunisia
464	2	464	1837-04-07	287	Colombia
465	2	465	1843-04-02	881	Kiribati
466	3	466	1838-12-18	1008	Angola
467	1	467	1844-08-14	859	Portugal
468	2	468	1841-12-06	480	Bulgaria
469	1	469	1839-07-20	856	Martinique
470	4	470	1837-05-23	568	Gambia
471	5	471	1840-12-19	208	Gibraltar
472	6	472	1840-07-12	129	Spain
473	8	473	1840-10-11	494	Samoa
474	8	474	1842-10-11	94	Colombia
475	9	475	1837-05-27	97	Tanzania
476	2	476	1844-09-02	61	Liechtenstein
477	1	477	1842-04-20	212	Philippines
478	3	478	1842-09-22	1083	Montserrat
479	8	479	1840-07-23	141	Liechtenstein
480	6	480	1839-03-21	345	Peru
481	2	481	1841-04-05	168	Fiji
482	6	482	1840-04-19	92	Ghana
483	9	483	1844-07-16	521	Russia
484	2	484	1844-12-25	546	Jordan
485	6	485	1843-06-01	413	Thailand
486	3	486	1844-03-19	486	Mexico
487	1	487	1844-10-24	341	Palau
488	5	488	1843-11-27	1089	Ethiopia
489	5	489	1838-01-16	26	Qatar
490	3	490	1843-02-14	36	Afghanistan
491	7	491	1844-08-23	1190	Malaysia
492	1	492	1838-09-06	446	Belize
493	4	493	1841-08-09	1099	Algeria
494	8	494	1845-05-26	466	Bermuda
495	8	495	1845-12-25	920	USA
496	9	496	1841-09-05	280	Djibouti
497	4	497	1839-09-17	599	Tajikistan
498	2	498	1843-08-07	121	Chad
499	1	499	1842-03-24	485	Niue
500	3	500	1840-02-22	210	USA
\.


--
-- Name: educational_certificates_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.educational_certificates_types_id_seq', 1, false);


--
-- Name: people_id_seq; Type: SEQUENCE SET; Schema: public; Owner: admin
--

SELECT pg_catalog.setval('public.people_id_seq', 1, false);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (id);


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
-- Name: birth_certificates verify_birth_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_birth_certificate_issuer BEFORE INSERT ON public.birth_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_birth_certificate_issuer();


--
-- Name: death_certificates verify_death_certificate_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_death_certificate_issuer BEFORE INSERT ON public.death_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_death_certificate_issuer();


--
-- Name: divorce_certificates verify_divorce_certificate_date; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_divorce_certificate_date BEFORE INSERT ON public.divorce_certificates FOR EACH ROW EXECUTE FUNCTION public.verify_divorce_certificate_date();


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
-- Name: passports verify_passport_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_issuer BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_issuer();


--
-- Name: passports verify_passport_number; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_passport_number BEFORE INSERT ON public.passports FOR EACH ROW EXECUTE FUNCTION public.verify_passport_number();


--
-- Name: visas verify_visa_issuer; Type: TRIGGER; Schema: public; Owner: admin
--

CREATE TRIGGER verify_visa_issuer BEFORE INSERT ON public.visas FOR EACH ROW EXECUTE FUNCTION public.verify_visa_issuer();


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
-- Name: educational_certificates fk_educational_certificates_educational_certificates_types; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.educational_certificates
    ADD CONSTRAINT fk_educational_certificates_educational_certificates_types FOREIGN KEY (kind) REFERENCES public.educational_certificates_types(id);


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
-- Name: pet_passports fk_pet_passports_offices; Type: FK CONSTRAINT; Schema: public; Owner: admin
--

ALTER TABLE ONLY public.pet_passports
    ADD CONSTRAINT fk_pet_passports_offices FOREIGN KEY (issuer) REFERENCES public.offices(id);


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
