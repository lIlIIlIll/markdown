package markdown

import std.collection.*
import std.convert.*

internal class ExternalDataObject {
    let scalars = HashMap<String, String>()
    let arrays = HashMap<String, Array<String>>()
}

internal class RestrictedJsonParser {
    private let source: String
    private var index: Int64 = 0

    init(source: String) {
        if (source.size > 1024 * 1024) {
            throw IllegalArgumentException("external descriptor exceeds 1 MiB")
        }
        this.source = source
    }

    func parse(): ExternalDataObject {
        let result = ExternalDataObject()
        whitespace();
        expect(b'{');
        whitespace()
        if (take(b'}')) {
            return result
        }
        while (true) {
            let key = stringValue();
            whitespace();
            expect(b':');
            whitespace()
            if (peek() == b'"') {
                if (result.scalars.get(key).isSome() || result.arrays.get(key).isSome()) {
                    fail("duplicate descriptor key")
                }
                result.scalars.add(key, stringValue())
            } else if (peek() == b'[') {
                if (result.scalars.get(key).isSome() || result.arrays.get(key).isSome()) {
                    fail("duplicate descriptor key")
                }
                result.arrays.add(key, stringArray())
            } else {
                fail("descriptor values must be strings or string arrays")
            }
            whitespace()
            if (take(b'}')) {
                break
            }
            expect(b',');
            whitespace()
        }
        whitespace()
        if (index != source.size) {
            fail("trailing JSON descriptor content")
        }
        result
    }

    private func stringArray(): Array<String> {
        let values = ArrayList<String>()
        expect(b'[');
        whitespace()
        if (take(b']')) {
            return values.toArray()
        }
        while (true) {
            values.add(stringValue());
            whitespace()
            if (take(b']')) {
                break
            }
            expect(b',');
            whitespace()
        }
        values.toArray()
    }

    private func stringValue(): String {
        expect(b'"')
        let out = StringBuilder()
        while (index < source.size && source[index] != b'"') {
            if (source[index] == b'\\') {
                index++
                if (index >= source.size) {
                    fail("unterminated JSON escape")
                }
                match (source[index]) {
                    case b'"' => out.append("\"")
                    case b'\\' => out.append("\\")
                    case b'/' => out.append("/")
                    case b'n' => out.append("\n")
                    case b'r' => out.append("\r")
                    case b't' => out.append("\t")
                    case _ => fail("unsupported JSON escape in descriptor")
                }
                index++
            } else {
                if (source[index] < 0x20) {
                    fail("control character in JSON string")
                }
                let next = externalNextRune(source, index)
                out.append(source[index..next]);
                index = next
            }
        }
        expect(b'"')
        out.toString()
    }

    private func whitespace(): Unit {
        while (index < source.size && (source[index] == b' ' || source[index] == b'\t' || source[index] == 10 ||
                source[index] == 13)) {
            index++
        }
    }
    private func peek(): Byte {
        if (index < source.size) {
            source[index]
        } else {
            0
        }
    }
    private func take(byte: Byte): Bool {
        if (index < source.size && source[index] == byte) {
            index++;
            return true
        }
        false
    }
    private func expect(byte: Byte): Unit {
        if (!take(byte)) {
            fail("unexpected JSON descriptor token")
        }
    }
    private func fail(message: String): Nothing {
        throw IllegalArgumentException("${message} at byte ${index}")
    }
}

public class ExternalDialectDescriptor {
    public let schemaVersion: String
    public let id: String
    public let version: String
    public let baseProfileId: String
    public let inlineRules: ImmutableArray<String>
    public let blockRules: ImmutableArray<String>
    public let rendererRules: ImmutableArray<String>

    private init(data: ExternalDataObject) {
        rejectUnknownDescriptorKeys(data)
        schemaVersion = requiredExternalScalar(data, "schemaVersion")
        id = requiredExternalScalar(data, "id")
        version = requiredExternalScalar(data, "version")
        baseProfileId = requiredExternalScalar(data, "baseProfile")
        if (schemaVersion != "1") {
            throw IllegalArgumentException("unsupported external dialect schema")
        }
        inlineRules = ImmutableArray<String>(externalArray(data, "inlineRules"))
        blockRules = ImmutableArray<String>(externalArray(data, "blockRules"))
        rendererRules = ImmutableArray<String>(externalArray(data, "rendererRules"))
    }

    public static func fromJson(source: String): ExternalDialectDescriptor {
        ExternalDialectDescriptor(RestrictedJsonParser(source).parse())
    }

