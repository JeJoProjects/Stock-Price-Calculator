"""Unit tests for stock search (offline mode)."""

import json
import pytest
from pathlib import Path
from py_app.core.stock_search import StockSearcher, StockResult


@pytest.fixture
def searcher_with_data(tmp_path, monkeypatch):
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    tickers = [
        {"symbol": "AAPL", "name": "Apple Inc.", "exchange": "NASDAQ"},
        {"symbol": "AMZN", "name": "Amazon.com Inc.", "exchange": "NASDAQ"},
        {"symbol": "MSFT", "name": "Microsoft Corporation", "exchange": "NASDAQ"},
        {"symbol": "GOOGL", "name": "Alphabet Inc.", "exchange": "NASDAQ"},
        {"symbol": "TSLA", "name": "Tesla Inc.", "exchange": "NASDAQ"},
        {"symbol": "AAL", "name": "American Airlines Group", "exchange": "NASDAQ"},
        {"symbol": "AMD", "name": "Advanced Micro Devices", "exchange": "NASDAQ"},
        {"symbol": "BA", "name": "Boeing Company", "exchange": "NYSE"},
    ]
    with open(data_dir / "us_tickers.json", "w") as f:
        json.dump(tickers, f)

    monkeypatch.setattr("py_app.core.stock_search.DATA_DIR", data_dir)
    monkeypatch.setattr("py_app.core.stock_search.POLYGON_API_KEY", "")
    monkeypatch.setattr("py_app.core.stock_search.ALPHA_VANTAGE_KEY", "")

    s = StockSearcher()
    return s


class TestOfflineSearch:
    def test_search_by_symbol(self, searcher_with_data):
        results = searcher_with_data.search("AAPL")
        assert len(results) == 1
        assert results[0].symbol == "AAPL"
        assert results[0].name == "Apple Inc."

    def test_search_by_partial_symbol(self, searcher_with_data):
        results = searcher_with_data.search("AA")
        symbols = [r.symbol for r in results]
        assert "AAPL" in symbols
        assert "AAL" in symbols

    def test_search_by_company_name(self, searcher_with_data):
        results = searcher_with_data.search("Tesla")
        assert len(results) == 1
        assert results[0].symbol == "TSLA"

    def test_search_case_insensitive(self, searcher_with_data):
        results = searcher_with_data.search("apple")
        assert len(results) == 1
        assert results[0].symbol == "AAPL"

    def test_empty_query(self, searcher_with_data):
        results = searcher_with_data.search("")
        assert len(results) == 0

    def test_no_match(self, searcher_with_data):
        results = searcher_with_data.search("ZZZZZ")
        assert len(results) == 0

    def test_result_limit(self, searcher_with_data, monkeypatch):
        monkeypatch.setattr("py_app.core.stock_search.SEARCH_RESULT_LIMIT", 2)
        results = searcher_with_data.search("A")
        assert len(results) <= 2

    def test_exchange_field(self, searcher_with_data):
        results = searcher_with_data.search("BA")
        ba = [r for r in results if r.symbol == "BA"]
        assert len(ba) == 1
        assert ba[0].exchange == "NYSE"
