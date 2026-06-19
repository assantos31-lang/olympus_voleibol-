import 'package:flutter/material.dart';
import 'coach_received_evaluations_page.dart';

class CoachEvaluationsHubExtensions {
  static void openReceivedEvaluations(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CoachReceivedEvaluationsPage(),
      ),
    );
  }
}
