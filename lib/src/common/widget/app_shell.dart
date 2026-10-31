import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/adaptive_dialog_widget.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/licenses.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_models_config_widget.dart';
import 'package:flutter/material.dart';

enum AppTab { transcribe, history, models }

/// Gives features a way to switch tabs and open a transcript in History
/// without depending on each other.
class AppShellScope extends InheritedWidget {
  const AppShellScope({required this.state, required super.child, super.key});

  final AppShellState state;

  static AppShellState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<AppShellScope>()?.widget;
    assert(widget != null, 'AppShellScope was not found in element tree');
    return (widget! as AppShellScope).state;
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) => false;
}

/// Tablet/desktop: side rail + content. Phone: content + bottom navigation.
/// Tabs live in an IndexedStack so the queue keeps running while browsing.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.transcribe;

  /// The transcript History should select next (list + transcript side by side).
  final ValueNotifier<int?> requestedTranscriptId = ValueNotifier<int?>(null);

  /// Keeps the tabs (and the running queue) alive when a resize or rotation
  /// swaps the bottom bar for the rail.
  final GlobalKey _tabsKey = GlobalKey(debugLabel: 'tabs');

  void selectTab(AppTab tab) {
    if (_tab != tab) setState(() => _tab = tab);
  }

  void showTranscript(int id) {
    requestedTranscriptId.value = id;
    selectTab(AppTab.history);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCpu());
  }

  @override
  void dispose() {
    requestedTranscriptId.dispose();
    super.dispose();
  }

  void _checkCpu() {
    if (!mounted || Dependencies.of(context).native.cpuSupported) return;
    final l10n = Localization.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AdaptiveDialogWidget(
        icon: Icons.warning_amber_rounded,
        tone: DialogTone.warning,
        title: l10n.cpuUnsupportedTitle,
        content: l10n.cpuUnsupportedMessage,
        confirmLabel: l10n.ok,
        showCancel: false,
        onConfirm: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      key: _tabsKey,
      index: _tab.index,
      children: const [TranscriptionQueueConfigWidget(), TranscriptsConfigWidget(), WhisperModelsConfigWidget()],
    );
    return AppShellScope(
      state: this,
      child: context.screenSizeMaybeWhen(
        orElse: () => _RailShell(tab: _tab, onSelect: selectTab, body: body),
        phone: () => _MobileShell(tab: _tab, onSelect: selectTab, body: body),
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({required this.tab, required this.onSelect, required this.body});

  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return Scaffold(
      // Tablets draw under the status and navigation bars; desktops have no insets.
      body: SafeArea(
        child: Row(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              child: NavigationRail(
                selectedIndex: tab.index,
                onDestinationSelected: (i) => onSelect(AppTab.values[i]),
                minWidth: 88,
                leading: const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(9),
                      child: Icon(Icons.graphic_eq, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: l10n.about,
                        icon: const Icon(Icons.info_outline, color: AppColors.inkSecondary),
                        onPressed: () => showAppAbout(context),
                      ),
                    ),
                  ),
                ),
                destinations: [
                  NavigationRailDestination(icon: const Icon(Icons.graphic_eq), label: Text(l10n.tabTranscribe)),
                  NavigationRailDestination(icon: const Icon(Icons.history), label: Text(l10n.tabHistory)),
                  NavigationRailDestination(icon: const Icon(Icons.memory), label: Text(l10n.tabModels)),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.tab, required this.onSelect, required this.body});

  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (i) => onSelect(AppTab.values[i]),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.graphic_eq), label: l10n.tabTranscribe),
            NavigationDestination(icon: const Icon(Icons.history), label: l10n.tabHistory),
            NavigationDestination(icon: const Icon(Icons.memory), label: l10n.tabModels),
          ],
        ),
      ),
    );
  }
}

extension AppLayoutExtension on BuildContext {
  /// History shows the transcript beside the list on desktops and on tablets
  /// held sideways; otherwise a tap opens the transcript as its own screen.
  bool get showsTranscriptBesideList =>
      screenSizeWhen(phone: () => false, tablet: () => orientation == Orientation.landscape, desktop: () => true);
}
