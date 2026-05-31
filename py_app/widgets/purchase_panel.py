"""Single purchase calculator card widget."""

from PySide6.QtWidgets import (
    QFrame, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton, QWidget,
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QDoubleValidator

from py_app.core.bridge import CalcEngine, PanelResult
from py_app.config import COLORS


class PurchasePanel(QFrame):
    values_changed = Signal()
    delete_requested = Signal(object)

    FIELD_IDS = {
        "investment": 1,
        "price": 2,
        "shares": 3,
    }

    def __init__(self, index: int, engine: CalcEngine, parent=None):
        super().__init__(parent)
        self.setObjectName("purchaseCard")
        self.setFixedWidth(280)
        self.setMinimumHeight(440)

        self._index = index
        self._engine = engine
        self._updating = False
        self._last_changed = 0
        self._second_last_changed = 0
        self._ticker = ""
        self._company = ""

        self._build_ui()
        self._connect_signals()

    @property
    def panel_index(self) -> int:
        return self._index

    def _build_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 12, 16, 16)
        layout.setSpacing(8)

        header = QHBoxLayout()
        self._title_label = QLabel(f"Purchase #{self._index + 1}")
        self._title_label.setObjectName("cardTitle")
        header.addWidget(self._title_label)
        header.addStretch()

        if self._index > 0:
            del_btn = QPushButton("✕")
            del_btn.setObjectName("deleteBtn")
            del_btn.setFixedSize(24, 24)
            del_btn.clicked.connect(lambda: self.delete_requested.emit(self))
            header.addWidget(del_btn)

        layout.addLayout(header)

        ticker_row = QHBoxLayout()
        self._ticker_label = QLabel("")
        self._ticker_label.setObjectName("tickerLabel")
        ticker_row.addWidget(self._ticker_label)
        self._company_label = QLabel("")
        self._company_label.setObjectName("companyLabel")
        ticker_row.addWidget(self._company_label)
        ticker_row.addStretch()
        layout.addLayout(ticker_row)

        validator = QDoubleValidator(0, 1e12, 6)
        validator.setNotation(QDoubleValidator.StandardNotation)

        self._investment_input = self._add_field(layout, "Total Investment ($)", validator)
        self._price_input = self._add_field(layout, "Share Price ($)", validator)
        self._shares_input = self._add_field(layout, "Number of Shares", validator)

        self._target_input = self._add_field(layout, "Target Price ($)", validator)

        sep = QFrame()
        sep.setObjectName("cardSeparator")
        sep.setFrameShape(QFrame.HLine)
        layout.addWidget(sep)

        self._return_label = self._add_output_row(layout, "Return")
        self._profit_label = self._add_output_row(layout, "Profit")
        self._gain_label = self._add_output_row(layout, "Gain %")

        layout.addStretch()

        reset_btn = QPushButton("Reset")
        reset_btn.setObjectName("resetBtn")
        reset_btn.clicked.connect(self.reset)
        layout.addWidget(reset_btn, alignment=Qt.AlignRight)

    def _add_field(self, parent_layout, label_text: str, validator=None) -> QLineEdit:
        lbl = QLabel(label_text)
        lbl.setProperty("class", "fieldLabel")
        parent_layout.addWidget(lbl)

        field = QLineEdit()
        field.setProperty("class", "fieldInput")
        if validator:
            field.setValidator(validator)
        parent_layout.addWidget(field)
        return field

    def _add_output_row(self, parent_layout, label_text: str) -> QLabel:
        row = QHBoxLayout()
        lbl = QLabel(label_text)
        lbl.setProperty("class", "fieldLabel")
        lbl.setFixedWidth(60)
        row.addWidget(lbl)

        val = QLabel("—")
        val.setProperty("class", "outputValue")
        val.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        row.addWidget(val)
        parent_layout.addLayout(row)
        return val

    def _connect_signals(self):
        self._investment_input.textChanged.connect(lambda: self._on_field_changed("investment"))
        self._price_input.textChanged.connect(lambda: self._on_field_changed("price"))
        self._shares_input.textChanged.connect(lambda: self._on_field_changed("shares"))
        self._target_input.textChanged.connect(lambda: self._recalculate())

    def _on_field_changed(self, field_name: str):
        if self._updating:
            return
        field_id = self.FIELD_IDS[field_name]
        if field_id != self._last_changed:
            self._second_last_changed = self._last_changed
            self._last_changed = field_id
        self._recalculate()

    def _get_value(self, field: QLineEdit) -> float:
        text = field.text().strip()
        if not text:
            return 0.0
        try:
            return float(text)
        except ValueError:
            return 0.0

    def _set_value(self, field: QLineEdit, value: float):
        if value == 0.0:
            field.setText("")
        else:
            field.setText(f"{value:.2f}")

    def _recalculate(self):
        if self._updating:
            return
        self._updating = True

        result = self._engine.calculate_panel(
            self._get_value(self._investment_input),
            self._get_value(self._price_input),
            self._get_value(self._shares_input),
            self._get_value(self._target_input),
            self._last_changed,
            self._second_last_changed,
        )

        inferred = result.inferred_field
        fields_map = {
            1: (self._investment_input, "investment"),
            2: (self._price_input, "price"),
            3: (self._shares_input, "shares"),
        }

        for fid, (widget, key) in fields_map.items():
            if fid == inferred:
                val = [result.total_investment, result.share_price, result.total_shares][fid - 1]
                self._set_value(widget, val)
                widget.setProperty("class", "inferredField")
            else:
                widget.setProperty("class", "fieldInput")
            widget.style().unpolish(widget)
            widget.style().polish(widget)

        if result.profit_plus_invest != 0:
            self._return_label.setText(f"${result.profit_plus_invest:,.2f}")
        else:
            self._return_label.setText("—")
        self._return_label.setProperty("class", "outputValue")

        self._set_profit_display(self._profit_label, result.profit, prefix="$")
        self._set_profit_display(self._gain_label, result.gain_percent, suffix="%")

        self._last_result = result
        self._updating = False
        self.values_changed.emit()

    def _set_profit_display(self, label: QLabel, value: float, prefix="", suffix=""):
        if value > 0:
            label.setText(f"+{prefix}{value:,.2f}{suffix}")
            label.setProperty("class", "profitPositive")
        elif value < 0:
            label.setText(f"-{prefix}{abs(value):,.2f}{suffix}")
            label.setProperty("class", "profitNegative")
        else:
            label.setText("—")
            label.setProperty("class", "profitZero")
        label.style().unpolish(label)
        label.style().polish(label)

    def set_ticker(self, symbol: str, name: str):
        self._ticker = symbol
        self._company = name
        self._ticker_label.setText(symbol)
        self._company_label.setText(name)

    def get_result(self) -> PanelResult:
        if hasattr(self, "_last_result"):
            return self._last_result
        return PanelResult()

    def has_valid_data(self) -> bool:
        r = self.get_result()
        return r.total_investment > 0 and r.share_price > 0 and r.total_shares > 0

    def reset(self):
        self._updating = True
        self._last_changed = 0
        self._second_last_changed = 0
        self._investment_input.clear()
        self._price_input.clear()
        self._shares_input.clear()
        self._target_input.clear()
        self._return_label.setText("—")
        self._profit_label.setText("—")
        self._gain_label.setText("—")
        self._return_label.setProperty("class", "outputValue")
        self._profit_label.setProperty("class", "profitZero")
        self._gain_label.setProperty("class", "profitZero")
        self._last_result = PanelResult()
        self._updating = False
        self.values_changed.emit()
