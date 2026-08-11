import '../../../core/ids.dart';
import '../../../core/result.dart';
import 'command_validator.dart';
import 'proposal.dart';

/// Port implemented over Drift (design §6.4). ONE transaction per command:
/// the `commands` audit row plus every effect. Assigns ids via IdGenerator,
/// stamps recordedAt via Clock.
abstract interface class CommandApplier {
  Future<Result<CommandReceipt>> apply(
    ValidatedCommand command, {
    required CommandId commandId,
    required ProposalOrigin origin,
  });
}
