import 'package:common_code_domain/common_code_domain.dart';
import 'package:test/test.dart';

void main() {
  group('common_code_domain', () {
    test('exports the placeholder descriptor', () {
      expect(
        commonCodeDomainDescriptor.label,
        'common_code_domain placeholder contract',
      );
    });
  });
}
