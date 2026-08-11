import '../../../core/ids.dart';
import '../../../core/result.dart';
import 'proposal.dart';

/// The single entry point for every record mutation (design §6.4).
abstract interface class ApprovalService {
  /// Form path (v1): validate + apply atomically; command row inserted with
  /// terminal status. Duplicate commandId with identical payload returns
  /// the original receipt; different payload => DuplicateIdError.
  Future<Result<CommandReceipt>> submit(Proposal proposal);

  /// Agent path — the Gate 4 seam. Declared and frozen NOW; v1 bodies:
  /// stage/approve/reject return Err(NotAvailableError), pending() returns
  /// [].
  Future<Result<PendingProposal>> stage(Proposal proposal);
  Future<Result<CommandReceipt>> approve(CommandId commandId);
  Future<Result<void>> reject(CommandId commandId, {required String reason});
  Future<List<PendingProposal>> pending();
}
