# SPI and schema versions

| Contract | Version | Compatibility rule |
| --- | --- | --- |
| Extension SPI | `1` | Unsupported versions fail during dialect compilation. |
| Dialect DSL schema | `1` | Semantic changes require a new schema version. |
| Syntax DSL schema | `1` | Rule normalization and ordering are fingerprinted. |
| Parser plan | `1` | Included in parse-artifact validation. |
| Parse artifact | `1` | Any mismatch is a cache miss; no guessed recovery. |
| Public API snapshot | `v1` | Checked by `scripts/check_public_api.py`. |

Semantic and implementation extension versions are distinct. Dialect SHA-256
fingerprints include base profile, dialect identity, extension identities,
normalized rules and order. Engine fingerprints add result-affecting limits.
Renderer policies are selected explicitly and are not part of parse cache keys.
