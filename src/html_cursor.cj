package markdown

import std.collection.*

/** A lazy renderer write. Its String is source/derived input, never a complete HTML document. */
internal class HtmlCursorEmission {
    let kind: Int64
    let value: String
    let node: ?NodeRef
    let start: Int64
    let end: Int64
    init(kind: Int64, value: String, node!: ?NodeRef = None, start!: Int64 = 0, end!: Int64 = -1) {
        this.kind = kind
        this.value = value
        this.node = node
        this.start = start
        this.end = if (end < 0) {
            value.size
        } else {
            end
        }
    }
}

internal enum HtmlCursorAction {
    | Output(HtmlCursorEmission)
    | Node(ArenaRenderFrame)
    | Children(NodeRef, Int64, Bool, Bool, Bool)
    | Table(NodeRef, Int64, Int64)
    | TableRow(NodeRef, Bool)
    | TableCells(NodeRef, Int64, Bool)
    | ImageAlt(NodeRef)
    | ImageChildren(NodeRef, Int64)
    | Footnotes(Document, Int64, Int64, Int64)
}

/** Records only the current node's bounded write plan and lazy child iterators. */
internal class HtmlPlanSink <: TextSink {
    private var actions = ArrayList<HtmlCursorAction>()
    public func write(value: String): SinkWriteResult {
        emit(HtmlCursorAction.Output(HtmlCursorEmission(0, value)))
        SinkWriteResult.Success
    }
    func emit(value: HtmlCursorAction): Unit {
        actions.add(value)
    }
    func output(kind: Int64, value: String, node!: ?NodeRef = None, start!: Int64 = 0, end!: Int64 = -1): Unit {
        emit(HtmlCursorAction.Output(HtmlCursorEmission(kind, value, node: node, start: start, end: end)))
    }
    func children(node: NodeRef, tableHeader!: Bool = false, suppressParagraph!: Bool = false, listItem!: Bool = false): Unit {
        emit(HtmlCursorAction.Children(node, 0, tableHeader, suppressParagraph, listItem))
    }
    func take(): Array<HtmlCursorAction> {
        let result = actions.toArray()
        actions.clear()
        result
    }
}

/** Pulls real renderer traversal and unfinished escaping in bounded UTF-8 chunks. */
internal class HtmlOutputCursor {
    private let renderer: HtmlRenderer
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let chunkBytes: Int64
    private let planner = HtmlPlanSink()
    private let legacyFrames = ArrayList<ArenaRenderFrame>()
    private let actions = ArrayList<HtmlCursorAction>()
    private var emission: ?HtmlCursorEmission = None
    private var inputOffset: Int64 = 0
    private var generated = ""
    private var generatedOffset: Int64 = 0
    private var maximumBuffer: Int64 = 0
    private var maximumActions: Int64 = 0

    init(renderer: HtmlRenderer, document: Document, chunkBytes: Int64, cancellation: CancellationToken,
        budget: OperationBudget) {
        if (chunkBytes < 4) {
            throw IllegalArgumentException("HTML output chunk size must be at least four bytes")
        }
        this.renderer = renderer
        this.chunkBytes = chunkBytes
        this.cancellation = cancellation
        this.budget = budget
        actions.add(HtmlCursorAction.Footnotes(document, 0, 0, 0))
        actions.add(HtmlCursorAction.Node(ArenaRenderFrame(document.root(), false)))
    }

    func nextChunk(): ?String {
        while (!actions.isEmpty() || emission.isSome() || generatedOffset < generated.size) {
            cancellation.throwIfCancelled(phase: "render")
            if (generatedOffset < generated.size) {
                let end = cursorUtf8End(generated, generatedOffset, chunkBytes, generated.size)
                let chunk = generated[generatedOffset..end]
                generatedOffset = end
                if (generatedOffset == generated.size) {
                    generated = ""
                    generatedOffset = 0
                }
                return Some(chunk)
            }
            if (let Some(value) <- emission) {
                if (inputOffset < value.end) {
                    let width = if (value.kind == 0) {
                        chunkBytes
                    } else {
                        max(1, chunkBytes / 8)
                    }
                    let end = cursorUtf8End(value.value, inputOffset, width, value.end)
                    budget.consumeScan(steps: end - inputOffset)
                    generated = renderer.encodeCursorEmission(value, inputOffset, end, cancellation, budget)
                    maximumBuffer = max(maximumBuffer, generated.size)
                    inputOffset = end
                    continue
                }
                emission = None
            }
            if (actions.isEmpty()) {
                return None
            }
            budget.consumeScan()
            maximumActions = max(maximumActions, actions.size)
            expand(actions.remove(at: actions.size - 1))
            let planned = planner.take()
            var index = planned.size - 1
            while (index >= 0) {
                actions.add(planned[index]);
                index--
            }
        }
        None
    }

    func bufferedBytes(): Int64 {
        generated.size - generatedOffset
    }
    func maximumBufferedBytes(): Int64 {
        maximumBuffer
    }
    func maximumPendingActions(): Int64 {
        maximumActions
    }

