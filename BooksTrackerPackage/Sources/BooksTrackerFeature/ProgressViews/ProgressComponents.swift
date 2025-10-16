//
//  ProgressComponents.swift
//  BooksTracker
//
//  Created by Jules on 10/16/25.
//

import SwiftUI

public struct ProgressBanner: View {
    @Binding var isShowing: Bool
    let title: String
    let message: String

    public var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                }
                Spacer()
                Button(action: {
                    withAnimation {
                        isShowing = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .glassEffect()
        }
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
public struct StagedProgressView: View {
    let stages: [String]
    @Binding var currentStageIndex: Int
    @Binding var progress: Double

    public var body: some View {
        VStack {
            HStack {
                ForEach(0..<stages.count, id: \.self) { index in
                    VStack {
                        Text(stages[index])
                            .font(.caption)
                            .foregroundColor(index == currentStageIndex ? .accentColor : .gray)
                        Rectangle()
                            .frame(height: 4)
                            .foregroundColor(index < currentStageIndex ? .accentColor : (index == currentStageIndex ? .accentColor : .gray.opacity(0.3)))
                            .overlay(
                                GeometryReader { geo in
                                    Rectangle()
                                        .frame(width: index == currentStageIndex ? geo.size.width * CGFloat(progress) : 0)
                                        .foregroundColor(.accentColor)
                                }
                            )
                    }
                }
            }
            .padding()
            .glassEffect()
        }
        .padding()
    }
}
public struct PollingIndicator: View {
    let stageName: String
    @State private var isAnimating = false

    public var body: some View {
        HStack {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 20, height: 20)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                .onAppear {
                    isAnimating = true
                }
            Text(stageName)
                .font(.body)
        }
        .padding()
        .glassEffect()
    }
}
public struct EstimatedTimeRemaining: View {
    let completionDate: Date
    @State private var timeRemaining: String = ""

    public var body: some View {
        Text(timeRemaining)
            .font(.caption)
            .onAppear(perform: setupTimer)
    }

    private func setupTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let remaining = completionDate.timeIntervalSince(Date())
            if remaining > 0 {
                timeRemaining = format(timeInterval: remaining)
            } else {
                timeRemaining = "Done"
                timer.invalidate()
            }
        }
    }

    private func format(timeInterval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: timeInterval) ?? ""
    }
}

#if DEBUG
struct ProgressComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ProgressBanner(isShowing: .constant(true), title: "Scanning Books", message: "12 of 24 scanned...")
            StagedProgressView(stages: ["Scanning", "Enriching", "Uploading"], currentStageIndex: .constant(1), progress: .constant(0.5))
            PollingIndicator(stageName: "Waiting for server...")
            EstimatedTimeRemaining(completionDate: Date().addingTimeInterval(120))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif