import 'package:flutter/material.dart';

import '../data/database_service.dart';
import '../services/tile_cache_service.dart';
import '../services/tracking_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// Branded startup screen. Runs the app bootstrap (open the DB, register the
/// background tracking service) while showing a pulsing neon wordmark, then
/// replaces itself with the map. Surfaces a retry if bootstrap fails.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _error = null);
    try {
      // Keep the brand moment on screen briefly even if init is instant, so it
      // reads as a splash rather than a flash.
      await Future.wait([
        _init(),
        Future<void>.delayed(const Duration(milliseconds: 1200)),
      ]);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _init() async {
    await DatabaseService.instance.open();
    await TileCacheService.configure();
    await TrackingService.instance.configure();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Scaffold(
      backgroundColor: cx.canvas,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                final t = _glow.value; // 0..1
                return Text(
                  'RollingBike',
                  style: TextStyle(
                    color: cx.accentInk,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    shadows: [
                      BoxShadow(
                        color: cx.accentInk.withValues(alpha: 0.35 + 0.4 * t),
                        blurRadius: 16 + 20 * t,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'OFFLINE TELEMETRY',
              style: TextStyle(
                color: cx.textDim,
                fontSize: 12,
                letterSpacing: 4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 44),
            if (_error == null)
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: cx.accentInk,
                ),
              )
            else
              _ErrorRetry(message: _error!, onRetry: _bootstrap),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cx = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Startup failed',
            style: TextStyle(color: cx.dangerInk, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cx.textDim, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: cx.accentInk,
              side: BorderSide(color: cx.accentInk),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
