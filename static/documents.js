documents = {
    1: {
        name: 'International Passports',
        view: [
            'id',
            'original_name',
            'original_surname',
            'en_name',
            'en_surname',
            'issue_date',
            'expiration_date',
            'sex',
            'issuer',
            'invalidated',
        ],
        insert: [
            ['id', 'int', false],
            ['original_name', 'str', false],
            ['original_surname', 'str', false],
            ['en_name', 'str', false],
            ['en_surname', 'str', false],
            ['expiration_date', 'date', false],
            ['sex', 'str', false],
            ['passport_owner', 'int', false],
            ['country', 'str', false],
            ['series', 'str', false],
        ],
        url: '/documents/international_passports',
    },
    2: {
        name: 'Marriage Certificates',
        view: [
            'ID',
            'Marriage ID',
            'First Person',
            'Second Person',
            'Date of Marriage',
            'Issuer',
            'Date of Issue',
        ],
        insert: [
            ['id', 'int', false],
            ['marriage_id', 'int', false],
        ],
        url: '/documents/marriage_certificates',
    },
    3: {
        name: 'Visas',
        view: [
            'ID',
            'Passport ID',
            'Visa Category',
            'Date of Issue',
            'Expiration Date',
        ],
        insert: [
            ['id', 'int', false],
            ['type', 'int', false],
            ['passport', 'int', false],
            ['country', 'str', false],
        ],
        url: '/documents/visas',
    },
    4: {
        name: 'Birth Certificates',
        view: [
            'id',
            'person',
            'Person\'s Name',
            'Date of Birth',
            'City of Birth',
            'Country of Birth',
            'Father\'s Name',
            'Mother\'s Name',
            'Date of Issue',
        ],
        insert: [
            ['id', 'int', false],
            ['father', 'int', true],
            ['mother', 'int', true],
            ['person', 'int', false],
            ['country_of_birth', 'str', false],
            ['city_of_birth', 'str', false],
        ],
        url: '/documents/birth_certificates',
    },
    5: {
        name: 'Death Certificates',
        view: [
            'ID',
            'Person ID',
            'Name',
            'Surname',
            'Date of Death',
            'Date of Issue',
        ],
        insert: [
            ['id', 'int', false],
            ['person', 'int', false],
        ],
        url: '/documents/death_certificates',
    },
    6: {
        name: 'Divorce Certificates',
        view: [
            'ID',
            'Divorce ID',
            'Marriage ID',
            'First Person',
            'Second Person',
            'Date of Marriage',
            'Date of Divorce',
            'Date of Issue',
            'Issuer',
        ],
        insert: [
            ['id', 'int', false],
            ['divorce_id', 'int', false],
        ],
        url: '/documents/divorce_certificates',
    },
    7: {
        name: 'Driver\'s Licenses',
        view: [
            'ID',
            'Person ID',
            'Type',
            'Name',
            'Surname',
            'Date of Birth',
            'Date of Issue',
            'Expiration Date',
        ],
        insert: [
            ['id', 'int', false],
            ['type', 'str', false],
            ['person', 'int', false],
            ['expiration_date', 'date', false],
        ],
        url: '/documents/drivers_licences',
    },
    8: {
        name: 'Passports',
        view: [
            'id',
            'original_name',
            'original_surname',
            'en_name',
            'en_surname',
            'issue_date',
            'expiration_date',
            'sex',
            'issuer',
            'invalidated',
        ],
        insert: [
            ['id', 'int', false],
            ['original_name', 'str', false],
            ['original_surname', 'str', false],
            ['en_name', 'str', false],
            ['en_surname', 'str', false],
            ['expiration_date', 'date', false],
            ['sex', 'str', false],
            ['passport_owner', 'int', false],
        ],
        url: '/documents/passports',
    },
    9: {
        name: 'Educational Certificates',
        view: [
            'id',
            'holder',
            'Level of Education',
            'Date of Issue',
        ],
        insert: [
            ['id', 'int', false],
            ['holder', 'int', false],
            ['kind', 'int', false],
        ],
        url: '/documents/educational_certificates',
    },
    10: {
        name: 'Pet Passports',
        view: [
            'id',
            'name',
            'pet_owner',
            'date_of_birth',
            'species',
            'issuer',
        ],
        insert: [
            ['id', 'int', false],
            ['name', 'str', false],
            ['pet_owner', 'int', false],
            ['date_of_birth', 'date', false],
            ['species', 'str', false],
        ],
        url: '/documents/pet_passports',
    }
}
