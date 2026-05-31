"""Unit tests for the CalcEngine (Python fallback path)."""

import pytest
from py_app.core.bridge import CalcEngine, PanelResult


@pytest.fixture
def engine():
    e = CalcEngine()
    return e


class TestSmartInference:
    def test_infer_shares_from_investment_and_price(self, engine):
        r = engine.calculate_panel(10000, 200, 0, 250)
        assert r.total_shares == pytest.approx(50.0)
        assert r.inferred_field == 3

    def test_infer_price_from_investment_and_shares(self, engine):
        r = engine.calculate_panel(10000, 0, 50, 300)
        assert r.share_price == pytest.approx(200.0)
        assert r.inferred_field == 2

    def test_infer_investment_from_price_and_shares(self, engine):
        r = engine.calculate_panel(0, 200, 50, 0)
        assert r.total_investment == pytest.approx(10000.0)
        assert r.inferred_field == 1

    def test_no_inference_all_zeros(self, engine):
        r = engine.calculate_panel(0, 0, 0, 0)
        assert r.inferred_field == 0

    def test_no_inference_single_field(self, engine):
        r = engine.calculate_panel(10000, 0, 0, 0)
        assert r.inferred_field == 0


class TestLastChangedTracking:
    def test_last_investment_derives_shares(self, engine):
        r = engine.calculate_panel(10000, 200, 100, 0, last_changed=1)
        assert r.total_shares == pytest.approx(50.0)
        assert r.inferred_field == 3

    def test_last_shares_second_investment_derives_price(self, engine):
        r = engine.calculate_panel(10000, 200, 40, 0, last_changed=3, second_last_changed=1)
        assert r.share_price == pytest.approx(250.0)
        assert r.inferred_field == 2

    def test_last_price_derives_shares(self, engine):
        r = engine.calculate_panel(10000, 250, 50, 0, last_changed=2)
        assert r.total_shares == pytest.approx(40.0)
        assert r.inferred_field == 3

    def test_last_shares_no_second_derives_investment(self, engine):
        r = engine.calculate_panel(0, 200, 50, 0, last_changed=3)
        assert r.total_investment == pytest.approx(10000.0)
        assert r.inferred_field == 1


class TestProfitCalculation:
    def test_positive_profit(self, engine):
        r = engine.calculate_panel(10000, 200, 0, 250)
        assert r.profit == pytest.approx(2500.0)
        assert r.profit_plus_invest == pytest.approx(12500.0)
        assert r.gain_percent == pytest.approx(25.0)

    def test_negative_profit(self, engine):
        r = engine.calculate_panel(10000, 200, 0, 150)
        assert r.profit == pytest.approx(-2500.0)
        assert r.gain_percent == pytest.approx(-25.0)

    def test_zero_target_no_profit(self, engine):
        r = engine.calculate_panel(10000, 200, 0, 0)
        assert r.profit == pytest.approx(0.0)
        assert r.profit_plus_invest == pytest.approx(0.0)

    def test_breakeven(self, engine):
        r = engine.calculate_panel(10000, 200, 0, 200)
        assert r.profit == pytest.approx(0.0)
        assert r.gain_percent == pytest.approx(0.0)


class TestCombinedCalculation:
    def test_two_valid_panels(self, engine):
        panels = [
            PanelResult(10000, 200, 50, 12500, 2500, 25, 0),
            PanelResult(5000, 100, 50, 7500, 2500, 50, 0),
        ]
        c = engine.calculate_combined(panels)
        assert c.valid_count == 2
        assert c.total_investment == pytest.approx(15000.0)
        assert c.total_shares == pytest.approx(100.0)
        assert c.total_profit == pytest.approx(5000.0)
        assert c.avg_profit == pytest.approx(2500.0)
        assert c.avg_share_price == pytest.approx(150.0)

    def test_skips_invalid_panel(self, engine):
        panels = [
            PanelResult(10000, 200, 50, 0, 2500, 0, 0),
            PanelResult(0, 0, 0, 0, 0, 0, 0),
        ]
        c = engine.calculate_combined(panels)
        assert c.valid_count == 1
        assert c.total_investment == pytest.approx(10000.0)

    def test_empty_list(self, engine):
        c = engine.calculate_combined([])
        assert c.valid_count == 0
        assert c.total_investment == pytest.approx(0.0)

    def test_weighted_avg_price(self, engine):
        panels = [
            PanelResult(10000, 100, 100, 0, 0, 0, 0),
            PanelResult(10000, 200, 50, 0, 0, 0, 0),
        ]
        c = engine.calculate_combined(panels)
        expected_avg = (100 * 100 + 200 * 50) / 150
        assert c.avg_share_price == pytest.approx(expected_avg)
