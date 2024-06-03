\c id-documents;

BEGIN;

DROP TABLE IF EXISTS countries CASCADE;
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

COMMIT;