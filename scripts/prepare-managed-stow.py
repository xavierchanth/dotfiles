#!/usr/bin/env python3
"""Stage lab Stow sources and migrate only links owned by declared packages."""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


def lexical(path):
    return Path(os.path.abspath(path))


def owned_destination(link, roots):
    destination = lexical(link.parent / os.readlink(link))
    for root in roots:
        if destination == root or root in destination.parents:
            return destination.relative_to(root)
    return None


def links_under(target):
    if target.is_symlink():
        yield target
    elif target.is_dir():
        for directory, folders, files in os.walk(target, followlinks=False):
            for name in folders + files:
                path = Path(directory) / name
                if path.is_symlink():
                    yield path


def prepare(home, source, declarations, retired):
    home, source = lexical(home), lexical(source)
    base = home / '.local/share/dotfiles'
    managed = base / 'stow'
    original = home / '.dotfiles/stow'
    # Refuse unexpected links anywhere in the managed destination ancestry.
    for path in [home / '.local', home / '.local/share', base, managed]:
        if path.is_symlink() or (path.exists() and not path.is_dir()):
            raise RuntimeError(f'refusing non-directory managed Stow path: {path}')
    for item in declarations:
        package = source / item['name']
        if not package.is_dir() or package.is_symlink():
            raise RuntimeError(f'missing or invalid deployed Stow package: {package}')
        for path in links_under(package):
            destination = lexical(path.parent / os.readlink(path))
            if source not in destination.parents:
                raise RuntimeError(f'Stow source link escapes deployed source: {path}')
    # Inspect ownership before staging or changing links; never traverse a user
    # symlink that redirects a declared target to another directory.
    migrations = []
    selected = {item['name'] for item in declarations}
    for item in declarations + retired:
        target = home / item['target']
        roots = [original / item['name'], managed / item['name']]
        for ancestor in target.parents:
            if ancestor == home:
                break
            if ancestor.is_symlink():
                raise RuntimeError(f'Stow target ancestor is a symlink: {ancestor}')
        for link in links_under(target):
            relative = owned_destination(link, roots)
            if relative is not None:
                destination = managed / item['name'] / relative
                exists = item['name'] in selected and os.path.lexists(source / item['name'] / relative)
                if os.path.lexists(link.with_name(link.name + '.stow-migration')):
                    raise RuntimeError(f'refusing existing migration path beside: {link}')
                migrations.append((link, destination if exists else None, link == target and exists))
            elif link == target:
                raise RuntimeError(f'Stow target is an unrelated symlink: {target}')
    marker = managed / '.deployed-source'
    if not marker.is_file() or marker.is_symlink() or marker.read_text() != str(source):
        base.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix='.stow-stage-', dir=base))
        try:
            for item in declarations:
                shutil.copytree(source / item['name'], staging / item['name'], symlinks=True)
            # Nix store source permissions are read-only; mise updates its lock.
            for directory, _, files in os.walk(staging):
                os.chmod(directory, 0o700)
                for name in files:
                    path = Path(directory) / name
                    if not path.is_symlink():
                        os.chmod(path, path.stat().st_mode | 0o600)
            (staging / '.deployed-source').write_text(str(source))
            backup = None
            if managed.exists():
                backup = Path(tempfile.mkdtemp(prefix='stow-backup-', dir=base))
                managed.rename(backup / 'stow')
                print(f'Previous managed Stow source preserved at {backup / "stow"}')
            try:
                staging.rename(managed)
            except OSError:
                if backup is not None:
                    (backup / 'stow').rename(managed)
                raise
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    for link, destination, materialize in migrations:
        if materialize:
            # Stow must receive a real target directory, not its own package
            # directory through a folded link. Keep both source trees intact.
            previous = os.readlink(link)
            link.unlink()
            try:
                link.mkdir()
            except OSError:
                if not os.path.lexists(link):
                    link.symlink_to(previous)
                raise
        elif destination is None:
            link.unlink()
        else:
            replacement = link.with_name(link.name + '.stow-migration')
            if os.path.lexists(replacement):
                raise RuntimeError(f'refusing existing migration path: {replacement}')
            replacement.symlink_to(os.path.relpath(destination, link.parent))
            os.replace(replacement, link)


if __name__ == '__main__':
    try:
        prepare(Path(sys.argv[1]), Path(sys.argv[2]), json.loads(sys.argv[3]), json.loads(sys.argv[4]))
    except (OSError, RuntimeError) as error:
        sys.exit(f'prepare-managed-stow: {error}')
