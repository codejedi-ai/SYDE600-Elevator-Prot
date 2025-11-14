//
//  ContentView.swift
//  testproject
//
//  Created by Darcy Liu on 2025-10-20.
//

import SwiftUI

enum ElevatorState {
    case idle
    case moving
    case arrived
    case doorsOpening
    case doorsOpen
    case doorsClosing
}

struct ContentView: View {
    @State private var selectedFloor: Int = 1
    @State private var currentFloor: Int = 1
    @State private var elevatorState: ElevatorState = .idle
    @State private var doorOffset: CGFloat = 0
    @State private var showCustomerSupport: Bool = false

    let totalFloors = 20

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left half - Elevator doors and display
                VStack(spacing: 0) {
                    // Floor display
                    VStack(spacing: 10) {
                        Text("Current Floor")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(currentFloor)")
                            .font(.system(size: 120, weight: .bold))
                            .foregroundColor(.white)

                        Text(elevatorStateText)
                            .font(.title3)
                            .foregroundColor(.yellow)
                            .padding(.top, 10)
                    }
                    .frame(height: geometry.size.height * 0.3)
                    .frame(maxWidth: .infinity)

                    Spacer()

                    // Elevator doors
                    ElevatorDoorsView(doorOffset: doorOffset)
                        .frame(height: geometry.size.height * 0.5)
                        .padding(.horizontal, 40)

                    Spacer()

                    // Customer Support Button
                    Button(action: {
                        showCustomerSupport = true
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
                    .padding(.bottom, 50)
                }
                .frame(width: geometry.size.width / 2)
                .background(Color.black)

                // Right half - Floor selector
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
                                ForEach((1...totalFloors).reversed(), id: \.self) { floor in
                                    FloorButton(
                                        floor: floor,
                                        isSelected: selectedFloor == floor,
                                        isCurrent: currentFloor == floor
                                    ) {
                                        selectFloor(floor)
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
                    }
                }
                .frame(width: geometry.size.width / 2)
                .background(Color(white: 0.15))
            }
        }
        .ignoresSafeArea()
        .alert("Customer Support", isPresented: $showCustomerSupport) {
            Button("Close", role: .cancel) { }
        } message: {
            Text("Emergency support is available 24/7.\nCall: 1-800-ELEVATOR")
        }
    }

    var elevatorStateText: String {
        switch elevatorState {
        case .idle:
            return "Ready"
        case .moving:
            return selectedFloor > currentFloor ? "Going Up ↑" : "Going Down ↓"
        case .arrived:
            return "Arrived"
        case .doorsOpening, .doorsOpen:
            return "Doors Opening"
        case .doorsClosing:
            return "Doors Closing"
        }
    }

    func selectFloor(_ floor: Int) {
        guard elevatorState == .idle && floor != currentFloor else { return }

        selectedFloor = floor
        elevatorState = .moving

        // Simulate elevator movement
        let travelTime = abs(floor - currentFloor) * 0.5

        DispatchQueue.main.asyncAfter(deadline: .now() + travelTime) {
            currentFloor = floor
            elevatorState = .arrived

            // Open doors
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                openDoors()
            }
        }
    }

    func openDoors() {
        elevatorState = .doorsOpening
        withAnimation(.easeInOut(duration: 2.0)) {
            doorOffset = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            elevatorState = .doorsOpen

            // Close doors after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                closeDoors()
            }
        }
    }

    func closeDoors() {
        elevatorState = .doorsClosing
        withAnimation(.easeInOut(duration: 2.0)) {
            doorOffset = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            elevatorState = .idle
        }
    }
}

struct FloorButton: View {
    let floor: Int
    let isSelected: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()

                VStack(spacing: 5) {
                    Text("Floor \(floor)")
                        .font(.system(size: 36, weight: .semibold))

                    if isCurrent {
                        Text("● Current")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .foregroundColor(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(isCurrent ? Color.green.opacity(0.3) :
                              isSelected ? Color.yellow : Color.gray.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(isCurrent ? Color.green : Color.white.opacity(0.2), lineWidth: 2)
                )

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct ElevatorDoorsView: View {
    let doorOffset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Elevator shaft
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    )

                // Inside elevator (visible when doors open)
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(white: 0.4), Color(white: 0.3)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(20)

                // Left door
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(white: 0.6), Color(white: 0.5)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .frame(width: geometry.size.width / 2)
                    .offset(x: -geometry.size.width / 4 * doorOffset)

                // Right door
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color(white: 0.5), Color(white: 0.6)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .frame(width: geometry.size.width / 2)
                    .offset(x: geometry.size.width / 4 * doorOffset)

                // Door handles
                if doorOffset < 0.5 {
                    HStack(spacing: 40) {
                        // Left handle
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 8, height: 80)
                            .offset(x: -geometry.size.width / 4 * doorOffset)

                        // Right handle
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 8, height: 80)
                            .offset(x: geometry.size.width / 4 * doorOffset)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
