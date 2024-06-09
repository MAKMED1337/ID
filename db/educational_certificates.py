from datetime import datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base
from .functions import select_all


class EducationalCertificates(Base):
    __tablename__ = 'educational_certificates'

    id: Mapped[int] = mapped_column(primary_key=True)
    issuer: Mapped[int]
    holder: Mapped[int]
    issue_date: Mapped[datetime]
    kind: Mapped[int]

    @staticmethod
    async def get(db: AsyncSession, user_id: int) -> list[dict]:
        assert type(user_id) == int  # noqa: S101, E721
        return await select_all(db, text('educational_certificates_view'), text(f'holder = {user_id}'))
