{ ... }:
{
  dotfiles.serviceGateway.routes."lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 3000;
    };
    healthPath = "/api/healthcheck";
    upstreamUnit = "homepage.service";
  };

  dotfiles.serviceGateway.routes."executor.lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 4788;
    };
    healthPath = "/api/health";
    upstreamUnit = "executor.service";
  };

  dotfiles.serviceGateway.routes."plane.lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 8080;
    };
    healthPath = "/";
    upstreamUnit = "plane.service";
  };
}
