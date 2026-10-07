import 'package:billiardtm/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("money is shown as whole so'm with spaced thousands", () {
    expect(formatCurrency(0), "0 so'm");
    expect(formatCurrency(500), "500 so'm");
    expect(formatCurrency(35000), "35 000 so'm");
    expect(formatCurrency(1250000), "1 250 000 so'm");
    expect(formatCurrency(35638.89), "35 639 so'm");
    expect(formatCurrency(-20000), "-20 000 so'm");
  });

  test('chart axis labels are shortened', () {
    expect(formatCompact(800), '800');
    expect(formatCompact(35000), '35 ming');
    expect(formatCompact(1200000), '1.2 mln');
  });
}
