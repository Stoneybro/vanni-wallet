import assert from "assert";
import { 
  TestHelpers,
  AidraSmartWallet_CommitmentDecreased
} from "generated";
const { MockDb, AidraSmartWallet } = TestHelpers;

describe("AidraSmartWallet contract CommitmentDecreased event tests", () => {
  // Create mock db
  const mockDb = MockDb.createMockDb();

  // Creating mock for AidraSmartWallet contract CommitmentDecreased event
  const event = AidraSmartWallet.CommitmentDecreased.createMockEvent({/* It mocks event fields with default values. You can overwrite them if you need */});

  it("AidraSmartWallet_CommitmentDecreased is created correctly", async () => {
    // Processing the event
    const mockDbUpdated = await AidraSmartWallet.CommitmentDecreased.processEvent({
      event,
      mockDb,
    });

    // Getting the actual entity from the mock database
    let actualAidraSmartWalletCommitmentDecreased = mockDbUpdated.entities.AidraSmartWallet_CommitmentDecreased.get(
      `${event.chainId}_${event.block.number}_${event.logIndex}`
    );

    // Creating the expected entity
    const expectedAidraSmartWalletCommitmentDecreased: AidraSmartWallet_CommitmentDecreased = {
      id: `${event.chainId}_${event.block.number}_${event.logIndex}`,
      token: event.params.token,
      amount: event.params.amount,
      newTotal: event.params.newTotal,
    };
    // Asserting that the entity in the mock database is the same as the expected entity
    assert.deepEqual(actualAidraSmartWalletCommitmentDecreased, expectedAidraSmartWalletCommitmentDecreased, "Actual AidraSmartWalletCommitmentDecreased should be the same as the expectedAidraSmartWalletCommitmentDecreased");
  });
});
