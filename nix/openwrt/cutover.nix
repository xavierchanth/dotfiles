{
  schemaVersion = 1;
  mutationAdapterReady = false;

  migration = {
    sourceCidr = "192.168.8.0/24";
    recoveryAddress = "192.168.8.1";
    targetCidr = "192.168.17.0/24";
  };

  target = {
    gateway = "192.168.17.1";
    pool = { first = "192.168.17.100"; last = "192.168.17.199"; };
    hosts = {
      charon = { address = "192.168.17.1"; role = "router"; };
      hades = { address = "192.168.17.2"; role = "dhcp-dns-tailnet-gateway"; reservationRef = "hades-lan"; };
      poseidon = { address = "192.168.17.3"; role = "workstation"; reservationRef = "poseidon-lan"; };
      zeus = { address = "192.168.17.4"; role = "workstation"; reservationRef = "zeus-lan"; };
      eris = { address = "192.168.17.5"; role = "server"; reservationRef = "eris-lan"; };
    };
  };

  policy = {
    ipv6 = "disabled-phase-1";
    oldLeaseWaitSeconds = 86400;
    transitionLeaseSeconds = 300;
    confirmWindowSeconds = 900;
    phase2 = {
      hadesFallbackDisableSeconds = 240;
      charonFallbackProbeSeconds = 300;
      requireProvenDhcpFence = true;
      ambiguousFallback = "fail-closed";
    };
  };

  reservationRefs = [ "hades-lan" "poseidon-lan" "zeus-lan" "eris-lan" ];
}
