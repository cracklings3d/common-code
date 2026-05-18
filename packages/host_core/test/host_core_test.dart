import 'package:host_core/host_core.dart';
import 'package:test/test.dart';

void main() {
  group('host_core', () {
    test('exports the placeholder descriptor', () {
      expect(hostCoreDescriptor.label, 'host_core placeholder contract');
    });
  });
}
