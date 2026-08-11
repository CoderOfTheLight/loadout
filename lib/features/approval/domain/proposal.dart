import '../../../core/ids.dart';
import '../../../core/time.dart';
import 'commands.dart';

/// Who authored a proposal (design §6.4). `commands.origin` stores the name.
enum ProposalOrigin { form, agent }

/// A command submission (design §6.4). [commandId] is caller-generated and
/// doubles as the idempotency key.
final class Proposal {
  const Proposal({
    required this.commandId,
    required this.origin,
    required this.command,
    required this.createdAt,
  });

  /// Caller-generated ULID; idempotency key.
  final CommandId commandId;
  final ProposalOrigin origin;
  final WorkspaceCommand command;
  final Instant createdAt;
}

/// What a successfully applied command returns.
final class CommandReceipt {
  const CommandReceipt({
    required this.commandId,
    required this.appliedAt,
    required this.createdRecordIds,
    this.warnings = const [],
  });

  final CommandId commandId;
  final Instant appliedAt;
  final List<String> createdRecordIds;

  /// e.g. 'NEGATIVE_ON_HAND'.
  final List<String> warnings;
}

/// A staged (not yet approved) proposal — the Gate 4 seam. v1 never
/// produces one.
final class PendingProposal {
  const PendingProposal({
    required this.commandId,
    required this.origin,
    required this.command,
    required this.createdAt,
  });

  final CommandId commandId;
  final ProposalOrigin origin;
  final WorkspaceCommand command;
  final Instant createdAt;
}
