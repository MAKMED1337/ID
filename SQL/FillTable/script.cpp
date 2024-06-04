#include <bits/stdc++.h>

using namespace std;

///INSERT INTO ankiety (id, nazwisko, wiek) VALUES (1, 'ob', 48);

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
        cout << "INSERT INTO cities (id, name) VALUES (" <<
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

void addOffices() {
    freopen("offices.sql", "w", stdout);
    cout << "--Offices\n";
    int id = 1;
    string types[] = {"consulat", "marriage agency", "driver schools"};

    for (country C : countries) {
        int type_id = 0;
        for (int i = 0; i < min<int>(2, cities[C.id].size()); i++) {
            cout << "INSERT INTO offices (id, office_type, country, address, city) VALUES (" <<
            id << ", "<< "'" + types[type_id] + "'" << ", "
            << STR(C.name) << ", " << STR(C.name + " " + cities[C.id][i]) << ", "<< STR(cities[C.id][i]) << ");\n";
            offices.push_back(Office(id, types[type_id], C.name, cities[C.id][i]));
            id++;
            type_id ++;
            type_id %= 3;
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
        int issuer = getRand(1, offices.size());
        int YY = getRand(1900, 2024);
        int MM = getRand(1, 12);
        int DD = getRand(1, 28);
        string date = to_string(YY) + "-" + to_string(MM) + "-" + to_string(DD);
        string date1 = to_string(YY + 10) + "-" + to_string(MM) + "-" + to_string(DD);
        cout << "INSERT INTO drivers_licences (id, type, person_id, issuer, issue_date, expiration_date) VALUES (" <<  
        i + 1 << ", " << STR(types[t_id]) << ", " << issuer << ", " << STR(date) << ", " << STR(date1)  << ");\n";
    }
}

void addEducationalCertificatesTypes() {
    freopen("educational_certificetes_types.sql", "w", stdout);
    string types[] = {"Associate Degree", "Bachelor Degree", "Postgraduate Diploma", "Master Degree", "Doctoral Degree"};
    int id = 1;
    for (string s : types) {
        cout << "INSERT INTO educational_certificetes_types (kind, prerequirement) VALUES (" <<  
        id++<< ", " << STR(s) << ");\n";
    }
}

void addEdType() {
    freopen("educational_instances_types.sql", "w", stdout);
    string types[] = {"university", "school"};
    int id = 1;
    for (string type : types) {
        cout << "INSERT INTO educational_instances_types (kind, educational_level) VALUES (" <<  
        id++<< ", " << STR(type) << ");\n";
    }
}

void addEdObjects() {
    freopen("educational_instances.sql", "w", stdout);
    array <string, 3> names[] = {{"Harvard University", "1636-09-08", "USA-Cambridge"}, {"Stanford University", "1885-10-01", "USA-Stanford"}, {"Massachusetts Institute of Technology", "1861-04-10", "USA-Cambridge"}, {"University of California, Berkeley", "1868-03-23", "USA-Berkeley"}, {"California Institute of Technology", "1891-09-23", "USA-Pasadena"}, {"University of Oxford", "1096-01-01", "UK-Oxford"}, {"University of Cambridge", "1209-01-01", "UK-Cambridge"}, {"Princeton University", "1746-10-22", "USA-Princeton"}, {"Yale University", "1701-10-09", "USA-New Haven"}, {"University of Chicago", "1890-07-09", "USA-Chicago"}, {"Columbia University", "1754-05-25", "USA-New York"}, {"University of Pennsylvania", "1740-11-14", "USA-Philadelphia"}, {"University of Michigan", "1817-08-26", "USA-Ann Arbor"}, {"Johns Hopkins University", "1876-02-22", "USA-Baltimore"}, {"University of California, Los Angeles", "1919-05-23", "USA-Los Angeles"}, {"Duke University", "1838-12-28", "USA-Durham"}, {"Northwestern University", "1851-01-28", "USA-Evanston"}, {"New York University", "1831-04-21", "USA-New York"}, {"University of California, San Diego", "1960-11-18", "USA-San Diego"}, {"University of Washington", "1861-11-04", "USA-Seattle"}, {"University of Toronto", "1827-03-15", "Canada-Toronto"}, {"Imperial College London", "1907-07-08", "UK-London"}, {"University College London", "1826-02-11", "UK-London"}, {"University of Edinburgh", "1582-04-14", "UK-Edinburgh"}, {"University of Melbourne", "1853-04-11", "Australia-Melbourne"}, {"Australian National University", "1946-08-01", "Australia-Canberra"}, {"University of Sydney", "1850-10-01", "Australia-Sydney"}, {"University of Queensland", "1909-12-16", "Australia-Brisbane"}, {"London School of Economics and Political Science", "1895-10-10", "UK-London"}, {"University of Hong Kong", "1911-03-30", "Hong Kong-Hong Kong"}, {"National University of Singapore", "1905-08-03", "Singapore-Singapore"}, {"ETH Zurich", "1855-10-16", "Switzerland-Zurich"}, {"Peking University", "1898-12-17", "China-Beijing"}, {"Tsinghua University", "1911-04-29", "China-Beijing"}, {"University of British Columbia", "1908-09-30", "Canada-Vancouver"}, {"University of Tokyo", "1877-04-12", "Japan-Tokyo"}, {"Seoul National University", "1946-08-22", "South Korea-Seoul"}, {"McGill University", "1821-03-31", "Canada-Montreal"}, {"University of Manchester", "1824-10-22", "UK-Manchester"}, {"University of Wisconsin-Madison", "1848-07-26", "USA-Madison"}, {"Cornell University", "1865-04-27", "USA-Ithaca"}, {"University of California, Davis", "1905-03-18", "USA-Davis"}, {"University of Illinois at Urbana-Champaign", "1867-03-02", "USA-Champaign"}, {"Carnegie Mellon University", "1900-11-15", "USA-Pittsburgh"}, {"University of Texas at Austin", "1883-09-15", "USA-Austin"}, {"University of Southern California", "1880-10-06", "USA-Los Angeles"}, {"King's College London", "1829-08-14", "UK-London"}, {"University of North Carolina at Chapel Hill", "1789-12-11", "USA-Chapel Hill"}, {"University of Minnesota", "1851-02-25", "USA-Minneapolis"}, {"Monash University", "1958-06-27", "Australia-Melbourne"}, {"Kyoto University", "1897-06-18", "Japan-Kyoto"}, {"University of Glasgow", "1451-01-07", "UK-Glasgow"}, {"University of Birmingham", "1900-03-09", "UK-Birmingham"}, {"University of Bristol", "1876-07-10", "UK-Bristol"}, {"University of Southampton", "1862-06-29", "UK-Southampton"}, {"University of Warwick", "1965-10-01", "UK-Coventry"}, {"University of Sheffield", "1905-05-31", "UK-Sheffield"}, {"University of Leeds", "1904-06-06", "UK-Leeds"}, {"University of Nottingham", "1881-06-17", "UK-Nottingham"}, {"University of Exeter", "1955-07-24", "UK-Exeter"}, {"University of St Andrews", "1413-02-28", "UK-St Andrews"}, {"University of Liverpool", "1881-07-16", "UK-Liverpool"}, {"University of York", "1963-10-09", "UK-York"}, {"Durham University", "1832-08-01", "UK-Durham"}, {"University of Aberdeen", "1495-09-10", "UK-Aberdeen"}, {"University of Dundee", "1881-07-25", "UK-Dundee"}, {"University of East Anglia", "1963-11-01", "UK-Norwich"}, {"University of Reading", "1892-03-17", "UK-Reading"}, {"University of Surrey", "1966-09-22", "UK-Guildford"}, {"University of Sussex", "1961-08-16", "UK-Falmer"}, {"University of Leicester", "1921-07-20", "UK-Leicester"}, {"Queen Mary University of London", "1887-10-11", "UK-London"}, {"City, University of London", "1894-05-14", "UK-London"}, {"Royal Holloway, University of London", "1849-06-30", "UK-Egham"}, {"Birkbeck, University of London", "1823-06-02", "UK-London"}, {"School of Oriental and African Studies", "1916-06-05", "UK-London"}, {"Goldsmiths, University of London", "1904-01-29", "UK-London"}, {"University of Strathclyde", "1796-07-01", "UK-Glasgow"}, {"Heriot-Watt University", "1821-10-16", "UK-Edinburgh"}, {"University of Kent", "1965-01-04", "UK-Canterbury"}, {"Loughborough University", "1909-07-18", "UK-Loughborough"}, {"University of Bath", "1966-10-25", "UK-Bath"}, {"University of Essex", "1964-09-11", "UK-Colchester"}, {"Lancaster University", "1964-08-20", "UK-Lancaster"}, {"Swansea University", "1920-05-19", "UK-Swansea"}, {"Cardiff University", "1883-10-24", "UK-Cardiff"}, {"University of Plymouth", "1862-04-10", "UK-Plymouth"}, {"University of Portsmouth", "1992-07-07", "UK-Portsmouth"}, {"University of Hull", "1927-10-11", "UK-Hull"}, {"Aberystwyth University", "1872-10-15", "UK-Aberystwyth"}, {"Bangor University", "1884-10-18", "UK-Bangor"}, {"University of Lincoln", "1861-02-14", "UK-Lincoln"}, {"University of Chester", "1839-04-15", "UK-Chester"}, {"University of Huddersfield", "1825-08-18", "UK-Huddersfield"}, {"University of Brighton", "1859-07-10", "UK-Brighton"}, {"University of Central Lancashire", "1828-09-20", "UK-Preston"}, {"University of Westminster", "1838-08-11", "UK-London"}, {"Phillips Exeter Academy", "1781-04-03", "USA-Exeter"}, {"Eton College", "1440-06-12", "UK-Windsor"}, {"Choate Rosemary Hall", "1890-10-24", "USA-Wallingford"}, {"Andover Phillips Academy", "1778-04-21", "USA-Andover"}, {"Rugby School", "1567-09-01", "UK-Rugby"}, {"The Lawrenceville School", "1810-06-15", "USA-Lawrenceville"}};

    int id = 1;
    for (auto [name, date, adress] : names) {
        cout << "INSERT INTO educational_instances (id, name, location, creation_date, kind) VALUES (" <<  
        id++ << ", " << STR(name) << ", " << STR(adress) << ", " << STR(date) << ", 2"  << ");\n";    }
}



// void addEdCertificate() {
//     freopen("educational_certificates.sql", "w", stdout);
//     for (int i = 0; i < 100; i++) {
//         int issuer = getRand(1, IDs.size());
//         int 
//     }
// }

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
    return 0;
}