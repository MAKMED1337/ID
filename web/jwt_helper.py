from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from pydantic_settings import BaseSettings, SettingsConfigDict


class JWTSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix='JWT_')

    SECRET_KEY: str
    ALGORITHM: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int


settings = JWTSettings()


def encode(payload: dict[str, Any]) -> str:
    return jwt.encode(payload, settings.SECRET_KEY, settings.ALGORITHM)


def decode(payload: str) -> dict[str, Any]:
    return jwt.decode(payload, settings.SECRET_KEY, [settings.ALGORITHM])


def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(UTC) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({'exp': expire})
    return encode(to_encode)
