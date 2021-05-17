import { expect } from 'chai';
import { ethers } from "hardhat";
import { deployContract, MockProvider } from 'ethereum-waffle';
import ERC20Json from '../artifacts/contracts/test/ERC20.sol/ERC20.json';
import ZapJson from '../artifacts/contracts/Zap.sol/Zap.json';
import WETH9Json from '../artifacts/contracts/test/WETH9.sol/WETH9.json';
import UniswapV2Router02Json from '../../uniswap-v2-periphery/build/UniswapV2Router02.json';
import UniswapV2FactoryJson from '../../uniswap-v2-core/build/UniswapV2Factory.json';
import { BigNumber, Contract } from 'ethers';
import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json';
import IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json';

export function expandTo18Decimals(n: number): BigNumber {
  return ethers.BigNumber.from(n).mul(ethers.BigNumber.from(10).pow(18))
}

const overrides = {
  gasLimit: 9999999
}

describe("Zap", function () {
  let zap: Contract;
  let weth: Contract;
  let wethPartner: Contract;
  let uniswapV2Factory: Contract;
  let wethPair: Contract;
  let initialPairWETHAmount: BigNumber;
  let initialPairWETHPartnerAmount: BigNumber;

  const provider = new MockProvider({
    ganacheOptions: {
      gasLimit: 9999999
    }
  });
  const [wallet] = provider.getWallets();
  let walletAddress: string;

  before(async () => {
    walletAddress = await wallet.getAddress();
    weth = await deployContract(wallet, WETH9Json)
    uniswapV2Factory = await deployContract(wallet, UniswapV2FactoryJson, [wallet.address]);
    const uniswapV2Router02 = await deployContract(wallet, UniswapV2Router02Json, [uniswapV2Factory.address, weth.address], overrides);
    
    wethPartner = await deployContract(wallet, ERC20Json, [expandTo18Decimals(100)]);
    zap = await deployContract(wallet, ZapJson, [uniswapV2Factory.address, uniswapV2Router02.address, weth.address], overrides);
    
    // Get some weth
    const wethAmount = expandTo18Decimals(20);
    await weth.deposit({ value: wethAmount });

    // Allowance to zap contract
    await weth.approve(zap.address, ethers.constants.MaxUint256);
  });

  before("Create pair", async () => {
    await uniswapV2Factory.createPair(wethPartner.address, weth.address);

    const wethPairAddress = await uniswapV2Factory.getPair(weth.address, wethPartner.address);
    wethPair = new Contract(wethPairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet);

    initialPairWETHAmount = expandTo18Decimals(20);
    initialPairWETHPartnerAmount = expandTo18Decimals(40);
  })

  it("Swap to weth works", async function () {

    const oldBalance = await provider.getBalance(walletAddress);
    const oldwethBalance = await weth.balanceOf(walletAddress);

    // I've spent one on previous test
    expect(oldwethBalance).to.eq(expandTo18Decimals(20));

    const wethAmount = expandTo18Decimals(30);
    await weth.deposit({ value: wethAmount });

    const balance = await provider.getBalance(walletAddress);
    const wethBalance = await weth.balanceOf(walletAddress);
    
    expect(oldwethBalance).to.lt(wethBalance);
    expect(oldBalance).to.gt(balance);
    expect(wethBalance).to.eq(expandTo18Decimals(50));
  });

  it("Zap to empty pool", async function () {

    logBasicInfo();
    await logCurrentBalances();
    // TODO: This value may change at anytime, should be calculated correctly
    const lpBought = BigNumber.from("689860274328339047");
    const wethAmount = expandTo18Decimals(1);
    await zap.deployed();
    await expect(await zap.ZapToken(weth.address, wethPair.address, wethAmount, true))
      .to.emit(weth, 'Transfer')
      .withArgs(wallet.address, zap.address, wethAmount)
      .to.emit(zap, 'zapToken')
      .withArgs(walletAddress, wethPair.address, lpBought);
    await logCurrentBalances();
  });

  function logBasicInfo() {
    console.log('Address:                 ' + weth.address);
    console.log('PARTNER Address:         ' + wethPartner.address);
    console.log('PAIR Address:            ' + wethPair.address);
    console.log('ZAP Address:             ' + zap.address);
  }

  async function logCurrentBalances() {
    console.log('----------------------Line------------------------');
    console.log('ZAP weth balance:        ' + await weth.balanceOf(zap.address));
    console.log('ZAP t2 balance:          ' + await wethPartner.balanceOf(zap.address));
    console.log('PAIR weth balance:       ' + await weth.balanceOf(wethPair.address));
    console.log('PAIR t2 balance:         ' + await wethPartner.balanceOf(wethPair.address));
    console.log('WALLET weth balance:     ' + await weth.balanceOf(walletAddress));
    console.log('WALLET t2 balance:       ' + await wethPartner.balanceOf(walletAddress));
    console.log('WALLET pair balance:     ' + await wethPair.balanceOf(walletAddress));
  }

});