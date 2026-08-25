package markdown

import std.unittest.*
import std.unittest.testmacro.*

class CountingVisitor <: MarkdownVisitor {
    var headings: Int64 = 0
    var texts: Int64 = 0
    protected override func enter(_: Heading): Unit {
        headings++
    }
    protected override func enter(_: Text): Unit {
        texts++
    }
}

@Test
class TraversalQueryTest {
    @TestCase
    func walkerIsNonRecursiveAndEmitsBalancedEvents(): Unit {
        let document = MarkdownEngine.builder().build().parse("# H\n\nA [link](url)").document
        var enters: Int64 = 0
        var exits: Int64 = 0
        for (event in document.walk()) {
            match (event) {
                case WalkEvent.Enter(_) => enters++
                case WalkEvent.Exit(_) => exits++
            }
        }
        @Expect(enters, exits)
        @Expect(enters > 1, true)
    }

    @TestCase
    func typedVisitorAndQueriesReturnExactNodesAndRelations(): Unit {
        let document = MarkdownEngine.builder().build().parse("# H\n\nA [link](url)").document
        let visitor = CountingVisitor()
        visitor.traverse(document)
        @Expect(visitor.headings, 1)
        @Expect(visitor.texts, 3)
        @Expect(AstQuery.headings(document).size, 1)
        @Expect(AstQuery.links(document).size, 1)
        let link = AstQuery.links(document)[0]
        @Expect(AstQuery.byNodeId(document, link.nodeId).isSome(), true)
        @Expect(AstQuery.ancestors(document, link.nodeId).size, 2)
        @Expect(AstQuery.descendants(document).size, 6)
        @Expect(AstQuery.containing(document, link.span.getOrThrow()).size >= 3, true)
        @Expect(AstQuery.byKind(document, NodeKind.Link).size, 1)
    }
}
