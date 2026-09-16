{ ... }:
{
  dotfiles.serviceGateway.routes."executor.lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 4788;
    };
    healthPath = "/api/health";
    upstreamUnit = "executor.service";
  };
}
