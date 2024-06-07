#include <bits/stdc++.h>

using namespace std;

vector <int> IDs;

mt19937_64 rng(228);

string STR(string S) {
    return "$$" + S + "$$";
}

int getRand(int l, int r) {
    return l + rng()%(r - l + 1);
}

void addPeople() {
    freopen("people.sql", "w", stdout);
    cout << "--people\n";
    for (int id = 1; id <= 500; id++) { /// 200 users
        string date = to_string(getRand(1900, 2024)) + "-" + to_string(getRand(1, 12)) + "-" + to_string(getRand(1, 28));
        cout << "INSERT INTO people (id, date_of_birth) VALUES (" << id
        << ", '" + date + "'::date);\n";
        IDs.push_back(id);
    }
}

struct account{
    int id;
    string login;
    string password;
    account(int id, string nick, string passwd):id(id), login(nick), password(passwd) {}
};

vector <account> accs;

void addAccounts() {
    freopen("accounts.sql", "w", stdout);
    cout << "--accounts\n";
    for (auto id : IDs) {
        cout << "SELECT add_user(" << id << ", " << "\'user" + to_string(id) + "\'"
         <<", " << "'12345678');\n";
        accs.push_back(account(id, "user" + to_string(id), "12345678"));
    }
}

struct country{
    int id;
    string name;
    country(int id, string name): id(id), name(name) {}
};

vector<pair <string, string>> cityToCountry;
map <string, int> countryToId;
map <int, string> idToCountry;
vector<string> cities[2000]; /// contry ID

vector <country> calcCountryes() {
    freopen("cities.txt", "r", stdin);
    freopen("countries.sql", "w", stdout);
    string s;
    getline(cin, s);
    string was = "";
    vector <country> ret;
    while(getline(cin, s)) {
        int ptr = 0;
        while(s[ptr] != ',') ptr++;
        string cntName = s.substr(2, ptr - 3);
        if (cntName != was) {
            ret.push_back(country(ret.size() + 1, cntName));
        }
        cityToCountry.emplace_back(s.substr(ptr + 2, s.size() - ptr - 5), cntName);
        cities[ret.size()].push_back(s.substr(ptr + 2, s.size() - ptr - 5));
        was = cntName;
    }
    for (country C : ret) {
        countryToId[C.name] = C.id;
        idToCountry[C.id] = C.name;
        cout << "INSERT INTO countries (id, country) VALUES (" <<
        C.id << ", " << STR(C.name) << ");\n";
    }
    return ret;
}

struct city {
    int id;
    string cityname;
    string country;
    city(int a, string b, string c): id(a), cityname(b), country(c) {}
};

vector <country> countries = calcCountryes();
map <pair <string, string>, int> IDCity;

void addCities() {
    freopen("cities.sql", "w", stdout);
    cout << "--Cities\n";
    int cnt = 1;
    for (auto C : cityToCountry) {
        cout << "INSERT INTO cities (id, country, city) VALUES (" << 
        cnt << ", '" + C.second + "', '" <<  C.first + "'" << ");\n";
        IDCity[C] = cnt;
        cnt++;
    }
}


struct Office{
    int id;
    string offic_type;
    string country;
    string location;
    string city;
    Office(int id, string offic_type, 
    string country, string city): id(id), offic_type(offic_type),
            country(country), city(city) {}
};

vector<Office> offices;
map <string, vector <int>> OFF;

void addOffices() {
    freopen("offices.sql", "w", stdout);
    cout << "--Offices\n";
    int id = 1;
    string types[] = {"consulat", "marriage agency", "driver schools", "medical center"};

    for (country C : countries) {
        int type_id = 0;
        for (int i = 0; i < min<int>(10, cities[C.id].size()); i++) {
            cout << "INSERT INTO offices (id, office_type, country, address, city) VALUES (" <<
            id << ", "<< "'" + types[type_id] + "'" << ", "
            << STR(C.name) << ", " << STR(C.name + " " + cities[C.id][i]) << ", "<< STR(cities[C.id][i]) << ");\n";
            offices.push_back(Office(id, types[type_id], C.name, cities[C.id][i]));
            OFF[types[type_id]].push_back(id);
            id++;
            type_id++;
            type_id %= 4;
        }
    }
}



struct admin{
    int user_id;
    int office_id;
    admin(int a, int b): user_id(a), office_id(b) {}
};

vector<admin> admins;

