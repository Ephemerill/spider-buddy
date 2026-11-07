// Auto Layout for the AppKit stand-in: anchors and constraints with AppKit's meanings, solved by a small Cassowary solver.
// The system is rebuilt from the views on each layout pass, so no edit variables are needed. Coordinates inside the
// solver are window-wide and y-down, which is what constraint constants mean regardless of isFlipped.
import Foundation
import CoreGraphics

// MARK: Public API

public struct NSLayoutPriority: RawRepresentable, Hashable, Comparable, ExpressibleByFloatLiteral, Sendable {
    public var rawValue: Float
    public init(rawValue: Float) { self.rawValue = rawValue }
    public init(_ v: Float) { rawValue = v }
    public init(floatLiteral v: Float) { rawValue = v }
    public static let required = NSLayoutPriority(1000)
    public static let defaultHigh = NSLayoutPriority(750)
    public static let dragThatCanResizeWindow = NSLayoutPriority(510)
    public static let windowSizeStayPut = NSLayoutPriority(500)
    public static let dragThatCannotResizeWindow = NSLayoutPriority(490)
    public static let defaultLow = NSLayoutPriority(250)
    public static let fittingSizeCompression = NSLayoutPriority(50)
    public static func < (a: NSLayoutPriority, b: NSLayoutPriority) -> Bool { a.rawValue < b.rawValue }
    public static func + (a: NSLayoutPriority, b: Float) -> NSLayoutPriority { NSLayoutPriority(a.rawValue + b) }
    public static func - (a: NSLayoutPriority, b: Float) -> NSLayoutPriority { NSLayoutPriority(a.rawValue - b) }
}

public enum NSLayoutAttribute: Int, Sendable { case left, right, top, bottom, leading, trailing, width, height, centerX, centerY, lastBaseline, firstBaseline, notAnAttribute }
public enum NSLayoutRelation: Int, Sendable { case lessThanOrEqual = -1, equal = 0, greaterThanOrEqual = 1 }

extension NSLayoutConstraint {
    public typealias Attribute = NSLayoutAttribute
    public typealias Relation = NSLayoutRelation
    public typealias Priority = NSLayoutPriority
    public enum Orientation: Int, Sendable { case horizontal = 0, vertical = 1 }
}
public typealias NSUserInterfaceLayoutOrientation = NSLayoutConstraint.Orientation

public final class NSLayoutConstraint: NSObject, @unchecked Sendable {
    public weak var firstItem: AnyObject?
    public weak var secondItem: AnyObject?
    public let firstAttribute: NSLayoutAttribute
    public let secondAttribute: NSLayoutAttribute
    public let relation: NSLayoutRelation
    public var multiplier: CGFloat
    public var constant: CGFloat { didSet { changed() } }
    public var priority: NSLayoutPriority = .required { didSet { changed() } }
    public var identifier: String?
    public var isActive = false {
        didSet {
            guard isActive != oldValue, let v = firstItem as? NSView else { return }
            if isActive { v.activeConstraints.append(self) } else { v.activeConstraints.removeAll { $0 === self } }
            changed()
        }
    }
    func changed() {
        (firstItem as? NSView)?.needsLayout = true
        (secondItem as? NSView)?.needsLayout = true
    }
    public init(item first: Any, attribute a: NSLayoutAttribute, relatedBy r: NSLayoutRelation, toItem second: Any?, attribute b: NSLayoutAttribute, multiplier m: CGFloat, constant c: CGFloat) {
        firstItem = first as AnyObject; secondItem = second as AnyObject?
        firstAttribute = a; secondAttribute = b; relation = r; multiplier = m; constant = c
    }
    public static func activate(_ cs: [NSLayoutConstraint]) { for c in cs { c.isActive = true } }
    public static func deactivate(_ cs: [NSLayoutConstraint]) { for c in cs { c.isActive = false } }
}

/// Anything with anchors: a view, or a layout guide (which is a rectangle of its view).
public protocol NSLayoutAnchorHost: AnyObject {}

