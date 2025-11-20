# SYDE600 Elevator Simulator

A SwiftUI-based elevator simulator application that demonstrates realistic elevator behavior including floor selection, movement, door animations, and auto-scrolling floor display.

## Features

- **Interactive Floor Selection**: Tap floor buttons to queue destinations
- **Realistic Elevator Movement**: Smooth floor transitions with directional logic
- **Door Animations**: Animated door opening and closing with proper state management
- **Auto-Scroll**: Automatic scrolling to current floor with manual override
- **Visual Feedback**: Color-coded floor states (current, queued, selected)
- **Customer Support**: Emergency support button integration

## Architecture

### View-Model Separation

The application follows a clean architecture pattern where the **View** and **Model** interact **ONLY** through specific public interface functions:

#### Public Interface Functions

1. **`enqueue(_ floor: Int)`**
   - Called when user presses a floor button
   - Adds or removes floor from the queue
   - Automatically starts elevator journey if idle

2. **`displayFloor(_ floor: Int) async`**
   - Called when elevator arrives at a floor
   - Handles complete door cycle:
     - Door opening animation
     - Door opened state (3 seconds with countdown)
     - Door closing animation
   - Called internally when elevator stops at a queued floor

3. **`doorOpen()`**
   - Plays door opening animation
   - **Sets door state to `.opening` BEFORE animation plays**
   - Sets `doorOffset = 1.0` to trigger view animation
   - Plays arrival chime
   - Transitions to `.open` state after animation

4. **`doorClose()`**
   - Plays door closing animation
   - **Sets door state to `.closing` BEFORE animation plays**
   - Sets `doorOffset = 0.0` to trigger view animation
   - Transitions to `.closed` state after animation

### Key Design Principles

- **Model (ElevatorModel)**: Contains all elevator business logic
  - Manages elevator state (idle, moving, stopped)
  - Handles floor queuing and movement logic
  - Controls door states and animations
  - Does NOT know about UI scrolling

- **View Controller (FloorSelectorViewController)**: Manages UI state
  - Handles scrolling state and auto-scroll behavior
  - Does NOT affect elevator model
  - Only calls `model.enqueue()` when buttons are pressed

- **View**: Observes model state and displays UI
  - Reacts to `@Published` properties
  - Calls public interface functions for user actions
  - Handles scrolling independently of model

## Project Structure

```
SYDE600-Elevator-Prot-4/
├── ElevatorModel.swift          # Core elevator logic and state
├── ContentView.swift            # Main UI views and view controllers
├── CenterOpeningDoorsView.swift # Door animation component
└── sounds/
    └── ding.mp3                  # Arrival chime sound
```

## Components

### ElevatorModel

The core model that manages elevator state:

- **State Properties**:
  - `currentFloor`: Current floor number (1-20)
  - `elevatorState`: `.idle`, `.moving`, or `.stopped`
  - `doorState`: `.closed`, `.opening`, `.open`, or `.closing`
  - `queuedFloors`: Set of floors in the queue
  - `currentDirection`: -1 (down), 0 (idle), or 1 (up)

- **Key Methods**:
  - `enqueue(_:)`: Add/remove floor from queue
  - `displayFloor(_:)`: Complete door cycle at a floor
  - `doorOpen()`: Open doors with animation
  - `doorClose()`: Close doors with animation

### ContentView

Main view structure:

- **ElevatorDisplayView**: Left side
  - Current floor display
  - Door animation
  - Customer Support button
  - Auto Scroll button

- **FloorSelectorView**: Right side
  - Scrollable floor list
  - Floor buttons with state indicators
  - Auto-scroll functionality

### FloorSelectorViewController

Manages scrolling UI state:

- `shouldAllowAutoScroll`: Controls whether view auto-scrolls
- `performAutoScroll()`: Centralized function for scrolling
- `handleUserScrolling()`: Disables auto-scroll when user scrolls
- `handleUserScrollRelease()`: Tracks scroll release

## Usage

### Building and Running

1. Open `SYDE600-Elevator-Prot-4.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (⌘R)

### Interacting with the Elevator

1. **Select a Floor**: Tap any floor button to add it to the queue
2. **Remove from Queue**: Tap a queued floor again to remove it
3. **Auto Scroll**: Press "Auto Scroll" button to scroll to current floor
4. **Manual Scroll**: Scroll the floor list manually (disables auto-scroll temporarily)

### Elevator Behavior

- **Direction Logic**: Elevator moves in one direction until no more floors in that direction, then reverses
- **Door Timing**: Doors open for 3 seconds when elevator arrives at a queued floor
- **Auto-Scroll**: Automatically scrolls to current floor during movement (if not manually disabled)

## State Management

### Elevator States

- **`.idle`**: Elevator is not in use, no floors queued
- **`.moving`**: Elevator is moving between floors
- **`.stopped`**: Elevator is stopped at a floor

### Door States

- **`.closed`**: Doors are closed, elevator can move
- **`.opening`**: Doors are opening (animation playing)
- **`.open`**: Doors are open, passengers can enter/exit
- **`.closing`**: Doors are closing (animation playing)

### Floor Button States

- **Current**: Green highlight - elevator is at this floor
- **Queued**: Orange highlight - floor is in the queue
- **Selected**: Yellow highlight - button was just pressed (temporary)

## Technical Details

### Door Animation Timing

- Door states are set **BEFORE** animations play
- Opening animation: 0.1 seconds
- Open state duration: 3 seconds (with countdown)
- Closing animation: 0.1 seconds

### Auto-Scroll Behavior

- Auto-scroll is enabled by default
- Disabled when user manually scrolls
- Re-enabled after 5 seconds of no scrolling (configurable)
- Can be manually enabled via "Auto Scroll" button

### Floor Movement

- Movement speed: 0.8 seconds per floor
- Smooth animations with `easeInOut` timing
- Automatic direction calculation based on queued floors

## Requirements

- iOS 15.0+ / macOS 12.0+
- Xcode 14.0+
- Swift 5.7+

## License

This project is part of SYDE600 coursework.

## Author

Created by Darcy Liu

