//
//  CenterOpeningDoorsView.swift
//  SYDE600-Elevator-Prot-4
//
//  Simple two-rectangle elevator doors that open from center
//

import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
#endif

struct AnimatedElevatorDoorsView: View {
    @State private var doorOffset: CGFloat = 0.0
    @State private var isOpen = false
    @State private var currentFloor: Int = 1
    
    #if os(iOS)
    @State private var arrivalPlayer: AVAudioPlayer?
    #endif
    
    private func playArrivalChime() {
        #if os(iOS)
        // Configure audio session to ensure playback even in silent mode.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Continue even if session setup fails
        }

        // Load and play ding.mp3 from the main bundle.
        if let url = Bundle.main.url(forResource: "ding", withExtension: "mp3") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                arrivalPlayer = player
                arrivalPlayer?.prepareToPlay()
                arrivalPlayer?.play()
            } catch {
                // Failed to create player; optionally fallback to system sound
            }
        }
        #endif
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Floor Display
            VStack(spacing: 10) {
                Text("Current Floor")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(currentFloor)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(width: 80, height: 80)
                    .background(Color.black)
                    .foregroundColor(.green)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: 2)
                    )
            }
            
            // Elevator Doors
            CenterOpeningDoorsView(doorOffset: doorOffset)
            
            // Floor Selection
            VStack(spacing: 15) {
                Text("Select Floor")
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(1...12, id: \.self) { floor in
                        Button("\(floor)") {
                            if currentFloor != floor {
                                // Close doors first if open
                                if isOpen {
                                    withAnimation(.easeInOut(duration: 1.0)) {
                                        doorOffset = 0.0
                                        isOpen = false
                                    }
                                }
                                
                                // Change floor after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + (isOpen ? 1.2 : 0.0)) {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        currentFloor = floor
                                    }

                                    // Play arrival chime
                                    playArrivalChime()
                                    
                                    // Auto-open doors after arriving
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        withAnimation(.easeInOut(duration: 1.5)) {
                                            doorOffset = 1.0
                                            isOpen = true
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 50, height: 40)
                        .background(currentFloor == floor ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .disabled(currentFloor == floor)
                    }
                }
            }
            
            // Manual Door Controls
            HStack(spacing: 20) {
                Button("Open Doors") {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        doorOffset = 1.0
                        isOpen = true
                    }
                }
                .disabled(isOpen)
                
                Button("Close Doors") {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        doorOffset = 0.0
                        isOpen = false
                    }
                }
                .disabled(!isOpen)
                
                Button("Toggle") {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        doorOffset = isOpen ? 0.0 : 1.0
                        isOpen.toggle()
                    }
                }
            }
        }
        .padding()
    }
}

struct CenterOpeningDoorsView: View {
    let doorOffset: CGFloat // 0.0 = closed (together), 1.0 = fully open (apart)

    var body: some View {
        GeometryReader { geometry in
            let doorWidth = geometry.size.width / 2
            let maxMovement = (geometry.size.width / 4) * 0.8 // Don't move doors completely off screen
            let doorMovement = doorOffset * maxMovement
            
            ZStack {
                // Background/elevator interior (visible when doors open)
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                // Left door - slides to the left but stays visible
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.gray, Color.gray.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: doorWidth, height: geometry.size.height)
                    .position(
                        x: (geometry.size.width / 4) - doorMovement,
                        y: geometry.size.height / 2
                    )
                    .overlay(
                        // Door panel details
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                            .frame(width: doorWidth - 20, height: geometry.size.height - 40)
                            .position(
                                x: (geometry.size.width / 4) - doorMovement,
                                y: geometry.size.height / 2
                            )
                    )
                    .overlay(
                        // Door handle
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                            .frame(width: 8, height: 60)
                            .position(
                                x: (geometry.size.width / 4) - doorMovement + doorWidth/3,
                                y: geometry.size.height / 2
                            )
                    )
                
                // Right door - slides to the right but stays visible
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.gray.opacity(0.8), Color.gray],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: doorWidth, height: geometry.size.height)
                    .position(
                        x: (3 * geometry.size.width / 4) + doorMovement,
                        y: geometry.size.height / 2
                    )
                    .overlay(
                        // Door panel details
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                            .frame(width: doorWidth - 20, height: geometry.size.height - 40)
                            .position(
                                x: (3 * geometry.size.width / 4) + doorMovement,
                                y: geometry.size.height / 2
                            )
                    )
                    .overlay(
                        // Door handle
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                            .frame(width: 8, height: 60)
                            .position(
                                x: (3 * geometry.size.width / 4) + doorMovement - doorWidth/3,
                                y: geometry.size.height / 2
                            )
                    )
                
                // Center seam line (visible when doors are closed or nearly closed)
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 2, height: geometry.size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .opacity(doorOffset < 0.1 ? 1 : 0)
            }
        }
        // Ensure any change to doorOffset animates smoothly across all parts
        .animation(.easeInOut(duration: 1.5), value: doorOffset)
    }
}

#Preview {
    TabView {
        // Animated version
        AnimatedElevatorDoorsView()
            .frame(height: 400)
            .padding()
            .tabItem {
                Label("Animated", systemImage: "play.fill")
            }
        
        // Static examples
        VStack(spacing: 30) {
            Text("Closed (Together)")
                .font(.title)
            CenterOpeningDoorsView(doorOffset: 0.0)
                .frame(height: 200)
                .padding()

            Text("Half Open")
                .font(.title)
            CenterOpeningDoorsView(doorOffset: 0.5)
                .frame(height: 200)
                .padding()

            Text("Fully Open (Apart)")
                .font(.title)
            CenterOpeningDoorsView(doorOffset: 1.0)
                .frame(height: 200)
                .padding()
        }
        .background(Color.black)
        .tabItem {
            Label("Static", systemImage: "rectangle.grid.2x2")
        }
    }
}
