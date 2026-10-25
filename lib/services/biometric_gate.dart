import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricOffer { unavailable, face, fingerprint, generic }

class BiometricGate {
  BiometricGate({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<BiometricOffer> probe() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) {
        return BiometricOffer.unavailable;
      }
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        return BiometricOffer.face;
      }
      if (types.contains(BiometricType.fingerprint)) {
        return BiometricOffer.fingerprint;
      }
      if (types.isNotEmpty || canCheck || supported) {
        return BiometricOffer.generic;
      }
    } catch (_) {}
    return BiometricOffer.unavailable;
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Hermsy',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
