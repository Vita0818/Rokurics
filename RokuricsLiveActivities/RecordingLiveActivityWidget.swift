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
    init() {
        JetBrainsMonoFont.ensureAvailable()
    }

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
                        .font(JetBrainsMonoFont.font(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    Text(context.state.elapsedMinuteText)
                        .font(JetBrainsMonoFont.font(size: 24, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Text(displayTitle(context))
                    .font(JetBrainsMonoFont.font(size: 13, weight: .medium))
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
                        .font(JetBrainsMonoFont.font(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.elapsedMinuteText)
                        .font(JetBrainsMonoFont.font(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(displayTitle(context))
                        .font(JetBrainsMonoFont.font(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                Text(context.state.elapsedMinuteText)
                    .font(JetBrainsMonoFont.font(size: 11, weight: .semibold).monospacedDigit())
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
