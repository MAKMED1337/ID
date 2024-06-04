from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL
from sqlalchemy.ext.asyncio import AsyncAttrs, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase


class DBSettings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False, env_prefix='POSTGRES_')

    user: str
    password: str
    db: str
    host: str = 'localhost'
    port: int = 5432


_settings = DBSettings()
connection_url = URL.create(
    'postgresql+asyncpg',
    _settings.user,
    _settings.password,
    _settings.host,
    _settings.port,
    _settings.db,
)


class Base(
    DeclarativeBase,
    AsyncAttrs,
):
    pass


engine = create_async_engine(connection_url)
make_session = async_sessionmaker(engine, expire_on_commit=False)


async def start() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)


async def stop() -> None:
    await engine.dispose()
