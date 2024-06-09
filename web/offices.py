from typing import Annotated

from fastapi import Depends, HTTPException, status
from pydantic import BaseModel

from db import document_tables, get_administrated_offices, get_issued_documents_types
from db import find_document as find_document_db

from .authorization import get_user
from .config import app
from .helper import DB


# checks if the user has an access
async def get_office(office_id: int, user: Annotated[int, Depends(get_user)], db: DB) -> int:
    offices = await get_administrated_offices(db, user)
    if not any(office['id'] == office_id for office in offices):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='You do not have access to this office',
        )
    return office_id


async def get_document(document_id: int, office_id: Annotated[int, Depends(get_office)], db: DB) -> int:
    documents = await get_issued_documents_types(db, office_id)
    if not any(document['id'] == document_id for document in documents):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='You do not have access to this document from this office',
        )
    return document_id


@app.get('/offices/access')
async def get_access(user: Annotated[int, Depends(get_user)], db: DB) -> list[dict]:
    return await get_administrated_offices(db, user)


@app.get('/offices/{office_id}/documents')
async def get_documents(office_id: Annotated[int, Depends(get_office)], db: DB) -> list[dict]:
    return await get_issued_documents_types(db, office_id)


class ID(BaseModel):
    id: int


@app.post('/offices/{office_id}/documents/{document_id}/find')
async def find_document(id: ID, document_id: Annotated[int, Depends(get_document)], db: DB) -> dict | None:
    if document_id not in document_tables:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Document type not found',
        )

    return await find_document_db(db, document_id, id.id)
