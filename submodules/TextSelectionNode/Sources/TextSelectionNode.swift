import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

private extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

private func findScrollView(view: UIView?) -> UIScrollView? {
    if let view = view {
        if let view = view as? UIScrollView {
            return view
        }
        return findScrollView(view: view.superview)
    } else {
        return nil
    }
}

private func cancelScrollViewGestures(view: UIView?) {
    if let view = view {
        if let gestureRecognizers = view.gestureRecognizers {
            for recognizer in gestureRecognizers {
                if let recognizer = recognizer as? UIPanGestureRecognizer {
                    switch recognizer.state {
                    case .began, .possible:
                        recognizer.state = .ended
                    default:
                        break
                    }
                }
            }
        }
        cancelScrollViewGestures(view: view.superview)
    }
}

private func generateKnobImage(color: UIColor, diameter: CGFloat, inverted: Bool = false) -> UIImage? {
    let f: (CGSize, CGContext) -> Void = { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: CGPoint(x: (size.width - 2.0) / 2.0, y: size.width / 2.0), size: CGSize(width: 2.0, height: size.height - size.width / 2.0 - 1.0)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: floor((size.width - diameter) / 2.0), y: floor((size.width - diameter) / 2.0)), size: CGSize(width: diameter, height: diameter)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: (size.width - 2.0) / 2.0, y: size.width + 2.0), size: CGSize(width: 2.0, height: 2.0)))
    }
    let size = CGSize(width: 12.0, height: 12.0 + 2.0 + 2.0)
    if inverted {
        return generateImage(size, contextGenerator: f)?.stretchableImage(withLeftCapWidth: Int(size.width / 2.0), topCapHeight: Int(size.height) - (Int(size.width) + 1))
    } else {
        return generateImage(size, rotatedContext: f)?.stretchableImage(withLeftCapWidth: Int(size.width / 2.0), topCapHeight: Int(size.width) + 1)
    }
}

public final class TextSelectionTheme {
    public let selection: UIColor
    public let knob: UIColor
    public let knobDiameter: CGFloat
    public let isDark: Bool
    
    public init(selection: UIColor, knob: UIColor, knobDiameter: CGFloat = 12.0, isDark: Bool) {
        self.selection = selection
        self.knob = knob
        self.knobDiameter = knobDiameter
        self.isDark = isDark
    }
}

private enum Knob {
    case left
    case right
}

public final class TextSelectionGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var longTapTimer: Timer?
    private var movingKnob: (Knob, CGPoint, CGPoint)?
    private var currentLocation: CGPoint?
    
    public var canBeginSelection: ((CGPoint) -> Bool)?
    public var beginSelection: ((CGPoint) -> Void)?
    fileprivate var knobAtPoint: ((CGPoint) -> (Knob, CGPoint)?)?
    fileprivate var moveKnob: ((Knob, CGPoint) -> Void)?
    public var finishedMovingKnob: (() -> Void)?
    public var clearSelection: (() -> Void)?
    public private(set) var didRecognizeTap: Bool = false
    fileprivate var isSelecting: Bool = false
    
    override public init(target: Any?, action: Selector?) {
        super.init(target: nil, action: nil)
        
        self.delegate = self
    }
    
    override public func reset() {
        super.reset()
        
        self.longTapTimer?.invalidate()
        self.longTapTimer = nil
        
        self.movingKnob = nil
        self.currentLocation = nil
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        let currentLocation = touches.first?.location(in: self.view)
        self.currentLocation = currentLocation
        
        if let currentLocation = currentLocation {
            if let (knob, knobPosition) = self.knobAtPoint?(currentLocation) {
                self.movingKnob = (knob, knobPosition, currentLocation)
                cancelScrollViewGestures(view: self.view?.superview)
                self.state = .began
            } else if self.canBeginSelection?(currentLocation) ?? true {
                if self.longTapTimer == nil {
                    final class TimerTarget: NSObject {
                        let f: () -> Void
                        
                        init(_ f: @escaping () -> Void) {
                            self.f = f
                        }
                        
                        @objc func event() {
                            self.f()
                        }
                    }
                    let longTapTimer = Timer(timeInterval: 0.3, target: TimerTarget({ [weak self] in
                        self?.longTapEvent()
                    }), selector: #selector(TimerTarget.event), userInfo: nil, repeats: false)
                    self.longTapTimer = longTapTimer
                    RunLoop.main.add(longTapTimer, forMode: .common)
                }
            } else {
                self.state = .failed
            }
        }
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        let currentLocation = touches.first?.location(in: self.view)
        self.currentLocation = currentLocation
        
        if let (knob, initialKnobPosition, initialGesturePosition) = self.movingKnob, let currentLocation = currentLocation {
            self.moveKnob?(knob, CGPoint(x: initialKnobPosition.x + currentLocation.x - initialGesturePosition.x, y: initialKnobPosition.y + currentLocation.y - initialGesturePosition.y))
        }
    }
    
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        if let longTapTimer = self.longTapTimer {
            self.longTapTimer = nil
            longTapTimer.invalidate()
            
            if self.isSelecting {
                self.didRecognizeTap = true
                DispatchQueue.main.async { [weak self] in
                    self?.didRecognizeTap = false
                }
            }
            
            self.clearSelection?()
        } else {
            if let _ = self.currentLocation, let _ = self.movingKnob {
                self.finishedMovingKnob?()
            }
        }
        self.state = .ended
    }
    
    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        self.state = .cancelled
    }
    
    private func longTapEvent() {
        if let currentLocation = self.currentLocation {
            self.beginSelection?(currentLocation)
            self.state = .ended
        }
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        return true
    }
}

