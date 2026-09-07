# Licensing audit

Status: **resolved for the planned architecture**  
Audit date: 2026-09-07

> [!NOTE]
> This is an engineering compliance review based on the published license notices of the
> audited projects. It is not individualized legal advice.

## Decision

The planned Telegram WS Proxy client can be distributed as an open-source GPLv3 client
without a GPLv2/GPLv3 incompatibility, provided the release follows the source and notice
requirements in this document.

Project policy:

- license this repository's integration/overlay and TgWsProxy-derived combined code under
  **GNU GPL-3.0-only**;
- exercise Telegram for Android's published **GNU GPL v2 or later** grant under GPLv3 when
  producing the combined client;
- retain the original licenses and notices of independent third-party components;
- publish complete Corresponding Source for every distributed APK;
- use independent branding, API credentials and signing material required by Telegram.

## Evidence snapshot

The audit is pinned to the following source state:

| Project | Revision/version |
|---|---|
| `DrKLO/Telegram` | `62b56a07ca7e30e39f7fd00a6728d6bbd716ca1c` — Telegram 12.10.1 (7038) |
| `Regstar2/tg-ws-proxy-android` | `b2558f16f8a46aa3abec2660acd606bffdfac613` |
| `amurcanov/tg-ws-proxy-android` | `da54314b7d9c1577851fc0f420bcfb6a1b67eee9` |
| `Flowseal/tg-ws-proxy` | `c02398fbc0af432ecb9ccacb7be7d97cdf5e74cf` |
| `golang.org/x/crypto` | `v0.31.0` |
| JNA | `5.14.0` |
| Go | module baseline `go 1.25`; license checked against Go 1.25 source |

The audit must be revisited if one of the upstream projects changes its licensing terms or
the integration adds a dependency with a copyleft/patent condition not covered here.

## 1. Telegram for Android

Repository:

- https://github.com/DrKLO/Telegram
- official application listing: https://telegram.org/apps

Telegram's root repository carries the GNU GPL v2 license text. More importantly, the
official Telegram application page states that Telegram for Android is licensed under
**GNU GPL v2 or later**, and first-party source files contain the same explicit notice.

Examples in the audited revision:

- `TMessagesProj/src/main/java/org/telegram/messenger/ApplicationLoader.java`:
  `It is licensed under GNU GPL v. 2 or later.`
- `TMessagesProj/jni/tgnet/ConnectionsManager.cpp`:
  `It is licensed under GNU GPL v. 2 or later.`
- the same notice is present across many first-party Java/C++ source files.

This distinction is decisive. A GPLv2-only work cannot normally be combined into one
program with GPLv3-only code. A GPLv2-or-later grant allows the recipient to select GPLv3
for the combined work. GNU's GPLv3 compatibility guidance states the same rule.

Reference:

- https://www.gnu.org/licenses/quick-guide-gplv3.html

### Consequence

Telegram-derived modifications used by this project can be distributed under GPLv3 when
the "or later" option is exercised. The project must preserve Telegram copyright/license
notices and must not claim ownership of upstream code.

Telegram's bundled third-party code keeps its own licenses. This audit does not relicense
those dependencies.

## 2. amurcanov and Regstar2 Android forks

`amurcanov/tg-ws-proxy-android` contains the GNU GPL v3 license text and its README states
that the fork is distributed under GPLv3.

`Regstar2/tg-ws-proxy-android` inherits from that project and likewise contains the GNU
GPL v3 license and declares GPLv3 in its README.

No separate "or any later version" grant was identified for the fork as a whole. Therefore
the safe project policy is to treat copied or derived code from these forks as
**GPL-3.0-only**, unless a specific file has a more permissive notice.

This is compatible with Telegram because Telegram for Android grants GPLv2-or-later and
GPLv3 can be selected for Telegram-derived code in the combined client.

## 3. Flowseal runtime origin

`Flowseal/tg-ws-proxy` is licensed under the MIT License.

MIT is permissive and GPL-compatible. Code copied from or substantially based on Flowseal
may be incorporated into the GPLv3 combined work, while the Flowseal MIT copyright and
permission notice must remain available.

The current Android fork documents Flowseal as the runtime origin in
`ORIGINAL_VS_ANDROID_DIFF.md`.

## 4. Go/native dependency inventory

The current native module in `Regstar2/tg-ws-proxy-android` declares:

```text
module tg-ws-proxy
go 1.25

require golang.org/x/crypto v0.31.0
```

