import 'dart:io';

import '../../approval/domain/proposal.dart';
import '../../recipes/domain/recipe_drafts.dart';

/// Gate 4. The agent NEVER writes: it emits Proposals of the same sealed
/// WorkspaceCommand types, which park in ApprovalService.stage until a human
/// approves. This file is the LocalAgent seam named by the architecture
/// (design §6.7).
abstract interface class LocalAgent {
  Stream<AgentTurn> run(AgentRequest request);
}

final class AgentRequest {
  const AgentRequest(this.utterance);

  final String utterance;
}

sealed class AgentTurn {
  const AgentTurn();
}

final class AgentMessageTurn extends AgentTurn {
  const AgentMessageTurn(this.text);

  final String text;
}

final class AgentProposalTurn extends AgentTurn {
  const AgentProposalTurn(this.proposal);

  /// Consumed by ApprovalService.stage.
  final Proposal proposal;
}

/// Gate 5. OCR output is an untrusted RecipeFormDraft proposal that prefills
/// the existing recipe form; images live ONLY inside a ScratchSpace session
/// ('ocr') and are swept per design §10. This is the RecipeOcr seam.
abstract interface class RecipeOcr {
  Future<RecipeOcrResult> extract({
    required String imagePath,
    required Directory session,
  });
}

final class RecipeOcrResult {
  const RecipeOcrResult({required this.draft, required this.uncertainFields});

  final RecipeFormDraft draft;
  final List<String> uncertainFields;
}
