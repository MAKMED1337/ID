from typing import Any

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession


async def function_call(db: AsyncSession, name: str, *args: Any) -> list[dict]:  # noqa: ANN401
    function = getattr(func, name).__call__(*args)
    stmt = select(text('*')).select_from(function)
    result = await db.execute(stmt)
    return [row._asdict() for row in result.all()]


async def get_administrated_offices(db: AsyncSession, user_id: int) -> list[dict]:
    return await function_call(db, 'get_administrated_offices', user_id)
