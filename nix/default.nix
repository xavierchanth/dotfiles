{inputs}: let
  inherit (inputs) nixpkgs nix-darwin home-manager deploy-rs;
  lib = nixpkgs.lib;
  jioPackageFor = pkgs: inputs.jio.packages.${pkgs.stdenv.hostPlatform.system}.jio;
  username = "chant";
  deployment = import ./deployment.nix;
  inventory = import ./inventory.nix;
  profiles = import ./profiles.nix;
  openwrtProfiles = import ./openwrt/profiles.nix;
  lab = import ./lab.nix;
  openwrtRender = import ./openwrt/render.nix { inherit lab; };
  labNetworkCutover = import ./openwrt/cutover.nix;
  registry = import ./registry.nix;
  resolve = import ./lib/groups.nix { inherit lib; };
  profileKinds = {
    darwin-workstation = { kind = "darwin"; legacy = "workstation"; };
    darwin-server = { kind = "darwin"; legacy = "server"; };
    linux-workstation = { kind = "nixos"; legacy = "workstation"; };
    linux-server = { kind = "nixos"; legacy = "server"; };
  };
  declarationFor = kind: hostname: let
    path = if kind == "darwin" then ./hosts/darwin/${hostname} else if kind == "nixos" then ./hosts/nixos/${hostname}
      else throw "no host declaration dispatch for `${kind}`";
    value = import path;
    valid = builtins.isAttrs value
      && value ? groups && builtins.isList value.groups && lib.all builtins.isString value.groups
      && value ? modules && builtins.isList value.modules && lib.all (module: builtins.isPath module) value.modules;
  in if valid then value else throw "host declaration `${hostname}` must be an attribute set with string-list `groups` and path-list `modules`";
  contextFor = hostname: let
    host = inventory.${hostname};
    mapping = profileKinds.${host.profile} or (throw "unknown profile `${host.profile}` for ${hostname}");
    _compatible = if mapping.kind == host.kind then true else throw "profile `${host.profile}` does not support ${host.kind}";
    profileGroups = profiles.${host.profile} or (throw "unknown profile `${host.profile}` for ${hostname}");
    declaration = declarationFor host.kind hostname;
    groupNames = profileGroups ++ (host.groups or []) ++ declaration.groups;
  in builtins.seq _compatible {
    inherit inputs username hostname inventory jioPackageFor deployment groupNames;
    hostProfile = host // { profileName = host.profile; profile = mapping.legacy; };
    resolvedGroups = resolve { inherit registry; kind = host.kind; groups = groupNames; };
  };
  validKinds = map (hostname: let host = inventory.${hostname}; in
    if !(host ? kind) then throw "inventory host `${hostname}` is missing kind"
    else if builtins.elem host.kind [ "darwin" "nixos" "openwrt" ] then true
    else throw "unknown inventory kind `${host.kind}`") (builtins.attrNames inventory);
  hostsOfKind = kind: lib.filterAttrs (_: host: host.kind == kind) inventory;
  darwinHosts = hostsOfKind "darwin";
  nixosHosts = hostsOfKind "nixos";
  hostModules = kind: hostname:
    (declarationFor kind hostname).modules ++ (inventory.${hostname}.extraModules or []);
  pkgsFor = system: import nixpkgs { inherit system; config.allowUnfree = true; };
  hmModule = context: { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = context;
    home-manager.users.${username}.imports = [ ./home/${username} ] ++ context.resolvedGroups.homeModules;
  };
  mkDarwin = hostname: let context = contextFor hostname; in nix-darwin.lib.darwinSystem {
    system = inventory.${hostname}.system; specialArgs = context;
    modules = hostModules "darwin" hostname ++ context.resolvedGroups.systemModules ++ [ home-manager.darwinModules.home-manager (hmModule context) ];
  };
  mkNixos = hostname: let context = contextFor hostname; in lib.nixosSystem {
    system = inventory.${hostname}.system; specialArgs = context;
    modules = hostModules "nixos" hostname ++ context.resolvedGroups.systemModules ++ [ home-manager.nixosModules.home-manager (hmModule context) ];
  };
  mkHome = hostname: let context = contextFor hostname; in home-manager.lib.homeManagerConfiguration {
    pkgs = pkgsFor inventory.${hostname}.system; extraSpecialArgs = context;
    modules = [ ./home/${username} ] ++ context.resolvedGroups.homeModules;
  };
  attrs = names: f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) names);
  supportedHomeHosts = darwinHosts // nixosHosts;
  resolverTests = import ./tests/groups.nix { inherit lib; };
  profileTests = lib.all (name: let mapping = profileKinds.${name}; in
    (resolve { inherit registry; kind = mapping.kind; groups = profiles.${name}; }) ? homeModules)
    (builtins.attrNames profileKinds);
  linuxWorkstation = resolve {
    inherit registry;
    kind = "nixos";
    groups = profiles.linux-workstation;
  };
  linuxWorkstationHome = home-manager.lib.homeManagerConfiguration {
    pkgs = pkgsFor "x86_64-linux";
    modules = linuxWorkstation.homeModules ++ [{
      home.username = "foundation-test";
      home.homeDirectory = "/home/foundation-test";
      home.stateVersion = "26.05";
    }];
  };
  deployNames = lab.deploymentOrder;
  deployCredentialsFor = name: (contextFor name).resolvedGroups.deployCredentials;
  credentialDeployNames = lib.filter (name: deployCredentialsFor name != []) deployNames;
  credentialNixosHosts = lib.filter (name: inventory.${name}.kind == "nixos") credentialDeployNames;
  codingValidation = let
    home = name: (mkHome name).config;
    packageNames = name: map lib.getName (home name).home.packages;
    has = package: name: builtins.elem package (packageNames name);
    hasCompiler = name: lib.any (p: lib.hasPrefix "gcc" p || lib.hasPrefix "clang" p) (packageNames name);
    hasPkgConfig = name: lib.any (p: lib.hasPrefix "pkg-config" p || lib.hasPrefix "pkgconf" p) (packageNames name);
    activation = name: (home name).home.activation;
    miseText = name: (activation name).installMiseTools.data;
    stowText = name: (activation name).stowDotfiles.data;
  in assert lib.all (name: has "mise" name && hasCompiler name && hasPkgConfig name) credentialNixosHosts;
     assert has "mise" "nyx" && !(hasCompiler "nyx");
     assert has "mise" "eris" && !(hasCompiler "eris");
     assert has "mise" "hades" && hasCompiler "hades" && activation "hades" ? installMiseTools;
     assert lib.all (name: (activation name).installMiseTools.after == [ "stowDotfiles" ]) credentialDeployNames;
     assert lib.all (name: (mkNixos name).config.programs.nix-ld.enable && (mkNixos name).config.systemd.services."home-manager-${username}".serviceConfig.TimeoutStartSec == "1h") credentialNixosHosts;
     assert lib.all (name: lib.hasInfix "export MISE_NODE_COMPILE=false" (miseText name)) credentialNixosHosts;
     assert lib.all (name: !(lib.hasInfix "export MISE_NODE_COMPILE=false" (miseText name))) [ "nyx" "eris" ];
     assert lib.all (name: lib.hasInfix "SSL_CERT_FILE=" (miseText name) && lib.hasInfix "MISE_GITHUB_TOKEN=" (miseText name) && lib.hasInfix ''"$PATH"'' (miseText name) && lib.hasInfix "timeout 5s" (miseText name)) credentialDeployNames;
     assert lib.all (name: !(lib.hasInfix ''cleanup_stow_links mise '' (stowText name))) credentialDeployNames;
     assert !(lib.hasInfix ''cleanup_stow_links mise '' (stowText "hades")); true;
  inventoryValidation = let
    charon = inventory.charon;
    deployed = lab.deploymentOrder;
    dedicatedLinux = lib.filter (name: inventory.${name}.kind == "nixos" && (inventory.${name}.deployment.useDedicatedUser or false)) deployed;
    cageHosts = lib.filter (name: builtins.elem "cage-desktop" (contextFor name).groupNames) (builtins.attrNames nixosHosts);
  in assert charon.kind == "openwrt" && charon.profile == "openwrt-router" && !(charon ? system);
     assert openwrtProfiles ? ${charon.profile};
     assert openwrtProfiles.${charon.profile}.managesPrivateDns && openwrtProfiles.${charon.profile}.attendedOnly;
     assert lib.all (name: inventory.${name}.lab.deploy or false) deployed;
     assert dedicatedLinux == [] || deployment.authorizedKeys != [];
     assert cageHosts == [ "poseidon" "zeus" ];
     true;
  darwinServerValidation = let
    eris = (mkDarwin "eris").config;
  in assert eris.services.openssh.enable == true;
     assert eris.services.tailscale.enable == true && eris.services.tailscale.overrideLocalDns == false;
     assert eris.system.defaults.loginwindow.autoLoginUser == null;
     assert !(builtins.elem "tailscale-app" eris.homebrew.casks);
     true;
  darwinMaintenanceValidation = let
    expectedSchedule = map (Hour: {
      inherit Hour;
      Minute = 0;
      Day = null;
      Month = null;
      Weekday = null;
    }) [ 4 5 6 ];
    validates = name: let
      config = (mkDarwin name).config;
      service = config.launchd.daemons.dotfiles-nix-store-maintenance.serviceConfig;
      activation = config.system.activationScripts.postActivation.text;
    in assert service.StartCalendarInterval == expectedSchedule;
       assert service.ProcessType == "Background";
       assert service.LowPriorityIO;
       assert service.LowPriorityBackgroundIO;
       assert builtins.length service.ProgramArguments == 2;
       assert lib.hasPrefix "/nix/store/" (builtins.head service.ProgramArguments);
       assert builtins.elem "run" service.ProgramArguments;
       assert lib.hasInfix "nix-store-maintenance request" activation;
       assert !(lib.hasInfix "brew" (builtins.concatStringsSep " " service.ProgramArguments));
       true;
  in assert lib.all validates [ "nyx" "eris" ]; true;
  jioValidation = import ./tests/jio.nix { inherit lib mkHome home-manager jioPackageFor pkgsFor; };
  homepageValidation = import ./tests/homepage.nix { inherit lib mkNixos contextFor; };
  cliproxyapiValidation = import ./tests/cliproxyapi.nix { inherit lib mkNixos contextFor; };
  cpaManagerPlusValidation = import ./tests/cpa-manager-plus.nix { inherit lib mkNixos contextFor; };
  serviceGatewayValidation = import ./tests/service-gateway.nix { inherit lib mkNixos contextFor; };
  tailnetGatewayDnsValidation = import ./tests/tailnet-gateway-dns.nix { inherit lib mkNixos contextFor; };
  labDnsDhcpValidation = import ./tests/lab-dns-dhcp.nix { inherit lib mkNixos contextFor; };
  tailscaleRouterValidation = import ./tests/tailscale-router.nix { inherit lib mkNixos; };
  erisHeadlessValidation = import ./tests/eris-headless.nix { inherit lib mkDarwin; };
  podmanHostValidation = let
    hades = (mkNixos "hades").config;
  in assert hades.virtualisation.oci-containers.backend == "podman";
     assert hades.virtualisation.podman.enable;
     assert hades.virtualisation.podman.defaultNetwork.settings.dns_enabled;
     assert !hades.virtualisation.docker.enable;
     assert !hades.virtualisation.podman.dockerCompat;
     assert !hades.virtualisation.podman.dockerSocket.enable;
     assert builtins.elem "podman-host" (contextFor "hades").groupNames;
     assert !(builtins.elem "docker-host" (contextFor "hades").groupNames);
     true;
  executorValidation = let
    hades = (mkNixos "hades").config;
    executor = hades.dotfiles.executor;
    container = hades.virtualisation.oci-containers.containers.executor;
  in assert executor.image == "ghcr.io/usefulsoftwareco/executor-selfhost:v1.6.8@sha256:527e014ce0641e9d569314561fba2a37b872ffd5074471b9bc48b66611ecb090";
     assert executor.bind == "127.0.0.1:4788";
     assert executor.webBaseUrl == "https://executor.lab.xavierchanth.xyz";
     assert executor.dataDirectory == "/var/lib/executor/data";
     assert executor.healthUrl == "http://127.0.0.1:4788/api/health";
     assert !executor.allowLocalNetwork && !executor.allowStdioMcp;
     assert container.serviceName == "executor";
     assert container.image == executor.image;
     assert container.ports == [ "127.0.0.1:4788:4788" ];
     assert container.volumes == [ "/var/lib/executor/data:/data" ];
     assert container.podman.sdnotify == "healthy";
     assert builtins.elem "executor.service" hades.dotfiles.labUpdate.requiredUnits;
     assert !executor.offsiteBackup.enable;
     assert !(builtins.elem "executor-backup-preflight.service" hades.systemd.services.executor.requires);
     assert !(hades.systemd.services ? executor-restore-check);
     assert !(hades.systemd.services ? executor-offsite-backup);
     assert hades.systemd.timers.executor-backup.timerConfig.Unit == "executor-backup.service";
     true;
  checked = builtins.deepSeq validKinds (assert !(registry ? plane); assert resolverTests; assert profileTests; assert codingValidation; assert inventoryValidation; assert darwinServerValidation; assert darwinMaintenanceValidation; assert homepageValidation; assert cliproxyapiValidation; assert cpaManagerPlusValidation; assert serviceGatewayValidation; assert tailnetGatewayDnsValidation; assert labDnsDhcpValidation; assert tailscaleRouterValidation; assert erisHeadlessValidation; assert podmanHostValidation; assert executorValidation; true);
  systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
  deployNodes = attrs deployNames (name: let
    host = inventory.${name};
    route = host.deployment or {};
    dedicated = host.kind == "nixos" && (route.useDedicatedUser or false);
  in {
    hostname = route.targetAddress or name;
    sshUser = if dedicated then deployment.user else username;
    groups = [ "lab" ];
    remoteBuild = true;
    interactiveSudo = true;
    autoRollback = true;
    magicRollback = host.kind == "nixos"; # deploy-rs' inotify rollback is not portable to Darwin.
    sshOpts = [ "-o" "ControlMaster=no" "-o" "ControlPath=none" "-o" "ServerAliveInterval=5" "-o" "ServerAliveCountMax=3" "-o" "ConnectTimeout=10" ]
      ++ lib.optionals dedicated [ "-o" "IdentitiesOnly=yes" "-o" "IdentityFile=~/${deployment.identityFile}" ]
      ++ lib.optionals (route ? proxyJump) [ "-o" "ProxyJump=${route.proxyJump}" ];
    activationTimeout = if builtins.elem name credentialDeployNames then 3900 else 600;
    confirmTimeout = 60;
    profiles.system = {
      user = "root";
      path = if host.kind == "nixos"
        then deploy-rs.lib.${host.system}.activate.nixos (mkNixos name)
        else deploy-rs.lib.${host.system}.activate.darwin (mkDarwin name);
    };
  });
  deployValidation = assert builtins.attrNames deployNodes == lib.sort builtins.lessThan [ "eris" "hades" "poseidon" "zeus" ];
    assert credentialDeployNames == deployNames;
    assert builtins.length deployNames == 4 && builtins.length (lib.unique deployNames) == 4;
    assert lib.all (n: deployNodes.${n}.groups == [ "lab" ]) deployNames;
    assert lib.all (n: n == "eris" || deployNodes.${n}.hostname == n) deployNames;
    assert deployNodes.eris.hostname == inventory.eris.lab.address;
    assert lib.all (n: let
      dedicated = inventory.${n}.kind == "nixos" && (inventory.${n}.deployment.useDedicatedUser or false);
    in deployNodes.${n}.sshUser == (if dedicated then deployment.user else username)) deployNames;
    assert deployNodes.eris.sshUser == username;
    assert deployNodes.eris.sshOpts == [ "-o" "ControlMaster=no" "-o" "ControlPath=none" "-o" "ServerAliveInterval=5" "-o" "ServerAliveCountMax=3" "-o" "ConnectTimeout=10" "-o" "ProxyJump=hades" ];
    assert lib.all (n: deployNodes.${n}.activationTimeout == 3900) credentialDeployNames; true;
  deployConfig = { nodes = deployNodes; };
  deployInventory = builtins.concatStringsSep "" (map (name:
    let route = inventory.${name}.deployment or {}; in
    let dedicated = inventory.${name}.kind == "nixos" && (route.useDedicatedUser or false); in
    "${name}\t${inventory.${name}.kind}\t${inventory.${name}.system}\t${if deployCredentialsFor name == [] then "-" else lib.concatStringsSep "," (deployCredentialsFor name)}\t${route.targetAddress or name}\t${route.proxyJump or "-"}\t${if dedicated then deployment.user else username}\t${if dedicated then deployment.identityFile else "-"}\n") deployNames);
  flakeSource = inputs.self.outPath;
  allPackages = lib.genAttrs systems (system: let pkgs = pkgsFor system; in rec {
    openwrt-charon-uci = pkgs.writeText "charon-uci" openwrtRender;
    lab-network-cutover-manifest = pkgs.writeText "lab-network-cutover.json" (builtins.toJSON labNetworkCutover);
    lab-network-cutover = pkgs.writeShellApplication {
      name = "lab-network-cutover";
      runtimeInputs = [ pkgs.openssh pkgs.python3 ];
      text = ''
        export LAB_CUTOVER_MANIFEST=${lib.escapeShellArg (toString lab-network-cutover-manifest)}
        exec ${pkgs.python3}/bin/python3 ${../scripts/lab-network-cutover.py} "$@"
      '';
    };
    openwrt-apply-charon = pkgs.writeShellApplication { name = "openwrt-apply-charon"; runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.openssh pkgs.nix ]; text = ''
      export CHARON_RENDER="${openwrt-charon-uci}"
      ${builtins.readFile ../scripts/openwrt-apply-charon}
    ''; };
    deploy-inventory = pkgs.writeText "deploy-inventory.tsv" deployInventory;
    deploy-supervisor = pkgs.writeScript "deploy-supervisor" ''
      #!${pkgs.python3}/bin/python3
      ${builtins.readFile ../scripts/deploy-supervisor.py}
    '';
    lab-update = let
      route = inventory.hades.deployment;
      dedicated = route.useDedicatedUser or false;
    in pkgs.writeShellApplication { name = "lab-update"; runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.gawk pkgs.perl pkgs.openssh pkgs.jujutsu pkgs.gnutar pkgs.nix ]; excludeShellChecks = [ "SC2016" ]; text = ''
      export LAB_UPDATE_TARGET=${lib.escapeShellArg (route.targetAddress or "hades")}
      export LAB_UPDATE_SSH_USER=${lib.escapeShellArg (if dedicated then deployment.user else username)}
      export LAB_UPDATE_IDENTITY=${lib.escapeShellArg (if dedicated then deployment.identityFile else "-")}
      export LAB_UPDATE_PROXY_JUMP=${lib.escapeShellArg (route.proxyJump or "-")}
      ${builtins.readFile ../bin/shared/lab-update}
    ''; };
    deploy-cli = pkgs.writeShellApplication { name = "deploy"; runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.openssh pkgs.nix pkgs.jujutsu pkgs.gh ]; text = ''
      export DEPLOY_FLAKE=${lib.escapeShellArg (toString flakeSource)}
      export DEPLOY_INVENTORY=${lib.escapeShellArg (toString deploy-inventory)}
      export DEPLOY_RS=${lib.escapeShellArg "${deploy-rs.packages.${system}.default}/bin/deploy"}
      export DEPLOY_SUPERVISOR=${lib.escapeShellArg "${deploy-supervisor}"}
      export DEPLOY_PREFLIGHT=${lib.escapeShellArg (toString ../scripts/deploy-preflight)}
      export LAB_UPDATE=${lib.escapeShellArg "${lab-update}/bin/lab-update"}
      ${builtins.readFile ../scripts/deploy}
    ''; };
  });