public final class TextSelectionNodeView: UIView {
    var hitTestImpl: ((CGPoint, UIEvent?) -> UIView?)?
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return self.hitTestImpl?(point, event)
    }
}

public enum TextSelectionAction: Equatable {
    case copy
    case share
    case lookup
    case speak
    case translate
    case quote(range: Range<Int>)
}

public final class TextSelectionNode: ASDisplayNode {
    private let theme: TextSelectionTheme
    private let strings: PresentationStrings
    private let textNode: TextNode
    private let updateIsActive: (Bool) -> Void
    public var canBeginSelection: (CGPoint) -> Bool = { _ in true }
    public var updateRange: ((NSRange?) -> Void)?
    public var presentMenu: ((UIView, CGPoint, [ContextMenuAction]) -> Void)?
    private let present: (ViewController, Any?) -> Void
    private let rootNode: () -> ASDisplayNode?
    private let performAction: (NSAttributedString, TextSelectionAction) -> Void
    private var highlightOverlay: LinkHighlightingNode?
    private let leftKnob: ASImageNode
    private let rightKnob: ASImageNode
    
    private var currentRange: (Int, Int)?
    private var currentRects: [CGRect]?
    
    public let highlightAreaNode: ASDisplayNode
    
    public private(set) var recognizer: TextSelectionGestureRecognizer?
    private var displayLinkAnimator: DisplayLinkAnimator?
    
    public var enableCopy: Bool = true
    public var enableLookup: Bool = true
    public var enableQuote: Bool = false
    public var enableTranslate: Bool = true
    public var enableShare: Bool = true
    
    public var menuSkipCoordnateConversion: Bool = false
    
    public var didRecognizeTap: Bool {
        return self.recognizer?.didRecognizeTap ?? false
    }
    
    private weak var contextMenu: ContextMenuController?
    
    public init(theme: TextSelectionTheme, strings: PresentationStrings, textNode: TextNode, updateIsActive: @escaping (Bool) -> Void, present: @escaping (ViewController, Any?) -> Void, rootNode: @escaping () -> ASDisplayNode?, externalKnobSurface: UIView? = nil, performAction: @escaping (NSAttributedString, TextSelectionAction) -> Void) {
        self.theme = theme
        self.strings = strings
        self.textNode = textNode
        self.updateIsActive = updateIsActive
        self.present = present
        self.rootNode = rootNode
        self.performAction = performAction
        self.leftKnob = ASImageNode()
        self.leftKnob.isUserInteractionEnabled = false
        self.leftKnob.image = generateKnobImage(color: theme.knob, diameter: theme.knobDiameter)
        self.leftKnob.displaysAsynchronously = false
        self.leftKnob.displayWithoutProcessing = true
        self.leftKnob.alpha = 0.0
        self.rightKnob = ASImageNode()
        self.rightKnob.isUserInteractionEnabled = false
        self.rightKnob.image = generateKnobImage(color: theme.knob, diameter: theme.knobDiameter, inverted: true)
        self.rightKnob.displaysAsynchronously = false
        self.rightKnob.displayWithoutProcessing = true
        self.rightKnob.alpha = 0.0
        
        self.highlightAreaNode = ASDisplayNode()
        
        super.init()
        
        self.setViewBlock({
            return TextSelectionNodeView()
        })
        
        if let externalKnobSurface {
            externalKnobSurface.addSubnode(self.leftKnob)
            externalKnobSurface.addSubnode(self.rightKnob)
        } else {
            self.addSubnode(self.leftKnob)
            self.addSubnode(self.rightKnob)
        }
    }
    
