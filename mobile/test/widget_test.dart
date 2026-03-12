import "package:edusys_mobile/main.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("App boots", (WidgetTester tester) async {
    await tester.pumpWidget(const EduSysApp());
    expect(find.text("EduSys"), findsWidgets);
  });
}
