package markdown

import std.unittest.*
import std.unittest.testmacro.*

class CountingVisitor <: MarkdownVisitor {
    var headings: Int64 = 0
    var texts: Int64 = 0
    protected override func enter(node: NodeRef): Unit {
        match (node.kind) {
            case NodeKind.Heading => headings++
            case NodeKind.Text => texts++
            case _ => ()
        }
    }
}

@Test
class TraversalQueryTest {
    @TestCase
    func arenaWalkerAndQueriesUseNodeRefsDirectly(): Unit {
        let document = MarkdownEngine.builder().build().parse("# H\n\nA [link](url)").ast
        var enters: Int64 = 0
        var exits: Int64 = 0
        for (event in document.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(_) => enters++
                case NodeRefWalkEvent.Exit(_) => exits++
            }
        }
        @Expect(enters, exits)
        @Expect(AstQuery.headings(document).size, 1)
        let links = AstQuery.links(document)
        @Expect(links.size, 1)
        let link = links[0].node
        @Expect(AstQuery.byNodeId(document, link.nodeId), Some(link))
        @Expect(AstQuery.ancestors(document, link.nodeId).size, 2)
        @Expect(AstQuery.descendants(document.root()).size, enters - 1)
        @Expect(AstQuery.containing(document, link.span.getOrThrow()).size >= 3, true)
        @Expect(AstQuery.byKind(document, NodeKind.Link).size, 1)
    }

    @TestCase
    func walkerIsNonRecursiveAndEmitsBalancedEvents(): Unit {
        let document = MarkdownEngine.builder().build().parse("# H\n\nA [link](url)").document
        var enters: Int64 = 0
        var exits: Int64 = 0
        for (event in document.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(_) => enters++
                case NodeRefWalkEvent.Exit(_) => exits++
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
        let link = AstQuery.links(document)[0].node
        @Expect(AstQuery.byNodeId(document, link.nodeId).isSome(), true)
        @Expect(AstQuery.ancestors(document, link.nodeId).size, 2)
        @Expect(AstQuery.descendants(document).size, 6)
        @Expect(AstQuery.containing(document, link.span.getOrThrow()).size >= 3, true)
        @Expect(AstQuery.byKind(document, NodeKind.Link).size, 1)
    }
}
