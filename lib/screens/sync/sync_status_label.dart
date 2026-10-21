import '../../l10n/l10n.dart';

String syncStatusLabel(Object? value) => switch (value) {
  'queued' => t.syncQueued,
  'sending' => t.syncSending,
  'processing' => t.syncProcessing,
  'confirmed' => t.syncConfirmed,
  'unknown' => t.syncUnknown,
  'needsAuthorization' => t.syncNeedsAuthorization,
  'failed' => t.syncFailed,
  'unsupported' => t.syncUnsupported,
  'deleted' => t.syncDeleted,
  _ => t.syncSyncNeedsAttention,
};
