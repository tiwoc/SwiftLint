import SwiftSyntax

public struct StrongIBOutletRule: ConfigurationProviderRule, SwiftSyntaxCorrectableRule, OptInRule {
    public var configuration = SeverityConfiguration(.warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "strong_iboutlet",
        name: "Strong IBOutlet",
        description: "@IBOutlets shouldn't be declared as weak.",
        kind: .lint,
        nonTriggeringExamples: [
            wrapExample("@IBOutlet var label: UILabel?"),
            wrapExample("weak var label: UILabel?")
        ],
        triggeringExamples: [
            wrapExample("@IBOutlet ↓weak var label: UILabel?"),
            wrapExample("@IBOutlet ↓unowned var label: UILabel!"),
            wrapExample("@IBOutlet ↓weak var textField: UITextField?")
        ],
        corrections: [
            wrapExample("@IBOutlet ↓weak var label: UILabel?"):
                wrapExample("@IBOutlet var label: UILabel?"),
            wrapExample("@IBOutlet ↓unowned var label: UILabel!"):
                wrapExample("@IBOutlet var label: UILabel!"),
            wrapExample("@IBOutlet ↓weak var textField: UITextField?"):
                wrapExample("@IBOutlet var textField: UITextField?")
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

private extension StrongIBOutletRule {
    final class Visitor: SyntaxVisitor, ViolationsSyntaxVisitor {
        private(set) var violationPositions: [AbsolutePosition] = []

        override func visitPost(_ node: VariableDeclSyntax) {
            if let violationPosition = node.violationPosition {
                violationPositions.append(violationPosition)
            }
        }
    }

    private final class Rewriter: SyntaxRewriter, ViolationsSyntaxRewriter {
        private(set) var correctionPositions: [AbsolutePosition] = []
        let locationConverter: SourceLocationConverter
        let disabledRegions: [SourceRange]

        init(locationConverter: SourceLocationConverter, disabledRegions: [SourceRange]) {
            self.locationConverter = locationConverter
            self.disabledRegions = disabledRegions
        }

        override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
            guard let violationPosition = node.violationPosition,
                  let weakOrUnownedModifier = node.weakOrUnownedModifier,
                  let modifiers = node.modifiers else {
                return super.visit(node)
            }

            let isInDisabledRegion = disabledRegions.contains { region in
                region.contains(node.positionAfterSkippingLeadingTrivia, locationConverter: locationConverter)
            }

            guard !isInDisabledRegion else {
                return super.visit(node)
            }

            let newModifiers = ModifierListSyntax(modifiers.filter { $0 != weakOrUnownedModifier })
            let newNode = node.withModifiers(newModifiers)
            correctionPositions.append(violationPosition)
            return super.visit(newNode)
        }
    }
}

private extension VariableDeclSyntax {
    var violationPosition: AbsolutePosition? {
        guard let keyword = weakOrUnownedKeyword, isIBOutlet else {
            return nil
        }

        return keyword.positionAfterSkippingLeadingTrivia
    }

    var isIBOutlet: Bool {
        attributes?.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.tokenKind == .identifier("IBOutlet")
        } ?? false
    }

    var weakOrUnownedModifier: DeclModifierSyntax? {
        modifiers?.first { decl in
            decl.name.tokenKind == .contextualKeyword("weak") ||
                decl.name.tokenKind == .contextualKeyword("unowned")
        }
    }

    var weakOrUnownedKeyword: TokenSyntax? {
        weakOrUnownedModifier?.name
    }
}

private func wrapExample(_ text: String, file: StaticString = #file, line: UInt = #line) -> Example {
    return Example("""
    class ViewController: UIViewController {
        \(text)
    }
    """, file: file, line: line)
}
