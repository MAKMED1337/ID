from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jwt.exceptions import InvalidTokenError
from pydantic import BaseModel

from db import Accounts

from . import jwt_helper
from .config import app
from .helper import DB


class Token(BaseModel):
    id: int


oauth2_scheme = OAuth2PasswordBearer(tokenUrl='login')


async def get_user(token: Annotated[str, Depends(oauth2_scheme)]) -> int:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail='Could not validate credentials',
        headers={'WWW-Authenticate': 'Bearer'},
    )
    try:
        payload = jwt_helper.decode(token)
        token_data = Token.model_validate(payload)
    except InvalidTokenError:
        raise credentials_exception from None

    user_id = token_data.id
    if user_id is None:
        raise credentials_exception
    return user_id


@app.post('/login')
async def login_for_access_token(form_data: Annotated[OAuth2PasswordRequestForm, Depends()], db: DB) -> str:
    user_id = await Accounts.find_account(db, form_data.username, form_data.password)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Incorrect username or password',
            headers={'WWW-Authenticate': 'Bearer'},
        )

    token = Token(id=user_id)
    return jwt_helper.create_access_token(data=token.model_dump())
