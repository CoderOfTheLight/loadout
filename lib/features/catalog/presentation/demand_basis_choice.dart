/// The one question, as two plain choices (folders proposal §2): "Does how
/// much you bring depend on how many people come?"
///
/// Used by the item form (the item's answer), the folder editor (the
/// folder's default answer) and the new-folder dialog. Two stacked
/// selectable tiles instead of radios so the long labels never truncate on
/// a narrow phone.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../domain/demand_basis.dart';
import 'catalog_format.dart';

class DemandBasisChoice extends StatelessWidget {
  const DemandBasisChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DemandBasis value;
  final ValueChanged<DemandBasis> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _option(context, DemandBasis.perPerson),
      const SizedBox(height: Space.s),
      _option(context, DemandBasis.perEvent),
    ],
  );

  Widget _option(BuildContext context, DemandBasis basis) {
    final scheme = Theme.of(context).colorScheme;
    final selected = basis == value;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small),
          side: BorderSide(
            color: selected ? scheme.secondary : scheme.outlineVariant,
          ),
        ),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        title: Text(demandBasisLabel(basis)),
        onTap: () => onChanged(basis),
      ),
    );
  }
}
