// Auto Layout for the AppKit stand-in: anchors and constraints with AppKit's meanings, solved by a small Cassowary solver.
// The system is rebuilt from the views on each layout pass, so no edit variables are needed. Coordinates inside the
// solver are y-down, which is what constraint constants mean regardless of isFlipped, and each view's origin is relative
// to its superview's: a constraint is written over the items' paths to the root, where their shared ancestors cancel.
// That keeps the system in small independent blocks; with window-wide origins a long stack's rows fill in with every
// view before it, and the panel's 3,300 constraints took a second or more to solve.
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

private struct Sym: Equatable {
    enum Kind: UInt8 { case invalid, external, slack, error, dummy }
    var id: Int32
    var kind: Kind
    static let invalid = Sym(id: 0, kind: .invalid)
}
/// A row of the tableau: a constant and coefficients, kept sorted by symbol id. Adding rows is a linear merge, with no
/// hashing: a solve does millions of these.
private final class Row {
    var syms: [Sym] = []
    var coefs: [Double] = []
    var constant: Double = 0
    init(_ c: Double = 0) { constant = c }
    init(copy r: Row) { syms = r.syms; coefs = r.coefs; constant = r.constant }
    var isEmpty: Bool { syms.isEmpty }
    private func find(_ id: Int32) -> (Int, Bool) {
        var lo = 0, hi = syms.count
        while lo < hi { let m = (lo + hi) >> 1; if syms[m].id < id { lo = m + 1 } else { hi = m } }
        return (lo, lo < syms.count && syms[lo].id == id)
    }
    func coefficient(_ s: Sym) -> Double { let (i, f) = find(s.id); return f ? coefs[i] : 0 }
    func contains(_ s: Sym) -> Bool { find(s.id).1 }
    func add(_ s: Sym, _ c: Double) {
        let (i, f) = find(s.id)
        if f {
            let v = coefs[i] + c
            if abs(v) < 1e-8 { syms.remove(at: i); coefs.remove(at: i) } else { coefs[i] = v }
        } else if abs(c) >= 1e-8 {
            syms.insert(s, at: i); coefs.insert(c, at: i)
        }
    }
    @discardableResult func remove(_ s: Sym) -> Double? {
        let (i, f) = find(s.id)
        guard f else { return nil }
        let c = coefs[i]
        syms.remove(at: i); coefs.remove(at: i)
        return c
    }
    /// self += r × c. Symbols that newly appear go in `added`, those that cancel out in `removed`.
    func add(_ r: Row, _ c: Double, added: inout [Sym], removed: inout [Sym]) {
        constant += r.constant * c
        var ns: [Sym] = [], nc: [Double] = []
        ns.reserveCapacity(syms.count + r.syms.count); nc.reserveCapacity(syms.count + r.syms.count)
        var i = 0, j = 0
        let n = syms.count, m = r.syms.count
        while i < n || j < m {
            if j == m || (i < n && syms[i].id < r.syms[j].id) {
                ns.append(syms[i]); nc.append(coefs[i]); i += 1
            } else if i == n || r.syms[j].id < syms[i].id {
                let v = r.coefs[j] * c
                if abs(v) >= 1e-8 { ns.append(r.syms[j]); nc.append(v); added.append(r.syms[j]) }
                j += 1
            } else {
                let v = coefs[i] + r.coefs[j] * c
                if abs(v) >= 1e-8 { ns.append(syms[i]); nc.append(v) } else { removed.append(syms[i]) }
                i += 1; j += 1
            }
        }
        syms = ns; coefs = nc
    }
    func add(_ r: Row, _ c: Double) { var a: [Sym] = [], b: [Sym] = []; add(r, c, added: &a, removed: &b) }
    func reverseSign() { constant = -constant; for i in coefs.indices { coefs[i] = -coefs[i] } }
    func solve(for s: Sym) {
        guard let k = remove(s) else { return }
        let c = -1.0 / k
        constant *= c
        for i in coefs.indices { coefs[i] *= c }
    }
    func solve(for lhs: Sym, _ rhs: Sym) { add(lhs, -1); solve(for: rhs) }
    /// Replaces `s` by `r` if this row has it.
    @discardableResult func substitute(_ s: Sym, _ r: Row, added: inout [Sym], removed: inout [Sym]) -> Bool {
        guard let c = remove(s) else { return false }
        add(r, c, added: &added, removed: &removed)
        return true
    }
    func substitute(_ s: Sym, _ r: Row) { var a: [Sym] = [], b: [Sym] = []; substitute(s, r, added: &a, removed: &b) }
}
final class LayoutSolver {
    enum Op { case eq, le, ge }
    /// The tableau, by basic symbol id.
    private var rows: [Row?] = []
    /// For each symbol id, the ids of the rows it appears in: substitutions and the ratio test touch only those.
    private var cols: [[Int32]] = []
    private var kinds: [Sym.Kind] = []
    private var rowTotal = 0
    private var vars: [LayoutVar: Sym] = [:]
    private var next: Int32 = 1
    /// The objective, one row per priority level, strongest first. As in Cassowary (and AppKit), levels are strictly
    /// ranked: no number of constraints at one priority outweighs a single one at a higher priority, so 250 beats
    /// 249.99998 however many of those there are. Each level is its own row, so no weights span many decades.
    private var objectives: [Row] = []
    private var levelStrengths: [Double] = []
    var pivots = 0, adds = 0, substitutions = 0, cellOps = 0
    var rowCount: Int { rowTotal }
    var shape: String {
        let sizes = rows.compactMap { $0?.syms.count }
        return "rows avg \(sizes.reduce(0, +) / max(sizes.count, 1)) max \(sizes.max() ?? 0), objective \(objectives.map(\.syms.count).reduce(0, +)) in \(objectives.count) levels, cols max \(cols.map(\.count).max() ?? 0)"
    }
    /// The objective row for constraints of this strength (higher strength, higher priority).
    private func level(_ strength: Double) -> Row {
        var lo = 0, hi = levelStrengths.count
        while lo < hi { let m = (lo + hi) >> 1; if levelStrengths[m] > strength { lo = m + 1 } else { hi = m } }
        if lo < levelStrengths.count, levelStrengths[lo] == strength { return objectives[lo] }
        let r = Row()
        levelStrengths.insert(strength, at: lo); objectives.insert(r, at: lo)
        return r
    }
    private func make(_ k: Sym.Kind) -> Sym {
        next += 1
        while rows.count <= Int(next) { rows.append(nil); cols.append([]); kinds.append(.invalid) }
        kinds[Int(next)] = k
        return Sym(id: next, kind: k)
    }
    private func sym(_ v: LayoutVar) -> Sym {
        if let s = vars[v] { return s }
        let s = make(.external); vars[v] = s; return s
    }
    private func row(_ s: Sym) -> Row? { rows[Int(s.id)] }

