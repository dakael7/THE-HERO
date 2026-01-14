class OfferQuestion {
  final String questionId;
  final String offerId;
  final String askerId;
  final String askerName;
  final String question;
  final DateTime createdAt;
  final String? answer;
  final String? answeredById;
  final DateTime? answeredAt;

  OfferQuestion({
    required this.questionId,
    required this.offerId,
    required this.askerId,
    required this.askerName,
    required this.question,
    required this.createdAt,
    this.answer,
    this.answeredById,
    this.answeredAt,
  });

  bool get isAnswered => answer != null && answer!.trim().isNotEmpty;

  OfferQuestion copyWith({
    String? questionId,
    String? offerId,
    String? askerId,
    String? askerName,
    String? question,
    DateTime? createdAt,
    String? answer,
    String? answeredById,
    DateTime? answeredAt,
  }) {
    return OfferQuestion(
      questionId: questionId ?? this.questionId,
      offerId: offerId ?? this.offerId,
      askerId: askerId ?? this.askerId,
      askerName: askerName ?? this.askerName,
      question: question ?? this.question,
      createdAt: createdAt ?? this.createdAt,
      answer: answer ?? this.answer,
      answeredById: answeredById ?? this.answeredById,
      answeredAt: answeredAt ?? this.answeredAt,
    );
  }
}
