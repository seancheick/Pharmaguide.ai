"""Storage on disk, shared by the rehearsal and each publisher process. Create-only uploads
behave as Storage does. Everything else in the publisher is real."""
import json, sys
from pathlib import Path
import release_manifest as rm, supabase_client, sync_to_supabase as sync

class Store:
    def __init__(self, root): self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)
    def __contains__(self, path): return (self.root / path).is_file()
    def __getitem__(self, path): return (self.root / path).read_bytes()
    def get(self, path, default=None): return self[path] if path in self else default
    def __setitem__(self, path, data):
        target = self.root / path; target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".part"); tmp.write_bytes(data); tmp.replace(target)
    def __iter__(self): return iter(sorted(str(p.relative_to(self.root)) for p in self.root.rglob("*") if p.is_file()))

def install(work):
    work = Path(work)
    objects = Store(work / "storage")
    uploads = []
    rm.GATE_PATH = work / "gate.json"; rm.TRUST_PATH = work / "trust.json"
    def upload(_c, _b, path, local, **kw):
        data = Path(local).read_bytes()
        if kw.get("upsert") is False and path in objects and objects[path] != data:
            raise ValueError(f"immutable Storage object differs: {path}")
        uploads.append(path); objects[path] = data
    def download(_c, _b, path):
        if path not in objects: raise FileNotFoundError(path)
        return objects[path]
    def listing(_c, _b, prefix, limit=1000, offset=0):
        return [] if offset else [{"name": p.rsplit("/", 1)[1]} for p in objects if p.rsplit("/", 1)[0] == prefix]
    supabase_client.upload_file, supabase_client.download_file, supabase_client.list_storage_paths = upload, download, listing
    sync.validate_bucket_upload_capacity = lambda *a, **k: None
    sync.discover_existing_remote_blob_paths = lambda *a, **k: set()
    sync._publish_catalog_search_step = lambda *a, **k: None
    sync.catalog_search_rows = lambda *a, **k: []
    return objects, uploads

if __name__ == "__main__":
    # One publisher process. Holds at the named stage until it is killed.
    import time
    job = json.loads(sys.argv[1])
    objects, _ = install(job["work"])
    def hold(*a, **k):
        Path(job["marker"]).write_text("here"); time.sleep(300)
    stage = job["stage"]
    if stage == "upload":
        real = supabase_client.upload_file
        def upload_then_hold(c, b, path, local, **kw):
            if path.startswith("rules/") or path.endswith("pharmaguide_core.db"):
                hold()
            return real(c, b, path, local, **kw)
        supabase_client.upload_file = upload_then_hold
    elif stage == "promote":
        sync._promote_registry_release = hold
    elif stage == "rpc":
        real = supabase_client.insert_manifest
        def mark_then_insert(*a, **k):
            Path(job["marker"]).write_text("here"); return real(*a, **k)
        supabase_client.insert_manifest = mark_then_insert
    sync.sync(job["catalog"], max_workers=1, **job["kwargs"])
