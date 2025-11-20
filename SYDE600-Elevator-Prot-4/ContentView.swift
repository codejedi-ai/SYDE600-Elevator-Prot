//
//  ContentView.swift
//  SYDE600-Elevator-Prot-4
//
//  Created by Darcy Liu on 2025-10-20.
//

import SwiftUI
#if os(iOS)
import AVFoundation
internal import Combine
#endif

// MARK: - View Classes
@MainActor
class ElevatorDisplayViewController: ObservableObject {
    @Published var showCustomerSupport: Bool = false
    private let model: ElevatorModel
    
    init(model: ElevatorModel) {
        self.model = model
    }
    
    func showSupport() {
        showCustomerSupport = true
    }
    
    func hideSupport() {
        showCustomerSupport = false
    }
}

@MainActor
class FloorSelectorViewController: ObservableObject {
    private let model: ElevatorModel
    
    // Scrolling state - handled in view, not model
    @Published var shouldAllowAutoScroll: Bool = true
    @Published var autoscrollDisableDuration: TimeInterval = 5.0
    @Published var shouldScrollToCurrentFloor: Bool = false // Triggers manual scroll to current floor
    @Published var scrollToFloor: Int? = nil // The floor to scroll to when shouldScrollToCurrentFloor is true
    
    private var scrollIdleTimer: Timer?
    private var lastScrollTime: Date = Date()
    
    init(model: ElevatorModel) {
        self.model = model
    }
    
    deinit {
        scrollIdleTimer?.invalidate()
    }
    
    /// Called when user presses a floor button
    func enqueueFloor(_ floor: Int) {
        model.enqueue(floor)
    }
    
    /// Called when user starts scrolling - disable autoscroll
    func handleUserScrolling() {
        shouldAllowAutoScroll = false
        lastScrollTime = Date()
        
        // Invalidate existing timer
        scrollIdleTimer?.invalidate()
        
        // Set new timer with configurable duration
        scrollIdleTimer = Timer.scheduledTimer(withTimeInterval: autoscrollDisableDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let timeSinceLastScroll = Date().timeIntervalSince(self.lastScrollTime)
                guard timeSinceLastScroll >= self.autoscrollDisableDuration else {
                    // Reschedule if not enough time has passed
                    let remainingTime = self.autoscrollDisableDuration - timeSinceLastScroll
                    self.scrollIdleTimer?.invalidate()
                    self.scrollIdleTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let self = self,
                                  Date().timeIntervalSince(self.lastScrollTime) >= self.autoscrollDisableDuration else {
                                return
                            }
                            self.shouldAllowAutoScroll = true
                        }
                    }
                    return
                }
                self.shouldAllowAutoScroll = true
            }
        }
    }
    
    /// Called when user stops scrolling
    func handleUserScrollRelease() {
        lastScrollTime = Date()
        // Timer will handle re-enabling autoscroll
    }
    
    /// Set the duration (in seconds) that autoscroll should be disabled after scrolling
    func setAutoscrollDisableDuration(_ duration: TimeInterval) {
        autoscrollDisableDuration = max(1.0, duration)
    }
    
    /// Centralized function to perform auto scroll to a specific floor
    /// - Parameters:
    ///   - floor: The floor number to scroll to (defaults to current floor from model)
    ///   - force: If true, enables autoscroll even if it was disabled (default: true)
    ///   - delay: Optional delay in seconds before scrolling (default: 0)
    func performAutoScroll(to floor: Int? = nil, force: Bool = true, delay: TimeInterval = 0) {
        if force {
            shouldAllowAutoScroll = true
        }
        
        // Cancel any existing timer
        scrollIdleTimer?.invalidate()
        
        let targetFloor = floor ?? model.currentFloor
        scrollToFloor = targetFloor
        
        if delay > 0 {
            // Schedule scroll after delay
            scrollIdleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.shouldScrollToCurrentFloor = true
                    // Reset the flag after a brief moment
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        await MainActor.run {
                            self.shouldScrollToCurrentFloor = false
                            self.scrollToFloor = nil
                        }
                    }
                }
            }
        } else {
            // Scroll immediately
            shouldScrollToCurrentFloor = true
            // Reset the flag after a brief moment
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    shouldScrollToCurrentFloor = false
                    scrollToFloor = nil
                }
            }
        }
    }
    
    /// Perform auto scroll to current floor (convenience method for button)
    func performAutoScroll() {
        performAutoScroll(to: nil, force: true, delay: 0)
    }
}

// MARK: - Main Controller
@MainActor
class ElevatorController: ObservableObject {
    let model: ElevatorModel
    let displayViewController: ElevatorDisplayViewController
    let floorSelectorViewController: FloorSelectorViewController
    
    init() {
        self.model = ElevatorModel()
        self.displayViewController = ElevatorDisplayViewController(model: model)
        self.floorSelectorViewController = FloorSelectorViewController(model: model)
        

    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var controller = ElevatorController()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left half - Elevator doors and display
                ElevatorDisplayView(
                    model: controller.model,
                    displayViewController: controller.displayViewController,
                    floorSelectorViewController: controller.floorSelectorViewController,
                    geometry: geometry
                )
                .frame(width: geometry.size.width / 2)
                .background(Color.black)

                // Right half - Floor selector
                FloorSelectorView(
                    model: controller.model,
                    viewController: controller.floorSelectorViewController,
                    geometry: geometry
                )
                .frame(width: geometry.size.width / 2)
                .background(Color(white: 0.15))
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            controller.model.haltAllOperations()
        }
    }
}

