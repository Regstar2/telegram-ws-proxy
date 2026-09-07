# Third-party notices

This repository integrates or is intended to integrate code from several upstream projects.
The project-level license is GNU GPL v3.0 only. Third-party components keep their own
copyright notices and license terms.

## Components

| Component | Audited revision/version | License | Treatment in Telegram WS Proxy |
|---|---|---|---|
| Telegram for Android — `DrKLO/Telegram` | `62b56a07ca7e30e39f7fd00a6728d6bbd716ca1c` | GNU GPL v2 or later | Telegram-derived code may be used under GPLv3 for the combined GPLv3 work. Preserve upstream copyright/license notices. |
| `amurcanov/tg-ws-proxy-android` | `da54314b7d9c1577851fc0f420bcfb6a1b67eee9` | GNU GPL v3 | Treat inherited Android/runtime-derived code conservatively as GPL-3.0-only. |
| `Regstar2/tg-ws-proxy-android` | `b2558f16f8a46aa3abec2660acd606bffdfac613` | GNU GPL v3 | Source of the current Android/runtime implementation. Treat copied/derived code as GPL-3.0-only unless a file states otherwise. |
| `Flowseal/tg-ws-proxy` | `c02398fbc0af432ecb9ccacb7be7d97cdf5e74cf` | MIT | Compatible with GPLv3. Preserve the Flowseal copyright and MIT permission notice for copied/substantial portions. |
| Go standard library/toolchain | Go 1.25 baseline | BSD 3-Clause-style + Go patent grant | Compatible with GPLv3. Preserve required notices for redistributed source/binary material as applicable. |
| `golang.org/x/crypto` | `v0.31.0` | BSD 3-Clause | Compatible with GPLv3. Preserve copyright/license notice in source and binary-distribution notices. |
| JNA | `5.14.0` | Apache-2.0 OR LGPL-2.1 | If JNA remains in the integrated core, this project selects the Apache-2.0 option. Apache-2.0 is GPLv3-compatible. Preserve its license/NOTICE requirements. |

## Telegram third-party code

The Telegram source tree includes third-party libraries and assets under their own licenses.
This NOTICE does not attempt to relicense those components. When building or redistributing
Telegram WS Proxy:

- keep Telegram's existing third-party license files and notices intact;
- do not replace third-party licenses with the project-level GPL text;
- include the exact corresponding source and license material for components for which the
  applicable license requires it;
- review any new dependency added by the integration before public binary distribution.

## Distribution requirements

For a public APK release, the project policy is to publish an exact source package for the
same release. The source package must contain the preferred form for modification of the
combined client, including the Telegram source revision, Telegram WS Proxy integration
source, TgWsProxy-derived source, build scripts, dependency manifests, patches/overlay and
the license/notice files required to rebuild the released APK.

A patch-only repository is useful for development, but public binary distribution must not
rely on the continued availability of an external upstream repository as the only way to
obtain Corresponding Source.

See [docs/licensing.md](docs/licensing.md) for the audit and release policy.
