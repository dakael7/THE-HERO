import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:the_hero/data/providers/network_providers.dart';
import 'package:the_hero/features/shared/profile/presentation/providers/profile_provider.dart';

class _FakeUser implements User {
  _FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('currentUserIdProvider follows Google account changes', () async {
    final users = StreamController<User?>();
    final container = ProviderContainer(
      overrides: [firebaseAuthUserProvider.overrideWith((ref) => users.stream)],
    );
    addTearDown(() async {
      container.dispose();
      await users.close();
    });

    users.add(_FakeUser('account-a'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(currentUserIdProvider), 'account-a');

    users.add(_FakeUser('account-b'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(currentUserIdProvider), 'account-b');
  });
}
