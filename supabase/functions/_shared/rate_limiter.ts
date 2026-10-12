// In-memory token bucket (S7). Limits hold per Edge Function instance, not
// globally; that bounds abuse from one caller without adding a shared store.
// The one owner for mcp-public (per IP), mcp-personal (per connection) and
// ai-share-snapshot (per user).
export class RateLimiter {
  #buckets = new Map<string, { tokens: number; at: number }>();
  constructor(
    readonly capacity = 60,
    readonly refillPerMs = 60 / 60_000,
    readonly maxKeys = 10_000,
    readonly now: () => number = Date.now,
  ) {}

  /// Takes one token for `key`; false when the bucket is empty.
  take(key: string): boolean {
    const now = this.now();
    const bucket = this.#buckets.get(key) ?? { tokens: this.capacity, at: now };
    bucket.tokens = Math.min(
      this.capacity,
      bucket.tokens + (now - bucket.at) * this.refillPerMs,
    );
    bucket.at = now;
    this.#buckets.delete(key);
    this.#buckets.set(key, bucket);
    if (this.#buckets.size > this.maxKeys) {
      this.#buckets.delete(this.#buckets.keys().next().value!);
    }
    if (bucket.tokens < 1) return false;
    bucket.tokens -= 1;
    return true;
  }
}
