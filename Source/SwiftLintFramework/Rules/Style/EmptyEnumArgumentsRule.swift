import SwiftSyntax

private func wrapInSwitch(
    variable: String = "foo",
    _ str: String,
    file: StaticString = #file, line: UInt = #line) -> Example {
    return Example(
        """
        switch \(variable) {
        \(str): break
        }
        """, file: file, line: line)
}

private func wrapInFunc(_ str: String, file: StaticString = #file, line: UInt = #line) -> Example {
    return Example("""
    func example(foo: Foo) {
        switch foo {
        case \(str):
            break
        }
    }
    """, file: file, line: line)
}

public struct EmptyEnumArgumentsRule: SwiftSyntaxCorrectableRule, ConfigurationProviderRule {
    public var configuration = SeverityConfiguration(.warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "empty_enum_arguments",
        name: "Empty Enum Arguments",
        description: "Arguments can be omitted when matching enums with associated values if they are not used.",
        kind: .style,
        nonTriggeringExamples: [
            wrapInSwitch("case .bar"),
            wrapInSwitch("case .bar(let x)"),
            wrapInSwitch("case let .bar(x)"),
            wrapInSwitch(variable: "(foo, bar)", "case (_, _)"),
            wrapInSwitch("case \"bar\".uppercased()"),
            wrapInSwitch(variable: "(foo, bar)", "case (_, _) where !something"),
            wrapInSwitch("case (let f as () -> String)?"),
            wrapInSwitch("default"),
            Example("if case .bar = foo {\n}"),
            Example("guard case .bar = foo else {\n}"),
            Example("if foo == .bar() {}"),
            Example("guard foo == .bar() else { return }"),
            Example("""
            if case .appStore = self.appInstaller, !UIDevice.isSimulator() {
              viewController.present(self, animated: false)
            } else {
              UIApplication.shared.open(self.appInstaller.url)
            }
            """),
            Example("""
            let updatedUserNotificationSettings = deepLink.filter { nav in
              guard case .settings(.notifications(_, nil)) = nav else { return false }
              return true
            }
            """)
        ],
        triggeringExamples: [
            wrapInSwitch("case .bar↓(_)"),
            wrapInSwitch("case .bar↓()"),
            wrapInSwitch("case .bar↓(_), .bar2↓(_)"),
            wrapInSwitch("case .bar↓() where method() > 2"),
            wrapInFunc("case .bar↓(_)"),
            Example("if case .bar↓(_) = foo {\n}"),
            Example("guard case .bar↓(_) = foo else {\n}"),
            Example("if case .bar↓() = foo {\n}"),
            Example("guard case .bar↓() = foo else {\n}"),
            Example("""
            if case .appStore↓(_) = self.appInstaller, !UIDevice.isSimulator() {
              viewController.present(self, animated: false)
            } else {
              UIApplication.shared.open(self.appInstaller.url)
            }
            """),
            Example("""
            let updatedUserNotificationSettings = deepLink.filter { nav in
              guard case .settings(.notifications↓(_, _)) = nav else { return false }
              return true
            }
            """)
        ],
        corrections: [
            wrapInSwitch("case .bar↓(_)"): wrapInSwitch("case .bar"),
            wrapInSwitch("case .bar↓()"): wrapInSwitch("case .bar"),
            wrapInSwitch("case .bar↓(_), .bar2↓(_)"): wrapInSwitch("case .bar, .bar2"),
            wrapInSwitch("case .bar↓() where method() > 2"): wrapInSwitch("case .bar where method() > 2"),
            wrapInFunc("case .bar↓(_)"): wrapInFunc("case .bar"),
            Example("if case .bar↓(_) = foo {"): Example("if case .bar = foo {"),
            Example("guard case .bar↓(_) = foo else {"): Example("guard case .bar = foo else {"),
            Example("""
            let updatedUserNotificationSettings = deepLink.filter { nav in
              guard case .settings(.notifications↓(_, _)) = nav else { return false }
              return true
            }
            """):
                Example("""
                let updatedUserNotificationSettings = deepLink.filter { nav in
                  guard case .settings(.notifications) = nav else { return false }
                  return true
                }
                """)
        ]
    )

    public func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor? {
        Visitor(viewMode: .sourceAccurate)
    }

    public func makeRewriter(file: SwiftLintFile) -> ViolationsSyntaxRewriter? {
        file.locationConverter.map { locationConverter in
            Rewriter(
                locationConverter: locationConverter,
                disabledRegions: disabledRegions(file: file)
            )
        }
    }
}

