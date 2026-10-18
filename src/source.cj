package markdown

import std.collection.*

/** 原始输入中的 UTF-8 byte offset。 */
public struct SourceOffset <: Equatable<SourceOffset> {
    /** 原始输入中的 UTF-8 byte offset 值。 */
    public let byteOffset: Int64

    /**
     * 创建 offset；负值抛出 `IllegalArgumentException`。
     * @param byteOffset 原始输入中的 UTF-8 byte offset。
     */
    public init(byteOffset: Int64) {
        if (byteOffset < 0) {
            throw IllegalArgumentException("source offset must be non-negative")
        }
        this.byteOffset = byteOffset
    }

    /** 按字节值比较两个 offset。
     * @param other 参与比较的另一个 offset。
     * @return 两个 offset 字节值是否相等。
     */
    public operator func ==(other: SourceOffset): Bool {
        byteOffset == other.byteOffset
    }
}

/** 原始输入中的半开 UTF-8 byte range `[startByte, endByte)`。 */
public struct SourceSpan <: Equatable<SourceSpan> {
    /** span 起始 byte（含）。 */
    public let startByte: Int64
    /** span 结束 byte（不含）。 */
    public let endByte: Int64

    /**
     * 创建 span；区间非法时抛出 `IllegalArgumentException`。
     * @param startByte span 起始 byte（含）。
     * @param endByte span 结束 byte（不含）。
     */
    public init(startByte: Int64, endByte: Int64) {
        if (startByte < 0 || endByte < startByte) {
            throw IllegalArgumentException("source span must be a non-negative half-open interval")
        }
        this.startByte = startByte
        this.endByte = endByte
    }

    /**
     * 返回 span 的 byte 长度。
     * @return span 的 byte 长度。
     */
    public func length(): Int64 {
        endByte - startByte
    }

    /**
     * 返回起止位置是否相同。
     * @return 起止位置相同时为 `true`。
     */
    public func isEmpty(): Bool {
        startByte == endByte
    }

    /** 判断 offset 是否落在半开 span 内。
     * @param offset 待判断的 offset。
     * @return offset 落在 span 内时为 `true`。
     */
    public func contains(offset: SourceOffset): Bool {
        offset.byteOffset >= startByte && offset.byteOffset < endByte
    }

    /** 判断另一个 span 是否完全包含于当前 span。
     * @param other 待判断的 span。
     * @return other 完全包含于当前 span 时为 `true`。
     */
    public func containsSpan(other: SourceSpan): Bool {
        other.startByte >= startByte && other.endByte <= endByte
    }

    /** 按起止字节比较两个 span。
     * @param other 参与比较的另一个 span。
     * @return 两个 span 起止是否相同。
     */
    public operator func ==(other: SourceSpan): Bool {
        startByte == other.startByte && endByte == other.endByte
    }
}

/** 一基的行号和 UTF-8 byte column。 */
public struct SourcePosition <: Equatable<SourcePosition> {
    /** 一基行号。 */
    public let line: Int64
    /** 一基 UTF-8 byte column。 */
    public let byteColumn: Int64

    /**
     * 创建 position；参数小于 1 时抛出 `IllegalArgumentException`。
     * @param line 一基行号。
     * @param byteColumn 一基 UTF-8 byte column。
     */
    public init(line: Int64, byteColumn: Int64) {
        if (line < 1 || byteColumn < 1) {
            throw IllegalArgumentException("source positions are one-based")
        }
        this.line = line
        this.byteColumn = byteColumn
    }

    /** 按行号和列比较两个 position。
     * @param other 参与比较的另一个 position。
     * @return 两个位置是否相等。
     */
    public operator func ==(other: SourcePosition): Bool {
        line == other.line && byteColumn == other.byteColumn
    }
}

/** 一基的行号和显示列。 */
public struct VisualPosition <: Equatable<VisualPosition> {
    /** 一基行号。 */
    public let line: Int64
    /** 一基显示列。 */
    public let visualColumn: Int64

    /**
     * 创建 position；参数小于 1 时抛出 `IllegalArgumentException`。
     * @param line 一基行号。
     * @param visualColumn 一基显示列。
     */
    public init(line: Int64, visualColumn: Int64) {
        if (line < 1 || visualColumn < 1) {
            throw IllegalArgumentException("visual positions are one-based")
        }
        this.line = line
        this.visualColumn = visualColumn
    }

