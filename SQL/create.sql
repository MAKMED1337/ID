CREATE SCHEMA IF NOT EXISTS "public";

CREATE  TABLE "public".countries (
	country              varchar  NOT NULL  ,
	id                   integer  NOT NULL  ,
	CONSTRAINT pk_countries PRIMARY KEY ( id ),
	CONSTRAINT unq_countries_country UNIQUE ( country )
 );

CREATE  TABLE "public".document_types (
	id                   integer  NOT NULL  ,
	document             varchar  NOT NULL  ,
	CONSTRAINT pk_document_types PRIMARY KEY ( id )
 );

CREATE  TABLE "public".educational_certificates_types (
	id                   serial  NOT NULL  ,
	name                 varchar  NOT NULL  ,
	prerequirement       integer    ,
	CONSTRAINT pk_educational_certificates_types PRIMARY KEY ( id ),
	CONSTRAINT unq_educational_certificates_types_kind UNIQUE ( name )
 );

CREATE  TABLE "public".offices_kinds (
	kind                 integer  NOT NULL  ,
	description          varchar(100)  NOT NULL  ,
	CONSTRAINT pk_offices_kinds PRIMARY KEY ( kind )
 );

CREATE  TABLE "public".people (
	id                   bigint  NOT NULL  ,
	date_of_birth        date DEFAULT CURRENT_DATE NOT NULL  ,
	date_of_death        date    ,
	name                 varchar(100)  NOT NULL  ,
	surname              varchar(100)  NOT NULL  ,
	CONSTRAINT pk_users PRIMARY KEY ( id )
 );

CREATE  TABLE "public".visa_categories (
	"type"               integer  NOT NULL  ,
	description          varchar(100)    ,
	working_permit       boolean  NOT NULL  ,
	residence_permit     boolean  NOT NULL  ,
	duration             interval  NOT NULL  ,
	country              varchar  NOT NULL  ,
	CONSTRAINT pk_visa_categories PRIMARY KEY ( "type", country )
 );

CREATE  TABLE "public".accounts (
	id                   bigint  NOT NULL  ,
	login                varchar  NOT NULL  ,
	hashed_password      varchar(200)  NOT NULL  ,
	CONSTRAINT pk_accounts PRIMARY KEY ( id )
 );

CREATE  TABLE "public".cities (
	id                   integer  NOT NULL  ,
	country              varchar(100)  NOT NULL  ,
	city                 varchar(100)  NOT NULL  ,
	CONSTRAINT pk_cities PRIMARY KEY ( id ),
	CONSTRAINT unq_cities_country_city UNIQUE ( country, city )
 );

CREATE  TABLE "public".educational_instances (
	id                   integer  NOT NULL  ,
	name                 varchar(100)  NOT NULL  ,
	address              varchar(200)  NOT NULL  ,
	creation_date        date  NOT NULL  ,
    closure_date         date    ,
	country              varchar  NOT NULL  ,
	city                 varchar  NOT NULL  ,
	CONSTRAINT pk_educational_instances PRIMARY KEY ( id )
 );

CREATE  TABLE "public".educational_instances_types_relation (
	instance_id          integer  NOT NULL  ,
	type_id              integer  NOT NULL  ,
	CONSTRAINT pk_educational_instances_types_relation PRIMARY KEY ( instance_id, type_id )
 );

CREATE  TABLE "public".marriages (
	id                   bigint  NOT NULL  ,
	person1              bigint  NOT NULL  ,
	person2              bigint  NOT NULL  ,
	marriage_date        date  NOT NULL  ,
	CONSTRAINT pk_marriage_certificates PRIMARY KEY ( id )
 );

ALTER TABLE "public".marriages ADD CONSTRAINT cns_marriage_certificates_different_people CHECK ( (person1 <> person2) );

CREATE  TABLE "public".office_kinds_documents (
	document_id          integer  NOT NULL  ,
	kind_id              integer  NOT NULL  ,
	CONSTRAINT pk_office_kinds_documents PRIMARY KEY ( document_id, kind_id )
 );

CREATE  TABLE "public".offices (
	id                   integer  NOT NULL  ,
	name 				 varchar  NOT NULL  ,
	country              varchar  NOT NULL  ,
	address              varchar(200)  NOT NULL  ,
	city                 varchar  NOT NULL  ,
	CONSTRAINT pk_offices PRIMARY KEY ( id )
 );

CREATE  TABLE "public".offices_kinds_relations (
	office_id            integer  NOT NULL  ,
	kind_id              integer  NOT NULL  ,
	CONSTRAINT pk_offices_kinds_relations PRIMARY KEY ( office_id, kind_id )
 );

CREATE  TABLE "public".passports (
	id                   bigint  NOT NULL  ,
	original_surname     varchar(100)  NOT NULL  ,
	original_name        varchar(100)  NOT NULL  ,
	en_name              varchar(100)  NOT NULL  ,
	en_surname           varchar(100)  NOT NULL  ,
	issue_date           date DEFAULT CURRENT_DATE NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	sex                  char(1)  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	passport_owner       bigint  NOT NULL  ,
	lost                 boolean DEFAULT FALSE  NOT NULL  ,
	invalidated          boolean DEFAULT FALSE  NOT NULL  ,
	CONSTRAINT pk_id_cards PRIMARY KEY ( id )
 );

