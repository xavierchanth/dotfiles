{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.dotfiles.serviceGateway;
  routeNames = builtins.attrNames cfg.routes;
  upstreamUrl = route:
    let address = if route.upstream.address == "::1" then "[::1]" else route.upstream.address;
    in "http://${address}:${toString route.upstream.port}";
  upstreamUnits = lib.unique (lib.filter (unit: unit != null)
    (map (name: cfg.routes.${name}.upstreamUnit) routeNames));
  proxyTarget = route:
    lib.optionalString (route.allowedPaths != [ ]) "@dataPlane " + upstreamUrl route;
  allowedPathConfig = route: lib.optionalString (route.allowedPaths != [ ]) ''
    @dataPlane path ${lib.concatStringsSep " " route.allowedPaths}
  '';
  validHostname = hostname:
    builtins.match "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$" hostname != null
    && builtins.match ".*\\.\\..*" hostname == null;
  serviceTarget = "tcp://${cfg.bindAddress}:${toString cfg.httpsPort}";
  serviceConfigFile = builtins.toFile "lab-serve-config.json" (builtins.toJSON {
    version = "0.0.1";
    services."svc:lab" = {
      advertised = true;
      endpoints."tcp:443" = serviceTarget;
    };
  });
  serviceStateFile = "/var/lib/tailnet-gateway-dns/svc-lab-state.json";
  serviceDrainMarker = "/var/lib/tailnet-gateway-dns/svc-lab-drained";
  serviceLockFile = "/var/lib/tailnet-gateway-dns/operation.lock";
  caRootCertificate = "${config.services.caddy.dataDir}/.local/share/caddy/pki/authorities/local/root.crt";
  caRootPrivateKey = "${config.services.caddy.dataDir}/.local/share/caddy/pki/authorities/local/root.key";
  caFingerprintFile = "${config.services.caddy.dataDir}/.dotfiles-root-ca.sha256";
  caFingerprint = pkgs.writeShellApplication {
    name = "service-gateway-ca-fingerprint";
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    text = ''
      set -eu
      certificate=${lib.escapeShellArg caRootCertificate}
      test -s "$certificate"
      openssl x509 -in "$certificate" -outform DER | sha256sum | cut -d ' ' -f 1
    '';
  };
  caAnchor = pkgs.writeShellApplication {
    name = "service-gateway-ca-anchor";
    runtimeInputs = [ pkgs.coreutils caFingerprint ];
    text = ''
      set -eu
      certificate=${lib.escapeShellArg caRootCertificate}
      private_key=${lib.escapeShellArg caRootPrivateKey}
      fingerprint_file=${lib.escapeShellArg caFingerprintFile}

      for _attempt in $(seq 1 30); do
        if test -s "$certificate" && test -s "$private_key"; then
          break
        fi
        sleep 1
      done
      test -s "$certificate"
      test -s "$private_key"

      fingerprint=$(service-gateway-ca-fingerprint)
      if test -e "$fingerprint_file"; then
        anchored=$(tr -d '\n' < "$fingerprint_file")
        if test "$anchored" != "$fingerprint"; then
          echo "service gateway CA fingerprint changed unexpectedly" >&2
          echo "anchored: $anchored" >&2
          echo "current:  $fingerprint" >&2
          exit 1
        fi
      else
        printf '%s\n' "$fingerprint" | install -m 0600 /dev/stdin "$fingerprint_file"
      fi
    '';
  };
  caExport = pkgs.writeShellApplication {
    name = "service-gateway-ca-export";
    runtimeInputs = [ pkgs.coreutils caFingerprint ];
    text = ''
      set -eu
      if test "$#" -ne 1; then
        echo "usage: service-gateway-ca-export DESTINATION.pem" >&2
        exit 64
      fi

      certificate=${lib.escapeShellArg caRootCertificate}
      fingerprint_file=${lib.escapeShellArg caFingerprintFile}
      destination=$1
      test -s "$certificate"
      test -s "$fingerprint_file"
      fingerprint=$(service-gateway-ca-fingerprint)
      anchored=$(tr -d '\n' < "$fingerprint_file")
      test "$fingerprint" = "$anchored"

      if test -e "$destination" && ! cmp -s "$certificate" "$destination"; then
        echo "refusing to overwrite a different certificate at $destination" >&2
        exit 1
      fi
      install -m 0644 "$certificate" "$destination"
      printf '%s  %s\n' "$fingerprint" "$destination"
    '';
  };
  serviceLifecycle = pkgs.writeShellApplication {
    name = "tailscale-service-gateway";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.python3 pkgs.systemd pkgs.tailscale ];
    text = ''
      export SVC_LAB_CURL=${lib.escapeShellArg "${pkgs.curl}/bin/curl"}
      export SVC_LAB_SYSTEMCTL=${lib.escapeShellArg "${pkgs.systemd}/bin/systemctl"}
      export SVC_LAB_TAILSCALE=${lib.escapeShellArg "${pkgs.tailscale}/bin/tailscale"}
      exec ${pkgs.python3}/bin/python3 ${../../../../scripts/tailscale-service-gateway.py} "$@" \
        --config ${lib.escapeShellArg serviceConfigFile} \
        --receipt ${lib.escapeShellArg serviceStateFile} \
        --drain-marker ${lib.escapeShellArg serviceDrainMarker} \
        --lock-file ${lib.escapeShellArg serviceLockFile} \
        --target ${lib.escapeShellArg serviceTarget} \
        --bind-address ${lib.escapeShellArg cfg.bindAddress} \
        --port ${toString cfg.httpsPort} \
        --health-host lab.xavierchanth.xyz \
        --health-path /api/healthcheck \
        --ca-certificate ${lib.escapeShellArg caRootCertificate}
    '';
  };
