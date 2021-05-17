//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "@uniswap/lib/contracts/libraries/Babylonian.sol";

contract Zap is ReentrancyGuard, Ownable  {

    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    constructor(
        address _uniFactory, 
        address _uniRouter, 
        address _wbnbAddress
    ) public {
        uniswapV2Factory = IUniswapV2Factory(_uniFactory);
        uniswapRouter = IUniswapV2Router02(_uniRouter);
        wbnbAddress = _wbnbAddress; //0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    }

    uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;

    address public wbnbAddress;
    IUniswapV2Factory private uniswapV2Factory;
    IUniswapV2Router02 private uniswapRouter;

    event zapToken(address sender, address pool, uint256 lpAmount);

    /**
    @notice Creates a pair using uniswap test router/factory
    @param _sentToken ERC20 token sent
    @param _pairAddress The deployed pair address
    @param _amount The amount of _sentToken to send
    @param _donateLeftovers Set true to save gas donating the leftovers of the zap
    @return Amount of LP returned
     */
    function ZapToken(
        address _sentToken,
        address _pairAddress,
        uint256 _amount,
        bool _donateLeftovers
    ) external payable nonReentrant returns (uint256) {

        IERC20(_sentToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 lpAmount = _zapToken(
            _sentToken,
            _pairAddress,
            _amount,
            _donateLeftovers
        );

        emit zapToken(msg.sender, _pairAddress, lpAmount);

        IERC20(_pairAddress).safeTransfer(msg.sender, lpAmount);
        return lpAmount;
    }

    function _zapToken(
        address _sentToken,
        address _pairAddress,
        uint256 _amount,
        bool _donateLeftovers
    ) internal returns (uint256) {
        (address token0Address, address token1Address) = _getPairTokens(_pairAddress);

        (uint256 token0Bought, uint256 token1Bought) = _swapTokens(
            _sentToken,
            token0Address,
            token1Address,
            _amount
        );
    
        return
            _uniswapRouterDeposit(
                token0Address,
                token1Address,
                token0Bought,
                token1Bought,
                _donateLeftovers
            );
    }

    // Improvement, did it on another function to declare it as view.
    function _getPairTokens(
        address _pairAddress
    ) internal view returns (address token0, address token1)
    {
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(_pairAddress);
        token0 = uniswapPair.token0();
        token1 = uniswapPair.token1();
    }

    function _uniswapRouterDeposit(
        address _token0Address,
        address _token1Address,
        uint256 token0Bought,
        uint256 token1Bought,
        bool _donateLeftovers
    ) internal returns (uint256) {
        IERC20(_token0Address).safeApprove(address(uniswapRouter), 0);
        IERC20(_token1Address).safeApprove(address(uniswapRouter), 0);

        IERC20(_token0Address).safeApprove(address(uniswapRouter), token0Bought);
        IERC20(_token1Address).safeApprove(address(uniswapRouter), token1Bought);

        (uint256 amount0, uint256 amount1, uint256 lpTokens) = uniswapRouter.addLiquidity(
            _token0Address,
            _token1Address,
            token0Bought,
            token1Bought,
            1,
            1,
            address(this),
            deadline
        );

        if (!_donateLeftovers) {
            if (token0Bought.sub(amount0) > 0) {
                IERC20(_token0Address).safeTransfer(
                    msg.sender,
                    token0Bought.sub(amount0)
                );
            }

            if (token1Bought.sub(amount1) > 0) {
                IERC20(_token1Address).safeTransfer(
                    msg.sender,
                    token1Bought.sub(amount1)
                );
            }
        }

        return lpTokens;
    }

    /**
    @notice Should allow to 
    **/
    function _swapTokens(
        address _sentTokenAddress,
        address _token0Address,
        address _token1Address,
        uint256 _amount
    ) internal returns (uint256 token0Bought, uint256 token1Bought) {
        IUniswapV2Pair pair = IUniswapV2Pair(uniswapV2Factory.getPair(_token0Address, _token1Address));
        (uint256 res0, uint256 res1, ) = pair.getReserves();

        // Not sure if pair can be returned in other order, but let's check it just in case
        if (_sentTokenAddress == _token0Address) {
            uint256 amountToSwap = calculateSwapInAmount(res0, _amount);
            if (amountToSwap <= 0) amountToSwap = _amount.div(2);
            token1Bought = _swapTokensForTokens(
                _sentTokenAddress,
                _token1Address,
                amountToSwap
            );
            token0Bought = _amount.sub(amountToSwap);
        } else {
            uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
            if (amountToSwap <= 0) amountToSwap = _amount.div(2);
            token0Bought = _swapTokensForTokens(
                _sentTokenAddress,
                _token0Address,
                amountToSwap
            );
            token1Bought = _amount.sub(amountToSwap);
        }        
    }

    function calculateSwapInAmount(uint256 reserveFromPair, uint256 _amount)
        internal
        pure
        returns (uint256)
    {
        uint256 swapAmount = Babylonian
                .sqrt(reserveFromPair.mul(_amount.mul(3988000) + reserveFromPair.mul(3988009)))
                .sub(reserveFromPair.mul(1997)) / 1994;
        if (swapAmount <= 0) {
            swapAmount = _amount.div(2);
        }
    }

    function _swapTokensForTokens(
        address _sentToken,
        address _token1Address,
        uint256 _amountToTrade
    ) internal returns (uint256 amountTokensBought) {
        // Should never enter here, but to avoid any issues...
        if (_sentToken == _token1Address) {
            return _amountToTrade;
        }
        // Set first to zero because it's not possible to change from a non-zero to another non-zero
        IERC20(_sentToken).safeApprove(address(uniswapRouter), 0);
        IERC20(_sentToken).safeApprove(address(uniswapRouter), _amountToTrade);

        address pair = uniswapV2Factory.getPair(_sentToken, _token1Address);
        require(pair != address(0), "No pair available");

        address[] memory path = new address[](2);
        path[0] = _sentToken;
        path[1] = _token1Address;

        amountTokensBought = uniswapRouter.swapExactTokensForTokens(
            _amountToTrade,
            1,
            path,
            address(this),
            deadline
        )[path.length - 1];

        require(amountTokensBought > 0, "Something wrong happened, it should have a value");
    }
}
