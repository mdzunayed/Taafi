import 'package:flutter/material.dart';
import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

enum ProgressStep { onTheWay, arrived, inService, completed }

class StatusProgressBar extends StatefulWidget {
  final ProgressStep currentStep;
  final Duration animationDuration;

  const StatusProgressBar({
    super.key,
    required this.currentStep,
    this.animationDuration = const Duration(milliseconds: 400),
  });

  @override
  State<StatusProgressBar> createState() => _StatusProgressBarState();
}

class _StatusProgressBarState extends State<StatusProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animationController.forward();
  }

  @override
  void didUpdateWidget(StatusProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStep != widget.currentStep) {
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  int _getStepIndex(ProgressStep step) {
    switch (step) {
      case ProgressStep.onTheWay:
        return 0;
      case ProgressStep.arrived:
        return 1;
      case ProgressStep.inService:
        return 2;
      case ProgressStep.completed:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getStepIndex(widget.currentStep);
    final steps = ['On the way', 'Arrived', 'In service', 'Completed'];

    return Column(
      children: [
        // Progress bar
        Row(
          children: List.generate(
            steps.length,
            (index) => Expanded(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  final isFilled = index <= currentIndex;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: isFilled ? MtColors.brand : MtColors.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (index < steps.length - 1)
                        SizedBox(
                          width: 4,
                          height: 4,
                          child: Container(color: MtColors.surface),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Labels
        Row(
          children: List.generate(
            steps.length,
            (index) => Expanded(
              child: Text(
                steps[index],
                textAlign: TextAlign.center,
                style:
                    (index == currentIndex
                            ? MtTextStyles.labelMd
                            : MtTextStyles.bodySm)
                        .copyWith(
                          color: index <= currentIndex
                              ? MtColors.brand
                              : MtColors.ink3,
                          fontWeight: index == currentIndex
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