ALTER TABLE "public".passports ADD CONSTRAINT cns_passports_sex CHECK ( (sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])) );

ALTER TABLE "public".passports ADD CONSTRAINT cns_passports_issue_expiry CHECK ( (issue_date < expiration_date) );

CREATE  TABLE "public".pet_passports (
	id                   bigint  NOT NULL  ,
	name                 varchar(100)  NOT NULL  ,
	pet_owner            bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	date_of_birth        date  NOT NULL  ,
	species              varchar NOT NULL  ,
	CONSTRAINT pk_animal_passports PRIMARY KEY ( id )
 );

CREATE  TABLE "public".administrators (
	user_id              bigint  NOT NULL  ,
	office_id            integer  NOT NULL  ,
	CONSTRAINT pk_administrators PRIMARY KEY ( user_id, office_id )
 );

CREATE  TABLE "public".birth_certificates (
	id                   bigint  NOT NULL  ,
	father               bigint    ,
	mother               bigint    ,
	person               bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	country_of_birth     varchar(100)    ,
	city_of_birth        varchar(100)    ,
	issue_date           date    ,
	CONSTRAINT pk_birth_certificate PRIMARY KEY ( id )
 );

CREATE  TABLE "public".death_certificates (
	id                   bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	person               bigint  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	CONSTRAINT pk_death_certificates PRIMARY KEY ( id )
 );

CREATE  TABLE "public".divorces (
	id                   bigint  NOT NULL  ,
	marriage_id          bigint  NOT NULL  ,
	divorce_date         date  NOT NULL  ,
	CONSTRAINT pk_divorces PRIMARY KEY ( id ),
	CONSTRAINT unq_divorces_marriage_id UNIQUE ( marriage_id )
 );

CREATE  TABLE "public".drivers_licences (
	id                   bigint  NOT NULL  ,
	"type"               varchar(3)  NOT NULL  ,
	person               bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	CONSTRAINT pk_drivers_licence PRIMARY KEY ( id )
 );

CREATE  TABLE "public".educational_certificates (
	id                   bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	holder               bigint  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	kind                 integer  NOT NULL  ,
	CONSTRAINT pk_educational_certificates PRIMARY KEY ( id )
 );

CREATE  TABLE "public".international_passports (
	id                   bigint  NOT NULL  ,
	original_name        varchar(100)  NOT NULL  ,
	original_surname     varchar(100)  NOT NULL  ,
	en_name              varchar(100)  NOT NULL  ,
	en_surname           varchar(100)  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date DEFAULT CURRENT_DATE NOT NULL  ,
	expiration_date      date  NOT NULL  ,
	sex                  char(1)  NOT NULL  ,
	passport_owner       bigint  NOT NULL  ,
	country              varchar  NOT NULL  ,
	lost                 boolean DEFAULT FALSE  NOT NULL  ,
	invalidated          boolean DEFAULT FALSE  NOT NULL  ,
	series               char(2)  NOT NULL  ,
	CONSTRAINT pk_international_passports PRIMARY KEY ( id )
 );

ALTER TABLE "public".international_passports ADD CONSTRAINT cns_international_passports_sex CHECK ( (sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar])) );

CREATE  TABLE "public".marriage_certificates (
	id                   bigint  NOT NULL  ,
	marriage_id          bigint  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	CONSTRAINT pk_marriage_certificates_0 PRIMARY KEY ( id )
 );

CREATE  TABLE "public".visas (
	id                   bigint  NOT NULL  ,
	"type"               integer  NOT NULL  ,
	passport             bigint  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	inner_issuer         integer  NOT NULL  ,
	country              varchar  NOT NULL  ,
	CONSTRAINT pk_visas PRIMARY KEY ( id )
 );

CREATE  TABLE "public".divorce_certificates (
	id                   bigint  NOT NULL  ,
	divorce_id           bigint  NOT NULL  ,
	issue_date           date  NOT NULL  ,
	issuer               integer  NOT NULL  ,
	CONSTRAINT pk_divorce_certificates PRIMARY KEY ( id )
 );

ALTER TABLE "public".accounts ADD CONSTRAINT fk_accounts_people FOREIGN KEY ( id ) REFERENCES "public".people( id );

ALTER TABLE "public".administrators ADD CONSTRAINT fk_administrators_offices FOREIGN KEY ( office_id ) REFERENCES "public".offices( id );