    public static func fromYaml(source: String): ExternalDialectDescriptor {
        if (source.size > 1024 * 1024) {
            throw IllegalArgumentException("external descriptor exceeds 1 MiB")
        }
        ExternalDialectDescriptor(parseRestrictedYaml(source))
    }

    public func compile(): CompiledMarkdownDialect {
        DialectCompiler.compile(toDialect())
    }

    public func toDialect(): MarkdownDialect {
        let profile = externalProfile(baseProfileId)
        let canonical = externalCanonicalDescriptor(this)
        let manifest = ExtensionManifest(id, version, "external-${Sha256.digest(canonical)}",
            supportedProfiles: [profile.id],
            capabilities: ExtensionCapabilities(specHtml: rendererRules.size > 0, safeHtml: rendererRules.size > 0,
                plainText: rendererRules.size > 0, markdown: rendererRules.size > 0, format: rendererRules.size > 0),
            trustLevel: "external-data")
        let builder = MarkdownDialect.define(id, version).base(profile).enable(manifest)
        for (index in 0..inlineRules.size) {
            addExternalInline(builder, id, inlineRules[index])
        }
        for (index in 0..blockRules.size) {
            addExternalBlock(builder, id, blockRules[index])
        }
        for (index in 0..rendererRules.size) {
            addExternalRenderer(builder, id, rendererRules[index])
        }
        builder.build()
    }
}

private func parseRestrictedYaml(source: String): ExternalDataObject {
    let data = ExternalDataObject()
    var activeArray = ""
    var offset: Int64 = 0
    while (offset <= source.size) {
        var end = offset
        while (end < source.size && source[end] != 10 && source[end] != 13) {
            end++
        }
        let raw = source[offset..end]
        if (raw.contains("\t")) {
            throw IllegalArgumentException("tabs are not allowed in descriptor YAML")
        }
        let trimmed = externalTrim(raw)
        if (!trimmed.isEmpty() && !trimmed.startsWith("#")) {
            if (trimmed.startsWith("- ")) {
                if (activeArray.isEmpty()) {
                    throw IllegalArgumentException("YAML array item has no key")
                }
                let existing: Array<String> = match (data.arrays.get(activeArray)) {
                    case Some(value) => value
                    case None => []
                }
                let next = ArrayList<String>();
                next.add(all: existing)
                next.add(externalYamlScalar(externalTrim(trimmed[2..])))
                data.arrays.add(activeArray, next.toArray())
            } else {
                let colon = externalFindByte(trimmed, b':', 0)
                if (colon <= 0) {
                    throw IllegalArgumentException("invalid descriptor YAML line")
                }
                let key = externalTrim(trimmed[..colon])
                let value = externalTrim(trimmed[colon + 1..])
                if (data.scalars.get(key).isSome() || data.arrays.get(key).isSome()) {
                    throw IllegalArgumentException("duplicate descriptor YAML key")
                }
                if (value.isEmpty()) {
                    activeArray = key
                    data.arrays.add(key, [])
                } else {
                    activeArray = ""
                    data.scalars.add(key, externalYamlScalar(value))
                }
            }
        }
        if (end >= source.size) {
            break
        }
        if (source[end] == 13 && end + 1 < source.size && source[end + 1] == 10) {
            end++
        }
        offset = end + 1
    }
    data
}

private func externalYamlScalar(value: String): String {
    if (value.size >= 2 && ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") &&
        value.endsWith("'")))) {
        value[1..value.size - 1]
    } else {
        value
    }
}

private func rejectUnknownDescriptorKeys(data: ExternalDataObject): Unit {
    let allowed = ["schemaVersion", "id", "version", "baseProfile", "inlineRules", "blockRules", "rendererRules"]
    for ((key, _) in data.scalars) {
        if (!externalContains(allowed, key)) {
            throw IllegalArgumentException("unknown descriptor key: ${key}")
        }
    }
    for ((key, _) in data.arrays) {
        if (!externalContains(allowed, key)) {
            throw IllegalArgumentException("unknown descriptor key: ${key}")
        }
    }
}

private func requiredExternalScalar(data: ExternalDataObject, key: String): String {
    match (data.scalars.get(key)) {
        case Some(value) =>
            if (!value.isEmpty()) {
                value
            } else {
                throw IllegalArgumentException("empty descriptor field: ${key}")
            }
        case None => throw IllegalArgumentException("missing descriptor field: ${key}")
    }
}

private func externalArray(data: ExternalDataObject, key: String): Array<String> {
    match (data.arrays.get(key)) {
        case Some(value) => value;
        case None => []
    }
}

