import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';

class HeroHomeState {
  final int selectedNavIndex;

  const HeroHomeState({
    this.selectedNavIndex = 0,
  });

  HeroHomeState copyWith({
    int? selectedNavIndex,
  }) {
    return HeroHomeState(
      selectedNavIndex: selectedNavIndex ?? this.selectedNavIndex,
    );
  }
}

class HeroHomeViewModel extends Notifier<HeroHomeState> {
  @override
  HeroHomeState build() {
    return const HeroHomeState();
  }

  void selectNavItem(int index) {
    state = state.copyWith(selectedNavIndex: index);
  }

  void reset() {
    state = const HeroHomeState();
  }
}

final heroHomeViewModelProvider =
    NotifierProvider<HeroHomeViewModel, HeroHomeState>(
  () => HeroHomeViewModel(),
);
