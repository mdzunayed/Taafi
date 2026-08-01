import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/admin_models.dart';
import '../../../../core/models/admin_patient_detail.dart';
import '../../../../core/models/user.dart';
import '../../../../core/theme/mt_colors.dart';
import '../../../../core/theme/mt_text_styles.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/mt_error_state.dart';
import '../../admin_providers.dart';
import 'admin_table_chrome.dart';

final _patientDateFmt = DateFormat('MMM d, y');

/// "Patients" sidebar screen — accounts with `role: 'user'`. The admin
/// scans this for sign-up volume, support context, and basic moderation.
class PatientsTab extends ConsumerWidget {
  const PatientsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPatientsProvider);
    return AdminListScaffold(
      title: 'Patients',
      subtitle: 'All registered patient accounts',
      onRefresh: () async {
        ref.invalidate(adminPatientsProvider);
        await ref.read(adminPatientsProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MtErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(adminPatientsProvider),
        ),
        data: (rows) => rows.isEmpty
            ? const AdminEmptyState(
                icon: Icons.people_outline,
                title: 'No patients yet',
                subtitle: 'New sign-ups will appear here automatically.',
              )
            : _PatientsTable(rows: rows),
      ),
    );
  }
}

class _PatientsTable extends StatelessWidget {
  final List<User> rows;
  const _PatientsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(MtColors.brandSofter),
          headingTextStyle: MtTextStyles.labelSm.copyWith(
            color: MtColors.ink3,
            letterSpacing: 0.8,
          ),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('NAME')),
            DataColumn(label: Text('PHONE')),
            DataColumn(label: Text('EMAIL')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final u in rows)
              DataRow(
                onSelectChanged: (_) => _openPatientDetail(context, u),
                cells: [
                  DataCell(_NameCell(name: u.name)),
                  DataCell(Text(u.phone.isEmpty ? '—' : u.phone,
                      style: MtTextStyles.bodyMd
                          .copyWith(color: MtColors.ink2))),
                  DataCell(Text(u.email.isEmpty ? '—' : u.email,
                      style: MtTextStyles.bodyMd
                          .copyWith(color: MtColors.ink2))),
                  DataCell(_StatusPill(label: u.accountStatus)),
                  DataCell(TextButton.icon(
                    onPressed: () => _openPatientDetail(context, u),
                    icon: const Icon(Icons.folder_shared_outlined, size: 15),
                    label: Text('History', style: MtTextStyles.labelMd),
                    style: TextButton.styleFrom(
                        foregroundColor: MtColors.brand),
                  )),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

void _openPatientDetail(BuildContext context, User patient) {
  showDialog<void>(
    context: context,
    builder: (_) => _PatientDetailDialog(patient: patient),
  );
}

/// Clinical drill-down: the patient's medical vault + care-request history,
/// fetched on open via [adminPatientDetailProvider].
class _PatientDetailDialog extends ConsumerWidget {
  final User patient;
  const _PatientDetailDialog({required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPatientDetailProvider(patient.id));
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  InitialsAvatar(
                    name: patient.name,
                    size: 44,
                    backgroundColor: MtColors.brandSoft,
                    textColor: MtColors.brand,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.name, style: MtTextStyles.h3),
                        Text(
                            [
                              if (patient.phone.isNotEmpty) patient.phone,
                              if (patient.email.isNotEmpty) patient.email,
                            ].join(' · '),
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink3)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => MtErrorState(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(
                        adminPatientDetailProvider(patient.id)),
                  ),
                  data: (detail) =>
                      _PatientDetailBody(detail: detail),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientDetailBody extends StatelessWidget {
  final AdminPatientDetail detail;
  const _PatientDetailBody({required this.detail});

  @override
  Widget build(BuildContext context) {
    final vault = detail.vault;
    final requests = detail.careRequests;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Medical vault ────────────────────────────────────────────
          Text('MEDICAL VAULT',
              style: MtTextStyles.labelSm.copyWith(
                color: MtColors.ink3,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 8),
          _VaultGrid(
            bloodType: vault.bloodType,
            allergies: vault.allergies,
            chronic: vault.chronicConditions,
            notes: vault.emergencyNotes,
          ),
          const SizedBox(height: 20),
          // ── Care-request history ─────────────────────────────────────
          Row(
            children: [
              Text('BOOKING HISTORY',
                  style: MtTextStyles.labelSm.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 0.8,
                  )),
              const SizedBox(width: 8),
              Text('(${requests.length})',
                  style: MtTextStyles.labelSm.copyWith(color: MtColors.ink3)),
            ],
          ),
          const SizedBox(height: 8),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No bookings yet.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
            )
          else
            for (final r in requests) _HistoryRow(request: r),
        ],
      ),
    );
  }
}

class _VaultGrid extends StatelessWidget {
  final String bloodType;
  final List<String> allergies;
  final List<String> chronic;
  final String notes;
  const _VaultGrid({
    required this.bloodType,
    required this.allergies,
    required this.chronic,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MtColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _vaultLine('Blood type', bloodType.isEmpty ? 'Unknown' : bloodType),
          _vaultLine('Allergies',
              allergies.isEmpty ? 'None recorded' : allergies.join(', ')),
          _vaultLine('Chronic conditions',
              chronic.isEmpty ? 'None recorded' : chronic.join(', ')),
          _vaultLine('Emergency notes',
              notes.trim().isEmpty ? '—' : notes, last: true),
        ],
      ),
    );
  }

  Widget _vaultLine(String label, String value, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label.toUpperCase(),
                style: MtTextStyles.labelSm.copyWith(
                  color: MtColors.ink3,
                  letterSpacing: 0.5,
                )),
          ),
          Expanded(
            child: Text(value,
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final AdminCareRequest request;
  const _HistoryRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
                const SizedBox(height: 2),
                Text('${_patientDateFmt.format(r.createdAt)} · ${r.area}',
                    style:
                        MtTextStyles.bodySm.copyWith(color: MtColors.ink3)),
              ],
            ),
          ),
          _StatusPill(label: r.status),
        ],
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  final String name;
  const _NameCell({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialsAvatar(
          name: name,
          size: 32,
          backgroundColor: MtColors.brandSoft,
          textColor: MtColors.brand,
        ),
        const SizedBox(width: 10),
        Text(name,
            style: MtTextStyles.labelMd.copyWith(color: MtColors.ink)),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final active = label.toLowerCase() == 'active';
    final fg = active ? MtColors.completed : MtColors.ink3;
    final bg = active ? MtColors.completedBg : MtColors.bg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style:
            MtTextStyles.labelSm.copyWith(color: fg, fontSize: 9),
      ),
    );
  }
}
