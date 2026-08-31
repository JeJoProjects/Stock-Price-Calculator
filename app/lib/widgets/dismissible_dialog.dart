import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Small "clever shortcut" wrapper: any dialog built with this closes on
/// Escape, matching the old app's dropdown/dialog dismiss convention
/// (Application::renderSearchBar's Esc-to-close) without repeating the
/// Shortcuts/Actions boilerplate at every call site.
Future<T?> showAppDialog<T>(BuildContext context, {required Widget child}) {
  return showDialog<T>(
    context: context,
    builder: (context) => Shortcuts(
      shortcuts: {LogicalKeySet(LogicalKeyboardKey.escape): const _DismissIntent()},
      child: Actions(
        actions: {
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) => Navigator.of(context).pop(),
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    ),
  );
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class AppDialogShell extends StatelessWidget {
  final String title;
  final Widget child;
  final double width;
  final double height;

  const AppDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.width = 420,
    this.height = 360,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kCardRadius)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