    private func setRow(_ key: Sym, _ row: Row) {
        rows[Int(key.id)] = row
        rowTotal += 1
        for s in row.syms { cols[Int(s.id)].append(key.id) }
    }
    private func takeRow(_ key: Sym) -> Row? {
        guard let row = rows[Int(key.id)] else { return nil }
        rows[Int(key.id)] = nil
        rowTotal -= 1
        for s in row.syms { uncol(s.id, key.id) }
        return row
    }
    private func uncol(_ s: Int32, _ r: Int32) {
        let i = Int(s)
        if let k = cols[i].firstIndex(of: r) { cols[i].swapAt(k, cols[i].count - 1); cols[i].removeLast() }
    }
    /// Replaces `s` by `row` in every row that has it, and in the objective (and `extra`, an artificial objective).
    private func substituteEverywhere(_ s: Sym, _ row: Row, extra: Row? = nil) {
        let keys = cols[Int(s.id)]
        cols[Int(s.id)] = []
        var added: [Sym] = [], removed: [Sym] = []
        for k in keys {
            guard let r = rows[Int(k)] else { continue }
            added.removeAll(keepingCapacity: true); removed.removeAll(keepingCapacity: true)
            substitutions += 1; cellOps += row.syms.count + r.syms.count
            r.substitute(s, row, added: &added, removed: &removed)
            for x in added { cols[Int(x.id)].append(k) }
            for x in removed { uncol(x.id, k) }
        }
        for o in objectives { o.substitute(s, row) }
        if let extra, !objectives.contains(where: { $0 === extra }) { extra.substitute(s, row) }
    }