### Go standard library/runtime

Go 1.25 source uses the Go project's BSD 3-Clause-style license and patent grant. Those
terms are compatible with GPLv3.

### golang.org/x/crypto v0.31.0

The module uses the Go project's 3-clause BSD license. It is GPL-compatible. Binary
redistribution must reproduce its required copyright/license disclaimer in documentation
or other materials supplied with the distribution.

No other external Go module is declared by the current native `go.mod`.

## 5. Android native bridge / JNA

The current standalone Android application uses:

```text
net.java.dev.jna:jna:5.14.0@aar
```

JNA 5.14.0 declares:

```text
Apache-2.0 OR LGPL-2.1
```

For this project, if JNA is retained in `tgwsproxy-core`, select the **Apache-2.0**
licensing option. Apache-2.0 is compatible with GPLv3 according to GNU's GPLv3
compatibility guidance.

Reference:

- https://www.gnu.org/licenses/quick-guide-gplv3.html

The preferred technical alternative is still to keep the bridge minimal. If JNA is removed
in favor of a JNI bridge, JNA disappears from this project's dependency/NOTICE set.

## 6. License for telegram-ws-proxy

The repository uses **GNU GPL-3.0-only** as the project-level license.

Why "only" instead of "or later":

1. the inherited Android fork is explicitly GPLv3;
2. no project-wide later-version permission was found for that inherited GPLv3 code;
3. choosing GPL-3.0-only avoids granting rights that may not be available for inherited
   code.

New files written entirely by the project owner could separately use a more permissive or
"or-later" license, but doing so does not change the license of the combined work.

## 7. Public APK distribution model

A public APK may be published only when the exact release also has complete Corresponding
Source available.

Required release artifacts/pointers:

1. APK and checksum/signature as applicable;
2. exact source tree for the released modified Telegram client;
3. Telegram WS Proxy integration source;
4. TgWsProxy-derived runtime source used to build `libtgwsproxy.so`;
5. build scripts and configuration needed to generate the APK/native library;
6. exact version/revision metadata for external dependencies;
7. license and notice files;
8. source for modified third-party components, if any;
9. required submodule sources or a complete reproducible source bundle.

### Source delivery policy

Development remains overlay-based:

```text
pinned Telegram + patches/integration -> working tree
```

For public binary releases, generate and publish a **complete source archive of the
assembled release tree**. Do not make the external `DrKLO/Telegram` repository the only
source-delivery mechanism.

This policy is intentionally stricter than relying on a patch set alone and removes
ambiguity about whether a recipient can obtain the exact Corresponding Source for the APK.

## 8. Telegram application requirements

Telegram's upstream README asks third-party client developers to:

- obtain their own `api_id`;
- not present the application as the official Telegram app;
- avoid the standard Telegram logo;
- publish their source code;
- replace Telegram's dummy/reproducible-build credentials with their own release
  credentials before publishing an APK.

These are independent of the GPL compatibility result and must be satisfied before a
public release.

Reference:

- https://github.com/DrKLO/Telegram/blob/master/README.md

## 9. Release gate

Before a public binary release:

- [ ] the built source revision matches the public source archive;
- [ ] `LICENSE` contains GPLv3;
- [ ] `NOTICE.md` is included;
- [ ] Telegram upstream notices remain intact;
- [ ] Flowseal MIT notice is retained for incorporated Flowseal-derived material;
- [ ] Go / x/crypto binary notice requirements are included;
- [ ] JNA Apache-2.0 notice is included if JNA is packaged;
- [ ] new dependencies have been added to the license inventory;
- [ ] source archive contains the preferred form for modifying/rebuilding the released APK;
- [ ] own Telegram `api_id`, branding, Firebase configuration and signing material are used.

## 10. Conclusion

**Issue #1 licensing blocker is resolved for the planned architecture.**

There is no GPLv2-vs-GPLv3 incompatibility preventing this project because Telegram for
Android is published under GPL v2 **or later**. The combined Telegram/TgWsProxy-derived
client can therefore use GPLv3, while permissively licensed Flowseal, Go/x-crypto and JNA
(Apache-2.0 option) components remain compatible.

The blocker would reopen if:

- a required Telegram component is discovered to be GPLv2-only and cannot remain a
  separable component;
- the integration introduces an incompatible dependency;
- a public APK is distributed without complete Corresponding Source or required notices.
