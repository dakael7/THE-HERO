import 'package:flutter/material.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/offer.dart';
import 'offer_form_screen.dart';

class DonationQuestionsScreen extends StatefulWidget {
  final Offer? initialOffer;

  const DonationQuestionsScreen({super.key, this.initialOffer});

  @override
  State<DonationQuestionsScreen> createState() => _DonationQuestionsScreenState();
}

class _DonationQuestionsScreenState extends State<DonationQuestionsScreen> {
  bool? _isInGoodState;
  bool? _worksCorrectly;

  @override
  void initState() {
    super.initState();
    final offer = widget.initialOffer;
    _isInGoodState = offer?.isInGoodState;
    _worksCorrectly = offer?.worksCorrectly;
  }

  bool get _canContinue => _isInGoodState != null && _worksCorrectly != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: const HeroHeaderAppBar(
        title: 'Preguntas',
        icon: Icons.quiz_rounded,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Está en buen estado?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _YesNoCard(
                    label: 'Sí',
                    selected: _isInGoodState == true,
                    yes: true,
                    onTap: () => setState(() => _isInGoodState = true),
                  ),
                  const SizedBox(width: 12),
                  _YesNoCard(
                    label: 'No',
                    selected: _isInGoodState == false,
                    yes: false,
                    onTap: () => setState(() => _isInGoodState = false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '¿Funciona correctamente?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _YesNoCard(
                    label: 'Sí',
                    selected: _worksCorrectly == true,
                    yes: true,
                    onTap: () => setState(() => _worksCorrectly = true),
                  ),
                  const SizedBox(width: 12),
                  _YesNoCard(
                    label: 'No',
                    selected: _worksCorrectly == false,
                    yes: false,
                    onTap: () => setState(() => _worksCorrectly = false),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canContinue
                      ? () async {
                          final result = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => OfferFormScreen(
                                initialOffer: widget.initialOffer,
                                initialIsInGoodState: _isInGoodState,
                                initialWorksCorrectly: _worksCorrectly,
                                hideConditionQuestions: true,
                              ),
                            ),
                          );

                          if (!context.mounted) return;
                          Navigator.of(context).pop(result);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: backgroundWhite,
                    disabledBackgroundColor: borderGray100,
                    disabledForegroundColor: textGray600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continuar',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YesNoCard extends StatelessWidget {
  final String label;
  final bool selected;
  final bool yes;
  final VoidCallback onTap;

  const _YesNoCard({
    required this.label,
    required this.selected,
    required this.yes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? primaryOrange : borderGray100;
    final icon = yes ? Icons.check_circle_outline : Icons.cancel_outlined;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: textGray600),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