private func externalProfile(id: String): MarkdownProfile {
    if (id == "commonmark-0.31.2") {
        MarkdownProfile.commonMark0312()
    } else if (id == "gfm-0.29") {
        MarkdownProfile.gfm029()
    } else if (id == "gfm-modern-v1") {
        MarkdownProfile.gfmModernV1()
    } else {
        throw IllegalArgumentException("unsupported external base profile")
    }
}

private func addExternalInline(builder: MarkdownDialectBuilder, extensionId: String, encoded: String): Unit {
    let fields = externalFields(encoded, 6)
    builder.inline(
        InlineSyntax
            .define(extensionId, fields[0])
            .delimiter(fields[1], closer: fields[2])
            .maximumLookahead(Int64.parse(fields[3]))
            .content(externalBool(fields[4]))
            .nesting(externalBool(fields[5])))
}

private func addExternalBlock(builder: MarkdownDialectBuilder, extensionId: String, encoded: String): Unit {
    let fields = externalFields(encoded, 7)
    let mode = if (fields[3] == "markdown") {
        BlockContentMode.Markdown
    } else if (fields[3] == "literal") {
        BlockContentMode.Literal
    } else {
        throw IllegalArgumentException("invalid external block content mode")
    }
    builder.block(
        BlockSyntax
            .define(extensionId, fields[0])
            .opener(fields[1])
            .closer(fields[2])
            .content(mode)
            .maximumBlockBytes(Int64.parse(fields[4]))
            .maximumCaptureLength(Int64.parse(fields[5]))
            .nesting(externalBool(fields[6]))
            .kindFromFirstWord(false))
}

private func addExternalRenderer(builder: MarkdownDialectBuilder, extensionId: String, encoded: String): Unit {
    let fields = externalFields(encoded, 5)
    builder.renderer(
        RendererRule(extensionId, fields[0], fields[1], classToken: fields[2], markdownOpener: fields[3],
            markdownCloser: fields[4]))
}

private func externalFields(value: String, expected: Int64): Array<String> {
    let fields = ArrayList<String>()
    var start: Int64 = 0
    var index: Int64 = 0
    while (index <= value.size) {
        if (index == value.size || value[index] == b'|') {
            fields.add(value[start..index]);
            start = index + 1
        }
        index++
    }
    if (fields.size != expected) {
        throw IllegalArgumentException("external rule has wrong field count")
    }
    fields.toArray()
}

private func externalCanonicalDescriptor(value: ExternalDialectDescriptor): String {
    let out = StringBuilder()
    out.append(value.schemaVersion);
    out.append("|");
    out.append(value.id);
    out.append("|")
    out.append(value.version);
    out.append("|");
    out.append(value.baseProfileId)
    for (item in value.inlineRules.toArray()) {
        out.append("|i:");
        out.append(item)
    }
    for (item in value.blockRules.toArray()) {
        out.append("|b:");
        out.append(item)
    }
    for (item in value.rendererRules.toArray()) {
        out.append("|r:");
        out.append(item)
    }
    out.toString()
}

private func externalContains(values: Array<String>, target: String): Bool {
    for (value in values) {
        if (value == target) {
            return true
        }
    }
    false
}

private func externalBool(value: String): Bool {
    if (value == "true") {
        true
    } else if (value == "false") {
        false
    } else {
        throw IllegalArgumentException("external boolean must be true or false")
    }
}

private func externalTrim(value: String): String {
    var start: Int64 = 0;
    var end = value.size
    while (start < end && (value[start] == b' ' || value[start] == b'\t')) {
        start++
    }
    while (end > start && (value[end - 1] == b' ' || value[end - 1] == b'\t')) {
        end--
    }
    value[start..end]
}

private func externalFindByte(value: String, byte: Byte, start: Int64): Int64 {
    var index = start
    while (index < value.size) {
        if (value[index] == byte) {
            return index
        };
        index++
    }
    -1
}

private func externalNextRune(value: String, offset: Int64): Int64 {
    if (offset >= value.size) {
        return value.size
    }
    let first = value[offset]
    let width: Int64 = if ((first & 0b1000_0000) == 0) {
        1
    } else if ((first & 0b1110_0000) == 0b1100_0000) {
        2
    } else if ((first & 0b1111_0000) == 0b1110_0000) {
        3
    } else if ((first & 0b1111_1000) == 0b1111_0000) {
        4
    } else {
        1
    }
    let end = offset + width
    if (end < value.size) {
        end
    } else {
        value.size
    }
}
