# External dialect schema v1

External JSON/YAML descriptors are data only. Values are strings or arrays of
strings; unknown keys, objects/callbacks, duplicate fields, tabs in YAML,
unsupported schema/profile, invalid rule field counts, and unbounded rules are
rejected.

Required fields: `schemaVersion`, `id`, `version`, `baseProfile`. Optional
arrays: `inlineRules`, `blockRules`, `rendererRules`.

- Inline: `ruleId|opener|closer|maxLookahead|parseChildren|allowNesting`
- Block: `ruleId|opener|closer|content(markdown-or-literal)|maxBlockBytes|maxCapture|allowNesting`
- Renderer: `kindId|htmlTag|classToken|markdownOpener|markdownCloser`

The normalized descriptor is included through the external implementation
digest and compiled dialect fingerprint. There is no field capable of carrying
or executing a code callback.
