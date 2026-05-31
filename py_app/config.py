"""Application-wide constants, color tokens, and configuration."""

import os
from pathlib import Path

APP_NAME = "StockCalc"
APP_VERSION = "1.0.0"

BASE_DIR = Path(__file__).resolve().parent
THEME_DIR = BASE_DIR / "theme"
ASSETS_DIR = BASE_DIR / "assets"
DATA_DIR = BASE_DIR / "data"

# --- TradingView-inspired color tokens ---
COLORS = {
    "bg_primary": "#131722",
    "bg_secondary": "#1e222d",
    "bg_input": "#2a2e39",
    "bg_hover": "#363c4e",
    "border": "#363c4e",
    "text_primary": "#d1d4dc",
    "text_muted": "#787b86",
    "accent_blue": "#2962ff",
    "profit_green": "#089981",
    "loss_red": "#f23645",
    "white": "#ffffff",
}

# --- Typography ---
FONT_FAMILY = "Segoe UI"
FONT_MONO = "Consolas"
FONT_SIZES = {
    "badge": 11,
    "label": 11,
    "body": 13,
    "card_title": 15,
    "main_title": 17,
    "stat_value": 16,
}

# --- Layout ---
PANEL_WIDTH = 280
PANEL_MIN_HEIGHT = 440
TOP_BAR_HEIGHT = 48
SEARCH_BAR_HEIGHT = 52
STATS_BAR_HEIGHT = 72
BORDER_RADIUS_INPUT = 6
BORDER_RADIUS_CARD = 12

# --- API Keys (read from environment or config file) ---
POLYGON_API_KEY = os.environ.get("POLYGON_API_KEY", "")
ALPHA_VANTAGE_KEY = os.environ.get("ALPHA_VANTAGE_KEY", "")

# --- API Endpoints ---
POLYGON_TICKER_SEARCH = "https://api.polygon.io/v3/reference/tickers"
ALPHA_VANTAGE_SEARCH = "https://www.alphavantage.co/query"

SEARCH_DEBOUNCE_MS = 300
SEARCH_RESULT_LIMIT = 12
