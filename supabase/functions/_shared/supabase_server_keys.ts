export type ReadEnvironment = (name: string) => string | undefined;

function nonblank(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  return normalized ? normalized : undefined;
}

function resolveSupabaseKey(
  readEnvironment: ReadEnvironment,
  names: {
    direct: string;
    bundle: string;
    legacy: string;
  },
): string | undefined {
  const directKey = nonblank(readEnvironment(names.direct));
  if (directKey) return directKey;

  const keyBundle = nonblank(readEnvironment(names.bundle));
  if (keyBundle) {
    let decoded: unknown;
    try {
      decoded = JSON.parse(keyBundle);
    } catch {
      throw new Error(`${names.bundle} is malformed`);
    }
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      throw new Error(`${names.bundle} is malformed`);
    }
    const bundledDefault = (decoded as { default?: unknown }).default;
    const defaultKey = typeof bundledDefault === "string"
      ? nonblank(bundledDefault)
      : undefined;
    if (!defaultKey) {
      throw new Error(`${names.bundle} has no default key`);
    }
    return defaultKey;
  }

  return nonblank(readEnvironment(names.legacy));
}

/// Resolves one server-only Supabase administrator key.
///
/// Current opaque secret keys are preferred. Managed Edge Functions may
/// expose them as a JSON bundle; the legacy service-role JWT remains only as
/// a migration fallback.
export function resolveSupabaseAdminKey(
  readEnvironment: ReadEnvironment = (name) => Deno.env.get(name),
): string | undefined {
  return resolveSupabaseKey(readEnvironment, {
    direct: "SUPABASE_SECRET_KEY",
    bundle: "SUPABASE_SECRET_KEYS",
    legacy: "SUPABASE_SERVICE_ROLE_KEY",
  });
}

/// Resolves the low-privilege project key used only to verify a caller's JWT.
export function resolveSupabasePublicKey(
  readEnvironment: ReadEnvironment = (name) => Deno.env.get(name),
): string | undefined {
  return resolveSupabaseKey(readEnvironment, {
    direct: "SUPABASE_PUBLISHABLE_KEY",
    bundle: "SUPABASE_PUBLISHABLE_KEYS",
    legacy: "SUPABASE_ANON_KEY",
  });
}
