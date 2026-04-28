import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class CustomDotLottieWidget extends StatelessWidget {
  final String lottiePath;
  final double height, width;
  final BoxFit fit;

  const CustomDotLottieWidget({
    required this.lottiePath,
    this.height = 100,
    this.width = 100,
    this.fit = BoxFit.contain,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      lottiePath,
      height: height,
      width: width,
      fit: fit,
      frameRate: FrameRate.max,
      decoder: customDecoder,
    );
  }
}

Future<LottieComposition?> customDecoder(List<int> bytes) {
  return LottieComposition.decodeZip(
    bytes,
    filePicker: (files) {
      return files.firstWhere(
        (f) => f.name.startsWith('animations/') && f.name.endsWith('.json'),
      );
    },
  );
}