    /// terms·vars + constant (op) 0, at this strength. Returns false for a required constraint that cannot hold.
    @discardableResult
    func add(_ terms: [(LayoutVar, Double)], _ constant: Double, _ op: Op, strength: Double, required: Bool) -> Bool {
        adds += 1
        let row = Row(constant)
        for (v, c) in terms {
            guard abs(c) > 1e-8 else { continue }
            let s = sym(v)
            if let r = self.row(s) { row.add(r, c) } else { row.add(s, c) }
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
                level(strength).add(err, 1)
            }
        case .eq:
            if !required {
                let ep = make(.error), em = make(.error)
                marker = ep; other = em
                row.add(ep, -1); row.add(em, 1)
                let o = level(strength)
                o.add(ep, 1); o.add(em, 1)
            } else {
                let d = make(.dummy)
                marker = d
                row.add(d, 1)
            }
        }
        if row.constant < 0 { row.reverseSign() }
        let subject = choose(row, marker, other)
        if subject == .invalid {
            if row.syms.allSatisfy({ $0.kind == .dummy }) {
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
        optimize(objectives)
        return true
    }
    private func insert(_ s: Sym, _ row: Row) {
        substituteEverywhere(s, row)
        setRow(s, row)
    }
    private func choose(_ row: Row, _ m: Sym, _ o: Sym) -> Sym {
        // (Sorted by id, so the first external is the lowest-numbered.)
        if let ext = row.syms.first(where: { $0.kind == .external }) { return ext }
        if m.kind == .slack || m.kind == .error, row.coefficient(m) < 0 { return m }
        if o.kind == .slack || o.kind == .error, row.coefficient(o) < 0 { return o }
        return .invalid
    }
    private func addWithArtificial(_ row: Row) -> Bool {
        let art = make(.slack)
        setRow(art, Row(copy: row))
        let a = Row(copy: row)
        optimize([a])
        let ok = abs(a.constant) < 1e-6
        if let r = takeRow(art) {
            if r.isEmpty { return ok }
            guard let e = r.syms.first(where: { $0.kind == .slack || $0.kind == .error }) else { return false }
            r.solve(for: art, e)
            substituteEverywhere(e, r)
            setRow(e, r)
        }
        for k in cols[Int(art.id)] { rows[Int(k)]?.remove(art) }
        cols[Int(art.id)] = []
        for o in objectives { o.remove(art) }
        return ok
    }
    /// Minimises the objective levels in order: a symbol may enter only if it improves some level without changing any
    /// stronger one (its cells there are zero), which is the lexicographic simplex.
    private func optimize(_ objs: [Row]) {
        var guardCount = 0
        var degenerate = 0
        while true {
            guardCount += 1
            if guardCount == 20000 { fputs("layout: simplex did not settle\n", stderr); return }
            // Entering: in the strongest level that can improve, the most negative cell (Dantzig), which takes the
            // fewest pivots; but during a run of degenerate pivots, which make no progress and can cycle on the systems
            // view trees make, the lowest-numbered one (Bland's rule), which cannot. Ties go by id, so the result does
            // not depend on hashing.
            var enter = Sym.invalid
            for (li, obj) in objs.enumerated() {
                func free(_ s: Sym) -> Bool {
                    guard s.kind != .dummy && s.kind != .external else { return false }
                    for k in 0..<li where abs(objs[k].coefficient(s)) > 1e-9 { return false }
                    return true
                }
                if degenerate > 20 {
                    for i in obj.syms.indices where obj.coefs[i] < -1e-9 && free(obj.syms[i]) { enter = obj.syms[i]; break }
                } else {
                    var best = -1e-9
                    for i in obj.syms.indices where obj.coefs[i] < best && free(obj.syms[i]) { enter = obj.syms[i]; best = obj.coefs[i] }
                }
                if enter != .invalid { break }
            }
            guard enter != .invalid else { return }
            pivots += 1
            var leave = Sym.invalid
            var ratio = Double.greatestFiniteMagnitude
            for k in cols[Int(enter.id)] where kinds[Int(k)] != .external {
                guard let r = rows[Int(k)] else { continue }
                let c = r.coefficient(enter)
                if c < 0 {
                    let q = -r.constant / c
                    if q < ratio - 1e-12 || (abs(q - ratio) <= 1e-12 && (leave == .invalid || k < leave.id)) { ratio = q; leave = Sym(id: k, kind: kinds[Int(k)]) }
                }
            }
            guard leave != .invalid, let row = takeRow(leave) else { return }
            degenerate = ratio < 1e-9 ? degenerate + 1 : 0
            row.solve(for: leave, enter)
            substituteEverywhere(enter, row, extra: objs.count == 1 ? objs[0] : nil)
            setRow(enter, row)
        }
    }
    func updateVariables() {
        for (v, s) in vars { v.value = rows[Int(s.id)]?.constant ?? 0 }
    }
}

/// The constraints of one solve, recorded, so that a system identical to the last one solved for the same root is
/// answered from the last result: a panel lays out the same unchanged tree many times over when it opens.
final class LayoutSystem {
    private var list: [([(LayoutVar, Double)], Double, LayoutSolver.Op, Double, Bool)] = []
    private var hasher = Hasher()
    private(set) var solver: LayoutSolver?
    private(set) var cached = false
    func add(_ terms: [(LayoutVar, Double)], _ constant: Double, _ op: LayoutSolver.Op, strength: Double, required: Bool) {
        list.append((terms, constant, op, strength, required))
        for (v, c) in terms { hasher.combine(ObjectIdentifier(v)); hasher.combine(c.bitPattern) }
        hasher.combine(constant.bitPattern); hasher.combine(op); hasher.combine(strength.bitPattern); hasher.combine(required)
        hasher.combine(-1)
    }
    /// Solves, or takes the last answer for `root` if nothing changed since. Leaves every variable's value set.
    func solve(root: NSView) {
        let key = hasher.finalize()
        if let c = root.layoutCache.first(where: { $0.key == key && $0.count == list.count }) {
            for (v, x) in c.values { v.value = x }
            cached = true
            return
        }
        let s = LayoutSolver()
        for (t, k, op, st, req) in list { s.add(t, k, op, strength: st, required: req) }
        s.updateVariables()
        solver = s
        var seen = Set<ObjectIdentifier>(), values: [(LayoutVar, Double)] = []
        for (t, _, _, _, _) in list { for (v, _) in t where seen.insert(ObjectIdentifier(v)).inserted { values.append((v, v.value)) } }
        // A few kept: fitting and laying out at a size alternate on the same root.
        root.layoutCache.insert(LayoutCache(key: key, count: list.count, values: values), at: 0)
        if root.layoutCache.count > 3 { root.layoutCache.removeLast() }
    }
    var count: Int { list.count }
}
struct LayoutCache {
    let key: Int
    let count: Int
    let values: [(LayoutVar, Double)]
}

// MARK: Building a system from the view tree

enum LayoutEngine {
    static func strength(_ p: NSLayoutPriority) -> Double { pow(10, Double(p.rawValue) / 110) }

