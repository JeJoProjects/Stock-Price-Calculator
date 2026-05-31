"""Stock symbol search bridge — called by StockCalc C++ app.

Usage: python scripts/search_symbols.py <query>
Output: JSON array of {symbol, name, exchange} objects, one per line.

Tries Yahoo Finance first (no API key), falls back to offline data.
"""
import sys
import json
import os
import urllib.request
import urllib.parse

def search_yahoo(query, max_results=12):
    """Search via Yahoo Finance autocomplete (no API key needed)."""
    url = "https://query2.finance.yahoo.com/v1/finance/search"
    params = urllib.parse.urlencode({
        "q": query,
        "quotesCount": max_results,
        "newsCount": 0,
        "listsCount": 0,
        "enableFuzzyQuery": "false",
        "quotesQueryId": "tss_match_phrase_query",
    })
    req = urllib.request.Request(
        f"{url}?{params}",
        headers={"User-Agent": "StockCalc/2.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode())
        results = []
        for q in data.get("quotes", []):
            if q.get("quoteType") not in ("EQUITY", "ETF"):
                continue
            results.append({
                "symbol": q.get("symbol", ""),
                "name": q.get("shortname") or q.get("longname", ""),
                "exchange": q.get("exchange", ""),
            })
        return results[:max_results]
    except Exception:
        return None

def search_offline(query, max_results=12):
    """Fall back to bundled JSON ticker data."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_path = os.path.join(script_dir, "..", "data", "us_tickers_full.json")
    try:
        with open(data_path, "r") as f:
            tickers = json.load(f)
    except Exception:
        return []

    q = query.lower()
    scored = []
    for t in tickers:
        sym = t.get("symbol", "").lower()
        name = t.get("name", "").lower()
        if sym.startswith(q):
            scored.append((100, t))
        elif q in sym:
            scored.append((50, t))
        elif q in name:
            scored.append((25, t))

    scored.sort(key=lambda x: -x[0])
    return [s[1] for s in scored[:max_results]]

def main():
    if len(sys.argv) < 2:
        print("[]")
        return

    query = " ".join(sys.argv[1:]).strip()
    if not query:
        print("[]")
        return

    results = search_yahoo(query)
    if results is None:
        results = search_offline(query)

    print(json.dumps(results))

if __name__ == "__main__":
    main()