    /** 按行号和显示列比较两个 position。
     * @param other 参与比较的另一个 position。
     * @return 两个位置是否相等。
     */
    public operator func ==(other: VisualPosition): Bool {
        line == other.line && visualColumn == other.visualColumn
    }
}

/** LSP 风格的零基行号和 UTF-16 code-unit character。 */
public struct Utf16Position <: Equatable<Utf16Position> {
    /** 零基行号。 */
    public let line: Int64
    /** 零基 UTF-16 code-unit character。 */
    public let character: Int64

    /**
     * 创建 position；参数为负时抛出 `IllegalArgumentException`。
     * @param line 零基行号。
     * @param character 零基 UTF-16 code-unit character。
     */
    public init(line: Int64, character: Int64) {
        if (line < 0 || character < 0) {
            throw IllegalArgumentException("UTF-16 positions must be non-negative")
        }
        this.line = line
        this.character = character
    }

    /** 按行号和 character 比较两个 position。
     * @param other 参与比较的另一个 position。
     * @return 两个位置是否相等。
     */
    public operator func ==(other: Utf16Position): Bool {
        line == other.line && character == other.character
    }
}

/** 对外暴露的位置编码。 */
public enum PositionEncoding {
    /** 一基 UTF-8 byte 位置。 */
    | Utf8Byte
    /** LSP 风格零基 UTF-16 位置。 */
    | Utf16CodeUnit
    /** 一基 visual 位置。 */
    | Visual
}

/** visual column 的 Unicode scalar 和 tab 计算策略。 */
public enum DisplayWidthPolicy {
    // Every Unicode scalar, including tab, advances one column.
    /** 每个 Unicode scalar（含 tab）前进一列。 */
    | UnicodeScalar
    // Every Unicode scalar advances one column and tab advances to tabStop.
    /** 每个 scalar 前进一列，tab 前进到下一个 tab stop。 */
    | UnicodeScalarWithTabStops
}

/**
 * 一次性 UTF-8 输入所有权容器。
 *
 * `take` 是 unsafe factory：调用方必须保证 bytes 已是有效 UTF-8，并放弃所有
 * mutable alias；输入只允许被 engine 消费一次。
 */
public class OwnedUtf8Input {
    private var bytes: ?Array<Byte>
    private init(bytes: Array<Byte>) {
        this.bytes = Some(bytes)
    }

    /** 转移唯一 bytes 所有权；调用方不得在返回后保留或修改 alias。
     * @param bytes 已确认为有效 UTF-8 的字节序列。
     * @return 持有唯一所有权的输入容器。
     */
    public static unsafe func take(bytes: Array<Byte>): OwnedUtf8Input {
        OwnedUtf8Input(bytes)
    }

    internal func consume(): Array<Byte> {
        match (bytes) {
            case Some(value) =>
                bytes = None
                value
            case None => throw IllegalStateException("owned UTF-8 input was already consumed")
        }
    }
}

/**
 * 可重复使用的不可变 UTF-8 输入。
 *
 * 普通构造会防御性复制并校验 bytes；unsafe `take` 在调用方保证有效 UTF-8 且放弃
 * mutable alias 时避免复制。
 */
public class ReusableUtf8Input {
    private let value: String
    private let bytes: Array<Byte>

    /**
     * 防御性复制并校验 bytes 构造输入。
     * @param bytes 待复制的 UTF-8 字节序列。
     */
    public init(bytes: Array<Byte>) {
        let owned = bytes.clone()
        value = String.fromUtf8(owned)
        this.bytes = owned
    }

    private init(value: String, bytes: Array<Byte>) {
        this.value = value
        this.bytes = bytes
    }

    /** 转移唯一 bytes 所有权，之后可被多次 parse。
     * @param bytes 已确认为有效 UTF-8 的字节序列。
     * @return 可重复解析的输入。
     */
    public static unsafe func take(bytes: Array<Byte>): ReusableUtf8Input {
        ReusableUtf8Input(String.withRawData(bytes), bytes)
    }

    internal func byteLength(): Int64 {
        bytes.size
    }

    internal func sourceBuffer(): SourceBuffer {
        SourceBuffer(value, bytes, true)
    }
}

/**
 * 与 parse result 绑定的 source 文本和原始 byte 映射。
 *
 * `slice`、位置转换和 `sourceSlice` 都以原始 UTF-8 byte offset 为边界；非法 UTF-8
 * 被替换时，只有 decoded boundary 才能创建 slice。
 */
public class SourceBuffer {
    private let value: String
    private let decodedBytes: Array<Byte>
    private let originalBytes: Array<Byte>
    private let decodedToOriginal: Array<Int64>
    private let mappingIsIdentity: Bool
    private let valueBackedIdentity: Bool
    private let utf8Policy: Utf8Policy

