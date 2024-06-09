from typing import Annotated

from fastapi import Depends

from db import (
    EducationalCertificates,
    InternationalPassports,
    Passports,
    Visas,
    get_birth_certificates,
    get_death_certificates,
    get_divorce_certificates,
    get_marriage_certificates,
)
from db.functions import get_drivers_licences

from .authorization import get_user
from .config import app
from .helper import DB


@app.get('/documents/passports')
async def get_passports(user: Annotated[int, Depends(get_user)], db: DB) -> list[Passports]:
    return await Passports.get(db, user)


@app.get('/documents/international_passports')
async def get_international_passports(user: Annotated[int, Depends(get_user)], db: DB) -> list[InternationalPassports]:
    return await InternationalPassports.get(db, user)


@app.get('/documents/educational_certificates')
async def get_educational_certificates(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await EducationalCertificates.get(db, user)


@app.get('/documents/visas')
async def get_visas(user: Annotated[int, Depends(get_user)], db: DB) -> list[Visas]:
    return await Visas.get(db, user)


@app.get('/documents/marriage_certificates')
async def get_marriage_certitificates(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_marriage_certificates(db, user)


@app.get('/documents/birth_certificates')
async def get_birth_certitificates(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_birth_certificates(db, user)


@app.get('/documents/death_certificates')
async def get_death_certitificates(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_death_certificates(db, user)


@app.get('/documents/drivers_licences')
async def get_driver_licences(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_drivers_licences(db, user)


@app.get('/documents/divorce_certificates')
async def get_divorce_certificates_(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_divorce_certificates(db, user)
