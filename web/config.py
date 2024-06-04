from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from db import start as start_db
from db import stop as stop_db


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    await start_db()
    yield
    await stop_db()


app = FastAPI(lifespan=lifespan)
