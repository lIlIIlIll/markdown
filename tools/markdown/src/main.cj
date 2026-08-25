package markdown_cli

import markdown.*
import std.convert.*
import std.env.*

main(args: Array<String>): Int64 {
    if (args.size == 0) {
        printUsage();
        return 2
    }
    try {
        let command = args[0]
        let profile = parseProfile(args)
        if (argValue(args, "--fault-inject", "") == "internal") {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "fault injection: internal invariant",
                phase: "cli_fault_injection")
        }
        let builder = MarkdownEngine.builder().profile(profile)
        let maximumInput = argValue(args, "--max-input-bytes", "")
        if (!maximumInput.isEmpty()) {
            builder.limits(cliLimits(Int64.parse(maximumInput)))
        }
        let engine = builder.build()
        if (command == "dialect") {
            return runDialect(engine, args)
        }
        let source = match (getStdIn().readToEnd()) {
            case Some(value) => value;
            case None => ""
        }
        let cancellation = CancellationSource()
        if (hasArg(args, "--cancel-before-start")) {
            cancellation.cancel()
        }
        if (command == "render") {
            return runRender(engine, source, args, cancellation.token)
        }
        if (command == "parse") {
            let result = engine.parse(source, cancellation: cancellation.token)
            let artifact = engine.createArtifact(result)
            println(artifact.debugJson())
            return 0
        }
        if (command == "format") {
            cancellation.token.throwIfCancelled(phase: "format")
            let formatted = if (hasArg(args, "--range")) {
                let snapshot = engine.parseSnapshot(source)
                let range = parseRange(argValue(args, "--range", ""), source.size)
                let edits = PreservingFormatter.formatRange(snapshot, range)
                if (edits.isEmpty()) {
                    source
                } else {
                    snapshot.applyEdits(edits).snapshot.result.source.text()
                }
            } else {
                CanonicalMarkdownRenderer().render(engine.parse(source, cancellation: cancellation.token).document)
            }
            if (hasArg(args, "--check")) {
                if (formatted != source) {
                    return 3
                }
                return 0
            }
            print(formatted)
            return 0
        }
        if (command == "check") {
            let snapshot = engine.parseSnapshot(source)
            let diagnostics = engine.lint(snapshot)
            var rejected = false
            for (diagnostic in diagnostics) {
                println("${diagnostic.code}: ${diagnostic.message}")
                match (diagnostic.severity) {
                    case DiagnosticSeverity.Error => rejected = true
                    case _ => ()
                }
            }
            return if (rejected) {
                4
            } else {
                0
            }
        }
        if (command == "explain") {
            let explanation = engine.explain(source, 0)
            println("selected=${explanation.selectedRule}")
            println("priority=${explanation.priority}")
            println("fingerprint=${explanation.fingerprint}")
            return 0
        }
        printUsage()
        2
    } catch (error: MarkdownException) {
        eprintln(error.message)
        match (error.code) {
            case MarkdownErrorCode.Cancelled => 6
            case MarkdownErrorCode.BudgetExceeded => 6
            case MarkdownErrorCode.ExtensionConflict => 5
            case MarkdownErrorCode.ExtensionFailure => 5
            case MarkdownErrorCode.InternalInvariantViolation => 7
            case _ => 1
        }
    } catch (error: IllegalArgumentException) {
        eprintln(error.message)
        2
    } catch (error: Exception) {
        eprintln(error.message)
        7
    }
}

func runRender(engine: MarkdownEngine, source: String, args: Array<String>, cancellation: CancellationToken): Int64 {
    let document = engine.parse(source, cancellation: cancellation).document
    let target = argValue(args, "--to", "safe-html")
    if (target == "spec-html") {
        let options = match (engine.profile.kind) {
            case ProfileKind.Gfm029 => HtmlOptions.gfmCompatible()
            case ProfileKind.GfmModernV1 => HtmlOptions.gfmCompatible()
            case _ => HtmlOptions.specCompatible()
        }
        print(HtmlRenderer(options: options).render(document))
        return 0
    }
    if (target == "safe-html") {
        print(HtmlRenderer().render(document));
        return 0
    }
    if (target == "text") {
        print(PlainTextRenderer().render(document));
        return 0
    }
    if (target == "markdown") {
        print(CanonicalMarkdownRenderer().render(document));
        return 0
    }
    eprintln("unknown render target: ${target}")
    2
}

func runDialect(engine: MarkdownEngine, args: Array<String>): Int64 {
    let action = if (args.size > 1) {
        args[1]
    } else {
        "describe"
    }
    if (action == "describe") {
        println("profile=${engine.profile.id}")
        println("extensions=${engine.capabilities().supportedExtensions.size}")
        return 0
    }
    if (action == "fingerprint") {
        println(engine.dialect.fingerprint);
        return 0
    }
    if (action == "validate") {
        let spiVersion = argValue(args, "--spi-version", "1")
        DialectCompiler.compile(
            MarkdownDialect
                .define("cli-validation", "1")
                .enable(ExtensionManifest("cli-validation", "1", "1", requiredSpiVersion: spiVersion))
                .build())
        println("valid")
        return 0
    }
    eprintln("unknown dialect action: ${action}")
    2
}

func parseProfile(args: Array<String>): MarkdownProfile {
    let value = argValue(args, "--profile", "commonmark-0.31.2")
    if (value == "commonmark-0.31.2") {
        return MarkdownProfile.commonMark0312()
    }
    if (value == "gfm-0.29") {
        return MarkdownProfile.gfm029()
    }
    if (value == "gfm-modern-v1") {
        return MarkdownProfile.gfmModernV1()
    }
    throw IllegalArgumentException("unknown profile: ${value}")
}

func argValue(args: Array<String>, name: String, fallback: String): String {
    for (index in 0..args.size) {
        if (args[index] == name && index + 1 < args.size) {
            return args[index + 1]
        }
    }
    fallback
}

func hasArg(args: Array<String>, name: String): Bool {
    for (value in args) {
        if (value == name) {
            return true
        }
    }
    false
}

func parseRange(value: String, inputBytes: Int64): SourceSpan {
    var separator: Int64 = -1
    for (index in 0..value.size) {
        if (value[index] == b':') {
            separator = index
            break
        }
    }
    if (separator <= 0 || separator + 1 >= value.size) {
        throw IllegalArgumentException("range must use start:end byte offsets")
    }
    let start = Int64.parse(value[..separator])
    let end = Int64.parse(value[separator + 1..])
    if (end > inputBytes) {
        throw IllegalArgumentException("range is outside input")
    }
    SourceSpan(start, end)
}

func cliLimits(maximumInputBytes: Int64): ParseLimits {
    if (maximumInputBytes <= 0) {
        throw IllegalArgumentException("maximum input bytes must be positive")
    }
    let safe = ParseLimits.safe()
    ParseLimits(maximumInputBytes, safe.maximumLineBytes, safe.maximumNestingDepth, safe.maximumAstNodes,
        safe.maximumReferences, safe.maximumTableColumns, safe.maximumUrlBytes, safe.maximumLiteralBytes,
        safe.maximumOutputBytes, safe.maximumExtensionCaptureBytes, safe.maximumExtensionLookaheadBytes)
}

func printUsage(): Unit {
    eprintln("usage: markdown <render|parse|format|check|explain|dialect> [options]")
}
