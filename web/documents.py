from typing import Annotated

from fastapi import Depends

from db import EducationalCertificates, InternationalPassports, Passports, Visas

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
async def get_educational_certificates(user: Annotated[int, Depends(get_user)], db: DB) -> list[EducationalCertificates]:
    return await EducationalCertificates.get(db, user)


@app.get('/documents/visas')
async def get_visas(user: Annotated[int, Depends(get_user)], db: DB) -> list[Visas]:
    return await Visas.get(db, user)
