from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base


class EducationalCertificates(Base):
    __tablename__ = 'educational_certificates'

    id: Mapped[int] = mapped_column(primary_key=True)
    issuer: Mapped[int]
    holder: Mapped[int]
    issue_date: Mapped[datetime]
    kind: Mapped[int]

    @staticmethod
    async def get(db: AsyncSession, user_id: int) -> list['EducationalCertificates']:
        result = await db.execute(select(EducationalCertificates).where(EducationalCertificates.holder == user_id))
        return result.scalars()  # type: ignore[return-type]
