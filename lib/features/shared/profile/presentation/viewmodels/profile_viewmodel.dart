import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

class ProfileState {
  final int publications;
  final int favorites;
  final int purchases;

  const ProfileState({
    this.publications = 0,
    this.favorites = 0,
    this.purchases = 0,
  });

  ProfileState copyWith({
    int? publications,
    int? favorites,
    int? purchases,
  }) {
    return ProfileState(
      publications: publications ?? this.publications,
      favorites: favorites ?? this.favorites,
      purchases: purchases ?? this.purchases,
    );
  }
}

class ProfileViewModel extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    return const ProfileState();
  }

  void updateStats({
    int? publications,
    int? favorites,
    int? purchases,
  }) {
    state = state.copyWith(
      publications: publications,
      favorites: favorites,
      purchases: purchases,
    );
  }
}

final profileViewModelProvider =
    NotifierProvider<ProfileViewModel, ProfileState>(
  () => ProfileViewModel(),
);