void addAdministrators() {
    freopen("administrators.sql", "w", stdout);
    shuffle(offices.begin(), offices.end(), rng);
    shuffle(accs.begin(), accs.end(), rng);
    int c = 0;
    for (Office OF : offices) {
        cout << "INSERT INTO administrators (user_id, office_id) VALUES (" <<  
        accs[c].id << ", " << OF.id << ");\n";
        admins.push_back(admin(accs[c].id, OF.id));
        c++;
    }
}

struct driver_licences {
    int id;
    string type;
    int person_id;
    int issuer;
    string issue_date;
    string expiration_date;
    driver_licences(int a, string b, int c, int d, string e, string f) :
        id(a), type(b), person_id(c), issuer(d), issue_date(e), expiration_date(f) {}
};

void addDriversLicences() {
    freopen("drivers_licences.sql", "w", stdout);
    string types[] = {"A", "B1", "C1", "C", "D", "D1"};
    for (int i = 0; i < 200; i++) {
        int t_id = getRand(0, 5);
        int pers_id = getRand(1, accs.size());
        int issuer = OFF["driver schools"][getRand(0, OFF["driver schools"].size() - 1)];
        int YY = getRand(1900, 2024);
        int MM = getRand(1, 12);
        int DD = getRand(1, 28);
        string date = to_string(YY) + "-" + to_string(MM) + "-" + to_string(DD);
        string date1 = to_string(YY + 10) + "-" + to_string(MM) + "-" + to_string(DD);
        cout << "INSERT INTO drivers_licences (id, type, person, issuer, issue_date, expiration_date) VALUES (" <<  
        i + 1 << ", " << STR(types[t_id]) << ", " << pers_id << ", " <<  issuer << ", " << STR(date) << ", " << STR(date1)  << ");\n";
    }
}

void addEducationalCertificatesTypes() {
    freopen("educational_certificetes_types.sql", "w", stdout);
    cout << "INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (1, null);\n";
    for (int id = 2; id < 20; id++) {
        cout << "INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (" <<  
        id << ", " << id/2 << ");\n";
    }
}

void addEdType() {
    freopen("educational_instances_types.sql", "w", stdout);
    string types[3] = {"school", "college", "university"};
    int id = 1;
    for (int id = 1; id <= 3; id++) {
        cout << "INSERT INTO educational_instances_types (kind, educational_level) VALUES (" <<  
        id << ", " << STR(types[id - 1]) << ");\n";
    }
}

int educational_instances_count = 1;
pair <int, int> universityIds;
void addUnivers() {
    vector <array <string, 5>> universities = {
        {"University of Warsaw", "1816-11-19", "Krakowskie Przedmieście 26/28, 00-927 Warsaw", "Warsaw", "Poland"},
        {"Jagiellonian University", "1364-05-12", "Golebia 24, 31-007 Krakow", "Krakow", "Poland"},
        {"Adam Mickiewicz University", "1919-05-07", "ul. Henryka Wieniawskiego 1, 61-712 Poznan", "Poznan", "Poland"},
        {"AGH University of Science and Technology", "1919-04-20", "al. Mickiewicza 30, 30-059 Krakow", "Krakow", "Poland"},
        {"Warsaw University of Technology", "1826-01-04", "Plac Politechniki 1, 00-661 Warsaw", "Warsaw", "Poland"},
        {"University of Wroclaw", "1702-08-01", "pl. Uniwersytecki 1, 50-137 Wroclaw", "Wroclaw", "Poland"},
        {"Gdansk University of Technology", "1904-10-06", "ul. Narutowicza 11/12, 80-233 Gdansk", "Gdansk", "Poland"},
        {"Lodz University of Technology", "1945-05-24", "ul. Stefana Żeromskiego 116, 90-924 Lodz", "Lodz", "Poland"},
        {"Nicolaus Copernicus University", "1945-10-15", "ul. Gagarina 11, 87-100 Torun", "Torun", "Poland"},
        {"Medical University of Warsaw", "1950-12-01", "ul. Żwirki i Wigury 61, 02-091 Warsaw", "Warsaw", "Poland"},
        {"Harvard University", "1636-09-08", "Massachusetts Hall, Cambridge, MA 02138", "Cambridge", "USA"},
        {"Stanford University", "1885-11-11", "450 Serra Mall, Stanford, CA 94305", "Stanford", "USA"},
        {"Massachusetts Institute of Technology", "1861-04-10", "77 Massachusetts Ave, Cambridge, MA 02139", "Cambridge", "USA"},
        {"University of California, Berkeley", "1868-03-23", "200 California Hall, Berkeley, CA 94720", "Berkeley", "USA"},
        {"California Institute of Technology", "1891-09-23", "1200 E California Blvd, Pasadena, CA 91125", "Pasadena", "USA"},
        {"University of Chicago", "1890-10-01", "5801 S Ellis Ave, Chicago, IL 60637", "Chicago", "USA"},
        {"Princeton University", "1746-10-22", "Princeton, NJ 08544", "Princeton", "USA"},
        {"Columbia University", "1754-05-25", "116th St & Broadway, New York, NY 10027", "New York", "USA"},
        {"Yale University", "1701-10-09", "New Haven, CT 06520", "New Haven", "USA"},
        {"University of Pennsylvania", "1740-11-14", "Philadelphia, PA 19104", "Philadelphia", "USA"}
    };
    universityIds = {educational_instances_count, educational_instances_count + universities.size() - 1};
    for (auto [name, date, adress, city, country] : universities) {
        cout << "INSERT INTO educational_instances (id, name, address, creation_date, kind, country, city) VALUES (" <<  
        educational_instances_count++ << ", " << STR(name) << ", " << STR(adress) << ", " << STR(date) << ", 3, " << STR(country) << ", " << STR(city)  << ");\n";
    }
}

