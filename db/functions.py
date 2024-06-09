from typing import Any

from sqlalchemy import ColumnExpressionArgument, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

document_tables = {
    1: 'international_passports',
    2: 'marriage_certificates_view',
    3: 'visas',
    4: 'birth_certificates',
    5: 'death_certificates',
    6: 'divorce_certificates_view',
    7: 'drivers_licences',
    8: 'passports',
    9: 'educational_certificates_view',
}


async def select_all(db: AsyncSession, source: Any, *where: ColumnExpressionArgument[bool]) -> list[dict]:  # noqa: ANN401, I have no time to find the correct type
    stmt = select(text('*')).select_from(source).where(*where)
    result = await db.execute(stmt)
    return [row._asdict() for row in result.all()]


async def function_call(db: AsyncSession, name: str, *args: Any) -> list[dict]:  # noqa: ANN401
    function = getattr(func, name).__call__(*args)
    return await select_all(db, function)


async def get_administrated_offices(db: AsyncSession, user_id: int) -> list[dict]:
    return await function_call(db, 'get_administrated_offices', user_id)


async def get_issued_documents_types(db: AsyncSession, office_id: int) -> list[dict]:
    return await function_call(db, 'get_issued_documents_types', office_id)


# This function should be avoided at all cost
async def find_document(db: AsyncSession, document_type: int, id: int) -> dict | None:
    assert type(id) == int  # noqa: E721, S101, at least some check for stupidity

    table = document_tables[document_type]
    result = await db.execute(text(f'SELECT * FROM {table} WHERE id = {id}'))  # noqa: S608
    document = result.first()
    return document._asdict() if document is not None else None


# This is the wrong place to do so, but ...
async def get_marriage_certificates(db: AsyncSession, user_id: int) -> list[dict]:
    assert type(user_id) == int  # noqa: E721, S101, at least some check for stupidity
    return await select_all(db, text('marriage_certificates_view'), text(f'first_person = {user_id} OR second_person = {user_id}'))


# This is the wrong place to do so, but ...
async def get_birth_certificates(db: AsyncSession, user_id: int) -> list[dict]:
    assert type(user_id) == int  # noqa: E721, S101, at least some check for stupidity
    return await select_all(db, text('birth_certificates'), text(f'person = {user_id}'))


# This is the wrong place to do so, but ...
async def get_death_certificates(db: AsyncSession, user_id: int) -> list[dict]:
    assert type(user_id) == int  # noqa: E721, S101, at least some check for stupidity
    return await select_all(db, text('death_certificates'), text(f'person = {user_id}'))


# This is the wrong place to do so, but ...
async def get_drivers_licences(db: AsyncSession, user_id: int) -> list[dict]:
    assert type(user_id) == int  # noqa: E721, S101, at least some check for stupidity
    return await select_all(db, text('drivers_licences'), text(f'person = {user_id}'))


# This is the wrong place to do so, but ...
async def get_divorce_certificates(db: AsyncSession, user_id: int) -> list[dict]:
    assert type(user_id) == int  # noqa: E721, S101, at least some check for stupidity
    return await select_all(db, text('divorce_certificates_view'), text(f'first_person = {user_id} OR second_person = {user_id}'))


async def invalidate_document(db: AsyncSession, document_type: int, id: int) -> None:
    assert type(id) == int  # noqa: E721, S101, at least some check for stupidity

    table = document_tables[document_type]
    await db.execute(text(f'UPDATE {table} SET invalidated = TRUE WHERE id = {id}'))  # noqa: S608
