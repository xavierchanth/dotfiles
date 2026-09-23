import fcntl
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time


root = pathlib.Path(os.environ["TEST_ROOT"])
source = (root / "nix/modules/nixos/lab-dns-dhcp/system.nix").read_text(encoding="utf-8")
start = source.index('  watchdog = pkgs.writeShellApplication {')
start = source.index("    text = ''\n", start) + len("    text = ''\n")
end = source.index("    '';\n  };\nin {", start)
watchdog_template = source[start:end]


def write_json(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)


with tempfile.TemporaryDirectory() as directory:
    tmp = pathlib.Path(directory)
    state_dir = tmp / "state"
    runtime_dir = tmp / "run"
    bin_dir = tmp / "bin"
    state_dir.mkdir()
    runtime_dir.mkdir()
    bin_dir.mkdir()
    authority = state_dir / "dhcp-authority.json"
    overlay = state_dir / "private-reservations.json"
    prepared_receipt = state_dir / "phase2-prepared-receipt.json"
    intent = tmp / "intent.json"
    service_state = tmp / "service-state.json"
    service_log = tmp / "systemctl.log"
    kill_log = tmp / "kill.log"
    runtime_state = runtime_dir / "authority-state"
    runtime_config = runtime_dir / "dnsmasq.conf"
    runtime_identity = "runtime-identity-watchdog-0001"
    proc_root = tmp / "proc"
    (proc_root / "sys/kernel/random").mkdir(parents=True, exist_ok=True)
    (proc_root / "sys/kernel/random/boot_id").write_text(runtime_identity + "\n", encoding="utf-8")
    (proc_root / "4242").mkdir(exist_ok=True)
    (proc_root / "4242/cgroup").write_text("0::/system.slice/lab-dns-dhcp.service\n", encoding="utf-8")
    uid = os.getuid()
    gid = os.getgid()

    mock_systemctl = bin_dir / "systemctl"
    mock_systemctl.write_text(
        """#!/usr/bin/env python3
import json, os, pathlib, signal as signals, sys
state_path = pathlib.Path(os.environ['MOCK_SERVICE_STATE'])
log_path = pathlib.Path(os.environ['MOCK_SERVICE_LOG'])
runtime_state = pathlib.Path(os.environ['MOCK_RUNTIME_STATE'])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
with log_path.open('a') as handle: handle.write(' '.join(args) + '\\n')
command = args[0]
if os.environ.get('MOCK_SYSTEMCTL_HANG') == command:
    import time
    time.sleep(30)
if command == 'restart' and os.environ.get('MOCK_RESTART_FAIL') == '1':
    raise SystemExit(1)
if command == 'restart':
    render_ready = os.environ.get('MOCK_RESTART_RENDER_READY')
    render_acquired = os.environ.get('MOCK_RESTART_RENDER_ACQUIRED')
    if render_ready:
        import time
        pathlib.Path(render_ready).write_text('ready')
        while render_acquired and not pathlib.Path(render_acquired).exists(): time.sleep(0.02)
    state.update(ActiveState='active', MainPID='4242', ControlPID='0')
    runtime_state.write_text('dhcp\\n')
    activated = os.environ.get('MOCK_ACTIVATED')
    if activated: pathlib.Path(activated).write_text('activated')
if command == 'show':
    for value in args:
        if value.startswith('--property='):
            prop = value.split('=', 1)[1]
            print(state[prop] if '--value' in args else f'{prop}={state[prop]}')
elif command in {'stop', 'kill'}:
    if not (command == 'stop' and os.environ.get('MOCK_STOP_STUCK') == '1'):
        state.update(ActiveState='inactive', MainPID='0', ControlPID='0')
elif command == 'start':
    state.update(ActiveState='active', MainPID='4242', ControlPID='0')
    runtime_state.write_text('dns-only\\n')
elif command == 'is-active':
    raise SystemExit(0 if state['ActiveState'] == 'active' else 3)
state_path.write_text(json.dumps(state))
""",
        encoding="utf-8",
    )
    mock_systemctl.chmod(0o755)

    mock_kill = bin_dir / "kill"
    mock_kill.write_text(
        """#!/usr/bin/env python3
import json, os, pathlib, signal as signals, sys
state_path = pathlib.Path(os.environ['MOCK_SERVICE_STATE'])
state = json.loads(state_path.read_text())
signal, pid = sys.argv[1:]
with pathlib.Path(os.environ['MOCK_KILL_LOG']).open('a') as handle:
    handle.write(f'{signal} {pid}\\n')
if pid == '4242' and signal == '-KILL':
    state.update(ActiveState='inactive', MainPID='0', ControlPID='0')
    state_path.write_text(json.dumps(state))
    raise SystemExit(0)
if signal == '-KILL':
    os.kill(int(pid), signals.SIGKILL)
    raise SystemExit(0)
if signal == '-0':
    try: os.kill(int(pid), 0)
    except ProcessLookupError: raise SystemExit(1)
    raise SystemExit(0)
raise SystemExit(1)
""",
        encoding="utf-8",
    )
    mock_kill.chmod(0o755)

    for name, body in {
        "stat": "#!/bin/sh\nprintf '%s\\n' root:root:600\n",
        "chown": "#!/bin/sh\nexit 0\n",
    }.items():
        path = bin_dir / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    mock_systemd_run = bin_dir / "systemd-run"
    mock_systemd_run.write_text(
        """#!/usr/bin/env python3
import os, pathlib, sys, time
ready = os.environ.get('MOCK_SYSTEMD_RUN_READY')
release = os.environ.get('MOCK_SYSTEMD_RUN_RELEASE')
proc_root = os.environ.get('MOCK_CONTROLLER_PROC_ROOT')
if proc_root:
    controller = pathlib.Path(proc_root) / str(os.getppid())
    controller.mkdir(exist_ok=True)
    controller.joinpath('stat').write_text('x ' * 21 + '12345\\n')
    controller.joinpath('cmdline').write_bytes(b'lab-dhcp-authority\\0')
    if not sys.argv[1:]:
        if ready: pathlib.Path(ready).write_text('ready')
        while release and not pathlib.Path(release).exists(): time.sleep(0.02)
        raise SystemExit(0)
    raise SystemExit(0)
if ready: pathlib.Path(ready).write_text('ready')
while release and not pathlib.Path(release).exists(): time.sleep(0.02)
""",
        encoding="utf-8",
    )
    mock_systemd_run.chmod(0o755)

    real_sync = shutil.which("sync")
    assert real_sync is not None
    mock_sync = bin_dir / "sync"
    mock_sync.write_text(
        f"""#!/usr/bin/env python3
import os, pathlib, time
ready = os.environ.get('MOCK_TERMINAL_SYNC_READY')
release = os.environ.get('MOCK_TERMINAL_SYNC_RELEASE')
activated = os.environ.get('MOCK_ACTIVATED')
transaction = pathlib.Path(os.environ['MOCK_STATE_DIR']) / 'active-operation.json'
if ready and activated and pathlib.Path(activated).exists() and not transaction.exists():
    pathlib.Path(ready).write_text('ready')
    while release and not pathlib.Path(release).exists(): time.sleep(0.02)
os.execv({real_sync!r}, [{real_sync!r}, *os.sys.argv[1:]])
""",
        encoding="utf-8",
    )
    mock_sync.chmod(0o755)

    mock_flock = bin_dir / "flock"
    mock_flock.write_text(
        """#!/usr/bin/env python3
import fcntl, sys, time
args = sys.argv[1:]
unlock = '-u' in args
nonblock = '-n' in args
timeout = 0.0
if '-w' in args: timeout = float(args[args.index('-w') + 1])
fd = int(args[-1])
if unlock:
    fcntl.flock(fd, fcntl.LOCK_UN)
    raise SystemExit(0)
deadline = time.monotonic() + timeout
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | (fcntl.LOCK_NB if nonblock or timeout else 0))
        raise SystemExit(0)
    except BlockingIOError:
        if nonblock or time.monotonic() >= deadline: raise SystemExit(1)
        time.sleep(0.02)
""",
        encoding="utf-8",
    )
    mock_flock.chmod(0o755)

    substitutions = {
        '${lib.escapeShellArg (if cfg.enable then "true" else "false")}': "true",
        "${lib.escapeShellArg authorityFile}": str(authority),
        "${lib.escapeShellArg overlayFile}": str(overlay),
        "${lib.escapeShellArg receiptFile}": str(prepared_receipt),
        "${lib.escapeShellArg reservationIntent}": str(intent),
        '${lib.escapeShellArg "${runtimeDir}/dnsmasq.conf"}': str(runtime_config),
        '${lib.escapeShellArg "${runtimeDir}/authority-state"}': str(runtime_state),
        "${lib.escapeShellArg stateDir}": str(state_dir),
        "${validator}": str(root / "scripts/lab-runtime-state.py"),
        "''${1:-}": "${1:-}",
        "''${2:-}": "${2:-}",
        "''${3:-}": "${3:-}",
        "''${LAB_DHCP_SYSTEMCTL:-systemctl}": "${LAB_DHCP_SYSTEMCTL:-systemctl}",
        "''${LAB_DHCP_PROC_ROOT:-/proc}": "${LAB_DHCP_PROC_ROOT:-/proc}",
        "''${LAB_DHCP_KILL:-kill}": "${LAB_DHCP_KILL:-kill}",
        "''${LAB_DHCP_TERMINAL_HOOK:-}": "${LAB_DHCP_TERMINAL_HOOK:-}",
    }
    watchdog = watchdog_template
    for old, new in substitutions.items():
        watchdog = watchdog.replace(old, new)
    watchdog = watchdog.replace(
        "python3 " + str(root / "scripts/lab-runtime-state.py") + " dhcp",
        f"python3 {root / 'scripts/lab-runtime-state.py'} dhcp --expected-uid {uid} --expected-gid {gid}",
    )
    assert not re.search(r"\$\{(?:lib|validator)", watchdog), watchdog
    watchdog_path = tmp / "watchdog.sh"
    watchdog_path.write_text("#!/bin/bash\n" + watchdog, encoding="utf-8")
    watchdog_path.chmod(0o755)

    write_json(intent, {"hades": {"address": "192.168.17.2"}})
    bindings = {"version": 1, "bindings": {"hades": {"macAddress": "02:aa:00:00:00:02"}}}
    write_json(overlay, bindings)
    overlay_sha = hashlib.sha256(overlay.read_bytes()).hexdigest()

    env = os.environ | {
        "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
        "LAB_DHCP_SYSTEMCTL": str(mock_systemctl),
        "MOCK_SERVICE_STATE": str(service_state),
        "MOCK_SERVICE_LOG": str(service_log),
        "MOCK_RUNTIME_STATE": str(runtime_state),
        "MOCK_KILL_LOG": str(kill_log),
        "MOCK_STATE_DIR": str(state_dir),
        "LAB_DHCP_PROC_ROOT": str(proc_root),
        "LAB_DHCP_KILL": str(mock_kill),
    }

    def fixture(activation="active", transaction="transaction-current-0001", expires=None):
        expiry = expires or int(time.time()) + 120
        prepared = {
            "version": 1, "authority": "hades", "phase": "phase2",
            "transition": "charon-to-hades", "charonDhcpSilent": True,
            "preparedState": "prepared-state-0001", "overlaySha256": overlay_sha,
            "runtimeIdentity": runtime_identity, "expiresAt": expiry,
        }
        write_json(prepared_receipt, prepared)
        authority_value = prepared | {
            "sourceReceiptSha256": hashlib.sha256(prepared_receipt.read_bytes()).hexdigest(),
            "activationState": activation, "transactionId": transaction,
            "controllerPid": os.getpid(),
        }
        write_json(authority, authority_value)
        runtime_state.write_text("dhcp\n", encoding="utf-8")
        runtime_config.write_text("dhcp-range=192.168.17.100,192.168.17.199\n", encoding="utf-8")
        write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
        service_log.write_text("", encoding="utf-8")
        return expiry

    # A stale deadline from an older transaction is a no-op.
    deadline = fixture()
    subprocess.run([watchdog_path, "--deadline", str(deadline), "transaction-stale-0001"], env=env, check=True)
    assert service_log.read_text(encoding="utf-8") == ""
    assert authority.exists()

    # The matching early deadline is forced-expiry: fence, revoke, then DNS-only.
    subprocess.run([watchdog_path, "--deadline", str(deadline), "transaction-current-0001"], env=env, check=True)
    assert not authority.exists()
    log = service_log.read_text(encoding="utf-8")
    assert log.index("stop --no-block") < log.index("start lab-dns-dhcp.service")
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"

    # A pending receipt abandoned by its operator is never accepted normally.
    fixture(activation="pending")
    subprocess.run([watchdog_path], env=env, check=True)
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"

    # Operation-lock contention cannot interleave; timeout fences immediately.
    fixture()
    lock_handle = (state_dir / "operation.lock").open("a")
    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
    started = time.monotonic()
    result = subprocess.run([watchdog_path], env=env, timeout=5)
    elapsed = time.monotonic() - started
    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    lock_handle.close()
    assert result.returncode != 0
    assert 1.5 <= elapsed < 5
    fenced = json.loads(service_state.read_text(encoding="utf-8"))
    assert fenced == {"ActiveState": "inactive", "MainPID": "0", "ControlPID": "0"}

    # Render-lock contention is independently bounded and cannot leave DHCP
    # serving while a renderer owns the final configuration fence.
    fixture()
    render_lock = (state_dir / "render.lock").open("a")
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_EX)
    started = time.monotonic()
    result = subprocess.run([watchdog_path], env=env, timeout=5)
    elapsed = time.monotonic() - started
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_UN)
    render_lock.close()
    assert result.returncode != 0
    assert 1.5 <= elapsed < 5
    fenced = json.loads(service_state.read_text(encoding="utf-8"))
    assert fenced == {"ActiveState": "inactive", "MainPID": "0", "ControlPID": "0"}

    # Reboot/start preparation must reject a previously cancelled transaction
    # before it can render a DHCP-enabled dnsmasq configuration.
    prepare_block = source.index('  prepare = pkgs.writeShellApplication {')
    prepare_start = source.index("    text = ''\n", prepare_block) + len("    text = ''\n")
    authority_block = source.index('  authority = pkgs.writeShellApplication {', prepare_start)
    prepare_end = source.rfind("    '';", prepare_start, authority_block)
    prepare_shell = source[prepare_start:prepare_end]
    names_file = tmp / "names"
    names_file.write_text("192.168.17.2 hades.lab.xavierchanth.xyz\n", encoding="utf-8")
    prepare_substitutions = substitutions | {
        "${lib.escapeShellArg runtimeDir}": str(runtime_dir),
        "${namesFile}": str(names_file),
        "${forwarderLines}": "server=1.1.1.1",
        "${cfg.interface}": "enp1s0",
        "${cfg.address}": "192.168.17.2",
        "${cfg.privateZone}": "lab.xavierchanth.xyz",
        "${cfg.searchDomain}": "lab.xavierchanth.xyz",
        "${cfg.poolStart}": "192.168.17.100",
        "${cfg.poolEnd}": "192.168.17.199",
        "${cfg.netmask}": "255.255.255.0",
        "${cfg.router}": "192.168.17.1",
        "${toString cfg.leaseSeconds}": "43200",
        '${lib.concatStringsSep "," cfg.searchDomains}': "lab.xavierchanth.xyz,lan",
        "''${pending_args[@]}": "${pending_args[@]}",
    }
    for old, new in prepare_substitutions.items():
        prepare_shell = prepare_shell.replace(old, new)
    prepare_shell = textwrap.dedent(prepare_shell)
    assert not re.search(r"\$\{(?:lib|cfg|validator|namesFile|forwarderLines|toString)", prepare_shell), prepare_shell
    prepare_path = tmp / "prepare.sh"
    prepare_path.write_text("#!/bin/bash\n" + prepare_shell, encoding="utf-8")
    prepare_path.chmod(0o755)
    tombstone_check = prepare_shell.index('test ! -e "$state_dir/cancelled-all"')
    authority_validation = prepare_shell.index("python3 ", tombstone_check)
    assert tombstone_check < authority_validation
    assert 'test ! -e "$state_dir/cancelled-$authority_transaction"' in prepare_shell
    for activation in ("active", "pending"):
        fixture(activation=activation)
        runtime_config.unlink(missing_ok=True)
        runtime_state.unlink(missing_ok=True)
        (state_dir / "cancelled-all").write_text("cancelled\n", encoding="utf-8")
        result = subprocess.run([prepare_path], env=env, text=True, capture_output=True)
        assert result.returncode != 0, (activation, result.stderr)
        assert not runtime_config.exists() or "dhcp-range=" not in runtime_config.read_text(encoding="utf-8")
        (state_dir / "cancelled-all").unlink()

    # Service preparation itself has a bounded render-lock acquisition and
    # cannot publish a DHCP configuration while another renderer is active.
    fixture()
    runtime_config.unlink(missing_ok=True)
    runtime_state.unlink(missing_ok=True)
    render_lock = (state_dir / "render.lock").open("a")
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_EX)
    started = time.monotonic()
    result = subprocess.run([prepare_path], env=env, timeout=5)
    elapsed = time.monotonic() - started
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_UN)
    render_lock.close()
    assert result.returncode != 0
    assert 1.5 <= elapsed < 5
    assert not runtime_config.exists()

    # Execute the generated authority controller with a failed restart. Its ERR
    # rollback must fence, revoke the pending receipt, and restore DNS-only.
    authority_block = source.index('  authority = pkgs.writeShellApplication {')
    authority_start = source.index("    text = ''\n", authority_block) + len("    text = ''\n")
    authority_end = source.index("    '';\n  };\n  watchdog =", authority_start)
    authority_shell = source[authority_start:authority_end]
    authority_substitutions = substitutions | {
        "${lib.escapeShellArg stateDir}": str(state_dir),
        "${lib.escapeShellArg receiptFile}": str(prepared_receipt),
        "${lib.escapeShellArg reservationIntent}": str(intent),
        '${lib.escapeShellArg "${runtimeDir}/dnsmasq.conf"}': str(runtime_config),
        '${lib.escapeShellArg "${runtimeDir}/authority-state"}': str(runtime_state),
        "${toString cfg.authorityArmSeconds}": "240",
        "${watchdog}": str(tmp / "watchdog-package"),
        "''${LAB_DHCP_SYSTEMD_RUN:-systemd-run}": "${LAB_DHCP_SYSTEMD_RUN:-systemd-run}",
    }
    for old, new in authority_substitutions.items():
        authority_shell = authority_shell.replace(old, new)
    authority_shell = re.sub(
        r"controller_start_time=\$\(cut -d' ' -f22 \"\$proc_root/\$\$/stat\"\)",
        "controller_start_time=12345",
        authority_shell,
    )
    for command in ("activate", "confirm"):
        authority_shell = authority_shell.replace(
            f"python3 {root / 'scripts/lab-runtime-state.py'} {command}",
            f"python3 {root / 'scripts/lab-runtime-state.py'} {command} --expected-uid {uid} --expected-gid {gid}",
        )
    assert not re.search(r"\$\{(?:lib|validator|watchdog|toString)", authority_shell), authority_shell
    authority_path = tmp / "authority.sh"
    authority_path.write_text("#!/bin/bash\n" + authority_shell, encoding="utf-8")
    authority_path.chmod(0o755)

    future = int(time.time()) + 600
    prepared = {
        "version": 1, "authority": "hades", "phase": "phase2",
        "transition": "charon-to-hades", "charonDhcpSilent": True,
        "preparedState": "prepared-state-0001", "overlaySha256": overlay_sha,
        "runtimeIdentity": runtime_identity, "expiresAt": future,
    }
    # Authority entry uses the same bounded render fence. Contention cannot
    # create an authority receipt or transition the DNS-only service to DHCP.
    authority.unlink(missing_ok=True)
    write_json(prepared_receipt, prepared)
    runtime_state.write_text("dns-only\n", encoding="utf-8")
    runtime_config.write_text("port=53\n", encoding="utf-8")
    render_lock = (state_dir / "render.lock").open("a")
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_EX)
    started = time.monotonic()
    result = subprocess.run(
        [authority_path, "arm"],
        env=env | {"LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run)},
        timeout=5,
    )
    elapsed = time.monotonic() - started
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_UN)
    render_lock.close()
    assert result.returncode != 0
    assert 1.5 <= elapsed < 5
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"

    # A renderer that wins the lock while restart is in flight cannot leave
    # DHCP active. The authority controller times out on reacquisition, fences
    # the service, and a later watchdog pass revokes the abandoned pending state.
    authority.unlink(missing_ok=True)
    write_json(prepared_receipt, prepared)
    runtime_state.write_text("dns-only\n", encoding="utf-8")
    runtime_config.write_text("port=53\n", encoding="utf-8")
    write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
    restart_ready = tmp / "restart-render.ready"
    restart_acquired = tmp / "restart-render.acquired"
    reacquire_env = env | {
        "LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run),
        "MOCK_RESTART_RENDER_READY": str(restart_ready),
        "MOCK_RESTART_RENDER_ACQUIRED": str(restart_acquired),
    }
    reacquire_controller = subprocess.Popen([authority_path, "arm"], env=reacquire_env)
    wait_deadline = time.monotonic() + 5
    while not restart_ready.exists() and time.monotonic() < wait_deadline:
        time.sleep(0.02)
    assert restart_ready.exists(), "authority controller did not reach restart"
    render_lock = (state_dir / "render.lock").open("a")
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_EX)
    restart_acquired.write_text("acquired", encoding="utf-8")
    assert reacquire_controller.wait(timeout=8) != 0
    fenced = json.loads(service_state.read_text(encoding="utf-8"))
    assert fenced == {"ActiveState": "inactive", "MainPID": "0", "ControlPID": "0"}
    fcntl.flock(render_lock.fileno(), fcntl.LOCK_UN)
    render_lock.close()
    subprocess.run([watchdog_path], env=env, check=True, timeout=8)
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"

    fixture(expires=future)
    (state_dir / "cancelled-all").write_text("cancelled\n", encoding="utf-8")
    cancelled_confirm = subprocess.run(
        [authority_path, "confirm", "prepared-state-0001"],
        env=env | {"LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run)},
    )
    assert cancelled_confirm.returncode != 0
    assert authority.exists()
    assert not (state_dir / "active-operation.json").exists()
    (state_dir / "cancelled-all").unlink()

    # Cancellation is sticky: arm refuses it, and only the explicit recovery
    # command may clear it before a later reauthorization.
    (state_dir / "cancelled-all").write_text("cancelled\n", encoding="utf-8")
    write_json(prepared_receipt, prepared)
    result = subprocess.run(
        [authority_path, "arm"],
        env=env | {"LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run)},
    )
    assert result.returncode != 0
    assert (state_dir / "cancelled-all").exists()
    result = subprocess.run([authority_path, "clear-cancellation"], env=env)
    assert result.returncode == 0
    assert not (state_dir / "cancelled-all").exists()
    result = subprocess.run(
        [authority_path, "arm"],
        env=env | {"LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run)},
    )
    assert result.returncode == 0
    assert json.loads(authority.read_text(encoding="utf-8"))["activationState"] == "active"
    assert runtime_state.read_text(encoding="utf-8") == "dhcp\n"

    write_json(prepared_receipt, prepared)
    runtime_state.write_text("dns-only\n", encoding="utf-8")
    runtime_config.write_text("port=53\n", encoding="utf-8")
    write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
    service_log.write_text("", encoding="utf-8")
    rollback_env = env | {
        "LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run),
        "MOCK_RESTART_FAIL": "1",
    }
    result = subprocess.run([authority_path, "arm"], env=rollback_env)
    assert result.returncode != 0
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"
    log = service_log.read_text(encoding="utf-8")
    assert log.index("restart lab-dns-dhcp.service") < log.index("stop --no-block") < log.rindex("start lab-dns-dhcp.service"), log

    # A deadline fence racing a real arm controller must durably cancel that
    # transaction. Once resumed, the controller may not reactivate DHCP.
    write_json(prepared_receipt, prepared)
    runtime_state.write_text("dns-only\n", encoding="utf-8")
    runtime_config.write_text("port=53\n", encoding="utf-8")
    write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
    service_log.write_text("", encoding="utf-8")
    ready = tmp / "systemd-run.ready"
    release = tmp / "systemd-run.release"
    concurrent_env = env | {
        "LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run),
        "MOCK_SYSTEMD_RUN_READY": str(ready),
        "MOCK_SYSTEMD_RUN_RELEASE": str(release),
    }
    controller = subprocess.Popen([authority_path, "arm"], env=concurrent_env)
    wait_deadline = time.monotonic() + 5
    while not ready.exists() and time.monotonic() < wait_deadline:
        time.sleep(0.02)
    assert ready.exists(), "arm controller did not reach the held deadline scheduler"
    deadline_result = subprocess.run(
        [watchdog_path, "--deadline", str(future), "transaction-does-not-matter"],
        env=env,
        timeout=6,
    )
    assert deadline_result.returncode != 0
    release.write_text("resume", encoding="utf-8")
    controller_status = controller.wait(timeout=6)
    final_service = json.loads(service_state.read_text(encoding="utf-8"))
    assert controller_status != 0
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"
    assert final_service == {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"}

    # A controller paused while holding the terminal cancellation lock cannot
    # delay expiry: the watchdog durably cancels, verified-kills the controller,
    # and fences DHCP after the bounded lock wait.
    subprocess.run([authority_path, "clear-cancellation"], env=env, check=True)
    write_json(prepared_receipt, prepared)
    write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
    terminal_ready = tmp / "terminal-sync.ready"
    terminal_release = tmp / "terminal-sync.release"
    activated_marker = tmp / "activation-happened"
    terminal_env = env | {
        "LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run),
        "LAB_DHCP_TERMINAL_HOOK": str(mock_systemd_run),
        "MOCK_SYSTEMD_RUN_READY": str(terminal_ready),
        "MOCK_SYSTEMD_RUN_RELEASE": str(terminal_release),
        "MOCK_CONTROLLER_PROC_ROOT": str(proc_root),
        "MOCK_ACTIVATED": str(activated_marker),
    }
    terminal_controller = subprocess.Popen([authority_path, "arm"], env=terminal_env)
    wait_deadline = time.monotonic() + 6
    while not terminal_ready.exists() and time.monotonic() < wait_deadline:
        time.sleep(0.02)
    assert terminal_ready.exists()
    terminal_authority = json.loads(authority.read_text(encoding="utf-8"))
    terminal_watchdog = subprocess.Popen(
        [watchdog_path, "--deadline", str(terminal_authority["expiresAt"]), terminal_authority["transactionId"]],
        env=env,
    )
    assert terminal_watchdog.wait(timeout=8) != 0
    terminal_status = terminal_controller.poll()
    assert terminal_status is not None and terminal_status != 0, "watchdog returned before terminating the cancelled controller"
    assert f"-KILL {terminal_controller.pid}" in kill_log.read_text(encoding="utf-8")
    terminal_release.write_text("resume", encoding="utf-8")
    assert terminal_controller.wait(timeout=6) == terminal_status
    # The first pass deliberately returns nonzero after fencing and killing.
    # Once the inherited hook descriptor is released, a second pass performs
    # durable revocation and the DNS-only restart.
    subprocess.run([watchdog_path], env=env, check=True)
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"

    # Aggregate hard-deadline accounting for cancellation, operation and
    # render waits; controller death observation; the worst stop/show/KILL
    # fence; and the final DNS-only restart.
    lock_waits = 2 + 2 + 2
    controller_kill_observation = 2
    stop_timeout = 3
    pre_kill_show_fence = (2 * 3) + 2
    kill_timeout = 3
    post_kill_show_fence = (2 * 3) + 2
    dns_only_restart = 3 + 3
    worst_case_seconds = (
        lock_waits + controller_kill_observation + stop_timeout +
        pre_kill_show_fence + kill_timeout + post_kill_show_fence + dns_only_restart
    )
    assert worst_case_seconds == 36
    assert worst_case_seconds < 45

    # Potentially blocking service-manager calls must remain bounded.
    fixture(activation="pending")
    hung_env = env | {"MOCK_SYSTEMCTL_HANG": "stop"}
    started = time.monotonic()
    try:
        subprocess.run([watchdog_path], env=hung_env, timeout=6)
    except subprocess.TimeoutExpired as error:
        raise AssertionError("watchdog stop fencing is not time-bounded") from error
    assert time.monotonic() - started < 6

    for hung_command, extra_env, bound in (
        ("show", {}, 35),
        ("kill", {"MOCK_STOP_STUCK": "1"}, 12),
        ("start", {}, 8),
    ):
        fixture(activation="pending")
        command_env = env | extra_env | {"MOCK_SYSTEMCTL_HANG": hung_command}
        started = time.monotonic()
        try:
            result = subprocess.run([watchdog_path], env=command_env, timeout=bound)
        except subprocess.TimeoutExpired as error:
            raise AssertionError(f"watchdog {hung_command} fencing is not time-bounded") from error
        assert time.monotonic() - started < bound
        if hung_command == "kill":
            assert result.returncode == 0
        else:
            assert result.returncode != 0
        final = json.loads(service_state.read_text(encoding="utf-8"))
        if hung_command == "kill":
            assert final == {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"}
            assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"
        else:
            assert final["ActiveState"] != "active" and final["MainPID"] == "0" and final["ControlPID"] == "0", (hung_command, final, service_log.read_text())

    fixture(activation="pending")
    combined_env = env | {"MOCK_STOP_STUCK": "1", "MOCK_SYSTEMCTL_HANG": "show"}
    started = time.monotonic()
    try:
        result = subprocess.run([watchdog_path], env=combined_env, timeout=35)
    except subprocess.TimeoutExpired as error:
        raise AssertionError("combined stuck-stop/hung-show fence exceeded hard margin") from error
    assert time.monotonic() - started < 35
    assert result.returncode != 0
    combined_final = json.loads(service_state.read_text(encoding="utf-8"))
    assert combined_final["ActiveState"] != "active"

    # A hung restart is bounded and drives the authority controller through
    # the same revoked DNS-only rollback path.
    write_json(prepared_receipt, prepared)
    runtime_state.write_text("dns-only\n", encoding="utf-8")
    runtime_config.write_text("port=53\n", encoding="utf-8")
    write_json(service_state, {"ActiveState": "active", "MainPID": "4242", "ControlPID": "0"})
    restart_hung_env = env | {
        "LAB_DHCP_SYSTEMD_RUN": str(mock_systemd_run),
        "MOCK_SYSTEMCTL_HANG": "restart",
    }
    started = time.monotonic()
    result = subprocess.run([authority_path, "arm"], env=restart_hung_env, timeout=10)
    assert time.monotonic() - started < 10
    assert result.returncode != 0
    assert not authority.exists()
    assert runtime_state.read_text(encoding="utf-8") == "dns-only\n"
