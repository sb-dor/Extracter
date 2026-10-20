import 'package:extracter/src/common/localization/generated/l10n.dart';

String modelName(Localization l10n, String modelId) => switch (modelId) {
  'tiny' => l10n.modelTiny,
  'base' => l10n.modelBase,
  'small' => l10n.modelSmall,
  'medium' => l10n.modelMedium,
  'large-v3-turbo' => l10n.modelLargeTurbo,
  _ => modelId,
};

String modelDescription(Localization l10n, String modelId) => switch (modelId) {
  'tiny' => l10n.modelTinyDescription,
  'base' => l10n.modelBaseDescription,
  'small' => l10n.modelSmallDescription,
  'medium' => l10n.modelMediumDescription,
  'large-v3-turbo' => l10n.modelLargeTurboDescription,
  _ => '',
};
