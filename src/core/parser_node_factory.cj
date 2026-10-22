package markdown.core

import std.collection.*

private func parserInitialArenaCapacity(estimatedInputBytes: Int64, source: ?SourceBuffer): Int64 {
    var bytesPerNode: Int64 = 16
    if (estimatedInputBytes >= 4096) {
        if (let Some(buffer) <- source) {
            if (let Some(bytes) <- buffer.decodedBytesForNative()) {
                var index: Int64 = 0
                let probeEnd = min(bytes.size, 256)
                var foundLineBreak = false
                while (index < probeEnd) {
                    if (bytes[index] == b'\n' || bytes[index] == b'\r') {
                        foundLineBreak = true
                        break
                    }
                    index++
                }
                if (!foundLineBreak) {
                    bytesPerNode = 1024
                }
            }
        }
    }
    max(16, estimatedInputBytes / bytesPerNode)
}

/**
 * parser 的受信任节点构造边界，集中维护 arena 分配、origin 和节点记录顺序。
 *
 * 调用方只能传入当前 factory 的子节点下标，必须先构造子节点，再将其挂接到唯一父节点。
 * 此路径省略通用 builder 的重复、前向与多父检查，不应作为绕过 AST invariant 的构造入口。
 * span 使用原始输入字节坐标，literal 的源码映射及扩展 schema 由 parser 保证。
 * 每次追加都在修改存储前检查 maximumAstNodes 并消耗可选 constructionBudget。
 * 需要扫描、literal 或其他操作预算时，parser 仍须在相应阶段单独计入。
 */
protected class ParserNodeFactory {
    private let arena: AstArenaBuilder
    private let maximumAstNodes: Int64
    private let source: ?SourceBuffer
    private var hasOrphans = false
    /**
     * parser 是否曾追加需要文档绑定的内建 custom payload，初值为 false；rollback 不清除此标记。
     */
    protected var requiresBinding = false

    /**
     * 创建启用受信任 parser 构造路径的 arena factory。
     * @param maximumAstNodes 包括最终 Document 根节点在内的 arena 节点数上限。
     * @param estimatedInputBytes 用于估算初始 arena 容量的输入大小，默认 0，不替代实际资源限制。
     * @param source 可选 parser source，默认 None；source-backed 文本方法要求提供。
     * @param lineage 可选节点身份分配器，默认创建独立 lineage。
     * @param constructionBudget 可选节点构造预算，每次追加节点前消耗；默认不额外计入该预算。
     */
    protected init(maximumAstNodes: Int64, estimatedInputBytes!: Int64 = 0, source!: ?SourceBuffer = None,
        lineage!: ?NodeLineage = None, constructionBudget!: ?NodeConstructionBudget = None) {
        this.maximumAstNodes = maximumAstNodes
        this.source = source
        let estimatedNodes = parserInitialArenaCapacity(estimatedInputBytes, source)
        arena = AstArenaBuilder(maximumNodes: maximumAstNodes, trustedParserConstruction: true,
            initialNodeCapacity: min(AST_NODE_CHUNK_SIZE, estimatedNodes),
            initialChildCapacity: min(AST_CHILD_CHUNK_SIZE, estimatedNodes), sourceBuffer: source, lineage: lineage,
            constructionBudget: constructionBudget)
    }

    /**
     * 追加 Document 根节点并冻结 arena，仅公开根节点可达的树。
     *
     * 输入 children 必须构成严格后序构造的树，普通路径不重新扫描重复或多父关系。
     * 存在被放弃的记录时使用可达性冻结，不将孤立记录暴露为文档节点。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @param profile 解析所用的 profile 身份。
     * @param dialectFingerprint 解析所用的 dialect fingerprint。
     * @param references 按解析顺序收集的文档级 reference definitions。
     * @return 绑定 source 与 lineage 的不可变 Document，拥有新的 revision。
     */
    protected func finishDocument(children: Array<Int64>, span: SourceSpan, profile: MarkdownProfile,
        dialectFingerprint: String, references: Array<ReferenceDefinition>): Document {
        let root = arena.appendParserOwned(NodeKind.DocumentNode, NodeCategory.Block, Some(span), NodeOriginKind.Parsed,
            children,
            payload: ArenaNodePayload.DocumentValue(profile, dialectFingerprint,
                ImmutableArray<ReferenceDefinition>(references)))
        if (!hasOrphans && arena.unparentedNodeCount() == 1) {
            return arena.freeze()
        }
        // Preserve one immutable arena snapshot and expose only the reachable
        // records. Speculative parser branches normally rollback before this
        // point; this sparse fallback avoids ever rebuilding the entire AST.
        arena.freeze(root)
    }

    /**
     * 记录当前 append-only arena 状态，供 parser 推测分支回滚。
     * @return 当前 append-only 状态的 checkpoint，不分配 Document snapshot。
     */
    protected func checkpoint(): AstArenaCheckpoint {
        arena.checkpoint()
    }

    /**
     * 撤销 checkpoint 之后追加的 arena 记录、children、payload 和 origin metadata。
     *
     * 仅回滚追加工作，不撤销对旧记录的 replace 操作，也不返还已消耗的构造预算或回收 NodeId。
     * @param checkpoint 由当前 factory 在仍可回退的 append 状态下创建的 checkpoint。
     */
    protected func rollback(checkpoint: AstArenaCheckpoint): Unit {
        arena.rollback(checkpoint)
    }

    /**
     * 追加 parser 已完成的 block quote 节点。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func blockQuote(children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.BlockQuote, NodeCategory.Block, children, span)
    }

    /**
     * 追加有序或无序列表节点，并检查起始编号非负。
     * @param listKind 有序或无序列表类别。
     * @param start 非负的列表起始编号。
     * @param delimiter 列表编号或 marker 的分隔符类别。
     * @param tight 是否采用 tight list 语义。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws IllegalArgumentException start 为负时。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func list(listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool, children: Array<Int64>,
        span: SourceSpan): Int64 {
        if (start < 0) {
            throw IllegalArgumentException("list start must be non-negative")
        }
        parsed(NodeKind.List, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListValue(listKind, start, delimiter, tight))
    }

    /**
     * 追加有序或无序列表节点，并检查起始编号非负。
     * @param listKind 有序或无序列表类别。
     * @param start 非负的列表起始编号。
     * @param delimiter 列表编号或 marker 的分隔符类别。
     * @param tight 是否采用 tight list 语义。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws IllegalArgumentException start 为负时。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func list(listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool,
        children: ArrayList<Int64>, span: SourceSpan): Int64 {
        if (start < 0) {
            throw IllegalArgumentException("list start must be non-negative")
        }
        parsedList(NodeKind.List, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListValue(listKind, start, delimiter, tight))
    }

    /**
     * 追加列表项节点，保存可选 task marker 状态。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @param taskState task list 状态，默认 NotTask。
     * @param markerSpan task marker 的原始字节范围，默认 None。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func listItem(children: Array<Int64>, span: SourceSpan, taskState!: TaskState = TaskState.NotTask,
        markerSpan!: ?SourceSpan = None): Int64 {
        parsed(NodeKind.ListItem, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListItemValue(taskState, markerSpan))
    }

    /**
     * 追加包含已完成 inline 子节点的段落。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func paragraph(children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Paragraph, NodeCategory.Block, children, span)
    }

    /**
     * 追加包含已完成 inline 子节点的段落。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func paragraph(children: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.Paragraph, NodeCategory.Block, children, span)
    }

    /**
     * 追加 1 至 6 级标题，并检查 level 范围。
     * @param level 标题级别，范围为 1 至 6。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws IllegalArgumentException level 不在 1 至 6 时。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func heading(level: Int64, children: Array<Int64>, span: SourceSpan): Int64 {
        if (level < 1 || level > 6) {
            throw IllegalArgumentException("heading level must be 1 through 6")
        }
        parsed(NodeKind.Heading, NodeCategory.Block, children, span, payload: ArenaNodePayload.HeadingValue(level))
    }

    /**
     * 追加保留原始 marker 字节的分隔线节点。
     * @param marker parser 已验证的分隔线 marker 字节。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func thematicBreak(marker: Byte, span: SourceSpan): Int64 {
        parsed(NodeKind.ThematicBreak, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.ThematicBreakValue(marker))
    }

    /**
     * 追加代码块节点，保存 literal、围栏及 info string 信息。
     * @param codeKind 缩进或围栏代码块类别。
     * @param literal 由 parser 已处理的节点 literal 内容。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @param fenceCharacter 可选围栏字节，默认 None。
     * @param fenceLength 围栏长度，默认 0。
     * @param openingFenceSpan 原始 opening fence 范围，默认 None。
     * @param closingFenceSpan 原始 closing fence 范围，默认 None。
     * @param infoRaw 未规范化的 info string，默认空字符串。
     * @param language parser 提取的语言标识，默认空字符串。
     * @param attributesRaw 原始属性文本，默认空字符串。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func codeBlock(codeKind: CodeBlockKind, literal: LiteralStorage, span: SourceSpan,
        fenceCharacter!: ?Byte = None, fenceLength!: Int64 = 0, openingFenceSpan!: ?SourceSpan = None,
        closingFenceSpan!: ?SourceSpan = None, infoRaw!: String = "", language!: String = "",
        attributesRaw!: String = ""): Int64 {
        parsed(NodeKind.CodeBlock, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.CodeBlockValue(codeKind, literal, fenceCharacter, fenceLength, openingFenceSpan,
                closingFenceSpan, infoRaw, language, attributesRaw))
    }

    /**
     * 追加保存 raw HTML literal 和 block 类型的节点，不清理 HTML。
     * @param literal 由 parser 已处理的节点 literal 内容。
     * @param blockType parser 已识别的 HTML block 类型编号。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func htmlBlock(literal: LiteralStorage, blockType: Int64, span: SourceSpan): Int64 {
        parsed(NodeKind.HtmlBlock, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.HtmlBlockValue(literal, blockType))
    }

    /**
     * 追加表格节点，保存列对齐信息与已完成的行。
     * @param alignments 按列顺序排列的对齐方式。
     * @param rows 已在此 factory 中完成且尚未归属其他父节点的行下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func table(alignments: Array<TableAlignment>, rows: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Table, NodeCategory.Block, rows, span,
            payload: ArenaNodePayload.TableValue(ImmutableArray<TableAlignment>(alignments)))
    }

    /**
     * 追加表格节点，保存列对齐信息与已完成的行。
     * @param alignments 按列顺序排列的对齐方式。
     * @param rows 已在此 factory 中完成且尚未归属其他父节点的行下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func table(alignments: Array<TableAlignment>, rows: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.Table, NodeCategory.Block, rows, span,
            payload: ArenaNodePayload.TableValue(ImmutableArray<TableAlignment>(alignments)))
    }

    /**
     * 追加表格行，标记其是否为 header。
     * @param header 该行是否为表头。
     * @param cells 已在此 factory 中完成且尚未归属其他父节点的单元格下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func tableRow(header: Bool, cells: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.TableRow, NodeCategory.Block, cells, span, payload: ArenaNodePayload.TableRowValue(header))
    }

    /**
     * 追加表格行，标记其是否为 header。
     * @param header 该行是否为表头。
     * @param cells 已在此 factory 中完成且尚未归属其他父节点的单元格下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func tableRow(header: Bool, cells: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.TableRow, NodeCategory.Block, cells, span, payload: ArenaNodePayload.TableRowValue(header))
    }

    /**
     * 追加表格单元格，保存对齐方式和 inline 子节点。
     * @param alignment 单元格的列对齐方式。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func tableCell(alignment: TableAlignment, children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.TableCell, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.TableCellValue(alignment))
    }

    /**
     * 追加 custom block 节点及显式 origin，必要时标记后续绑定。
     *
     * Footnote、HeadingId、DefinitionList、Math 和 CodeGroup 内建 payload 将 requiresBinding 置为 true。
     * @param extensionId 提供节点语义的扩展标识。
     * @param extensionSemanticVersion 扩展的语义版本。
     * @param localKindId 扩展内的节点类别标识。
     * @param payload 符合该扩展节点契约的 custom payload。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 可选的原始输入半开字节范围，与显式 origin 保持一致。
     * @param origin 节点的显式来源元数据，其 kind 决定 originKind。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func customBlock(extensionId: String, extensionSemanticVersion: String, localKindId: String,
        payload: CustomPayload, children: Array<Int64>, span: ?SourceSpan, origin: NodeOrigin): Int64 {
        if (payload is FootnoteDefinitionPayload || payload is FootnoteReferencePayload || payload is HeadingIdPayload ||
            payload is DefinitionListPayload || payload is MathPayload || payload is CodeGroupPayload) {
            requiresBinding = true
        }
        arena.appendParserOwned(NodeKind.CustomBlock, NodeCategory.Block, span, origin.kind, children,
            payload: ArenaNodePayload.CustomValue(extensionId, extensionSemanticVersion, localKindId, payload),
            origin: Some(origin))
    }

    /**
     * 追加 raw 与语义值可分别存储的文本节点。
     * @param raw 保留原始拼写的文本存储。
     * @param value 解析后的语义文本存储。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @param normalized 可选的规范化文本缓存，默认 None。
     * @param origin 可选显式 origin，默认由 span 构造 Parsed origin。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func text(raw: LiteralStorage, value: LiteralStorage, span: SourceSpan, normalized!: ?String = None,
        origin!: ?NodeOrigin = None): Int64 {
        match (origin) {
            case Some(valueOrigin) => arena.appendParserOwned(NodeKind.Text, NodeCategory.Inline, Some(span),
                valueOrigin.kind, [], payload: ArenaNodePayload.TextValue(raw, value, normalized),
                origin: Some(valueOrigin))
            case None => parsed(NodeKind.Text, NodeCategory.Inline, [], span,
                payload: ArenaNodePayload.TextValue(raw, value, normalized))
        }
    }

    /**
     * 以 source span 存储未改变的 parser 文本，避免复制 raw 和语义值。
     *
     * 要求构造 factory 时提供 source，且 span 对应未发生语义变换的文本。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func sourceText(span: SourceSpan): Int64 {
        let sourceBuffer = source.getOrThrow()
        let _ = sourceBuffer
        parsed(NodeKind.Text, NodeCategory.Inline, [], span, payload: ArenaNodePayload.TextSourceValue)
    }

    /**
     * 将已有记录替换为 source-backed 文本，保留 NodeId 与 child range。
     *
     * 仅用于 parser 已有文本记录的局部修订，不重新消耗节点分配预算。
     * 要求构造 factory 时提供 source，替换后的 span 对应未改变语义的文本。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     */
    protected func replaceSourceText(index: Int64, span: SourceSpan): Unit {
        let sourceBuffer = source.getOrThrow()
        let _ = sourceBuffer
        arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span), NodeOriginKind.Parsed,
            payload: Some(ArenaNodePayload.TextSourceValue))
    }

    /**
     * 查询记录是否采用 source-backed 文本存储。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return source-backed 文本记录的 span；其他 payload 返回 None。
     */
    protected func sourceTextSpan(index: Int64): ?SourceSpan {
        match (arena.payloadAt(index)) {
            case ArenaNodePayload.TextSourceValue => arena.recordAt(index).span
            case _ => None
        }
    }

    /**
     * 替换已有记录的文本 payload、span 和 origin，保留 NodeId 与 child range。
     *
     * 仅用于 parser 已有文本记录的局部修订，不重新消耗节点分配预算。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @param raw 保留原始拼写的文本存储。
     * @param value 解析后的语义文本存储。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @param normalized 可选的规范化文本缓存，默认 None。
     * @param origin 可选显式 origin，默认由 span 构造 Parsed origin。
     */
    protected func replaceText(index: Int64, raw: LiteralStorage, value: LiteralStorage, span: SourceSpan,
        normalized!: ?String = None, origin!: ?NodeOrigin = None): Unit {
        match (origin) {
            case Some(valueOrigin) => arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span),
                valueOrigin.kind, payload: Some(ArenaNodePayload.TextValue(raw, value, normalized)),
                origin: Some(valueOrigin))
            case None => arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span),
                NodeOriginKind.Parsed, payload: Some(ArenaNodePayload.TextValue(raw, value, normalized)))
        }
    }

    /**
     * 读取文本 payload，对 source-backed 文本按需构造共享 source slice。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 文本的 raw、value 和 normalized 存储；非文本 payload 返回 None。
     */
    protected func textPayload(index: Int64): ?ArenaTextPayload {
        match (arena.payloadAt(index)) {
            case ArenaNodePayload.TextValue(raw, value, normalized) => Some(ArenaTextPayload(raw, value, normalized))
            case ArenaNodePayload.TextSourceValue =>
                let sourceBuffer = source.getOrThrow()
                let span = arena.recordAt(index).span.getOrThrow()
                let storage = LiteralStorage.Slice(sourceBuffer.sourceSlice(span))
                let normalized: ?String = None
                Some(ArenaTextPayload(storage, storage, normalized))
            case _ => None
        }
    }

    /**
     * 读取当前 arena 记录的可选源码范围。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 当前记录的可选 source span。
     */
    protected func span(index: Int64): ?SourceSpan {
        arena.recordAt(index).span
    }

    /**
     * 标记构造过程中可能存在孤立记录，不立即删除该记录。
     *
     * 后续 finishDocument 从根节点计算可达记录，避免重建整棵 AST。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     */
    protected func abandon(index: Int64): Unit {
        let _ = arena.recordAt(index)
        hasOrphans = true
    }

    /**
     * 非空数组使 factory 标记为可能含孤立记录，不逐个删除记录。
     *
     * 调用方保证数组中的下标来自当前 factory；此方法仅探测首个下标是否有效。
     * @param indexes 当前 factory arena 中仍有效的节点物理下标数组。
     */
    protected func abandonAll(indexes: Array<Int64>): Unit {
        if (!indexes.isEmpty()) {
            let _ = arena.recordAt(indexes[0])
            hasOrphans = true
        }
    }

    /**
     * 追加 soft line break 节点。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func softBreak(span: SourceSpan): Int64 {
        parsed(NodeKind.SoftBreak, NodeCategory.Inline, [], span)
    }

    /**
     * 追加保存原始换行语法类别的 hard break 节点。
     * @param syntaxKind hard break 的原始语法类别。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func hardBreak(syntaxKind: HardBreakKind, span: SourceSpan): Int64 {
        parsed(NodeKind.HardBreak, NodeCategory.Inline, [], span, payload: ArenaNodePayload.HardBreakValue(syntaxKind))
    }

    /**
     * 追加保存语义 literal 与原始 delimiter 的 inline code 节点。
     * @param literal 由 parser 已处理的节点 literal 内容。
     * @param delimiterRaw 原始 code span delimiter 拼写。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func codeSpan(literal: String, delimiterRaw: String, span: SourceSpan): Int64 {
        parsed(NodeKind.CodeSpan, NodeCategory.Inline, [], span,
            payload: ArenaNodePayload.CodeSpanValue(literal, delimiterRaw))
    }

    /**
     * 追加 emphasis、strong 或 strikethrough 容器，拒绝其他 NodeKind。
     * @param kind Emphasis、Strong 或 Strikethrough。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws IllegalArgumentException kind 不是受支持的 inline 容器时。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func inlineContainer(kind: NodeKind, children: Array<Int64>, span: SourceSpan): Int64 {
        match (kind) {
            case NodeKind.Emphasis => parsed(kind, NodeCategory.Inline, children, span)
            case NodeKind.Strong => parsed(kind, NodeCategory.Inline, children, span)
            case NodeKind.Strikethrough => parsed(kind, NodeCategory.Inline, children, span)
            case _ => throw IllegalArgumentException("node kind is not an inline container")
        }
    }

    /**
     * 追加保存 raw 与解码后 destination、title 的链接，不执行安全 URI 过滤。
     * @param destinationRaw destination 的原始拼写。
     * @param destination parser 解码后的 destination，安全策略由后续 renderer 应用。
     * @param titleRaw title 的原始拼写。
     * @param title parser 解码后的 title。
     * @param syntaxKind hard break 的原始语法类别。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func link(destinationRaw: String, destination: String, titleRaw: String, title: String,
        syntaxKind: LinkSyntaxKind, children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Link, NodeCategory.Inline, children, span,
            payload: ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind))
    }

    /**
     * 追加保存 raw 与解码后 destination、title 的图片，不执行安全 URI 过滤。
     * @param destinationRaw destination 的原始拼写。
     * @param destination parser 解码后的 destination，安全策略由后续 renderer 应用。
     * @param titleRaw title 的原始拼写。
     * @param title parser 解码后的 title。
     * @param syntaxKind hard break 的原始语法类别。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func image(destinationRaw: String, destination: String, titleRaw: String, title: String,
        syntaxKind: LinkSyntaxKind, children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Image, NodeCategory.Inline, children, span,
            payload: ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind))
    }

    /**
     * 追加 raw inline HTML 节点，不清理或转义内容。
     * @param literal 由 parser 已处理的节点 literal 内容。
     * @param span 节点在原始输入中的半开 UTF-8 字节范围，调用方保证与源码及子节点一致。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func htmlInline(literal: String, span: SourceSpan): Int64 {
        parsed(NodeKind.HtmlInline, NodeCategory.Inline, [], span, payload: ArenaNodePayload.HtmlInlineValue(literal))
    }

    /**
     * 追加 custom inline 节点及显式 origin，必要时标记后续绑定。
     *
     * Footnote、HeadingId、DefinitionList、Math 和 CodeGroup 内建 payload 将 requiresBinding 置为 true。
     * @param extensionId 提供节点语义的扩展标识。
     * @param extensionSemanticVersion 扩展的语义版本。
     * @param localKindId 扩展内的节点类别标识。
     * @param payload 符合该扩展节点契约的 custom payload。
     * @param children 按源码顺序排列、已在此 factory 中完成且尚未挂接到其他父节点的子节点物理下标。
     * @param span 可选的原始输入半开字节范围，与显式 origin 保持一致。
     * @param origin 节点的显式来源元数据，其 kind 决定 originKind。
     * @return 新节点在当前 factory arena 中的物理下标，不是 NodeId。
     * @throws LimitExceededException 追加节点超过 maximumAstNodes 或构造预算耗尽时。
     */
    protected func customInline(extensionId: String, extensionSemanticVersion: String, localKindId: String,
        payload: CustomPayload, children: Array<Int64>, span: ?SourceSpan, origin: NodeOrigin): Int64 {
        if (payload is FootnoteDefinitionPayload || payload is FootnoteReferencePayload || payload is HeadingIdPayload ||
            payload is DefinitionListPayload || payload is MathPayload || payload is CodeGroupPayload) {
            requiresBinding = true
        }
        arena.appendParserOwned(NodeKind.CustomInline, NodeCategory.Inline, span, origin.kind, children,
            payload: ArenaNodePayload.CustomValue(extensionId, extensionSemanticVersion, localKindId, payload),
            origin: Some(origin))
    }

    /**
     * 通过新建只读 arena 视图取得暂态子树的 NodeRef。
     *
     * 供扩展 parser callback 观察已完成子树，不代表 parser 已生成完整文档。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 绑定新预览 revision 的 NodeRef，不能作为另一 Document 的引用使用。
     */
    protected func snapshotNode(index: Int64): NodeRef {
        let snapshot = arena.snapshotView()
        snapshot.nodeAt(index)
    }

    /**
     * 在同一个新建只读 arena 视图中取得多个 NodeRef。
     *
     * 供扩展 parser callback 观察已完成子树，不代表 parser 已生成完整文档。
     * @param indexes 当前 factory arena 中仍有效的节点物理下标数组。
     * @return 按 indexes 顺序返回的 NodeRef 数组，全部绑定同一个预览 revision。
     */
    protected func snapshotNodes(indexes: Array<Int64>): Array<NodeRef> {
        let snapshot = arena.snapshotView()
        Array<NodeRef>(indexes.size) {index => snapshot.nodeAt(indexes[index])}
    }

    /**
     * 读取暂态 parser 子树的记录头，不创建 Document snapshot。
     *
     * 调用方必须在下一次 rollback 之前完成依赖这些下标的读取。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 当前节点记录头，仅供本次暂态事件 lowering 读取。
     */
    protected func eventRecord(index: Int64): ArenaNodeRecord {
        arena.recordAt(index)
    }

    /**
     * 读取暂态节点 payload，不创建 Document snapshot。
     *
     * 调用方必须在下一次 rollback 之前完成依赖这些下标的读取。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 当前记录的 payload。
     */
    protected func eventPayload(index: Int64): ArenaNodePayload {
        arena.payloadAt(index)
    }

    /**
     * 按 child arena 位置读取子节点物理下标。
     *
     * index 是 child arena 下标，不是节点下标，通常由 record.firstChild 加 child offset 得到。
     * @param index 当前 child arena 中的有效位置，不是节点物理下标。
     * @return child arena 中对应位置保存的节点物理下标。
     */
    protected func eventChildIndex(index: Int64): Int64 {
        arena.childIndexAt(index)
    }

    /**
     * 按原始字节范围读取 factory 绑定的 source 文本。
     * @param span 原始输入中的有效半开字节范围；factory 必须绑定 source。
     * @return 范围内的解码文本。
     */
    protected func eventSourceText(span: SourceSpan): String {
        source.getOrThrow().slice(span)
    }

    /**
     * 迭代遍历已完成的暂态子树，检查是否包含 Link 节点。
     * @param index 当前 factory arena 中仍有效的节点物理下标。
     * @return 子树中存在 Link 时为 true；Image 不算 Link。
     */
    protected func containsLink(index: Int64): Bool {
        let stack = ArrayList<Int64>()
        stack.add(index)
        while (!stack.isEmpty()) {
            let current = stack.remove(at: stack.size - 1)
            let record = arena.recordAt(current)
            match (record.kind) {
                case NodeKind.Link => return true
                case _ => ()
            }
            var childOffset: Int64 = 0
            while (childOffset < record.childCount) {
                stack.add(arena.childIndexAt(record.firstChild + childOffset))
                childOffset++
            }
        }
        false
    }

    private func parsed(kind: NodeKind, category: NodeCategory, children: Array<Int64>, span: SourceSpan,
        payload!: ArenaNodePayload = ArenaNodePayload.Empty): Int64 {
        arena.appendParserOwned(kind, category, Some(span), NodeOriginKind.Parsed, children, payload: payload)
    }

    private func parsedList(kind: NodeKind, category: NodeCategory, children: ArrayList<Int64>, span: SourceSpan,
        payload!: ArenaNodePayload = ArenaNodePayload.Empty): Int64 {
        arena.appendParserOwnedList(kind, category, Some(span), NodeOriginKind.Parsed, children, payload: payload)
    }
}

/**
 * parser 文本节点的 raw、语义值和可选规范化缓存存储。
 */
protected struct ArenaTextPayload {
    /**
     * 保留文本原始拼写的存储，可引用 source slice。
     */
    protected let rawStorage: LiteralStorage
    /**
     * 解析后的语义文本存储，可与 rawStorage 共享。
     */
    protected let valueStorage: LiteralStorage
    /**
     * 可选规范化文本缓存，None 表示未提供缓存。
     */
    protected let normalized: ?String

    /**
     * 保存文本的两种存储和可选规范化缓存，不复制存储所引用的源码。
     * @param rawStorage 保留原始拼写的文本存储。
     * @param valueStorage 解析后的语义文本存储。
     * @param normalized 可选的规范化文本缓存，不在此处计算。
     */
    protected init(rawStorage: LiteralStorage, valueStorage: LiteralStorage, normalized: ?String) {
        this.rawStorage = rawStorage
        this.valueStorage = valueStorage
        this.normalized = normalized
    }
}
