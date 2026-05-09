"""Bookstore REST API.

Endpoints (per spec):
  GET    /books            list all books (Name, Author, ISBN, Price)
  POST   /book/{book_id}   add a new book
  PUT    /book/{book_id}   update existing book's price
  DELETE /book/{book_id}   delete a book

Plus operational endpoints:
  GET    /health           liveness/readiness for K8s probes
  GET    /metrics          Prometheus scrape target (Phase 8)

Storage is an in-memory dict — data is lost on pod restart. That matches the
spec ("simple REST API"). Swap in Postgres later if persistence matters.
"""

import logging
import sys
from typing import Dict

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
from starlette.requests import Request
import time


# ─── Logging — JSON to stdout so Filebeat/ELK can parse it (Phase 8) ───
try:
    from pythonjsonlogger import jsonlogger
    _handler = logging.StreamHandler(sys.stdout)
    _handler.setFormatter(jsonlogger.JsonFormatter(
        fmt="%(asctime)s %(levelname)s %(name)s %(message)s"
    ))
    logging.basicConfig(level=logging.INFO, handlers=[_handler])
except ImportError:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("bookstore")


# ─── Metrics — exposed at /metrics for Prometheus ──────────────────────
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "handler", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration",
    ["method", "handler"],
)


# ─── Models ────────────────────────────────────────────────────────────
class Book(BaseModel):
    name: str = Field(..., min_length=1, examples=["The Pragmatic Programmer"])
    author: str = Field(..., min_length=1, examples=["Andy Hunt"])
    isbn: str = Field(..., min_length=10, max_length=17, examples=["978-0135957059"])
    price: float = Field(..., gt=0, examples=[42.99])


class PriceUpdate(BaseModel):
    price: float = Field(..., gt=0)


# ─── App + state ───────────────────────────────────────────────────────
app = FastAPI(title="Bookstore API", version="1.0.0")
books: Dict[int, Book] = {
    1: Book(name="The Pragmatic Programmer", author="Andy Hunt",
            isbn="978-0135957059", price=42.99),
    2: Book(name="Designing Data-Intensive Applications", author="Martin Kleppmann",
            isbn="978-1449373320", price=49.95),
    3: Book(name="Clean Code", author="Robert C. Martin",
            isbn="978-0132350884", price=37.50),
}


# ─── Metrics middleware ────────────────────────────────────────────────
@app.middleware("http")
async def track_metrics(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start
    handler = request.url.path
    REQUESTS.labels(request.method, handler, response.status_code).inc()
    LATENCY.labels(request.method, handler).observe(duration)
    return response


# ─── Endpoints — required by spec ──────────────────────────────────────
@app.get("/books", response_model=Dict[int, Book])
def list_books():
    """List all books in the bookstore."""
    return books


@app.post("/book/{book_id}", status_code=status.HTTP_201_CREATED)
def add_book(book_id: int, book: Book):
    """Add a new book. Fails if book_id already exists."""
    if book_id in books:
        raise HTTPException(409, f"Book {book_id} already exists; use PUT to update")
    books[book_id] = book
    log.info("book added", extra={"book_id": book_id, "isbn": book.isbn})
    return {"book_id": book_id, "book": book}


@app.put("/book/{book_id}")
def update_price(book_id: int, update: PriceUpdate):
    """Update the price of an existing book."""
    if book_id not in books:
        raise HTTPException(404, f"Book {book_id} not found")
    old_price = books[book_id].price
    books[book_id].price = update.price
    log.info("book price updated",
             extra={"book_id": book_id, "old": old_price, "new": update.price})
    return {"book_id": book_id, "book": books[book_id]}


@app.delete("/book/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_book(book_id: int):
    """Delete a book by ID."""
    if book_id not in books:
        raise HTTPException(404, f"Book {book_id} not found")
    del books[book_id]
    log.info("book deleted", extra={"book_id": book_id})
    return None


# ─── Operational endpoints ─────────────────────────────────────────────
@app.get("/health")
def health():
    """K8s liveness + readiness probe target."""
    return {"status": "ok", "books_count": len(books)}


@app.get("/metrics")
def metrics():
    """Prometheus scrape target."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