pair <int, int> schoolsIds;

void addSchools() {
    vector<array <string, 5>> schools = {
        {"John Paul II High School", "1957-09-01", "ul. Swietej Gertrudy 7, 31-046 Krakow", "Krakow", "Poland"},
        {"High School No. 5 Krakow", "1945-09-01", "ul. Studencka 12, 31-116 Krakow", "Krakow", "Poland"},
        {"International School of Krakow", "1993-09-01", "ul. Starowislna 26, 31-032 Krakow", "Krakow", "Poland"},
        {"School Complex No. 1 Krakow", "1964-09-01", "ul. Ulanow 3, 31-450 Krakow", "Krakow", "Poland"},
        {"High School No. 8 Krakow", "1928-09-01", "ul. Grzegorzecka 24, 31-532 Krakow", "Krakow", "Poland"},
        {"School Complex No. 2 Krakow", "1959-09-01", "ul. Sobieskiego 15, 31-136 Krakow", "Krakow", "Poland"},
        {"Bilingual High School No. 1 Warsaw", "1992-09-01", "ul. Syrokomli 20, 30-102 Warsaw", "Warsaw", "Poland"},
        {"Lyceum No. 9 Warsaw", "1935-09-01", "ul. Nowosadecka 41, 30-383 Warsaw", "Warsaw", "Poland"},
        {"Lyceum No. 3 Warsaw", "1910-09-01", "ul. Topolowa 22, 31-506 Warsaw", "Warsaw", "Poland"},
        {"Catholic School Complex Warsaw", "1991-09-01", "ul. Bernardynska 5, 00-055 Warsaw", "Warsaw", "Poland"}
    };
    
    schoolsIds = {educational_instances_count, educational_instances_count + schools.size() - 1};

    for (auto [name, date, adress, city, country] : schools) {
        cout << "INSERT INTO educational_instances (id, name, address, creation_date, kind, country, city) VALUES (" <<  
        educational_instances_count++ << ", " << STR(name) << ", " << STR(adress) << ", " << STR(date) << ", 1, " << STR(country) << ", " << STR(city)  << ");\n";
    }
}

pair <int, int> collegesIds;

void addColleges() {
    vector <array <string, 5>> colleges = {
        {"Cracow University of Technology", "1945-10-06", "ul. Warszawska 24, 31-155 Krakow", "Krakow", "Poland"},
        {"AGH University of Science and Technology", "1919-04-20", "al. Mickiewicza 30, 30-059 Krakow", "Krakow", "Poland"},
        {"Warsaw University of Technology", "1826-01-04", "Plac Politechniki 1, 00-661 Warsaw", "Warsaw", "Poland"},
        {"University of Warsaw", "1816-11-19", "Krakowskie Przedmieście 26/28, 00-927 Warsaw", "Warsaw", "Poland"},
        {"University of Social Sciences and Humanities", "1996-10-01", "ul. Chodakowska 19/31, 03-815 Warsaw", "Warsaw", "Poland"},
        {"Warsaw School of Economics", "1906-10-30", "al. Niepodleglosci 162, 02-554 Warsaw", "Warsaw", "Poland"},
        {"University of Information Technology and Management in Rzeszow", "1996-11-01", "ul. Sucharskiego 2, 35-225 Rzeszow", "Rzeszow", "Poland"},
        {"Cracow University of Economics", "1925-10-01", "ul. Rakowicka 27, 31-510 Krakow", "Krakow", "Poland"},
        {"Warsaw University of Life Sciences", "1816-09-23", "Nowoursynowska 166, 02-787 Warsaw", "Warsaw", "Poland"},
        {"Academy of Fine Arts in Warsaw", "1945-10-22", "Krakowskie Przedmieście 5, 00-068 Warsaw", "Warsaw", "Poland"}
    };

    collegesIds = {educational_instances_count, educational_instances_count + colleges.size() - 1};

    for (auto [name, date, adress, city, country] : colleges) {
        cout << "INSERT INTO educational_instances (id, name, address, creation_date, kind, country, city) VALUES (" <<  
        educational_instances_count++ << ", " << STR(name) << ", " << STR(adress) << ", " << STR(date) << ", 2, " << STR(country) << ", " << STR(city)  << ");\n";
    }
}


