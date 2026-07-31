export interface StorageObjectRemovalClient {
  remove(paths: string[]): Promise<{
    data: unknown;
    error: unknown;
  }>;
  exists(path: string): Promise<{
    data: boolean | null;
    error: unknown;
  }>;
}

export interface VerifiedStorageRemoval {
  deletedObjectCount: number;
}

function deletedObjectNames(data: unknown): Set<string> {
  if (!Array.isArray(data)) {
    throw new Error("Storage deletion returned an invalid response");
  }

  const names = new Set<string>();
  for (const item of data) {
    if (
      !item || typeof item !== "object" ||
      typeof (item as { name?: unknown }).name !== "string"
    ) {
      throw new Error("Storage deletion returned an invalid object");
    }
    names.add((item as { name: string }).name);
  }
  return names;
}

/// Deletes every requested private object and proves that any object omitted
/// from Storage's deletion response is already absent. This makes retries
/// idempotent without treating a partial deletion as success.
export async function removeStorageObjectsOrThrow(
  client: StorageObjectRemovalClient,
  requestedPaths: string[],
): Promise<VerifiedStorageRemoval> {
  const uniquePaths = new Set(requestedPaths);
  if (uniquePaths.size !== requestedPaths.length) {
    throw new Error("Storage deletion paths must be unique");
  }
  if (requestedPaths.length === 0) {
    return { deletedObjectCount: 0 };
  }

  const { data, error } = await client.remove(requestedPaths);
  if (error) throw error;

  const deletedNames = deletedObjectNames(data);
  for (const name of deletedNames) {
    if (!uniquePaths.has(name)) {
      throw new Error("Storage deletion returned an unexpected object");
    }
  }

  const unconfirmedPaths = requestedPaths.filter((path) =>
    !deletedNames.has(path)
  );
  const absenceChecks = await Promise.all(
    unconfirmedPaths.map(async (path) => {
      const { data, error } = await client.exists(path);
      if (error || data !== false) {
        throw error ?? new Error("Storage object still exists after deletion");
      }
    }),
  );
  if (absenceChecks.length !== unconfirmedPaths.length) {
    throw new Error("Storage absence verification was incomplete");
  }

  return { deletedObjectCount: deletedNames.size };
}
