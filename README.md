# ca-certificates-dod-unclass

A [melange](https://github.com/chainguard-dev/melange) package that adds DoD Unclassified CA certificates to the Wolfi system trust store, built into container images with [apko](https://github.com/chainguard-dev/apko).

## Overview

Many DoD services present TLS certificates signed by the DoD PKI rather than a commercial CA. Standard container base images don't include DoD root and intermediate CAs, so TLS connections to these services fail with `unable to get local issuer certificate`.

This project packages the DoD v5.14 certificate bundle as an apk and merges it into the system trust store at build time, so that any TLS client (curl, OpenSSL, Go, Python, etc.) trusts DoD-signed endpoints out of the box.

## Project Structure

```
.
├── Makefile                                  # build, test, clean targets
├── melange.yaml                              # melange package definition
├── wolfi-ca-certificates-dod-unclass.yaml    # apko image config (with DoD certs)
├── wolfi-base.yaml                           # apko image config (baseline, no DoD certs)
├── certs/
│   └── Certificates_PKCS7_v5_14_DoD/         # source DoD certificate bundle (PKCS7)
│       ├── Certificates_PKCS7_v5_14_DoD.pem.p7b
│       ├── Certificates_PKCS7_v5_14_DoD_DoD_Root_CA_3.der.p7b
│       ├── Certificates_PKCS7_v5_14_DoD_DoD_Root_CA_4.der.p7b
│       ├── Certificates_PKCS7_v5_14_DoD_DoD_Root_CA_5.der.p7b
│       ├── Certificates_PKCS7_v5_14_DoD_DoD_Root_CA_6.der.p7b
│       └── DoD_PKE_CA_chain.pem
└── scripts/
    ├── build.sh                              # builds melange package + both apko images
    └── test.sh                               # runs verification tests
```

## Prerequisites

- [melange](https://github.com/chainguard-dev/melange) - for building the apk package
- [apko](https://github.com/chainguard-dev/apko) - for building container images
- [Docker](https://www.docker.com/) - for loading and running the built images

## Quick Start

```sh
make build    # generate signing keys, build the apk, build both images
make test     # run the test suite
make clean    # remove all build artifacts (tars, keys, packages, SBOMs)
```

## Melange Package Configuration

The `melange.yaml` defines how the DoD certificates are packaged into an apk.

### Package Metadata

```yaml
package:
  name: ca-certificates-dod-unclass
  version: 5.14.0
  epoch: 2
  dependencies:
    runtime:
      - ca-certificates-bundle
    replaces:
      - ca-certificates-bundle
```

- **`runtime: ca-certificates-bundle`** - declares a dependency on the standard Wolfi CA bundle so it is always installed first.
- **`replaces: ca-certificates-bundle`** - allows this package to overwrite `/etc/ssl/certs/ca-certificates.crt` from `ca-certificates-bundle`. Without this, apko rejects the image build due to a file conflict.

### Build Pipeline

The pipeline runs inside a Wolfi build environment with `busybox` and `openssl` available:

1. **Extract certificates** - `openssl pkcs7 -print_certs` converts the source PKCS7 bundle (`Certificates_PKCS7_v5_14_DoD.pem.p7b`) into individual PEM files, then `awk` splits them by CN into separate `.crt` files.

2. **Install individual certs** - each cert is placed in `/usr/share/ca-certificates/dod/` (e.g., `DoD_Root_CA_3.crt`, `DOD_SW_CA-82.crt`).

3. **Create DoD-only bundle** - all DoD certs are concatenated into `/etc/ssl/certs/dod-ca-certificates.crt` for applications that want to reference the DoD bundle separately.

4. **Merge into system trust store** - the existing `/etc/ssl/certs/ca-certificates.crt` from the build environment (provided by `ca-certificates-bundle`) is copied and the DoD certs are appended. This merged file becomes the package's version of `ca-certificates.crt`.

### Why Not Use Scriptlets?

apko does not execute package scriptlets (post-install, etc.) - it only extracts files. An earlier version of this package used a `post-install` scriptlet to run `update-ca-certificates` or append certs to the trust store, but that never fired when installed via apko. The current approach performs the merge entirely in the build pipeline, so the resulting apk contains the final merged trust store file and works with both apk and apko.

## apko Image Configurations

### wolfi-ca-certificates-dod-unclass.yaml

Builds a Wolfi base image with the DoD certificate package included:

```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
    - ./melange.rsa.pub          # local package signing key
  repositories:
    - https://packages.wolfi.dev/os
    - ./packages                  # local melange package output
  packages:
    - wolfi-base
    - ca-certificates-dod-unclass
    - curl
```

The local `./packages` repository and `./melange.rsa.pub` key allow apko to find and verify the locally-built apk.

### wolfi-base.yaml

A baseline Wolfi image without DoD certs, used for comparison testing:

```yaml
contents:
  keyring:
    - https://packages.wolfi.dev/os/wolfi-signing.rsa.pub
  repositories:
    - https://packages.wolfi.dev/os
  packages:
    - wolfi-base
    - curl
```

## Tests

The test suite (`scripts/test.sh`) builds on Docker and validates 5 things:

| Test | Description |
|------|-------------|
| 1 | The DoD image has more certificates in `/etc/ssl/certs/ca-certificates.crt` than the baseline (expects +49 DoD certs) |
| 2 | Individual DoD cert files exist in `/usr/share/ca-certificates/dod/` |
| 3 | Standard HTTPS still works (curl to `google.com` returns 200) |
| 4 | A DoD PKI-signed site (`www.defensetravel.osd.mil`) **fails** TLS verification in the baseline image |
| 5 | The same DoD PKI-signed site **succeeds** TLS verification in the DoD image |

Tests 4 and 5 are the key validation: `www.defensetravel.osd.mil` presents a certificate signed by `DOD SW CA-82` (part of the DoD PKI chain), which is not trusted by default in any standard trust store. The test confirms that only the image with the DoD certs merged into the trust store can complete the TLS handshake.

## Installed Certificate Hierarchy

The package includes DoD Root CAs and their intermediate CAs:

- **DoD Root CA 3, 4, 5, 6** - root certificates
- **DOD DERILITY CA-1, 3, 4, 5, 6** - identity/decommissioning CAs
- **DOD EMAIL CA-59 through 81** - email signing CAs
- **DOD ID CA-59 through 81** - identity CAs
- **DOD SW CA-60 through 85** - software/server CAs

48 certificates total, covering the full DoD Unclassified PKI v5.14 bundle.

## Updating Certificates

When a new DoD certificate bundle is released:

1. Replace the contents of `certs/Certificates_PKCS7_v5_14_DoD/` with the new bundle
2. Update the `version` in `melange.yaml` to match the new bundle version
3. Run `make clean && make build && make test`