    /**
     * 从文本构造 identity-mapped 的 source buffer。
     * @param value 解码后的源文本。
     */
    public init(value: String) {
        this.value = value
        this.decodedBytes = []
        this.originalBytes = []
        this.decodedToOriginal = []
        this.mappingIsIdentity = true
        this.valueBackedIdentity = true
        this.utf8Policy = Utf8Policy.Strict
    }

    internal init(value: String, originalBytes: Array<Byte>, decodedToOriginal: Array<Int64>,
        utf8Policy!: Utf8Policy = Utf8Policy.ReplaceInvalid) {
        let decoded = value.toArray()
        if (decodedToOriginal.size != decoded.size + 1) {
            throw IllegalArgumentException("decoded-to-original map has invalid size")
        }
        if (decodedToOriginal[decodedToOriginal.size - 1] != originalBytes.size) {
            throw IllegalArgumentException("decoded-to-original map does not end at original input length")
        }
        var identity = originalBytes.size == decoded.size
        if (identity) {
            for (index in 0..decodedToOriginal.size) {
                if (decodedToOriginal[index] != index) {
                    identity = false
                    break
                }
            }
        }
        this.value = value
        this.decodedBytes = decoded
        this.originalBytes = originalBytes.clone()
        this.decodedToOriginal = if (identity) {
            []
        } else {
            decodedToOriginal.clone()
        }
        this.mappingIsIdentity = identity
        this.valueBackedIdentity = false
        this.utf8Policy = utf8Policy
    }

    internal init(value: String, originalBytes: Array<Byte>, utf8Policy!: Utf8Policy = Utf8Policy.Strict) {
        let decoded = value.toArray()
        if (decoded.size != originalBytes.size) {
            throw IllegalArgumentException("identity source buffer requires equal decoded/original lengths")
        }
        this.value = value
        this.decodedBytes = decoded
        this.originalBytes = originalBytes.clone()
        this.decodedToOriginal = []
        this.mappingIsIdentity = true
        this.valueBackedIdentity = false
        this.utf8Policy = utf8Policy
    }

    internal init(value: String, ownedBytes: Array<Byte>, takeOwnership: Bool) {
        if (!takeOwnership || value.size != ownedBytes.size) {
            throw IllegalArgumentException("owned source buffer requires identity UTF-8 bytes")
        }
        this.value = value
        this.decodedBytes = ownedBytes
        this.originalBytes = ownedBytes
        this.decodedToOriginal = []
        this.mappingIsIdentity = true
        this.valueBackedIdentity = false
        this.utf8Policy = Utf8Policy.Strict
    }

    /**
     * 返回原始输入的 byte 长度。
     * @return 原始输入的字节长度。
     */
    public func byteLength(): Int64 {
        originalLength()
    }

    /**
     * 返回完整解码文本。
     * @return 完整源文本。
     */
    public func text(): String {
        value
    }

    internal func decodedBytesForNative(): ?Array<Byte> {
        if (valueBackedIdentity) {
            None
        } else {
            Some(decodedBytes)
        }
    }

    internal func hasIdentityMapping(): Bool {
        mappingIsIdentity
    }

    internal func decodePolicy(): Utf8Policy {
        utf8Policy
    }

    internal func originalBytesForArtifact(): Array<Byte> {
        if (!mappingIsIdentity) {
            throw IllegalStateException("artifact bytes require an identity source mapping")
        }
        if (valueBackedIdentity) {
            value.toArray()
        } else {
            originalBytes.clone()
        }
    }

    /** 返回 span 对应文本；span 必须在 source 内且落在解码边界。
     * @param span 目标 source span。
     * @return span 对应文本。
     * @throws IllegalArgumentException span 越界或未落在解码边界时。
     */
    public func slice(span: SourceSpan): String {
        ensureSpan(span)
        if (mappingIsIdentity) {
            return value[span.startByte..span.endByte]
        }
        let start = decodedOffset(span.startByte)
        let end = decodedOffset(span.endByte)
        String.fromUtf8(decodedBytes.slice(start, end - start))
    }

    /** 返回节点 source span 对应文本；无 span 的节点会失败。
     * @param node 目标节点。
     * @return 节点 span 对应文本。
     * @throws IllegalArgumentException 节点无 span 或 span 越界时。
     */
    public func text(node: NodeRef): String {
        match (node.span) {
            case Some(span) => slice(span)
            case None => throw IllegalArgumentException("node has no source span")
        }
    }

