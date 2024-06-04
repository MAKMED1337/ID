from datetime import datetime

from sqlalchemy.orm import Mapped, mapped_column

from .config import Base


class People(Base):
    __tablename__ = 'people'

    id: Mapped[int] = mapped_column(primary_key=True)
    date_of_birth: Mapped[datetime]
    date_of_death: Mapped[datetime | None]
