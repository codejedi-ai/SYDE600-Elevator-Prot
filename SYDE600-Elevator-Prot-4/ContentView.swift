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
    
    init(model: ElevatorModel) {
        self.model = model
    }
    
    func selectFloor(_ floor: Int) {
        Task {
            await model.selectFloor(floor)
        }
    }
    
    func handleUserScrolling() {
        model.handleUserInteraction()
    }
    
    func handleUserScrollRelease() {
        model.handleUserRelease()
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
                    viewController: controller.displayViewController,
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
    @ObservedObject var viewController: ElevatorDisplayViewController
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

            // Customer Support Button section
            VStack(spacing: 15) {
                // Customer Support Button
                Button(action: {
                    viewController.showSupport()
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Customer Support")
                            .font(.title2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .background(Color.red)
                    .cornerRadius(15)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 50)
        }
        .alert("Customer Support", isPresented: $viewController.showCustomerSupport) {
            Button("Close", role: .cancel) {
                viewController.hideSupport()
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
                                viewController.selectFloor(floor)
                            }
                            .id(floor)
                        }
                    }
                }
                .onAppear {
                    // Scroll to floor 1 at the bottom on start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(1, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: model.currentFloor) { _, newFloor in
                    // Always update scroll position when elevator moves
                    if model.elevatorState == .moving {
                        if model.shouldAllowAutoScroll {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(newFloor, anchor: .center)
                            }
                        } else {
                            proxy.scrollTo(newFloor, anchor: .center)
                        }
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    // Use SwiftUI's built-in scroll phase detection
                    switch newPhase {
                    case .interacting:
                        viewController.handleUserScrolling()
                    case .idle:
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
