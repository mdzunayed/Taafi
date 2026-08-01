import 'package:equatable/equatable.dart';

import 'user.dart';

/// Server response for `POST /api/admin/create-provider`. Carries the
/// freshly-minted [account] (so the admin UI can show "Dr. Foo was
/// created") AND the **plaintext** [temporaryPassword] returned exactly
/// once. The admin is expected to copy it via the
/// `AddProviderScreen.CopyCredentialsCard` and hand it to the new hire
/// out-of-band; subsequent reads never expose the plaintext again.
class AdminProvisionResult extends Equatable {
  final User account;
  final String temporaryPassword;

  const AdminProvisionResult({
    required this.account,
    required this.temporaryPassword,
  });

  @override
  List<Object?> get props => [account, temporaryPassword];
}