in
{
  options.dotfiles.serviceGateway = {
    bindAddress = mkOption {
      type = types.strMatching "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$";
      default = "127.0.0.1";
      description = "Address where the private TLS gateway listens.";
    };
    httpsPort = mkOption {
      type = types.port;
      default = 8443;
      description = "TCP port where the private TLS gateway listens.";
    };
    tailscaleService = {
      name = mkOption { type = types.str; readOnly = true; default = "svc:lab"; };
      port = mkOption { type = types.port; readOnly = true; default = 443; };
      target = mkOption { type = types.str; readOnly = true; default = serviceTarget; };
      configFile = mkOption { type = types.path; readOnly = true; default = serviceConfigFile; };
      stateFile = mkOption { type = types.str; readOnly = true; default = serviceStateFile; };
      drainMarker = mkOption { type = types.str; readOnly = true; default = serviceDrainMarker; };
      lifecyclePackage = mkOption { type = types.package; readOnly = true; default = serviceLifecycle; };
    };
    redirects = mkOption {
      type = types.attrsOf (types.strMatching "^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?$");
      default = { };
      description = "Permanent HTTPS origin redirects keyed by canonical hostname.";
    };
    ca = {
      rootCertificate = mkOption {
        type = types.str;
        readOnly = true;
        default = caRootCertificate;
        description = "Public Caddy local-CA root certificate generated on the gateway host.";
      };
      fingerprintFile = mkOption {
        type = types.str;
        readOnly = true;
        default = caFingerprintFile;
        description = "Host-local anchor used to detect an unexpected Caddy CA rotation.";
      };
    };
    routes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          upstream = mkOption {
            type = types.submodule {
              options = {
                address = mkOption {
                  type = types.enum [ "127.0.0.1" "::1" ];
                  description = "Loopback address of the upstream service.";
                };
                port = mkOption {
                  type = types.port;
                  description = "Loopback port of the upstream service.";
                };
              };
            };
            description = "HTTP loopback endpoint for this stable service origin.";
          };
          healthPath = mkOption {
            type = types.strMatching "^/[^[:space:]]*$";
            description = "Unauthenticated HTTP path used for active upstream health checks.";
          };
          allowedPaths = mkOption {
            type = types.listOf (types.strMatching "^/[^[:space:]]*$");
            default = [ ];
            description = "Optional fail-closed path allowlist proxied without rewriting; an empty list proxies the whole origin.";
          };
          upstreamUnit = mkOption {
            type = types.nullOr (types.strMatching "^[A-Za-z0-9@_.:-]+\\.service$");
            default = null;
            description = "Optional systemd service that Caddy should start after and weakly depend on.";
          };
        };
      });
      default = { };
      description = "Stable tailnet-only HTTPS origins, keyed by canonical hostname.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.routes != { };
        message = "The service-gateway group requires at least one route";
      }
      {
        assertion = lib.all validHostname routeNames;
        message = "Service gateway route keys must be lowercase hostnames without empty labels";
      }
    ];

    services.caddy = {
      enable = true;
      openFirewall = false;
      globalConfig = ''
        auto_https disable_redirects
        default_bind ${cfg.bindAddress}
        https_port ${toString cfg.httpsPort}
        servers {
          protocols h1 h2
          strict_sni_host on
        }
      '';
      virtualHosts = (lib.mapAttrs (hostname: route: {
        hostName = hostname;
        listenAddresses = [ cfg.bindAddress ];
        extraConfig = ''
          tls internal
          ${allowedPathConfig route}
          ${lib.optionalString (route.allowedPaths != [ ]) "route {"}
          reverse_proxy ${proxyTarget route} {
            health_uri ${route.healthPath}
            health_interval 10s
            health_timeout 3s
            health_status 2xx
            flush_interval -1
          }
          ${lib.optionalString (route.allowedPaths != [ ]) "respond 404"}
          ${lib.optionalString (route.allowedPaths != [ ]) "}"}
        '';
      }) cfg.routes) // (lib.mapAttrs (hostname: target: {
        hostName = hostname;
        listenAddresses = [ cfg.bindAddress ];
        extraConfig = ''
          tls internal
          redir ${target}{uri} permanent
        '';
      }) cfg.redirects);
    };

    systemd.services.caddy = {
      wants = upstreamUnits;
      after = [ "tailscaled.service" ] ++ upstreamUnits;
      serviceConfig.ExecStartPost = "${caAnchor}/bin/service-gateway-ca-anchor";
    };

    systemd.services.svc-lab = {
      description = "Declaratively reconcile the svc:lab Tailscale Service host";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" "tailscaled-autoconnect.service" ];
      after = [ "network-online.target" "tailscaled.service" "tailscaled-autoconnect.service" "caddy.service" ];
      requires = [ "tailscaled.service" "caddy.service" ];
      partOf = [ "tailscaled.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "2min";
        Restart = "on-failure";
        RestartSec = "30s";
        ExecStart = "${serviceLifecycle}/bin/tailscale-service-gateway reconcile";
        ExecReload = "${serviceLifecycle}/bin/tailscale-service-gateway reconcile";
      };
    };

    systemd.services.svc-lab-reconcile = {
      description = "Refresh svc:lab live state and private DNS receipt";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" "caddy.service" ];
      requires = [ "tailscaled.service" "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "2min";
        ExecStart = "${serviceLifecycle}/bin/tailscale-service-gateway reconcile";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.timers.svc-lab-reconcile = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        RandomizedDelaySec = "30s";
        Unit = "svc-lab-reconcile.service";
      };
    };

    systemd.services.tailscaled.wants = [ "svc-lab.service" ];

    environment.systemPackages = [ caFingerprint caExport serviceLifecycle ];

    dotfiles.labUpdate.requiredUnits = [ "caddy.service" "svc-lab.service" ];
  };
}
