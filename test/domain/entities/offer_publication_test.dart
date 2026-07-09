import 'package:flutter_test/flutter_test.dart';
import 'package:the_hero/domain/entities/offer.dart';

void main() {
  test('donation publication requires both answers to be yes', () {
    expect(
      donationPublicationAnswersAreYes(
        isInGoodState: true,
        worksCorrectly: true,
      ),
      isTrue,
    );
    expect(
      donationPublicationAnswersAreYes(
        isInGoodState: true,
        worksCorrectly: false,
      ),
      isFalse,
    );
    expect(
      donationPublicationAnswersAreYes(
        isInGoodState: false,
        worksCorrectly: true,
      ),
      isFalse,
    );
    expect(
      donationPublicationAnswersAreYes(
        isInGoodState: null,
        worksCorrectly: true,
      ),
      isFalse,
    );
  });
}
