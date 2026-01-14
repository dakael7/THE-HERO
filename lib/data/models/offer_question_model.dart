import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../domain/entities/offer_question.dart';

class OfferQuestionModel {
  final String questionId;
  final String offerId;
  final String askerId;
  final String askerName;
  final String question;
  final firestore.Timestamp createdAt;
  final String? answer;
  final String? answeredById;
  final firestore.Timestamp? answeredAt;

  OfferQuestionModel({
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

  factory OfferQuestionModel.fromJson(Map<String, dynamic> json) {
    return OfferQuestionModel(
      questionId: json['questionId'] as String? ?? '',
      offerId: json['offerId'] as String? ?? '',
      askerId: json['askerId'] as String? ?? '',
      askerName: json['askerName'] as String? ?? 'Usuario',
      question: json['question'] as String? ?? '',
      createdAt:
          json['createdAt'] as firestore.Timestamp? ?? firestore.Timestamp.now(),
      answer: json['answer'] as String?,
      answeredById: json['answeredById'] as String?,
      answeredAt: json['answeredAt'] as firestore.Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questionId': questionId,
      'offerId': offerId,
      'askerId': askerId,
      'askerName': askerName,
      'question': question,
      'createdAt': createdAt,
      'answer': answer,
      'answeredById': answeredById,
      'answeredAt': answeredAt,
    };
  }

  OfferQuestion toEntity() {
    return OfferQuestion(
      questionId: questionId,
      offerId: offerId,
      askerId: askerId,
      askerName: askerName,
      question: question,
      createdAt: createdAt.toDate(),
      answer: answer,
      answeredById: answeredById,
      answeredAt: answeredAt?.toDate(),
    );
  }

  factory OfferQuestionModel.fromEntity(OfferQuestion entity) {
    return OfferQuestionModel(
      questionId: entity.questionId,
      offerId: entity.offerId,
      askerId: entity.askerId,
      askerName: entity.askerName,
      question: entity.question,
      createdAt: firestore.Timestamp.fromDate(entity.createdAt),
      answer: entity.answer,
      answeredById: entity.answeredById,
      answeredAt: entity.answeredAt != null
          ? firestore.Timestamp.fromDate(entity.answeredAt!)
          : null,
    );
  }
}
