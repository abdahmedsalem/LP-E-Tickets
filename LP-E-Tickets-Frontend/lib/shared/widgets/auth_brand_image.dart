import 'package:flutter/material.dart';

class AuthBrandImage extends StatelessWidget {
  const AuthBrandImage({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 184,
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -10),
          child: Transform.scale(
            scale: 1.12,
            child: Image.asset(
              'designs/lptickets.png',
              height: 176,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
