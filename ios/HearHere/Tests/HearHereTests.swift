import Testing
@testable import HearHere

@Test func moderationStatusDisplayName() {
    #expect(ModerationStatus.approved.displayName == "Published")
    #expect(ModerationStatus.rejected.displayName == "Not Published")
    #expect(ModerationStatus.pendingModeration.displayName == "Under Review")
    #expect(ModerationStatus.pendingReview.displayName == "Under Review")
    #expect(ModerationStatus.pendingUpload.displayName == "Uploading")
}

@Test func moderationStatusVisibility() {
    #expect(ModerationStatus.approved.isPubliclyVisible == true)
    #expect(ModerationStatus.rejected.isPubliclyVisible == false)
    #expect(ModerationStatus.pendingModeration.isPubliclyVisible == false)
}

@Test func moderationStatusPending() {
    #expect(ModerationStatus.pendingUpload.isPending == true)
    #expect(ModerationStatus.pendingModeration.isPending == true)
    #expect(ModerationStatus.pendingReview.isPending == true)
    #expect(ModerationStatus.approved.isPending == false)
    #expect(ModerationStatus.rejected.isPending == false)
}
