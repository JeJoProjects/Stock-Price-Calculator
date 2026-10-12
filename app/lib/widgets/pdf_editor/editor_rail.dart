import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../pdfedit/doc_session.dart';
import '../../pdfedit/workspace.dart';
import '../../theme/app_theme.dart';
import 'editor_controller.dart';
import 'page_renderer.dart';

/// Left rail: open documents on top, page thumbnails of the active one below.
class EditorRail extends StatelessWidget {
  const EditorRail({
    super.key,
    required this.workspace,
    required this.ctrl,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onNewBlank,
    required this.onClose,
    required this.onDeletePage,
    required this.onRotatePage,
  });

  final PdfWorkspace workspace;
  final EditorController ctrl;
  final VoidCallback onOpenFiles, onOpenFolder, onNewBlank;
  final void Function(int docIndex) onClose;
  final void Function(int page) onDeletePage;
  final void Function(int page, int degrees) onRotatePage;

  @override
  Widget build(BuildContext context) {
    final active = workspace.active;
    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(children: [
            Expanded(
              child: Text('Documents (${workspace.docs.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
            IconButton(
              tooltip: 'Open PDF files (Ctrl+O)',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onOpenFiles,
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              tooltip: 'Open a whole folder',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onOpenFolder,
              icon: const Icon(Icons.folder_open_rounded),
            ),
            IconButton(
              tooltip: 'New blank document',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onNewBlank,
              icon: const Icon(Icons.add_box_outlined),
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: workspace.docs.length,
            itemBuilder: (_, i) => _DocTile(
              doc: workspace.docs[i],
              active: i == workspace.activeIndex,
              onTap: () => workspace.activate(i),
              onClose: () => onClose(i),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(active == null ? 'Pages' : 'Pages (${active.pageCount})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
        Expanded(
          child: active == null
              ? const SizedBox()
              : ListenableBuilder(
                  listenable: Listenable.merge([active, ctrl]),
                  builder: (context, _) => ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: active.pageCount,
                    itemBuilder: (_, i) => _Thumb(
                      session: active,
                      page: i,
                      current: ctrl.currentPage == i,
                      onTap: () => ctrl.requestScrollTo(i),
                      onDelete: () => onDeletePage(i),
                      onRotate: (d) => onRotatePage(i, d),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc, required this.active, required this.onTap, required this.onClose});
  final PdfDocSession doc;
  final bool active;
  final VoidCallback onTap, onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: doc,
        builder: (context, _) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            color: active ? AppColors.accentBlue.withValues(alpha: 0.18) : Colors.transparent,
            child: Row(children: [
              Icon(Icons.picture_as_pdf_rounded, size: 16, color: active ? AppColors.accentBlue : AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Tooltip(
                    message: doc.sourcePath ?? doc.title,
                    child: Text(doc.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                  ),
                  Text('${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                ]),
              ),
              if (doc.dirty)
                const Tooltip(
                  message: 'Unsaved changes',
                  child: Icon(Icons.circle, size: 8, color: Color(0xFFFFB300)),
                ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
              ),
            ]),
          ),
        ),
      );
}

class _Thumb extends StatefulWidget {
  const _Thumb({
    required this.session,
    required this.page,
    required this.current,
    required this.onTap,
    required this.onDelete,
    required this.onRotate,
  });

  final PdfDocSession session;
  final int page;
  final bool current;
  final VoidCallback onTap, onDelete;
  final void Function(int) onRotate;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  ui.Image? _img;
  String _key = '';
  bool _hover = false;

  static const _thumbW = 150.0;

  void _load(double dpr) {
    final s = widget.session;
    final (pw, ph) = s.pageSize(widget.page);
    final w = (_thumbW * dpr).round();
    final h = (_thumbW * dpr * ph / pw).round().clamp(1, 4000);
    final key = '${s.renderKey}|${widget.page}|$w';
    if (key == _key) return;
    _key = key;
    PageImageCache.instance.get(s, widget.page, w, h, annotations: true).then((i) {
      if (mounted && _key == key) setState(() => _img = i);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    _load(MediaQuery.devicePixelRatioOf(context));
    final (pw, ph) = widget.session.pageSize(widget.page);
    final h = _thumbW * ph / pw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(children: [
            Stack(children: [
              Container(
                width: _thumbW,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: widget.current ? AppColors.accentBlue : AppColors.border, width: widget.current ? 2.5 : 1),
                ),
                child: _img == null ? null : RawImage(image: _img, fit: BoxFit.fill),
              ),
              if (_hover)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Row(children: [
                    _mini(Icons.rotate_left_rounded, 'Rotate left', () => widget.onRotate(-90)),
                    _mini(Icons.rotate_right_rounded, 'Rotate right', () => widget.onRotate(90)),
                    _mini(Icons.delete_outline_rounded, 'Delete page', widget.onDelete),
                  ]),
                ),
            ]),
            const SizedBox(height: 3),
            Text('${widget.page + 1}',
                style: TextStyle(fontSize: 11, color: widget.current ? AppColors.accentBlue : AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }

  Widget _mini(IconData i, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xCC131722), borderRadius: BorderRadius.circular(4)),
            child: Icon(i, size: 14, color: Colors.white),
          ),
        ),
      );
}
