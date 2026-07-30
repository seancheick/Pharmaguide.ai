import {
  removeStorageObjectsOrThrow,
  type StorageObjectRemovalClient,
} from "./verified_storage_removal.ts";

function fakeClient({
  deletedNames,
  remainingPaths = new Set<string>(),
}: {
  deletedNames: string[];
  remainingPaths?: Set<string>;
}): StorageObjectRemovalClient {
  return {
    remove: (_paths: string[]) =>
      Promise.resolve({
        data: deletedNames.map((name) => ({ name })),
        error: null,
      }),
    exists: (path: string) =>
      Promise.resolve({
        data: remainingPaths.has(path),
        error: null,
      }),
  };
}

Deno.test("accepts a complete Storage deletion response", async () => {
  const result = await removeStorageObjectsOrThrow(
    fakeClient({ deletedNames: ["a/front.jpg", "a/facts.jpg"] }),
    ["a/front.jpg", "a/facts.jpg"],
  );

  if (result.deletedObjectCount !== 2) {
    throw new Error(`unexpected deleted count: ${result.deletedObjectCount}`);
  }
});

Deno.test("accepts an already-absent object after a prior partial retry", async () => {
  const result = await removeStorageObjectsOrThrow(
    fakeClient({ deletedNames: ["a/front.jpg"] }),
    ["a/front.jpg", "a/facts.jpg"],
  );

  if (result.deletedObjectCount !== 1) {
    throw new Error(`unexpected deleted count: ${result.deletedObjectCount}`);
  }
});

Deno.test("rejects a partial deletion while any object still exists", async () => {
  let rejected = false;
  try {
    await removeStorageObjectsOrThrow(
      fakeClient({
        deletedNames: ["a/front.jpg"],
        remainingPaths: new Set(["a/facts.jpg"]),
      }),
      ["a/front.jpg", "a/facts.jpg"],
    );
  } catch {
    rejected = true;
  }

  if (!rejected) {
    throw new Error("partial Storage deletion was accepted");
  }
});

Deno.test("rejects duplicate requested paths", async () => {
  let rejected = false;
  try {
    await removeStorageObjectsOrThrow(
      fakeClient({ deletedNames: ["a/front.jpg"] }),
      ["a/front.jpg", "a/front.jpg"],
    );
  } catch {
    rejected = true;
  }

  if (!rejected) {
    throw new Error("duplicate Storage paths were accepted");
  }
});
