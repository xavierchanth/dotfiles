{ config, pkgs, ... }:
let
  release = "v1.3.1";
  hostname = "plane.lab.xavierchanth.xyz";
  upstream = "http://127.0.0.1:8080";
  healthPath = "/";
  uploadLimitBytes = "10485760";
  stateDirectory = "/var/lib/plane";
  backupDirectory = "/var/backups/plane";
  environmentFile = "${stateDirectory}/plane.env";
  composePath = "${stateDirectory}/docker-compose.yml";
  composeSource = pkgs.fetchurl {
    url = "https://github.com/makeplane/plane/releases/download/${release}/docker-compose.yml";
    hash = "sha256-1M76tqKBoHSVcT/6xL3uwgZHa/+HGNMPnqZwdsekFfA=";
  };
  composeFile = pkgs.runCommand "plane-${release}-docker-compose.yml" {
    nativeBuildInputs = [ pkgs.gnugrep pkgs.gnupatch ];
  } ''
    cp ${composeSource} "$out"
    chmod u+w "$out"
    patch "$out" < ${./compose.patch}
    if grep -E '^[[:space:]]+image:' "$out" | grep -v '@sha256:'; then
      echo "Plane compose file contains an image without an immutable digest" >&2
      exit 1
    fi
    test "$(grep -Ec '^[[:space:]]+image:' "$out")" -eq 13
    for service in web space admin live api worker beat-worker migrator plane-db plane-redis plane-mq plane-minio proxy; do
      grep -Eq "^  $service:" "$out"
    done
    test "$(grep -c 'host_ip: 127.0.0.1' "$out")" -eq 1
    test "$(grep -Ec '^[[:space:]]+published:' "$out")" -eq 1
  '';
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name plane --env-file ${environmentFile} --file ${composePath}";
  prepare = pkgs.writeShellApplication {
    name = "plane-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    text = ''
      set -eu
      install -d -m 0700 -o root -g root ${stateDirectory}
      install -d -m 0700 -o root -g root ${backupDirectory}
      install -m 0444 -o root -g root ${composeFile} ${composePath}

      if [ ! -e ${environmentFile} ]; then
        temporary="$(mktemp ${stateDirectory}/.plane.env.XXXXXX)"
        trap 'rm -f "$temporary"' EXIT
        postgres_password="$(openssl rand -hex 32)"
        rabbitmq_password="$(openssl rand -hex 32)"
        minio_access_key="$(openssl rand -hex 16)"
        minio_secret_key="$(openssl rand -hex 32)"
        secret_key="$(openssl rand -hex 32)"
        live_secret_key="$(openssl rand -hex 32)"
        printf '%s\n' \
          'COMPOSE_PROJECT_NAME=plane' \
          'APP_DOMAIN=${hostname}' \
          'APP_RELEASE=${release}' \
          'LISTEN_HTTP_PORT=8080' \
          'WEB_URL=https://${hostname}' \
          'CORS_ALLOWED_ORIGINS=https://${hostname}' \
          'DEBUG=0' \
          'API_BASE_URL=http://api:8000' \
          'PGHOST=plane-db' \
          'PGDATABASE=plane' \
          'POSTGRES_USER=plane' \
          "POSTGRES_PASSWORD=$postgres_password" \
          'POSTGRES_DB=plane' \
          'POSTGRES_PORT=5432' \
          'PGDATA=/var/lib/postgresql/data' \
          "DATABASE_URL=postgresql://plane:$postgres_password@plane-db/plane" \
          'REDIS_HOST=plane-redis' \
          'REDIS_PORT=6379' \
          'REDIS_URL=redis://plane-redis:6379/' \
          'RABBITMQ_HOST=plane-mq' \
          'RABBITMQ_PORT=5672' \
          'RABBITMQ_USER=plane' \
          "RABBITMQ_PASSWORD=$rabbitmq_password" \
          'RABBITMQ_VHOST=plane' \
          "AMQP_URL=amqp://plane:$rabbitmq_password@plane-mq:5672/plane" \
          "SECRET_KEY=$secret_key" \
          'USE_MINIO=1' \
          "AWS_ACCESS_KEY_ID=$minio_access_key" \
          "AWS_SECRET_ACCESS_KEY=$minio_secret_key" \
          'AWS_S3_ENDPOINT_URL=http://plane-minio:9000' \
          'AWS_S3_BUCKET_NAME=uploads' \
          'FILE_SIZE_LIMIT=${uploadLimitBytes}' \
          'MINIO_ENDPOINT_SSL=0' \
          'API_KEY_RATE_LIMIT=60/minute' \
          "LIVE_SERVER_SECRET_KEY=$live_secret_key" \
          'SITE_ADDRESS=:80' \
          > "$temporary"
        install -m 0600 -o root -g root "$temporary" ${environmentFile}
        rm -f "$temporary"
        trap - EXIT
      fi

      test -s ${environmentFile}
      chmod 0600 ${environmentFile}
    '';
  };
  backup = pkgs.writeShellApplication {
    name = "plane-backup";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.gzip pkgs.gnutar ];
    text = ''
      set -eu
      umask 077
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      temporary="${backupDirectory}/.$stamp.tmp"
      destination="${backupDirectory}/$stamp"
      trap 'rm -rf "$temporary"' EXIT
      install -d -m 0700 "$temporary"

      ${compose} exec -T plane-db pg_dump --username plane --dbname plane \
        | gzip -9 > "$temporary/postgres.sql.gz"
      tar -C /var/lib/docker/volumes/plane_uploads/_data -czf "$temporary/uploads.tar.gz" .
      install -m 0600 ${environmentFile} "$temporary/plane.env"
      install -m 0644 ${composePath} "$temporary/docker-compose.yml"
      ${compose} images > "$temporary/images.txt"
      printf '%s\n' '${release}' > "$temporary/release.txt"
      gzip -t "$temporary/postgres.sql.gz"
      tar -tzf "$temporary/uploads.tar.gz" >/dev/null
      (
        cd "$temporary"
        sha256sum postgres.sql.gz uploads.tar.gz plane.env docker-compose.yml images.txt release.txt > SHA256SUMS
      )
      mv "$temporary" "$destination"
      trap - EXIT

      find ${backupDirectory} -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +14 -exec rm -rf -- {} +
    '';
  };