    /** 返回 document root 的 source 文本。
     * @param document 目标 Document。
     * @return document root 的源文本。
     */
    public func text(document: Document): String {
        text(document.root())
    }

    /** 创建延迟读取的 `SourceSlice`，并立即校验 span。
     * @param span 目标 source span。
     * @return 延迟文本视图。
     * @throws IllegalArgumentException span 越界或未落在解码边界时。
     */
    public func sourceSlice(span: SourceSpan): SourceSlice {
        validateSliceSpan(span)
        SourceSlice(this, span)
    }

    internal func validateSliceSpan(span: SourceSpan): Unit {
        ensureSpan(span)
        // A slice must also end on decoded boundaries when invalid UTF-8 was
        // replaced and original/decoded offsets are not identical.
        decodedOffset(span.startByte)
        decodedOffset(span.endByte)
    }

    /** 返回一基行号对应的文本，不含行结束符。
     * @param lineNumber 一基行号。
     * @return 该行文本（不含行结束符）。
     * @throws IllegalArgumentException 行号小于 1 时。
     */
    public func line(lineNumber: Int64): String {
        if (lineNumber < 1) {
            throw IllegalArgumentException("line number must be one-based")
        }
        var current: Int64 = 1
        var start: Int64 = 0
        var index: Int64 = 0
        while (index < originalLength()) {
            let byte = originalByte(index)
            if (byte == 10 || byte == 13) {
                if (current == lineNumber) {
                    let decodedStart = decodedOffset(start)
                    let decodedEnd = decodedOffset(index)
                    return decodedSlice(decodedStart, decodedEnd)
                }
                if (byte == 13 && index + 1 < originalLength() && originalByte(index + 1) == 10) {
                    index++
                }
                current++
                start = index + 1
            }
            index++
        }
        if (current == lineNumber) {
            let decodedStart = decodedOffset(start)
            return decodedSlice(decodedStart, decodedLength())
        }
        throw IllegalArgumentException("line number is outside source")
    }

    /**
     * 返回 source 行数；空 source 也有一行。
     * @return 输入行数。
     */
    public func lineCount(): Int64 {
        var count: Int64 = 1
        var index: Int64 = 0
        while (index < originalLength()) {
            if (originalByte(index) == 10 || originalByte(index) == 13) {
                if (originalByte(index) == 13 && index + 1 < originalLength() && originalByte(index + 1) == 10) {
                    index++
                }
                count++
            }
            index++
        }
        count
    }

    /** 将原始 byte offset 转为一基 UTF-8 byte 位置。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 一基 UTF-8 byte 位置。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func position(byteOffset: Int64): SourcePosition {
        ensureOffset(byteOffset)
        var line: Int64 = 1
        var column: Int64 = 1
        var index: Int64 = 0
        while (index < byteOffset) {
            if (originalByte(index) == 13) {
                if (index + 1 < byteOffset && originalByte(index + 1) == 10) {
                    index++
                }
                line++
                column = 1
            } else if (originalByte(index) == 10) {
                line++
                column = 1
            } else {
                column++
            }
            index++
        }
        SourcePosition(line, column)
    }

    /** 将原始 byte offset 转为零基 UTF-16 位置。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 零基 UTF-16 位置。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func utf16Position(byteOffset: Int64): Utf16Position {
        ensureOffset(byteOffset)
        let decodedLimit = decodedOffset(byteOffset)
        var line: Int64 = 0
        var character: Int64 = 0
        var index: Int64 = 0
        while (index < decodedLimit) {
            if (decodedByte(index) == 13) {
                if (index + 1 < decodedLimit) {
                    if (decodedByte(index + 1) == 10) {
                        index++
                    }
                }
                line++
                character = 0
                index++
                continue
            }
            if (decodedByte(index) == 10) {
                line++
                character = 0
                index++
                continue
            }
            let width = utf8Width(decodedByte(index))
            if (index + width > decodedLimit) {
                throw IllegalArgumentException("byte offset is not on a UTF-8 boundary")
            }
            character += if (width == 4) {
                2
            } else {
                1
            }
            index += width
        }
        Utf16Position(line, character)
    }

    /** 将原始 byte offset 转为一基 visual position；tabStop 默认是 4。
     * @param byteOffset 原始输入中的字节偏移。
     * @param tabStop tab 展开宽度，必须为正。
     * @return 一基 visual 位置。
     * @throws IllegalArgumentException offset 越界或 tabStop 非正时。
     */
    public func visualPosition(byteOffset: Int64, tabStop!: Int64 = 4): VisualPosition {
        if (tabStop <= 0) {
            throw IllegalArgumentException("tab stop must be positive")
        }
        ensureOffset(byteOffset)
        let decodedLimit = decodedOffset(byteOffset)
        var line: Int64 = 1
        var column: Int64 = 1
        var index: Int64 = 0
        while (index < decodedLimit) {
            if (decodedByte(index) == 13) {
                if (index + 1 < decodedLimit) {
                    if (decodedByte(index + 1) == 10) {
                        index++
                    }
                }
                line++;
                column = 1
                index++;
                continue
            }
            if (decodedByte(index) == 10) {
                line++;
                column = 1
                index++;
                continue
            }
            if (decodedByte(index) == b'\t') {
                column += tabStop - ((column - 1) % tabStop)
                index++
                continue
            }
            let width = utf8Width(decodedByte(index))
            column++
            index += width
        }
        VisualPosition(line, column)
    }