void addEdObjects() {
    freopen("educational_instances.sql", "w", stdout);
    addUnivers();
    addSchools();
    addColleges();
}

int total = 1;

void addCert(int issuer, int holder, string issue_date, int kind) {
    cout << "INSERT INTO educational_certificates (id, issuer, holder, issue_date, kind) VALUES (" <<  
    total++ << ", " << issuer << ", " << holder << ", " << STR(issue_date) << ", " << kind << ");\n";
}

/*
* addEducCertificates logic works because prerequirement for all kind of 
* educational_certificates_types is kind/2
*/
void addEducCertificates() {
    freopen("educational_certificates.sql", "w", stdout);
    for (auto id : IDs) {
        int cntCert = getRand(0, 4);
        int kind = 1;
        int wasY = 1980; /// TODO: define with date of birth + 10
        for (int i = 0; i < cntCert; i++) {
            int issuer = getRand(universityIds.first, universityIds.second);
            if (kind / 2 == 0) { 
                issuer = getRand(schoolsIds.first, schoolsIds.second);
            } else if (kind / 2 <= 1) {
                issuer = getRand(collegesIds.first, collegesIds.second);
            }
            string date = to_string(wasY + getRand(4, 7)) + "-" + to_string(getRand(1, 12)) 
            + "-" + to_string(getRand(1, 28));
            addCert(issuer, id, date, kind);
            kind = kind * 2 + getRand(0, 1); 
        }
    }
}


void printBirth(int id, string father, string mother, int person, int issuer, string country, string city, string date) {
    cout << "INSERT INTO birth_certificates (id, father, mother, person, issuer, country_of_birth, city_of_birth, issue_date) VALUES (" 
    << id << ", " << father << ", " << mother << ", " << person << ", " << issuer << ", " << STR(country) << ", " << STR(city) << ", " << STR(date) << ");\n";
}



void addBirth() {
    freopen("birth_certificates.sql", "w", stdout);
    sort(IDs.begin(), IDs.end());
    int i = 1;
    int YY = 2024;
    for (auto id : IDs) {
        int issuer = OFF["medical center"][getRand(0, OFF["medical center"].size() - 1)];
        int country_id = getRand(1, countries.size() - 1);
        string CC = idToCountry[country_id];
        string city = cities[country_id][getRand(0, (int)cities[country_id].size() - 1)];
        string date = to_string(YY - getRand(0, 3)) + "-" + to_string(getRand(1, 12)) + "-" + to_string(getRand(1, 28));
        string father = to_string(id << 1);
        string mother = to_string(id << 1 | 1);
        if ((id << 1) > IDs.size()) father = "null";
        if ((id << 1 | 1) > IDs.size()) mother = "null";
        printBirth(i, father, mother, id, issuer, CC, city, date);
        i++;
        if ((i&(i-1)) == 0) YY -= 25;
    }
}


void printMarrige(int id, int person1, int person2, string date) {
    cout << "INSERT INTO marriages (id, person1, person2, marriage_date) VALUES ("
    << id << ", " << person1 << ", " << person2<< ", " << STR(date)<< ");\n";
}

void addMarriges() {
    freopen("marriages.sql", "w", stdout);
    int id = 1;
    int YY = 2014;
    for (int i = 2; i < IDs.size() && (i^1) < IDs.size(); i += 2) {
        string date = to_string(YY - getRand(0, 2)) + "-" + to_string(getRand(1, 12)) + "-" + to_string(getRand(1, 28));
        printMarrige(id++, i, (i ^ 1), date);
        if ((i&(i-1)) == 0) YY -= 25;
    }
}

int main() {
    addPeople();
    addAccounts();
    addCities();
    addOffices();
    addAdministrators();
    addDriversLicences();
    addEducationalCertificatesTypes();
    addEdType();
    addEdObjects();
    addEducCertificates();
    addBirth();
    addMarriges();
    return 0;
}