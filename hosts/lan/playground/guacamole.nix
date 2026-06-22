# hosts/lan/playground/guacamole.nix
#
# Declarative Apache Guacamole gateway - replaces the old imperative per-user setup
# (Tomcat 9 + guacd under the removed secvm user) that died when this box was
# renamed playground and stripped to headless.
#
#   browser --:8080/guacamole--> Tomcat 9 (guacamole-client WAR)
#                                  |- guacd (guacamole-server, localhost:4822)
#                                  `- PostgreSQL auth backend (connections/users
#                                     managed in the web UI, not a Nix file)
#
# The JDBC auth extension isn't in nixpkgs, so it's repackaged in
# ../../../pkgs/guacamole-auth-jdbc-postgresql. GUACAMOLE_HOME is assembled at
# /var/lib/guacamole (extension jar + PG driver via tmpfiles symlinks; the
# properties file is rendered by sops so the DB password never hits the
# world-readable store / public repo).
#
# Initial web login is guacadmin / guacadmin (from 002-create-admin-user.sql) -
# change it on first login. The sops guacamole_db_password is the Postgres role
# password (DB connection), a different thing.
{ config, pkgs, lib, ... }:

let
  jdbcPg = pkgs.callPackage ../../../pkgs/guacamole-auth-jdbc-postgresql { };
  guacHome = "/var/lib/guacamole";
  # DB name must equal the role name for postgresql `ensureDBOwnership`.
  dbName = "guacamole";
  dbUser = "guacamole";
in
{
  # guacd proxy daemon (localhost:4822).
  services.guacamole-server.enable = true;

  # Tomcat webapp on :8080. Leave `settings` empty so the module doesn't write
  # guacamole.properties into the store (it would leak the DB password);
  # GUACAMOLE_HOME below provides it instead.
  services.guacamole-client = {
    enable = true;
    settings = lib.mkForce { };
  };

  # Point Tomcat at our assembled GUACAMOLE_HOME and don't start the webapp until
  # the schema/role exist.
  systemd.services.tomcat = {
    environment.GUACAMOLE_HOME = guacHome;
    after = [ "guacamole-db-init.service" ];
    requires = [ "guacamole-db-init.service" ];
  };

  # Assemble GUACAMOLE_HOME declaratively: the extension jar + JDBC driver are
  # store symlinks; the secret-bearing properties file is symlinked to the
  # sops-rendered copy (owned by tomcat, see the template below).
  systemd.tmpfiles.rules = [
    "d ${guacHome}            0750 tomcat tomcat -"
    "d ${guacHome}/extensions 0750 tomcat tomcat -"
    "d ${guacHome}/lib        0750 tomcat tomcat -"
    "L+ ${guacHome}/extensions/guacamole-auth-jdbc-postgresql.jar - - - - ${jdbcPg}/extensions/guacamole-auth-jdbc-postgresql.jar"
    "L+ ${guacHome}/lib/postgresql-jdbc.jar - - - - ${pkgs.postgresql_jdbc}/share/java/postgresql-jdbc.jar"
    "L+ ${guacHome}/guacamole.properties - - - - ${config.sops.templates."guacamole.properties".path}"
  ];

  # guacamole.properties, rendered with the DB password pulled from sops at
  # activation. Tomcat reads it through the GUACAMOLE_HOME symlink above.
  sops.templates."guacamole.properties" = {
    owner = "tomcat";
    content = ''
      guacd-hostname: localhost
      guacd-port: 4822
      postgresql-hostname: 127.0.0.1
      postgresql-port: 5432
      postgresql-database: ${dbName}
      postgresql-username: ${dbUser}
      postgresql-password: ${config.sops.placeholder.guacamole_db_password}
    '';
  };
  sops.secrets.guacamole_db_password.sopsFile = ../../../secrets/playground.yaml;

  # --- PostgreSQL ------------------------------------------------------------
  services.postgresql = {
    enable = true;
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
    # Guacamole connects over TCP as `${dbUser}` with a password (the tomcat user
    # isn't the PG role, so peer auth can't apply). Matched first via mkBefore.
    authentication = lib.mkBefore ''
      host ${dbName} ${dbUser} 127.0.0.1/32 scram-sha-256
      host ${dbName} ${dbUser} ::1/128      scram-sha-256
    '';
  };

  # One-shot: set the role password from sops + load Guacamole's schema once
  # (idempotent - guarded on the guacamole_user table). Runs as the postgres
  # superuser after PG is up, before Tomcat.
  systemd.services.guacamole-db-init = {
    description = "Initialize the Guacamole PostgreSQL schema + role password";
    # postgresql-setup.service runs ensureDatabases/ensureUsers (the role + DB must
    # exist before we ALTER it / load the schema), so order after it, not just
    # postgresql.service, or we race role creation.
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.postgresql.package ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
      LoadCredential = "dbpw:${config.sops.secrets.guacamole_db_password.path}";
    };
    script = ''
      set -euo pipefail
      pw=$(cat "$CREDENTIALS_DIRECTORY/dbpw")
      # set/refresh the role password (scram hash) so the JDBC connection works
      psql -tAc "ALTER ROLE ${dbUser} WITH LOGIN PASSWORD '$pw';"
      # load the schema once, then hand ownership of the objects to ${dbUser}
      if [ "$(psql -d ${dbName} -tAc "SELECT to_regclass('public.guacamole_user');")" != "guacamole_user" ]; then
        psql -d ${dbName} -v ON_ERROR_STOP=1 -f ${jdbcPg}/schema/001-create-schema.sql
        psql -d ${dbName} -v ON_ERROR_STOP=1 -f ${jdbcPg}/schema/002-create-admin-user.sql
        psql -d ${dbName} -c "GRANT ALL ON ALL TABLES    IN SCHEMA public TO ${dbUser};"
        psql -d ${dbName} -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${dbUser};"
      fi
    '';
  };
}