    /** 将 UTF-16 位置转回原始 byte offset；位于 surrogate pair 中间会失败。
     * @param position 目标 UTF-16 位置。
     * @return 对应的原始 byte offset。
     * @throws IllegalArgumentException 位置越界或拆分 surrogate pair 时。
     */
    public func byteOffset(position: Utf16Position): Int64 {
        var line: Int64 = 0
        var character: Int64 = 0
        var decoded: Int64 = 0
        while (decoded < decodedLength()) {
            if (line == position.line && character == position.character) {
                return originalOffset(decoded)
            }
            if (decodedByte(decoded) == 13) {
                if (decoded + 1 < decodedLength()) {
                    if (decodedByte(decoded + 1) == 10) {
                        decoded++
                    }
                }
                line++;
                character = 0
                decoded++;
                continue
            }
            if (decodedByte(decoded) == 10) {
                line++;
                character = 0
                decoded++;
                continue
            }
            let width = utf8Width(decodedByte(decoded))
            let units: Int64 = if (width == 4) {
                2
            } else {
                1
            }
            if (line == position.line && character + units > position.character) {
                throw IllegalArgumentException("UTF-16 position splits a surrogate pair")
            }
            character += units
            decoded += width
        }
        if (line == position.line && character == position.character) {
            return originalOffset(decoded)
        }
        throw IllegalArgumentException("UTF-16 position is outside source")
    }

    private func ensureSpan(span: SourceSpan): Unit {
        if (span.endByte > originalLength()) {
            throw IllegalArgumentException("source span is outside source")
        }
    }

    private func ensureOffset(byteOffset: Int64): Unit {
        if (byteOffset < 0 || byteOffset > originalLength()) {
            throw IllegalArgumentException("byte offset is outside source")
        }
    }

    internal func originalOffset(decodedOffset: Int64): Int64 {
        let length = decodedLength()
        if (decodedOffset < 0 || decodedOffset > length) {
            throw IllegalArgumentException("decoded byte offset is outside source")
        }
        if (mappingIsIdentity) {
            return decodedOffset
        }
        decodedToOriginal[decodedOffset]
    }

    internal func matches(span: SourceSpan, candidate: String): Bool {
        ensureSpan(span)
        if (mappingIsIdentity) {
            if (span.length() != candidate.size) {
                return false
            }
            return value[span.startByte..span.endByte] == candidate
        }
        let start = decodedOffset(span.startByte)
        let end = decodedOffset(span.endByte)
        if (end - start != candidate.size) {
            return false
        }
        var index: Int64 = 0
        while (index < candidate.size) {
            if (decodedBytes[start + index] != candidate[index]) {
                return false
            }
            index++
        }
        true
    }

