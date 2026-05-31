"""ctypes bridge to the C++23 StockCalcEngine DLL."""

import ctypes
from dataclasses import dataclass
from pathlib import Path

_c_double_p = ctypes.POINTER(ctypes.c_double)
_c_int_p = ctypes.POINTER(ctypes.c_int)


def _find_dll() -> str:
    base = Path(__file__).resolve().parent.parent / "backend" / "build"
    candidates = [
        base / "Release" / "stockcalc_engine.dll",
        base / "Debug" / "stockcalc_engine.dll",
        base / "stockcalc_engine.dll",
        base / "libstockcalc_engine.dll",
        base / "libstockcalc_engine.so",
        base / "libstockcalc_engine.dylib",
    ]
    for p in candidates:
        if p.exists():
            return str(p)
    return ""


@dataclass
class PanelResult:
    total_investment: float = 0.0
    share_price: float = 0.0
    total_shares: float = 0.0
    profit_plus_invest: float = 0.0
    profit: float = 0.0
    gain_percent: float = 0.0
    inferred_field: int = 0


@dataclass
class CombinedResult:
    avg_share_price: float = 0.0
    total_investment: float = 0.0
    total_shares: float = 0.0
    total_profit: float = 0.0
    avg_profit: float = 0.0
    valid_count: int = 0


class CalcEngine:
    """Wrapper around the C++ calculation DLL. Falls back to pure Python if DLL not found."""

    def __init__(self):
        dll_path = _find_dll()
        self._lib = None
        if dll_path:
            try:
                self._lib = ctypes.CDLL(dll_path)
                self._setup_functions()
            except OSError:
                self._lib = None

    def _setup_functions(self):
        self._lib.calc_panel.argtypes = [
            ctypes.c_double, ctypes.c_double, ctypes.c_double,
            ctypes.c_double, ctypes.c_int, ctypes.c_int,
            _c_double_p, _c_double_p, _c_double_p,
            _c_double_p, _c_double_p, _c_double_p, _c_int_p,
        ]
        self._lib.calc_panel.restype = None

        self._lib.calc_combined.argtypes = [
            _c_double_p, _c_double_p, _c_double_p, _c_double_p,
            ctypes.c_int,
            _c_double_p, _c_double_p, _c_double_p,
            _c_double_p, _c_double_p, _c_int_p,
        ]
        self._lib.calc_combined.restype = None

    @property
    def using_native(self) -> bool:
        return self._lib is not None

    def calculate_panel(
        self,
        total_investment: float,
        share_price: float,
        total_shares: float,
        target_price: float,
        last_changed: int = 0,
        second_last_changed: int = 0,
    ) -> PanelResult:
        if self._lib:
            return self._calc_panel_native(
                total_investment, share_price, total_shares,
                target_price, last_changed, second_last_changed,
            )
        return self._calc_panel_python(
            total_investment, share_price, total_shares,
            target_price, last_changed, second_last_changed,
        )

    def _calc_panel_native(self, inv, price, shares, target, last, second) -> PanelResult:
        o_inv = ctypes.c_double()
        o_price = ctypes.c_double()
        o_shares = ctypes.c_double()
        o_pi = ctypes.c_double()
        o_profit = ctypes.c_double()
        o_gain = ctypes.c_double()
        o_inferred = ctypes.c_int()
        self._lib.calc_panel(
            inv, price, shares, target, last, second,
            ctypes.byref(o_inv), ctypes.byref(o_price), ctypes.byref(o_shares),
            ctypes.byref(o_pi), ctypes.byref(o_profit), ctypes.byref(o_gain),
            ctypes.byref(o_inferred),
        )
        return PanelResult(
            o_inv.value, o_price.value, o_shares.value,
            o_pi.value, o_profit.value, o_gain.value, o_inferred.value,
        )

    def _calc_panel_python(self, inv, price, shares, target, last, second) -> PanelResult:
        inferred = 0

        if last == 1:  # total_investment
            if second == 3 and shares > 0:
                inv = price * shares
                inferred = 1
            elif price > 0:
                shares = inv / price
                inferred = 3
        elif last == 2:  # share_price
            if inv > 0 and price > 0:
                shares = inv / price
                inferred = 3
        elif last == 3:  # total_shares
            if second == 1 and inv > 0 and shares > 0:
                price = inv / shares
                inferred = 2
            elif price > 0:
                inv = price * shares
                inferred = 1
        else:
            nz = (inv > 0) + (price > 0) + (shares > 0)
            if nz == 2:
                if inv <= 0 and price > 0 and shares > 0:
                    inv = price * shares
                    inferred = 1
                elif price <= 0 and inv > 0 and shares > 0:
                    price = inv / shares
                    inferred = 2
                elif shares <= 0 and inv > 0 and price > 0:
                    shares = inv / price
                    inferred = 3

        pi = profit = gain = 0.0
        if target > 0 and shares > 0:
            pi = target * shares
            profit = pi - inv
        if target > 0 and price > 0:
            gain = ((target - price) * 100.0) / price

        return PanelResult(inv, price, shares, pi, profit, gain, inferred)

    def calculate_combined(self, panels: list[PanelResult]) -> CombinedResult:
        if self._lib and panels:
            return self._calc_combined_native(panels)
        return self._calc_combined_python(panels)

    def _calc_combined_native(self, panels: list[PanelResult]) -> CombinedResult:
        n = len(panels)
        arr_d = ctypes.c_double * n
        investments = arr_d(*(p.total_investment for p in panels))
        prices = arr_d(*(p.share_price for p in panels))
        shares_arr = arr_d(*(p.total_shares for p in panels))
        profits = arr_d(*(p.profit for p in panels))

        o_avg_p = ctypes.c_double()
        o_ti = ctypes.c_double()
        o_ts = ctypes.c_double()
        o_tp = ctypes.c_double()
        o_ap = ctypes.c_double()
        o_vc = ctypes.c_int()

        self._lib.calc_combined(
            investments, prices, shares_arr, profits, n,
            ctypes.byref(o_avg_p), ctypes.byref(o_ti), ctypes.byref(o_ts),
            ctypes.byref(o_tp), ctypes.byref(o_ap), ctypes.byref(o_vc),
        )
        return CombinedResult(
            o_avg_p.value, o_ti.value, o_ts.value,
            o_tp.value, o_ap.value, o_vc.value,
        )

    def _calc_combined_python(self, panels: list[PanelResult]) -> CombinedResult:
        total_inv = total_sh = total_pr = weighted = 0.0
        valid = 0
        for p in panels:
            if p.total_investment > 0 and p.share_price > 0 and p.total_shares > 0:
                total_inv += p.total_investment
                total_sh += p.total_shares
                total_pr += p.profit
                weighted += p.share_price * p.total_shares
                valid += 1
        if valid == 0:
            return CombinedResult()
        avg_price = weighted / total_sh if total_sh > 0 else 0.0
        avg_profit = total_pr / valid
        return CombinedResult(avg_price, total_inv, total_sh, total_pr, avg_profit, valid)
