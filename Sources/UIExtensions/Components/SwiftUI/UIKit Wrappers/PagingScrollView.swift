//
//  PagingScrollView.swift
//  UIExtensions
//
//  Created by Luis Reisewitz on 21.01.20.
//  Copyright © 2020 Lautsprecher Teufel GmbH. All rights reserved.
//

#if canImport(UIKit)
import FoundationExtensions
import SwiftUI
import UIKit

/// Paging Scroll View adapted from
///  <https://github.com/izakpavel/SwiftUIPagingScrollView/blob/master/SwiftUIPagingScrollView/PagingScrollView.swift>
/// Currently supports horizontal paging only.
public struct PagingScrollView<DataCollection: RandomAccessCollection, PageType: View>: View where DataCollection.Element: Identifiable {

    /// Creates a horizontal paging scrollView.
    /// - Parameters:
    ///   - activePageIndex: Binding to the active Page Index. Will be updated from inside.
    ///   - items: The items to display.
    ///   - tileWidth: Closure that receives calculated PageWidth and returns the width for a single cell.
    ///   - tilePadding: How much padding there should be between cells.
    ///   - content: ViewBuilder for a single content cell. Content should probably use the
    ///     `FullFrameModifier` to expand to the full offered size.
    public init(activePageIndex: Binding<Int>,
                items: DataCollection,
                tileWidth: @escaping (CGFloat) -> CGFloat = { $0 },
                tilePadding: CGFloat,
                @ViewBuilder content: @escaping (DataCollection.Element) -> PageType) {
        self.items = items
        self.content = content

        self._activePageIndex = activePageIndex

        self.tileWidthClosure = tileWidth
        self.tilePadding = tilePadding
    }

    // MARK: Content Properties

    /// Collection of data to show.
    let items: DataCollection
    /// ViewBuilder for a single content cell.
    let content: (DataCollection.Element) -> PageType
    /// Index of current page 0..N-1
    @Binding var activePageIndex: Int

    // MARK: Layout Properties

    /// Width of item / tile. CGFloat passed in is the computed pageWidth of the ScrollView.
    private let tileWidthClosure: (CGFloat) -> CGFloat

    /// Padding between items
    private let tilePadding: CGFloat

    /// Some damping factor to reduce liveness. Currently we are not reducing liveness, as that felt weird.
    private let scrollDampingFactor: CGFloat = 1

    /// Current offset of all items
    @State var currentScrollOffset: CGFloat = 0

    /// Drag offset during drag gesture
    @State private var dragOffset: CGFloat = 0

    public var body: some View {
        GeometryReader { outerProxy in
            HStack(alignment: .center, spacing: self.tilePadding) {
                /// building items into HStack
                ForEach(self.items) { element in
                    self.content(element)
                        .offset(x: self.currentScrollOffset, y: 0)
                        .frame(width: self.tileWidth(for: outerProxy))
                }
            }
            .onAppear {
                self.currentScrollOffset = self.offsetForPageIndex(self.activePageIndex, proxy: outerProxy)
            }
            .offset(x: self.stackOffset(for: outerProxy), y: 0)
            .background(Color.black.opacity(0.00001)) // hack - this allows gesture recognizing even when background is transparent
            .frame(width: self.contentWidth(for: outerProxy))
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification), perform: { (_) in
                self.currentScrollOffset = self.computeCurrentScrollOffset(for: outerProxy)
            })
            .gesture(
                DragGesture(minimumDistance: 1,
                            coordinateSpace: .local)
                .onChanged { value in
                    self.dragOffset = value.translation.width
                    self.currentScrollOffset = self.computeCurrentScrollOffset(for: outerProxy)
                }
                .onEnded { value in
                    // compute nearest index
                    let velocityDiff = (value.predictedEndTranslation.width - self.dragOffset)
                        * self.scrollDampingFactor
                    // Calculate what the page would be after the drag
                    // using the final velocity.
                    let newPageIndex = self.indexPageForOffset(
                        self.currentScrollOffset + velocityDiff,
                        proxy: outerProxy
                    )
                    // Clamp the page so that a free scroll with a lot of
                    // velocity only skips to the next page, but not
                    // multiple pages.
                    let finalIndex = newPageIndex
                        .clamped(to: (self.activePageIndex - 1)...(self.activePageIndex + 1))
                    self.dragOffset = 0
                    withAnimation {
                        self.activePageIndex = finalIndex
                        self.currentScrollOffset = self.computeCurrentScrollOffset(for: outerProxy)
                    }
                }
            )
        }
    }
}

