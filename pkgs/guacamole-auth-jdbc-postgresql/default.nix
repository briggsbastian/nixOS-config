# Apache Guacamole PostgreSQL JDBC auth extension.
#
# nixpkgs ships only guacamole-client (the WAR) + guacamole-server (guacd); the
# database auth extensions are a separate upstream download, so we repackage the
# official binary tarball. Pinned to match the guacamole-client version in
# nixpkgs (1.6.0).
#
# Exposes:
#   $out/extensions/guacamole-auth-jdbc-postgresql.jar  -> GUACAMOLE_HOME/extensions
#   $out/schema/{001-create-schema,002-create-admin-user}.sql  (loaded into PG once)
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "guacamole-auth-jdbc-postgresql";
  version = "1.6.0";

  src = fetchurl {
    url = "mirror://apache/guacamole/${finalAttrs.version}/binary/guacamole-auth-jdbc-${finalAttrs.version}.tar.gz";
    sha256 = "0rlk0fkvf8y7f5qw9yj9ymcph0wa63yispa7iblw09bxsv9mzg4p";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/extensions $out/schema
    # stable, unversioned name so consumers don't hardcode the version
    cp postgresql/guacamole-auth-jdbc-postgresql-${finalAttrs.version}.jar \
      $out/extensions/guacamole-auth-jdbc-postgresql.jar
    cp postgresql/schema/*.sql $out/schema/

    runHook postInstall
  '';

  meta = {
    description = "Apache Guacamole PostgreSQL JDBC authentication extension";
    homepage = "https://guacamole.apache.org/";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = lib.platforms.linux;
  };
})
