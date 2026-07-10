import 'package:flutter_test/flutter_test.dart';
import 'package:moonlight_tizen_flutter/ui/moonlight_ui.dart';

void main() {
  testWidgets('browser harness starts on the hosts screen', (tester) async {
    await tester.pumpWidget(const FakeMoonlightApp());
    await tester.pump();

    expect(find.text('HOSTS'), findsOneWidget);
    expect(find.text('ADD HOST'), findsOneWidget);
    expect(find.text('Living Room PC'), findsOneWidget);
  });
}