    override public func didLoad() {
        super.didLoad()
        
        (self.view as? TextSelectionNodeView)?.hitTestImpl = { [weak self] point, event in
            return self?.hitTest(point, with: event)
        }
       
        let recognizer = TextSelectionGestureRecognizer(target: nil, action: nil)
        recognizer.knobAtPoint = { [weak self] point in
            return self?.knobAtPoint(point)
        }
        recognizer.moveKnob = { [weak self] knob, point in
            guard let strongSelf = self, let cachedLayout = strongSelf.textNode.cachedLayout, let _ = cachedLayout.attributedString, let currentRange = strongSelf.currentRange else {
                return
            }
            
            let mappedPoint = strongSelf.view.convert(point, to: strongSelf.textNode.view)
            if let stringIndex = strongSelf.textNode.attributesAtPoint(mappedPoint, orNearest: true)?.0 {
                var updatedLeft = currentRange.0
                var updatedRight = currentRange.1
                switch knob {
                case .left:
                    updatedLeft = stringIndex
                case .right:
                    updatedRight = stringIndex
                }
                if strongSelf.currentRange?.0 != updatedLeft || strongSelf.currentRange?.1 != updatedRight {
                    strongSelf.currentRange = (updatedLeft, updatedRight)
                    let updatedRange = NSRange(location: min(updatedLeft, updatedRight), length: max(updatedLeft, updatedRight) - min(updatedLeft, updatedRight))
                    strongSelf.updateSelection(range: updatedRange, animateIn: false)
                }
                
                if let scrollView = findScrollView(view: strongSelf.view) {
                    let scrollPoint = strongSelf.view.convert(point, to: scrollView)
                    scrollView.scrollRectToVisible(CGRect(origin: CGPoint(x: scrollPoint.x, y: scrollPoint.y - 50.0), size: CGSize(width: 1.0, height: 100.0)), animated: false)
                }
            }
        }
        recognizer.finishedMovingKnob = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.displayMenu()
        }
        recognizer.beginSelection = { [weak self] point in
            guard let strongSelf = self, let cachedLayout = strongSelf.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
                return
            }
            
            strongSelf.dismissSelection()
            
            let mappedPoint = strongSelf.view.convert(point, to: strongSelf.textNode.view)
            var resultRange: NSRange?
            if let stringIndex = strongSelf.textNode.attributesAtPoint(mappedPoint, orNearest: false)?.0 {
                let string = attributedString.string as NSString
                
                let inputRange = CFRangeMake(0, string.length)
                let flag = UInt(kCFStringTokenizerUnitWord)
                let locale = CFLocaleCopyCurrent()
                let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, string as CFString, inputRange, flag, locale)
                var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
                