    private static func vars(_ o: AnyObject?) -> LayoutVars? {
        if let v = o as? NSView { return v.layoutVars }
        if let g = o as? NSLayoutGuide { return g.vars }
        return nil
    }
    /// The item's own offset variables, then its container's, up to (not including) the root being solved.
    private static func chain(_ o: AnyObject?, axisX: Bool, root: NSView) -> [LayoutVar] {
        var out: [LayoutVar] = []
        var cur: AnyObject? = o
        while let c = cur, c !== root {
            guard let v = vars(c) else { break }
            out.append(axisX ? v.l : v.t)
            if let view = c as? NSView { cur = view.superview } else if let g = c as? NSLayoutGuide { cur = g.owningView } else { break }
        }
        return out
    }
    private static func terms(_ o: AnyObject?, _ a: NSLayoutAttribute, _ k: Double, root: NSView) -> [(LayoutVar, Double)] {
        guard let v = vars(o) else { return [] }
        func pos(_ x: Bool) -> [(LayoutVar, Double)] { chain(o, axisX: x, root: root).map { ($0, k) } }
        switch a {
        case .left, .leading: return pos(true)
        case .right, .trailing: return pos(true) + [(v.w, k)]
        case .top: return pos(false)
        case .bottom: return pos(false) + [(v.h, k)]
        case .width: return [(v.w, k)]
        case .height: return [(v.h, k)]
        case .centerX: return pos(true) + [(v.w, k / 2)]
        case .centerY: return pos(false) + [(v.h, k / 2)]
        case .firstBaseline:
            let b = (o as? NSView)?.firstBaselineFromTop ?? 0
            return pos(false) + (b == 0 ? [(v.h, k)] : [])
        case .lastBaseline:
            return pos(false) + [(v.h, k)]
        case .notAnAttribute: return []
        }
    }
    /// Coefficients of the same variable summed; those that cancel dropped.
    private static func merged(_ t: [(LayoutVar, Double)]) -> [(LayoutVar, Double)] {
        var order: [LayoutVar] = []
        var sum: [LayoutVar: Double] = [:]
        for (v, c) in t {
            if sum[v] == nil { order.append(v) }
            sum[v, default: 0] += c
        }
        return order.compactMap { v in abs(sum[v]!) > 1e-9 ? (v, sum[v]!) : nil }
    }
    private static func baselineConstant(_ o: AnyObject?, _ a: NSLayoutAttribute) -> Double {
        guard let v = o as? NSView else { return 0 }
        if a == .firstBaseline { return Double(v.firstBaselineFromTop) }
        if a == .lastBaseline { return -Double(v.lastBaselineFromBottom) }
        return 0
    }

