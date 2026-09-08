# Launcher branding asset

The launcher artwork is copied byte-for-byte from:

- repository: `Regstar2/tg-ws-proxy-android`;
- source path: `icon.png`;
- source branch at extraction: `main`;
- Git blob SHA: `7c943f64d8beb01df6e5dd16128fc0ca0a56e863`;
- source size: 771432 bytes.

Tracked source asset:

```text
integration/branding/res/drawable-nodpi/tgwsproxy_launcher_source.png
```

Android packaging uses:

- a default `mipmap/tgwsproxy_launcher` alias for legacy launchers;
- an adaptive `mipmap-anydpi-v26/tgwsproxy_launcher.xml` resource for API 26+.

The integration script copies these resources into the generated `.tgwsproxy/branding/res` directory and generates a standalone manifest that points `android:icon` and `android:roundIcon` to `@mipmap/tgwsproxy_launcher`.

The same generated standalone manifest sets the application label to the literal `Telegram-WSP`. A literal manifest label is used intentionally so locale-specific upstream `AppName` resources cannot change the fork name back to `Telegram` on devices using translated resources. Package/applicationId values are unchanged.

The pinned Telegram source tree is not modified with extra branding resource files.
