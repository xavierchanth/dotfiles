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
iris_spec = importlib.util.spec_from_file_location('iris_routing', repo / 'scripts/prepare-iris-routing.py')
iris = importlib.util.module_from_spec(iris_spec)
iris_spec.loader.exec_module(iris)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def stow(home, package='demo', target='.config/demo'):
    subprocess.run(['stow', '--dir', str(home / '.local/share/dotfiles/stow'),
                    '--target', str(home / target), '--restow', package], check=True)


def initialize_checkout(home):
    (home / '.dotfiles').mkdir(parents=True)
    subprocess.run(['git', 'init', '--quiet', home / '.dotfiles'], check=True)


def assert_refused(callback):
    try:
        callback()
        raise AssertionError('unsafe Iris routing layout accepted')
    except RuntimeError:
        pass


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
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
        root = Path(temporary).resolve()
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

# Iris config is captured from the legacy skill tree, then exposed beside
# skills independently of source swaps and Stow directory folding.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    declarations = [{'name': 'agents', 'target': '.agents'}]
    routing = Path('agents/skills/orchestration/iris/config')
    source_one = root / 'source-one'
    write(source_one / routing / '.gitignore', 'workspaces.yaml\nvocabulary.yaml\n')
    module.prepare(home, source_one, declarations, [])
    (home / '.agents').mkdir(parents=True)
    stow(home, 'agents', '.agents')
    config = home / '.agents/skills/orchestration/iris/config'
    write(config / 'vocabulary.yaml', 'organizations:\n  example: [example]\n')

    iris.prepare(home, link=False)
    state = home / '.dotfiles/local/iris/vocabulary.yaml'
    subprocess.run(['git', '-C', home / '.dotfiles', 'check-ignore', '--quiet',
                    'local/iris/vocabulary.yaml'], check=True)
    assert state.read_text() == 'organizations:\n  example: [example]\n'
    assert not (config / 'vocabulary.yaml').exists()

    source_two = root / 'source-two'
    write(source_two / 'agents/skills/orchestration/iris/SKILL.md', 'second generation')
    module.prepare(home, source_two, declarations, [])
    stow(home, 'agents', '.agents')
    iris.prepare(home, link=True)
    overlay = home / '.agents/config/iris'
    assert overlay.is_symlink() and overlay.resolve() == state.parent
    routed = overlay / 'vocabulary.yaml'
    assert routed.is_file(), routed
    assert routed.resolve() == state, (routed.resolve(), state)
    assert routed.read_text() == state.read_text()
    workspaces = overlay / 'workspaces.yaml'
    assert not workspaces.exists(), workspaces
    assert workspaces.resolve() == home / '.dotfiles/local/iris/workspaces.yaml'
    assert state.stat().st_mode & 0o777 == 0o600
    assert state.parent.stat().st_mode & 0o777 == 0o700

    state.write_text('organizations:\n  durable: [durable]\n')
    state.chmod(0o644)
    iris.prepare(home, link=False)
    assert state.stat().st_mode & 0o777 == 0o600
    source_three = root / 'source-three'
    write(source_three / 'agents/skills/orchestration/iris/SKILL.md', 'third generation')
    module.prepare(home, source_three, declarations, [])
    stow(home, 'agents', '.agents')
    iris.prepare(home, link=True)
    assert overlay.is_symlink() and routed.is_file(), routed
    assert routed.resolve() == state, (routed.resolve(), state)
    assert routed.read_text() == 'organizations:\n  durable: [durable]\n'

# Existing target content can make Stow fold only the config directory. That
# verified Stow-owned link remains safe to traverse while routing files move.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    declarations = [{'name': 'agents', 'target': '.agents'}]
    routing = Path('agents/skills/orchestration/iris/config')
    source = root / 'source'
    write(source / routing / '.gitignore', 'workspaces.yaml\nvocabulary.yaml\n')
    write(source / routing / 'vocabulary.yaml', 'config link layout\n')
    module.prepare(home, source, declarations, [])
    iris_target = home / '.agents/skills/orchestration/iris'
    write(iris_target / 'user-note', 'preserve')
    stow(home, 'agents', '.agents')
    config = iris_target / 'config'
    assert config.is_symlink()

    iris.prepare(home, link=False)
    state = home / '.dotfiles/local/iris/vocabulary.yaml'
    assert state.read_text() == 'config link layout\n'
    stow(home, 'agents', '.agents')
    iris.prepare(home, link=True)
    assert not (config / 'vocabulary.yaml').exists()
    assert (home / '.agents/config/iris/vocabulary.yaml').resolve() == state
    assert (iris_target / 'user-note').read_text() == 'preserve'

