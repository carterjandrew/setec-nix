{ module, pkgs }:

let
  fakeSetec = pkgs.writeShellApplication {
    name = "setec";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      printf '%s\n' "$@" > /var/lib/setec/arguments
      printf '%s' "''${TS_AUTHKEY-}" > /var/lib/setec/auth-key
      exec sleep infinity
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "setec-module";

  nodes.machine = {
    imports = [ module ];

    environment.etc."setec-test-auth-key" = {
      text = "supersecretvalue\n";
      mode = "0400";
    };

    services.setec = {
      enable = true;
      package = fakeSetec;
      hostname = "secrets";
      authKeyFile = "/etc/setec-test-auth-key";
      encryption.backend = "insecure";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("setec.service")
    machine.succeed("grep -Fx server /var/lib/setec/arguments")
    machine.succeed("grep -Fx -- --state-dir=/var/lib/setec /var/lib/setec/arguments")
    machine.succeed("grep -Fx -- --hostname=secrets /var/lib/setec/arguments")
    machine.succeed("grep -Fx -- --dev /var/lib/setec/arguments")
    machine.succeed("test \"$(cat /var/lib/setec/auth-key)\" = supersecretvalue")
    machine.succeed("test \"$(stat -Lc %a /var/lib/setec)\" = 700")
    machine.succeed("test \"$(systemctl show setec.service -P DynamicUser)\" = yes")
    machine.succeed("! systemctl cat setec.service | grep -F supersecretvalue")
  '';
}
