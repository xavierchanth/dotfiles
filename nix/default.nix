{inputs}: let
  inherit (inputs) nixpkgs nix-darwin home-manager deploy-rs;
  lib = nixpkgs.lib;
  username = "chant";
  inventory = import ./inventory.nix;
  profiles = import ./profiles.nix;
  openwrtProfiles = import ./openwrt/profiles.nix;
  lab = import ./lab.nix;
  openwrtRender = import ./openwrt/render.nix { inherit lab; };
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
    inherit inputs username hostname inventory;
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
  codingHosts = credentialDeployNames;
  codingValidation = let
    home = name: (mkHome name).config;
    packageNames = name: map lib.getName (home name).home.packages;
    has = package: name: builtins.elem package (packageNames name);
    hasCompiler = name: lib.any (p: lib.hasPrefix "gcc" p || lib.hasPrefix "clang" p) (packageNames name);
    hasPkgConfig = name: lib.any (p: lib.hasPrefix "pkg-config" p || lib.hasPrefix "pkgconf" p) (packageNames name);
    activation = name: (home name).home.activation;
    miseText = name: (activation name).installMiseTools.data;
    stowText = name: (activation name).stowDotfiles.data;
  in assert lib.all (name: has "mise" name && hasCompiler name && hasPkgConfig name) codingHosts;
     assert has "mise" "nyx" && !(hasCompiler "nyx");
     assert !(has "mise" "hades") && !(hasCompiler "hades") && !(activation "hades" ? installMiseTools);
     assert lib.all (name: (activation name).installMiseTools.after == [ "stowDotfiles" ]) codingHosts;
     assert lib.all (name: (mkNixos name).config.programs.nix-ld.enable && (mkNixos name).config.systemd.services."home-manager-${username}".serviceConfig.TimeoutStartSec == "1h") codingHosts;
     assert lib.all (name: lib.hasInfix "SSL_CERT_FILE=" (miseText name) && lib.hasInfix "MISE_GITHUB_TOKEN=" (miseText name) && lib.hasInfix ''"$PATH"'' (miseText name) && lib.hasInfix "timeout 5s" (miseText name)) codingHosts;
     assert lib.all (name: !(lib.hasInfix ''cleanup_stow_links mise '' (stowText name))) codingHosts;
     assert lib.hasInfix ''cleanup_stow_links mise '' (stowText "hades"); true;
  inventoryValidation = let
    charon = inventory.charon;
    deployed = lab.deploymentOrder;
  in assert charon.kind == "openwrt" && charon.profile == "openwrt-router" && !(charon ? system);
     assert openwrtProfiles ? ${charon.profile};
     assert openwrtProfiles.${charon.profile}.managesPrivateDns && openwrtProfiles.${charon.profile}.attendedOnly;
     assert lib.all (name: inventory.${name}.lab.deploy or false) deployed; true;
  darwinServerValidation = let
    eris = (mkDarwin "eris").config;
  in assert eris.services.openssh.enable == true;
     assert eris.services.tailscale.enable == true && eris.services.tailscale.overrideLocalDns == false;
     assert eris.system.defaults.loginwindow.autoLoginUser == null;
     assert !(builtins.elem "tailscale-app" eris.homebrew.casks);
     true;
  checked = builtins.deepSeq validKinds (assert resolverTests; assert profileTests; assert codingValidation; assert inventoryValidation; assert darwinServerValidation; true);
  systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
  deployNodes = attrs deployNames (name: let
    host = inventory.${name};
    route = host.deployment or {};
  in {
    hostname = route.targetAddress or name;
    sshUser = username;
    groups = [ "lab" ];
    remoteBuild = true;
    interactiveSudo = true;
    autoRollback = true;
    magicRollback = host.kind == "nixos"; # deploy-rs' inotify rollback is not portable to Darwin.
    sshOpts = [ "-o" "ControlMaster=no" "-o" "ControlPath=none" "-o" "ServerAliveInterval=5" "-o" "ServerAliveCountMax=3" "-o" "ConnectTimeout=10" ] ++ lib.optionals (route ? proxyJump) [ "-o" "ProxyJump=${route.proxyJump}" ];
    activationTimeout = if builtins.elem name codingHosts then 3900 else 600;
    confirmTimeout = 60;
    profiles.system = {
      user = "root";
      path = if host.kind == "nixos"
        then deploy-rs.lib.${host.system}.activate.nixos (mkNixos name)
        else deploy-rs.lib.${host.system}.activate.darwin (mkDarwin name);
    };
  });
  deployValidation = assert builtins.attrNames deployNodes == lib.sort builtins.lessThan [ "eris" "hades" "poseidon" "zeus" ];
    assert credentialDeployNames == [ "poseidon" "zeus" ];
    assert lib.all (name: inventory.${name}.kind == "nixos") credentialDeployNames;
    assert builtins.length deployNames == 4 && builtins.length (lib.unique deployNames) == 4;
    assert lib.all (n: deployNodes.${n}.groups == [ "lab" ]) deployNames;
    assert lib.all (n: n == "eris" || deployNodes.${n}.hostname == n) deployNames;
    assert deployNodes.eris.hostname == inventory.eris.lab.address;
    assert deployNodes.eris.sshOpts == [ "-o" "ControlMaster=no" "-o" "ControlPath=none" "-o" "ServerAliveInterval=5" "-o" "ServerAliveCountMax=3" "-o" "ConnectTimeout=10" "-o" "ProxyJump=hades" ];
    assert lib.all (n: deployNodes.${n}.activationTimeout == 3900) codingHosts; true;
  deployConfig = { nodes = deployNodes; };
  deployInventory = builtins.concatStringsSep "" (map (name:
    "${name}\t${inventory.${name}.kind}\t${inventory.${name}.system}\t${if deployCredentialsFor name == [] then "-" else lib.concatStringsSep "," (deployCredentialsFor name)}\n") deployNames);
  flakeSource = inputs.self.outPath;
  allPackages = lib.genAttrs systems (system: let pkgs = pkgsFor system; in rec {
    openwrt-charon-uci = pkgs.writeText "charon-uci" openwrtRender;
    openwrt-apply-charon = pkgs.writeShellApplication { name = "openwrt-apply-charon"; runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.openssh pkgs.nix ]; text = ''
      export CHARON_RENDER="${openwrt-charon-uci}"
      ${builtins.readFile ../scripts/openwrt-apply-charon}
    ''; };
    deploy-inventory = pkgs.writeText "deploy-inventory.tsv" deployInventory;
    deploy-supervisor = pkgs.writeScript "deploy-supervisor" ''
      #!${pkgs.python3}/bin/python3
      ${builtins.readFile ../scripts/deploy-supervisor.py}
    '';
    lab-update = pkgs.writeShellApplication { name = "lab-update"; runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.gawk pkgs.perl pkgs.openssh pkgs.jujutsu pkgs.gnutar pkgs.nix ]; excludeShellChecks = [ "SC2016" ]; text = builtins.readFile ../bin/shared/lab-update; };
    deploy-cli = pkgs.writeShellApplication { name = "deploy"; runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.openssh pkgs.nix pkgs.jujutsu pkgs.gh ]; text = ''
      export DEPLOY_FLAKE=${lib.escapeShellArg (toString flakeSource)}
      export DEPLOY_INVENTORY=${lib.escapeShellArg (toString deploy-inventory)}
      export DEPLOY_RS=${lib.escapeShellArg "${deploy-rs.packages.${system}.default}/bin/deploy"}
      export DEPLOY_SUPERVISOR=${lib.escapeShellArg "${deploy-supervisor}"}
      export LAB_UPDATE=${lib.escapeShellArg "${lab-update}/bin/lab-update"}
      ${builtins.readFile ../scripts/deploy}
    ''; };
  });