    internal func decodedOffset(originalOffset: Int64): Int64 {
        ensureOffset(originalOffset)
        if (mappingIsIdentity) {
            return originalOffset
        }
        var low: Int64 = 0
        var high = decodedToOriginal.size
        while (low < high) {
            let middle = low + (high - low) / 2
            if (decodedToOriginal[middle] < originalOffset) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if (low < decodedToOriginal.size && decodedToOriginal[low] == originalOffset) {
            return low
        }
        throw IllegalArgumentException("original byte offset is not on a decoded boundary")
    }

    internal func originalLength(): Int64 {
        if (valueBackedIdentity) {
            value.size
        } else {
            originalBytes.size
        }
    }

    internal func decodedLength(): Int64 {
        if (valueBackedIdentity) {
            value.size
        } else {
            decodedBytes.size
        }
    }

    internal func originalByte(index: Int64): Byte {
        if (valueBackedIdentity) {
            value[index]
        } else {
            originalBytes[index]
        }
    }

    internal func decodedByte(index: Int64): Byte {
        if (valueBackedIdentity) {
            value[index]
        } else {
            decodedBytes[index]
        }
    }

    private func decodedSlice(start: Int64, end: Int64): String {
        if (valueBackedIdentity) {
            value[start..end]
        } else {
            String.fromUtf8(decodedBytes.slice(start, end - start))
        }
    }
}

private func utf8Width(first: Byte): Int64 {
    if (first < 0x80) {
        1
    } else if ((first & 0xE0) == 0xC0) {
        2
    } else if ((first & 0xF0) == 0xE0) {
        3
    } else {
        4
    }
}

/** 绑定 source buffer 和 span 的延迟文本视图。 */
public class SourceSlice {
    /** 绑定的 source buffer。 */
    public let source: SourceBuffer
    /** 绑定的 source span。 */
    public let span: SourceSpan

    /**
     * 创建延迟文本视图并立即校验 span。
     * @param source 绑定的 source buffer。
     * @param span 绑定的 source span。
     */
    public init(source: SourceBuffer, span: SourceSpan) {
        // Validate eagerly so a SourceSlice is always safe to read.
        source.validateSliceSpan(span)
        this.source = source
        this.span = span
    }

    /**
     * 读取 slice 文本。
     * @return slice 文本。
     */
    public func text(): String {
        source.slice(span)
    }
    /**
     * 读取并返回独立 String。
     * @return 独立 String 副本。
     */
    public func detach(): String {
        text()
    }
}

/** AST literal 的复制存储或 source-backed 延迟存储。 */
public enum LiteralStorage {
    /** 复制存储：携带独立 String。 */
    | Copy(String)
    /** 延迟存储：按 span 从 source 读取。 */
    | Slice(SourceSlice)
}

extend LiteralStorage {
    /**
     * 读取当前 literal 文本。
     * @return literal 文本。
     */
    public func text(): String {
        match (this) {
            case LiteralStorage.Copy(value) => value
            case LiteralStorage.Slice(value) => value.text()
        }
    }

    /**
     * 将当前 literal 转为独立的 `Copy` 存储。
     * @return 独立的 `Copy` 存储。
     */
    public func detach(): LiteralStorage {
        LiteralStorage.Copy(text())
    }
}

internal class SourceIndex {
    internal let originalLineStarts: Array<Int64>
    internal let originalContentStarts: Array<Int64>
    internal let decodedLineStarts: Array<Int64>
    internal let decodedContentStarts: Array<Int64>
    internal let decodedLineEnds: Array<Int64>
    internal let checkpointsByLine: Array<Array<SourceCheckpoint>>

