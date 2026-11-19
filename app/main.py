"""PayFlow transaction-status service.

A small Flask API that stands in for a fintech microservice. The point of
this repo is the delivery pipeline around it, so the app stays simple:
health/readiness probes, Prometheus metrics, JSON logs, and a tiny
in-memory transaction store.
"""
import json
import logging
import os
import socket
import time
import uuid

from flask import Flask, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = os.getenv("APP_VERSION", "dev")
START_TIME = time.time()

REQUESTS = Counter(
    "payflow_http_requests_total", "HTTP requests", ["method", "endpoint", "status"]
)
LATENCY = Histogram(
    "payflow_http_request_duration_seconds", "Request latency", ["endpoint"]
)
TXN_CREATED = Counter("payflow_transactions_created_total", "Transactions created")

VALID_STATUSES = {"pending", "settled", "declined"}


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "msg": record.getMessage(),
            "version": APP_VERSION,
        }
        payload.update(getattr(record, "extra_fields", {}))
        return json.dumps(payload)


def _configure_logging():
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    log = logging.getLogger("payflow")
    log.handlers = [handler]
    log.setLevel(os.getenv("LOG_LEVEL", "INFO"))
    log.propagate = False
    return log


def create_app():
    app = Flask(__name__)
    log = _configure_logging()
    store = {}
    app.config["READY"] = True

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()

    @app.after_request
    def _record(resp):
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
        if endpoint not in ("/metrics", "/health"):
            level = logging.ERROR if resp.status_code >= 500 else logging.INFO
            log.log(level, "request", extra={"extra_fields": {
                "method": request.method,
                "path": request.path,
                "status": resp.status_code,
            }})
        return resp

    @app.get("/health")
    def health():
        """Liveness: the process is up."""
        return jsonify(status="ok", version=APP_VERSION,
                       uptime_s=round(time.time() - START_TIME, 1),
                       host=socket.gethostname())

    @app.get("/ready")
    def ready():
        """Readiness: safe to receive traffic."""
        if not app.config["READY"]:
            return jsonify(status="not-ready"), 503
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

    @app.post("/api/v1/transactions")
    def create_txn():
        body = request.get_json(silent=True) or {}
        amount = body.get("amount")
        currency = body.get("currency", "PKR")
        if isinstance(amount, bool) or not isinstance(amount, (int, float)) or amount <= 0:
            return jsonify(error="amount must be a positive number"), 400
        if not isinstance(currency, str) or len(currency) != 3:
            return jsonify(error="currency must be a 3-letter code"), 400
        txn = {
            "id": str(uuid.uuid4()),
            "amount": round(float(amount), 2),
            "currency": currency.upper(),
            "status": "pending",
            "created_at": int(time.time()),
        }
        store[txn["id"]] = txn
        TXN_CREATED.inc()
        return jsonify(txn), 201

    @app.get("/api/v1/transactions/<txn_id>")
    def get_txn(txn_id):
        txn = store.get(txn_id)
        if not txn:
            return jsonify(error="not found"), 404
        return jsonify(txn)

    @app.patch("/api/v1/transactions/<txn_id>")
    def update_txn(txn_id):
        txn = store.get(txn_id)
        if not txn:
            return jsonify(error="not found"), 404
        status = (request.get_json(silent=True) or {}).get("status")
        if status not in VALID_STATUSES:
            return jsonify(error=f"status must be one of {sorted(VALID_STATUSES)}"), 400
        txn["status"] = status
        return jsonify(txn)

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