in builtins.seq checked (builtins.seq deployValidation {
  packages = allPackages;
  apps = lib.genAttrs systems (system: {
    deploy = { type = "app"; program = "${allPackages.${system}.deploy-cli}/bin/deploy"; };
    openwrt-apply-charon = { type = "app"; program = "${allPackages.${system}.openwrt-apply-charon}/bin/openwrt-apply-charon"; };
  });
  deploy = deployConfig;
  darwinConfigurations = attrs (builtins.attrNames darwinHosts) mkDarwin;
  nixosConfigurations = attrs (builtins.attrNames nixosHosts) mkNixos;
  homeConfigurations = builtins.listToAttrs (map (hostname: { name = "${username}@${hostname}"; value = mkHome hostname; }) (builtins.attrNames supportedHomeHosts));
  checks = lib.recursiveUpdate
    (lib.genAttrs systems (system: let pkgs = pkgsFor system; in {
      deploy-invariants = pkgs.runCommand "deploy-invariant-tests" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.python3 deploy-rs.packages.${system}.default ]; DEPLOY_SCRIPT = ../scripts/deploy; CONSUMER_SCRIPT = ../scripts/consume-deploy-credential; DEPLOY_RS_REAL = "${deploy-rs.packages.${system}.default}/bin/deploy"; } ''
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
