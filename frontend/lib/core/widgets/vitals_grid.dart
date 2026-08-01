import 'package:flutter/material.dart';

import '../theme/mt_colors.dart';
import '../theme/mt_text_styles.dart';

/// Lightweight vitals view-model shared across the chat sidebar and the
/// nurse dashboard. All fields are nullable so a half-filled set still
/// renders cleanly (each tile shows an em-dash for missing values).
class PatientVitals {
  final String? bloodPressure; // "120/80 mmHg"
  final String? temperature; // "98.6 °F"
  final String? spo2; // "98%"
  final String? heartRate; // "72 bpm"

  const PatientVitals({
    this.bloodPressure,
    this.temperature,
    this.spo2,
    this.heartRate,
  });

  /// Build from the snake_case `care_requests.vitals` sub-doc shape
  /// (`blood_pressure`, `temperature`, `spo2`, `pulse`, plus matching
  /// `*_unit` siblings). Returns [empty] when the input is null/empty
  /// so the caller can pass through `PatientVitals.fromJson(rawMap)`
  /// unconditionally.
  factory PatientVitals.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    String? withUnit(String key, String unitKey, String defaultUnit) {
      final v = j[key];
      if (v == null || v.toString().trim().isEmpty) return null;
      final unit = (j[unitKey] ?? defaultUnit).toString();
      return '$v $unit'.trim();
    }

    return PatientVitals(
      bloodPressure: withUnit('blood_pressure', 'blood_pressure_unit', 'mmHg'),
      temperature: withUnit('temperature', 'temperature_unit', '°F'),
      spo2: withUnit('spo2', 'spo2_unit', '%'),
      heartRate: withUnit('pulse', 'pulse_unit', 'bpm'),
    );
  }

  static const PatientVitals empty = PatientVitals();
}

/// 2×2 vitals grid (BP / Temp / SpO₂ / Heart rate). Used by the
/// chat sidebar's doctor-side context panel AND the new nurse dashboard
/// `YOUR LATEST VITALS` section, so the visual treatment stays in
/// lockstep across surfaces.
class VitalsGrid extends StatelessWidget {
  final PatientVitals vitals;
  const VitalsGrid({super.key, required this.vitals});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _VitalTile(
                icon: Icons.favorite_outline,
                accent: MtColors.rejected,
                label: 'BP',
                value: vitals.bloodPressure ?? '—',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VitalTile(
                icon: Icons.thermostat,
                accent: const Color(0xFFF59E0B),
                label: 'Temp',
                value: vitals.temperature ?? '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _VitalTile(
                icon: Icons.air,
                accent: const Color(0xFF2563EB),
                label: 'SpO₂',
                value: vitals.spo2 ?? '—',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _VitalTile(
                icon: Icons.monitor_heart_outlined,
                accent: MtColors.brand,
                label: 'Heart rate',
                value: vitals.heartRate ?? '—',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VitalTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  const _VitalTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ],
      ),
    );
  }
}
