import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/widgets/custom_lottie_widget.dart';
import '../../providers/app_config_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/states/auth_state.dart';

/// Returns true if [current] is older than [minimum] (semver comparison).
bool _isOutdated(String current, String minimum) {
  final c = current.split('.').map(int.tryParse).toList();
  final m = minimum.split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final cv = i < c.length ? (c[i] ?? 0) : 0;
    final mv = i < m.length ? (m[i] ?? 0) : 0;
    if (cv < mv) return true;
    if (cv > mv) return false;
  }
  return false;
}

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (prev, next) {
      if (prev != next) {
        next.whenOrNull(
          authenticated: (user) async {
            if (!context.mounted) return;

            // Version check — Android only, iOS skipped until App Store release.
            if (Platform.isAndroid) {
              final minVersion = ref.read(minAppVersionProvider);
              if (minVersion.isNotEmpty) {
                final info = await PackageInfo.fromPlatform();
                if (_isOutdated(info.version, minVersion)) {
                  if (context.mounted) context.pushReplacement(forceUpdateRoute);
                  return;
                }
              }
            }

            final currentVersion = ref.read(currentPolicyVersionProvider);
            final userVersion = user.privacyPolicyVersion ?? 0;
            if (userVersion < currentVersion) {
              context.pushReplacement(consentRoute);
            } else if (user.username == null) {
              context.pushReplacement(userNameRoute);
            } else {
              context.pushReplacement(homeRoute);
            }
          },
          unauthenticated: () async {
            if (Platform.isAndroid) {
              final minVersion = ref.read(minAppVersionProvider);
              if (minVersion.isNotEmpty) {
                final info = await PackageInfo.fromPlatform();
                if (_isOutdated(info.version, minVersion)) {
                  if (context.mounted) context.pushReplacement(forceUpdateRoute);
                  return;
                }
              }
            }
            if (context.mounted) context.pushReplacement(loginRoute);
          },
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CustomDotLottieWidget(
          lottiePath: 'assets/lottie/splash_screen.lottie',
          width: 300,
          height: 300,
        ),
      ),
    );
  }
}
