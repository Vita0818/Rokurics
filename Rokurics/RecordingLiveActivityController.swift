//
//  RecordingLiveActivityController.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import ActivityKit
import Foundation

@MainActor
final class RecordingLiveActivityController {
    private var activity: Activity<RecordingLiveActivityAttributes>?
    private var latestElapsedMinute: Int?
    private var latestIsPaused = false
    private var latestIsSavingLocally = false

    func start(title: String, elapsedSeconds: TimeInterval) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        if activity != nil {
            update(title: title, elapsedSeconds: elapsedSeconds, isPaused: false, isSavingLocally: false, force: true)
            return
        }

        let elapsedMinute = Self.elapsedMinute(for: elapsedSeconds)
        let attributes = RecordingLiveActivityAttributes(recordingName: title)
        let contentState = RecordingLiveActivityAttributes.ContentState(
            title: title,
            elapsedMinutes: elapsedMinute,
            isPaused: false,
            isSavingLocally: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: contentState, staleDate: nil),
                pushType: nil
            )
            latestElapsedMinute = elapsedMinute
            latestIsPaused = false
            latestIsSavingLocally = false
        } catch {
            print("[RokuricsLiveActivity][ERROR] request failed: \(error.localizedDescription)")
        }
    }

    func update(
        title: String,
        elapsedSeconds: TimeInterval,
        isPaused: Bool,
        isSavingLocally: Bool,
        force: Bool = false
    ) {
        guard let activity else {
            return
        }

        let elapsedMinute = Self.elapsedMinute(for: elapsedSeconds)
        guard force
            || latestElapsedMinute != elapsedMinute
            || latestIsPaused != isPaused
            || latestIsSavingLocally != isSavingLocally
        else {
            return
        }

        latestElapsedMinute = elapsedMinute
        latestIsPaused = isPaused
        latestIsSavingLocally = isSavingLocally

        let contentState = RecordingLiveActivityAttributes.ContentState(
            title: title,
            elapsedMinutes: elapsedMinute,
            isPaused: isPaused,
            isSavingLocally: isSavingLocally
        )

        Task {
            await activity.update(ActivityContent(state: contentState, staleDate: nil))
        }
    }

    func end(title: String, elapsedSeconds: TimeInterval, isSavingLocally: Bool = false) {
        guard let activity else {
            return
        }

        self.activity = nil
        latestElapsedMinute = nil
        latestIsPaused = false
        latestIsSavingLocally = false

        let contentState = RecordingLiveActivityAttributes.ContentState(
            title: title,
            elapsedMinutes: Self.elapsedMinute(for: elapsedSeconds),
            isPaused: false,
            isSavingLocally: isSavingLocally
        )

        Task {
            await activity.end(
                ActivityContent(state: contentState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private static func elapsedMinute(for seconds: TimeInterval) -> Int {
        max(0, Int(seconds.rounded(.down))) / 60
    }
}
