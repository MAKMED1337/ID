from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from .config import Base


class Administrators(Base):
    __tablename__ = 'administrators'

    user_id: Mapped[int] = mapped_column(ForeignKey('accounts.id'), primary_key=True)
    office_id: Mapped[int] = mapped_column(primary_key=True)
