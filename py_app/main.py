"""StockCalc — TradingView-inspired Stock Profit Calculator."""

import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFont

from py_app.windows.main_window import MainWindow
from py_app.config import THEME_DIR


def main():
    app = QApplication(sys.argv)

    app.setFont(QFont("Segoe UI", 13))

    qss_path = THEME_DIR / "dark.qss"
    if qss_path.exists():
        app.setStyleSheet(qss_path.read_text(encoding="utf-8"))

    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
