# important disclosure

Even though there is not much going on here, it has yet to be validated by someone with more experience than me for being secure. Given I have no idea what I'm doing, I'll wait until I have some audits before saying this is something reasonable to use. 

# setec-nix

Nix package and NixOS module for
[Setec](https://github.com/tailscale/setec), Tailscale's lightweight secrets
manager.

Setec runs its own embedded Tailscale node using `tsnet`. It stores an encrypted
secrets database locally and controls access using grants in your tailnet
policy. This repository packages the Setec command and provides a hardened
systemd service for NixOS.

## Package

Build the package with:

```console
nix build github:OWNER/setec-nix
```

Run the Setec CLI without installing it:

```console
nix run github:OWNER/setec-nix -- help
```

The flake exposes `packages.<system>.setec`, `packages.<system>.default`, and an
overlay as `overlays.default`. The classic `default.nix` entry point remains
available for `nix-build`.

## NixOS module

Add the flake as an input and import its module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    setec-nix.url = "github:OWNER/setec-nix";
  };

  outputs =
    { nixpkgs, setec-nix, ... }:
    {
      nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          setec-nix.nixosModules.default
          {
            services.setec = {
              enable = true;
              hostname = "secrets";
              authKeyFile = "/run/secrets/setec-auth-key";

              encryption.backend = "tpm";
            };
          }
        ];
      };
    };
}
```

Both `hostname` and `encryption.backend` must be explicitly configured. The
service keeps its state, encrypted database, audit log, and default TPM key in
`/var/lib/setec`. systemd manages this directory with mode `0700` and runs the
service under a dynamic user.

### Encryption backends

For a TPM 2.0 device:

```nix
services.setec = {
  encryption = {
    backend = "tpm";
    tpm = {
      keyFile = "/var/lib/setec/tpm.key";
      device = "/dev/tpmrm0";
    };
  };
};
```

TPM mode enables NixOS TPM support, grants the service access to the configured
device, and stores the sealed key below `/var/lib/setec`. The sealed key is tied
to that TPM; losing the TPM state may make the database unrecoverable.

For AWS KMS:

```nix
services.setec = {
  encryption = {
    backend = "aws-kms";
    kms.keyName = "arn:aws:kms:us-east-1:123456789012:key/example";
  };
  environmentFile = "/run/secrets/setec.env";
};
```

The environment file can provide AWS SDK credentials, for example:

```text
AWS_ACCESS_KEY_ID=example
AWS_SECRET_ACCESS_KEY=example
```

Do not create secret-bearing environment files with `builtins.toFile`,
`pkgs.writeText`, or another Nix expression: doing so places their contents in
the world-readable Nix store. Deploy them at runtime with a secrets manager such
as sops-nix or agenix.

For local testing only:

```nix
services.setec.encryption.backend = "insecure";
```

The `insecure` backend passes Setec's `--dev` flag and uses a static dummy
encryption key. It must never be used for production secrets.

### Tailnet enrollment

`authKeyFile` names a file containing a Tailscale auth key. The module loads it
through systemd's credential mechanism and supplies it to Setec as
`TS_AUTHKEY`. Setec normally needs this key only on its first start because its
tsnet enrollment is retained in `/var/lib/setec`.

The option is optional. Without it, a new instance prints an interactive login
URL to the journal:

```console
journalctl -u setec.service
```

Use `loginServer` when enrolling with Headscale or another compatible control
server. `environmentFile` may also provide advanced tsnet variables. If both
credential sources define `TS_AUTHKEY`, `authKeyFile` takes precedence.

### S3 backups

Setec can upload the encrypted database to S3 when it changes:

```nix
services.setec.backup = {
  bucket = "setec-backups";
  region = "us-east-1";
  role = "arn:aws:iam::123456789012:role/setec-backup";
};
```

`region` is required when `bucket` is configured. `role` is optional. AWS
credentials can come from the instance environment or `environmentFile`.

### Options

| Option | Default | Purpose |
| --- | --- | --- |
| `services.setec.enable` | `false` | Enable the Setec service. |
| `services.setec.package` | bundled package | Override the Setec package. |
| `services.setec.hostname` | required | Advertised tsnet hostname. |
| `services.setec.loginServer` | `null` | Custom Tailscale-compatible control URL. |
| `services.setec.authKeyFile` | `null` | Runtime file containing the initial auth key. |
| `services.setec.environmentFile` | `null` | Runtime environment file for AWS or tsnet settings. |
| `services.setec.encryption.backend` | required | `aws-kms`, `tpm`, or `insecure`. |
| `services.setec.encryption.kms.keyName` | `null` | AWS KMS key ARN. |
| `services.setec.encryption.tpm.keyFile` | `/var/lib/setec/tpm.key` | TPM-sealed key path. |
| `services.setec.encryption.tpm.device` | `/dev/tpmrm0` | TPM resource-manager device. |
| `services.setec.backup.bucket` | `null` | S3 backup bucket. |
| `services.setec.backup.region` | `null` | S3 bucket region. |
| `services.setec.backup.role` | `null` | Optional IAM role ARN. |

Setec listens on ports 80 and 443 inside its tsnet virtual network. The module
does not open ports in the host firewall.

## Development

Format and run all package, module-evaluation, and NixOS VM tests with:

```console
nix fmt
nix flake check
```

### AI Disclosure

The initial packaging, NixOS module, tests, and documentation in this project
were developed with AI assistance. The resulting changes were reviewed and
validated with reproducible Nix builds and automated tests.

## License

This project is available under the BSD 3-Clause License, matching upstream
Setec. See [LICENSE](LICENSE). Setec itself remains copyright Tailscale Inc and
its contributors and is distributed under its own BSD 3-Clause license.
