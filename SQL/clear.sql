-- \c id-documents;

BEGIN;

DROP TABLE IF EXISTS countries CASCADE;
DROP TABLE IF EXISTS cities CASCADE;
DROP TABLE IF EXISTS driving_schools CASCADE;
DROP TABLE IF EXISTS educational_certificetes_types CASCADE;
DROP TABLE IF EXISTS educational_instances_types CASCADE;
DROP TABLE IF EXISTS offices_kinds CASCADE;
DROP TABLE IF EXISTS passport_offices CASCADE;
DROP TABLE IF EXISTS people CASCADE;
DROP TABLE IF EXISTS pet_passports CASCADE;
DROP TABLE IF EXISTS visa_categories CASCADE;
DROP TABLE IF EXISTS birth_certificates CASCADE;
DROP TABLE IF EXISTS death_certificates CASCADE;
DROP TABLE IF EXISTS drivers_licences CASCADE;
DROP TABLE IF EXISTS educational_instances CASCADE;
DROP TABLE IF EXISTS educational_certificates CASCADE;
DROP TABLE IF EXISTS international_passports CASCADE;
DROP TABLE IF EXISTS marriages CASCADE;
DROP TABLE IF EXISTS offices_kinds_relations CASCADE;
DROP TABLE IF EXISTS passports CASCADE;
DROP TABLE IF EXISTS visas CASCADE;
DROP TABLE IF EXISTS divorces CASCADE;
DROP TABLE IF EXISTS marriage_certificates CASCADE;
DROP TABLE IF EXISTS divorce_certificates CASCADE;
DROP TABLE IF EXISTS offices CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS administrators CASCADE;
DROP TABLE IF EXISTS educational_certificates_types CASCADE;
DROP TABLE IF EXISTS educational_instances_types_relation CASCADE;
DROP TABLE IF EXISTS office_kinds_documents CASCADE;
DROP TABLE IF EXISTS document_types CASCADE;

DROP FUNCTION IF EXISTS add_user(bigint,VARCHAR,VARCHAR);
DROP FUNCTION IF EXISTS login;
DROP FUNCTION IF EXISTS get_administrated_offices;
DROP FUNCTION IF EXISTS verify_divorce_unique;
DROP FUNCTION IF EXISTS verify_marriage_unique;
DROP FUNCTION IF EXISTS verify_divorce_date;
DROP FUNCTION IF EXISTS verify_marriage_certificate_date;
DROP FUNCTION IF EXISTS verify_divorce_certificate_date;
DROP FUNCTION IF EXISTS verify_educational_certificate_date;
DROP FUNCTION IF EXISTS verify_educational_instance_date;
DROP FUNCTION IF EXISTS verify_educational_certificate_prerequisites;
DROP FUNCTION IF EXISTS verify_educational_certificate_birth_date;
DROP FUNCTION IF EXISTS verify_educational_certificate_death_date;
DROP FUNCTION IF EXISTS verify_educational_certificate_kind;
DROP FUNCTION IF EXISTS verify_passport_death_date;
DROP FUNCTION IF EXISTS verify_passport_birth_date;
DROP FUNCTION IF EXISTS verify_passport_number;
DROP FUNCTION IF EXISTS verify_international_passport_number;
DROP FUNCTION IF EXISTS verify_visa_passport_expiration_date;

DROP VIEW IF EXISTS educational_certificates_view;

DROP EXTENSION IF EXISTS pgcrypto;

COMMIT;