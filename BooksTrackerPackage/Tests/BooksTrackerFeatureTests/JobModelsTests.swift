import Testing
@testable import BooksTrackerFeature

@Suite("Job Models Tests")
struct JobModelsTests {

    @Test("JobIdentifier creates unique IDs for same job type")
    func jobIdentifierUniqueness() {
        let job1 = JobIdentifier(jobType: "CSV_IMPORT")
        let job2 = JobIdentifier(jobType: "CSV_IMPORT")

        #expect(job1.id != job2.id)
        #expect(job1.jobType == job2.jobType)
    }

    @Test("JobIdentifier is Hashable and Equatable")
    func jobIdentifierHashable() {
        let job1 = JobIdentifier(jobType: "TEST")
        let job2 = job1

        #expect(job1 == job2)
        #expect(job1.hashValue == job2.hashValue)
    }
}
