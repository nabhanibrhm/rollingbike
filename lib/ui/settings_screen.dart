import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../theme/app_theme.dart';

/// Settings tab, following the design mockup: a Display section (speed unit +
/// dark mode) over a version footer.
///
/// The dark-mode toggle is a deliberate addition to the mockup (which shows
/// both themes with no visible switch) so riders can override the theme in-app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cx = AppColors.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final unit = ref.watch(speedUnitProvider);

    return Scaffold(
      backgroundColor: cx.canvas,
      appBar: AppBar(
        backgroundColor: cx.canvas,
        foregroundColor: cx.textBright,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Settings',
            style: TextStyle(
                color: cx.textBright,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionLabel('Display'),
          _SettingsTile(
            icon: Icons.speed,
            title: 'Speed unit',
            trailing: Text(
              unit.speedLabel,
              style: TextStyle(color: cx.textDim, fontSize: 13),
            ),
            onTap: () => ref.read(speedUnitProvider.notifier).toggle(),
          ),
          const SizedBox(height: 12),
          _SettingsTile(
            icon: isDark ? Icons.dark_mode : Icons.light_mode,
            title: 'Dark mode',
            trailing: Switch(
              value: isDark,
              activeThumbColor: cx.onAccent,
              activeTrackColor: cx.accent,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            ),
            onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text('RollingBike v1.0.0',
                style: TextStyle(color: cx.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: cx.textDim,
          fontSize: 12,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Material(
      color: cx.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cx.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cx.accentInk, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: cx.textBright,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
