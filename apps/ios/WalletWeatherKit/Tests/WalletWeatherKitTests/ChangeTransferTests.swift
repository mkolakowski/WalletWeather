import Foundation
import Testing
@testable import WalletWeatherKit

extension StubServerSuites {
    /// Change transfer (#324): what the app sends to `PATCH /api/transfers/{id}`
    /// and how it reads the transfer it fills the form from.
    @Suite struct ChangeTransferRequests {
        static func client() -> APIClient {
            APIClient(connection: Connection(server: URL(string: "https://ww.example.com")!, token: "ww_sample-token-not-real"),
                      session: StubServer.session())
        }

        static let answer = Data("""
        {"id": 7, "from_account_id": 1, "from_account_name": "Checking", "to_account_id": 2, "to_account_name": "Savings",
         "amount": 75.5, "transfer_date": "2026-11-17", "description": "Pocket money", "notes": null,
         "transaction_ids": [11, 12], "created_at": "2026-11-15T12:00:00"}
        """.utf8)

        @Test func savingSendsThePatchTheWebAppSends() async throws {
            StubServer.answer(200, Self.answer)
            var draft = MoveMoneyDraft(today: LocalDay(year: 2026, month: 11, day: 17), from: 1, to: 2)
            draft.amountText = "75.5"
            draft.description = "Pocket money"
            draft.notes = "  "
            let saved = try await Self.client().updateTransfer(7, try #require(TransferBody(draft)))
            #expect(saved.id == 7 && saved.amount == Money(Decimal(string: "75.5")!) && saved.toAccountName == "Savings")
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "PATCH" && request.url?.path == "/api/transfers/7")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ww_sample-token-not-real")
            let body = try #require(StubServer.lastBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
            #expect(body["from_account_id"] as? Int == 1 && body["to_account_id"] as? Int == 2)
            #expect(body["amount"] as? Double == 75.5)
            #expect(body["transfer_date"] as? String == "2026-11-17")
            #expect(body["description"] as? String == "Pocket money")
            #expect(body["notes"] is NSNull)
        }

        @Test func theFormIsFilledInFromTheTransferInTheList() async throws {
            let list = Data("""
            {"total": 2, "transfers": [
              {"id": 9, "from_account_id": 2, "from_account_name": "Savings", "to_account_id": 1, "to_account_name": "Checking",
               "amount": 10, "transfer_date": "2026-11-18", "description": "Transfer", "notes": null, "transaction_ids": [13, 14]},
              {"id": 7, "from_account_id": 1, "from_account_name": "Checking", "to_account_id": 2, "to_account_name": "Savings",
               "amount": 75.5, "transfer_date": "2026-11-17", "description": "Pocket money", "notes": "For Sam",
               "transaction_ids": [11, 12]}]}
            """.utf8)
            StubServer.answer(200, list)
            let found = try await Self.client().transfer(7)
            let request = try #require(StubServer.lastRequest)
            #expect(request.httpMethod == "GET" && request.url?.path == "/api/transfers")
            let draft = MoveMoneyDraft(changing: found)
            #expect(draft.fromAccountId == 1 && draft.toAccountId == 2)
            #expect(draft.amountText == "75.5" && draft.date == LocalDay(year: 2026, month: 11, day: 17))
            #expect(draft.description == "Pocket money" && draft.notes == "For Sam" && draft.problem == nil)

            // One that isn't in the list is the server's 404.
            do {
                _ = try await Self.client().transfer(99)
                Issue.record("found a transfer that isn't there")
            } catch {
                guard case let .server(status, _) = error else { Issue.record("\(error)"); return }
                #expect(status == 404)
            }
        }

        @Test func aRefusalIsPassedOnAsTheServerWordedIt() async throws {
            StubServer.answer(400, Data(#"{"detail": "from_account and to_account must differ"}"#.utf8))
            do {
                try await Self.client().updateTransfer(7, TransferBody(from: 1, to: 1, amount: 5, on: LocalDay(year: 2026, month: 11, day: 17)))
                Issue.record("a refused change went through")
            } catch {
                guard case let .server(status, detail) = error else { Issue.record("\(error)"); return }
                #expect(status == 400 && detail == "from_account and to_account must differ")
            }
        }
    }
}
