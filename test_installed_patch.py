"""Offline tests of the installer integration using small stand-ins (not real ZHS)."""
from __future__ import annotations
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

from verify_and_integrate_v4 import RELS, IntegrationError, git_blob_sha
from test_integration_v4 import AI_SOURCE, ZH_SOURCE, HTTP_SOURCE

S = Path(__file__).resolve().parent / 'payload' / 'Patch-ZHS-0.1.5.py'
spec = importlib.util.spec_from_file_location('installed_zhs_patch', S)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

class InstalledIntegrationTests(unittest.TestCase):
    def _make(self, root):
        sources = {RELS[0]: AI_SOURCE, RELS[1]: ZH_SOURCE, RELS[2]: HTTP_SOURCE}
        for rel, content in sources.items():
            f = root / rel.removeprefix('src/zhs/')
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(content, encoding='utf8')
        hashes = {rel: git_blob_sha(content.encode()) for rel, content in sources.items()}
        return hashes

    def test_readonly_then_apply_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            root,backup=Path(d)/'zhs',Path(d)/'backups'
            hashes=self._make(root)
            before={rel:(root/rel.removeprefix('src/zhs/')).read_bytes() for rel in RELS}
            check=patch.patch_installed(root,backup,False,expected=hashes)
            self.assertEqual(len(check['changes']),3)
            self.assertFalse(backup.exists())
            for rel in RELS:
                self.assertEqual((root/rel.removeprefix('src/zhs/')).read_bytes(),before[rel])
            applied=patch.patch_installed(root,backup,True,expected=hashes)
            self.assertTrue(applied['modified'])
            self.assertTrue(Path(applied['backup'],'manifest.json').exists())
            for rel in RELS:
                self.assertEqual((Path(applied['backup'])/rel.removeprefix('src/zhs/')).read_bytes(), before[rel])
            again=patch.patch_installed(root,backup,True,expected=hashes)
            self.assertFalse(again['modified'])
            self.assertEqual(again['changes'],[])

    def test_mismatched_file_never_mutates(self):
        with tempfile.TemporaryDirectory() as d:
            root,backup=Path(d)/'zhs',Path(d)/'backups'
            hashes=self._make(root)
            p=root/'zhidao/video.py'
            p.write_text(p.read_text()+'\n# unknown\n', encoding='utf8')
            pre={rel:(root/rel.removeprefix('src/zhs/')).read_bytes() for rel in RELS}
            with self.assertRaises(IntegrationError):
                patch.patch_installed(root,backup,True,expected=hashes)
            self.assertFalse(backup.exists())
            for rel in RELS:
                self.assertEqual((root/rel.removeprefix('src/zhs/')).read_bytes(),pre[rel])

    def test_failure_rolls_back(self):
        with tempfile.TemporaryDirectory() as d:
            root,backup=Path(d)/'zhs',Path(d)/'backups'
            hashes=self._make(root)
            before={rel:(root/rel.removeprefix('src/zhs/')).read_bytes() for rel in RELS}
            count=0
            def fail_mid(src,dst):
                nonlocal count
                count+=1
                if count==2:raise OSError('intentional')
                return os.replace(src,dst)
            with self.assertRaises(OSError):
                patch.patch_installed(root,backup,True,expected=hashes,replace=fail_mid)
            for rel in RELS:
                self.assertEqual((root/rel.removeprefix('src/zhs/')).read_bytes(),before[rel])

    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'zhs';hashes=self._make(root)
            p=root/'ai/video.py';data=p.read_bytes();p.unlink()
            other=Path(d)/'outside.py';other.write_bytes(data)
            p.symlink_to(other)
            with self.assertRaises(IntegrationError):
                patch.patch_installed(root,Path(d)/'backup',True,expected=hashes)

if __name__=='__main__': unittest.main()