ALTER TABLE "public".administrators ADD CONSTRAINT fk_administrators_accounts FOREIGN KEY ( user_id ) REFERENCES "public".accounts( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificates_cities FOREIGN KEY ( city_of_birth, country_of_birth ) REFERENCES "public".cities( city, country );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificate_people_father FOREIGN KEY ( father ) REFERENCES "public".people( id );

ALTER TABLE "public".birth_certificates ADD CONSTRAINT fk_birth_certificate_people_mother FOREIGN KEY ( mother ) REFERENCES "public".people( id );

ALTER TABLE "public".cities ADD CONSTRAINT fk_cities_countries FOREIGN KEY ( country ) REFERENCES "public".countries( country );

ALTER TABLE "public".death_certificates ADD CONSTRAINT fk_death_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".death_certificates ADD CONSTRAINT fk_death_certificates_people FOREIGN KEY ( person ) REFERENCES "public".people( id );

ALTER TABLE "public".divorce_certificates ADD CONSTRAINT fk_divorce_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".divorce_certificates ADD CONSTRAINT fk_divorce_certificates_marriage FOREIGN KEY ( divorce_id ) REFERENCES "public".divorces( id );

ALTER TABLE "public".divorces ADD CONSTRAINT fk_divorces_marriage FOREIGN KEY ( marriage_id ) REFERENCES "public".marriages( id );

ALTER TABLE "public".drivers_licences ADD CONSTRAINT fk_drivers_licences_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".drivers_licences ADD CONSTRAINT fk_drivers_licences_people FOREIGN KEY ( person ) REFERENCES "public".people( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_holder FOREIGN KEY ( holder ) REFERENCES "public".people( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_issuer FOREIGN KEY ( issuer ) REFERENCES "public".educational_instances( id );

ALTER TABLE "public".educational_certificates ADD CONSTRAINT fk_educational_certificates_educational_certificates_types FOREIGN KEY ( kind ) REFERENCES "public".educational_certificates_types( id );

ALTER TABLE "public".educational_certificates_types ADD CONSTRAINT fk_educational_certificates_types FOREIGN KEY ( prerequirement ) REFERENCES "public".educational_certificates_types( id );

ALTER TABLE "public".educational_instances ADD CONSTRAINT fk_educational_instances FOREIGN KEY ( country, city ) REFERENCES "public".cities( country, city );

ALTER TABLE "public".educational_instances_types_relation ADD CONSTRAINT fk_educational_instances_types_relation_educational_instances FOREIGN KEY ( instance_id ) REFERENCES "public".educational_instances( id );

ALTER TABLE "public".educational_instances_types_relation ADD CONSTRAINT fk_educational_instances_types_relation_educational_certificate FOREIGN KEY ( type_id ) REFERENCES "public".educational_certificates_types( id );

ALTER TABLE "public".international_passports ADD CONSTRAINT fk_international_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".international_passports ADD CONSTRAINT fk_international_passports_owner FOREIGN KEY ( passport_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".international_passports ADD CONSTRAINT fk_international_passports_countries FOREIGN KEY ( country ) REFERENCES "public".countries( country );

ALTER TABLE "public".marriage_certificates ADD CONSTRAINT fk_marriage_certificates_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".marriage_certificates ADD CONSTRAINT fk_marriage_certificates FOREIGN KEY ( marriage_id ) REFERENCES "public".marriages( id );

ALTER TABLE "public".marriages ADD CONSTRAINT fk_marriage_certificates_person1 FOREIGN KEY ( person1 ) REFERENCES "public".people( id );

ALTER TABLE "public".marriages ADD CONSTRAINT fk_marriage_certificates_person2 FOREIGN KEY ( person2 ) REFERENCES "public".people( id );

ALTER TABLE "public".office_kinds_documents ADD CONSTRAINT fk_office_kinds_documents_document_types FOREIGN KEY ( document_id ) REFERENCES "public".document_types( id );

ALTER TABLE "public".office_kinds_documents ADD CONSTRAINT fk_office_kinds_documents_offices_kinds FOREIGN KEY ( kind_id ) REFERENCES "public".offices_kinds( kind );

ALTER TABLE "public".offices ADD CONSTRAINT fk_offices_cities FOREIGN KEY ( country, city ) REFERENCES "public".cities( country, city );

ALTER TABLE "public".offices_kinds_relations ADD CONSTRAINT fk_offices_kinds_relations_offices FOREIGN KEY ( office_id ) REFERENCES "public".offices( id );

ALTER TABLE "public".offices_kinds_relations ADD CONSTRAINT fk_offices_kinds_relations_kind FOREIGN KEY ( kind_id ) REFERENCES "public".offices_kinds( kind );

ALTER TABLE "public".passports ADD CONSTRAINT fk_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".passports ADD CONSTRAINT fk_passports_person FOREIGN KEY ( passport_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".pet_passports ADD CONSTRAINT fk_pet_passports_offices FOREIGN KEY ( issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".pet_passports ADD CONSTRAINT fk_pet_passports_owner FOREIGN KEY ( pet_owner ) REFERENCES "public".people( id );

ALTER TABLE "public".visa_categories ADD CONSTRAINT fk_visa_categories_countries FOREIGN KEY ( country ) REFERENCES "public".countries( country );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_visa_categories FOREIGN KEY ( "type", country ) REFERENCES "public".visa_categories( "type", country );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_offices FOREIGN KEY ( inner_issuer ) REFERENCES "public".offices( id );

ALTER TABLE "public".visas ADD CONSTRAINT fk_visas_passport FOREIGN KEY ( passport ) REFERENCES "public".international_passports( id );
