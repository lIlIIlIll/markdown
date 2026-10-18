package markdown

import std.collection.*

/** Shared complete-document pipeline after either batch or append construction. */
internal func finishParsedDocument(arena: Document, source: SourceBuffer, diagnostics: ArrayList<Diagnostic>,
    profile: MarkdownProfile, dialect: CompiledMarkdownDialect, bindingOptions: BindingOptions, limits: ParseLimits,
    budget: OperationBudget, cancellation: CancellationToken, requiresBinding!: Bool): ParseResult {
    var document = arena
    if (!dialect.astTransforms.isEmpty()) {
        for (index in 0..dialect.astTransforms.size) {
            let transform = dialect.astTransforms[index]
            cancellation.throwIfCancelled(phase: "ast_transform")
            budget.consumeExtensionCallback()
            budget.consumeTransform()
            try {
                document = transform.transform(document, source, limits, budget, cancellation)
                cancellation.throwIfCancelled(phase: "ast_transform")
                document.requireSource(source)
                let root = document.root().asDocument().getOrThrow()
                if (!root.profile.sameIdentity(profile) || root.dialectFingerprint != dialect.fingerprint) {
                    throw IllegalArgumentException("AST transform changed profile or dialect identity")
                }
                AstInvariantValidator().validate(document, limits: limits, budget: budget, cancellation: cancellation)
            } catch (error: Exception) {
                throwExtensionStageFailure(dialect, transform.extensionId, transform.transformId, "ast_transform", error)
            }
        }
    }
    if (requiresBinding || dialect.parserHotPlan.hasDocumentStages || (dialect.parserOptions.extensionsEnabled &&
        dialect.parserHotPlan.headingIdRule.isSome())) {
        document = DocumentBinder.bind(document, bindingOptions, limits, budget, cancellation,
            headingsEnabled: dialect.parserOptions.extensionsEnabled && dialect.parserHotPlan.headingIdRule.isSome())
        diagnostics.add(all: document.bindings.diagnostics.toArray())
    }
    for (index in 0..dialect.documentAnalyses.size) {
        let analysis = dialect.documentAnalyses[index]
        cancellation.throwIfCancelled(phase: "document_analysis")
        budget.consumeExtensionCallback()
        try {
            let values = analysis.analyze(document, source, limits, budget, cancellation)
            cancellation.throwIfCancelled(phase: "document_analysis")
            for (diagnostic in values) {
                diagnostics.add(validatedAnalysisDiagnostic(diagnostic, analysis, source, limits, budget, cancellation))
            }
        } catch (error: Exception) {
            throwExtensionStageFailure(dialect, analysis.extensionId, analysis.analysisId, "document_analysis", error)
        }
    }
    ParseResult(document, source, diagnostics.toArray())
}

private func validatedAnalysisDiagnostic(value: Diagnostic, analysis: ExtensionDocumentAnalysis, source: SourceBuffer,
    limits: ParseLimits, budget: OperationBudget, cancellation: CancellationToken): Diagnostic {
    budget.consumeScan()
    cancellation.throwIfCancelled(phase: "document_analysis")
    validateAnalysisSpan(value.span, source)
    if (let Some(extensionId) <- value.extensionId) {
        if (extensionId != analysis.extensionId) {
            throw IllegalArgumentException("document analysis returned another extension's diagnostic")
        }
    }
    validateAnalysisLiteral(value.code, limits, budget)
    validateAnalysisLiteral(value.message, limits, budget)
    if (let Some(ruleId) <- value.ruleId) {
        validateAnalysisLiteral(ruleId, limits, budget)
    }
    for (span in value.relatedSpans) {
        budget.consumeScan()
        cancellation.throwIfCancelled(phase: "document_analysis")
        validateAnalysisSpan(span, source)
    }
    for (index in 0..value.fixes.size) {
        budget.consumeScan()
        cancellation.throwIfCancelled(phase: "document_analysis")
        let fix = value.fixes[index]
        validateAnalysisSpan(fix.span, source)
        validateAnalysisLiteral(fix.title, limits, budget)
        validateAnalysisLiteral(fix.replacement, limits, budget)
    }
    Diagnostic(value.code, value.severity, value.message, value.span, relatedSpans: value.relatedSpans.clone(),
        extensionId: Some(analysis.extensionId), ruleId: if (value.ruleId.isSome()) {
            value.ruleId
        } else {
            Some(analysis.analysisId)
        }, fixes: value.fixes.toArray())
}

private func validateAnalysisSpan(span: SourceSpan, source: SourceBuffer): Unit {
    if (span.endByte > source.byteLength()) {
        throw IllegalArgumentException("document analysis returned an out-of-source range")
    }
    validateAnalysisOffset(span.startByte, source)
    validateAnalysisOffset(span.endByte, source)
}

private func validateAnalysisOffset(offset: Int64, source: SourceBuffer): Unit {
    let decoded = source.decodedOffset(offset)
    if (decoded < source.decodedLength() && (source.decodedByte(decoded) & 0xC0) == 0x80) {
        throw IllegalArgumentException("document analysis range splits a UTF-8 scalar")
    }
}

private func validateAnalysisLiteral(value: String, limits: ParseLimits, budget: OperationBudget): Unit {
    if (value.size > limits.maximumLiteralBytes) {
        throw LimitExceededException("diagnostic_literal_bytes", limits.maximumLiteralBytes, value.size,
            "document_analysis")
    }
    budget.consumeScan(steps: value.size)
}

private func throwExtensionStageFailure(dialect: CompiledMarkdownDialect, extensionId: String, ruleId: String,
    phase: String, error: Exception): Nothing {
    if (let failure: MarkdownException <- error) {
        match (failure.code) {
            case MarkdownErrorCode.Cancelled | MarkdownErrorCode.BudgetExceeded | MarkdownErrorCode.LimitExceeded
                | MarkdownErrorCode.ExtensionFailure => throw failure
            case _ => ()
        }
    }
    let manifest = compiledExtensionManifest(dialect, extensionId)
    throw ExtensionFailureException(extensionId, manifest.semanticVersion, manifest.implementationVersion, phase, error,
        ruleId: Some(ruleId))
}

private func compiledExtensionManifest(dialect: CompiledMarkdownDialect, extensionId: String): ExtensionManifest {
    for (index in 0..dialect.manifests.size) {
        let manifest = dialect.manifests[index]
        if (manifest.extensionId == extensionId) {
            return manifest
        }
    }
    throw IllegalStateException("compiled dialect is missing extension manifest")
}
