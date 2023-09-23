import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("Correlatzia", function () {
    let buyer, seller1, seller2;
    let instance: Contract;
    let instanceAddress: string;
    let usdc: Contract;
    const initialAmount = 100;
    this.beforeEach(async () => {
        // seller1 is default signer
        [seller1, buyer, seller2] = await ethers.getSigners();
        // Deploy contracts
        usdc = await ethers.deployContract("USDC");// for the test we are deploying our own but for testing in the network we will use the real address
        instance = await ethers.deployContract("Orders", [await usdc.getAddress()]);
        instanceAddress = await instance.getAddress();

        await usdc.mint(seller1.address, initialAmount);
        await usdc.mint(seller2.address, initialAmount);
    });

    it("User can deposit funds", async () => {
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit();

        expect(await usdc.balanceOf(instanceAddress)).to.be.eq(initialAmount);
        expect(await instance.balances(seller1.address)).to.be.eq(initialAmount);
    });


    it("User must approve before deposit", async () => {

        await expect(instance.deposit()).to.be.reverted;

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(initialAmount);
    });


    it("User can withdraw funds partially and totally", async () => {
        // deposit
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit();

        const halfAmount = initialAmount / 2;
        // partial withdraw
        await instance.withdrawFunds(halfAmount);

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(halfAmount);
        expect(await instance.balances(seller1.address)).to.be.eq(halfAmount);

        // total withdraw
        await instance.withdrawFunds(halfAmount);

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(initialAmount);
        expect(await instance.balances(seller1.address)).to.be.eq(0);
    });

    it("User can request to buy from another", async () => {
        await expect(instance.buy(0, seller1.address)).to.be.revertedWith("Invalid amount");
        await expect(instance.buy(initialAmount, seller1.address)).to.be.revertedWith("Invalid seller amount");
        // seller 1 deposits
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit();

        // seller 2 deposits
        await usdc.connect(seller2).approve(instanceAddress, initialAmount);

        await instance.connect(seller2).deposit();

        // buyer place order for seller 1
        await instance.connect(buyer).buy(initialAmount, seller1.address);
        const [oAmount1, oSeller1] = await instance.connect(buyer).getOrder(0);
        expect(oAmount1).to.be.eq(initialAmount);
        expect(oSeller1).to.be.eq(seller1.address);
        expect(await instance.balances(seller1.address)).to.be.eq(0);

        // buyer place order for seller 2
        await instance.connect(buyer).buy(initialAmount, seller2.address);
        const [oAmount2, oSeller2] = await instance.connect(buyer).getOrder(1);
        expect(oAmount2).to.be.eq(initialAmount);
        expect(oSeller2).to.be.eq(seller2.address);
        expect(await instance.balances(seller1.address)).to.be.eq(0);
    });

    it("Buyer can redeem the order after maturity", async () => {
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit();


        // buyer place order for seller 1
        await instance.connect(buyer).buy(initialAmount, seller1.address);
        
        await expect(instance.connect(buyer).withdrawAtMaturity(0)).to.be.revertedWith("Maturity not reached yet");
        const newTimestamp = (await ethers.provider.getBlock("latest"))!.timestamp + (30 * 24 * 60 * 60);
        await time.increaseTo(newTimestamp);

        const prevBalance = await ethers.provider.getBalance(seller1.address);
        await instance.connect(buyer).withdrawAtMaturity(0);

        expect(await ethers.provider.getBalance(seller1.address)).to.be.eq(prevBalance);
        expect(await usdc.balanceOf(buyer.address)).to.be.eq(initialAmount);

        await expect(instance.connect(buyer).withdrawAtMaturity(0)).to.be.revertedWith("Order already redeemed");
    });
});