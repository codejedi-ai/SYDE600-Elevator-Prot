//
//  ElevatorModel.swift
//  SYDE600-Elevator-Prot-4
//
//  Created by Darcy Liu on 2025-11-19.
//

import SwiftUI
internal import Combine
#if os(iOS)
import AVFoundation
#endif

// MARK: - Model Enums
enum ElevatorState {
    case idle
    case stopped      // At a floor but not moving
    case doorsOpening
    case doorsOpen
    case doorsClosing
    case moving       // Actually moving between floors
}

enum ScrollPanelState {
    case idle         // No touch events for 5+ seconds
    case selection    // User is touching/interacting
}

// MARK: - Elevator Model
@MainActor
class ElevatorModel: ObservableObject {
    @Published var currentFloor: Int = 1
    @Published var elevatorState: ElevatorState = .idle
    @Published var doorOffset: CGFloat = 0
    @Published var queuedFloors: Set<Int> = []
    @Published var currentDirection: Int = 0 // -1 for down, 1 for up, 0 for idle
    @Published var upReverseFloor: Int = 0
    @Published var downReverseFloor: Int = 0
    @Published var scrollPanelState: ScrollPanelState = .idle
    
    private var floorChangeTimer: Timer?
    private var lastUserReleaseTime: Date = Date()
    
    #if os(iOS)
    private var arrivalPlayer: AVAudioPlayer?
    #endif
    
    let totalFloors = 20
    
    init() {
        // Initialize any required setup here
    }
    
    deinit {
        // Clean up timer synchronously in deinit
        floorChangeTimer?.invalidate()
        floorChangeTimer = nil
    }
    
    var elevatorStateText: String {
        switch elevatorState {
        case .idle:
            return "Idle"
        case .stopped:
            return "Stopped"
        case .moving:
            return currentDirection > 0 ? "Going Up ↑" : "Going Down ↓"
        case .doorsOpening:
            return "Doors Opening"
        case .doorsOpen:
            return "Doors Open"
        case .doorsClosing:
            return "Doors Closing"
        }
    }
    
    func cleanupTimers() async {
        floorChangeTimer?.invalidate()
        floorChangeTimer = nil
    }
    
    private func playArrivalChime() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Continue even if session setup fails
        }

        if let url = Bundle.main.url(forResource: "ding", withExtension: "mp3") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                arrivalPlayer = player
                arrivalPlayer?.prepareToPlay()
                arrivalPlayer?.play()
            } catch {
                print("Could not play arrival chime: \(error)")
            }
        } else {
            print("Could not find ding.mp3 file in bundle")
        }
        #endif
    }
    
    func handleUserInteraction() {
        scrollPanelState = .selection
    }
    
    func handleUserRelease() {
        lastUserReleaseTime = Date()
        scrollPanelState = .selection
    }
    
    var shouldAllowAutoScroll: Bool {
        Date().timeIntervalSince(lastUserReleaseTime) >= 5.0
    }
    
    func calculateReverseFloors() {
        guard !queuedFloors.isEmpty else {
            upReverseFloor = 0
            downReverseFloor = 0
            return
        }
        
        let sortedFloors = queuedFloors.sorted()
        upReverseFloor = sortedFloors.max() ?? 0
        downReverseFloor = sortedFloors.min() ?? 0
    }

    func startElevatorJourney() {
        guard !queuedFloors.isEmpty && elevatorState == .idle else { return }

        let sortedFloors = queuedFloors.sorted()
        if let closestFloor = sortedFloors.min(by: { abs($0 - currentFloor) < abs($1 - currentFloor) }) {
            currentDirection = closestFloor > currentFloor ? 1 : -1
        }
        
        calculateReverseFloors()
        
        if queuedFloors.contains(currentFloor) {
            elevatorState = .stopped
            handleStoppedState()
        } else {
            elevatorState = .moving
            moveToNextFloor()
        }
    }

    private func handleStoppedState() {
        if queuedFloors.contains(currentFloor) {
            queuedFloors.remove(currentFloor)
            calculateReverseFloors()
            
            playArrivalChime()
            
            Task {
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                openDoors()
            }
        } else {
            checkNextMove()
        }
    }
    
    private func checkNextMove() {
        guard !queuedFloors.isEmpty else {
            elevatorState = .idle
            currentDirection = 0
            upReverseFloor = 0
            downReverseFloor = 0
            return
        }
        
        elevatorState = .moving
        moveToNextFloor()
    }
    
    private func moveToNextFloor() {
        guard elevatorState == .moving else { return }
        
        let nextFloor = getNextFloorInDirection()
        
        guard let targetFloor = nextFloor else {
            elevatorState = .idle
            currentDirection = 0
            return
        }

        animateFloorProgression(from: currentFloor, to: targetFloor)
    }
    
    private func getNextFloorInDirection() -> Int? {
        let sortedFloors = queuedFloors.sorted()
        
        if currentDirection == 1 {
            let floorsAbove = sortedFloors.filter { $0 > currentFloor }
            if let nextFloor = floorsAbove.min() {
                return nextFloor
            } else if currentFloor < upReverseFloor {
                return upReverseFloor
            } else {
                currentDirection = -1
                let floorsBelow = sortedFloors.filter { $0 < currentFloor }
                return floorsBelow.max()
            }
        } else {
            let floorsBelow = sortedFloors.filter { $0 < currentFloor }
            if let nextFloor = floorsBelow.max() {
                return nextFloor
            } else if currentFloor > downReverseFloor {
                return downReverseFloor
            } else {
                currentDirection = 1
                let floorsAbove = sortedFloors.filter { $0 > currentFloor }
                return floorsAbove.min()
            }
        }
    }
    
    private func animateFloorProgression(from startFloor: Int, to endFloor: Int) {
        floorChangeTimer?.invalidate()
        
        let timePerFloor: Double = 0.8
        let direction = endFloor > startFloor ? 1 : -1
        
        var currentAnimatedFloor = startFloor
        
        floorChangeTimer = Timer.scheduledTimer(withTimeInterval: timePerFloor, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                currentAnimatedFloor += direction
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.currentFloor = currentAnimatedFloor
                }
                
                if self.queuedFloors.contains(currentAnimatedFloor) {
                    self.floorChangeTimer?.invalidate()
                    self.floorChangeTimer = nil
                    
                    self.elevatorState = .stopped
                    self.handleStoppedState()
                    return
                }
                
                if currentAnimatedFloor == endFloor {
                    self.floorChangeTimer?.invalidate()
                    self.floorChangeTimer = nil

                    self.elevatorState = .stopped
                    self.handleStoppedState()
                }
            }
        }
    }

    private func openDoors() {
        guard elevatorState == .stopped else { return }
        
        elevatorState = .doorsOpening
        doorOffset = 1.0

        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            elevatorState = .doorsOpen

            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            closeDoors()
        }
    }

    private func closeDoors() {
        guard elevatorState == .doorsOpen else { return }
        
        elevatorState = .doorsClosing
        doorOffset = 0.0

        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            checkNextMove()
        }
    }
}
