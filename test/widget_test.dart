import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sathi_claim_recovery/app.dart';
import 'package:sathi_claim_recovery/features/claim/data/claim_analysis_service.dart';
import 'package:sathi_claim_recovery/features/claim/presentation/providers/claim_controller.dart';

void main() {
  testWidgets('Sathi opens the dashboard with the seeded demo claim', (tester) async {
    await tester.pumpWidget(
      BlocProvider<ClaimCubit>(
        create: (_) => ClaimCubit(DemoClaimAnalysisService()),
        child: const SathiApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sathi'), findsOneWidget);
    expect(find.text('Your health claim needs attention'), findsOneWidget);
    expect(find.text('Review my claim'), findsOneWidget);
    expect(find.text('DEMO DATA'), findsOneWidget);
  });
}
