#!/usr/bin/env python3
"""Exercise deployment source migration with real Stow in disposable homes."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(os.environ.get('TEST_ROOT', Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location('managed_stow', repo / 'scripts/prepare-managed-stow.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def stow(home):
    subprocess.run(['stow', '--dir', str(home / '.local/share/dotfiles/stow'),
                    '--target', str(home / '.config/demo'), '--restow', 'demo'], check=True)


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    home = root / 'home'
    source = root / 'source-one'
    declarations = [{'name': 'demo', 'target': '.config/demo'}]
    old = home / '.dotfiles/stow/demo'
    target = home / '.config/demo'
    target.mkdir(parents=True)
    write(old / 'config', 'local checkout edits')
    write(source / 'demo/config', 'deployed')
    write(source / 'demo/nested/new', 'new')
    write(source / 'demo/.stow-local-ignore', '^ignored$\n')
    write(source / 'demo/ignored', 'ignored')
    (target / 'config').symlink_to(os.path.relpath(old / 'config', target))
    (target / 'removed').symlink_to(old / 'removed')
    write(target / 'user-file', 'preserve')
    (target / 'user-link').symlink_to(root / 'unrelated/stow/demo/file')
    module.prepare(home, source, declarations, [])
    stow(home)
    assert (target / 'config').read_text() == 'deployed'
    assert not os.path.lexists(target / 'removed')
    assert (old / 'config').read_text() == 'local checkout edits'
    assert (target / 'user-file').read_text() == 'preserve'
    assert (target / 'user-link').is_symlink()
    assert not os.path.lexists(target / 'ignored')
    assert (target / 'nested/new').read_text() == 'new'
    managed = home / '.local/share/dotfiles/stow'
    write(managed / 'demo/config', 'managed local edit')
    module.prepare(home, source, declarations, [])
    assert (target / 'config').read_text() == 'managed local edit'
    assert not list(managed.parent.glob('stow-backup-*'))
    source_two = root / 'source-two'
    write(source_two / 'demo/config', 'updated')
    module.prepare(home, source_two, declarations, [])
    stow(home)
    assert (target / 'config').read_text() == 'updated'
    assert not os.path.lexists(target / 'nested')
    backups = list(managed.parent.glob('stow-backup-*/stow/demo/config'))
    assert len(backups) == 1 and backups[0].read_text() == 'managed local edit'
    # A regular user replacement that conflicts with Stow is preserved.
    (target / 'config').unlink()
    write(target / 'config', 'user replacement')
    module.prepare(home, source_two, declarations, [])
    result = subprocess.run(['stow', '--dir', str(managed), '--target', str(target), '--restow', 'demo'], capture_output=True)
    assert result.returncode != 0 and (target / 'config').read_text() == 'user replacement'
    # Missing package preflight leaves existing links and source untouched.
    before = os.readlink(target / 'user-link')
    try:
        module.prepare(home, root / 'missing', declarations, [])
        raise AssertionError('missing package accepted')
    except RuntimeError:
        pass
    assert os.readlink(target / 'user-link') == before
    assert (managed / 'demo/config').read_text() == 'updated'
    # Retired package cleanup only removes links owned by the exact source.
    (target / 'owned-retired').symlink_to(managed / 'demo/config')
    module.prepare(home, source_two, [], declarations)
    assert (target / 'config').read_text() == 'user replacement'
    assert (target / 'user-link').is_symlink()
    assert not os.path.lexists(target / 'owned-retired')
    # Unrelated target directory symlinks and escaping source links fail safely.
    redirect = home / '.config/redirect'
    redirect.symlink_to(root, target_is_directory=True)
    try:
        module.prepare(home, source_two, [{'name': 'demo', 'target': '.config/redirect'}], [])
        raise AssertionError('target symlink accepted')
    except RuntimeError:
        pass
    (source_two / 'demo/escape').symlink_to(root / 'outside')
    try:
        module.prepare(home, source_two, declarations, [])
        raise AssertionError('escaping source link accepted')
    except RuntimeError:
        pass
    (source_two / 'demo/escape').unlink()
    # Unexpected managed directory symlinks fail safely.
    shutil.rmtree(managed)
    managed.symlink_to(source_two, target_is_directory=True)
    try:
        module.prepare(home, source_two, declarations, [])
        raise AssertionError('managed symlink accepted')
    except RuntimeError:
        pass
# A target folded into an entire old or managed package must become a real
# directory before Stow runs, otherwise Stow sees its source as its target.
for owner in ['original', 'managed']:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        home = root / 'home'
        source = root / 'source'
        target = home / '.config/demo'
        old = home / '.dotfiles/stow/demo'
        write(old / 'config', 'preserved checkout')
        write(source / 'demo/config', 'deployed')
        write(source / 'demo/nested/new', 'nested')
        target.parent.mkdir(parents=True)
        if owner == 'original':
            target.symlink_to(os.path.relpath(old, target.parent))
        else:
            module.prepare(home, source, declarations, [])
            target.symlink_to(home / '.local/share/dotfiles/stow/demo')
        module.prepare(home, source, declarations, [])
        assert target.is_dir() and not target.is_symlink()
        stow(home)
        assert (target / 'config').read_text() == 'deployed'
        assert (target / 'nested/new').read_text() == 'nested'
        assert (old / 'config').read_text() == 'preserved checkout'
        module.prepare(home, source, declarations, [])
        stow(home)
        assert not target.is_symlink()
print('managed Stow migration tests passed')
