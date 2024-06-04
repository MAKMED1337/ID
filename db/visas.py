from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base
from .international_passports import InternationalPassports


class Visas(Base):
    __tablename__ = 'visas'

    id: Mapped[int] = mapped_column(primary_key=True)
    type: Mapped[int]
    passport: Mapped[int]
    issue_date: Mapped[datetime]
    inner_issuer: Mapped[int]
    country: Mapped[str]

    @staticmethod
    async def get(db: AsyncSession, user_id: int) -> list['Visas']:
        stmt = select(Visas) \
            .join(InternationalPassports, Visas.passport == InternationalPassports.id) \
            .where(InternationalPassports.passport_owner == user_id)
        result = await db.execute(stmt)
        return result.scalars()  # type: ignore[return-type]
