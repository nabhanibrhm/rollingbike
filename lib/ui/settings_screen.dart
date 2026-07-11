import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../services/location_source.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Settings tab, following the design mockup: a Recording section (tracking
/// method) and a Display section (speed unit + dark mode), over a version
/// footer.
///
/// The dark-mode toggle is a deliberate addition to the mockup (which shows
/// both themes with no visible switch) so riders can override the theme in-app.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  LocationSourceKind? _gpsSource;

  @override
  void initState() {
    super.initState();
    _loadGpsSource();
  }

  Future<void> _loadGpsSource() async {
    final kind = await SettingsService.instance.loadGpsSource();
    if (mounted) setState(() => _gpsSource = kind);
  }

  /// Lets the rider pick which GPS pipeline future rides record with (a
  /// temporary A/B test), persisting the choice for the background isolate to
  /// read at the next "Start ride" tap.
  Future<void> _openTrackingMethodPicker() async {
    final current = _gpsSource ?? await SettingsService.instance.loadGpsSource();
    if (!mounted) return;
    final chosen = await _showGpsSourcePicker(current);
    if (chosen == null || !mounted) return;
    await SettingsService.instance.saveGpsSource(chosen);
    if (mounted) setState(() => _gpsSource = chosen);
  }

  Future<LocationSourceKind?> _showGpsSourcePicker(LocationSourceKind current) {
    final cx = AppColors.of(context);
    const descriptions = {
      LocationSourceKind.fused: 'Google fused provider · 5 m filter',
      LocationSourceKind.raw: 'Raw GNSS · 1 s cadence · every fix',
      LocationSourceKind.fusedFast: 'Fused provider · 1 s cadence · every fix',
    };
    return showDialog<LocationSourceKind>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cx.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tracking method',
                  style: TextStyle(
                      color: cx.textBright,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final kind in LocationSourceKind.values)
                _GpsOption(
                  label: kind.label,
                  desc: descriptions[kind]!,
                  selected: kind == current,
                  onTap: () => Navigator.of(ctx).pop(kind),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: cx.textDim)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          _SectionLabel('Recording'),
          _SettingsTile(
            icon: Icons.gps_fixed,
            title: 'Tracking method',
            subtitle: Text(
              _gpsSource?.label ?? '—',
              style: TextStyle(color: cx.textDim, fontSize: 13),
            ),
            trailing: Icon(Icons.chevron_right, color: cx.textDim),
            onTap: _openTrackingMethodPicker,
          ),
          const SizedBox(height: 22),
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

/// A selectable tracking-method row in the picker dialog: a radio circle (amber
/// when selected) + label + description.
class _GpsOption extends StatelessWidget {
  const _GpsOption({
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? cx.accentInk : cx.textDim, width: 2),
              ),
              child: selected
                  ? Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: cx.accentInk,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: cx.textBright,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: TextStyle(
                          color: cx.textDim, fontSize: 12.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