open class NSLayoutAnchor<AnchorType>: NSObject {
    let item: AnyObject
    let attr: NSLayoutAttribute
    init(item: AnyObject, attr: NSLayoutAttribute) { self.item = item; self.attr = attr }
    public func constraint(equalTo other: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.equal, other, 1, 0) }
    public func constraint(equalTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.equal, other, 1, c) }
    public func constraint(greaterThanOrEqualTo other: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.greaterThanOrEqual, other, 1, 0) }
    public func constraint(greaterThanOrEqualTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, other, 1, c) }
    public func constraint(lessThanOrEqualTo other: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.lessThanOrEqual, other, 1, 0) }
    public func constraint(lessThanOrEqualTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, other, 1, c) }
    func make(_ r: NSLayoutRelation, _ other: NSLayoutAnchor<AnchorType>?, _ m: CGFloat, _ c: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(item: item, attribute: attr, relatedBy: r, toItem: other?.item as Any?, attribute: other?.attr ?? .notAnAttribute, multiplier: m, constant: c)
    }
}
public final class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
public final class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}
public final class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { make(.equal, nil, 1, c) }
    public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, nil, 1, c) }
    public func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, nil, 1, c) }
    public func constraint(equalTo o: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.equal, o, m, 0) }
    public func constraint(equalTo o: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { make(.equal, o, m, c) }
    public func constraint(greaterThanOrEqualTo o: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, o, m, 0) }
    public func constraint(lessThanOrEqualTo o: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, o, m, 0) }
}

public final class NSLayoutGuide: NSObject {
    public weak var owningView: NSView?
    public var identifier = ""
    public override init() { super.init() }
    let vars = LayoutVars()
    public var frame: CGRect { CGRect(x: vars.solved.minX, y: vars.solved.minY, width: vars.solved.width, height: vars.solved.height) }
    public lazy var leadingAnchor = NSLayoutXAxisAnchor(item: self, attr: .leading)
    public lazy var trailingAnchor = NSLayoutXAxisAnchor(item: self, attr: .trailing)
    public lazy var leftAnchor = NSLayoutXAxisAnchor(item: self, attr: .left)
    public lazy var rightAnchor = NSLayoutXAxisAnchor(item: self, attr: .right)
    public lazy var topAnchor = NSLayoutYAxisAnchor(item: self, attr: .top)
    public lazy var bottomAnchor = NSLayoutYAxisAnchor(item: self, attr: .bottom)
    public lazy var widthAnchor = NSLayoutDimension(item: self, attr: .width)
    public lazy var heightAnchor = NSLayoutDimension(item: self, attr: .height)
    public lazy var centerXAnchor = NSLayoutXAxisAnchor(item: self, attr: .centerX)
    public lazy var centerYAnchor = NSLayoutYAxisAnchor(item: self, attr: .centerY)
}

// MARK: The solver (Cassowary, after the Kiwi implementation)

final class LayoutVar: Hashable {
    var value: Double = 0
    static func == (a: LayoutVar, b: LayoutVar) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}
final class LayoutVars {
    let l = LayoutVar(), t = LayoutVar(), w = LayoutVar(), h = LayoutVar()
    var solved = CGRect.zero
}

