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
    case idle         // Not in use
    case moving       // Moving between floors
    case stopped      // Stopped at a floor (people can enter/exit)
}

enum DoorState {
    case closed       // Doors are closed
    case opening      // Doors are opening
    case open         // Doors are open (people can enter/exit)
    case closing      // Doors are closing
}

// MARK: - Elevator Model
@MainActor
class ElevatorModel: ObservableObject {
    @Published var currentFloor: Int = 1
    @Published var selectedFloor: Int = 0
    @Published var elevatorState: ElevatorState = .idle
    @Published var doorState: DoorState = .closed
    @Published var doorOffset: CGFloat = 0
    @Published var doorOpenCountdown: Int = 0  // Countdown timer for door open state
    @Published var queuedFloors: Set<Int> = []
    @Published var currentDirection: Int = 0 // -1 for down, 1 for up, 0 for idle
    @Published var upReverseFloor: Int = 0
    @Published var downReverseFloor: Int = 0
    
    private var floorChangeTimer: Timer?
    
    #if os(iOS)
    private var arrivalPlayer: AVAudioPlayer?
    #endif
    
    let totalFloors = 20
    
    init() {
        // Initialize any required setup here
    }
    
    deinit {
        // Clean up timers synchronously in deinit
        floorChangeTimer?.invalidate()
        floorChangeTimer = nil
    }
    
    var elevatorStateText: String {
        switch elevatorState {
        case .idle:
            return "Idle"
        case .moving:
            return currentDirection > 0 ? "Going Up ↑" : "Going Down ↓"
        case .stopped:
            switch doorState {
            case .closed:
                return "Stopped - Doors Closed"
            case .opening:
                return "Stopped - Doors Opening"
            case .open:
                return "Stopped - Doors Open"
            case .closing:
                return "Stopped - Doors Closing"
            }
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
    
    /// Helper function to clear selected floor after a delay
    private func clearSelectedFloor(after delay: TimeInterval = 0.5, reason: String = "") {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            selectedFloor = 0
            if !reason.isEmpty {
                print("DEBUG: Cleared selection (\(reason))")
            }
        }
    }
    
    /// Enqueue or dequeue a floor when user presses the button
    func enqueue(_ floor: Int) {
        print("DEBUG: enqueue(\(floor)) called")
        
        // Set selected floor for visual feedback
        selectedFloor = floor
        
        guard floor != currentFloor else {
            // Clear selection after a brief moment if selecting current floor
            clearSelectedFloor(reason: "was current floor")
            return
        }
        
        // Toggle floor in queue
        if queuedFloors.contains(floor) {
            queuedFloors.remove(floor)
            calculateReverseFloors()
            print("DEBUG: Removed floor \(floor) from queue")
        } else {
            queuedFloors.insert(floor)
            calculateReverseFloors()
            print("DEBUG: Added floor \(floor) to queue")
            
            // Start elevator journey if idle
            if elevatorState == .idle {
                startElevatorJourney()
            }
        }
        
        // Clear selection after a brief moment
        clearSelectedFloor(reason: "after delay")
    }

    func startElevatorJourney() {
        print("DEBUG: startElevatorJourney() called, state: \(elevatorState), door state: \(doorState), queued floors: \(queuedFloors)")
        guard !queuedFloors.isEmpty else { 
            print("DEBUG: startElevatorJourney() - no queued floors")
            return 
        }
        
        // Can only start journey if idle, or if stopped with doors closed
        guard elevatorState == .idle || (elevatorState == .stopped && doorState == .closed) else {
            print("DEBUG: startElevatorJourney() - cannot start, elevator state: \(elevatorState), door state: \(doorState)")
            return
        }

        let sortedFloors = queuedFloors.sorted()
        if let closestFloor = sortedFloors.min(by: { abs($0 - currentFloor) < abs($1 - currentFloor) }) {
            currentDirection = closestFloor > currentFloor ? 1 : -1
        }
        
        calculateReverseFloors()
        
        if queuedFloors.contains(currentFloor) {
            print("DEBUG: Current floor \(currentFloor) is queued, stopping here")
            stopElevator()
        } else {
            print("DEBUG: Current floor not queued, starting movement to next destination")
            elevatorState = .moving
            startMovementToNextFloor()
        }
    }

    // MARK: - Public Methods
    
    /// Public method to stop the elevator (e.g., for emergency stop)
    func forceStopElevator() {
        print("DEBUG: forceStopElevator() called - current state: \(elevatorState)")
        
        // Cancel any ongoing floor progression
        floorChangeTimer?.invalidate()
        floorChangeTimer = nil
        
        // Stop immediately regardless of current state
        elevatorState = .stopped
        currentDirection = 0
        
        print("DEBUG: Emergency stop executed at floor \(currentFloor)")
        
        // Check if there are still queued floors and handle accordingly
        if !queuedFloors.isEmpty {
            print("DEBUG: Emergency stop - \(queuedFloors.count) floors still queued")
            // Remove current floor from queue if it's there
            if queuedFloors.contains(currentFloor) {
                queuedFloors.remove(currentFloor)
                calculateReverseFloors()
                
                // Open doors since we stopped at a queued floor
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                    await self.handleDoorCycle()
                }
            } else {
                // Just stopped, don't open doors but allow continuing later
                checkForNextMovement()
            }
        } else {
            // No queued floors, go idle
            elevatorState = .idle
            print("DEBUG: Emergency stop - no queued floors, going idle")
        }
    }
    
