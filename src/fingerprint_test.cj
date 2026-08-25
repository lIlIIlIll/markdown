package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FingerprintTest {
    @TestCase
    func sha256MatchesKnownVectors(): Unit {
        @Expect(Sha256.digest(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        @Expect(Sha256.digest("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @TestCase
    func dialectFingerprintIsDeterministicAndSemanticChangesAlterIt(): Unit {
        let first = DialectCompiler.compile(MarkdownDialect.define("docs", "1").build())
        let same = DialectCompiler.compile(MarkdownDialect.define("docs", "1").build())
        let changed = DialectCompiler.compile(MarkdownDialect.define("docs", "2").build())
        @Expect(first.fingerprint, same.fingerprint)
        @Expect(first.fingerprint.size, 64)
        @Expect(first.fingerprint != changed.fingerprint, true)
    }
}
