// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../libraries/PriceConverter.sol";
import "../../token/interfaces/IERC20Custom.sol";

contract MockPresale is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    struct PresaleData {
        uint256 startingTime;
        uint256 usdPrice;
    }

    event TokenPresold(
        address indexed to,
        address indexed paymentTokenAddress,
        uint256 amount,
        uint256 paymentTokenamount
    );

    Counters.Counter public totalPresaleRound;
    address public tokenAddress;
    address payable public presaleReceiver;

    // Mapping `presaleRound` to its data details
    mapping(uint256 => PresaleData) presaleDetailsMapping;
    mapping(address => bool) presaleTokenAvaliblilityMapping;

    error presaleRoundClosed();
    error presaleTokenNotAvailable();
    error presaleNativeTokenPaymentNotSufficient();
    error presaleStartingTimeInvalid();
    error presaleUSDPriceInvalid();

    constructor(address _tokenAddress, address payable _presaleReceiver) {
        tokenAddress = _tokenAddress;
        presaleReceiver = _presaleReceiver;
    }

    /**
     * Get Current Presale Round
     */
    function getCurrentPresaleRound() public view returns (uint256) {
        for (
            uint256 presaleRound = totalPresaleRound.current() - 1;
            presaleRound > 0;
            presaleRound--
        ) {
            if (
                presaleDetailsMapping[presaleRound].startingTime <=
                block.timestamp
            ) {
                return presaleRound;
            }
        }

        return 0;
    }

    /**
     * Getting the Current Price
     */
    function getCurrentPrice() public view returns (uint256) {
        uint256 currentPresaleRound = getCurrentPresaleRound();
        return presaleDetailsMapping[currentPresaleRound].usdPrice;
    }

    /**
     * Execute the Presale of ALPS Token in exchange of other token
     *
     * @dev _paymentTokenAddress - Address of the token use to pay (address 0 is for native token)
     * @dev _amount - Amount denominated in the `paymentTokenAddress` being paid
     * @dev _aggregatorTokenAddress - Use to convert price with Chainlink
     */
    function presaleTokens(
        address _paymentTokenAddress,
        uint256 _amount,
        address // Aggregator Address is unused here
    ) public payable nonReentrant {
        uint256 currentPresaleRound = getCurrentPresaleRound();

        // Check whether the presale round is still open
        PresaleData memory currentPresale = presaleDetailsMapping[
            currentPresaleRound
        ];
        if (block.timestamp >= currentPresale.startingTime)
            revert presaleRoundClosed();

        // Check whether token is valid
        if (presaleTokenAvaliblilityMapping[_paymentTokenAddress])
            revert presaleTokenNotAvailable();

        // Convert the token with Chainlink Price Feed
        IERC20Custom token = IERC20Custom(tokenAddress);
        uint256 presaleAmount = 10**18;

        // Receive the payment token and transfer it to another address
        if (_paymentTokenAddress == address(0)) {
            if (msg.value < _amount) {
                revert presaleNativeTokenPaymentNotSufficient();
            } else {
                presaleReceiver.transfer(_amount);

                // in case you deployed the contract with more ether than required,
                // transfer the remaining ether back to yourself
                payable(msg.sender).transfer(address(this).balance);
            }
        } else {
            IERC20 paymentToken = IERC20(_paymentTokenAddress);
            paymentToken.transferFrom(msg.sender, presaleReceiver, _amount);
        }

        // Send ALPS token to `msg.sender`
        token.mint(msg.sender, presaleAmount);
        emit TokenPresold(
            msg.sender,
            _paymentTokenAddress,
            presaleAmount,
            _amount
        );
    }

    /**
     * Set new Presale Receiver Address
     *
     * @dev _newPresaleReceiver - Address that'll receive the presale payment token
     */
    function setPresaleReceiver(address payable _newPresaleReceiver)
        public
        onlyOwner
    {
        presaleReceiver = _newPresaleReceiver;
    }

    function setPresaleTokenAddress(address _newTokenAddress) public onlyOwner {
        tokenAddress = _newTokenAddress;
    }

    /**
     * Creating/Updating a presale round information
     *
     * @dev _presaleRound - The presale round chosen
     * @dev _startingTime - The starting Presale time
     * @dev _usdPrice - The USD Price of the Token in certain Presale Round
     */
    function setPresaleRound(
        uint256 _presaleRound,
        uint256 _startingTime,
        uint256 _usdPrice
    ) public onlyOwner {
        uint256 presaleStartingTime = presaleDetailsMapping[_presaleRound]
            .startingTime;
        uint256 presaleUSDPrice = presaleDetailsMapping[_presaleRound].usdPrice;
        // Increment the total round counter when new presale is created
        if (presaleStartingTime == 0 && presaleUSDPrice == 0)
            totalPresaleRound.increment();

        // Starting time has to be:
        // - larger than zero
        // - larger than previous round starting time
        if (
            _startingTime == 0 ||
            (_presaleRound != 0 &&
                _startingTime <
                presaleDetailsMapping[_presaleRound - 1].startingTime)
        ) revert presaleStartingTimeInvalid();

        // USD Price given must be larger than zero
        if (_usdPrice == 0) revert presaleUSDPriceInvalid();

        presaleDetailsMapping[_presaleRound].startingTime = _startingTime;
        presaleDetailsMapping[_presaleRound].usdPrice = _usdPrice;
    }
}