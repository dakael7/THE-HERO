import 'package:flutter_riverpod/flutter_riverpod.dart';

class RiderHomeState {
  final int selectedNavIndex;
  final bool isLoading;

  const RiderHomeState({this.selectedNavIndex = 0, this.isLoading = false});

  RiderHomeState copyWith({int? selectedNavIndex, bool? isLoading}) {
    return RiderHomeState(
      selectedNavIndex: selectedNavIndex ?? this.selectedNavIndex,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class RiderHomeViewModel extends Notifier<RiderHomeState> {
  @override
  RiderHomeState build() {
    return const RiderHomeState();
  }

  void selectNavItem(int index) {
    state = state.copyWith(selectedNavIndex: index);
  }

  void reset() {
    state = const RiderHomeState();
  }
}

final riderHomeViewModelProvider =
    NotifierProvider<RiderHomeViewModel, RiderHomeState>(() {
      return RiderHomeViewModel();
    });
