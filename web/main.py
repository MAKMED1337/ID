from fastapi.staticfiles import StaticFiles

from . import authorization, documents  # noqa: F401
from .config import app

app.mount('/static', StaticFiles(directory='static'), name='static')
