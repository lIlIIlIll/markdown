package markdown

import std.collection.*

public struct SourceOffset <: Equatable<SourceOffset> {
    public let byteOffset: Int64

    public init(byteOffset: Int64) {
        if (byteOffset < 0) {
            throw IllegalArgumentException("source offset must be non-negative")
        }
        this.byteOffset = byteOffset
    }

    public operator func ==(other: SourceOffset): Bool {
        byteOffset == other.byteOffset
    }
}

public struct SourceSpan <: Equatable<SourceSpan> {
    public let startByte: Int64
    public let endByte: Int64

    public init(startByte: Int64, endByte: Int64) {
        if (startByte < 0 || endByte < startByte) {
            throw IllegalArgumentException("source span must be a non-negative half-open interval")
        }
        this.startByte = startByte
        this.endByte = endByte
    }

    public func length(): Int64 {
        endByte - startByte
    }

    public func isEmpty(): Bool {
        startByte == endByte
    }

    public func contains(offset: SourceOffset): Bool {
        offset.byteOffset >= startByte && offset.byteOffset < endByte
    }

    public func containsSpan(other: SourceSpan): Bool {
        other.startByte >= startByte && other.endByte <= endByte
    }

    public operator func ==(other: SourceSpan): Bool {
        startByte == other.startByte && endByte == other.endByte
    }
}

public struct SourcePosition <: Equatable<SourcePosition> {
    public let line: Int64
    public let byteColumn: Int64

    public init(line: Int64, byteColumn: Int64) {
        if (line < 1 || byteColumn < 1) {
            throw IllegalArgumentException("source positions are one-based")
        }
        this.line = line
        this.byteColumn = byteColumn
    }

    public operator func ==(other: SourcePosition): Bool {
        line == other.line && byteColumn == other.byteColumn
    }
}

public struct VisualPosition <: Equatable<VisualPosition> {
    public let line: Int64
    public let visualColumn: Int64

    public init(line: Int64, visualColumn: Int64) {
        if (line < 1 || visualColumn < 1) {
            throw IllegalArgumentException("visual positions are one-based")
        }
        this.line = line
        this.visualColumn = visualColumn
    }

    public operator func ==(other: VisualPosition): Bool {
        line == other.line && visualColumn == other.visualColumn
    }
}

public struct Utf16Position <: Equatable<Utf16Position> {
    public let line: Int64
    public let character: Int64

    public init(line: Int64, character: Int64) {
        if (line < 0 || character < 0) {
            throw IllegalArgumentException("UTF-16 positions must be non-negative")
        }
        this.line = line
        this.character = character
    }

    public operator func ==(other: Utf16Position): Bool {
        line == other.line && character == other.character
    }
}

public enum PositionEncoding {
    | Utf8Byte
    | Utf16CodeUnit
    | Visual
}

public enum DisplayWidthPolicy {
    // Every Unicode scalar, including tab, advances one column.
    | UnicodeScalar
    // Every Unicode scalar advances one column and tab advances to tabStop.
    | UnicodeScalarWithTabStops
}

public class OwnedUtf8Input {
    private var bytes: ?Array<Byte>
    private init(bytes: Array<Byte>) {
        this.bytes = Some(bytes)
    }

    // The caller must not retain or mutate aliases after transferring ownership.
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

public class SourceBuffer {
    private let value: String
    private let decodedBytes: Array<Byte>
    private let originalBytes: Array<Byte>
    private let decodedToOriginal: Array<Int64>
    private let mappingIsIdentity: Bool
    private let valueBackedIdentity: Bool

    public init(value: String) {
        this.value = value
        this.decodedBytes = []
        this.originalBytes = []
        this.decodedToOriginal = []
        this.mappingIsIdentity = true
        this.valueBackedIdentity = true
    }

    internal init(value: String, originalBytes: Array<Byte>, decodedToOriginal: Array<Int64>) {
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
    }

    internal init(value: String, originalBytes: Array<Byte>) {
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
    }

    public func byteLength(): Int64 {
        originalLength()
    }

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

    public func slice(span: SourceSpan): String {
        ensureSpan(span)
        if (mappingIsIdentity) {
            return value[span.startByte..span.endByte]
        }
        let start = decodedOffset(span.startByte)
        let end = decodedOffset(span.endByte)
        String.fromUtf8(decodedBytes.slice(start, end - start))
    }

    public func text(node: MarkdownNode): String {
        match (node.span) {
            case Some(span) => slice(span)
            case None => throw IllegalArgumentException("node has no source span")
        }
    }

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

public class SourceSlice {
    public let source: SourceBuffer
    public let span: SourceSpan

    public init(source: SourceBuffer, span: SourceSpan) {
        // Validate eagerly so a SourceSlice is always safe to read.
        source.validateSliceSpan(span)
        this.source = source
        this.span = span
    }

    public func text(): String {
        source.slice(span)
    }
    public func detach(): String {
        text()
    }
}

public enum LiteralStorage {
    | Copy(String)
    | Slice(SourceSlice)
}

extend LiteralStorage {
    public func text(): String {
        match (this) {
            case LiteralStorage.Copy(value) => value
            case LiteralStorage.Slice(value) => value.text()
        }
    }

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

public class SourcePositionMap {
    public let source: SourceBuffer
    public let tabStop: Int64
    public let displayWidthPolicy: DisplayWidthPolicy
    private let index: SourceIndex

    public init(source: SourceBuffer, tabStop!: Int64 = 4) {
        if (tabStop <= 0) {
            throw IllegalArgumentException("tab stop must be positive")
        }
        this.source = source
        this.tabStop = tabStop
        this.displayWidthPolicy = DisplayWidthPolicy.UnicodeScalarWithTabStops
        index = SourceIndex(source, tabStop, DisplayWidthPolicy.UnicodeScalarWithTabStops)
    }

    public init(source: SourceBuffer, tabStop: Int64, displayWidthPolicy: DisplayWidthPolicy) {
        if (tabStop <= 0) {
            throw IllegalArgumentException("tab stop must be positive")
        }
        this.source = source
        this.tabStop = tabStop
        this.displayWidthPolicy = displayWidthPolicy
        index = SourceIndex(source, tabStop, displayWidthPolicy)
    }

    public func sourcePosition(byteOffset: Int64): SourcePosition {
        ensureOffset(byteOffset)
        let line = index.originalLine(byteOffset)
        let contentStart = index.originalContentStarts[line]
        SourcePosition(line + 1, max(1, byteOffset - contentStart + 1))
    }
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
