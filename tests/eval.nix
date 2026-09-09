{
  module,
  nixpkgs,
  pkgs,
  system,
}:

let
  makeSystem =
    setecConfig:
    nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        module
        {
          boot.isContainer = true;
          system.stateVersion = "26.05";
          services.setec = setecConfig;
        }
      ];
    };

  evaluates =
    setecConfig:
    (builtins.tryEval (makeSystem setecConfig).config.system.build.toplevel.drvPath).success;

  base = {
    enable = true;
    hostname = "secrets";
  };
in
assert evaluates (base // { encryption.backend = "insecure"; });
assert evaluates (
  base
  // {
    encryption = {
      backend = "aws-kms";
      kms.keyName = "arn:aws:kms:us-east-1:123456789012:key/example";
    };
    backup = {
      bucket = "setec-backups";
      region = "us-east-1";
      role = "arn:aws:iam::123456789012:role/setec-backup";
    };
  }
);
assert evaluates (base // { encryption.backend = "tpm"; });
assert !(evaluates (base // { }));
assert
  !(evaluates {
    enable = true;
    encryption.backend = "insecure";
  });
assert !(evaluates (base // { encryption.backend = "aws-kms"; }));
assert
  !(evaluates (
    base
    // {
      encryption = {
        backend = "tpm";
        kms.keyName = "unexpected";
      };
    }
  ));
assert
  !(evaluates (
    base
    // {
      encryption = {
        backend = "tpm";
        tpm.keyFile = "/srv/setec/tpm.key";
      };
    }
  ));
assert
  !(evaluates (
    base
    // {
      encryption.backend = "insecure";
      backup.bucket = "setec-backups";
    }
  ));
assert
  !(evaluates (
    base
    // {
      encryption.backend = "insecure";
      backup.region = "us-east-1";
    }
  ));
assert
  !(evaluates (
    base
    // {
      encryption.backend = "insecure";
      backup.role = "arn:aws:iam::123456789012:role/setec-backup";
    }
  ));
pkgs.runCommand "setec-module-evaluation-tests" { } ''
  touch "$out"
''
