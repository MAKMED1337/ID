from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base


class InternationalPassports(Base):
    __tablename__ = 'international_passports'

    id: Mapped[int] = mapped_column(primary_key=True)
    original_surname: Mapped[str]
    original_name: Mapped[str]
    en_name: Mapped[str]
    en_surname: Mapped[str]
    issue_date: Mapped[datetime]
    expiration_date: Mapped[datetime]
    sex: Mapped[str]
    issuer: Mapped[int]
    passport_owner: Mapped[int]

    @staticmethod
    async def get(db: AsyncSession, user_id: int) -> list['InternationalPassports']:
        result = await db.execute(select(InternationalPassports).where(InternationalPassports.passport_owner == user_id))
        return result.scalars()  # type: ignore[return-type]
