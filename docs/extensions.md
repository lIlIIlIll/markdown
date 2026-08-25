# Extension SPI and TCK

An `ExtensionManifest` declares semantic/implementation/SPI versions, profiles, dependencies, conflicts, capabilities, budget, trust level, and missing-renderer policy. Code extensions run with host-process permissions; the library does not claim sandboxing.

The Extension TCK covers chunk invariance, spans, Safe HTML, unclosed/nested syntax, conflict/build failures, limits, cancellation, formatter/renderer coverage, fuzz smoke, and determinism. External JSON/YAML data must never carry executable callbacks.

`OfficialExtensions.p1Dialect()` installs the versioned, default-off 1.1 set:
Footnotes, Front Matter, Math, Definition Lists, Heading IDs, and Smart
Punctuation. Each extension can also be installed independently on a dialect
builder and passes the shared TCK. Front Matter retains raw literal content and
does not parse YAML/TOML/JSON. Math retains literal content and never executes
or invokes a math engine. `OfficialExtensions.catalog()` records the 1.0 GFM,
1.1, and future GitHub Alerts/WikiLinks enablement matrix; P1/future extensions
are not enabled by CommonMark or GFM convenience profiles.

## Isolation boundary

Host-code extensions have the host process's permissions and are not silently
sandboxed. `IsolatedPluginRunner` is a separate fail-closed IPC contract:
`PluginIsolationPolicy` explicitly controls file read/write, network, child
processes, input/output limits and protocol version. A
`PluginIsolationTransport` implementation must create the OS process/sandbox;
the core reports `builtInOsSandbox=false` rather than pretending an in-process
callback is isolated. Cancellation, identity/version mismatch, worker failure,
malformed/oversized output and budget exhaustion reject the response. The host
OS remains the final authority, so an extension cannot gain permissions the
worker process was not granted.
