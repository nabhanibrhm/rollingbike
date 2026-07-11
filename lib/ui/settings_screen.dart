import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../services/location_source.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Settings tab. Absorbs what used to live in the app drawer — theme toggle,
/// tracking-method (GPS source A/B) picker, and exit — plus a version footer.
///
/// This is a functional first pass; Phase 6 re-skins it to the prototype and
/// adds the km/h ↔ mph speed-unit control.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Lets the rider pick which GPS pipeline future rides record with (a
  /// temporary A/B test), persisting the choice for the background isolate to
  /// read at the next "Start ride" tap.
  Future<void> _openTrackingMethodPicker() async {
    final current = await SettingsService.instance.loadGpsSource();
    if (!mounted) return;
    final chosen = await _showGpsSourcePicker(current);
    if (chosen == null || !mounted) return;
    await SettingsService.instance.saveGpsSource(chosen);
    setState(() {}); // refresh the subtitle
  }

  Future<LocationSourceKind?> _showGpsSourcePicker(LocationSourceKind current) {
    final cx = AppColors.of(context);
    const descriptions = {
      LocationSourceKind.fused: 'Google fused provider · 5 m filter (original)',
      LocationSourceKind.raw: 'Raw GNSS · 1 s cadence · every fix',
      LocationSourceKind.fusedFast: 'Fused provider · 1 s cadence · every fix',
    };
    return showDialog<LocationSourceKind>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cx.surface,
        title: Text('Tracking method',
            style: TextStyle(color: cx.textBright, fontSize: 18)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in LocationSourceKind.values)
              ListTile(
                onTap: () => Navigator.of(ctx).pop(kind),
                leading: Icon(
                  kind == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: kind == current ? cx.accentInk : cx.textDim,
                ),
                title: Text(kind.label,
                    style: TextStyle(
                        color: cx.textBright, fontWeight: FontWeight.w600)),
                subtitle: Text(descriptions[kind]!,
                    style: TextStyle(color: cx.textDim, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: cx.textDim)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

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
          _SectionLabel('Recording'),
          _SettingsTile(
            icon: Icons.gps_fixed,
            title: 'Tracking method',
            subtitle: FutureBuilder<LocationSourceKind>(
              future: SettingsService.instance.loadGpsSource(),
              builder: (_, snap) => Text(
                snap.data?.label ?? '—',
                style: TextStyle(color: cx.textDim, fontSize: 13),
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: cx.textDim),
            onTap: _openTrackingMethodPicker,
          ),
          const SizedBox(height: 22),
          _SectionLabel('Display'),
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
          const SizedBox(height: 22),
          _SectionLabel('App'),
          _SettingsTile(
            icon: Icons.exit_to_app,
            title: 'Exit',
            onTap: () => SystemNavigator.pop(),
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
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? subtitle;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: cx.textBright,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
