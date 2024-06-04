from sqlalchemy import ForeignKey, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base


class Accounts(Base):
    __tablename__ = 'accounts'

    id: Mapped[int] = mapped_column(ForeignKey('people.id'), primary_key=True)
    login: Mapped[str]
    hashed_password: Mapped[str]

    @staticmethod
    async def login(db: AsyncSession, username: str, password: str) -> int | None:
        return await db.execute(select(func.login(username, password)))  # type: ignore[return-value]
