# tests/mgmt-ca.nix
#
# mgmt-shaped check: a hermetic, single-node NixOS VM test proving the mechanism
# mgmt's whole TLS story rests on -- step-ca issues a cert over ACME and nginx
# serves it on an internal vhost, verifiable against the CA root. If step-ca,
# lego, or the nginx<->ACME wiring breaks, every *.mgmt.lan service silently
# falls back to an untrusted cert; this catches that in CI.
#
# It MIRRORS hosts/lan/mgmt/modules/step-ca.nix (same ACME provisioner shape, the
# same "lego trusts the generated root" wiring) rather than importing it: that
# module pins mgmt's real IP + domain set into /etc/hosts, which fights a single
# hermetic node. Here every name resolves to loopback and nothing touches the
# network or real DNS.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "mgmt-ca";

  nodes.machine =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.curl
        pkgs.openssl
      ];

      # No real DNS: the CA name and the vhost both resolve to this node, so ACME
      # HTTP-01 validation and the test's own curl hit local nginx.
      networking.hosts."127.0.0.1" = [
        "ca.test.lan"
        "web.test.lan"
      ];

      # Generate root + intermediate before step-ca starts (mirrors step-ca.nix).
      systemd.services.step-ca-init = {
        description = "Generate step-ca root and intermediate (test)";
        wantedBy = [ "multi-user.target" ];
        before = [ "step-ca.service" ];
        path = [ pkgs.step-cli ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          dir=/var/lib/private/step-ca
          if [ ! -f "$dir/certs/root_ca.crt" ]; then
            mkdir -p "$dir/certs" "$dir/secrets" "$dir/db"
            step certificate create "test.lan Root CA" \
              "$dir/certs/root_ca.crt" "$dir/secrets/root_ca_key" \
              --profile root-ca --no-password --insecure --not-after 87600h
            step certificate create "test.lan Intermediate CA" \
              "$dir/certs/intermediate_ca.crt" "$dir/secrets/intermediate_ca_key" \
              --profile intermediate-ca --no-password --insecure --not-after 87600h \
              --ca "$dir/certs/root_ca.crt" --ca-key "$dir/secrets/root_ca_key"
          fi
          mkdir -p /var/lib/test-public
          chmod 755 /var/lib/test-public
          install -m644 "$dir/certs/root_ca.crt" /var/lib/test-public/root_ca.crt
        '';
      };

      services.step-ca = {
        enable = true;
        address = "127.0.0.1";
        port = 8443;
        settings = {
          root = "/var/lib/step-ca/certs/root_ca.crt";
          crt = "/var/lib/step-ca/certs/intermediate_ca.crt";
          key = "/var/lib/step-ca/secrets/intermediate_ca_key";
          dnsNames = [
            "ca.test.lan"
            "localhost"
            "127.0.0.1"
          ];
          logger.format = "text";
          db = {
            type = "badgerv2";
            dataSource = "/var/lib/step-ca/db";
          };
          authority.provisioners = [
            {
              type = "ACME";
              name = "acme";
            }
          ];
        };
      };

      # Point ACME (lego) at the local step-ca and make lego trust its root.
      security.acme = {
        acceptTerms = true;
        defaults = {
          email = "admin@test.lan";
          server = "https://127.0.0.1:8443/acme/acme/directory";
          environmentFile = pkgs.writeText "lego-env" ''
            LEGO_CA_CERTIFICATES=/var/lib/test-public/root_ca.crt
          '';
        };
      };

      services.nginx = {
        enable = true;
        virtualHosts."web.test.lan" = {
          forceSSL = true;
          enableACME = true;
          locations."/".return = "200 'hermetic-ca-ok'";
        };
      };

      # Every ACME order needs the CA up first (mirrors step-ca.nix).
      systemd.services."acme-web.test.lan" = {
        after = [ "step-ca.service" ];
        wants = [ "step-ca.service" ];
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("step-ca-init.service")
    machine.wait_for_unit("step-ca.service")

    # step-ca issues the cert over ACME (lego). The oneshot completes on success.
    machine.wait_for_unit("acme-web.test.lan.service")
    machine.wait_for_unit("nginx.service")

    # nginx serves TLS with a cert that verifies against the step-ca root...
    machine.wait_until_succeeds(
        "curl -sS --cacert /var/lib/test-public/root_ca.crt https://web.test.lan | grep -q hermetic-ca-ok",
        timeout=180,
    )
    # ...and it's the step-ca intermediate that issued it, not nginx's snakeoil fallback.
    machine.succeed(
        "echo | openssl s_client -connect web.test.lan:443 -servername web.test.lan 2>/dev/null "
        "| openssl x509 -noout -issuer | grep -i Intermediate"
    )
  '';
}
