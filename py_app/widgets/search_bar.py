"""Search bar with debounced autocomplete dropdown for US stock symbols."""

from PySide6.QtWidgets import (
    QWidget, QHBoxLayout, QLineEdit, QPushButton, QLabel,
)
from PySide6.QtCore import Qt, QTimer, Signal

from py_app.core.stock_search import StockSearcher, StockResult
from py_app.widgets.autocomplete_list import AutocompleteDropdown
from py_app.config import SEARCH_DEBOUNCE_MS


class SearchBar(QWidget):
    stock_selected = Signal(str, str)  # symbol, company_name

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setObjectName("searchBarContainer")
        self.setFixedHeight(52)
        self._searcher = StockSearcher()

        layout = QHBoxLayout(self)
        layout.setContentsMargins(24, 6, 24, 6)
        layout.setSpacing(0)

        self._search_icon = QLabel("\U0001f50d")
        self._search_icon.setFixedWidth(28)
        self._search_icon.setAlignment(Qt.AlignCenter)
        layout.addWidget(self._search_icon)

        self._input = QLineEdit()
        self._input.setObjectName("searchInput")
        self._input.setPlaceholderText("Search symbol or company name...")
        self._input.setClearButtonEnabled(False)
        layout.addWidget(self._input)

        self._clear_btn = QPushButton("✕")
        self._clear_btn.setObjectName("searchClearBtn")
        self._clear_btn.setFixedSize(28, 28)
        self._clear_btn.setVisible(False)
        self._clear_btn.clicked.connect(self._on_clear)
        layout.addWidget(self._clear_btn)

        self._dropdown = AutocompleteDropdown(self.window())
        self._dropdown.item_selected.connect(self._on_item_selected)

        self._debounce_timer = QTimer()
        self._debounce_timer.setSingleShot(True)
        self._debounce_timer.setInterval(SEARCH_DEBOUNCE_MS)
        self._debounce_timer.timeout.connect(self._do_search)

        self._input.textChanged.connect(self._on_text_changed)
        self._input.installEventFilter(self)

    def _on_text_changed(self, text: str):
        self._clear_btn.setVisible(bool(text))
        if text.strip():
            self._debounce_timer.start()
        else:
            self._debounce_timer.stop()
            self._dropdown.hide()

    def _do_search(self):
        query = self._input.text().strip()
        if not query:
            return
        results = self._searcher.search(query)
        if results:
            self._dropdown.set_results(results)
            pos = self._input.mapToGlobal(self._input.rect().bottomLeft())
            self._dropdown.show_at(pos, self._input.width())
        else:
            self._dropdown.hide()

    def _on_item_selected(self, symbol: str, name: str):
        self._input.setText(symbol)
        self._dropdown.hide()
        self.stock_selected.emit(symbol, name)

    def _on_clear(self):
        self._input.clear()
        self._dropdown.hide()
        self._input.setFocus()

    def eventFilter(self, obj, event):
        if obj is self._input and event.type() == event.Type.KeyPress:
            key = event.key()
            if key == Qt.Key_Down and self._dropdown.isVisible():
                self._dropdown.move_selection(1)
                return True
            elif key == Qt.Key_Up and self._dropdown.isVisible():
                self._dropdown.move_selection(-1)
                return True
            elif key in (Qt.Key_Return, Qt.Key_Enter) and self._dropdown.isVisible():
                self._dropdown.confirm_selection()
                return True
            elif key == Qt.Key_Escape:
                self._dropdown.hide()
                return True
        return super().eventFilter(obj, event)