    /// Constraints act on alignment rectangles (AppKit): how far an attribute of the alignment rectangle lies from the
    /// same attribute of the frame. Positions run down from the top. Baselines too are measured from the alignment
    /// rectangle: a view without a baseline puts both at its bottom (an image view: AppKit, measured).
    private static func alignConstant(_ o: AnyObject?, _ a: NSLayoutAttribute) -> Double {
        guard let v = o as? NSView else { return 0 }
        let i = v.alignmentRectInsets
        if i.top == 0, i.left == 0, i.bottom == 0, i.right == 0 { return 0 }
        switch a {
        case .left, .leading: return Double(i.left)
        case .right, .trailing: return -Double(i.right)
        case .top: return Double(i.top)
        case .bottom: return -Double(i.bottom)
        case .width: return -Double(i.left + i.right)
        case .height: return -Double(i.top + i.bottom)
        case .centerX: return Double(i.left - i.right) / 2
        case .centerY: return Double(i.top - i.bottom) / 2
        case .firstBaseline: return v.firstBaselineFromTop == 0 ? -Double(i.bottom) : Double(i.top)
        case .lastBaseline: return -Double(i.bottom)
        default: return 0
        }
    }

    private static func add(_ s: LayoutSystem, _ c: NSLayoutConstraint, root: NSView) {
        var t = terms(c.firstItem, c.firstAttribute, 1, root: root)
        var k = Double(-c.constant) + baselineConstant(c.firstItem, c.firstAttribute) + alignConstant(c.firstItem, c.firstAttribute)
        if c.secondItem != nil, c.secondAttribute != .notAnAttribute {
            t += terms(c.secondItem, c.secondAttribute, -Double(c.multiplier), root: root)
            k -= Double(c.multiplier) * (baselineConstant(c.secondItem, c.secondAttribute) + alignConstant(c.secondItem, c.secondAttribute))
        }
        t = merged(t)
        let op: LayoutSolver.Op = c.relation == .equal ? .eq : c.relation == .lessThanOrEqual ? .le : .ge
        let req = c.priority >= .required
        s.add(t, k, op, strength: strength(c.priority), required: req)
    }

