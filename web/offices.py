from typing import Annotated

from fastapi import Depends

from db import get_administrated_offices

from .authorization import get_user
from .config import app
from .helper import DB


@app.get('/offices/access')
async def get_visas(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_administrated_offices(db, user)
