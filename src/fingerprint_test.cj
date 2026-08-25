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

    @TestCase
    func canonicalFingerprintEncodingHasNoDelimiterOrFieldSplitCollisions(): Unit {
        let emptyFirst = CanonicalDescriptor()
        emptyFirst.append("")
        emptyFirst.append("文@|:/")
        let emptyLast = CanonicalDescriptor()
        emptyLast.append("文@|:/")
        emptyLast.append("")
        @Expect(Sha256.digest(emptyFirst.toString()) == Sha256.digest(emptyLast.toString()), false)

        let splitLeft = DialectCompiler.compile(MarkdownDialect.define("a@b", "c").build())
        let splitRight = DialectCompiler.compile(MarkdownDialect.define("a", "b@c").build())
        @Expect(splitLeft.fingerprint == splitRight.fingerprint, false)

        let unicode = DialectCompiler.compile(MarkdownDialect.define("文档@|:/", "β@|:/").build())
        @Expect(unicode.fingerprint.size, 64)

        let firstOrder = DialectCompiler.compile(
            MarkdownDialect
                .define("ordered-set", "1")
                .enable(ExtensionManifest("a", "1.0.0", "x"))
                .enable(ExtensionManifest("b", "1.0.0", "y"))
                .build())
        let reverseOrder = DialectCompiler.compile(
            MarkdownDialect
                .define("ordered-set", "1")
                .enable(ExtensionManifest("b", "1.0.0", "y"))
                .enable(ExtensionManifest("a", "1.0.0", "x"))
                .build())
        @Expect(firstOrder.fingerprint, reverseOrder.fingerprint)

        let rulesLeft = DialectCompiler.compile(
            MarkdownDialect
                .define("rule-order", "1")
                .enable(ExtensionManifest("x", "1.0.0", "1"))
                .inline(InlineSyntax.define("x", "a").delimiter("%%"))
                .inline(InlineSyntax.define("x", "b").delimiter("^^"))
                .build())
        let rulesRight = DialectCompiler.compile(
            MarkdownDialect
                .define("rule-order", "1")
                .enable(ExtensionManifest("x", "1.0.0", "1"))
                .inline(InlineSyntax.define("x", "b").delimiter("^^"))
                .inline(InlineSyntax.define("x", "a").delimiter("%%"))
                .build())
        @Expect(rulesLeft.fingerprint == rulesRight.fingerprint, false)
    }
}
