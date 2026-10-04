@import XCTest;
@import integration_test;

// Runs integration_test/picker_test.dart (the target of `flutter build ios --config-only`) as
// XCTest cases: unlike `flutter test`, it doesn't depend on the tool finding the app's VM
// service, which often fails on iOS simulators (flutter/flutter#181771).
INTEGRATION_TEST_IOS_RUNNER(RunnerTests)