in
{
  assertions = [{
    assertion = config.virtualisation.docker.enable;
    message = "Plane requires the Hades Docker host";
  }];

  dotfiles.labUpdate.requiredUnits = [ "plane.service" ];

  systemd.services.plane = {
    description = "Plane human work ledger";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wants = [ "network-online.target" ];
    environment.COMPOSE_PROJECT_NAME = "plane";
    path = [ pkgs.curl pkgs.docker pkgs.docker-compose ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
      UMask = "0077";
      TimeoutStartSec = "15min";
      TimeoutStopSec = "5min";
      ExecStartPre = "${prepare}/bin/plane-prepare";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose --project-name plane --env-file ${environmentFile} --file ${composePath} up --detach --remove-orphans";
      ExecStartPost = pkgs.writeShellScript "plane-wait-healthy" ''
        set -eu
        for attempt in $(${pkgs.coreutils}/bin/seq 1 120); do
          status="$(${pkgs.curl}/bin/curl --silent --show-error --max-time 5 --output /dev/null --write-out '%{http_code}' --header 'Host: ${hostname}' ${upstream}${healthPath} || true)"
          if [ "$status" = 200 ]; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 5
        done
        ${compose} ps >&2
        exit 1
      '';
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose --project-name plane --env-file ${environmentFile} --file ${composePath} down";
    };
  };

  systemd.services.plane-backup = {
    description = "Back up Plane database, uploads, configuration, and release manifest";
    after = [ "plane.service" ];
    requires = [ "plane.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      ExecStart = "${backup}/bin/plane-backup";
    };
  };

  systemd.timers.plane-backup = {
    description = "Daily Plane backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:20:00";
      Persistent = true;
      RandomizedDelaySec = "20min";
      Unit = "plane-backup.service";
    };
  };
}
