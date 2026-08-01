/// Who attends a booking — and every piece of copy that depends on it.
///
/// A booking's provider type is not decoration: it words four of the six
/// tracker steps ("Nurse On the Way" vs "Doctor On the Way"), names the
/// registration number on the assigned-provider card (BMDC vs Nursing
/// Council), and picks the pre-arrival preparation tip.
///
/// MIRROR: `backend/src/utils/providerTypes.js` is the authoritative copy of
/// the enum and every table below. The server already ships resolved,
/// role-aware labels on each booking, so this file is normally only the
/// fallback — but mobile builds are not force-updated, and a client talking to
/// an API that predates the tracker's role awareness would otherwise render
/// generic "Provider" copy. Keep the two in sync when adding a role.
library;

enum ProviderType { doctor, nurse, physiotherapist, labTech }

extension ProviderTypeX on ProviderType {
  /// The type a booking falls back to when nothing else can be resolved. Home
  /// nursing is the majority of the catalog, so it is the least surprising
  /// answer for an untagged row — same default the backend applies.
  static const ProviderType fallback = ProviderType.nurse;

  String toWire() {
    switch (this) {
      case ProviderType.doctor:
        return 'DOCTOR';
      case ProviderType.nurse:
        return 'NURSE';
      case ProviderType.physiotherapist:
        return 'PHYSIOTHERAPIST';
      case ProviderType.labTech:
        return 'LAB_TECH';
    }
  }

  /// Parses a wire value, returning `null` for anything unrecognised so the
  /// caller can decide whether to fall back or keep looking.
  static ProviderType? tryFromWire(String? raw) {
    final key = (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (key.isEmpty) return null;
    switch (key) {
      case 'doctor':
      case 'physician':
      case 'dr':
        return ProviderType.doctor;
      case 'nurse':
      case 'nursing':
        return ProviderType.nurse;
      case 'physiotherapist':
      case 'physiotherapy':
      case 'physio':
      case 'therapist':
        return ProviderType.physiotherapist;
      case 'labtech':
      case 'lab':
      case 'labtechnician':
      case 'phlebotomist':
        return ProviderType.labTech;
      default:
        return null;
    }
  }

  /// Parses a wire value, falling back to [fallback].
  static ProviderType fromWire(String? raw) => tryFromWire(raw) ?? fallback;

  /// Role noun for badges and sentence copy — "Call Nurse", "Your Doctor".
  String get roleLabel {
    switch (this) {
      case ProviderType.doctor:
        return 'Doctor';
      case ProviderType.nurse:
        return 'Nurse';
      case ProviderType.physiotherapist:
        return 'Physiotherapist';
      case ProviderType.labTech:
        return 'Lab Technician';
    }
  }

  /// Which council the provider's registration number belongs to, shown as its
  /// prefix on the provider card ("BMDC #B-54123").
  String get registrationLabel {
    switch (this) {
      case ProviderType.doctor:
        return 'BMDC';
      case ProviderType.nurse:
        return 'BNMC';
      case ProviderType.physiotherapist:
        return 'BPA';
      case ProviderType.labTech:
        return 'Reg';
    }
  }

  /// What the patient should have ready. Shown only while the provider is on
  /// their way or already working — the window where it can still change the
  /// outcome of the visit.
  String get preparationTip {
    switch (this) {
      case ProviderType.doctor:
        return 'Please keep your past medical prescriptions and recent lab '
            'reports ready.';
      case ProviderType.nurse:
        return 'Ensure a clean, well-lit space and adequate water access for '
            'procedure setup.';
      case ProviderType.physiotherapist:
        return 'Clear a firm, flat space to move in and wear loose clothing. '
            'Keep any previous imaging or therapy notes at hand.';
      case ProviderType.labTech:
        return 'Follow any fasting instructions given for your test, keep your '
            'ID and prior reports handy, and sit in a well-lit spot.';
    }
  }

  /// Role-aware wording for the four tracker steps that name the attending
  /// provider, keyed by milestone wire key. Steps 1 (REQUESTED) and 6
  /// (COMPLETED) are role-neutral and are absent here.
  ///
  /// [ProviderType.physiotherapist] says "Specialist" rather than repeating
  /// the full noun — the wording the tracker spec calls for, and it keeps the
  /// step off a third line on a narrow handset.
  Map<String, String> get _milestoneCopy {
    switch (this) {
      case ProviderType.doctor:
        return const {
          'CONFIRMED': 'Confirmed — Assigning Doctor',
          'SCHEDULED': 'Doctor Assigned — Scheduled',
          'EN_ROUTE': 'Doctor On the Way',
          'IN_SERVICE': 'Doctor Consultation in Progress',
        };
      case ProviderType.nurse:
        return const {
          'CONFIRMED': 'Confirmed — Assigning Nurse',
          'SCHEDULED': 'Nurse Assigned — Scheduled',
          'EN_ROUTE': 'Nurse On the Way',
          'IN_SERVICE': 'Nursing Care in Progress',
        };
      case ProviderType.physiotherapist:
        return const {
          'CONFIRMED': 'Confirmed — Assigning Specialist',
          'SCHEDULED': 'Specialist Assigned — Scheduled',
          'EN_ROUTE': 'Specialist On the Way',
          'IN_SERVICE': 'Therapy Session in Progress',
        };
      case ProviderType.labTech:
        return const {
          'CONFIRMED': 'Confirmed — Assigning Lab Technician',
          'SCHEDULED': 'Lab Technician Assigned — Scheduled',
          'EN_ROUTE': 'Lab Technician On the Way',
          'IN_SERVICE': 'Sample Collection in Progress',
        };
    }
  }

  /// Role-aware label for a milestone wire key, or `null` when that step
  /// carries no role-specific wording.
  String? milestoneCopy(String milestoneKey) => _milestoneCopy[milestoneKey];
}
