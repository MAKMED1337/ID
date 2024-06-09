from typing import Any

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

document_tables = {
    1: 'international_passports',
    2: 'marriage_certificates',
    3: 'visas',
    4: 'birth_certificates',
    5: 'death_certificates',
    6: 'divorce_certificates',
    7: 'drivers_licences',
    8: 'passports',
}


async def function_call(db: AsyncSession, name: str, *args: Any) -> list[dict]:  # noqa: ANN401
    function = getattr(func, name).__call__(*args)
    stmt = select(text('*')).select_from(function)
    result = await db.execute(stmt)
    return [row._asdict() for row in result.all()]


async def get_administrated_offices(db: AsyncSession, user_id: int) -> list[dict]:
    return await function_call(db, 'get_administrated_offices', user_id)


async def get_issued_documents_types(db: AsyncSession, office_id: int) -> list[dict]:
    return await function_call(db, 'get_issued_documents_types', office_id)


# this function should be avoided at all cost
async def find_document(db: AsyncSession, document_type: int, id: int) -> dict | None:
    assert type(id) == int  # noqa: E721, S101, at least some check for stupidity

    table = document_tables[document_type]
    result = await db.execute(text(f'SELECT * FROM {table} WHERE id = {id}'))  # noqa: S608
    document = result.first()
    return document._asdict() if document is not None else None
