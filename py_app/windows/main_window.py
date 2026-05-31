"""Main application window — orchestrates all widgets."""

from PySide6.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QScrollArea,
    QFrame, QLabel,
)
from PySide6.QtCore import Qt

from py_app.core.bridge import CalcEngine
from py_app.widgets.top_bar import TopBar
from py_app.widgets.search_bar import SearchBar
from py_app.widgets.purchase_panel import PurchasePanel
from py_app.widgets.combined_stats import CombinedStatsBar
from py_app.config import PANEL_WIDTH


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("StockCalc")
        self.setMinimumSize(700, 620)
        self.resize(960, 680)

        self._engine = CalcEngine()
        self._panels: list[PurchasePanel] = []

        central = QWidget()
        central.setObjectName("centralWidget")
        self.setCentralWidget(central)

        root = QVBoxLayout(central)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(0)

        self._top_bar = TopBar()
        root.addWidget(self._top_bar)

        self._search_bar = SearchBar()
        self._search_bar.stock_selected.connect(self._on_stock_selected)
        root.addWidget(self._search_bar)

        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        self._scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self._scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)

        self._panels_container = QWidget()
        self._panels_layout = QHBoxLayout(self._panels_container)
        self._panels_layout.setContentsMargins(24, 16, 24, 16)
        self._panels_layout.setSpacing(16)
        self._panels_layout.setAlignment(Qt.AlignLeft | Qt.AlignTop)

        self._scroll.setWidget(self._panels_container)
        root.addWidget(self._scroll, 1)

        self._combined_bar = CombinedStatsBar(self._engine)
        self._combined_bar.reset_all_clicked.connect(self._reset_all)
        root.addWidget(self._combined_bar)

        self._add_panel()
        self._rebuild_add_button()

    def _add_panel(self) -> PurchasePanel:
        panel = PurchasePanel(len(self._panels), self._engine)
        panel.values_changed.connect(self._update_combined)
        panel.delete_requested.connect(self._remove_panel)
        self._panels.append(panel)

        insert_pos = self._panels_layout.count() - 1
        if insert_pos < 0:
            insert_pos = 0
        self._panels_layout.insertWidget(insert_pos, panel)

        return panel

    def _rebuild_add_button(self):
        if hasattr(self, "_add_card") and self._add_card:
            self._panels_layout.removeWidget(self._add_card)
            self._add_card.deleteLater()

        self._add_card = QFrame()
        self._add_card.setObjectName("newPurchaseCard")
        self._add_card.setFixedWidth(PANEL_WIDTH)
        self._add_card.setMinimumHeight(440)
        self._add_card.setCursor(Qt.PointingHandCursor)

        card_layout = QVBoxLayout(self._add_card)
        card_layout.setAlignment(Qt.AlignCenter)

        icon = QLabel("+")
        icon.setObjectName("newPurchaseIcon")
        icon.setAlignment(Qt.AlignCenter)
        card_layout.addWidget(icon)

        label = QLabel("New Purchase")
        label.setObjectName("newPurchaseLabel")
        label.setAlignment(Qt.AlignCenter)
        card_layout.addWidget(label)

        self._add_card.mousePressEvent = lambda _: self._on_add_clicked()
        self._panels_layout.addWidget(self._add_card)

    def _on_add_clicked(self):
        self._add_card.setParent(None)
        panel = self._add_panel()
        self._rebuild_add_button()

        self._scroll.ensureWidgetVisible(panel)
        self._search_bar._input.setFocus()

    def _remove_panel(self, panel: PurchasePanel):
        if len(self._panels) <= 1:
            return
        self._panels.remove(panel)
        self._panels_layout.removeWidget(panel)
        panel.deleteLater()

        for i, p in enumerate(self._panels):
            p._index = i
            p._title_label.setText(f"Purchase #{i + 1}")

        self._update_combined()

    def _on_stock_selected(self, symbol: str, name: str):
        for panel in reversed(self._panels):
            if not panel.has_valid_data():
                panel.set_ticker(symbol, name)
                return
        self._panels[-1].set_ticker(symbol, name)

    def _update_combined(self):
        results = [p.get_result() for p in self._panels]
        self._combined_bar.update_stats(results)

    def _reset_all(self):
        for panel in self._panels:
            panel.reset()
        self._combined_bar.reset_display()