    internal init(source: SourceBuffer, tabStop: Int64, displayWidthPolicy: DisplayWidthPolicy) {
        let originalStarts = ArrayList<Int64>()
        let originalContent = ArrayList<Int64>()
        originalStarts.add(0)
        originalContent.add(0)
        var original: Int64 = 0
        while (original < source.originalLength()) {
            if (source.originalByte(original) == 13) {
                originalStarts.add(original + 1)
                if (original + 1 < source.originalLength() && source.originalByte(original + 1) == 10) {
                    originalContent.add(original + 2)
                    original++
                } else {
                    originalContent.add(original + 1)
                }
            } else if (source.originalByte(original) == 10) {
                originalStarts.add(original + 1)
                originalContent.add(original + 1)
            }
            original++
        }
        originalLineStarts = originalStarts.toArray()
        originalContentStarts = originalContent.toArray()

        let decodedStarts = ArrayList<Int64>()
        let decodedContent = ArrayList<Int64>()
        let decodedEnds = ArrayList<Int64>()
        decodedStarts.add(0)
        decodedContent.add(0)
        var decoded: Int64 = 0
        while (decoded < source.decodedLength()) {
            if (source.decodedByte(decoded) == 13) {
                decodedEnds.add(decoded)
                decodedStarts.add(decoded + 1)
                if (decoded + 1 < source.decodedLength() && source.decodedByte(decoded + 1) == 10) {
                    decodedContent.add(decoded + 2)
                    decoded++
                } else {
                    decodedContent.add(decoded + 1)
                }
            } else if (source.decodedByte(decoded) == 10) {
                decodedEnds.add(decoded)
                decodedStarts.add(decoded + 1)
                decodedContent.add(decoded + 1)
            }
            decoded++
        }
        decodedEnds.add(source.decodedLength())
        decodedLineStarts = decodedStarts.toArray()
        decodedContentStarts = decodedContent.toArray()
        decodedLineEnds = decodedEnds.toArray()

        let lineCheckpoints = ArrayList<Array<SourceCheckpoint>>()
        for (line in 0..decodedLineStarts.size) {
            let checkpoints = ArrayList<SourceCheckpoint>()
            var current = decodedContentStarts[line]
            let end = decodedLineEnds[line]
            var utf16Units: Int64 = 0
            var visualColumn: Int64 = 1
            var checkpointOffset = current
            checkpoints.add(SourceCheckpoint(current, utf16Units, visualColumn))
            while (current < end) {
                if (source.decodedByte(current) == b'\t' && expandsTabs(displayWidthPolicy)) {
                    visualColumn += tabStop - ((visualColumn - 1) % tabStop)
                    current++
                    utf16Units++
                } else {
                    let width = utf8Width(source.decodedByte(current))
                    utf16Units += if (width == 4) {
                        2
                    } else {
                        1
                    }
                    visualColumn++
                    current += width
                }
                if (current - checkpointOffset >= 64) {
                    checkpoints.add(SourceCheckpoint(current, utf16Units, visualColumn))
                    checkpointOffset = current
                }
            }
            if (checkpoints[checkpoints.size - 1].decodedOffset != end) {
                checkpoints.add(SourceCheckpoint(end, utf16Units, visualColumn))
            }
            lineCheckpoints.add(checkpoints.toArray())
        }
        checkpointsByLine = lineCheckpoints.toArray()
    }

    internal func originalLine(byteOffset: Int64): Int64 {
        lineAt(originalLineStarts, byteOffset)
    }

    internal func decodedLine(decodedOffset: Int64): Int64 {
        lineAt(decodedLineStarts, decodedOffset)
    }