    /// Completely halt all elevator operations (for app backgrounding, etc.)
    func haltAllOperations() {
        print("DEBUG: haltAllOperations() called")
        
        // Cancel all timers and tasks
        floorChangeTimer?.invalidate()
        floorChangeTimer = nil
        
        // Set to idle state with doors closed
        elevatorState = .idle
        doorState = .closed
        currentDirection = 0
        doorOffset = 0.0
        doorOpenCountdown = 0
        
        print("DEBUG: All elevator operations halted")
    }
    
    // MARK: - Public Interface: View-Model Interaction
    // The View and Model interact ONLY through these functions:
    // 1. enqueue(floor) - when user presses a floor button
    // 2. displayFloor(floor) - when elevator arrives at a floor (includes complete door cycle)
    // 3. doorOpen() - play door opening animation (state set BEFORE animation)
    // 4. doorClose() - play door closing animation (state set BEFORE animation)
    
    /// Called when elevator arrives at a floor - displays floor and handles complete door cycle
    /// This includes: door opening animation, door opened state (3 seconds), and door closing animation
    /// The view can call this, or it's called internally when the elevator stops at a queued floor
    func displayFloor(_ floor: Int) async {
        print("DEBUG: displayFloor(\(floor)) called")
        
        // Ensure elevator is stopped at the correct floor
        guard elevatorState == .stopped && currentFloor == floor else {
            print("DEBUG: Cannot display floor - elevator state: \(elevatorState), current floor: \(currentFloor), target: \(floor)")
            return
        }
        
        // Ensure doors are closed before starting
        guard doorState == .closed else {
            print("DEBUG: Cannot display floor - doors are not closed (state: \(doorState))")
            return
        }
        
        // Start door cycle: open → wait → close
        await handleDoorCycle()
    }
    
