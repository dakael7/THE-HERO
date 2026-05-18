class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final bool isAuthenticated;
  final String? loadingMessage;
  final double? uploadProgress;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.isAuthenticated = false,
    this.loadingMessage,
    this.uploadProgress,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? isAuthenticated,
    String? loadingMessage,
    double? uploadProgress,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      loadingMessage: loadingMessage,
      uploadProgress: uploadProgress,
    );
  }

  factory AuthState.initial() {
    return const AuthState();
  }
}
