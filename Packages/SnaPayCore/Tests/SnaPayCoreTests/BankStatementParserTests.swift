import Foundation
import Testing
@testable import SnaPayCore

struct BankStatementParserTests {
    let calendar = Calendar.israel

    @Test func parsesQuotedFieldsAndCRLF() {
        let csv = "\u{FEFF}a,\"b, with comma\",\"say \"\"hi\"\"\"\r\n1,2,3\r\n"
        #expect(BankStatementParser.parseCSV(csv) == [["a", "b, with comma", "say \"hi\""], ["1", "2", "3"]])
    }

    @Test func detectsSemicolonDelimiter() {
        #expect(BankStatementParser.parseCSV("x;y\n1;2") == [["x", "y"], ["1", "2"]])
    }

    @Test func checkingAccountWithDebitCreditColumns() throws {
        let csv = """
        תנועות בחשבון עו"ש
        מספר חשבון: 12-345-678901
        תאריך,תאריך ערך,תיאור התנועה,חובה,זכות,יתרה
        01/09/2026,01/09/2026,משכורת,,"12,500.00","15,200.00"
        03/09/2026,03/09/2026,הוראת קבע ועד בית,250.00,,"14,950.00"
        סה"כ,,,,,
        """
        let rows = BankStatementParser.parseCSV(csv)
        let (headerRow, mapping) = try BankStatementParser.detectMapping(rows)
        #expect(headerRow == 2)
        #expect(mapping == StatementColumnMapping(date: 0, description: 2, amount: nil, debit: 3, credit: 4))

        let result = try BankStatementParser.rows(from: Array(rows.dropFirst(headerRow + 1)), mapping: mapping, calendar: calendar)
        #expect(result.count == 2)
        #expect(result[0] == StatementRow(date: startOfDay(2026, 9, 1), description: "משכורת", amount: 12_500))
        #expect(result[1].amount == -250)
    }

    @Test func cardStatementWithPositiveCharges() throws {
        let csv = """
        תאריך עסקה,שם בית העסק,סכום עסקה,סכום חיוב
        23.09.26,ארומה,48.90,48.90
        """
        let rows = BankStatementParser.parseCSV(csv)
        let (headerRow, mapping) = try BankStatementParser.detectMapping(rows)
        #expect(mapping.amount == 3)
        let result = try BankStatementParser.rows(from: Array(rows.dropFirst(headerRow + 1)), mapping: mapping, amountsArePositiveForExpenses: true, calendar: calendar)
        #expect(result == [StatementRow(date: startOfDay(2026, 9, 23), description: "ארומה", amount: Decimal(string: "-48.90")!)])
    }

    @Test func missingHeaderThrows() {
        #expect(throws: BankStatementParserError.headerNotFound) {
            try BankStatementParser.detectMapping([["a", "b"], ["1", "2"]])
        }
    }

    @Test(arguments: [
        ("1,234.50", Decimal(string: "1234.50")),
        ("-1,234.50", Decimal(string: "-1234.50")),
        ("(99.90)", Decimal(string: "-99.90")),
        ("₪ 20", Decimal(20)),
        ("15.00-", Decimal(-15)),
        ("abc", nil),
        ("1.2.3", nil),
    ] as [(String, Decimal?)])
    func parsesAmounts(text: String, expected: Decimal?) {
        #expect(BankStatementParser.parseAmount(text) == expected)
    }

    @Test func parsesDates() {
        #expect(BankStatementParser.parseDate("23/09/2026", calendar: calendar) == startOfDay(2026, 9, 23))
        #expect(BankStatementParser.parseDate("2026-09-23", calendar: calendar) == startOfDay(2026, 9, 23))
        #expect(BankStatementParser.parseDate("31/02/2026", calendar: calendar) == nil)
        #expect(BankStatementParser.parseDate("סה\"כ", calendar: calendar) == nil)
    }
}
