from faker import Faker

fake = Faker('en_US')

F = open('people_names.txt', 'w')
id = 1
for id in range(1, 501):
    print(str(fake.passport_owner()), file = F)
F.close()
