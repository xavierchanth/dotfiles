{ ... }: {
  dotfiles.labDnsDhcp = {
    enable = false;
    dhcpFirewallEnable = false;
    records = {
      "charon.lab.xavierchanth.xyz" = "192.168.17.1";
      "hades.lab.xavierchanth.xyz" = "192.168.17.2";
      "poseidon.lab.xavierchanth.xyz" = "192.168.17.3";
      "zeus.lab.xavierchanth.xyz" = "192.168.17.4";
      "eris.lab.xavierchanth.xyz" = "192.168.17.5";
    };
    reservations = {
      hades.address = "192.168.17.2";
      poseidon.address = "192.168.17.3";
      zeus.address = "192.168.17.4";
      eris.address = "192.168.17.5";
    };
  };
}
