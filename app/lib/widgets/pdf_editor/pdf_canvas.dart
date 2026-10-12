import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../../pdfedit/doc_session.dart';
import '../../theme/app_theme.dart';
import 'editable_page.dart';
import 'editor_controller.dart';

/// Scrollable column of editable pages with zoom (buttons, fit width,
/// Ctrl+wheel) and current-page tracking.
class PdfCanvas extends StatefulWidget {
  const PdfCanvas({super.key, required this.session, required this.ctrl, required this.callbacks});

  final PdfDocSession session;
  final EditorController ctrl;
  final PageCallbacks callbacks;

  @override
  State<PdfCanvas> createState() => _PdfCanvasState();
}

class _PdfCanvasState extends State<PdfCanvas> {
  static const _margin = 28.0;
  static const _gap = 18.0;

  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  double _viewportW = 800, _viewportH = 600;
  double _scale = 1.0;
  int _lastScrollTick = 0;

  PdfDocSession get s => widget.session;
  EditorController get c => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_trackPage);
    c.addListener(_onCtrl);
    s.addListener(_onSession);
    _lastScrollTick = c.scrollTick;
  }

  @override
  void didUpdateWidget(PdfCanvas old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
      if (_vertical.hasClients) _vertical.jumpTo(0);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onCtrl);
    s.removeListener(_onSession);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _onCtrl() {
    if (!mounted) return;
    if (c.scrollTick != _lastScrollTick) {
      _lastScrollTick = c.scrollTick;
      _scrollToPage(c.scrollToPage);
    }
    setState(() {});
  }

  double get _maxPageW {
    var m = 1.0;
    for (var i = 0; i < s.pageCount; i++) {
      m = math.max(m, s.pageSize(i).$1);
    }
    return m;
  }

  double _pageTop(int page) {
    var y = _gap;
    for (var i = 0; i < page && i < s.pageCount; i++) {
      y += s.pageSize(i).$2 * _scale + _gap;
    }
    return y;
  }

  void _scrollToPage(int page) {
    if (!_vertical.hasClients) return;
    final target = (_pageTop(page) - _gap).clamp(0.0, _vertical.position.maxScrollExtent);
    _vertical.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  void _trackPage() {
    if (!_vertical.hasClients || s.pageCount == 0) return;
    final mid = _vertical.offset + _viewportH * 0.35;
    var y = _gap;
    var page = 0;
    for (var i = 0; i < s.pageCount; i++) {
      final h = s.pageSize(i).$2 * _scale;
      if (mid < y + h + _gap / 2) {
        page = i;
        break;
      }
      y += h + _gap;
      page = i;
    }
    c.setCurrentPage(page);
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final dy = (event as PointerScrollEvent).scrollDelta.dy;
        c.setZoom(_scale * math.exp(-dy / 500));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _viewportW = box.maxWidth;
      _viewportH = box.maxHeight;
      if (c.fitWidth) {
        _scale = ((_viewportW - 2 * _margin) / _maxPageW).clamp(EditorController.minZoom, EditorController.maxZoom);
        c.zoom = _scale;
      } else {
        _scale = c.zoom;
      }
      final contentW = math.max(_viewportW, _maxPageW * _scale + 2 * _margin);
      return ColoredBox(
        color: const Color(0xFF0E1118),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: contentW > _viewportW + 1,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentW,
              height: box.maxHeight,
              child: Scrollbar(
                controller: _vertical,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _vertical,
                  padding: const EdgeInsets.symmetric(vertical: _gap),
                  scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
                  itemCount: s.pageCount,
                  itemBuilder: (context, i) => Listener(
                    onPointerSignal: _onWheel,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: Center(
                        child: EditablePage(
                          key: ValueKey('${identityHashCode(s)}:$i'),
                          session: s,
                          ctrl: c,
                          pageIndex: i,
                          scale: _scale,
                          callbacks: widget.callbacks,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Thin themed divider used between toolbar groups.
class ToolbarDivider extends StatelessWidget {
  const ToolbarDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: AppColors.border);
}