private struct Sym: Hashable {
    enum Kind: UInt8 { case invalid, external, slack, error, dummy }
    var id: Int32
    var kind: Kind
    static let invalid = Sym(id: 0, kind: .invalid)
}
private final class Row {
    var cells: [Sym: Double] = [:]
    var constant: Double = 0
    init(_ c: Double = 0) { constant = c }
    init(copy r: Row) { cells = r.cells; constant = r.constant }
    func add(_ s: Sym, _ c: Double) {
        let v = (cells[s] ?? 0) + c
        if abs(v) < 1e-8 { cells[s] = nil } else { cells[s] = v }
    }
    func add(_ r: Row, _ c: Double) {
        constant += r.constant * c
        for (s, v) in r.cells { add(s, v * c) }
    }
    func reverseSign() { constant = -constant; for k in Array(cells.keys) { cells[k] = -cells[k]! } }
    func solve(for s: Sym) {
        let c = -1.0 / cells[s]!
        cells[s] = nil
        constant *= c
        for k in Array(cells.keys) { cells[k]! *= c }
    }
    func solve(for lhs: Sym, _ rhs: Sym) { add(lhs, -1); solve(for: rhs) }
    func substitute(_ s: Sym, _ r: Row) {
        if let c = cells.removeValue(forKey: s) { add(r, c) }
    }
}
final class LayoutSolver {
    enum Op { case eq, le, ge }
    private var rows: [Sym: Row] = [:]
    private var vars: [LayoutVar: Sym] = [:]
    private var next: Int32 = 1
    private let objective = Row()
    private func make(_ k: Sym.Kind) -> Sym { next += 1; return Sym(id: next, kind: k) }
    private func sym(_ v: LayoutVar) -> Sym {
        if let s = vars[v] { return s }
        let s = make(.external); vars[v] = s; return s
    }
    /// terms·vars + constant (op) 0, at this strength. Returns false for a required constraint that cannot hold.
    @discardableResult
    func add(_ terms: [(LayoutVar, Double)], _ constant: Double, _ op: Op, strength: Double, required: Bool) -> Bool {
        let row = Row(constant)
        for (v, c) in terms {
            guard abs(c) > 1e-8 else { continue }
            let s = sym(v)
            if let r = rows[s] { row.add(r, c) } else { row.add(s, c) }
        }
        var marker = Sym.invalid, other = Sym.invalid
        switch op {
        case .le, .ge:
            let coeff: Double = op == .le ? 1 : -1
            let slack = make(.slack)
            marker = slack
            row.add(slack, coeff)
            if !required {
                let err = make(.error)
                other = err
                row.add(err, -coeff)
                objective.add(err, strength)
            }
        case .eq:
            if !required {
                let ep = make(.error), em = make(.error)
                marker = ep; other = em
                row.add(ep, -1); row.add(em, 1)
                objective.add(ep, strength); objective.add(em, strength)
            } else {
                let d = make(.dummy)
                marker = d
                row.add(d, 1)
            }
        }
        if row.constant < 0 { row.reverseSign() }
        let subject = choose(row, marker, other)
        if subject == .invalid {
            if row.cells.keys.allSatisfy({ $0.kind == .dummy }) {
                if abs(row.constant) > 1e-8 { return false }
                let m = marker
                row.solve(for: m)
                insert(m, row)
            } else if !addWithArtificial(row) {
                return false
            }
        } else {
            row.solve(for: subject)
            insert(subject, row)
        }
        optimize(objective)
        return true
    }
    private func insert(_ s: Sym, _ row: Row) {
        for (_, r) in rows { r.substitute(s, row) }
        objective.substitute(s, row)
        rows[s] = row
    }
    private func choose(_ row: Row, _ m: Sym, _ o: Sym) -> Sym {
        for (s, _) in row.cells where s.kind == .external { return s }
        if m.kind == .slack || m.kind == .error, (row.cells[m] ?? 0) < 0 { return m }
        if o.kind == .slack || o.kind == .error, (row.cells[o] ?? 0) < 0 { return o }
        return .invalid
    }
    private func addWithArtificial(_ row: Row) -> Bool {
        let art = make(.slack)
        rows[art] = Row(copy: row)
        let a = Row(copy: row)
        optimize(a)
        let ok = abs(a.constant) < 1e-6
        if let r = rows.removeValue(forKey: art) {
            if r.cells.isEmpty { return ok }
            guard let e = r.cells.keys.first(where: { $0.kind == .slack || $0.kind == .error || $0.kind == .external }) else { return false }
            r.solve(for: art, e)
            for (_, x) in rows { x.substitute(e, r) }
            objective.substitute(e, r)
            rows[e] = r
        }
        for (_, r) in rows { r.cells[art] = nil }
        objective.cells[art] = nil
        return ok
    }
    private func optimize(_ obj: Row) {
        var guardCount = 0
        while guardCount < 5000 {
            guardCount += 1
            // Entering: the most negative pivotable cell, ties broken by id so the result does not depend on hashing.
            var enter = Sym.invalid
            var best = -1e-9
            for (s, c) in obj.cells where s.kind != .dummy && s.kind != .external && c < 0 {
                if c < best - 1e-12 || (abs(c - best) <= 1e-12 && (enter == .invalid || s.id < enter.id)) { best = c; enter = s }
            }
            guard enter != .invalid else { return }
            var leave = Sym.invalid
            var ratio = Double.greatestFiniteMagnitude
            for (s, r) in rows where s.kind != .external {
                if let c = r.cells[enter], c < 0 {
                    let q = -r.constant / c
                    if q < ratio - 1e-12 || (abs(q - ratio) <= 1e-12 && s.id < leave.id) { ratio = q; leave = s }
                }
            }
            guard leave != .invalid, let row = rows.removeValue(forKey: leave) else { return }
            row.solve(for: leave, enter)
            for (_, r) in rows { r.substitute(enter, row) }
            objective.substitute(enter, row)
            if obj !== objective { obj.substitute(enter, row) }
            rows[enter] = row
        }
    }
    func updateVariables() {
        for (v, s) in vars { v.value = rows[s]?.constant ?? 0 }
    }
}