struct ElevatorDisplayView: View {
    @ObservedObject var model: ElevatorModel
    @ObservedObject var displayViewController: ElevatorDisplayViewController
    @ObservedObject var floorSelectorViewController: FloorSelectorViewController
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            // Floor display section
            VStack(spacing: 10) {
                Text("Current Floor")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                Text("\(model.currentFloor)")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(model.elevatorState == .moving ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: model.currentFloor)

                VStack(spacing: 5) {
                    Text(model.elevatorStateText)
                        .font(.title3)
                        .foregroundColor(.white)
                    
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)

            // Doors section - centered in remaining space
            VStack {
                Spacer()

                CenterOpeningDoorsView(doorOffset: model.doorOffset)
                    .frame(height: geometry.size.height * 0.35)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .frame(maxWidth: .infinity)

            // Customer Support and Auto Scroll Buttons section
            HStack(spacing: 15) {
                // Customer Support Button
                Button(action: {
                    displayViewController.showSupport()
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Customer Support")
                            .font(.title2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(Color.red)
                    .cornerRadius(15)
                }
                
                // Auto Scroll Button
                Button(action: {
                    floorSelectorViewController.performAutoScroll()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Auto Scroll")
                            .font(.title2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(Color.blue)
                    .cornerRadius(15)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
        }
        .alert("Customer Support", isPresented: $displayViewController.showCustomerSupport) {
            Button("Close", role: .cancel) {
                displayViewController.hideSupport()
            }
        } message: {
            Text("Emergency support is available 24/7.\nCall: 1-800-ELEVATOR")
        }
    }
}

struct FloorSelectorView: View {
    @ObservedObject var model: ElevatorModel
    @ObservedObject var viewController: FloorSelectorViewController
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select Floor")
                .font(.title)
                .foregroundColor(.white)
                .padding(.top, 40)
                .padding(.bottom, 20)

            // Scrollable floor picker
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Floors in reverse order (highest to lowest)
                        ForEach((1...model.totalFloors).reversed(), id: \.self) { floor in
                            FloorButton(
                                floor: floor,
                                isSelected: model.selectedFloor == floor,
                                isCurrent: model.currentFloor == floor,
                                isQueued: model.queuedFloors.contains(floor)
                            ) {
                                viewController.enqueueFloor(floor)
                            }
                            .id(floor)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    // Scroll to floor 1 at the bottom on start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(1, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: model.currentFloor) { _, newFloor in
                    // When elevator state changes, use centralized autoscroll function
                    if model.elevatorState == .moving {
                        if viewController.shouldAllowAutoScroll {
                            // Use centralized function to scroll to new floor
                            viewController.performAutoScroll(to: newFloor, force: false, delay: 0)
                        }
                        // If autoscroll is disabled, don't scroll (user is manually scrolling)
                    }
                }
                .onChange(of: model.elevatorState) { _, newState in
                    // When elevator stops at a floor, scroll to current floor after a brief delay
                    if newState == .stopped && model.doorState == .open {
                        if viewController.shouldAllowAutoScroll {
                            // Scroll to current floor after doors open (0.5 second delay)
                            viewController.performAutoScroll(to: model.currentFloor, force: false, delay: 0.5)
                        }
                    }
                }
                .onChange(of: viewController.shouldScrollToCurrentFloor) { _, shouldScroll in
                    // When auto scroll is triggered (button or elevator), scroll to target floor
                    if shouldScroll, let targetFloor = viewController.scrollToFloor {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(targetFloor, anchor: .center)
                        }
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    // Use SwiftUI's built-in scroll phase detection
                    switch newPhase {
                    case .interacting:
                        // User started scrolling - disable autoscroll and set timer
                        viewController.handleUserScrolling()
                    case .idle:
                        // User stopped scrolling - update last interaction time
                        viewController.handleUserScrollRelease()
                    default:
                        break
                    }
                }
            }
        }
    }
}


struct FloorButton: View {
    let floor: Int
    let isSelected: Bool
    let isCurrent: Bool
    let isQueued: Bool
    let action: () -> Void

    private var textColor: Color {
        if isCurrent { return .white }        // Current floor: white text on green
        if isSelected { return .black }       // Selected: black text on yellow
        if isQueued { return .white }         // Queued: white text on orange
        return .white                         // Default: white text
    }
    
    private var backgroundColor: Color {
        if isCurrent { return Color.green.opacity(0.3) }     // Current floor: green
        if isSelected { return Color.yellow }                // Selected: bright yellow
        if isQueued { return Color.orange.opacity(0.4) }     // Queued: orange
        return Color.gray.opacity(0.3)                       // Default: gray
    }
    
    private var borderColor: Color {
        if isCurrent { return Color.green }          // Current floor: green border
        if isSelected { return Color.yellow }        // Selected: yellow border
        if isQueued { return Color.orange }          // Queued: orange border
        return Color.white.opacity(0.2)              // Default: subtle white
    }
    
    private var borderWidth: CGFloat {
        if isCurrent { return 3 }       // Current floor: thick border
        if isSelected { return 3 }      // Selected: thick border
        if isQueued { return 3 }        // Queued: thick border
        return 2                        // Default: normal border
    }

    var body: some View {
        HStack {
            Spacer()

            VStack(spacing: 5) {
                Text("Floor \(floor)")
                    .font(.system(size: 36, weight: .semibold))

                if isCurrent {
                    Text("● Current")
                        .font(.caption)
                        .foregroundColor(.white)
                } else if isQueued {
                    Text("✓ Queued")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .onTapGesture {
                // Simple tap - execute action immediately
                action()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
}
