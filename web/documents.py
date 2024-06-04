from typing import Annotated

from fastapi import Depends

from db import Passports

from .authorization import get_user
from .config import app
from .helper import DB


@app.get('/documents/passport')
async def get_passport(user: Annotated[int, Depends(get_user)], db: DB) -> list[Passports]:
    return await Passports.get_passports(db, user)
