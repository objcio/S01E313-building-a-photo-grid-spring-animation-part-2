// Photos are from https://unsplash.com

import SwiftUI

struct TransitionIsActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var transitionIsActive: Bool {
        get { self[TransitionIsActiveKey.self] }
        set { self[TransitionIsActiveKey.self] = newValue }
    }
}

struct TransitionReader<Content: View>: View {
    var content: (Bool) -> Content
    @Environment(\.transitionIsActive) var active
    
    var body: some View {
        content(active)
    }
}

struct TransitionActive: ViewModifier {
    var active: Bool
    
    func body(content: Content) -> some View {
        content
            .environment(\.transitionIsActive, active)
    }
}

struct DragState {
    var value: DragGesture.Value
    var detailPosition: CGPoint
    
    var velocity: CGSize = .zero
    
    var target: CGPoint?
    
    mutating func update(_ newValue: DragGesture.Value) {
        let interval = newValue.time.timeIntervalSince(value.time)
        velocity = (newValue.translation - value.translation) / interval
        value = newValue
    }
    
    var currentPosition: CGPoint {
        detailPosition + value.translation
    }
    
    var directionToTarget: CGPoint? {
        target.map { $0 - currentPosition }
    }
    
    var shouldClose: Bool {
        velocity.height > 0
    }
    
    var initialVelocity: CGFloat? {
        guard let d = directionToTarget else { return nil }
        let projectedVelocityLength = velocity.dot(d) / d.length
        let normalizedProjectedVelocity = projectedVelocityLength / d.length
        return normalizedProjectedVelocity
    }
}

extension DragState: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Line(start: value.location, end: value.location + velocity)
                .foregroundColor(.orange)
            if let d = directionToTarget {
                Line(start: value.location, end: value.location + d)
                    .foregroundColor(.blue)
                let initial = d * initialVelocity!
                Line(start: value.location, end: value.location + initial)
                    .foregroundColor(.green)
            }
        }
    }
}

struct PhotosView: View {
    @State private var detail: Int? = nil
    @State private var slowAnimations = false
    @Namespace private var namespace
    @Namespace private var dummyNS
    
    
    var body: some View {
        VStack {
            Toggle("Slow Animations", isOn: $slowAnimations)
            ZStack {
                photoGrid
                    .opacity(gridOpacity)
                    .animation(animation, value: gridOpacity == 0)
                detailView
            }
            .animation(animation, value: detail)
        }.overlay {
            debug?.ignoresSafeArea()
        }
    }
    
    var animation: Animation {
        .default.speed(slowAnimations ? 0.2 : 1)
    }
    
    @State private var gridCenters: [Int:CGPoint] = [:]
    @State private var detailCenter: CGPoint = .zero
    @State private var dragState: DragState?
    @State private var debug: DragState?
    
    var detailGesture: some Gesture {
        let tap = TapGesture().onEnded {
            detail = nil
        }
        let drag = DragGesture(coordinateSpace: .global).onChanged { value in
            if dragState == nil {
                dragState = DragState(value: value, detailPosition: detailCenter)
            } else {
                dragState!.update(value)
            }
        }.onEnded { value in
            guard var d = dragState else { return }
            d.target = d.shouldClose ? gridCenters[detail!]! : detailCenter
            debug = d
            withAnimation(.interpolatingSpring(mass: 5, stiffness: 200, damping: 100, initialVelocity: d.initialVelocity ?? 0).speed(slowAnimations ? 0.2 : 1)) {
                dragState = nil
                if d.shouldClose {
                    detail = nil
                }
            }
        }
        
        return drag.simultaneously(with: tap)
    }
    
    var offset: CGSize {
        dragState?.value.translation ?? .zero
    }
    
    var dragScale: CGFloat {
        guard offset.height > 0 else { return 1 }
        return 1 - offset.height/1000
    }
    
    var gridOpacity: CGFloat {
        guard detail != nil else { return 1 }
        return (1 - dragScale) * 1.3
    }
    
    @ViewBuilder
    var detailView: some View {
        if let d = detail {
            ZStack {
                TransitionReader { active in
                    Image("beach_\(d)")
                        .resizable()
                        .mask {
                            Rectangle().aspectRatio(1, contentMode: active ? .fit : .fill)
                        }
                        .matchedGeometryEffect(id: d, in: active ? namespace : dummyNS, isSource: false)
                        .aspectRatio(contentMode: .fit)
                        .offset(offset)
                        .background(GeometryReader { proxy in
                            Color.clear.onAppearOrChange(of: proxy.frame(in: .global).center) { detailCenter = $0 }
                        })
                        .scaleEffect(active ? 1 : dragScale)
                        .gesture(detailGesture)
                }
            }
            .zIndex(2)
            .id(d)
            .transition(.modifier(active: TransitionActive(active: true), identity: TransitionActive(active: false)))
        }
    }
    
    var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [.init(.adaptive(minimum: 100, maximum: .infinity), spacing: 3)], spacing: 3) {
                ForEach(1..<11) { ix in
                    Image("beach_\(ix)")
                        .resizable()
                        .measureGridCell(id: ix)
                        .matchedGeometryEffect(id: ix, in: namespace)
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                        .aspectRatio(1, contentMode: .fit)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            detail = ix
                        }
                }
            }
        }
        .onPreferenceChange(GridKey.self, perform: {
            gridCenters = $0
        })
    }
}

struct GridKey: PreferenceKey {
    static var defaultValue: [Int: CGPoint] = [:]
    static func reduce(value: inout [Int : CGPoint], nextValue: () -> [Int : CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func measureGridCell(id: Int) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: GridKey.self, value: [
                id: proxy.frame(in: .global).center
            ])
        })
    }
    
    func onAppearOrChange<Value: Equatable>(of value: Value, perform: @escaping (Value) -> ()) -> some View {
        self.onChange(of: value) { perform($0) }
            .onAppear { perform(value) }
    }
}

struct ContentView: View {
    var body: some View {
        PhotosView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
