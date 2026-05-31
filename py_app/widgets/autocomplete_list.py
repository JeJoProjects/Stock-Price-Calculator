"""Floating autocomplete dropdown list for stock symbol search."""

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QListWidget, QListWidgetItem, QLabel,
    QHBoxLayout, QFrame,
)
from PySide6.QtCore import Qt, Signal, QPoint
from PySide6.QtGui import QFont

from py_app.core.stock_search import StockResult
from py_app.config import COLORS


class AutocompleteDropdown(QWidget):
    item_selected = Signal(str, str)  # symbol, name

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("autocompleteDropdown")
        self.setWindowFlags(Qt.Popup | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint)
        self.setAttribute(Qt.WA_TranslucentBackground, False)
        self.setMaximumHeight(340)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 4, 0, 4)
        layout.setSpacing(0)

        self._list = QListWidget()
        self._list.setObjectName("autocompleteList")
        self._list.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self._list.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self._list.itemClicked.connect(self._on_click)
        layout.addWidget(self._list)

        self._footer = QLabel("  ↑↓ navigate  •  Enter select  •  Esc close")
        self._footer.setStyleSheet(f"font-size: 11px; color: {COLORS['text_muted']}; padding: 6px 12px;")
        layout.addWidget(self._footer)

        self._results: list[StockResult] = []

    def set_results(self, results: list[StockResult]):
        self._results = results
        self._list.clear()
        for r in results:
            item = QListWidgetItem()
            item.setData(Qt.UserRole, r)
            self._list.addItem(item)

            row = QWidget()
            row_layout = QHBoxLayout(row)
            row_layout.setContentsMargins(12, 4, 12, 4)
            row_layout.setSpacing(12)

            sym_label = QLabel(r.symbol)
            sym_label.setFixedWidth(80)
            sym_label.setFont(QFont("Consolas", 13, QFont.Bold))
            sym_label.setStyleSheet("color: #ffffff;")
            row_layout.addWidget(sym_label)

            name_label = QLabel(r.name)
            name_label.setStyleSheet("color: #d1d4dc; font-size: 13px;")
            row_layout.addWidget(name_label, 1)

            if r.exchange:
                badge = QLabel(r.exchange)
                badge.setStyleSheet(
                    f"color: {COLORS['text_muted']}; font-size: 11px; "
                    f"background-color: {COLORS['bg_hover']}; "
                    "border-radius: 3px; padding: 2px 6px;"
                )
                badge.setAlignment(Qt.AlignCenter)
                row_layout.addWidget(badge)

            item.setSizeHint(row.sizeHint())
            self._list.setItemWidget(item, row)

        if results:
            self._list.setCurrentRow(0)

    def show_at(self, pos: QPoint, width: int):
        self.setFixedWidth(width)
        self.move(pos)
        self.show()
        self.raise_()

    def move_selection(self, delta: int):
        count = self._list.count()
        if count == 0:
            return
        current = self._list.currentRow()
        new_row = max(0, min(count - 1, current + delta))
        self._list.setCurrentRow(new_row)

    def confirm_selection(self):
        current = self._list.currentItem()
        if current:
            r = current.data(Qt.UserRole)
            self.item_selected.emit(r.symbol, r.name)

    def _on_click(self, item: QListWidgetItem):
        r = item.data(Qt.UserRole)
        if r:
            self.item_selected.emit(r.symbol, r.name)
