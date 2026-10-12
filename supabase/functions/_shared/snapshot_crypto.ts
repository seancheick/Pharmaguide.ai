// AES-256-GCM sealing of consented stack snapshots (ADR-009 Phase 2).
//
// One owner for the snapshot row and its encryption: ai-share-snapshot seals,
// mcp-personal opens. Keys come from function secrets
// AI_SHARE_SNAPSHOT_KEY_V1, _V2, ... (base64, exactly 32 bytes; keep them in
// Supabase Vault / Edge Function secrets, never in the repo). The highest
// configured version encrypts new shares; every configured version decrypts.
//
// Rotation: add AI_SHARE_SNAPSHOT_KEY_V<n+1> to both functions' secrets and
// redeploy (new shares use n+1 and store key_version = n+1). Remove V<n> after
// the longest share lifetime (30 days); shares still on V<n> then fail closed
// and the user re-shares.
//
// Encrypted at rest; PharmaGuide's server can decrypt while a share is live;
// not end-to-end. The additional data binds a ciphertext to its connection,
// user and key version, so a row copied to another connection never opens.

export const SNAPSHOT_FORMAT = "pharmaguide-brief-markdown/v1";
export const MAX_PAYLOAD_BYTES = 64 * 1024;
const KEY_ENV_PREFIX = "AI_SHARE_SNAPSHOT_KEY_V";
const MAX_KEY_VERSION = 32;
const NONCE_BYTES = 12;

type Bytes = Uint8Array<ArrayBuffer>;

export type SnapshotKeyReason = "no_key" | "invalid_key" | "unknown_key_version";

export class SnapshotKeyError extends Error {
  constructor(readonly reason: SnapshotKeyReason) {
    super(`snapshot key unavailable: ${reason}`);
  }
}

/// Wrong key, tampered ciphertext, or a row that belongs to another
/// connection. Carries no ciphertext or plaintext.
export class SnapshotDecryptError extends Error {
  constructor() {
    super("snapshot could not be decrypted");
  }
}

export interface Keyring {
  current: number;
  keys: Map<number, CryptoKey>;
}

export interface SnapshotBinding {
  connectionId: string;
  userId: string;
}

export interface Sealed {
  ciphertext: Bytes;
  nonce: Bytes;
  keyVersion: number;
}

/// A public.ai_share_snapshots row as PostgREST reads and writes it (bytea as
/// "\x..." hex). There is no plaintext column.
export interface SnapshotRow {
  snapshot_id: string;
  connection_id: string;
  user_id: string;
  format: string;
  scope: Record<string, boolean>;
  stack_revision: string | null;
  ciphertext: string;
  nonce: string;
  key_version: number;
  generated_at: string;
  expires_at: string;
}

function base64Bytes(value: string): Bytes | null {
  try {
    return Uint8Array.from(atob(value.trim()), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

export async function keyringFromEnv(get: (name: string) => string | undefined): Promise<Keyring> {
  const keys = new Map<number, CryptoKey>();
  for (let version = 1; version <= MAX_KEY_VERSION; version++) {
    const raw = get(`${KEY_ENV_PREFIX}${version}`);
    if (raw === undefined || raw.trim() === "") continue;
    const bytes = base64Bytes(raw);
    if (!bytes || bytes.length !== 32) throw new SnapshotKeyError("invalid_key");
    keys.set(
      version,
      await crypto.subtle.importKey("raw", bytes, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]),
    );
  }
  if (keys.size === 0) throw new SnapshotKeyError("no_key");
  return { current: Math.max(...keys.keys()), keys };
}

function additionalData(binding: SnapshotBinding, keyVersion: number): Bytes {
  return new TextEncoder().encode(
    `pharmaguide-ai-share|${binding.connectionId}|${binding.userId}|${keyVersion}`,
  );
}

export async function encryptSnapshot(
  keyring: Keyring,
  plaintext: string,
  binding: SnapshotBinding,
): Promise<Sealed> {
  const keyVersion = keyring.current;
  const key = keyring.keys.get(keyVersion);
  if (!key) throw new SnapshotKeyError("unknown_key_version");
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce, additionalData: additionalData(binding, keyVersion) },
      key,
      new TextEncoder().encode(plaintext),
    ),
  );
  return { ciphertext, nonce, keyVersion };
}

export async function decryptSnapshot(
  keyring: Keyring,
  sealed: Sealed,
  binding: SnapshotBinding,
): Promise<string> {
  const key = keyring.keys.get(sealed.keyVersion);
  if (!key) throw new SnapshotKeyError("unknown_key_version");
  try {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: sealed.nonce, additionalData: additionalData(binding, sealed.keyVersion) },
      key,
      sealed.ciphertext,
    );
    return new TextDecoder("utf-8", { fatal: true }).decode(plain);
  } catch {
    throw new SnapshotDecryptError();
  }
}

export function toPgBytea(bytes: Uint8Array): string {
  return "\\x" + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function fromPgBytea(value: unknown): Bytes {
  if (typeof value !== "string" || !/^\\x(?:[0-9a-fA-F]{2})*$/.test(value)) {
    throw new SnapshotDecryptError();
  }
  const hex = value.slice(2);
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

export interface SnapshotInput {
  snapshotId: string;
  connectionId: string;
  userId: string;
  format: string;
  scope: Record<string, boolean>;
  stackRevision: string | null;
  payload: string;
  generatedAt: Date;
  expiresAt: Date;
}

export async function sealSnapshotRow(keyring: Keyring, input: SnapshotInput): Promise<SnapshotRow> {
  const sealed = await encryptSnapshot(keyring, input.payload, {
    connectionId: input.connectionId,
    userId: input.userId,
  });
  return {
    snapshot_id: input.snapshotId,
    connection_id: input.connectionId,
    user_id: input.userId,
    format: input.format,
    scope: input.scope,
    stack_revision: input.stackRevision,
    ciphertext: toPgBytea(sealed.ciphertext),
    nonce: toPgBytea(sealed.nonce),
    key_version: sealed.keyVersion,
    generated_at: input.generatedAt.toISOString(),
    expires_at: input.expiresAt.toISOString(),
  };
}

/// Decrypts a row for the verified connection and user the caller resolved,
/// never for the ids the row itself claims.
export async function openSnapshotRow(
  keyring: Keyring,
  row: SnapshotRow,
  binding: SnapshotBinding,
): Promise<string> {
  return await decryptSnapshot(
    keyring,
    {
      ciphertext: fromPgBytea(row.ciphertext),
      nonce: fromPgBytea(row.nonce),
      keyVersion: Number(row.key_version),
    },
    binding,
  );
}
