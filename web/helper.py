from collections.abc import AsyncIterator
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from db.config import make_session


async def get_db() -> AsyncIterator[AsyncSession]:
    db = make_session()
    try:
        yield db
    finally:
        await db.close()

DB = Annotated[AsyncSession, Depends(get_db)]
