{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.dotfiles.labDnsDhcp;
  stateDir = "/var/lib/lab-dns-dhcp";
  runtimeDir = "/run/lab-dns-dhcp";
  overlayFile = "${stateDir}/private-reservations.json";
  authorityFile = "${stateDir}/dhcp-authority.json";
  receiptFile = "${stateDir}/phase2-prepared-receipt.json";
  validator = pkgs.writeText "lab-runtime-state.py" (builtins.readFile ../../../../scripts/lab-runtime-state.py);
  namesFile = pkgs.writeText "lab-dns-hosts" (lib.concatStringsSep "" (lib.mapAttrsToList
    (name: address: "${address} ${name}\n") cfg.records));
  reservationIntent = pkgs.writeText "lab-reservation-intent.json" (builtins.toJSON cfg.reservations);
  forwarderLines = lib.concatMapStringsSep "\n" (address: "server=${address}") cfg.forwarders;
  prepare = pkgs.writeShellApplication {
    name = "lab-dns-dhcp-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.python3 pkgs.util-linux ];
    text = ''
      set -euE
      state_dir=${lib.escapeShellArg stateDir}
      runtime_dir=${lib.escapeShellArg runtimeDir}
      overlay=${lib.escapeShellArg overlayFile}
      authority=${lib.escapeShellArg authorityFile}
      receipt=${lib.escapeShellArg receiptFile}
      intent=${lib.escapeShellArg reservationIntent}
      transaction_file="$state_dir/active-operation.json"
      proc_root=''${LAB_DHCP_PROC_ROOT:-/proc}
      kill_cmd=''${LAB_DHCP_KILL:-kill}
      umask 077

      install -d -m 0750 "$runtime_dir"
      exec 9>"$state_dir/render.lock"
      flock -w 2 9
      exec 7>"$state_dir/operation.lock"
      runtime_identity=$(cat "$proc_root/sys/kernel/random/boot_id")
      tmp="$runtime_dir/dnsmasq.conf.new"
      state_tmp="$runtime_dir/authority-state.new"
      cat > "$tmp" <<'EOF'
      port=53
      interface=${cfg.interface}
      listen-address=${cfg.address}
      bind-interfaces
      no-resolv
      domain-needed
      bogus-priv
      local=/${cfg.privateZone}/
      addn-hosts=${namesFile}
      ${forwarderLines}
      cache-size=1000
      domain=${cfg.searchDomain}
      EOF

      if test -e "$authority"; then
        test -f "$authority" && test ! -L "$authority"
        test "$(stat -c %U:%G:%a "$authority")" = root:root:600
        now=$(date +%s)
        test -f "$overlay" && test ! -L "$overlay"
        overlay_sha=$(sha256sum "$overlay" | cut -d' ' -f1)
        jq -e --argjson now "$now" --arg sha "$overlay_sha" '
          .version == 1 and .authority == "hades" and .phase == "phase2" and
          (.preparedState | type == "string" and length >= 16) and
          .overlaySha256 == $sha and
          ((.expiresAt == null) or (.expiresAt | type == "number" and . > $now))
        ' "$authority" >/dev/null

        test -s "$overlay"
        test -f "$overlay" && test ! -L "$overlay"
        test "$(stat -c %U:%G:%a "$overlay")" = root:root:600
        authority_transaction=$(jq -r .transactionId "$authority")
        test ! -e "$state_dir/cancelled-all"
        test ! -e "$state_dir/cancelled-$authority_transaction"
        pending_args=()
        if test "$(jq -r .activationState "$authority")" = pending; then
          if flock -n 7; then
            flock -u 7
            echo 'pending DHCP authority has no live lifecycle operation' >&2
            exit 1
          fi
          pending_args=(--allow-pending --transaction-id "$(jq -r .transactionId "$authority")")
          test -f "$transaction_file" && test ! -L "$transaction_file"
          test "$(stat -c %U:%G:%a "$transaction_file")" = root:root:600
          test "$(jq -r .transactionId "$transaction_file")" = "$(jq -r .transactionId "$authority")"
          controller_pid=$(jq -r .controllerPid "$transaction_file")
          test "$controller_pid" = "$(jq -r .controllerPid "$authority")"
          test "$(jq -r .runtimeIdentity "$transaction_file")" = "$runtime_identity"
          test "$(jq -r .controllerStartTime "$transaction_file")" = "$(cut -d' ' -f22 "$proc_root/$controller_pid/stat")"
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$(jq -r .transactionId "$authority")"
          "$kill_cmd" -0 "$controller_pid"
        fi
        python3 ${validator} dhcp --now "$now" --runtime-identity "$runtime_identity" \
          --intent "$intent" --overlay "$overlay" --authority "$authority" --receipt "$receipt" \
          "''${pending_args[@]}" >/dev/null
        jq -e --slurpfile intent "$intent" '
          .version == 1 and (.bindings | type == "object") and
          ((.bindings | keys | sort) == ($intent[0] | keys | sort)) and
          ([.bindings[].macAddress | ascii_downcase] | length == (unique | length)) and
          all(.bindings[]; (.macAddress | test("^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$")))
        ' "$overlay" >/dev/null

        jq -r --slurpfile intent "$intent" '
          .bindings | to_entries[] |
          "dhcp-host=" + (.value.macAddress | ascii_downcase) + "," + $intent[0][.key].address + "," + .key + ",${toString cfg.leaseSeconds}"
        ' "$overlay" >> "$tmp"
        cat >> "$tmp" <<'EOF'
      dhcp-authoritative
      dhcp-range=${cfg.poolStart},${cfg.poolEnd},${cfg.netmask},${toString cfg.leaseSeconds}
      dhcp-option=option:router,${cfg.router}
      dhcp-option=option:dns-server,${cfg.address}
      dhcp-option=option:domain-search,${lib.concatStringsSep "," cfg.searchDomains}
      dhcp-leasefile=${stateDir}/dnsmasq.leases
      EOF
        printf '%s\n' dhcp > "$state_tmp"
      else
        printf '%s\n' dns-only > "$state_tmp"
      fi

      install -m 0600 "$tmp" "$runtime_dir/dnsmasq.conf"
      install -m 0600 "$state_tmp" "$runtime_dir/authority-state"
      flock -u 9
    '';
  };
  authority = pkgs.writeShellApplication {
    name = "lab-dhcp-authority";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.python3 pkgs.systemd pkgs.util-linux ];
    text = ''
      set -euE
      state_dir=${lib.escapeShellArg stateDir}
      authority="$state_dir/dhcp-authority.json"
      overlay="$state_dir/private-reservations.json"
      receipt=${lib.escapeShellArg receiptFile}
      command=''${1:-}
      prepared_state=''${2:-}
      install -d -m 0700 "$state_dir"
      exec 8>"$state_dir/operation.lock"
      flock 8
      exec 6>"$state_dir/cancellation.lock"
      exec 9>"$state_dir/render.lock"
      flock -w 2 9
      transaction_id=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
      transaction_file="$state_dir/active-operation.json"
      systemctl_cmd=''${LAB_DHCP_SYSTEMCTL:-systemctl}
      systemd_run_cmd=''${LAB_DHCP_SYSTEMD_RUN:-systemd-run}
      proc_root=''${LAB_DHCP_PROC_ROOT:-/proc}
      kill_cmd=''${LAB_DHCP_KILL:-kill}
      terminal_hook=''${LAB_DHCP_TERMINAL_HOOK:-}
      runtime_identity=$(cat "$proc_root/sys/kernel/random/boot_id")
      controller_start_time=$(cut -d' ' -f22 "$proc_root/$$/stat")
      if test ${lib.escapeShellArg (if cfg.enable then "true" else "false")} != true && test "$command" != status; then
        echo 'lab DNS/DHCP is disabled in this generation' >&2
        exit 1
      fi
      fence_service() {
        main_pid=0
        control_pid=0
        unit_fenced() {
          unit_output=$(timeout --kill-after=1 2 "$systemctl_cmd" show \
            --property=ActiveState --property=MainPID --property=ControlPID lab-dns-dhcp.service) || return 1
          while IFS='=' read -r property value; do
            case "$property" in ActiveState) state=$value ;; MainPID) main_pid=$value ;; ControlPID) control_pid=$value ;; esac
          done <<< "$unit_output"
          { test "$state" = inactive || test "$state" = failed; } &&
            test "$main_pid" = 0 && test "$control_pid" = 0
        }
        timeout --kill-after=1 2 "$systemctl_cmd" stop --no-block lab-dns-dhcp.service || true
        for _ in 1 2; do
          unit_fenced && return 0
          sleep 1
        done
        timeout --kill-after=1 2 "$systemctl_cmd" kill --kill-who=all --signal=KILL lab-dns-dhcp.service || true
        for pid in "$main_pid" "$control_pid"; do
          if printf '%s' "$pid" | grep -Eq '^[0-9]+$' && test "$pid" -gt 1 && grep -q '/lab-dns-dhcp.service' "$proc_root/$pid/cgroup" 2>/dev/null; then "$kill_cmd" -KILL "$pid" 2>/dev/null || true; fi
        done
        for _ in 1 2; do
          unit_fenced && return 0
          sleep 1
        done
        return 1
      }
      revoke_locked() {
        if test -e "$authority"; then
          rejected="$state_dir/.rejected-authority.$(date +%s).$$"
          mv "$authority" "$rejected"
        fi
        rm -f ${lib.escapeShellArg "${runtimeDir}/dnsmasq.conf"} ${lib.escapeShellArg "${runtimeDir}/authority-state"}
        rm -f "$transaction_file"
        sync "$state_dir"
      }
      recover_dns_only() {
        if ! flock -w 2 9; then
          fence_service || true
          echo 'timed out acquiring the render lock; service remains fenced' >&2
          return 1
        fi
        fence_service || { echo 'failed to fence DHCP service' >&2; return 1; }
        revoke_locked || { echo 'failed to revoke DHCP authority; service remains fenced' >&2; return 1; }
        flock -u 9
        timeout --kill-after=1 2 "$systemctl_cmd" start lab-dns-dhcp.service
        timeout --kill-after=1 2 "$systemctl_cmd" is-active --quiet lab-dns-dhcp.service
        grep -qx dns-only ${lib.escapeShellArg "${runtimeDir}/authority-state"}
      }
      activate_dhcp() {
        test ! -e "$state_dir/cancelled-all"
        test ! -e "$state_dir/cancelled-$transaction_id"
        flock -u 9
        if timeout --kill-after=1 2 "$systemctl_cmd" restart lab-dns-dhcp.service &&
          timeout --kill-after=1 2 "$systemctl_cmd" is-active --quiet lab-dns-dhcp.service &&
          grep -qx dhcp ${lib.escapeShellArg "${runtimeDir}/authority-state"}; then
          if ! flock -w 2 9; then
            fence_service || true
            echo 'timed out reacquiring the render lock after activation; service remains fenced' >&2
            return 1
          fi
          flock -w 2 6
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$transaction_id"
          python3 ${validator} activate --now "$(date +%s)" --runtime-identity "$runtime_identity" \
            --intent ${lib.escapeShellArg reservationIntent} --overlay "$overlay" --authority "$authority" \
            --receipt "$receipt" --allow-pending --transaction-id "$transaction_id" >/dev/null
          flock -u 9
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$transaction_id"
          outcome_tmp=$(mktemp "$state_dir/.operation-outcome.XXXXXX")
          printf '{"transactionId":"%s","outcome":"active"}\n' "$transaction_id" > "$outcome_tmp"
          chmod 0600 "$outcome_tmp"
          chown root:root "$outcome_tmp"
          sync "$outcome_tmp"
          mv -f "$outcome_tmp" "$state_dir/operation-outcome.json"
          sync "$state_dir"
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$transaction_id"
          if test -n "$terminal_hook"; then "$terminal_hook"; fi
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$transaction_id"
          flock -u 6
          return 0
        fi
        return 1
      }
      schedule_deadline() {
        deadline=$1
        now=$(date +%s)
        test "$deadline" -gt $(( now + 45 ))
        trigger=$(( deadline - 45 ))
        unit="lab-dhcp-authority-deadline-$deadline-$$"
        "$systemd_run_cmd" --quiet --unit "$unit" --on-calendar="@$trigger" \
          --timer-property=AccuracySec=1s --timer-property=RandomizedDelaySec=0 \
          ${watchdog}/bin/lab-dhcp-authority-watchdog --deadline "$deadline" "$transaction_id"
      }
      transition_failed() {
        status=$?
        trap - ERR
        flock -u 9 || true
        recover_dns_only || true
        exit "$status"
      }
      if test "$command" = arm || test "$command" = confirm; then
        if test "$command" = confirm; then
          existing_transaction=$(jq -r '.transactionId // empty' "$authority")
          test ! -e "$state_dir/cancelled-all"
          test ! -e "$state_dir/cancelled-$existing_transaction"
        fi
        operation_tmp=$(mktemp "$state_dir/.active-operation.XXXXXX")
        printf '{"transactionId":"%s","controllerPid":%s,"controllerStartTime":"%s","runtimeIdentity":"%s"}\n' \
          "$transaction_id" "$$" "$controller_start_time" "$runtime_identity" > "$operation_tmp"
        chmod 0600 "$operation_tmp"
        chown root:root "$operation_tmp"
        sync "$operation_tmp"
        mv -f "$operation_tmp" "$transaction_file"
        sync "$state_dir"
        trap transition_failed ERR
      fi
      case "$command" in
        arm)
          test ! -e "$state_dir/cancelled-all"
          test -z "$prepared_state"
          test -f "$receipt" && test ! -L "$receipt"
          test "$(stat -c %U:%G:%a "$receipt")" = root:root:600
          test -f "$overlay" && test ! -L "$overlay"
          test "$(stat -c %U:%G:%a "$overlay")" = root:root:600
          now=$(date +%s)
          overlay_sha=$(sha256sum "$overlay" | cut -d' ' -f1)
          jq -e --argjson now "$now" --arg sha "$overlay_sha" --arg runtimeIdentity "$runtime_identity" '
            .version == 1 and .authority == "hades" and .phase == "phase2" and
            .transition == "charon-to-hades" and .charonDhcpSilent == true and
            (.preparedState | type == "string" and length >= 16) and
            (.expiresAt | type == "number" and . > $now) and .overlaySha256 == $sha and
            .runtimeIdentity == $runtimeIdentity
          ' "$receipt" >/dev/null
          prepared_state=$(jq -r .preparedState "$receipt")
          receipt_expires=$(jq -r .expiresAt "$receipt")
          receipt_sha=$(sha256sum "$receipt" | cut -d' ' -f1)
          expires_at=$(( now + ${toString cfg.authorityArmSeconds} ))
          if test "$expires_at" -gt "$receipt_expires"; then expires_at=$receipt_expires; fi
          schedule_deadline "$expires_at"
          tmp=$(mktemp "$state_dir/.dhcp-authority.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          jq -n --arg state "$prepared_state" --arg sha "$overlay_sha" --arg runtimeIdentity "$runtime_identity" \
            --arg receiptSha "$receipt_sha" --argjson expires "$expires_at" \
            --arg transactionId "$transaction_id" --argjson controllerPid "$$" \
            '{version:1,authority:"hades",phase:"phase2",transition:"charon-to-hades",charonDhcpSilent:true,preparedState:$state,overlaySha256:$sha,runtimeIdentity:$runtimeIdentity,sourceReceiptSha256:$receiptSha,expiresAt:$expires,activationState:"pending",transactionId:$transactionId,controllerPid:$controllerPid}' > "$tmp"
          chown root:root "$tmp"
          chmod 0600 "$tmp"
          sync "$tmp"
          mv -f "$tmp" "$authority"
          sync "$state_dir"
          trap - EXIT
          activate_dhcp
          ;;
        confirm)
          test -n "$prepared_state"
          now=$(date +%s)
          receipt_expires=$(jq -r .expiresAt "$receipt")
          schedule_deadline "$receipt_expires"
          python3 ${validator} confirm --now "$now" --runtime-identity "$runtime_identity" \
            --intent ${lib.escapeShellArg reservationIntent} --overlay "$overlay" \
            --authority "$authority" --receipt "$receipt" --prepared-state "$prepared_state" \
            --transaction-id "$transaction_id" --controller-pid "$$" >/dev/null
          activate_dhcp
          ;;
        disarm)
          flock -u 9
          recover_dns_only
          ;;
        clear-cancellation)
          flock -u 9
          recover_dns_only
          if ! flock -w 2 9; then
            fence_service || true
            echo 'timed out reacquiring the render lock; cancellation remains sticky and service remains fenced' >&2
            exit 1
          fi
          for marker in "$state_dir"/cancelled-*; do
            test -e "$marker" || continue
            test -f "$marker" && test ! -L "$marker"
            rm -f -- "$marker"
          done
          sync "$state_dir"
          flock -u 9
          ;;
        status)
          if test -s "$authority"; then
            jq '{version,authority,preparedState,expiresAt}' "$authority"
          else
            printf '%s\n' '{"authority":"none"}'
          fi
          ;;
        *)
          echo 'usage: lab-dhcp-authority arm | confirm <prepared-state> | disarm | clear-cancellation | status' >&2
          exit 2
          ;;
      esac
    '';
  };
  watchdog = pkgs.writeShellApplication {
    name = "lab-dhcp-authority-watchdog";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.python3 pkgs.systemd pkgs.util-linux ];
    text = ''
      set -eu
      test ${lib.escapeShellArg (if cfg.enable then "true" else "false")} = true || exit 0
      authority=${lib.escapeShellArg authorityFile}
      overlay=${lib.escapeShellArg overlayFile}
      receipt=${lib.escapeShellArg receiptFile}
      intent=${lib.escapeShellArg reservationIntent}
      runtime_config=${lib.escapeShellArg "${runtimeDir}/dnsmasq.conf"}
      runtime_state=${lib.escapeShellArg "${runtimeDir}/authority-state"}
      state_dir=${lib.escapeShellArg stateDir}
      transaction_file="$state_dir/active-operation.json"
      deadline_mode=''${1:-}
      expected_deadline=''${2:-}
      expected_transaction=''${3:-}
      systemctl_cmd=''${LAB_DHCP_SYSTEMCTL:-systemctl}
      proc_root=''${LAB_DHCP_PROC_ROOT:-/proc}
      kill_cmd=''${LAB_DHCP_KILL:-kill}
      exec 6>"$state_dir/cancellation.lock"
      exec 8>"$state_dir/operation.lock"
      fence_without_locks() {
        main_pid=0
        control_pid=0
        unit_fenced() {
          unit_output=$(timeout --kill-after=1 2 "$systemctl_cmd" show \
            --property=ActiveState --property=MainPID --property=ControlPID lab-dns-dhcp.service) || return 1
          while IFS='=' read -r property value; do
            case "$property" in ActiveState) state=$value ;; MainPID) main_pid=$value ;; ControlPID) control_pid=$value ;; esac
          done <<< "$unit_output"
          { test "$state" = inactive || test "$state" = failed; } &&
            test "$main_pid" = 0 && test "$control_pid" = 0
        }
        timeout --kill-after=1 2 "$systemctl_cmd" stop --no-block lab-dns-dhcp.service || true
        for _ in 1 2; do
          unit_fenced && return 0
          sleep 1
        done
        timeout --kill-after=1 2 "$systemctl_cmd" kill --kill-who=all --signal=KILL lab-dns-dhcp.service || true
        for pid in "$main_pid" "$control_pid"; do
          if printf '%s' "$pid" | grep -Eq '^[0-9]+$' && test "$pid" -gt 1 && grep -q '/lab-dns-dhcp.service' "$proc_root/$pid/cgroup" 2>/dev/null; then "$kill_cmd" -KILL "$pid" 2>/dev/null || true; fi
        done
        for _ in 1 2; do
          unit_fenced && return 0
          sleep 1
        done
        return 1
      }
      persist_cancellation() {
        cancelled_transaction=""
        if test -f "$state_dir/active-operation.json" && test ! -L "$state_dir/active-operation.json"; then
          cancelled_transaction=$(jq -r '.transactionId // empty' "$state_dir/active-operation.json" 2>/dev/null || true)
        elif test -f "$authority" && test ! -L "$authority"; then
          cancelled_transaction=$(jq -r '.transactionId // empty' "$authority" 2>/dev/null || true)
        fi
        cancellation_tmp=$(mktemp "$state_dir/.cancelled-all.XXXXXX") || return 1
        printf '%s\n' cancelled > "$cancellation_tmp" || return 1
        chmod 0600 "$cancellation_tmp" && chown root:root "$cancellation_tmp" &&
          sync "$cancellation_tmp" && mv -f "$cancellation_tmp" "$state_dir/cancelled-all" || return 1
        if printf '%s' "$cancelled_transaction" | grep -Eq '^[0-9a-f]{32}$'; then
          transaction_cancel_tmp=$(mktemp "$state_dir/.cancelled-transaction.XXXXXX") || return 1
          printf '%s\n' "$cancelled_transaction" > "$transaction_cancel_tmp" || return 1
          chmod 0600 "$transaction_cancel_tmp" && chown root:root "$transaction_cancel_tmp" &&
            sync "$transaction_cancel_tmp" &&
            mv -f "$transaction_cancel_tmp" "$state_dir/cancelled-$cancelled_transaction" || return 1
        fi
        sync "$state_dir"
      }
      kill_cancelled_controller() {
        test -f "$state_dir/active-operation.json" && test ! -L "$state_dir/active-operation.json" || return 0
        controller_pid=$(jq -r '.controllerPid // empty' "$state_dir/active-operation.json" 2>/dev/null || true)
        printf '%s' "$controller_pid" | grep -Eq '^[0-9]+$' || return 1
        test "$controller_pid" -gt 1 || return 1
        test "$controller_pid" != "$$" || return 1
        marker_boot=$(jq -r '.runtimeIdentity // empty' "$state_dir/active-operation.json" 2>/dev/null || true)
        marker_start=$(jq -r '.controllerStartTime // empty' "$state_dir/active-operation.json" 2>/dev/null || true)
        test "$marker_boot" = "$(cat "$proc_root/sys/kernel/random/boot_id")" || return 1
        test -r "$proc_root/$controller_pid/stat" || return 0
        test "$marker_start" = "$(cut -d' ' -f22 "$proc_root/$controller_pid/stat")" || return 1
        tr '\0' ' ' < "$proc_root/$controller_pid/cmdline" | grep -q 'lab-dhcp-authority' || return 1
        "$kill_cmd" -KILL "$controller_pid" 2>/dev/null || true
        for _ in 1 2; do
          "$kill_cmd" -0 "$controller_pid" 2>/dev/null || return 0
          sleep 1
        done
        return 1
      }
      if ! flock -w 2 6; then
        cancellation_status=0
        persist_cancellation || cancellation_status=$?
        kill_cancelled_controller || true
        fence_without_locks || true
        test "$cancellation_status" -eq 0
        exit 1
      fi
      if ! flock -w 2 8; then
        cancellation_status=0
        persist_cancellation || cancellation_status=$?
        flock -u 6
        if test "$cancellation_status" -ne 0; then kill_cancelled_controller || true; fi
        fence_without_locks || true
        test "$cancellation_status" -eq 0
        exit 1
      fi
      flock -u 6
      exec 9>"$state_dir/render.lock"
      if ! flock -w 2 9; then
        cancellation_status=0
        persist_cancellation || cancellation_status=$?
        fence_without_locks || true
        test "$cancellation_status" -eq 0
        exit 1
      fi
      runtime_identity=$(cat "$proc_root/sys/kernel/random/boot_id")
      now=$(date +%s)
      current_transaction=$(jq -r '.transactionId // empty' "$authority" 2>/dev/null || true)
      if ! test -e "$state_dir/cancelled-all" && \
        ! test -e "$state_dir/cancelled-$current_transaction" && \
        python3 ${validator} dhcp --now "$now" --runtime-identity "$runtime_identity" --intent "$intent" \
        --overlay "$overlay" --authority "$authority" --receipt "$receipt" >/dev/null 2>&1; then
        if test "$deadline_mode" != --deadline; then exit 0; fi
        current_transaction=$(jq -r .transactionId "$authority")
        authority_deadline=$(jq -r '.expiresAt // empty' "$authority")
        if test -n "$authority_deadline"; then
          current_deadline=$authority_deadline
        else
          current_deadline=$(jq -r .expiresAt "$receipt")
        fi
        if test "$current_transaction" != "$expected_transaction" || \
          test "$current_deadline" != "$expected_deadline"; then
          exit 0
        fi
      fi
      if ! fence_without_locks; then
        echo 'failed to fence invalid DHCP authority' >&2
        exit 1
      fi
      if test -e "$authority"; then
        rejected="$state_dir/.rejected-authority.$(date +%s).$$"
        if ! mv "$authority" "$rejected"; then
          echo 'failed to revoke invalid DHCP authority; service remains fenced' >&2
          exit 1
        fi
      fi
      rm -f "$transaction_file"
      sync "$state_dir"
      rm -f "$runtime_config" "$runtime_state"
      flock -u 9
      timeout --kill-after=1 2 "$systemctl_cmd" start lab-dns-dhcp.service
      timeout --kill-after=1 2 "$systemctl_cmd" is-active --quiet lab-dns-dhcp.service
      grep -qx dns-only "$runtime_state"
    '';
  };
