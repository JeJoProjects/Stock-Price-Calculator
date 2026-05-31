"""Combined statistics bar at the bottom of the window."""

from PySide6.QtWidgets import QWidget, QHBoxLayout, QVBoxLayout, QLabel, QPushButton
from PySide6.QtCore import Qt, Signal

from py_app.core.bridge import CalcEngine, PanelResult
from py_app.config import COLORS


class CombinedStatsBar(QWidget):
    reset_all_clicked = Signal()

    def __init__(self, engine: CalcEngine, parent=None):
        super().__init__(parent)
        self.setObjectName("combinedBar")
        self.setFixedHeight(72)
        self._engine = engine

        layout = QHBoxLayout(self)
        layout.setContentsMargins(24, 8, 24, 8)
        layout.setSpacing(0)

        self._avg_price = self._add_stat(layout, "Avg Price")
        self._total_invest = self._add_stat(layout, "Total Invest")
        self._total_shares = self._add_stat(layout, "Total Shares")
        self._total_profit = self._add_stat(layout, "Total Profit")
        self._avg_profit = self._add_stat(layout, "Avg Profit")

        layout.addSpacing(16)

        reset_btn = QPushButton("Reset All")
        reset_btn.setObjectName("resetAllBtn")
        reset_btn.setFixedSize(100, 36)
        reset_btn.clicked.connect(self.reset_all_clicked.emit)
        layout.addWidget(reset_btn)

    def _add_stat(self, parent_layout, label_text: str) -> QLabel:
        container = QVBoxLayout()
        container.setSpacing(2)
        container.setAlignment(Qt.AlignCenter)

        lbl = QLabel(label_text)
        lbl.setProperty("class", "statLabel")
        lbl.setAlignment(Qt.AlignCenter)
        container.addWidget(lbl)

        val = QLabel("$0.00")
        val.setProperty("class", "statValue")
        val.setAlignment(Qt.AlignCenter)
        container.addWidget(val)

        parent_layout.addLayout(container, 1)
        return val

    def update_stats(self, panels: list[PanelResult]):
        result = self._engine.calculate_combined(panels)

        self._avg_price.setText(f"${result.avg_share_price:,.2f}")
        self._total_invest.setText(f"${result.total_investment:,.2f}")
        self._total_shares.setText(f"{result.total_shares:,.3f}")

        self._set_profit_value(self._total_profit, result.total_profit)
        self._set_profit_value(self._avg_profit, result.avg_profit)

    def _set_profit_value(self, label: QLabel, value: float):
        if value > 0:
            label.setText(f"+${value:,.2f}")
            label.setProperty("class", "statValueGreen")
        elif value < 0:
            label.setText(f"-${abs(value):,.2f}")
            label.setProperty("class", "statValueRed")
        else:
            label.setText("$0.00")
            label.setProperty("class", "statValue")
        label.style().unpolish(label)
        label.style().polish(label)

    def reset_display(self):
        for w in (self._avg_price, self._total_invest, self._total_shares,
                  self._total_profit, self._avg_profit):
            w.setText("$0.00")
            w.setProperty("class", "statValue")
            w.style().unpolish(w)
            w.style().polish(w)
