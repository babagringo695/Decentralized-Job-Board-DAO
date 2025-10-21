import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;

describe("Job Posting Management Contract", () => {
  it("should successfully load the contract", () => {
    const nextId = simnet.callReadOnlyFn(
      "job-posting-management",
      "get-next-job-id",
      [],
      deployer
    );

    expect(nextId.result).toBeUint(1);
  });

  it("should track total escrow locked", () => {
    const totalEscrow = simnet.callReadOnlyFn(
      "job-posting-management",
      "get-total-escrow-locked",
      [],
      deployer
    );

    expect(totalEscrow.result).toBeUint(0);
  });
});