    /// Play door opening animation
    /// Sets door state to .opening BEFORE the animation plays
    func doorOpen() {
        guard elevatorState == .stopped && doorState == .closed else {
            print("DEBUG: Cannot open doors - elevator state: \(elevatorState), door state: \(doorState)")
            return
        }
        
        print("DEBUG: doorOpen() - Setting state to opening BEFORE animation at floor \(currentFloor)")
        
        // SET STATE BEFORE ANIMATION
        doorState = .opening
        doorOffset = 1.0
        
        // Play arrival chime
        playArrivalChime()
        
        // Animation plays (view observes doorOffset change)
        // After animation completes, transition to open state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.doorState = .open
            print("DEBUG: doorOpen() - Animation complete, doors are now OPEN")
            
            assert(self.elevatorState == .stopped, "Elevator should be stopped after door opening")
            assert(self.doorState == .open, "Doors should be open after opening animation")
        }
    }
    
    /// Play door closing animation
    /// Sets door state to .closing BEFORE the animation plays
    func doorClose() {
        guard elevatorState == .stopped && doorState == .open else {
            print("DEBUG: Cannot close doors - elevator state: \(elevatorState), door state: \(doorState)")
            return
        }
        
        print("DEBUG: doorClose() - Setting state to closing BEFORE animation at floor \(currentFloor)")
        
        // SET STATE BEFORE ANIMATION
        doorState = .closing
        doorOffset = 0.0
        
        // Animation plays (view observes doorOffset change)
        // After animation completes, transition to closed state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.doorState = .closed
            print("DEBUG: doorClose() - Animation complete, doors are now CLOSED")
            
            assert(self.elevatorState == .stopped, "Elevator should be stopped after door closing")
            assert(self.doorState == .closed, "Doors should be closed after closing animation")
        }
    }
    
    // MARK: - Door State Management (Internal)
    
    /// Internal function to open doors (used by handleDoorCycle)
    private func openDoors() {
        doorOpen()
    }
    
    /// Internal function to close doors (used by handleDoorCycle)
    private func closeDoors() {
        doorClose()
    }
    
    /// Complete door cycle: open → wait 3 seconds → close
    private func handleDoorCycle() async {
        print("DEBUG: Starting door cycle at floor \(currentFloor)")
        
        // Step 1: The elevator is stopped and the door is closed
        print("DEBUG: Step 1 - Elevator stopped, doors closed")
        assert(elevatorState == .stopped, "Elevator must be stopped to start door cycle")
        assert(doorState == .closed, "Doors must be closed to start door cycle")
        
        // Step 2: openDoors() - play the door opening animation (synchronous call)
        openDoors()
        
        // Wait for door opening animation to complete (doors transition from .opening to .open)
        print("DEBUG: Step 2 - Waiting for door opening animation to complete...")
        while doorState == .opening {
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds polling
        }
        
        // Assert that doors are now open after animation
        assert(doorState == .open, "Doors should be open after opening animation completes")
        
        // Step 3: At this point the doors are open with the elevator stopped
        print("DEBUG: Step 3 - Doors open, elevator stopped - waiting 3 seconds for passengers")
        doorOpenCountdown = 3
        
        // Step 4: Await timer for 3 seconds
        for countdown in (1...3).reversed() {
            doorOpenCountdown = countdown
            print("DEBUG: Door countdown: \(countdown) second\(countdown == 1 ? "" : "s") remaining")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        doorOpenCountdown = 0
        print("DEBUG: Step 4 - 3 seconds elapsed")
        
        // Step 5: closeDoors() - play the door closing animation (synchronous call)
        closeDoors()
        
        // Wait for door closing animation to complete (doors transition from .closing to .closed)
        print("DEBUG: Step 5 - Waiting for door closing animation to complete...")
        while doorState == .closing {
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds polling
        }
        
        // Assert that doors are now closed after animation
        assert(doorState == .closed, "Doors should be closed after closing animation completes")
        
        // Step 6: At this point the elevator is stopped and the doors are closed
        print("DEBUG: Step 6 - Door cycle complete: elevator stopped, doors closed")
        assert(elevatorState == .stopped, "Elevator should still be stopped after door cycle")
        assert(doorState == .closed, "Doors should be closed after door cycle")
        
        // Now check for next movement
        checkForNextMovement()
    }
    
    /// Force doors to close immediately (for emergency or testing)
    /// Uses the public doorClose() function
    func forceCloseDoors() {
        guard elevatorState == .stopped && doorState == .open else {
            print("DEBUG: Cannot force close doors - elevator state: \(elevatorState), door state: \(doorState)")
            return
        }
        
        print("DEBUG: FORCE closing doors at floor \(currentFloor)")
        doorOpenCountdown = 0  // Clear countdown immediately
        
        // Use public doorClose() function
        doorClose()
        
        // Wait for door closing animation to complete before checking next movement
        Task {
            // Poll until doors are fully closed
            while await MainActor.run(body: { self.doorState == .closing }) {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds polling
            }
            
            await MainActor.run {
                // Assert that doors are closed after force close
                assert(self.doorState == .closed, "Doors should be closed after force close")
                print("DEBUG: Force close animation complete - checking next movement")
                self.checkForNextMovement()
            }
        }
    }
    
    /// Test door timing by stopping at current floor and displaying it
    /// Uses the public displayFloor() function
    func testDoorTiming() {
        print("DEBUG: Testing door timing at current floor \(currentFloor)")
        elevatorState = .stopped
        doorState = .closed
        Task {
            await displayFloor(currentFloor)
        }
    }
    
    /// Check if elevator should continue to next destination
    private func checkForNextMovement() {
        print("DEBUG: checkForNextMovement() called - state: \(elevatorState), door: \(doorState)")
        
        guard elevatorState == .stopped && doorState == .closed else {
            print("DEBUG: Cannot move - elevator state: \(elevatorState), door state: \(doorState)")
            return
        }
        
        // Assert that we're in the correct state to check for movement
        assert(elevatorState == .stopped, "Elevator must be stopped to check for next movement")
        assert(doorState == .closed, "Doors must be closed to check for next movement")
        
        guard !queuedFloors.isEmpty else {
            print("DEBUG: No more queued floors - going idle")
            elevatorState = .idle
            currentDirection = 0
            upReverseFloor = 0
            downReverseFloor = 0
            
            // Assert transition to idle
            assert(elevatorState == .idle, "Elevator should be idle when no queued floors")
            assert(currentDirection == 0, "Direction should be 0 when idle")
            return
        }
        
        print("DEBUG: \(queuedFloors.count) floors still queued - resuming movement")
        elevatorState = .moving
        
        // Assert transition to moving
        assert(elevatorState == .moving, "Elevator should be moving when resuming to queued floors")
        
        startMovementToNextFloor()
    }
    
    // MARK: - Floor Movement Functions
    
    /// Increment floor by 1 (only if elevator should be moving up)
    private func incrementFloor() -> Bool {
        guard elevatorState == .moving && currentDirection > 0 else {
            print("DEBUG: incrementFloor() blocked - state: \(elevatorState), direction: \(currentDirection)")
            return false
        }
        
        // Assert elevator is in correct state for movement
        assert(elevatorState == .moving, "Elevator must be moving to increment floor")
        assert(currentDirection > 0, "Direction must be up to increment floor")
        
        let newFloor = currentFloor + 1
        guard newFloor <= totalFloors else {
            print("DEBUG: incrementFloor() blocked - would exceed max floor \(totalFloors)")
            return false
        }
        
        print("DEBUG: incrementFloor() - moving from \(currentFloor) to \(newFloor)")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentFloor = newFloor
        }
        
        // Assert floor was incremented correctly
        assert(currentFloor == newFloor, "Floor should be incremented to \(newFloor)")
        return true
    }
    
    /// Decrement floor by 1 (only if elevator should be moving down)  
    private func decrementFloor() -> Bool {
        guard elevatorState == .moving && currentDirection < 0 else {
            print("DEBUG: decrementFloor() blocked - state: \(elevatorState), direction: \(currentDirection)")
            return false
        }
        
        // Assert elevator is in correct state for movement
        assert(elevatorState == .moving, "Elevator must be moving to decrement floor")
        assert(currentDirection < 0, "Direction must be down to decrement floor")
        
        let newFloor = currentFloor - 1
        guard newFloor >= 1 else {
            print("DEBUG: decrementFloor() blocked - would go below floor 1")
            return false
        }
        
        print("DEBUG: decrementFloor() - moving from \(currentFloor) to \(newFloor)")
        withAnimation(.easeInOut(duration: 0.3)) {
            currentFloor = newFloor
        }
        
        // Assert floor was decremented correctly
        assert(currentFloor == newFloor, "Floor should be decremented to \(newFloor)")
        return true
    }
    
    // MARK: - Private Methods
    
    private func stopElevator() {
        print("DEBUG: stopElevator() called at floor \(currentFloor)")
        
        // Transition to stopped state
        elevatorState = .stopped
        doorState = .closed  // Doors start closed when we stop
        
        // Assert that elevator is now stopped with doors closed
        assert(elevatorState == .stopped, "Elevator should be stopped after calling stopElevator")
        assert(doorState == .closed, "Doors should be closed when elevator stops")
        
        // Remove current floor from queue if it's queued
        if queuedFloors.contains(currentFloor) {
            queuedFloors.remove(currentFloor)
            calculateReverseFloors()
            print("DEBUG: Elevator stopped at queued floor \(currentFloor) - will display floor")
            
            // Call displayFloor to handle door cycle
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds brief delay
                await self.displayFloor(self.currentFloor)
            }
        } else {
            print("DEBUG: Elevator stopped at floor \(currentFloor) - checking for next move")
            // Floor not queued, check for next move immediately
            checkForNextMovement()
        }
    }


    
    private func startMovementToNextFloor() {
        print("DEBUG: startMovementToNextFloor() called, current state: \(elevatorState)")
        guard elevatorState == .moving else { 
            print("DEBUG: startMovementToNextFloor() guard failed, state is \(elevatorState), expected .moving")
            return 
        }
        
        let nextFloor = getNextFloorInDirection()
        print("DEBUG: Next floor in direction: \(nextFloor?.description ?? "nil")")
        
        guard let targetFloor = nextFloor else {
            print("DEBUG: No target floor found, going idle")
            elevatorState = .idle
            currentDirection = 0
            return
        }

        print("DEBUG: Starting animation from floor \(currentFloor) to floor \(targetFloor)")
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
        print("DEBUG: animateFloorProgression() from \(startFloor) to \(endFloor)")
        floorChangeTimer?.invalidate()
        
        let timePerFloor: Double = 0.8
        let direction = endFloor > startFloor ? 1 : -1
        
        // Set the direction before starting
        currentDirection = direction
        
        // Run elevator movement in background thread
        Task {
            var targetReached = false
            
            while !targetReached && elevatorState == .moving {
                // Sleep for the time per floor (background thread)
                try? await Task.sleep(nanoseconds: UInt64(timePerFloor * 1_000_000_000))
                
                // Update UI on main thread
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    
                    // Check if we should still be moving
                    guard self.elevatorState == .moving else {
                        print("DEBUG: animateFloorProgression stopped - elevator state changed to \(self.elevatorState)")
                        return
                    }
                    
                    // Move to next floor using our safe functions
                    let moved: Bool
                    if direction > 0 {
                        moved = self.incrementFloor()
                    } else {
                        moved = self.decrementFloor()
                    }
                    
                    // If we couldn't move, stop the animation
                    guard moved else {
                        print("DEBUG: animateFloorProgression stopped - could not move floor")
                        targetReached = true
                        return
                    }
                    
                    // Check if current floor is in queued floors - STOP if it is!
                    if self.queuedFloors.contains(self.currentFloor) {
                        print("DEBUG: animateFloorProgression - reached queued floor \(self.currentFloor)")
                        self.stopElevator()
                        targetReached = true
                        return
                    }
                    
                    // Check if we've reached the destination
                    if self.currentFloor == endFloor {
                        print("DEBUG: animateFloorProgression - reached destination floor \(endFloor)")
                        self.stopElevator()
                        targetReached = true
                    }
                }
            }
            
            await MainActor.run {
                print("DEBUG: animateFloorProgression completed")
            }
        }
    }
}
