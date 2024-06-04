from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from jwt.exceptions import InvalidTokenError
from pydantic import BaseModel

from db import Accounts

from . import jwt_helper
from .config import app
from .helper import DB

app.mount('/static', StaticFiles(directory='static'), name='static')


class ReturnToken(BaseModel):
    access_token: str
    token_type: str


class Token(BaseModel):
    username: str
    password: str


oauth2_scheme = OAuth2PasswordBearer(tokenUrl='token')


async def get_user(db: DB, username: str, password: str) -> int | None:
    return await Accounts.login(db, username, password)


async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)], db: DB) -> int:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail='Could not validate credentials',
        headers={'WWW-Authenticate': 'Bearer'},
    )
    try:
        payload = jwt_helper.decode(token)
        token_data = Token.model_validate(payload)
    except InvalidTokenError as e:
        raise credentials_exception from e

    user = await get_user(db, token_data.username, token_data.password)
    if user is None:
        raise credentials_exception
    return user


@app.post('/login')
async def login_for_access_token(form_data: Annotated[OAuth2PasswordRequestForm, Depends()], db: DB) -> ReturnToken:
    user = await get_user(db, form_data.username, form_data.password)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Incorrect username or password',
            headers={'WWW-Authenticate': 'Bearer'},
        )

    token = Token(username=form_data.username, password=form_data.password)
    access_token = jwt_helper.create_access_token(data=token.model_dump())
    return ReturnToken(access_token=access_token, token_type='bearer')  # noqa: S106


@app.get('/users/me/')
async def read_users_me(
    current_user: Annotated[int, Depends(get_current_user)],
) -> int:
    return current_user
