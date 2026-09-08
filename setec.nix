{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "setec";
  version = "0-unstable-2026-08-24";

  src = ./setec;

  vendorHash = "sha256-OWW4+k/+tpAn5N4w0/5peEpGwbIHVyXp2m857JVKuFs=";

  subPackages = [ "cmd/setec" ];

  meta = {
    description = "Lightweight secrets manager for Tailscale networks";
    homepage = "https://github.com/tailscale/setec";
    license = lib.licenses.bsd3;
    mainProgram = "setec";
    platforms = lib.platforms.unix;
  };
}