    internal func checkpointAt(line: Int64, decodedOffset: Int64): SourceCheckpoint {
        let checkpoints = checkpointsByLine[line]
        var low: Int64 = 0
        var high = checkpoints.size
        while (low < high) {
            let middle = low + (high - low) / 2
            if (checkpoints[middle].decodedOffset <= decodedOffset) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        checkpoints[low - 1]
    }

    internal func checkpointAtUtf16(line: Int64, character: Int64): SourceCheckpoint {
        let checkpoints = checkpointsByLine[line]
        var low: Int64 = 0
        var high = checkpoints.size
        while (low < high) {
            let middle = low + (high - low) / 2
            if (checkpoints[middle].utf16Units <= character) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        checkpoints[low - 1]
    }

    private func lineAt(starts: Array<Int64>, offset: Int64): Int64 {
        var low: Int64 = 0
        var high = starts.size
        while (low < high) {
            let middle = low + (high - low) / 2
            if (starts[middle] <= offset) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        low - 1
    }
}

internal struct SourceCheckpoint {
    internal let decodedOffset: Int64
    internal let utf16Units: Int64
    internal let visualColumn: Int64

    internal init(decodedOffset: Int64, utf16Units: Int64, visualColumn: Int64) {
        this.decodedOffset = decodedOffset
        this.utf16Units = utf16Units
        this.visualColumn = visualColumn
    }
}

/**
 * 为大量位置查询预建的 line/checkpoint 索引。
 *
 * 默认使用 tab stop 4 和 `UnicodeScalarWithTabStops`；也可以显式选择 display width
 * policy。
 */
public class SourcePositionMap {
    /** 绑定的 source buffer。 */
    public let source: SourceBuffer
    /** tab 展开宽度。 */
    public let tabStop: Int64
    /** visual column 计算策略。 */
    public let displayWidthPolicy: DisplayWidthPolicy
    private let index: SourceIndex

    /**
     * 使用默认 display width policy 构建索引。
     * @param source 绑定的 source buffer。
     * @param tabStop tab 展开宽度，必须为正。
     */
    public init(source: SourceBuffer, tabStop!: Int64 = 4) {
        if (tabStop <= 0) {
            throw IllegalArgumentException("tab stop must be positive")
        }
        this.source = source
        this.tabStop = tabStop
        this.displayWidthPolicy = DisplayWidthPolicy.UnicodeScalarWithTabStops
        index = SourceIndex(source, tabStop, DisplayWidthPolicy.UnicodeScalarWithTabStops)
    }

    /**
     * 显式指定 display width policy 构建索引。
     * @param source 绑定的 source buffer。
     * @param tabStop tab 展开宽度，必须为正。
     * @param displayWidthPolicy visual column 计算策略。
     */
    public init(source: SourceBuffer, tabStop: Int64, displayWidthPolicy: DisplayWidthPolicy) {
        if (tabStop <= 0) {
            throw IllegalArgumentException("tab stop must be positive")
        }
        this.source = source
        this.tabStop = tabStop
        this.displayWidthPolicy = displayWidthPolicy
        index = SourceIndex(source, tabStop, displayWidthPolicy)
    }

    /** 通过索引计算一基 UTF-8 byte position。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 一基 UTF-8 byte 位置。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func sourcePosition(byteOffset: Int64): SourcePosition {
        ensureOffset(byteOffset)
        let line = index.originalLine(byteOffset)
        let contentStart = index.originalContentStarts[line]
        SourcePosition(line + 1, max(1, byteOffset - contentStart + 1))
    }
    /** 通过索引计算 visual position。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 一基 visual 位置。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func visualPosition(byteOffset: Int64): VisualPosition {
        ensureOffset(byteOffset)
        let decodedLimit = source.decodedOffset(byteOffset)
        let line = index.decodedLine(decodedLimit)
        if (decodedLimit < index.decodedContentStarts[line]) {
            return VisualPosition(line + 1, 1)
        }
        let checkpoint = index.checkpointAt(line, decodedLimit)
        var column = checkpoint.visualColumn
        var current = checkpoint.decodedOffset
        while (current < decodedLimit) {
            if (source.decodedByte(current) == b'\t' && expandsTabs(displayWidthPolicy)) {
                column += tabStop - ((column - 1) % tabStop)
                current++
            } else {
                let width = utf8Width(source.decodedByte(current))
                if (current + width > decodedLimit) {
                    throw IllegalArgumentException("byte offset is not on a UTF-8 boundary")
                }
                column++
                current += width
            }
        }
        VisualPosition(line + 1, column)
    }
    /** 通过索引计算 UTF-16 position。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 零基 UTF-16 位置。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func utf16Position(byteOffset: Int64): Utf16Position {
        ensureOffset(byteOffset)
        let decodedLimit = source.decodedOffset(byteOffset)
        let line = index.decodedLine(decodedLimit)
        if (decodedLimit < index.decodedContentStarts[line]) {
            return Utf16Position(line, 0)
        }
        let checkpoint = index.checkpointAt(line, decodedLimit)
        var character = checkpoint.utf16Units
        var current = checkpoint.decodedOffset
        while (current < decodedLimit) {
            let width = utf8Width(source.decodedByte(current))
            if (current + width > decodedLimit) {
                throw IllegalArgumentException("byte offset is not on a UTF-8 boundary")
            }
            character += if (width == 4) {
                2
            } else {
                1
            }
            current += width
        }
        Utf16Position(line, character)
    }
    /** 通过索引将 UTF-16 position 转回 byte offset。
     * @param position 目标 UTF-16 位置。
     * @return 对应的原始 byte offset。
     * @throws IllegalArgumentException 位置越界时。
     */
    public func byteOffset(position: Utf16Position): Int64 {
        if (position.line >= index.decodedLineStarts.size) {
            throw IllegalArgumentException("UTF-16 position is outside source")
        }
        let checkpoint = index.checkpointAtUtf16(position.line, position.character)
        var character = checkpoint.utf16Units
        var current = checkpoint.decodedOffset
        let end = index.decodedLineEnds[position.line]
        while (current < end) {
            if (character == position.character) {
                return source.originalOffset(current)
            }
            let width = utf8Width(source.decodedByte(current))
            let units: Int64 = if (width == 4) {
                2
            } else {
                1
            }
            if (character + units > position.character) {
                throw IllegalArgumentException("UTF-16 position splits a surrogate pair")
            }
            character += units
            current += width
        }
        if (character == position.character) {
            return source.originalOffset(current)
        }
        throw IllegalArgumentException("UTF-16 position is outside source")
    }

    private func ensureOffset(byteOffset: Int64): Unit {
        if (byteOffset < 0 || byteOffset > source.byteLength()) {
            throw IllegalArgumentException("byte offset is outside source")
        }
    }
}

private func expandsTabs(policy: DisplayWidthPolicy): Bool {
    match (policy) {
        case DisplayWidthPolicy.UnicodeScalar => false
        case DisplayWidthPolicy.UnicodeScalarWithTabStops => true
    }
}
