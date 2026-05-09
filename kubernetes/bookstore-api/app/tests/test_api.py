"""Pytest suite for the bookstore API.

Run from k8s-devops-project/kubernetes/bookstore-api/app/:

    pip install -r requirements.txt pytest httpx
    pytest tests/ -v

The Jenkins pipeline runs these in the `python` container before building the image.
"""

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client():
    """Fresh seed data per test (avoids state bleed between tests).

    We reset the books dict in-place rather than reloading main.py — reload
    re-runs the module body, which re-registers Prometheus metrics and crashes
    with 'Duplicated timeseries' errors.
    """
    import main
    main.books.clear()
    main.books.update(main._seed())
    return TestClient(main.app)


# ─── /books ─────────────────────────────────────────────────────────
def test_list_books_returns_seed_data(client):
    r = client.get("/books")
    assert r.status_code == 200
    data = r.json()
    assert "1" in data and "2" in data and "3" in data
    assert data["1"]["author"] == "Andy Hunt"


# ─── POST /book/{id} ────────────────────────────────────────────────
def test_add_book_succeeds(client):
    payload = {
        "name": "Refactoring",
        "author": "Martin Fowler",
        "isbn": "978-0134757599",
        "price": 39.99,
    }
    r = client.post("/book/100", json=payload)
    assert r.status_code == 201

    # Confirm it's actually persisted
    r2 = client.get("/books")
    assert "100" in r2.json()
    assert r2.json()["100"]["isbn"] == "978-0134757599"


def test_add_book_conflict_on_existing_id(client):
    payload = {"name": "x", "author": "y", "isbn": "1234567890", "price": 1.0}
    r = client.post("/book/1", json=payload)   # ID 1 already in seed data
    assert r.status_code == 409


def test_add_book_validation_rejects_negative_price(client):
    payload = {"name": "x", "author": "y", "isbn": "1234567890", "price": -5}
    r = client.post("/book/200", json=payload)
    assert r.status_code == 422


# ─── PUT /book/{id} ─────────────────────────────────────────────────
def test_update_price_succeeds(client):
    r = client.put("/book/1", json={"price": 99.99})
    assert r.status_code == 200
    assert r.json()["book"]["price"] == 99.99


def test_update_nonexistent_book_returns_404(client):
    r = client.put("/book/9999", json={"price": 99.99})
    assert r.status_code == 404


def test_update_rejects_zero_price(client):
    r = client.put("/book/1", json={"price": 0})
    assert r.status_code == 422


# ─── DELETE /book/{id} ──────────────────────────────────────────────
def test_delete_book_succeeds(client):
    r = client.delete("/book/2")
    assert r.status_code == 204

    r2 = client.get("/books")
    assert "2" not in r2.json()


def test_delete_nonexistent_book_returns_404(client):
    r = client.delete("/book/9999")
    assert r.status_code == 404


# ─── Operational ────────────────────────────────────────────────────
def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["books_count"] == 3


def test_metrics_exposes_prometheus_format(client):
    # Hit a handler so the counter has a value
    client.get("/books")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
    assert "http_request_duration_seconds" in r.text