    private static func collect(_ v: NSView, _ out: inout [NSView]) {
        out.append(v)
        for s in v.subviews { collect(s, &out) }
    }

    /// Solves the tree under `root`. With a size the root is held at it; without, it shrinks to fit.
    static let log = ProcessInfo.processInfo.environment["SPIDER_LAYOUT_LOG"] == "1"
    static func solve(root: NSView, size: CGSize?) -> CGSize {
        let started = CACurrentMediaTime()
        var all: [NSView] = []
        collect(root, &all)
        let solver = LayoutSystem()
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
                // (Offsets from the superview's top left.)
                let p = sup.layoutVars
                let f = v.frame
                solver.add([(x.w, 1)], -Double(f.width), .eq, strength: 1, required: true)
                solver.add([(x.h, 1)], -Double(f.height), .eq, strength: 1, required: true)
                let bx = sup.bounds.minX, by = sup.bounds.minY
                solver.add([(x.l, 1)], -Double(f.minX - bx), .eq, strength: 1, required: true)
                if sup.isFlipped {
                    solver.add([(x.t, 1)], -Double(f.minY - by), .eq, strength: 1, required: true)
                } else {
                    solver.add([(x.t, 1), (p.h, -1)], Double(f.maxY - by), .eq, strength: 1, required: true)
                }
            }
            if v.takesPartInConstraints || v === root {
                // The intrinsic size is the alignment rectangle's; the frame is that plus the insets.
                let n = v.intrinsicContentSize, i = v.alignmentRectInsets
                if n.width >= 0 {
                    let hug = v.contentHuggingPriority(for: .horizontal), res = v.contentCompressionResistancePriority(for: .horizontal)
                    let w = Double(n.width + i.left + i.right)
                    solver.add([(x.w, 1)], -w, .le, strength: strength(hug), required: hug >= .required)
                    solver.add([(x.w, 1)], -w, .ge, strength: strength(res), required: res >= .required)
                }
                if n.height >= 0 {
                    let hug = v.contentHuggingPriority(for: .vertical), res = v.contentCompressionResistancePriority(for: .vertical)
                    let h = Double(n.height + i.top + i.bottom)
                    solver.add([(x.h, 1)], -h, .le, strength: strength(hug), required: hug >= .required)
                    solver.add([(x.h, 1)], -h, .ge, strength: strength(res), required: res >= .required)
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
            for c in v.activeConstraints where relevant(c) { add(solver, c, root: root) }
            for c in v.generatedConstraints() where relevant(c) { add(solver, c, root: root) }
        }
        solver.solve(root: root)
        if LayoutEngine.log {
            let ms = (CACurrentMediaTime() - started) * 1000
            fputs(String(format: "layout %@: %d views (%d constrained), %d constraints, %@, %.1f ms\n",
                         String(describing: type(of: root)), all.count, all.filter(\.takesPartInConstraints).count, solver.count,
                         solver.cached ? "same as last time" : "\(solver.solver?.rowCount ?? 0) rows, \(solver.solver?.pivots ?? 0) pivots", ms), stderr)
        }
        // Back to root-wide origins: each view's offset added to its superview's (parents come first in `all`).
        for v in all {
            let x = v.layoutVars
            let o = v === root ? CGPoint.zero : (v.superview?.layoutVars.solved.origin ?? .zero)
            x.solved = CGRect(x: o.x + x.l.value, y: o.y + x.t.value, width: x.w.value, height: x.h.value)
        }
        for v in all {
            let o = v.layoutVars.solved.origin
            for g in v.layoutGuides { g.vars.solved = CGRect(x: o.x + g.vars.l.value, y: o.y + g.vars.t.value, width: g.vars.w.value, height: g.vars.h.value) }
        }
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