                while !tokenType.isEmpty {
                    let currentTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                    if currentTokenRange.location <= stringIndex && currentTokenRange.location + currentTokenRange.length > stringIndex {
                        resultRange = NSRange(location: currentTokenRange.location, length: currentTokenRange.length)
                        break
                    }
                    tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
                }
                if resultRange == nil {
                    resultRange = NSRange(location: stringIndex, length: 1)
                }
            }
            
            strongSelf.currentRange = resultRange.flatMap {
                ($0.lowerBound, $0.upperBound)
            }
            strongSelf.updateSelection(range: resultRange, animateIn: true)
            strongSelf.displayMenu()
            strongSelf.recognizer?.isSelecting = true
            strongSelf.updateIsActive(true)
        }
        recognizer.clearSelection = { [weak self] in
            self?.dismissSelection()
            self?.updateIsActive(false)
        }
        recognizer.canBeginSelection = { [weak self] point in
            guard let self else {
                return false
            }
            return self.canBeginSelection(point)
        }
        self.recognizer = recognizer
        self.view.addGestureRecognizer(recognizer)
    }
    
    public func updateLayout() {
        if let currentRange = self.currentRange {
            let updatedMin = currentRange.0
            let updatedMax = currentRange.1
            let updatedRange = NSRange(location: min(updatedMin, updatedMax), length: max(updatedMin, updatedMax) - min(updatedMin, updatedMax))
            
            self.updateSelection(range: updatedRange, animateIn: false)
        }
    }
    
    public func pretendInitiateSelection() {
        guard let cachedLayout = self.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
            return
        }
        
        var resultRange: NSRange?
        let stringIndex = 0
        let string = attributedString.string as NSString
        
        let inputRange = CFRangeMake(0, string.length)
        let flag = UInt(kCFStringTokenizerUnitWord)
        let locale = CFLocaleCopyCurrent()
        let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, string as CFString, inputRange, flag, locale)
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        
        while !tokenType.isEmpty {
            let currentTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if currentTokenRange.location <= stringIndex && currentTokenRange.location + currentTokenRange.length > stringIndex  {
                resultRange = NSRange(location: currentTokenRange.location, length: currentTokenRange.length)
                break
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        if resultRange == nil {
            resultRange = NSRange(location: stringIndex, length: 1)
        }
        
        self.currentRange = resultRange.flatMap {
            ($0.lowerBound, $0.upperBound)
        }
        self.updateSelection(range: resultRange, animateIn: true)
        self.updateIsActive(true)
    }
    
    public func pretendExtendSelection(to index: Int) {
        guard let cachedLayout = self.textNode.cachedLayout, let _ = cachedLayout.attributedString, let endRangeRect = cachedLayout.rangeRects(in: NSRange(location: index, length: 1))?.rects.first else {
            return
        }
        let startPoint = self.rightKnob.frame.center
        let endPoint = endRangeRect.center
        let displayLinkAnimator = DisplayLinkAnimator(duration: 0.3, from: 0.0, to: 1.0, update: { [weak self] progress in
            guard let strongSelf = self else {
                return
            }
            let point = CGPoint(x: (1.0 - progress) * startPoint.x + progress * endPoint.x, y: (1.0 - progress) * startPoint.y + progress * endPoint.y)
            strongSelf.recognizer?.moveKnob?(.right, point)
        }, completion: {
        })
        self.displayLinkAnimator = displayLinkAnimator
    }
    
    public func setSelection(range: NSRange, displayMenu: Bool) {
        guard let cachedLayout = self.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
            return
        }
        let range = self.convertSelectionFromOriginalText(attributedString: attributedString, range: range)
        
        self.currentRange = (range.lowerBound, range.upperBound)
        self.updateSelection(range: range, animateIn: true)
        self.updateIsActive(true)
        
        if displayMenu {
            self.displayMenu()
        }
    }
    
    private func convertSelectionToOriginalText(attributedString: NSAttributedString, range: NSRange) -> NSRange {
        var adjustedRange = range
        
        do {
            attributedString.enumerateAttribute(originalTextAttributeKey, in: NSRange(location: 0, length: range.lowerBound), options: [], using: { value, range, stop in
                guard let value = value as? OriginalTextAttribute else {
                    return
                }
                let updatedSubstring = NSMutableAttributedString(string: value.string)
                let difference = updatedSubstring.length - range.length
                
                adjustedRange.location += difference
            })
        }
        
        do {
            attributedString.enumerateAttribute(originalTextAttributeKey, in: range, options: [], using: { value, range, stop in
                guard let value = value as? OriginalTextAttribute else {
                    return
                }
                let updatedSubstring = NSMutableAttributedString(string: value.string)
                let difference = updatedSubstring.length - range.length
                
                adjustedRange.length += difference
            })
        }
        
        return adjustedRange
    }
    
    private func convertSelectionFromOriginalText(attributedString: NSAttributedString, range: NSRange) -> NSRange {
        var adjustedRange = range
        
        final class PreviousText: NSObject {
            let id: Int
            let string: String
            
            init(id: Int, string: String) {
                self.id = id
                self.string = string
            }
        }
        
        var nextId = 0
        let attributedString = NSMutableAttributedString(attributedString: attributedString)
        var fullRange = NSRange(location: 0, length: attributedString.length)
        while true {
            var found = false
            attributedString.enumerateAttribute(originalTextAttributeKey, in: fullRange, options: [], using: { value, range, stop in
                if let value = value as? OriginalTextAttribute {
                    let updatedSubstring = NSMutableAttributedString(string: value.string)
                    
                    let replacementRange = NSRange(location: 0, length: updatedSubstring.length)
                    updatedSubstring.addAttributes(attributedString.attributes(at: range.location, effectiveRange: nil), range: replacementRange)
                    updatedSubstring.addAttribute(NSAttributedString.Key(rawValue: "__previous_text"), value: PreviousText(id: nextId, string: attributedString.attributedSubstring(from: range).string), range: replacementRange)
                    nextId += 1
                    
                    attributedString.replaceCharacters(in: range, with: updatedSubstring)
                    let updatedRange = NSRange(location: range.location, length: updatedSubstring.length)
                    
                    found = true
                    stop.pointee = ObjCBool(true)
                    fullRange = NSRange(location: updatedRange.upperBound, length: fullRange.upperBound - range.upperBound)
                }
            })
            if !found {
                break
            }
        }
        
        do {
            attributedString.enumerateAttribute(NSAttributedString.Key(rawValue: "__previous_text"), in: NSRange(location: 0, length: range.lowerBound), options: [], using: { value, range, stop in
                guard let value = value as? PreviousText else {
                    return
                }
                let updatedSubstring = NSMutableAttributedString(string: value.string)
                let difference = updatedSubstring.length - range.length
                
                adjustedRange.location += difference
            })
        }
        
        do {
            attributedString.enumerateAttribute(NSAttributedString.Key(rawValue: "__previous_text"), in: range, options: [], using: { value, range, stop in
                guard let value = value as? PreviousText else {
                    return
                }
                let updatedSubstring = NSMutableAttributedString(string: value.string)
                let difference = updatedSubstring.length - range.length
                
                adjustedRange.length += difference
            })
        }
        
        return adjustedRange
    }
    
    public func getSelection() -> NSRange? {
        guard let currentRange = self.currentRange, let cachedLayout = self.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
            return nil
        }
        let range = NSRange(location: min(currentRange.0, currentRange.1), length: max(currentRange.0, currentRange.1) - min(currentRange.0, currentRange.1))
        return self.convertSelectionToOriginalText(attributedString: attributedString, range: range)
    }
    
    private func updateSelection(range: NSRange?, animateIn: Bool) {
        self.updateRange?(range)
        
        var rects: (rects: [CGRect], start: TextRangeRectEdge, end: TextRangeRectEdge)?
        
        if let range = range {
            rects = self.textNode.rangeRects(in: range)
        }
        
        self.currentRects = rects?.rects
        
        if let (rects, startEdge, endEdge) = rects, !rects.isEmpty {
            let highlightOverlay: LinkHighlightingNode
            if let current = self.highlightOverlay {
                highlightOverlay = current
            } else {
                highlightOverlay = LinkHighlightingNode(color: self.theme.selection)
                highlightOverlay.isUserInteractionEnabled = false
                highlightOverlay.innerRadius = 2.0
                highlightOverlay.outerRadius = 2.0
                highlightOverlay.inset = 1.0
                highlightOverlay.useModernPathCalculation = false
                
                self.highlightOverlay = highlightOverlay
                self.highlightAreaNode.addSubnode(highlightOverlay)
            }
            highlightOverlay.frame = self.bounds
            highlightOverlay.updateRects(rects)
            if let image = self.leftKnob.image {
                self.leftKnob.frame = CGRect(origin: CGPoint(x: floor(startEdge.x - image.size.width / 2.0), y: startEdge.y - self.theme.knobDiameter), size: CGSize(width: image.size.width, height: self.theme.knobDiameter + startEdge.height))
                self.rightKnob.frame = CGRect(origin: CGPoint(x: floor(endEdge.x - image.size.width / 2.0), y: endEdge.y), size: CGSize(width: image.size.width, height: self.theme.knobDiameter + endEdge.height))
            }
            if self.leftKnob.alpha.isZero {
                highlightOverlay.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue)
                self.leftKnob.alpha = 1.0
                self.leftKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.14, delay: 0.19)
                self.rightKnob.alpha = 1.0
                self.rightKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.14, delay: 0.19)
                self.leftKnob.layer.animateSpring(from: 0.5 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.2, delay: 0.25, initialVelocity: 0.0, damping: 80.0)
                self.rightKnob.layer.animateSpring(from: 0.5 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.2, delay: 0.25, initialVelocity: 0.0, damping: 80.0)
                
                if animateIn {
                    var result = CGRect()
                    for rect in rects {
                        if result.isEmpty {
                            result = rect
                        } else {
                            result = result.union(rect)
                        }
                    }
                    highlightOverlay.layer.animateScale(from: 2.0, to: 1.0, duration: 0.26)
                    let fromResult = CGRect(origin: CGPoint(x: result.minX - result.width / 2.0, y: result.minY - result.height / 2.0), size: CGSize(width: result.width * 2.0, height: result.height * 2.0))
                    highlightOverlay.layer.animatePosition(from: CGPoint(x: (-fromResult.midX + highlightOverlay.bounds.midX) / 1.0, y: (-fromResult.midY + highlightOverlay.bounds.midY) / 1.0), to: CGPoint(), duration: 0.26, additive: true)
                }
            }
        } else if let highlightOverlay = self.highlightOverlay {
            self.highlightOverlay = nil
            highlightOverlay.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { [weak highlightOverlay] _ in
                highlightOverlay?.removeFromSupernode()
            })
            self.leftKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.18)
            self.leftKnob.alpha = 0.0
            self.leftKnob.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18)
            self.rightKnob.alpha = 0.0
            self.rightKnob.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18)
        }
    }
    
    private func knobAtPoint(_ point: CGPoint) -> (Knob, CGPoint)? {
        if !self.leftKnob.alpha.isZero, self.leftKnob.frame.insetBy(dx: -4.0, dy: -8.0).contains(point) {
            return (.left, self.leftKnob.frame.offsetBy(dx: 0.0, dy: self.leftKnob.frame.width / 2.0).center)
        }
        if !self.rightKnob.alpha.isZero, self.rightKnob.frame.insetBy(dx: -4.0, dy: -8.0).contains(point) {
            return (.right, self.rightKnob.frame.offsetBy(dx: 0.0, dy: -self.rightKnob.frame.width / 2.0).center)
        }
        if !self.leftKnob.alpha.isZero, self.leftKnob.frame.insetBy(dx: -14.0, dy: -14.0).contains(point) {
            return (.left, self.leftKnob.frame.offsetBy(dx: 0.0, dy: self.leftKnob.frame.width / 2.0).center)
        }
        if !self.rightKnob.alpha.isZero, self.rightKnob.frame.insetBy(dx: -14.0, dy: -14.0).contains(point) {
            return (.right, self.rightKnob.frame.offsetBy(dx: 0.0, dy: -self.rightKnob.frame.width / 2.0).center)
        }
        return nil
    }
    
    private func dismissSelection() {
        self.currentRange = nil
        self.recognizer?.isSelecting = false
        self.updateSelection(range: nil, animateIn: false)
        
        self.contextMenu?.dismiss()
        self.contextMenu = nil
    }
    
    public func cancelSelection() {
        self.dismissSelection()
        self.updateIsActive(false)
    }
    
    private func displayMenu() {
        guard let currentRects = self.currentRects, !currentRects.isEmpty, let currentRange = self.currentRange, let cachedLayout = self.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
            return
        }
        let range = NSRange(location: min(currentRange.0, currentRange.1), length: max(currentRange.0, currentRange.1) - min(currentRange.0, currentRange.1))
        var completeRect = currentRects[0]
        for i in 0 ..< currentRects.count {
            completeRect = completeRect.union(currentRects[i])
        }
        completeRect = completeRect.insetBy(dx: 0.0, dy: -12.0)
        
        let string = NSMutableAttributedString(attributedString: attributedString.attributedSubstring(from: range))
        
        var fullRange = NSRange(location: 0, length: string.length)
        while true {
            var found = false
            string.enumerateAttribute(originalTextAttributeKey, in: fullRange, options: [], using: { value, range, stop in
                if let value = value as? OriginalTextAttribute {
                    let updatedSubstring = NSMutableAttributedString(string: value.string)
                    
                    let replacementRange = NSRange(location: 0, length: updatedSubstring.length)
                    updatedSubstring.addAttributes(string.attributes(at: range.location, effectiveRange: nil), range: replacementRange)
                    
                    string.replaceCharacters(in: range, with: updatedSubstring)
                    let updatedRange = NSRange(location: range.location, length: updatedSubstring.length)
                    
                    found = true
                    stop.pointee = ObjCBool(true)
                    fullRange = NSRange(location: updatedRange.upperBound, length: fullRange.upperBound - range.upperBound)
                }
            })
            if !found {
                break
            }
        }
        
        let adjustedRange = self.convertSelectionToOriginalText(attributedString: attributedString, range: range)
        
        var actions: [ContextMenuAction] = []
        if self.enableCopy {
            actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuCopy, accessibilityLabel: self.strings.Conversation_ContextMenuCopy), action: { [weak self] in
                self?.performAction(string, .copy)
                self?.cancelSelection()
            }))
        }
        if self.enableQuote {
            actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuQuote, accessibilityLabel: self.strings.Conversation_ContextMenuQuote), action: { [weak self] in
                self?.performAction(string, .quote(range: adjustedRange.lowerBound ..< adjustedRange.upperBound))
                self?.cancelSelection()
            }))
        }
        if self.enableLookup {
            actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuLookUp, accessibilityLabel: self.strings.Conversation_ContextMenuLookUp), action: { [weak self] in
                self?.performAction(string, .lookup)
                self?.cancelSelection()
            }))
        }
        if #available(iOS 15.0, *) {
            if self.enableTranslate {
                actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuTranslate, accessibilityLabel: self.strings.Conversation_ContextMenuTranslate), action: { [weak self] in
                    self?.performAction(string, .translate)
                    self?.cancelSelection()
                }))
            }
        }
