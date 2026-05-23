//
//  RecordingLiveActivityWidget.swift
//  RokuricsLiveActivities
//
//  Created by Codex on 2026/5/21.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RokuricsLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
    }
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(context.state.statusText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    Text(context.state.elapsedMinuteText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Text(displayTitle(context))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .activityBackgroundTint(.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.elapsedMinuteText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(displayTitle(context))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(context.state.elapsedMinuteText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }

    private func displayTitle(_ context: ActivityViewContext<RecordingLiveActivityAttributes>) -> String {
        let recordingName = context.attributes.recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recordingName.isEmpty {
            return recordingName
        }

        let title = context.state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "课堂录音" : title
    }
}
