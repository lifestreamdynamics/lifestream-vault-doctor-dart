## 1.0.1

- Fix YAML frontmatter quoting for special scalars (`true`, `false`, `null`, numeric strings)
- Fix `flushQueue` to honor `setConsentPreVerified()` for queue flushing
- Fix `CrashQueue._load()` to handle malformed JSON entries without crashing
- Add `close()` method for HTTP client lifecycle management
- Add device context adapter tests

## 1.0.0

- Initial release — Dart port of `@lifestreamdynamics/doctor`
- Pure Dart core (no Flutter dependency)
- HMAC-SHA256 request signing
- Offline queue with persistent storage support
- GDPR consent management
- Rate limiting and deduplication
- Breadcrumb trail (circular buffer)
- Markdown + YAML report format (compatible with TypeScript version)
- Device context collection via `dart:io`
