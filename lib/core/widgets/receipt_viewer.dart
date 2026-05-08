import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

void showReceiptViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: const SizedBox.expand(),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (context, url) => const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white54,
                  ),
                ),
                errorWidget: (context, url, err) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(ctx).padding.top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
