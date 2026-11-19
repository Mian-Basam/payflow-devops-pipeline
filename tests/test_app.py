import pytest

from app.main import create_app


@pytest.fixture
def client():
    return create_app().test_client()


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json["status"] == "ok"


def test_ready(client):
    assert client.get("/ready").status_code == 200


def test_metrics_exposed(client):
    client.get("/health")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"payflow_http_requests_total" in r.data


def test_transaction_lifecycle(client):
    r = client.post("/api/v1/transactions", json={"amount": 2500, "currency": "pkr"})
    assert r.status_code == 201
    txn = r.json
    assert txn["currency"] == "PKR" and txn["status"] == "pending"

    r = client.patch(f"/api/v1/transactions/{txn['id']}", json={"status": "settled"})
    assert r.status_code == 200 and r.json["status"] == "settled"
    assert client.get(f"/api/v1/transactions/{txn['id']}").json["status"] == "settled"


@pytest.mark.parametrize("body", [
    {}, {"amount": -5}, {"amount": "10"}, {"amount": True},
    {"amount": 5, "currency": "RUPEE"},
])
def test_rejects_bad_input(client, body):
    assert client.post("/api/v1/transactions", json=body).status_code == 400


def test_bad_status(client):
    txn = client.post("/api/v1/transactions", json={"amount": 1}).json
    r = client.patch(f"/api/v1/transactions/{txn['id']}", json={"status": "lost"})
    assert r.status_code == 400


def test_not_found(client):
    assert client.get("/api/v1/transactions/nope").status_code == 404
