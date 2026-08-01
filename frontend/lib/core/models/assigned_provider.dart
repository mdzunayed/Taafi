import 'package:equatable/equatable.dart';

import 'provider_type.dart';

/// The single provider the patient coordinates with directly for a dispatched
/// booking — who is coming, how to reach them, and the credential that proves
/// they are who the app says they are.
///
/// Wire source is `care_requests.assigned_provider`, frozen at dispatch time
/// and refreshed against the live provider record on every read (see
/// `backend/src/utils/doctorView.js`). Distinct from the fuller
/// `AssignedDoctor` / `AssignedNurse` profile blocks, which back the read-only
/// profile screens: this is the contact card, and it is deliberately
/// role-agnostic so the tracking screen doesn't branch on doctor-vs-nurse to
/// render one row.
///
/// Every field but [name] is nullable, and the UI simply omits what is
/// missing. A provider who never filled in a designation shows no designation
/// line — the card never invents one.
class AssignedProvider extends Equatable {
  /// Provider (or account) id the admin dispatched. Empty when the booking
  /// only carries a name.
  final String id;

  /// The role THIS provider fills, which can differ from the booking's own
  /// type — a nursing booking escalated to a doctor is attended by a doctor.
  final ProviderType type;

  final String name;
  final String? photoUrl;

  /// Dialable number. Null when the provider profile carries none, in which
  /// case the card hides both direct-contact buttons and the patient falls
  /// back to the Taafi support desk.
  final String? phone;

  /// How the role reads on the card — "Senior Care Nurse", "General
  /// Physician". Sourced from the provider's specialisation / designation.
  final String? designation;

  /// BMDC / Nursing Council registration number. Rendered behind
  /// [ProviderTypeX.registrationLabel] so a patient can tell the two apart.
  final String? registrationNo;

  final DateTime? assignedAt;

  const AssignedProvider({
    required this.id,
    required this.type,
    required this.name,
    this.photoUrl,
    this.phone,
    this.designation,
    this.registrationNo,
    this.assignedAt,
  });

  /// True when the patient can actually reach this provider directly. The
  /// call/WhatsApp row is hidden entirely when false — a dead button is worse
  /// than no button on a screen someone opens because they need help now.
  bool get isReachable => (phone ?? '').trim().isNotEmpty;

  /// Digits-only phone, the form `tel:` and `wa.me` both want.
  String get dialablePhone => (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  /// Credential line under the name: "General Physician • BMDC #B-54123",
  /// collapsing to whichever half exists. Empty when the provider filled in
  /// neither.
  String get credentialLine {
    final parts = <String>[];
    final role = designation?.trim();
    if (role != null && role.isNotEmpty) parts.add(role);
    final reg = registrationNo?.trim();
    if (reg != null && reg.isNotEmpty) {
      // Don't double up the '#' when the stored number already carries one.
      final shown = reg.startsWith('#') ? reg : '#$reg';
      parts.add('${type.registrationLabel} $shown');
    }
    return parts.join('  •  ');
  }

  /// Two-letter initials for the avatar fallback, ignoring an honorific.
  String get initials {
    final cleaned =
        name.replaceAll(RegExp(r'^(Dr\.?|Nurse|Sister)\s+', caseSensitive: false), '').trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final s = parts.first;
      return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  List<Object?> get props =>
      [id, type, name, photoUrl, phone, designation, registrationNo, assignedAt];

  /// Builds from the `assigned_provider` wire block, or returns null when the
  /// block is absent/unnamed — the tracking screen reads null as "no provider
  /// dispatched yet" and shows nothing rather than an empty card.
  ///
  /// [fallbackType] is the booking's own provider type, used when the block
  /// itself doesn't name a role.
  static AssignedProvider? fromJson(
    dynamic raw, {
    ProviderType fallbackType = ProviderTypeX.fallback,
  }) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);

    String? str(String key) {
      final v = json[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    final name = str('name');
    if (name == null) return null;

    return AssignedProvider(
      id: str('provider_id') ?? '',
      type: ProviderTypeX.tryFromWire(json['provider_type']?.toString()) ??
          fallbackType,
      name: name,
      photoUrl: str('photo_url'),
      phone: str('phone'),
      designation: str('designation'),
      registrationNo: str('registration_no'),
      assignedAt: DateTime.tryParse(json['assigned_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'provider_id': id,
        'provider_type': type.toWire(),
        'name': name,
        'photo_url': photoUrl,
        'phone': phone,
        'designation': designation,
        'registration_no': registrationNo,
        'assigned_at': assignedAt?.toIso8601String(),
      };
}