// MARK: Building a system from the view tree

enum LayoutEngine {
    static func strength(_ p: NSLayoutPriority) -> Double { pow(10, Double(p.rawValue) / 110) }

    private static func vars(_ o: AnyObject?) -> LayoutVars? {
        if let v = o as? NSView { return v.layoutVars }
        if let g = o as? NSLayoutGuide { return g.vars }
        return nil
    }
    private static func terms(_ o: AnyObject?, _ a: NSLayoutAttribute, _ k: Double) -> [(LayoutVar, Double)] {
        guard let v = vars(o) else { return [] }
        switch a {
        case .left, .leading: return [(v.l, k)]
        case .right, .trailing: return [(v.l, k), (v.w, k)]
        case .top: return [(v.t, k)]
        case .bottom: return [(v.t, k), (v.h, k)]
        case .width: return [(v.w, k)]
        case .height: return [(v.h, k)]
        case .centerX: return [(v.l, k), (v.w, k / 2)]
        case .centerY: return [(v.t, k), (v.h, k / 2)]
        case .firstBaseline:
            let b = (o as? NSView)?.firstBaselineFromTop ?? 0
            return [(v.t, k)] + (b == 0 ? [(v.h, k)] : [])
        case .lastBaseline:
            return [(v.t, k), (v.h, k)]
        case .notAnAttribute: return []
        }
    }
    private static func baselineConstant(_ o: AnyObject?, _ a: NSLayoutAttribute) -> Double {
        guard let v = o as? NSView else { return 0 }
        if a == .firstBaseline { return Double(v.firstBaselineFromTop) }
        if a == .lastBaseline { return -Double(v.lastBaselineFromBottom) }
        return 0
    }

    private static func add(_ s: LayoutSolver, _ c: NSLayoutConstraint) {
        var t = terms(c.firstItem, c.firstAttribute, 1)
        var k = Double(-c.constant) + baselineConstant(c.firstItem, c.firstAttribute)
        if c.secondItem != nil, c.secondAttribute != .notAnAttribute {
            t += terms(c.secondItem, c.secondAttribute, -Double(c.multiplier))
            k -= Double(c.multiplier) * baselineConstant(c.secondItem, c.secondAttribute)
        }
        let op: LayoutSolver.Op = c.relation == .equal ? .eq : c.relation == .lessThanOrEqual ? .le : .ge
        let req = c.priority >= .required
        s.add(t, k, op, strength: strength(c.priority), required: req)
    }

    private static func collect(_ v: NSView, _ out: inout [NSView]) {
        out.append(v)
        for s in v.subviews { collect(s, &out) }
    }

