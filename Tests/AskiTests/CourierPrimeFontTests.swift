import Testing
@testable import Aski

@Suite struct CourierPrimeFontTests {
    @Test func courierPrimeFactoryProducesFontWithRequestedSize() {
        let font = ASCIIFont.courierPrime(size: 18)
        #expect(font.pointSize == 18)
        #expect(font.postScriptName.lowercased().contains("courier"))
    }
}
