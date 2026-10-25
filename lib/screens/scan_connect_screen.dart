import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/connect_link.dart';
import '../theme/app_theme.dart';
import '../widgets/ui/frank_ui.dart';

/// The camera, looking for the QR code `hermes-spawn connect` prints. Pops
/// with the address and key from the first one it reads.
class ScanConnectScreen extends StatefulWidget {
  const ScanConnectScreen({super.key});

  @override
  State<ScanConnectScreen> createState() => _ScanConnectScreenState();
}

class _ScanConnectScreenState extends State<ScanConnectScreen> {
  final _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  var _done = false;
  var _notOurs = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final link = parseConnectLink(barcode.rawValue ?? '');
      if (link != null) {
        _done = true;
        Navigator.of(context).pop(link);
        return;
      }
    }
    if (!_notOurs) {
      setState(() => _notOurs = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraProblem(error: error),
          ),
          // A frame to aim with.
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
            ),
          ),
          Positioned(
            top: media.padding.top + 8,
            left: 8,
            child: FrankIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              color: Colors.white,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: media.padding.bottom + 40,
            child: Text(
              _notOurs
                  ? 'That QR code is not from hermes-spawn connect.'
                  : 'Point the camera at the QR code from\nhermes-spawn connect',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
                shadows: [Shadow(blurRadius: 8)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          denied
              ? 'Hermsy needs the camera to scan the code. Allow it in '
                    'Android Settings › Apps › Hermsy › Permissions, or type '
                    'the address and key instead.'
              : 'The camera could not start (${error.errorCode.name}). '
                    'Type the address and key instead.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