in builtins.seq checked (builtins.seq deployValidation {
  packages = allPackages;
  apps = lib.genAttrs systems (system: {
    deploy = { type = "app"; program = "${allPackages.${system}.deploy-cli}/bin/deploy"; meta.description = "Deploy a configured lab host with deploy-rs"; };
    lab-network-cutover = { type = "app"; program = "${allPackages.${system}.lab-network-cutover}/bin/lab-network-cutover"; meta.description = "Prepare and operate the guarded two-phase lab network cutover"; };
    openwrt-apply-charon = { type = "app"; program = "${allPackages.${system}.openwrt-apply-charon}/bin/openwrt-apply-charon"; meta.description = "Apply the managed Charon router DNS configuration"; };
  });
  deploy = deployConfig;
  darwinConfigurations = attrs (builtins.attrNames darwinHosts) mkDarwin;
  nixosConfigurations = attrs (builtins.attrNames nixosHosts) mkNixos;
  homeConfigurations = builtins.listToAttrs (map (hostname: { name = "${username}@${hostname}"; value = mkHome hostname; }) (builtins.attrNames supportedHomeHosts));
  checks = lib.recursiveUpdate
    (lib.genAttrs systems (system: let pkgs = pkgsFor system; in {
      handoff-reference = import ./handoff-reference-package.nix { inherit pkgs; };
      jio-config = assert jioValidation; pkgs.runCommand "jio-config-tests" {
        nativeBuildInputs = [ (jioPackageFor pkgs) ];
      } ''
        mkdir -p config data state runtime
        cp ${(mkHome "nyx").config.xdg.configFile."jio/config.toml".source} config/config.toml
        cp ${(mkHome "nyx").config.xdg.configFile."jio/projects.toml".source} config/projects.toml
        jio --config-dir "$PWD/config" --data-dir "$PWD/data" --state-dir "$PWD/state" --runtime-dir "$PWD/runtime" doctor > "$out"
      '';
      jio-release = pkgs.runCommand "jio-release-tests" {
        nativeBuildInputs = [ pkgs.python3 ];
        JIO_RELEASE_HELPER = ../scripts/jio-release;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../tests/jio-release.py}
        touch "$out"
      '';
      jio-fetch-auth = pkgs.runCommand "jio-fetch-auth-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
        JIO_AUTH_HELPER = ../scripts/nix-with-github;
        TEST_BASH = "${pkgs.bash}/bin/bash";
      } ''
        python3 ${../tests/nix-with-github.py}
        touch "$out"
      '';

      service-gateway = let
        cliProxyVhost = (mkNixos "hades").config.services.caddy.virtualHosts."cliproxyapi.lab.xavierchanth.xyz";
        caddyfile = pkgs.writeText "service-gateway-cliproxyapi-Caddyfile" ''
          {
            admin off
          }
          cliproxyapi.lab.xavierchanth.xyz:443 {
            ${cliProxyVhost.extraConfig}
          }
        '';
      in assert serviceGatewayValidation; pkgs.runCommand "service-gateway-tests" {
        nativeBuildInputs = [ pkgs.caddy pkgs.jq pkgs.python3 ];
        SVC_LAB_CONTROLLER = ../scripts/tailscale-service-gateway.py;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        caddy adapt --config ${caddyfile} --adapter caddyfile > adapted.json
        handlers=$(jq -c '[
          .apps.http.servers[].routes[]
          | ..
          | objects
          | .handler?
          | select(. == "reverse_proxy" or . == "static_response")
        ]' adapted.json)
        test "$handlers" = '["reverse_proxy","static_response"]'
        paths=$(jq -c '[
          .apps.http.servers[].routes[]
          | ..
          | objects
          | select(.handle?[0]?.handler? == "reverse_proxy")
          | .match[0].path[]
        ]' adapted.json)
        test "$paths" = '["/v1/models","/v1/responses","/v1/responses/compact"]'
        python3 ${../tests/tailscale-service-gateway.py}
        echo 'service gateway eval and adapted-route assertions passed' > $out
      '';

      tailscale-router = assert tailscaleRouterValidation; pkgs.runCommand "tailscale-router-tests" { } ''
        echo 'Tailscale router eval assertions passed' > $out
      '';

      tailnet-gateway-dns = assert tailnetGatewayDnsValidation; pkgs.runCommand "tailnet-gateway-dns-tests" { } ''
        echo 'tailnet gateway DNS eval assertions passed' > $out
      '';

      lab-dns-dhcp = assert labDnsDhcpValidation; pkgs.runCommand "lab-dns-dhcp-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.python3 ];
      } ''
        export TEST_ROOT=${flakeSource}
        ${pkgs.python3}/bin/python3 ${../tests/lab-runtime-state.py}
        ${pkgs.python3}/bin/python3 ${../tests/lab-dhcp-watchdog.py}
        echo 'Lab DNS and DHCP eval assertions passed' > $out
      '';

      eris-headless = assert erisHeadlessValidation; pkgs.runCommand "eris-headless-tests" { } ''
        echo 'Eris headless eval assertions passed' > $out
      '';

      homepage = assert homepageValidation; pkgs.runCommand "homepage-tests" { } ''
        echo 'homepage eval assertions passed' > $out
      '';

      podman-host = assert podmanHostValidation && executorValidation; pkgs.runCommand "podman-host-tests" { } ''
        echo 'Podman host and Executor eval assertions passed' > $out
      '';

      cliproxyapi = let
        proxy = (mkNixos "hades").config.dotfiles.cliproxyapi;
      in assert cliproxyapiValidation; pkgs.runCommand "cliproxyapi-tests" {
        nativeBuildInputs = [ pkgs.openssl pkgs.gnugrep ];
      } ''
        management_key="cpa_management_$(openssl rand -hex ${toString proxy.managementKeyBytes})"
        printf '%s\n' "$management_key" | grep -Eq '^cpa_management_[0-9a-f]{${toString (proxy.managementKeyBytes * 2)}}$'
        test "$(printf '%s' "$management_key" | wc -c)" -le 72
        echo 'CLIProxyAPI eval assertions passed' > $out
      '';

      cpa-manager-plus = assert cpaManagerPlusValidation; pkgs.runCommand "cpa-manager-plus-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils ];
      } ''
        mkdir -p state
        ln -s "$PWD/state" data
        bash ${../scripts/cpa-manager-plus-verify-writable-topology.sh} "$PWD/data" "$PWD/state"
        test -z "$(find state -maxdepth 1 -name '.cpamp-write-probe.*' -print -quit)"
        echo 'CPA Manager Plus eval assertions passed' > $out
      '';

      cage-mcp-protocol = pkgs.runCommand "cage-mcp-protocol-tests" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.mcp p.pillow ])) ];
        TEST_ROOT = flakeSource;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../tests/cage-mcp.py}
        touch "$out"
      '';
      cage-session-scripts = pkgs.runCommand "cage-session-script-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.python3 pkgs.shellcheck ];
        TEST_ROOT = flakeSource;
        TEST_BASH = "${pkgs.bash}/bin/bash";
      } ''
        shellcheck ${../scripts/cage-session.sh} ${../scripts/cage-session-app.sh}
        python3 ${../tests/cage-session.py}
        touch "$out"
      '';
      deploy-invariants = pkgs.runCommand "deploy-invariant-tests" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.python3 deploy-rs.packages.${system}.default ]; DEPLOY_SCRIPT = ../scripts/deploy; CONSUMER_SCRIPT = ../scripts/consume-deploy-credential; DEPLOY_RS_REAL = "${deploy-rs.packages.${system}.default}/bin/deploy"; } ''
        export DEPLOY_PREFLIGHT=${../scripts/deploy-preflight}
        TEST_BASH=${pkgs.bash}/bin/bash ${pkgs.bash}/bin/bash ${../tests/deploy-preflight.sh}
        DEPLOY_SUPERVISOR=${allPackages.${system}.deploy-supervisor} TEST_BASH=${pkgs.bash}/bin/bash ${pkgs.bash}/bin/bash ${../tests/deploy.sh}
        ${pkgs.python3}/bin/python3 ${../tests/deploy-supervisor.py} ${allPackages.${system}.deploy-supervisor}
        # Exercise every wrapper mode against the pinned parser. The invalid local
        # flake fails before any SSH can be attempted.
        for mode in dry-activate test boot; do
          if ${allPackages.${system}.deploy-supervisor} "$DEPLOY_RS_REAL" "--$mode" --skip-checks --remote-build /nonexistent-deploy-parser-test#node >"parser-$mode.log" 2>&1; then exit 1; fi
          ! grep -Eqi 'unexpected argument|unknown (argument|option)|unrecognized option' "parser-$mode.log"
        done
        touch $out
      '';
      managed-stow = pkgs.runCommand "managed-stow-tests" {
        nativeBuildInputs = [ pkgs.git pkgs.python3 pkgs.stow ];
        TEST_ROOT = flakeSource;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../tests/managed-stow.py}
        touch "$out"
      '';
      codex-config = pkgs.runCommand "codex-config-tests" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.tomlkit ])) ];
        TEST_ROOT = flakeSource;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../tests/codex-config.py}
        touch "$out"
      '';
    } // lib.optionalAttrs (builtins.elem system [ "aarch64-darwin" "x86_64-linux" ]) {
      resolver-evaluation = assert resolverTests; pkgs.runCommand "resolver-evaluation" {} ''
        echo 'resolver eval assertions passed' > $out
      '';
      openwrt-safety = pkgs.runCommand "openwrt-safety-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.gawk pkgs.shellcheck ];
        TEST_ROOT = flakeSource;
        CHARON_RENDER = allPackages.${system}.openwrt-charon-uci;
        CHARON_APP = "${allPackages.${system}.openwrt-apply-charon}/bin/openwrt-apply-charon";
        SKIP_FLAKE_EVAL = 1;
      } ''
        bash ${../tests/openwrt.sh}
        touch $out
      '';
      lab-network-cutover = pkgs.runCommand "lab-network-cutover-tests" {
        nativeBuildInputs = [ pkgs.nix pkgs.python3 ];
        TEST_ROOT = flakeSource;
        LAB_CUTOVER_BIN = "${allPackages.${system}.lab-network-cutover}/bin/lab-network-cutover";
        LAB_CUTOVER_MANIFEST_TEST = allPackages.${system}.lab-network-cutover-manifest;
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../tests/lab-network-cutover.py}
        touch $out
      '';
      lab-update-safety = let
        manifest = name: (mkNixos name).config.environment.etc."lab-update/required-units".text;
      in pkgs.runCommand "lab-update-safety-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ];
        TEST_ROOT = flakeSource;
        LAB_UPDATE_BIN = "${allPackages.${system}.lab-update}/bin/lab-update";
        HADES_MANIFEST = manifest "hades";
        POSEIDON_MANIFEST = manifest "poseidon";
      } ''
        bash ${../tests/lab-update-test.sh}
        touch $out
      '';
    } // lib.optionalAttrs (lib.hasSuffix "-darwin" system) {
      nix-store-maintenance = pkgs.runCommand "nix-store-maintenance-tests" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.shellcheck ];
        NIX_STORE_MAINTENANCE_SCRIPT = ../scripts/nix-store-maintenance.sh;
        DOTFILES_CLEAN_SCRIPT = ../scripts/clean.sh;
      } ''
        shellcheck ${../scripts/nix-store-maintenance.sh} ${../tests/nix-store-maintenance.sh}
        bash ${../tests/nix-store-maintenance.sh}
        touch $out
      '';
    } // lib.optionalAttrs (pkgs ? uci && lib.hasSuffix "-linux" system) {
      openwrt-libuci = pkgs.runCommand "openwrt-libuci-semantic" {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.uci ];
        CHARON_RENDER = allPackages.${system}.openwrt-charon-uci;
      } ''
        bash ${../tests/openwrt-libuci.sh}
        touch $out
      '';
    }))
    { x86_64-linux.linux-workstation-home = linuxWorkstationHome.activationPackage; };
})
