import Foundation

#if canImport(XCTest)
import XCTest

// XCTest runs these on Linux toolchains and in Xcode. Classes run serially, which
// the process-wide stub and environment rely on.

final class AuthenticationTests: XCTestCase {
    func testSendsBearerKeyAndSdkHeaders() async throws { try await AuthenticationCases().testSendsBearerKeyAndSdkHeaders() }
    func testRefusesToConstructWithoutAKey() async throws { AuthenticationCases().testRefusesToConstructWithoutAKey() }
    func testReadsKeyFromEnvironmentAndDefaultsBaseURL() async throws { try await AuthenticationCases().testReadsKeyFromEnvironmentAndDefaultsBaseURL() }
}

final class ErrorTests: XCTestCase {
    func testPlanLimitCarriesTheFullOfferDetectedByCode() async throws { try await ErrorCases().testPlanLimitCarriesTheFullOfferDetectedByCode() }
    func testNeverRetriesAQuotaExhausted429() async throws { try await ErrorCases().testNeverRetriesAQuotaExhausted429() }
    func testRetriesAnOrdinary429OnAPostAndHonoursRetryAfter() async throws { try await ErrorCases().testRetriesAnOrdinary429OnAPostAndHonoursRetryAfter() }
    func testGivesUpOnAPersistentThrottleWithRateLimitError() async throws { try await ErrorCases().testGivesUpOnAPersistentThrottleWithRateLimitError() }
    func testRetries503OnGetButNotOnPost() async throws { try await ErrorCases().testRetries503OnGetButNotOnPost() }
    func testMapsStatusesToTypedErrorsAndReadsTheOpenAIShape() async throws { try await ErrorCases().testMapsStatusesToTypedErrorsAndReadsTheOpenAIShape() }
    func testRetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkError() async throws { try await ErrorCases().testRetriesNetworkFailuresForIdempotentCallsThenThrowsNetworkError() }
}

final class RequestTests: XCTestCase {
    func testEncodesPathParamsRequiredAndOptionalQueryAndBody() async throws { try await RequestCases().testEncodesPathParamsRequiredAndOptionalQueryAndBody() }
    func testReturnsNullForAnEmpty204AndStringsForNonJSON() async throws { try await RequestCases().testReturnsNullForAnEmpty204AndStringsForNonJSON() }
    func testExposesARawRequestEscapeHatch() async throws { try await RequestCases().testExposesARawRequestEscapeHatch() }
    func testBuildsQueryStringsAndBackoffDelays() async throws { RequestCases().testBuildsQueryStringsAndBackoffDelays() }
}

final class StreamingTests: XCTestCase {
    func testStreamsChatCompletionsUntilDoneForcingStreamTrue() async throws { try await StreamingCases().testStreamsChatCompletionsUntilDoneForcingStreamTrue() }
    func testYieldsNamedEventsMultiLineDataAndATrailingFrame() async throws { try await StreamingCases().testYieldsNamedEventsMultiLineDataAndATrailingFrame() }
    func testRaisesAPlanLimitFrameAsPlanLimitError() async throws { try await StreamingCases().testRaisesAPlanLimitFrameAsPlanLimitError() }
    func testRaisesAnHTTPErrorBeforeStreamingAndNeverRetries() async throws { try await StreamingCases().testRaisesAnHTTPErrorBeforeStreamingAndNeverRetries() }
}

final class PaginationTests: XCTestCase {
    func testWalksOffsetPagesUntilAShortPage() async throws { try await PaginationCases().testWalksOffsetPagesUntilAShortPage() }
    func testDrivesARealListMethodAndRespectsMaxItems() async throws { try await PaginationCases().testDrivesARealListMethodAndRespectsMaxItems() }
}

final class ResourceTests: XCTestCase {
    func testEveryOperationBuildsItsVerbAndURL() async throws { try await ResourceCases().testEveryOperationBuildsItsVerbAndURL() }
}
#endif