in {
  options.dotfiles.labDnsDhcp = {
    enable = mkOption { type = types.bool; default = false; description = "Activate Hades LAN DNS/DHCP after the .17.2 transition generation is selected."; };
    dhcpFirewallEnable = mkOption { type = types.bool; default = false; description = "Open UDP 67 only during the reviewed DHCP-authority generation."; };
    interface = mkOption { type = types.str; default = "enp1s0"; };
    address = mkOption { type = types.str; default = "192.168.17.2"; };
    router = mkOption { type = types.str; default = "192.168.17.1"; };
    netmask = mkOption { type = types.str; default = "255.255.255.0"; };
    poolStart = mkOption { type = types.str; default = "192.168.17.100"; };
    poolEnd = mkOption { type = types.str; default = "192.168.17.199"; };
    privateZone = mkOption { type = types.str; default = "lab.xavierchanth.xyz"; };
    searchDomain = mkOption { type = types.str; default = "lab.xavierchanth.xyz"; };
    searchDomains = mkOption { type = types.listOf types.str; default = [ "lab.xavierchanth.xyz" "lan" ]; };
    forwarders = mkOption { type = types.listOf types.str; default = [ "1.1.1.1" "1.0.0.1" ]; };
    records = mkOption { type = types.attrsOf types.str; default = { }; };
    reservations = mkOption {
      type = types.attrsOf (types.submodule { options.address = mkOption { type = types.str; }; });
      default = { };
      description = "Public logical reservation intent. Hardware identifiers come from the private runtime overlay.";
    };
    leaseSeconds = mkOption { type = types.ints.positive; default = 43200; readOnly = true; };
    authorityArmSeconds = mkOption { type = types.ints.between 60 900; default = 240; };
    privateOverlayFile = mkOption { type = types.str; default = overlayFile; readOnly = true; };
    authorityFile = mkOption { type = types.str; default = authorityFile; readOnly = true; };
  };

  config = {
    assertions = [
      { assertion = cfg.address == "192.168.17.2"; message = "Hades LAN DNS/DHCP must use 192.168.17.2"; }
      { assertion = cfg.router == "192.168.17.1"; message = "Charon must remain the Lab default gateway"; }
      { assertion = cfg.interface == "enp1s0"; message = "Hades LAN DNS/DHCP must remain scoped to enp1s0"; }
      { assertion = !cfg.dhcpFirewallEnable || cfg.enable; message = "DHCP firewall exposure requires LAN DNS/DHCP activation"; }
      { assertion = cfg.records != { }; message = "LAN DNS requires explicit records"; }
      { assertion = cfg.reservations != { }; message = "DHCP requires logical reservations"; }
      { assertion = lib.all (address: lib.hasPrefix "192.168.17." address) (builtins.attrValues cfg.records); message = "LAN DNS records must remain in the canonical Lab subnet"; }
      { assertion = lib.all (reservation: lib.hasPrefix "192.168.17." reservation.address) (builtins.attrValues cfg.reservations); message = "DHCP reservations must remain in the canonical Lab subnet"; }
      { assertion = builtins.length (map (reservation: reservation.address) (builtins.attrValues cfg.reservations)) == builtins.length (lib.unique (map (reservation: reservation.address) (builtins.attrValues cfg.reservations))); message = "DHCP reservation addresses must be unique"; }
    ];
    systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];
    systemd.services.lab-dns-dhcp = {
      description = "Hades LAN DNS and authority-gated DHCP";
      wantedBy = lib.optionals cfg.enable [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${prepare}/bin/lab-dns-dhcp-prepare";
        ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --conf-file=${runtimeDir}/dnsmasq.conf";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "lab-dns-dhcp";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "lab-dns-dhcp";
        StateDirectoryMode = "0700";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    systemd.services.lab-dhcp-authority-watchdog = {
      description = "Fail closed when the provisional Hades DHCP authority expires";
      serviceConfig = { Type = "oneshot"; ExecStart = "${watchdog}/bin/lab-dhcp-authority-watchdog"; };
    };
    systemd.timers.lab-dhcp-authority-watchdog = {
      wantedBy = lib.optionals cfg.enable [ "timers.target" ];
      timerConfig = { OnBootSec = "30s"; OnUnitActiveSec = "30s"; Unit = "lab-dhcp-authority-watchdog.service"; };
    };
    networking.firewall.interfaces.${cfg.interface} = lib.mkIf cfg.enable {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ] ++ lib.optionals cfg.dhcpFirewallEnable [ 67 ];
    };
    environment.systemPackages = [ authority prepare ];
    dotfiles.labUpdate.requiredUnits = lib.optionals cfg.enable [ "lab-dns-dhcp.service" ];
  };
}
