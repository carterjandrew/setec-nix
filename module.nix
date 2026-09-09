{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.setec;
  stateDir = "/var/lib/setec";
  hostname = if cfg.hostname == null then "" else cfg.hostname;
  backend = if cfg.encryption.backend == null then "" else cfg.encryption.backend;

  serverArgs = [
    "server"
    "--state-dir=${stateDir}"
    "--hostname=${hostname}"
  ]
  ++ lib.optionals (cfg.loginServer != null) [ "--login-server=${cfg.loginServer}" ]
  ++ lib.optionals (backend == "aws-kms") [
    "--kms-key-name=${if cfg.encryption.kms.keyName == null then "" else cfg.encryption.kms.keyName}"
  ]
  ++ lib.optionals (backend == "tpm") [
    "--tpm-key-file=${cfg.encryption.tpm.keyFile}"
    "--tpm-device=${cfg.encryption.tpm.device}"
  ]
  ++ lib.optionals (backend == "insecure") [ "--dev" ]
  ++ lib.optionals (cfg.backup.bucket != null) [
    "--backup-bucket=${cfg.backup.bucket}"
    "--backup-bucket-region=${if cfg.backup.region == null then "" else cfg.backup.region}"
  ]
  ++ lib.optionals (cfg.backup.role != null) [ "--backup-role=${cfg.backup.role}" ];
in
{
  options.services.setec = {
    enable = lib.mkEnableOption "Setec secrets manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./setec.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./setec.nix { }";
      description = "The Setec package to use.";
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "secrets";
      description = "Hostname advertised by the embedded tsnet node.";
    };

    loginServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://headscale.example.com";
      description = "Optional Tailscale-compatible control server URL.";
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/setec-ts-auth-key";
      description = ''
        File containing the Tailscale auth key used for initial tsnet enrollment.
        The file is loaded with systemd credentials and is not copied into the
        Nix store when specified as a runtime path.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/setec.env";
      description = ''
        systemd environment file for AWS credentials or advanced tsnet
        settings. Do not use a Nix store path for secrets. When both sources
        set TS_AUTHKEY, authKeyFile takes precedence.
      '';
    };

    encryption = {
      backend = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "aws-kms"
            "tpm"
            "insecure"
          ]
        );
        default = null;
        example = "tpm";
        description = ''
          Encryption backend. The insecure backend uses Setec's development
          key and must never be used for production secrets.
        '';
      };

      kms.keyName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "arn:aws:kms:us-east-1:123456789012:key/example";
        description = "AWS KMS key ARN used to encrypt the Setec database.";
      };

      tpm = {
        keyFile = lib.mkOption {
          type = lib.types.str;
          default = "${stateDir}/tpm.key";
          description = ''
            Path where Setec stores the TPM-sealed database key. The path must
            be below /var/lib/setec so it remains writable by the sandboxed
            service.
          '';
        };

        device = lib.mkOption {
          type = lib.types.str;
          default = "/dev/tpmrm0";
          description = "TPM 2.0 device used to seal and unseal the database key.";
        };
      };
    };

    backup = {
      bucket = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "S3 bucket to receive encrypted database backups.";
      };

      region = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "us-east-1";
        description = "AWS region containing the backup bucket.";
      };

      role = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "arn:aws:iam::123456789012:role/setec-backup";
        description = "Optional IAM role ARN to assume when writing backups.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hostname != null && cfg.hostname != "";
        message = "services.setec.hostname must be set to a non-empty tsnet hostname";
      }
      {
        assertion = cfg.encryption.backend != null;
        message = "services.setec.encryption.backend must be explicitly set";
      }
      {
        assertion = backend != "aws-kms" || cfg.encryption.kms.keyName != null;
        message = "services.setec.encryption.kms.keyName is required for the aws-kms backend";
      }
      {
        assertion = backend == "aws-kms" || cfg.encryption.kms.keyName == null;
        message = "services.setec.encryption.kms.keyName may only be set for the aws-kms backend";
      }
      {
        assertion = backend != "tpm" || lib.hasPrefix "${stateDir}/" cfg.encryption.tpm.keyFile;
        message = "services.setec.encryption.tpm.keyFile must be below ${stateDir}";
      }
      {
        assertion = cfg.backup.bucket == null || cfg.backup.region != null;
        message = "services.setec.backup.region is required when backup.bucket is set";
      }
      {
        assertion = cfg.backup.bucket != null || cfg.backup.region == null;
        message = "services.setec.backup.region requires backup.bucket";
      }
      {
        assertion = cfg.backup.bucket != null || cfg.backup.role == null;
        message = "services.setec.backup.role requires backup.bucket";
      }
    ];

    security.tpm2.enable = lib.mkIf (backend == "tpm") true;

    systemd.services.setec = {
      description = "Setec secrets manager";
      documentation = [ "https://github.com/tailscale/setec/blob/main/docs/server.md" ];
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ] ++ lib.optional (backend == "tpm") "tpm2-udev-trigger.service";
      after = [ "network-online.target" ] ++ lib.optional (backend == "tpm") "tpm2-udev-trigger.service";

      script = ''
        ${lib.optionalString (cfg.authKeyFile != null) ''
          export TS_AUTHKEY="$(<"$CREDENTIALS_DIRECTORY/auth-key")"
        ''}
        exec ${lib.getExe cfg.package} ${lib.escapeShellArgs serverArgs}
      '';

      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "setec";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 10;

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        LoadCredential = lib.mkIf (cfg.authKeyFile != null) [ "auth-key:${cfg.authKeyFile}" ];
        SupplementaryGroups = lib.optionals (backend == "tpm" && config.security.tpm2.tssGroup != null) [
          config.security.tpm2.tssGroup
        ];

        DevicePolicy = "closed";
        DeviceAllow = lib.optionals (backend == "tpm") [ "${cfg.encryption.tpm.device} rw" ];
        PrivateDevices = backend != "tpm";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateMounts = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
      };
    };
  };
}