//        if isSpeakSelectionEnabled() {
//            actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuSpeak, accessibilityLabel: self.strings.Conversation_ContextMenuSpeak), action: { [weak self] in
//                self?.performAction(attributedText, .speak)
//                self?.dismissSelection()
//            }))
//        }
        
        let realFullRange = NSRange(location: 0, length: attributedString.length)
        if range != realFullRange {
            actions.append(ContextMenuAction(content: .text(title: self.strings.TextSelection_SelectAll, accessibilityLabel: self.strings.TextSelection_SelectAll), action: { [weak self] in
                guard let self else {
                    return
                }
                self.contextMenu?.dismiss()
                self.setSelection(range: realFullRange, displayMenu: true)
            }))
        } else if self.enableShare {
            actions.append(ContextMenuAction(content: .text(title: self.strings.Conversation_ContextMenuShare, accessibilityLabel: self.strings.Conversation_ContextMenuShare), action: { [weak self] in
                self?.performAction(string, .share)
                self?.cancelSelection()
            }))
        }
        
        self.contextMenu?.dismiss()
        
        let contextMenu = makeContextMenuController(actions: actions, catchTapsOutside: false, hasHapticFeedback: false, isDark: self.theme.isDark, skipCoordnateConversion: self.menuSkipCoordnateConversion)
        contextMenu.dismissOnTap = { [weak self] view, point in
            guard let self else {
                return true
            }
            if self.knobAtPoint(view.convert(point, to: self.view)) == nil {
                //self.cancelSelection()
                return true
            }
            return true
        }
        self.contextMenu = contextMenu
        self.present(contextMenu, ContextMenuControllerPresentationArguments(sourceNodeAndRect: { [weak self] in
            guard let strongSelf = self, let rootNode = strongSelf.rootNode() else {
                return nil
            }
            
            if strongSelf.menuSkipCoordnateConversion {
                return (strongSelf, strongSelf.view.convert(completeRect, to: rootNode.view), rootNode, rootNode.bounds)
            } else {
                return (strongSelf, completeRect, rootNode, rootNode.bounds)
            }
        }, bounce: false))
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.knobAtPoint(point) != nil {
            return self.view
        }
        if self.bounds.contains(point) {
            return self.view
        }
        return nil
    }
}
