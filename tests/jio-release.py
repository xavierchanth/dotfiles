#!/usr/bin/env python3
"""Private release transport tests; no credentials or product execution."""
import argparse
import copy
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

HELPER = Path(os.environ.get('JIO_RELEASE_HELPER', Path(__file__).resolve().parents[1] / 'scripts/jio-release'))
loader = importlib.machinery.SourceFileLoader('jio_release', str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
OUT = '/nix/store/' + 'a' * 32 + '-jio-0.1.0'
DRV = '/nix/store/' + 'b' * 32 + '-jio-0.1.0.drv'
REV = '1' * 40
EXPECTED = dict(repository='example/private', revision=REV, system='aarch64-darwin', storePath=OUT, derivationPath=DRV)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.expected = dict(EXPECTED)
        self.entries = {
            'nix-cache-info': b'StoreDir: /nix/store\nVersion: 3\n',
            'a' * 32 + '.narinfo': ('StorePath: ' + OUT + '\nURL: nar/payload.nar.xz\nCompression: xz\nNarHash: sha256:dummy\nNarSize: 3\nReferences: \nSig: fixture:signature\n').encode(),
            'nar/payload.nar.xz': b'fixture',
        }
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.metadata = dict(self.expected, schemaVersion=1, closurePaths=[OUT])
        self.write_assets()

    def write_assets(self, extra=None):
        archive = self.assets / 'jio-aarch64-darwin.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for name, data in self.entries.items():
                info = tarfile.TarInfo(name); info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            if extra:
                tar.addfile(extra, io.BytesIO(b'x') if extra.isfile() else None)
        self.metadata['archive'] = dict(name=archive.name, sha256=m.digest(archive))
        (self.assets / 'jio-aarch64-darwin.json').write_text(json.dumps(self.metadata))
        (self.assets / 'receipt.json').write_text(json.dumps(self.expected))
        return archive

    def extract(self):
        metadata, archive = m.validate_assets(self.assets, self.expected)
        destination = self.root / 'extracted'
        destination.mkdir(exist_ok=True)
        m.extract_cache(archive, destination, metadata)

    def test_valid_archive(self):
        self.extract()

    def test_metadata_identity(self):
        for key in ('revision', 'system', 'repository', 'storePath', 'derivationPath', 'schemaVersion'):
            with self.subTest(key=key):
                original = copy.deepcopy(self.metadata)
                self.metadata[key] = 'wrong'
                self.write_assets()
                with self.assertRaises(ValueError): m.validate_assets(self.assets, self.expected)
                self.metadata = original

    def test_checksum_mismatch(self):
        archive = self.assets / 'jio-aarch64-darwin.tar.gz'
        archive.write_bytes(archive.read_bytes() + b'changed')
        with self.assertRaises(ValueError): m.validate_assets(self.assets, self.expected)

    def test_asset_symlink(self):
        asset = self.assets / 'jio-aarch64-darwin.json'
        asset.rename(self.root / 'metadata')
        asset.symlink_to(self.root / 'metadata')
        with self.assertRaises(ValueError): m.validate_assets(self.assets, self.expected)

    def test_unsafe_archive_paths(self):
        for name in ('../escape', '/escape', './nix-cache-info', 'nar/../escape', 'extra/file'):
            with self.subTest(name=name):
                info = tarfile.TarInfo(name); info.size = 1
                self.write_assets(info)
                with self.assertRaises(ValueError): self.extract()
                import shutil
                shutil.rmtree(self.root / 'extracted', ignore_errors=True)

    def test_links_and_special_files(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE):
            with self.subTest(kind=kind):
                info = tarfile.TarInfo('nar/extra'); info.type = kind; info.linkname = '/etc/passwd'
                self.write_assets(info)
                with self.assertRaises(ValueError): self.extract()
                import shutil
                shutil.rmtree(self.root / 'extracted', ignore_errors=True)

    def test_known_empty_cache_directories(self):
        for name in ('log', 'build-trace-v2'):
            with self.subTest(name=name):
                info = tarfile.TarInfo(name); info.type = tarfile.DIRTYPE
                self.write_assets(info)
                self.extract()
                import shutil
                shutil.rmtree(self.root / 'extracted')

    def test_known_cache_directories_cannot_have_contents(self):
        for name in ('log/output', 'build-trace-v2/trace'):
            with self.subTest(name=name):
                info = tarfile.TarInfo(name); info.size = 1
                self.write_assets(info)
                with self.assertRaises(ValueError): self.extract()
                import shutil
                shutil.rmtree(self.root / 'extracted', ignore_errors=True)

    def test_duplicate_entry(self):
        info = tarfile.TarInfo('nix-cache-info'); info.size = 1
        self.write_assets(info)
        with self.assertRaises(ValueError): self.extract()

    def test_missing_payload(self):
        del self.entries['nar/payload.nar.xz']; self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_missing_closure_entry(self):
        self.metadata['closurePaths'].append('/nix/store/' + 'c' * 32 + '-dependency')
        self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_reference_outside_closure(self):
        name = 'a' * 32 + '.narinfo'
        self.entries[name] = self.entries[name].replace(b'References: ', b'References: missing-dependency')
        self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_unsigned_entry(self):
        name = 'a' * 32 + '.narinfo'
        self.entries[name] = self.entries[name].split(b'Sig:')[0]
        self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_unknown_compression(self):
        name = 'a' * 32 + '.narinfo'
        self.entries[name] = self.entries[name].replace(b'Compression: xz', b'Compression: unknown')
        self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_external_payload_url(self):
        name = 'a' * 32 + '.narinfo'
        self.entries[name] = self.entries[name].replace(b'nar/payload.nar.xz', b'https://example.com/token')
        self.write_assets()
        with self.assertRaises(ValueError): self.extract()

    def test_changed_receipt(self):
        (self.assets / 'receipt.json').write_text(json.dumps(dict(self.expected, revision='2' * 40)))
        with self.assertRaises(ValueError): m.validate_receipt(self.assets, self.expected)

    def test_import_has_explicit_destination_and_signature_checks(self):
        args = argparse.Namespace(command='import', system=self.expected['system'], to_store='local?root=/private/tmp/fixture')
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'cache_directory', return_value=self.assets), patch.object(m.subprocess, 'run') as command:
            m.run(args, self.root)
        invocation = command.call_args.args[0]
        self.assertIn('--to', invocation)
        self.assertNotIn('--store', invocation)
        self.assertNotIn('--no-check-sigs', invocation)
        self.assertEqual(invocation[-4:], ['--option', 'require-sigs', 'true', OUT])

    def test_failed_import_never_builds(self):
        args = argparse.Namespace(command='import', system=self.expected['system'], to_store=None)
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'cache_directory', return_value=self.assets), patch.object(m.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['nix', 'copy'])) as command:
            with self.assertRaises(subprocess.CalledProcessError): m.run(args, self.root)
            self.assertEqual(command.call_count, 1)
            self.assertEqual(command.call_args.args[0][:2], ['nix', 'copy'])

    def test_candidate_uses_exact_revision_and_forbids_lock_updates(self):
        lock = {'root': 'root', 'nodes': {'root': {'inputs': {'jio': 'jio'}}, 'jio': {'locked': {'type': 'github', 'owner': 'example', 'repo': 'private', 'rev': REV}}}}
        (self.root / 'flake.lock').write_text(json.dumps(lock))
        result = dict(storePath=OUT, derivationPath=DRV, revision=REV)
        with patch.object(m, 'json_command', return_value=result) as command:
            self.assertEqual(m.candidate(self.root, 'aarch64-darwin'), EXPECTED)
            self.assertIn('--no-update-lock-file', command.call_args.args[0])
        with patch.object(m, 'json_command', return_value=dict(storePath=OUT, derivationPath=DRV, revision='2' * 40)):
            with self.assertRaises(ValueError): m.candidate(self.root, 'aarch64-darwin')

    def test_candidate_rejects_dot_repository_components(self):
        for owner, repository in [('.', 'private'), ('..', 'private'), ('example', '.'), ('example', '..')]:
            lock = {'root': 'root', 'nodes': {'root': {'inputs': {'jio': 'jio'}}, 'jio': {'locked': {'type': 'github', 'owner': owner, 'repo': repository, 'rev': REV}}}}
            (self.root / 'flake.lock').write_text(json.dumps(lock))
            with self.subTest(owner=owner, repository=repository), patch.object(m, 'json_command') as command:
                with self.assertRaises(ValueError): m.candidate(self.root, 'aarch64-darwin')
                command.assert_not_called()

    def test_prepare_download_and_reuse(self):
        import shutil
        args = argparse.Namespace(command='prepare', system=self.expected['system'], to_store=None)
        destination = self.root / 'prepared'
        api = [{'private': True}, {'tag_name': 'nix-' + REV, 'draft': False}, {'object': {'sha': REV, 'type': 'commit', 'url': 'fixture'}}]
        def download(command, **kwargs):
            self.assertEqual(command[:3], ['gh', 'release', 'download'])
            self.assertEqual(command[3], 'nix-' + REV)
            target = Path(command[command.index('--dir') + 1])
            for name in ('jio-aarch64-darwin.json', 'jio-aarch64-darwin.tar.gz'):
                shutil.copyfile(self.assets / name, target / name)
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'cache_directory', return_value=destination), patch.object(m, 'json_command', side_effect=api), patch.object(m.subprocess, 'run', side_effect=download) as command:
            m.run(args, self.root)
            self.assertEqual(command.call_count, 1)
        self.assertEqual(json.loads((destination / 'receipt.json').read_text()), self.expected)
        self.assertEqual(destination.stat().st_mode & 0o777, 0o700)
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'cache_directory', return_value=destination), patch.object(m, 'json_command', side_effect=api), patch.object(m.subprocess, 'run') as command:
            m.run(args, self.root)
            command.assert_not_called()

    def test_prepare_rejects_wrong_tag(self):
        args = argparse.Namespace(command='prepare', system=self.expected['system'], to_store=None)
        api = [{'private': True}, {'tag_name': 'nix-' + REV, 'draft': False}, {'object': {'sha': '2' * 40, 'type': 'commit', 'url': 'fixture'}}]
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'cache_directory', return_value=self.assets), patch.object(m, 'json_command', side_effect=api), patch.object(m.subprocess, 'run') as command:
            with self.assertRaises(ValueError): m.run(args, self.root)
            command.assert_not_called()

    def test_prepare_rejects_public_repository(self):
        args = argparse.Namespace(command='prepare', system=self.expected['system'], to_store=None)
        with patch.object(m, 'candidate', return_value=self.expected), patch.object(m, 'json_command', return_value={'private': False}), patch.object(m.subprocess, 'run') as command:
            with self.assertRaises(ValueError): m.run(args, self.root)
            command.assert_not_called()


if __name__ == '__main__': unittest.main()
