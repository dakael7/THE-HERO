import 'env.dart';

class DonationPricingConfig {
  const DonationPricingConfig._();

  static double get buyerShippingCost =>
      Env.donationBuyerShippingCostCLP.toDouble();
  static double get buyerServiceFee => Env.donationBuyerServiceFeeCLP.toDouble();
  static double get taxPercentage => Env.donationTaxBasisPoints / 10000.0;
}