// MARK: - Private Layout Helpers
extension PagingScrollView {
    /// Calculates the offset for the given page index.
    /// - Parameters:
    ///   - index: Page Index
    ///   - proxy: Proxy that contains this view.
    private func offsetForPageIndex(_ index: Int, proxy: GeometryProxy) -> CGFloat {
        let activePageOffset = CGFloat(index) * (tileWidth(for: proxy) + tilePadding)

        return self.leadingOffset(for: proxy) - activePageOffset
    }

    /// Calculates the page index for the given scrollView offset.
    /// - Parameters:
    ///   - offset: Scrollview offset.
    ///   - proxy: Proxy that contains this view.
    private func indexPageForOffset(_ offset: CGFloat, proxy: GeometryProxy) -> Int {
        guard self.itemCount > 0 else {
            return 0
        }
        let offset = self.logicalScrollOffset(trueOffset: offset, proxy: proxy)
        let floatIndex = offset / (tileWidth(for: proxy) + tilePadding)
        var computedIndex = Int(round(floatIndex))
        computedIndex = max(computedIndex, 0)
        return min(computedIndex, self.itemCount - 1)
    }

    /// Current scroll offset applied on items.
    /// - Parameter proxy: Proxy that contains this view.
    private func computeCurrentScrollOffset(for proxy: GeometryProxy) -> CGFloat {
        return self.offsetForPageIndex(self.activePageIndex,
                                       proxy: proxy)
            + self.dragOffset
    }

    /// Logical offset starting at 0 for the first item - this makes computing the page index easier
    /// - Parameters:
    ///   - trueOffset: Real offset of the scrollView, without any modifications.
    ///   - proxy: Proxy that contains this view.
    private func logicalScrollOffset(trueOffset: CGFloat, proxy: GeometryProxy) -> CGFloat {
        return (trueOffset - leadingOffset(for: proxy)) * -1.0
    }

    /// How much of surrounding iems is still visible
    /// - Parameter proxy: Proxy that contains this view.
    private func tileRemain(for proxy: GeometryProxy) -> CGFloat {
        return (pageWidth(for: proxy) - tileWidth(for: proxy) - 2 * tilePadding) / 2
    }

    /// Returns usable pageWidth for the given proxy.
    /// - Parameter proxy: Proxy that contains this view.
    private func pageWidth(for proxy: GeometryProxy) -> CGFloat {
        return proxy.safeWidth
    }

    /// Total width of all content cells plus padding.
    /// - Parameter proxy: Proxy that contains this view.
    private func contentWidth(for proxy: GeometryProxy) -> CGFloat {
        (tileWidth(for: proxy) + tilePadding) * CGFloat(itemCount)
    }

    /// Offset to scroll on the first item
    /// - Parameter proxy: Proxy that contains this view.
    private func leadingOffset(for proxy: GeometryProxy) -> CGFloat {
        tileRemain(for: proxy) + tilePadding
    }

    /// Since the HStack is centered by default this offset actually moves it entirely to the left
    /// - Parameter proxy: Proxy that contains this view.
    private func stackOffset(for proxy: GeometryProxy) -> CGFloat {
        let remainingSpace = contentWidth(for: proxy)
            - pageWidth(for: proxy)
            - tilePadding
        return remainingSpace / 2
    }

    /// Number of items
    private var itemCount: Int {
        items.count
    }

    private func tileWidth(for proxy: GeometryProxy) -> CGFloat {
        let pageWidth = self.pageWidth(for: proxy)
        return tileWidthClosure(pageWidth)
    }
}
#endif