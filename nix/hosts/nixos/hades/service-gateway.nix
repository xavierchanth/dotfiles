{ ... }:
{
  dotfiles.serviceGateway.bindAddress = "127.0.0.1";
  dotfiles.serviceGateway.httpsPort = 8443;
  dotfiles.serviceGateway.redirects."xavierchanth.xyz" = "https://lab.xavierchanth.xyz";

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

  dotfiles.serviceGateway.routes."cliproxyapi.lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 8317;
    };
    healthPath = "/healthz";
    allowedPaths = [
      "/v1/models"
      "/v1/responses"
      "/v1/responses/compact"
    ];
    upstreamUnit = "cliproxyapi.service";
  };

  dotfiles.serviceGateway.routes."cpamp.lab.xavierchanth.xyz" = {
    upstream = {
      address = "127.0.0.1";
      port = 18317;
    };
    healthPath = "/health";
    upstreamUnit = "cpa-manager-plus.service";
  };
}
