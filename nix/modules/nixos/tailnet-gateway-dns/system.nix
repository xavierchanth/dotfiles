{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.dotfiles.tailnetGatewayDns;
  stateDir = "/var/lib/tailnet-gateway-dns";
  runtimeDir = "/run/tailnet-gateway-dns";
  stateFile = config.dotfiles.serviceGateway.tailscaleService.stateFile;
  validator = pkgs.writeText "lab-runtime-state.py" (builtins.readFile ../../../../scripts/lab-runtime-state.py);
  prepare = pkgs.writeShellApplication {
    name = "tailnet-gateway-dns-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.python3 pkgs.tailscale ];
    text = ''
      set -eu
      runtime_dir=${lib.escapeShellArg runtimeDir}
      umask 077
      state_file=${lib.escapeShellArg stateFile}
      test -f "$state_file" && test ! -L "$state_file"
      test "$(stat -c %U:%G:%a "$state_file")" = root:root:600
      test "$(wc -l < "$state_file")" -eq 1
      now=$(date +%s)
      validated=$(python3 ${validator} tailnet --now "$now" --state "$state_file")
      resolver=$(printf '%s\n' "$validated" | sed -n '1p')
      tailvip=$(printf '%s\n' "$validated" | sed -n '2p')
      live=$(tailscale ip -4 | sed -n '1p')
      test "$resolver" = "$live"
      install -d -m 0750 "$runtime_dir"
      tmp_hosts="$runtime_dir/hosts.new"
      tmp_corefile="$runtime_dir/Corefile.new"
      : > "$tmp_hosts"
      for name in ${lib.escapeShellArgs cfg.names}; do
        printf '%s %s\n' "$tailvip" "$name" >> "$tmp_hosts"
      done
      cat > "$tmp_corefile" <<EOF
      ${cfg.privateZone}:53 {
        bind $resolver
        errors
        hosts $runtime_dir/hosts {
          ttl ${toString cfg.ttl}
        }
        cache ${toString cfg.ttl}
      }
      .:53 {
        bind $resolver
        errors
        hosts $runtime_dir/hosts {
          ttl ${toString cfg.ttl}
          fallthrough
        }
        forward . ${lib.concatStringsSep " " cfg.forwarders}
        cache ${toString cfg.ttl}
      }
      EOF
      install -m 0600 "$tmp_hosts" "$runtime_dir/hosts"
      install -m 0600 "$tmp_corefile" "$runtime_dir/Corefile"
    '';
  };
  watchdog = pkgs.writeShellApplication {
    name = "tailnet-gateway-dns-watchdog";
    runtimeInputs = [ pkgs.coreutils pkgs.python3 pkgs.systemd ];
    text = ''
      set -eu
      state_file=${lib.escapeShellArg stateFile}
      now=$(date +%s)
      if ! python3 ${validator} tailnet --now "$now" --state "$state_file" >/dev/null 2>&1; then
        systemctl stop tailnet-gateway-dns.service
      fi
    '';
  };
in {
  options.dotfiles.tailnetGatewayDns = {
    names = mkOption {
      type = types.listOf (types.strMatching "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$");
      default = [ ];
      description = "Explicit private names mapped to the runtime svc:lab TailVIP.";
    };
    forwarders = mkOption {
      type = types.listOf (types.strMatching "^[0-9a-fA-F:.]+$");
      default = [ "1.1.1.1" "1.0.0.1" ];
      description = "Public recursive resolvers for records not synthesized locally.";
    };
    privateZone = mkOption {
      type = types.str;
      default = "lab.xavierchanth.xyz";
      readOnly = true;
      description = "Authoritative-negative service zone; unknown nested names never reach public resolvers.";
    };
    ttl = mkOption { type = types.ints.between 5 300; default = 30; };
    stateFile = mkOption { type = types.str; readOnly = true; default = stateFile; };
  };

  config = {
    assertions = [{ assertion = cfg.names != [ ]; message = "tailnet-gateway-dns requires explicit private names"; }];
    systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];
    systemd.services.tailnet-gateway-dns = {
      description = "Tailnet-only private gateway DNS";
      wantedBy = [ "multi-user.target" ];
      wants = [ "tailscaled.service" "tailscaled-autoconnect.service" "network-online.target" ];
      after = [ "tailscaled.service" "tailscaled-autoconnect.service" "network-online.target" "svc-lab.service" ];
      requires = [ "svc-lab.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${prepare}/bin/tailnet-gateway-dns-prepare";
        ExecStart = "${pkgs.coredns}/bin/coredns -conf ${runtimeDir}/Corefile";
        Restart = "on-failure";
        RestartSec = 10;
        User = "root";
        RuntimeDirectory = "tailnet-gateway-dns";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "tailnet-gateway-dns";
        StateDirectoryMode = "0700";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    systemd.services.tailnet-gateway-dns-watchdog = {
      description = "Stop tailnet gateway DNS when its svc:lab receipt expires";
      serviceConfig = { Type = "oneshot"; ExecStart = "${watchdog}/bin/tailnet-gateway-dns-watchdog"; };
    };
    systemd.timers.tailnet-gateway-dns-watchdog = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "30s"; OnUnitActiveSec = "30s"; Unit = "tailnet-gateway-dns-watchdog.service"; };
    };
    networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
    environment.systemPackages = [ prepare ];
    dotfiles.labUpdate.requiredUnits = [ "tailnet-gateway-dns.service" ];
  };
}
