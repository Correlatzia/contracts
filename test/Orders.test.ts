import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { AddressLike } from "ethers";

describe("Correlatzia", function () {
    let buyer: { address: AddressLike; }, seller1: { address: AddressLike; }, seller2: { address: AddressLike; };
    let instance: Contract;
    let instanceAddress: string;
    let usdc: Contract;
    const initialAmount = 100;
    const strike = 10;
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

        await expect(instance.deposit(strike)).to.emit(instance, 'NewDeposit').withArgs(seller1.address, initialAmount, strike);

        expect(await usdc.balanceOf(instanceAddress)).to.be.eq(initialAmount);
        expect(await instance.getBalance(seller1.address)).to.be.eq(initialAmount);
    });


    it("User must approve before deposit", async () => {

        await expect(instance.deposit(strike)).to.be.reverted;

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(initialAmount);
    });


    it("User can withdraw funds partially and totally", async () => {
        // deposit
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit(strike);

        const halfAmount = initialAmount / 2;
        // partial withdraw
        await expect(instance.withdrawFunds(halfAmount)).to.emit(instance, 'WithdrawFunds').withArgs(seller1.address, halfAmount);

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(halfAmount);
        expect(await instance.getBalance(seller1.address)).to.be.eq(halfAmount);

        // total withdraw
        await instance.withdrawFunds(halfAmount);

        expect(await usdc.balanceOf(seller1.address)).to.be.eq(initialAmount);
        expect(await instance.getBalance(seller1.address)).to.be.eq(0);
    });

    it("User can request to buy from another", async () => {
        await usdc.mint(buyer.address, initialAmount)
        await usdc.connect(buyer).approve(instanceAddress, initialAmount);
        await expect(instance.buy(0, seller1.address)).to.be.revertedWith("Invalid amount");
        await expect(instance.buy(initialAmount, seller1.address)).to.be.revertedWith("Invalid seller amount");
        // seller 1 deposits
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit(strike);

        // seller 2 deposits
        await usdc.connect(seller2).approve(instanceAddress, initialAmount);

        await instance.connect(seller2).deposit(strike);

        // buyer place order for seller 1
        await expect(instance.connect(buyer).buy(initialAmount, seller1.address)).to.emit(instance, 'PlaceOrder').withArgs(seller1.address, buyer.address, initialAmount);
        const [oAmount1, oSeller1] = await instance.connect(buyer).getOrder(0);
        expect(oAmount1).to.be.eq(initialAmount);
        expect(oSeller1).to.be.eq(seller1.address);
        expect(await instance.getBalance(seller1.address)).to.be.eq(0);

        // buyer place order for seller 2
        await usdc.mint(buyer.address, initialAmount)
        await usdc.connect(buyer).approve(instanceAddress, initialAmount);
        await instance.connect(buyer).buy(initialAmount, seller2.address);
        const [oAmount2, oSeller2] = await instance.connect(buyer).getOrder(1);
        expect(oAmount2).to.be.eq(initialAmount);
        expect(oSeller2).to.be.eq(seller2.address);
        expect(await instance.getBalance(seller1.address)).to.be.eq(0);
    });

    it("Buyer can redeem the order after maturity", async () => {
        await usdc.approve(instanceAddress, initialAmount);

        await instance.deposit(strike);

        // buyer place order for seller 1
        await usdc.mint(buyer.address, initialAmount)
        await usdc.connect(buyer).approve(instanceAddress, initialAmount);
        await instance.connect(buyer).buy(initialAmount, seller1.address);
        
        await expect(instance.connect(buyer).withdrawAtMaturity(0)).to.be.revertedWith("Maturity not reached yet");
        const newTimestamp = (await ethers.provider.getBlock("latest"))!.timestamp + (30 * 24 * 60 * 60);
        await time.increaseTo(newTimestamp);
        // buyer redeems order
        const prevBalance = await usdc.balanceOf(seller1.address);
        await instance.connect(buyer).withdrawAtMaturity(0);

        expect(await usdc.balanceOf(seller1.address)).to.be.gt(prevBalance);
        expect(await usdc.balanceOf(buyer.address)).to.be.eq(initialAmount);

        await expect(instance.connect(buyer).withdrawAtMaturity(0)).to.be.revertedWith("Order already redeemed");
    });


    it("Alice, Bob, and John scenario", async () => {
        const alice = seller1;
        const bob = buyer;
        const john = seller2;
        const aliceAmount = 10000;
        const bobAmount = 5000;
        const johnAmount = 3000;

        // alice gets 10_000
        await usdc.mint(alice, aliceAmount);
        // Bob gets 5000
        await usdc.mint(bob, bobAmount);
        //John gets 3000
        await usdc.mint(john, johnAmount);
        // Alice deposits 10_000
        await usdc.approve(instanceAddress, aliceAmount);

        await instance.deposit(strike);

        // Bob buys 5_000
        await usdc.connect(bob).approve(instanceAddress, bobAmount);
        await instance.connect(bob).buy(initialAmount, seller1.address);
        // John buys 3_000
        await usdc.connect(john).approve(instanceAddress, johnAmount);
        await instance.connect(john).buy(initialAmount, seller1.address);

        // Maturity period comes
        const newTimestamp = (await ethers.provider.getBlock("latest"))!.timestamp + (30 * 24 * 60 * 60);
        await time.increaseTo(newTimestamp);

        // 
  
    });
});