# A pre-existing real config directory makes Stow link individual files. Only
# links to the exact selected Stow package path are accepted and migrated.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    declarations = [{'name': 'agents', 'target': '.agents'}]
    routing = Path('agents/skills/orchestration/iris/config')
    source = root / 'source'
    write(source / routing / '.gitignore', 'workspaces.yaml\nvocabulary.yaml\n')
    write(source / routing / 'vocabulary.yaml', 'individual link layout\n')
    module.prepare(home, source, declarations, [])
    config = home / '.agents/skills/orchestration/iris/config'
    config.mkdir(parents=True)
    stow(home, 'agents', '.agents')
    routed = config / 'vocabulary.yaml'
    assert not config.is_symlink() and routed.is_symlink()

    iris.prepare(home, link=False)
    state = home / '.dotfiles/local/iris/vocabulary.yaml'
    assert state.read_text() == 'individual link layout\n'
    stow(home, 'agents', '.agents')
    iris.prepare(home, link=True)
    assert not routed.exists()
    assert (home / '.agents/config/iris/vocabulary.yaml').resolve() == state

# Unrelated directory and file links fail closed without changing their data.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    outside = root / 'outside'
    write(outside / 'vocabulary.yaml', 'outside directory\n')
    config = home / '.agents/skills/orchestration/iris/config'
    config.parent.mkdir(parents=True)
    config.symlink_to(outside, target_is_directory=True)
    assert_refused(lambda: iris.prepare(home, link=False))
    assert config.is_symlink() and (outside / 'vocabulary.yaml').read_text() == 'outside directory\n'

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    outside = root / 'outside.yaml'
    write(outside, 'outside file\n')
    config = home / '.agents/skills/orchestration/iris/config'
    config.mkdir(parents=True)
    routed = config / 'vocabulary.yaml'
    routed.symlink_to(outside)
    assert_refused(lambda: iris.prepare(home, link=False))
    assert routed.is_symlink() and outside.read_text() == 'outside file\n'

# Divergent copies stop migration while preserving both versions for recovery.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    config = home / '.agents/skills/orchestration/iris/config'
    source = config / 'vocabulary.yaml'
    destination = home / '.dotfiles/local/iris/vocabulary.yaml'
    write(source, 'current config\n')
    write(destination, 'existing local state\n')
    assert_refused(lambda: iris.prepare(home, link=False))
    assert source.read_text() == 'current config\n'
    assert destination.read_text() == 'existing local state\n'

# A fresh install needs no config placeholder in the skill tree. Restowing
# preserves the private overlay, and conflicting user content stays untouched.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary).resolve()
    home = root / 'home'
    initialize_checkout(home)
    source = root / 'source'
    write(source / 'agents/skills/orchestration/iris/SKILL.md', 'public skill')
    declarations = [{'name': 'agents', 'target': '.agents'}]
    iris.prepare(home, link=False)
    module.prepare(home, source, declarations, [])
    (home / '.agents').mkdir(parents=True, exist_ok=True)
    stow(home, 'agents', '.agents')
    folded = os.readlink(home / '.agents/skills')
    iris.prepare(home, link=True)
    overlay = home / '.agents/config/iris'
    write(overlay / 'vocabulary.yaml', 'private alias')
    iris.prepare(home, link=True)
    stow(home, 'agents', '.agents')
    assert os.readlink(home / '.agents/skills') == folded
    assert (overlay / 'vocabulary.yaml').read_text() == 'private alias'
    assert not (home / '.local/share/dotfiles/stow/agents/config').exists()
    assert not (source / 'agents/skills/orchestration/iris/config').exists()
    overlay.unlink()
    outside = root / 'outside'
    write(outside / 'vocabulary.yaml', 'user data')
    overlay.symlink_to(outside)
    assert_refused(lambda: iris.prepare(home, link=True))
    assert (outside / 'vocabulary.yaml').read_text() == 'user data'
    overlay.unlink()
    write(overlay / 'vocabulary.yaml', 'occupied')
    assert_refused(lambda: iris.prepare(home, link=True))
    assert (overlay / 'vocabulary.yaml').read_text() == 'occupied'

print('managed Stow migration tests passed')
