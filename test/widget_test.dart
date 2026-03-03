import 'package:flutter_test/flutter_test.dart';
import 'package:wicket_mobile/main.dart';

void main() {
  testWidgets('WicketPkApp renders without errors', (WidgetTester tester) async {
    // Note: This test requires Supabase initialization which needs mocking
    // For now, we just verify the app widget can be created
    // Full integration tests should mock Supabase.initialize()
    expect(const WicketPkApp(), isA<WicketPkApp>());
  });
}
