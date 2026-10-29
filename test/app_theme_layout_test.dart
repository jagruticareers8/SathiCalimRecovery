import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sathi_claim_recovery/core/theme/app_theme.dart';

void main() {
  test('global button themes use finite minimum widths', () {
    final filled = AppTheme.light.filledButtonTheme.style!;
    final outlined = AppTheme.light.outlinedButtonTheme.style!;
    final filledSize = filled.minimumSize!.resolve(const <WidgetState>{})!;
    final outlinedSize = outlined.minimumSize!.resolve(const <WidgetState>{})!;

    expect(filledSize.width.isFinite, isTrue);
    expect(outlinedSize.width.isFinite, isTrue);
    expect(filledSize.height, 48);
    expect(outlinedSize.height, 46);
  });
}
