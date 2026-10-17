import Foundation

#if !canImport(XCTest) && canImport(Testing)
import Testing

// Swift Testing runs these where XCTest is absent (e.g. a Command Line Tools-only
// macOS). One serialized suite: the stub and the environment are process-wide.
@Suite(.serialized) struct MisarDevTests {
    @Test func testSendsBearerKeyAndSdkHeaders() async throws { try await AuthenticationCases().testSendsBearerKeyAndSdkHeaders() }
    @Test func testRefusesToConstructWithoutAKey() async throws { AuthenticationCases().testRefusesToConstructWithoutAKey() }
    @Test func testReadsKeyFromEnvironmentAndDefaultsBaseURL() async throws { try await AuthenticationCases().testReadsKeyFromEnvironmentAndDefaultsBaseURL() }
    @Test func testPlanLimitCarriesTheFullOfferDetectedByCode() async throws { try await ErrorCases().testPlanLimitCarriesTheFullOfferDetectedByCode() }
    @Test func testNeverRetriesAQuotaExhausted429() async throws { try await ErrorCases().testNeverRetriesAQuotaExhausted429() }
    @Test func testRetriesAnOrdinary429OnAPostAndHonoursRetryAfter() async throws { try await ErrorCases().testRetriesAnOrdinary429OnAPostAndHonoursRetryAfter() }
    @Test func testGivesUpOnAPersistentThrottleWithRateLimitError() async throws { try await ErrorCases().testGivesUpOnAPersistentThrottleWithRateLimitError() }
    @Test func testRetries503OnGetButNotOnPost() async throws { try await ErrorCases().testRetries503OnGetButNotOnPost() }
    @Test func testMapsStatusesToTypedErrorsAndReadsTheOpenAIShape() async throws { try await ErrorCases().testMapsStatusesToTypedErrorsAndReadsTheOpenAIShape() }
    @Test func testRetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkError() async throws { try await ErrorCases().testRetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkError() }
    @Test func testEncodesPathParamsRequiredAndOptionalQueryAndBody() async throws { try await RequestCases().testEncodesPathParamsRequiredAndOptionalQueryAndBody() }
    @Test func testReturnsNullForAnEmpty204AndStringsForNonJSON() async throws { try await RequestCases().testReturnsNullForAnEmpty204AndStringsForNonJSON() }
    @Test func testExposesARawRequestEscapeHatch() async throws { try await RequestCases().testExposesARawRequestEscapeHatch() }
    @Test func testBuildsQueryStringsAndBackoffDelays() async throws { RequestCases().testBuildsQueryStringsAndBackoffDelays() }
    @Test func testStreamsChatCompletionsUntilDoneForcingStreamTrue() async throws { try await StreamingCases().testStreamsChatCompletionsUntilDoneForcingStreamTrue() }
    @Test func testYieldsNamedEventsMultiLineDataAndATrailingFrame() async throws { try await StreamingCases().testYieldsNamedEventsMultiLineDataAndATrailingFrame() }
    @Test func testRaisesAPlanLimitFrameAsPlanLimitError() async throws { try await StreamingCases().testRaisesAPlanLimitFrameAsPlanLimitError() }
    @Test func testRaisesAnHTTPErrorBeforeStreamingAndNeverRetries() async throws { try await StreamingCases().testRaisesAnHTTPErrorBeforeStreamingAndNeverRetries() }
    @Test func testWalksOffsetPagesUntilAShortPage() async throws { try await PaginationCases().testWalksOffsetPagesUntilAShortPage() }
    @Test func testDrivesARealListMethodAndRespectsMaxItems() async throws { try await PaginationCases().testDrivesARealListMethodAndRespectsMaxItems() }
    @Test func testEveryOperationBuildsItsVerbAndURL() async throws { try await ResourceCases().testEveryOperationBuildsItsVerbAndURL() }
}
#endif