    /// Solves the tree under `root`. With a size the root is held at it; without, it shrinks to fit.
    static func solve(root: NSView, size: CGSize?) -> CGSize {
        var all: [NSView] = []
        collect(root, &all)
        let solver = LayoutSolver()
        let inTree = Set(all.map { ObjectIdentifier($0) })
        let rv = root.layoutVars
        solver.add([(rv.l, 1)], 0, .eq, strength: 1, required: true)
        solver.add([(rv.t, 1)], 0, .eq, strength: 1, required: true)
        if let size {
            solver.add([(rv.w, 1)], -Double(size.width), .eq, strength: 1, required: true)
            solver.add([(rv.h, 1)], -Double(size.height), .eq, strength: 1, required: true)
        } else {
            solver.add([(rv.w, 1)], 0, .eq, strength: strength(.fittingSizeCompression), required: false)
            solver.add([(rv.h, 1)], 0, .eq, strength: strength(.fittingSizeCompression), required: false)
        }
        for v in all {
            let x = v.layoutVars
            solver.add([(x.w, 1)], 0, .ge, strength: 1, required: true)
            solver.add([(x.h, 1)], 0, .ge, strength: 1, required: true)
            if v !== root, let sup = v.superview, !v.takesPartInConstraints {
                // Frame-based: held where its frame says, within a superview that may itself be solved.
                let p = sup.layoutVars
                let f = v.frame
                solver.add([(x.w, 1)], -Double(f.width), .eq, strength: 1, required: true)
                solver.add([(x.h, 1)], -Double(f.height), .eq, strength: 1, required: true)
                let bx = sup.bounds.minX, by = sup.bounds.minY
                solver.add([(x.l, 1), (p.l, -1)], -Double(f.minX - bx), .eq, strength: 1, required: true)
                if sup.isFlipped {
                    solver.add([(x.t, 1), (p.t, -1)], -Double(f.minY - by), .eq, strength: 1, required: true)
                } else {
                    solver.add([(x.t, 1), (p.t, -1), (p.h, -1)], Double(f.maxY - by), .eq, strength: 1, required: true)
                }
            }
            if v.takesPartInConstraints || v === root {
                let n = v.intrinsicContentSize
                if n.width >= 0 {
                    let hug = v.contentHuggingPriority(for: .horizontal), res = v.contentCompressionResistancePriority(for: .horizontal)
                    solver.add([(x.w, 1)], -Double(n.width), .le, strength: strength(hug), required: hug >= .required)
                    solver.add([(x.w, 1)], -Double(n.width), .ge, strength: strength(res), required: res >= .required)
                }
                if n.height >= 0 {
                    let hug = v.contentHuggingPriority(for: .vertical), res = v.contentCompressionResistancePriority(for: .vertical)
                    solver.add([(x.h, 1)], -Double(n.height), .le, strength: strength(hug), required: hug >= .required)
                    solver.add([(x.h, 1)], -Double(n.height), .ge, strength: strength(res), required: res >= .required)
                }
            }
        }
        func relevant(_ c: NSLayoutConstraint) -> Bool {
            func ok(_ o: AnyObject?) -> Bool {
                guard let o else { return true }
                if let v = o as? NSView { return inTree.contains(ObjectIdentifier(v)) }
                if let g = o as? NSLayoutGuide { return g.owningView.map { inTree.contains(ObjectIdentifier($0)) } ?? false }
                return false
            }
            return ok(c.firstItem) && ok(c.secondItem)
        }
        for v in all {
            for c in v.activeConstraints where relevant(c) { add(solver, c) }
            for c in v.generatedConstraints() where relevant(c) { add(solver, c) }
        }
        solver.updateVariables()
        for v in all { v.layoutVars.solved = CGRect(x: v.layoutVars.l.value, y: v.layoutVars.t.value, width: v.layoutVars.w.value, height: v.layoutVars.h.value) }
        for v in all { for g in v.layoutGuides { g.vars.solved = CGRect(x: g.vars.l.value, y: g.vars.t.value, width: g.vars.w.value, height: g.vars.h.value) } }
        return CGSize(width: rv.w.value, height: rv.h.value)
    }

    /// One layout pass for a window's content, or any root. Sets frames, lets wrapping labels re-measure, and repeats if
    /// that changed anything.
    static func layout(root: NSView, size: CGSize) {
        for _ in 0..<4 {
            _ = solve(root: root, size: size)
            var all: [NSView] = []
            collect(root, &all)
            var changed = false
            for v in all where v !== root && v.takesPartInConstraints {
                guard let sup = v.superview else { continue }
                let s = v.layoutVars.solved, p = sup.layoutVars.solved
                let x = s.minX - p.minX + sup.bounds.minX
                let y = sup.isFlipped ? s.minY - p.minY + sup.bounds.minY : p.height - (s.minY - p.minY) - s.height + sup.bounds.minY
                let f = CGRect(x: (x * 2).rounded() / 2, y: (y * 2).rounded() / 2, width: (s.width * 2).rounded() / 2, height: (s.height * 2).rounded() / 2)
                if abs(f.minX - v.frame.minX) > 0.25 || abs(f.minY - v.frame.minY) > 0.25 || abs(f.width - v.frame.width) > 0.25 || abs(f.height - v.frame.height) > 0.25 {
                    v.frame = f
                    changed = true
                }
            }
            for v in all where v.widthChangedIntrinsic() { changed = true }
            for v in all { v.layout() }
            if !changed { break }
        }
    }
}
