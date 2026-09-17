#!/usr/bin/env python3
"""Expose checkout-private Iris config independently of Stow generations."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROUTING_FILES = ('vocabulary.yaml', 'workspaces.yaml')
ROUTING_CONFIG = Path('skills/orchestration/iris/config')


def lexical(path):
    return Path(os.path.abspath(path))


def link_destination(path):
    return lexical(path.parent / os.readlink(path))


def stow_config_directories(home):
    return (
        lexical(home / '.dotfiles/stow/agents' / ROUTING_CONFIG),
        lexical(home / '.local/share/dotfiles/stow/agents' / ROUTING_CONFIG),
    )


def validate_config_path(config, stow_configs):
    if config.is_symlink():
        destination = link_destination(config)
        if destination not in stow_configs or destination.is_symlink() or not destination.is_dir():
            raise RuntimeError(f'refusing unrelated Iris config link: {config}')
    elif config.exists() and not config.is_dir():
        raise RuntimeError(f'refusing invalid Iris config path: {config}')


def ensure_ignored(checkout, git):
    relative = 'local/iris/vocabulary.yaml'
    check = subprocess.run([git, '-C', checkout, 'check-ignore', '--quiet', '--', relative])
    if check.returncode == 0:
        return
    if check.returncode != 1:
        raise RuntimeError(f'cannot inspect Dotfiles ignore rules: {checkout}')
    result = subprocess.run(
        [git, '-C', checkout, 'rev-parse', '--path-format=absolute', '--git-path', 'info/exclude'],
        check=True, capture_output=True, text=True)
    exclude = Path(result.stdout.strip())
    if exclude.is_symlink() or (exclude.exists() and not exclude.is_file()):
        raise RuntimeError(f'refusing invalid Git exclude path: {exclude}')
    contents = exclude.read_text() if exclude.exists() else ''
    rule = '/local/iris/'
    if rule not in contents.splitlines():
        exclude.parent.mkdir(parents=True, exist_ok=True)
        with exclude.open('a') as stream:
            if contents and not contents.endswith('\n'):
                stream.write('\n')
            stream.write(f'{rule}\n')
    check = subprocess.run([git, '-C', checkout, 'check-ignore', '--quiet', '--', relative])
    if check.returncode != 0:
        raise RuntimeError(f'cannot ignore Iris state in Dotfiles checkout: {checkout}')


def state_directory(home, git):
    checkout = home / '.dotfiles'
    if checkout.is_symlink() or not checkout.is_dir():
        raise RuntimeError(f'missing or invalid Dotfiles checkout: {checkout}')
    local = checkout / 'local'
    state = local / 'iris'
    for path in (local, state):
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            raise RuntimeError(f'refusing non-directory Iris state path: {path}')
    state.mkdir(parents=True, exist_ok=True)
    state.chmod(0o700)
    ensure_ignored(checkout, git)
    return state


def migrate_regular_file(source, destination):
    if source.is_symlink() or not source.is_file():
        raise RuntimeError(f'refusing non-file Iris routing state: {source}')
    if destination.is_symlink() or (destination.exists() and not destination.is_file()):
        raise RuntimeError(f'refusing invalid Iris state destination: {destination}')
    if destination.exists():
        if source.read_bytes() != destination.read_bytes():
            raise RuntimeError(f'refusing conflicting Iris routing state: {source}')
        source.unlink()
        destination.chmod(0o600)
        return
    temporary = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=f'.{destination.name}.', dir=destination.parent)
        os.close(descriptor)
        temporary = Path(name)
        shutil.copyfile(source, temporary)
        temporary.chmod(0o600)
        os.replace(temporary, destination)
        temporary = None
        source.unlink()
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def migrate_file(source, destination, stow_configs):
    if source.is_symlink():
        linked = link_destination(source)
        if linked == destination:
            if destination.exists():
                if destination.is_symlink() or not destination.is_file():
                    raise RuntimeError(f'refusing invalid Iris state destination: {destination}')
                destination.chmod(0o600)
            return
        expected = tuple(config / source.name for config in stow_configs)
        if linked not in expected or linked.is_symlink() or not linked.is_file():
            raise RuntimeError(f'refusing unrelated Iris routing link: {source}')
        migrate_regular_file(linked, destination)
        source.unlink()
        return
    if not source.exists():
        return
    migrate_regular_file(source, destination)


def prepare(home, *, link, git='git'):
    home = lexical(home)
    state = state_directory(home, git)
    # The overlay is a sibling of skills, so even a folded skills symlink is
    # left intact and no private links are written into a Stow source tree.
    overlay = home / '.agents/config/iris'
    for parent in (home / '.agents', overlay.parent):
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise RuntimeError(f'refusing redirected Iris config parent: {parent}')
    if overlay.is_symlink():
        if link_destination(overlay) != state:
            raise RuntimeError(f'refusing unrelated Iris config link: {overlay}')
    elif overlay.exists():
        raise RuntimeError(f'refusing occupied Iris config path: {overlay}')

    # Capture files from the previous, skill-local layout before Stow swaps
    # its source. The old directory need not exist in the next generation.
    config = home / '.agents' / ROUTING_CONFIG
    stow_configs = stow_config_directories(home)
    validate_config_path(config, stow_configs)
    for name in ROUTING_FILES:
        migrate_file(config / name, state / name, stow_configs)
        if (config / name).is_symlink():
            (config / name).unlink()
        destination = state / name
        if destination.is_symlink() or (destination.exists() and not destination.is_file()):
            raise RuntimeError(f'refusing invalid Iris state destination: {destination}')
        if destination.exists():
            destination.chmod(0o600)
    if not link:
        return
    overlay.parent.mkdir(parents=True, exist_ok=True)
    if not overlay.is_symlink():
        overlay.symlink_to(state, target_is_directory=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('migrate', 'link'))
    parser.add_argument('home', type=Path)
    parser.add_argument('--git', default='git')
    arguments = parser.parse_args()
    prepare(arguments.home, link=arguments.mode == 'link', git=arguments.git)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f'prepare-iris-routing: {error}')
