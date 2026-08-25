package markdown

import std.unittest.*
import std.unittest.testmacro.*
import std.unicode.*

class UppercasePass <: TransformPass {
    public prop id: String {
        get() {
            "uppercase"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop requires: Array<String> {
        get() {
            []
        }
    }
    public prop produces: Array<String> {
        get() {
            ["upper-text"]
        }
    }
    public prop priority: Int64 {
        get() {
            10
        }
    }
    public prop purity: TransformPurity {
        get() {
            TransformPurity.Pure
        }
    }
    public func apply(document: Document): Document {
        TreeRewriter.rewrite(document, {
            node => match (node) {
                case text: Text => RewriteAction.MapText(text.value.toUpper())
                case _ => RewriteAction.Keep
            }
        })
    }
}

class DependentPass <: TransformPass {
    public prop id: String {
        get() {
            "dependent"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop requires: Array<String> {
        get() {
            ["upper-text"]
        }
    }
    public prop produces: Array<String> {
        get() {
            ["done"]
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop purity: TransformPurity {
        get() {
            TransformPurity.Pure
        }
    }
    public func apply(document: Document): Document {
        document
    }
}

@Test
class ServicesTest {
    @TestCase
    func resolvedAndRawEventsHaveExplicitlyDifferentSemantics(): Unit {
        let document = MarkdownEngine.builder().build().parse("# H").document
        var resolvedText: Int64 = 0
        for (event in document.events()) {
            if (let MarkdownEvent.TextValue(_) <- event) {
                resolvedText++
            }
        }
        var rawText: Int64 = 0
        for (event in document.events(mode: EventMode.RawBlock)) {
            if (let MarkdownEvent.TextValue(_) <- event) {
                rawText++
            }
        }
        @Expect(resolvedText, 1)
        @Expect(rawText, 0)
    }

    @TestCase
    func annotationChannelsAreTypedAndLifecycleBound(): Unit {
        let store = AnnotationStore()
        @Expect(store.threadSafe, false)
        let channel = store.channel(AnnotationKey<String>("heading-slug", includeInFingerprint: true))
        channel.put(NodeId(1), "intro")
        @Expect(channel.get(NodeId(1)), Some("intro"))
        store.close()
        @Expect(store.isClosed(), true)
    }

    @TestCase
    func transformPipelineOrdersDependenciesAndValidatesOutput(): Unit {
        let pipeline = TransformPipeline.compile([DependentPass(), UppercasePass()])
        @Expect(pipeline.orderedPassIds(), ["uppercase", "dependent"])
        let document = MarkdownEngine.builder().build().parse("hello").document
        @Expect(PlainTextRenderer().render(pipeline.run(document)), "HELLO")
    }
}