private extension EmptyEnumArgumentsRule {
    final class Visitor: SyntaxVisitor, ViolationsSyntaxVisitor {
        private(set) var violationPositions: [AbsolutePosition] = []

        override func visitPost(_ node: CaseItemSyntax) {
            if let violationPosition = node.pattern.emptyEnumArgumentsViolation(rewrite: false)?.position {
                violationPositions.append(violationPosition)
            }
        }

        override func visitPost(_ node: MatchingPatternConditionSyntax) {
            if let violationPosition = node.pattern.emptyEnumArgumentsViolation(rewrite: false)?.position {
                violationPositions.append(violationPosition)
            }
        }
    }

    final class Rewriter: SyntaxRewriter, ViolationsSyntaxRewriter {
        private(set) var correctionPositions: [AbsolutePosition] = []
        let locationConverter: SourceLocationConverter
        let disabledRegions: [SourceRange]

        init(locationConverter: SourceLocationConverter, disabledRegions: [SourceRange]) {
            self.locationConverter = locationConverter
            self.disabledRegions = disabledRegions
        }

        override func visit(_ node: CaseItemSyntax) -> Syntax {
            guard
                let (violationPosition, newPattern) = node.pattern.emptyEnumArgumentsViolation(rewrite: true),
                !isInDisabledRegion(node)
            else {
                return super.visit(node)
            }

            correctionPositions.append(violationPosition)
            return super.visit(Syntax(node.withPattern(newPattern)))
        }

        override func visit(_ node: MatchingPatternConditionSyntax) -> Syntax {
            guard
                let (violationPosition, newPattern) = node.pattern.emptyEnumArgumentsViolation(rewrite: true),
                !isInDisabledRegion(node)
            else {
                return super.visit(node)
            }

            correctionPositions.append(violationPosition)
            return super.visit(Syntax(node.withPattern(newPattern)))
        }

        private func isInDisabledRegion<T: SyntaxProtocol>(_ node: T) -> Bool {
            disabledRegions.contains { region in
                region.contains(node.positionAfterSkippingLeadingTrivia, locationConverter: locationConverter)
            }
        }
    }
}

private extension PatternSyntax {
    func emptyEnumArgumentsViolation(rewrite: Bool) -> (position: AbsolutePosition, pattern: PatternSyntax)? {
        guard
            var pattern = self.as(ExpressionPatternSyntax.self),
            let expression = pattern.expression.as(FunctionCallExprSyntax.self),
            expression.argumentsHasViolation,
            let calledExpression = expression.calledExpression.as(MemberAccessExprSyntax.self),
            calledExpression.base == nil,
            let violationPosition = expression.innermostFunctionCall.leftParen?.positionAfterSkippingLeadingTrivia
        else {
            return nil
        }

        if rewrite {
            pattern.expression = expression.removingInnermostDiscardArguments
        }

        return (violationPosition, PatternSyntax(pattern))
    }
}

private extension FunctionCallExprSyntax {
    var argumentsHasViolation: Bool {
        argumentList.allSatisfy(\.expression.isDiscardAssignmentOrFunction)
    }

    var innermostFunctionCall: FunctionCallExprSyntax {
        argumentList
            .lazy
            .compactMap { $0.expression.as(FunctionCallExprSyntax.self)?.innermostFunctionCall }
            .first ?? self
    }

    var removingInnermostDiscardArguments: ExprSyntax {
        guard
            argumentsHasViolation,
            let calledExpression = calledExpression.as(MemberAccessExprSyntax.self),
            calledExpression.base == nil
        else {
            return ExprSyntax(self)
        }

        if argumentList.allSatisfy({ $0.expression.is(DiscardAssignmentExprSyntax.self) }) {
            let newCalledExpression = calledExpression
                .withTrailingTrivia(rightParen?.trailingTrivia ?? .zero)
            let newExpression = self
                .withCalledExpression(ExprSyntax(newCalledExpression))
                .withLeftParen(nil)
                .withArgumentList(nil)
                .withRightParen(nil)
            return ExprSyntax(newExpression)
        }

        var copy = self
        for (index, arg) in argumentList.enumerated() {
            if let newArgExpr = arg.expression.as(FunctionCallExprSyntax.self) {
                let newArg = arg.withExpression(newArgExpr.removingInnermostDiscardArguments)
                copy.argumentList = copy.argumentList.replacing(childAt: index, with: newArg)
            }
        }
        return ExprSyntax(copy)
    }
}

private extension ExprSyntax {
    var isDiscardAssignmentOrFunction: Bool {
        self.is(DiscardAssignmentExprSyntax.self) ||
            (self.as(FunctionCallExprSyntax.self)?.argumentsHasViolation == true)
    }
}
