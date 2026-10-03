/// Free tier: [freeLimit] songs processed; unlimited once purchased.
/// Billing is tied to the feature, never to individual songs.
class Entitlement {
  Entitlement({this.freeLimit = 3, this.purchased = false, this.processed = 0});

  final int freeLimit;
  bool purchased;
  int processed;

  bool get canProcessMore => purchased || processed < freeLimit;
  int get freeRemaining =>
      purchased ? -1 : (freeLimit - processed).clamp(0, freeLimit);

  /// Call when a song's separation + scoring is consumed. Returns false
  /// (and does not count) if the limit is reached.
  bool consume() {
    if (!canProcessMore) return false;
    processed++;
    return true;
  }

  Map<String, Object?> toJson() =>
      {'freeLimit': freeLimit, 'purchased': purchased, 'processed': processed};

  factory Entitlement.fromJson(Map<String, Object?> j) => Entitlement(
        freeLimit: (j['freeLimit'] as int?) ?? 3,
        purchased: (j['purchased'] as bool?) ?? false,
        processed: (j['processed'] as int?) ?? 0,
      );
}
