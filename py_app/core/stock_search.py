"""Stock symbol search with 3-tier fallback: Polygon -> AlphaVantage -> offline JSON."""

import json
import threading
from dataclasses import dataclass
from pathlib import Path

import requests

from py_app.config import (
    POLYGON_API_KEY,
    ALPHA_VANTAGE_KEY,
    POLYGON_TICKER_SEARCH,
    ALPHA_VANTAGE_SEARCH,
    SEARCH_RESULT_LIMIT,
    DATA_DIR,
)


@dataclass
class StockResult:
    symbol: str
    name: str
    exchange: str


class StockSearcher:
    def __init__(self):
        self._offline_data: list[dict] | None = None
        self._lock = threading.Lock()

    def search(self, query: str) -> list[StockResult]:
        query = query.strip()
        if not query:
            return []

        if POLYGON_API_KEY:
            try:
                return self._search_polygon(query)
            except Exception:
                pass

        if ALPHA_VANTAGE_KEY:
            try:
                return self._search_alpha_vantage(query)
            except Exception:
                pass

        return self._search_offline(query)

    def _search_polygon(self, query: str) -> list[StockResult]:
        resp = requests.get(
            POLYGON_TICKER_SEARCH,
            params={
                "search": query,
                "active": "true",
                "market": "stocks",
                "locale": "us",
                "limit": SEARCH_RESULT_LIMIT,
                "apiKey": POLYGON_API_KEY,
            },
            timeout=5,
        )
        resp.raise_for_status()
        data = resp.json()
        results = []
        for item in data.get("results", []):
            results.append(StockResult(
                symbol=item.get("ticker", ""),
                name=item.get("name", ""),
                exchange=item.get("primary_exchange", "").replace("XNAS", "NASDAQ").replace("XNYS", "NYSE"),
            ))
        return results[:SEARCH_RESULT_LIMIT]

    def _search_alpha_vantage(self, query: str) -> list[StockResult]:
        resp = requests.get(
            ALPHA_VANTAGE_SEARCH,
            params={
                "function": "SYMBOL_SEARCH",
                "keywords": query,
                "apikey": ALPHA_VANTAGE_KEY,
            },
            timeout=5,
        )
        resp.raise_for_status()
        data = resp.json()
        results = []
        for item in data.get("bestMatches", []):
            region = item.get("4. region", "")
            if region != "United States":
                continue
            results.append(StockResult(
                symbol=item.get("1. symbol", ""),
                name=item.get("2. name", ""),
                exchange=item.get("3. type", "Equity"),
            ))
        return results[:SEARCH_RESULT_LIMIT]

    def _load_offline_data(self):
        if self._offline_data is not None:
            return
        json_path = DATA_DIR / "us_tickers.json"
        if json_path.exists():
            with open(json_path, "r", encoding="utf-8") as f:
                self._offline_data = json.load(f)
        else:
            self._offline_data = []

    def _search_offline(self, query: str) -> list[StockResult]:
        with self._lock:
            self._load_offline_data()

        query_lower = query.lower()
        results = []
        for item in self._offline_data or []:
            sym = item.get("symbol", "")
            name = item.get("name", "")
            if query_lower in sym.lower() or query_lower in name.lower():
                results.append(StockResult(
                    symbol=sym,
                    name=name,
                    exchange=item.get("exchange", ""),
                ))
                if len(results) >= SEARCH_RESULT_LIMIT:
                    break
        return results
