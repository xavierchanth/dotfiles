{
  name = "lab-dns-dhcp";
  platforms = [ "nixos" ];
  nixos = [ ./system.nix ];
  requires = [ "lab-update-contract" ];
  before = [ ];
  after = [ ];
  conflicts = [ ];
  deployCredentials = [ ];
}
