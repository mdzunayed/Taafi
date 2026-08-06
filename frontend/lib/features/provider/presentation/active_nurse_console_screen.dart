import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/doctor_dashboard.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../auth/auth_provider.dart';
import '../../shared/presentation/widgets/active_chat_drawer.dart';
import '../providers/nurse_workflow_provider.dart';
import 'collect_cash_panel.dart';
import 'widgets/patient_documents_panel.dart';
import 'widgets/target_patient_panel.dart';

/// Phase 3 + 4 of the Nurse Operations Hub: a full-screen procedural
/// terminal for on-site care. Vitals ingestion form + context-aware task
/// checklist + live chat/call utilities + the Complete-Care-Session engine.
///
/// Layout cap: `Center → ConstrainedBox(maxWidth: 600)` so it stays
/// readable on wide web / tablet viewports.
class ActiveNurseConsoleScreen extends ConsumerStatefulWidget {
  final UpcomingAppointment appointment;
  const ActiveNurseConsoleScreen({super.key, required this.appointment});

  @override
  ConsumerState<ActiveNurseConsoleScreen> createState() =>
      _ActiveNurseConsoleScreenState();
}

class _ActiveNurseConsoleScreenState
    extends ConsumerState<ActiveNurseConsoleScreen> {
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _heartRate = TextEditingController();
  final _spo2 = TextEditingController();
  final _temperature = TextEditingController();
  final _bloodSugar = TextEditingController();

  /// Procedures ticked on the multi-select chips — the structured care log
  /// posted alongside the vitals at completion.
  final Set<String> _procedures = <String>{};

  bool _savingVitals = false;
  bool _completing = false;

  UpcomingAppointment get _appt => widget.appointment;
  String get _accountId => _appt.patientAccountId ?? '';

  @override
  void dispose() {
    _systolic.dispose();
    _diastolic.dispose();
    _heartRate.dispose();
    _spo2.dispose();
    _temperature.dispose();
    _bloodSugar.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? MtColors.rejected : MtColors.completed,
    ));
  }

  /// Validates the vitals form. Returns an error string, or null when the
  /// (partially-filled) form is acceptable. Empty fields are allowed; only
  /// filled fields must parse to an in-range number.
  String? _validateVitals() {
    int? n(TextEditingController c) =>
        c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    double? d(TextEditingController c) =>
        c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

    bool filled(TextEditingController c) => c.text.trim().isNotEmpty;

    if (filled(_systolic) != filled(_diastolic)) {
      return 'Enter both systolic and diastolic blood pressure';
    }
    final sys = n(_systolic);
    final dia = n(_diastolic);
    if (sys != null && (sys < 50 || sys > 300)) return 'Systolic looks out of range';
    if (dia != null && (dia < 30 || dia > 200)) return 'Diastolic looks out of range';
    final hr = n(_heartRate);
    if (filled(_heartRate) && hr == null) return 'Heart rate must be a number';
    if (hr != null && (hr < 20 || hr > 250)) return 'Heart rate looks out of range';
    final spo2 = n(_spo2);
    if (filled(_spo2) && spo2 == null) return 'SpO₂ must be a number';
    if (spo2 != null && (spo2 < 50 || spo2 > 100)) return 'SpO₂ must be 50–100%';
    final temp = d(_temperature);
    if (filled(_temperature) && temp == null) return 'Temperature must be a number';
    if (temp != null && (temp < 80 || temp > 115)) return 'Temperature looks out of range';
    final rbs = d(_bloodSugar);
    if (filled(_bloodSugar) && rbs == null) return 'Blood sugar must be a number';
    return null;
  }

  /// Builds the wire payload from the form. `bloodPressure` collapses the
  /// systolic/diastolic pair into the "S/D" string the schema stores.
  ({String? bp, String? hr, String? spo2, String? temp, String? rbs})
      _vitalsPayload() {
    final sys = _systolic.text.trim();
    final dia = _diastolic.text.trim();
    final bp = (sys.isNotEmpty && dia.isNotEmpty) ? '$sys/$dia' : null;
    return (
      bp: bp,
      hr: _heartRate.text.trim().isEmpty ? null : _heartRate.text.trim(),
      spo2: _spo2.text.trim().isEmpty ? null : _spo2.text.trim(),
      temp:
          _temperature.text.trim().isEmpty ? null : _temperature.text.trim(),
      rbs: _bloodSugar.text.trim().isEmpty ? null : _bloodSugar.text.trim(),
    );
  }

  /// The care log as a sorted list for the wire (chips are held in a Set).
  List<String>? _procedureList() =>
      _procedures.isEmpty ? null : _procedures.toList();

  Future<void> _saveVitals() async {
    final err = _validateVitals();
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    final v = _vitalsPayload();
    if (v.bp == null &&
        v.hr == null &&
        v.spo2 == null &&
        v.temp == null &&
        v.rbs == null &&
        _procedures.isEmpty) {
      _toast('Enter at least one vital reading or procedure first',
          error: true);
      return;
    }
    setState(() => _savingVitals = true);
    try {
      await ref.read(nurseWorkflowProvider).saveVitals(
            _appt.id,
            bloodPressure: v.bp,
            pulse: v.hr,
            spo2: v.spo2,
            temperature: v.temp,
            bloodSugar: v.rbs,
            procedures: _procedureList(),
          );
      _toast('Vitals saved to the patient record.');
    } catch (e) {
      _toast('Could not save vitals: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingVitals = false);
    }
  }

  Future<void> _openChat() async {
    final me = ref.read(currentUserProvider);
    final patientId = _accountId;
    if (me == null || patientId.isEmpty || _appt.id.isEmpty) {
      _toast('Chat is not available for this visit yet', error: true);
      return;
    }
    // Slide-in communication drawer — text/image/location chat plus the
    // in-header "Call via Secure Line" masked-calling button.
    await openActiveChatDrawer(
      context,
      appointmentId: _appt.id,
      currentUserId: me.id,
      otherUserId: patientId,
      otherUserName: _appt.patientName,
      otherRoleLabel: 'Patient',
    );
  }

  Future<void> _call() async {
    final phone = _appt.patientPhone;
    if (phone == null || phone.isEmpty) {
      _toast('Patient phone is not available yet', error: true);
      return;
    }
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok) _toast('No phone app available to place the call', error: true);
  }

  /// Phase 4 — open the summary sheet, then POST vitals + summary to
  /// `/api/appointments/:id/complete` and return to the dispatch terminal.
  Future<void> _completeSession() async {
    final err = _validateVitals();
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    final summary = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SummarySheet(),
    );
    if (summary == null || !mounted) return; // cancelled

    final v = _vitalsPayload();
    setState(() => _completing = true);
    try {
      final updated = await ref.read(nurseWorkflowProvider).completeSession(
            _appt.id,
            bloodPressure: v.bp,
            pulse: v.hr,
            spo2: v.spo2,
            temperature: v.temp,
            bloodSugar: v.rbs,
            procedures: _procedureList(),
            summary: summary,
          );
      if (!mounted) return;
      _toast('Care session completed & logged.');
      // Nurse-only visits settle their balance at the door too: if the
      // completion parked the booking in the payment-due state, offer
      // cash collection before leaving the console. (When a doctor is
      // still owed the prescription the visit parks in `nurse_completed`
      // instead, and the panel no-ops.)
      await offerCashCollection(
        context,
        ref,
        appointment: updated,
        patientName: _appt.patientName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _completing = false);
        _toast('Could not complete the session: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: AppBar(
        backgroundColor: MtColors.surface,
        foregroundColor: MtColors.ink,
        elevation: 0,
        title: const Text('Nursing Procedural Terminal'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: MtColors.line),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _PatientHeaderCard(appt: _appt),
                      // Payment posture, stated up front so the nurse knows
                      // before they start whether a cash handoff is coming —
                      // and kept live, so a patient switching to (or
                      // completing) online payment mid-visit flips this card
                      // instead of leaving a stale cash prompt on screen.
                      const SizedBox(height: 12),
                      BookingPaymentBanner(
                        bookingId: _appt.id,
                        fallbackIsCashOnService: _appt.isCashOnService,
                      ),
                      // Discharge summaries, old prescriptions, lab reports.
                      // Above the vitals form deliberately: a wound-care or
                      // post-op visit is often defined by the document the
                      // patient attached, and reading it after logging vitals
                      // is reading it too late.
                      const SizedBox(height: 12),
                      PatientDocumentsPanel(bookingId: _appt.id),
                      const SizedBox(height: 20),
                      _SectionLabel('Patient vitals ingestion'),
                      const SizedBox(height: 8),
                      _VitalsForm(
                        systolic: _systolic,
                        diastolic: _diastolic,
                        heartRate: _heartRate,
                        spo2: _spo2,
                        temperature: _temperature,
                        bloodSugar: _bloodSugar,
                        saving: _savingVitals,
                        onSave: _saveVitals,
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel('Procedures performed'),
                      const SizedBox(height: 8),
                      _ProcedureChips(
                        selected: _procedures,
                        onToggle: (label) => setState(() {
                          _procedures.contains(label)
                              ? _procedures.remove(label)
                              : _procedures.add(label);
                        }),
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel('Live synchronization utilities'),
                      const SizedBox(height: 8),
                      _SyncUtilitiesRow(onChat: _openChat, onCall: _call),
                    ],
                  ),
                ),
                _CompleteFooter(busy: _completing, onTap: _completeSession),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient header
// ---------------------------------------------------------------------------

class _PatientHeaderCard extends StatelessWidget {
  final UpcomingAppointment appt;
  const _PatientHeaderCard({required this.appt});

  @override
  Widget build(BuildContext context) {
    final address = appt.address;
    // Family-member booking: the visit is FOR the recipient — show them as
    // the patient, with the account holder noted as who booked it.
    final recipient = appt.careRecipient;
    final displayName =
        recipient != null ? recipient.name : appt.patientName;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                name: displayName,
                size: 52,
                backgroundColor: const Color(0xFFDBEAFE),
                textColor: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                        recipient != null
                            ? '${appt.serviceName} · booked by ${appt.patientName}'
                            : appt.serviceName,
                        style: MtTextStyles.bodySm
                            .copyWith(color: MtColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          if (recipient != null) ...[
            const SizedBox(height: 12),
            TargetPatientPanel(recipient: recipient),
          ],
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 16, color: MtColors.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      style: MtTextStyles.bodySm
                          .copyWith(color: MtColors.ink2)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vitals ingestion form
// ---------------------------------------------------------------------------

class _VitalsForm extends StatelessWidget {
  final TextEditingController systolic;
  final TextEditingController diastolic;
  final TextEditingController heartRate;
  final TextEditingController spo2;
  final TextEditingController temperature;
  final TextEditingController bloodSugar;
  final bool saving;
  final VoidCallback onSave;

  const _VitalsForm({
    required this.systolic,
    required this.diastolic,
    required this.heartRate,
    required this.spo2,
    required this.temperature,
    required this.bloodSugar,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: systolic,
                  label: 'Systolic',
                  suffix: 'mmHg',
                  icon: Icons.favorite_outline,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('/',
                    style: TextStyle(
                        fontSize: 22,
                        color: MtColors.ink3,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: _NumField(
                  controller: diastolic,
                  label: 'Diastolic',
                  suffix: 'mmHg',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: heartRate,
                  label: 'Heart rate',
                  suffix: 'bpm',
                  icon: Icons.monitor_heart_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: spo2,
                  label: 'SpO₂',
                  suffix: '%',
                  icon: Icons.air,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: temperature,
                  label: 'Body temperature',
                  suffix: '°F',
                  icon: Icons.thermostat_outlined,
                  allowDecimal: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: bloodSugar,
                  label: 'Blood sugar (RBS)',
                  suffix: 'mmol/L',
                  icon: Icons.water_drop_outlined,
                  allowDecimal: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: MtColors.brand),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text('Save vitals to record',
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.brand)),
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.brand,
                side: const BorderSide(color: MtColors.brand),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final IconData? icon;
  final bool allowDecimal;

  const _NumField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.icon,
    this.allowDecimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        allowDecimal
            ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        suffixText: suffix,
        suffixStyle: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
        prefixIcon:
            icon == null ? null : Icon(icon, size: 18, color: MtColors.ink3),
        filled: true,
        fillColor: MtColors.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: MtColors.brand, width: 1.4),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Procedures performed — multi-select care log
// ---------------------------------------------------------------------------

class _ProcedureChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _ProcedureChips({required this.selected, required this.onToggle});

  /// The structured procedures a home-care nurse logs on-site. These labels
  /// are what get persisted to `CareRequest.procedures` and surfaced on the
  /// patient's nursing report.
  static const List<({String label, IconData icon})> _catalog = [
    (label: 'Dressing', icon: Icons.healing_outlined),
    (label: 'IV Fluid', icon: Icons.water_drop_outlined),
    (label: 'Catheter Care', icon: Icons.medical_services_outlined),
    (label: 'Lab Collection', icon: Icons.science_outlined),
    (label: 'Injections', icon: Icons.vaccines_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in _catalog)
            _ProcedureChip(
              label: p.label,
              icon: p.icon,
              active: selected.contains(p.label),
              onTap: () => onToggle(p.label),
            ),
        ],
      ),
    );
  }
}

class _ProcedureChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ProcedureChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: active ? MtColors.brand : MtColors.surface2,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: active ? MtColors.brand : MtColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle : icon,
              size: 16,
              color: active ? Colors.white : MtColors.ink3,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: MtTextStyles.labelMd.copyWith(
                color: active ? Colors.white : MtColors.ink2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live sync utilities
// ---------------------------------------------------------------------------

class _SyncUtilitiesRow extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onCall;
  const _SyncUtilitiesRow({required this.onChat, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text('Live Chat',
                  style: MtTextStyles.labelLg.copyWith(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: Text('Phone Line', style: MtTextStyles.labelLg),
              style: OutlinedButton.styleFrom(
                foregroundColor: MtColors.ink,
                side: const BorderSide(color: MtColors.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Complete footer
// ---------------------------------------------------------------------------

class _CompleteFooter extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _CompleteFooter({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: MtColors.completed,
            foregroundColor: Colors.white,
            disabledBackgroundColor: MtColors.completedBg,
            disabledForegroundColor: MtColors.completed,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.check_circle_outline, size: 20),
          label: Text(
            busy ? 'Submitting…' : 'Complete Care Session & Log Summary',
            style: MtTextStyles.labelLg
                .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary sheet
// ---------------------------------------------------------------------------

class _SummarySheet extends StatefulWidget {
  const _SummarySheet();

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: MtColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Session summary',
              style: MtTextStyles.h3.copyWith(color: MtColors.ink)),
          const SizedBox(height: 4),
          Text(
            'Record any field anomalies or follow-up notes for this visit.',
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            autofocus: true,
            style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
            decoration: InputDecoration(
              hintText:
                  'e.g. Patient\'s blood pressure remains slightly elevated '
                  'post-injection.',
              hintStyle: MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
              filled: true,
              fillColor: MtColors.surface2,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: MtColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: MtColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: MtColors.brand, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.completed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Finalize & Submit',
                  style: MtTextStyles.labelLg
                      .copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel
          .copyWith(color: MtColors.ink3, letterSpacing: 1.0),
    );
  }
}