    private func expand(action: HtmlCursorAction): Unit {
        match (action) {
            case HtmlCursorAction.Output(value) =>
                emission = Some(value)
                inputOffset = value.start
            case HtmlCursorAction.Node(frame) => renderer.expandCursorNode(frame, legacyFrames, planner, cancellation,
                budget)
            case HtmlCursorAction.Children(parent, index, header, suppress, listItem) =>
                let children = parent.children()
                if (index < children.size) {
                    let child = children[index]
                    let childSuppress = if (listItem && suppress) {
                        if (let NodeKind.Paragraph <- child.kind) {
                            true
                        } else {
                            false
                        }
                    } else {
                        suppress
                    }
                    actions.add(HtmlCursorAction.Children(parent, index + 1, header, suppress, listItem))
                    actions.add(
                        HtmlCursorAction.Node(
                            ArenaRenderFrame(child, false, tableHeader: header, suppressParagraph: childSuppress,
                                newlineAfter: listItem && childSuppress && index + 1 < children.size)))
                }
            case HtmlCursorAction.Table(table, index, stage) => expandTable(table, index, stage)
            case HtmlCursorAction.TableRow(row, header) => renderer.expandCursorTableRow(row, header, planner,
                cancellation, budget)
            case HtmlCursorAction.TableCells(row, index, header) =>
                let cells = row.children()
                if (index < cells.size) {
                    let cell = cells[index]
                    if (cell.asTableCell().isNone()) {
                        throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                            "table row contains non-cell", phase: "render", span: cell.span)
                    }
                    actions.add(HtmlCursorAction.TableCells(row, index + 1, header))
                    actions.add(HtmlCursorAction.Node(ArenaRenderFrame(cell, false, tableHeader: header)))
                }
            case HtmlCursorAction.ImageAlt(node) => expandImageAlt(node)
            case HtmlCursorAction.ImageChildren(parent, index) =>
                let children = parent.children()
                if (index < children.size) {
                    actions.add(HtmlCursorAction.ImageChildren(parent, index + 1))
                    actions.add(HtmlCursorAction.ImageAlt(children[index]))
                }
            case HtmlCursorAction.Footnotes(document, index, stage, reference) => expandFootnotes(document, index, stage,
                reference)
        }
    }

    private func expandTable(table: NodeRef, index: Int64, stage: Int64): Unit {
        let rows = table.children()
        match (stage) {
            case 0 =>
                planner.output(0, "<table>\n")
                if (rows.size > 0) {
                    planner.output(0, "<thead>\n")
                    planner.emit(HtmlCursorAction.TableRow(rows[0], true))
                    planner.emit(HtmlCursorAction.Table(table, 1, 1))
                } else {
                    planner.output(0, "</table>\n")
                }
            case 1 =>
                planner.output(0, "</thead>\n")
                if (rows.size > 1) {
                    planner.output(0, "<tbody>\n")
                    planner.emit(HtmlCursorAction.Table(table, 1, 2))
                } else {
                    planner.output(0, "</table>\n")
                }
            case _ =>
                if (index < rows.size) {
                    planner.emit(HtmlCursorAction.TableRow(rows[index], false))
                    planner.emit(HtmlCursorAction.Table(table, index + 1, 2))
                } else {
                    planner.output(0, "</tbody>\n</table>\n")
                }
        }
    }

    private func expandImageAlt(node: NodeRef): Unit {
        renderer.requireCursorCustomContract(node)
        if (let Some(value) <- mathPayload(node)) {
            planner.output(2, value.expression)
            return
        }
        match (node.kind) {
            case NodeKind.Text => planner.output(2, node.asText().getOrThrow().value)
            case NodeKind.CodeSpan => planner.output(2, node.asCodeSpan().getOrThrow().literal)
            case NodeKind.SoftBreak => planner.output(2, "\n")
            case NodeKind.HardBreak => planner.output(2, "\n")
            case _ => actions.add(HtmlCursorAction.ImageChildren(node, 0))
        }
    }

    private func expandFootnotes(document: Document, index: Int64, stage: Int64, reference: Int64): Unit {
        let notes = document.bindings.footnotes
        if (notes.isEmpty()) {
            return
        }
        if (stage == 0) {
            planner.output(0, "<section class=\"footnotes\" aria-label=\"Footnotes\">\n<ol>\n")
            planner.emit(HtmlCursorAction.Footnotes(document, 0, 1, 0))
        } else if (stage == 1) {
            if (index >= notes.size) {
                planner.output(0, "</ol>\n</section>\n");
                return
            }
            let note = notes[index]
            let definition = document.nodeRefAtPhysical(note.definitionIndex)
            renderer.cursorFootnoteOpen(note, planner, cancellation, budget)
            planner.children(definition)
            planner.emit(HtmlCursorAction.Footnotes(document, index, 2, 0))
        } else {
            let note = notes[index]
            if (reference == 0) {
                planner.output(0, "<p class=\"footnote-backlinks\">")
            }
            if (reference < note.references.size) {
                let definition = document.nodeRefAtPhysical(note.definitionIndex)
                renderer.cursorFootnoteBacklink(note, reference, definition, planner, cancellation, budget)
                planner.emit(HtmlCursorAction.Footnotes(document, index, 2, reference + 1))
            } else {
                planner.output(0, "</p>\n</li>\n")
                planner.emit(HtmlCursorAction.Footnotes(document, index + 1, 1, 0))
            }
        }
    }
}

/** Return a nonempty UTF-8 prefix; chunk sizes >= 4 can hold any scalar. */
internal func cursorUtf8End(value: String, start: Int64, width: Int64, limit: Int64): Int64 {
    var end = min(limit, start + min(width, limit - start))
    while (end > start && end < limit && (value[end] & 0xC0) == 0x80) {
        end--
    }
    if (end == start) {
        end++
        while (end < limit && (value[end] & 0xC0) == 0x80) {
            end++
        }
    }
    end
}
