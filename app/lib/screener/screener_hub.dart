/// Bundles the three ScreenerClient pollers (Finviz, Yahoo, Combined) that
/// back the tabbed ScreenerPanel, so HomePage keeps owning one object - same
/// shape as the single ScreenerClient it used to own - instead of three.
library;

import 'screener_client.dart';

class ScreenerHub {
  final ScreenerClient finviz;
  final ScreenerClient yahoo;
  final ScreenerClient combined;

  ScreenerHub({String baseUrl = 'http://localhost:8090'})
      : finviz = ScreenerClient(baseUrl: baseUrl, endpointPath: '/screener/finviz'),
        yahoo = ScreenerClient(baseUrl: baseUrl, endpointPath: '/screener/yahoo'),
        combined = ScreenerClient(baseUrl: baseUrl, endpointPath: '/screener/combined');

  /// Applies one shared refresh cadence to all three tabs, driven by the
  /// existing AppSettings.screenerRefreshSeconds preference.
  void setPollInterval(Duration interval) {
    finviz.setPollInterval(interval);
    yahoo.setPollInterval(interval);
    combined.setPollInterval(interval);
  }

  void dispose() {
    finviz.dispose();
    yahoo.dispose();
    combined.dispose();
  }
}
