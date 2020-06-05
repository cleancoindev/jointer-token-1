pragma solidity ^0.5.9;

import "../common/Ownable.sol";
import "../common/SafeMath.sol";
import "../common/TokenTransfer.sol";
import "../InterFaces/IAuctionRegistery.sol";
import "../InterFaces/IAuctionTagAlong.sol";
import "../InterFaces/IAuctionProtection.sol";
import "../InterFaces/IERC20Token.sol";
import "../InterFaces/ICurrencyPrices.sol";
import "../InterFaces/IAuctionLiquadity.sol";
import "../InterFaces/ITokenVault.sol";
import "../InterFaces/IToken.sol";
import "../InterFaces/IIndividualBonus.sol";
import "../InterFaces/IWhiteList.sol";


contract AuctionRegistery is Ownable, AuctionRegisteryContracts {
    IAuctionRegistery public contractsRegistry;

    address payable public whiteListAddress;
    address payable public smartSwapAddress;
    address payable public currencyPricesAddress;
    address payable public vaultAddress;
    address payable public mainTokenAddress;
    address payable public auctionProtectionAddress;
    address payable public liquadityAddress;
    address payable public companyFundWalletAddress;
    address payable public companyTokenWalletAddress;
    address payable public individualBonusAddress;

    constructor(
        address _systemAddress,
        address _multisigAdress,
        address _registeryAddress
    ) public Ownable(_systemAddress, _multisigAdress) {
        contractsRegistry = IAuctionRegistery(_registeryAddress);
        _updateAddresses();
    }

    function updateRegistery(address _address)
        external
        onlyAuthorized()
        notZeroAddress(_address)
        returns (bool)
    {
        contractsRegistry = IAuctionRegistery(_address);
        _updateAddresses();
        return true;
    }

    function getAddressOf(bytes32 _contractName)
        internal
        view
        returns (address payable)
    {
        return contractsRegistry.getAddressOf(_contractName);
    }

    /**@dev updates all the address from the registry contract
    this decision was made to save gas that occurs from calling an external view function */

    function _updateAddresses() internal {
        whiteListAddress = getAddressOf(WHITE_LIST);
        smartSwapAddress = getAddressOf(SMART_SWAP);
        currencyPricesAddress = getAddressOf(CURRENCY);
        vaultAddress = getAddressOf(VAULT);
        mainTokenAddress = getAddressOf(MAIN_TOKEN);
        auctionProtectionAddress = getAddressOf(AUCTION_PROTECTION);
        liquadityAddress = getAddressOf(LIQUADITY);
        companyFundWalletAddress = getAddressOf(COMPANY_FUND_WALLET);
        companyTokenWalletAddress = getAddressOf(COMPANY_MAIN_TOKEN_WALLET);
        individualBonusAddress = getAddressOf(INDIVIDUAL_BONUS);
    }

    function updateAddresses() external returns (bool) {
        _updateAddresses();
    }
}


contract AuctionUtils is AuctionRegistery {
    uint256 public constant PERCENT_NOMINATOR = 10**6;

    uint256 public constant DECIMAL_NOMINATOR = 10**18;

    // allowed contarct limit the contribution
    uint256 public maxContributionAllowed = 150;

    // managment fee to run auction cut from basesupply
    uint256 public mangmentFee = 2;

    uint256 public stacking = 1;

    // fund that will be locked in contacrt
    uint256 public downSideProtectionRatio = 90;

    // Fund goes to companyWallet
    uint256 public fundWalletRatio = 90;

    // if contribution reach above yesterdayContribution groupBonus multiplyer
    uint256 public groupBonusRatio = 2;

    // user neeed this amount of mainToken to contribute
    uint256 public mainTokenRatio = 100;

    // how much buffer we allow to user contribute more
    uint256 public bufferLimit = 105;

    //ByDefault it false
    bool public mainTokencheckOn;

    constructor(
        address _systemAddress,
        address _multisigAdress,
        address _registeryAddress
    )
        public
        AuctionRegistery(_systemAddress, _multisigAdress, _registeryAddress)
    {}

    function setGroupBonusRatio(uint256 _groupBonusRatio)
        external
        onlyOwner()
        returns (bool)
    {
        groupBonusRatio = _groupBonusRatio;
        return true;
    }

    function setMangmentFee(uint256 _mangmentFee)
        external
        onlyOwner()
        returns (bool)
    {
        mangmentFee = _mangmentFee;
        return true;
    }

    function setBufferLimit(uint256 _bufferLimit)
        external
        onlyOwner()
        returns (bool)
    {
        bufferLimit = _bufferLimit;
        return true;
    }

    function setDownSideProtectionRatio(uint256 _ratio)
        external
        onlyOwner()
        returns (bool)
    {
        require(_ratio < 100, "ERR_SHOULD_BE_LESS_THAN_100");
        downSideProtectionRatio = _ratio;
        return true;
    }

    function setfundWalletRatio(uint256 _ratio)
        external
        onlyOwner()
        returns (bool)
    {
        require(_ratio < 100, "ERR_SHOULD_BE_LESS_THAN_100");
        fundWalletRatio = _ratio;
        return true;
    }

    function setMainTokenRatio(uint256 _ratio)
        external
        onlyOwner()
        returns (bool)
    {
        mainTokenRatio = _ratio;
        return true;
    }

    function setMainTokenCheckOn(bool _mainTokencheckOn)
        external
        onlyOwner()
        returns (bool)
    {
        mainTokencheckOn = _mainTokencheckOn;
        return true;
    }

    function setMaxContributionAllowed(uint256 _maxContributionAllowed)
        external
        onlyOwner()
        returns (bool)
    {
        maxContributionAllowed = _maxContributionAllowed;
        return true;
    }
}


contract AuctionFormula is SafeMath, TokenTransfer {
    function calcuateAuctionTokenDistrubution(
        uint256 dayWiseContributionByWallet,
        uint256 dayWiseSupplyCore,
        uint256 dayWiseSupplyBonus,
        uint256 dayWiseContribution,
        uint256 downSideProtectionRatio
    ) internal pure returns (uint256, uint256) {
        uint256 _dayWiseSupplyCore = safeDiv(
            safeMul(dayWiseSupplyCore, dayWiseContributionByWallet),
            dayWiseContribution
        );

        uint256 _dayWiseSupplyBonus = 0;

        if (dayWiseSupplyBonus > 0)
            _dayWiseSupplyBonus = safeDiv(
                safeMul(dayWiseSupplyBonus, dayWiseContributionByWallet),
                dayWiseContribution
            );

        uint256 _returnAmount = safeAdd(
            _dayWiseSupplyCore,
            _dayWiseSupplyBonus
        );

        // user get only 100 - downSideProtectionRatio(90) fund only other fund is locked
        uint256 _userAmount = safeDiv(
            safeMul(_dayWiseSupplyCore, safeSub(100, downSideProtectionRatio)),
            100
        );

        return (_returnAmount, _userAmount);
    }

    function calcuateAuctionFundDistrubution(
        uint256 _value,
        uint256 downSideProtectionRatio,
        uint256 fundWalletRatio
    )
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 _downsideAmount = safeDiv(
            safeMul(_value, downSideProtectionRatio),
            100
        );
        uint256 newvalue = safeSub(_value, _downsideAmount);

        uint256 _fundwallet = safeDiv(safeMul(newvalue, fundWalletRatio), 100);

        newvalue = safeSub(newvalue, _fundwallet);

        return (_downsideAmount, _fundwallet, newvalue);
    }

    function calculateNewSupply(
        uint256 todayContribution,
        uint256 tokenPrice,
        uint256 decimal
    ) internal pure returns (uint256) {
        return
            safeDiv(
                safeMul(todayContribution, safeExponent(10, decimal)),
                tokenPrice
            );
    }

    function calculateSupplyPercent(uint256 _supply, uint256 _percent)
        internal
        pure
        returns (uint256)
    {
        uint256 _tempSupply = safeDiv(
            safeMul(_supply, 100),
            safeSub(100, _percent)
        );
        uint256 _managmantFee = safeSub(_tempSupply, _supply);
        return _managmantFee;
    }
}


contract AuctionStorage is AuctionFormula, AuctionUtils {
    uint256 public auctionDay = 1;

    // address how much invested by them in auciton till date
    mapping(address => uint256) public userTotalFund;

    // how much token recived by address in auciton till date
    mapping(address => uint256) public userTotalReturnToken;

    // day wise supply (groupBounus+coreSupply)
    mapping(uint256 => uint256) public dayWiseSupply;

    // day wise  coreSupply
    mapping(uint256 => uint256) public dayWiseSupplyCore;

    // day wise bonusSupply
    mapping(uint256 => uint256) public dayWiseSupplyBonus;

    // daywise contribution
    mapping(uint256 => uint256) public dayWiseContribution;

    // daywise markertPrice
    mapping(uint256 => uint256) public dayWiseMarketPrice;

    // dayWise downsideProtection Ratio
    mapping(uint256 => uint256) public dayWiseDownSideProtectionRatio;

    // address wise contribution each day
    mapping(uint256 => mapping(address => uint256)) public walletDayWiseContribution;

    // day wiser five top contributor
    mapping(uint256 => mapping(uint256 => address)) public topFiveContributior;

    //contributor Index
    mapping(uint256 => mapping(address => uint256)) public topContributiorIndex;

    // check if daywise token disturbuted
    mapping(uint256 => mapping(address => bool)) public returnToken;

    // total contribution till date
    uint256 public totalContribution = 2500000 * PERCENT_NOMINATOR;

    uint256 public todayContribution;

    uint256 public yesterdayContribution = 500 * PERCENT_NOMINATOR;

    uint256 public allowedMaxContribution = 850000000;

    uint256 public yesterdaySupply;

    uint256 public todaySupply = 50000 * DECIMAL_NOMINATOR;

    uint256 public tokenAuctionEndPrice = 10000;

    bool public auctionSoldOut;

    constructor(
        address _systemAddress,
        address _multisigAdress,
        address _registeryAddress
    ) public AuctionUtils(_systemAddress, _multisigAdress, _registeryAddress) {
        dayWiseDownSideProtectionRatio[auctionDay] = downSideProtectionRatio;
    }
}


contract AuctionFundCollector is AuctionStorage {
    event FundAdded(
        uint256 indexed _auctionDayId,
        uint256 _todayContribution,
        address indexed _fundBy,
        address indexed _fundToken,
        uint256 _fundAmount,
        uint256 _fundValue,
        uint256 _marketPrice
    );

    constructor(
        address _systemAddress,
        address _multisigAdress,
        address _registeryAddress
    )
        public
        AuctionStorage(_systemAddress, _multisigAdress, _registeryAddress)
    {}

    // check before contribution
    function _checkContribution(address _from) internal view returns (bool) {
        require(
            IWhiteList(whiteListAddress).isWhiteListed(_from),
            "ERR_WHITELIST_CHECK"
        );
        return true;
    }

    function mainTokenCheck(address _from, uint256 _contributedAmount)
        internal
        returns (bool)
    {
        IERC20Token mainToken = IERC20Token(mainTokenAddress);

        uint256 _mainTokenPrice = ICurrencyPrices(currencyPricesAddress)
            .getCurrencyPrice(mainTokenAddress);

        uint256 _tokenAmount = safeDiv(
            safeMul(
                safeDiv(
                    safeMul(mainToken.balanceOf(_from), mainTokenRatio),
                    100
                ),
                _mainTokenPrice
            ),
            safeExponent(10, mainToken.decimals())
        );

        require(
            _tokenAmount >=
                safeAdd(
                    walletDayWiseContribution[auctionDay][_from],
                    _contributedAmount
                ),
            "ERR_USER_DONT_HAVE_ENOUGH_TOKEN"
        );

        uint256 lockToken = safeDiv(
            safeAdd(
                walletDayWiseContribution[auctionDay][_from],
                _contributedAmount
            ),
            _mainTokenPrice
        );

        IToken(mainTokenAddress).lockToken(_from, lockToken, now);
    }

    function fundAdded(
        address _token,
        uint256 _amount,
        uint256 _decimal,
        address _from,
        uint256 currentMarketPrice
    ) internal {
        require(auctionSoldOut == false, "ERR_AUCTION_SOLD_OUT");

        uint256 _currencyPrices = ICurrencyPrices(currencyPricesAddress)
            .getCurrencyPrice(_token);

        uint256 _contributedAmount = safeDiv(
            safeMul(_amount, _currencyPrices),
            safeExponent(10, _decimal)
        );

        if (mainTokencheckOn) {
            mainTokenCheck(_from, _contributedAmount);
        }

        // allow five percent more for buffer
        // Allow five percent more because of volatility in ether price
        if (
            safeAdd(todayContribution, _contributedAmount) >=
            allowedMaxContribution
        ) {
            require(
                safeDiv(safeMul(allowedMaxContribution, bufferLimit), 100) >=
                    safeAdd(todayContribution, _contributedAmount),
                "ERR_CONTRIBUTION_LIMIT_REACH"
            );

            auctionSoldOut = true;
        }

        todayContribution = safeAdd(todayContribution, _contributedAmount);

        walletDayWiseContribution[auctionDay][_from] = safeAdd(
            walletDayWiseContribution[auctionDay][_from],
            _contributedAmount
        );

        userTotalFund[_from] = safeAdd(
            userTotalFund[_from],
            _contributedAmount
        );

        dayWiseContribution[auctionDay] = safeAdd(
            dayWiseContribution[auctionDay],
            _contributedAmount
        );

        address contributor;
        uint256 topContributior;


            uint256 contributionByUser
         = walletDayWiseContribution[auctionDay][_from];

        bool replaced = false;
        address replaceWith;

        for (uint256 x = 1; x <= 5; x++) {
            contributor = topFiveContributior[auctionDay][x];
            topContributior = walletDayWiseContribution[auctionDay][contributor];
            if (contributionByUser >= topContributior && replaced == false) {
                topFiveContributior[auctionDay][x] = _from;
                topContributiorIndex[auctionDay][_from] = x;
                replaceWith = contributor;
                replaced = true;
            } else if (replaced && replaceWith != _from) {
                topFiveContributior[auctionDay][x] = replaceWith;
                topContributiorIndex[auctionDay][replaceWith] = x;
                replaceWith = contributor;
            }
        }

        emit FundAdded(
            auctionDay,
            todayContribution,
            _from,
            _token,
            _amount,
            _contributedAmount,
            currentMarketPrice
        );
    }

    function _contributeWithEther(uint256 _value, address _from)
        internal
        returns (bool)
    {
        (
            uint256 downSideAmount,
            uint256 fundWalletamount,
            uint256 reserveAmount
        ) = calcuateAuctionFundDistrubution(
            _value,
            dayWiseDownSideProtectionRatio[auctionDay],
            fundWalletRatio
        );

        IAuctionProtection(auctionProtectionAddress).lockEther.value(
            downSideAmount
        )(_from);

        uint256 currentMarketPrice = IAuctionLiquadity(liquadityAddress)
            .contributeWithEther
            .value(reserveAmount)();

        companyFundWalletAddress.transfer(fundWalletamount);

        fundAdded(address(0), _value, 18, _from, currentMarketPrice);
    }

    function _contributeWithToken(
        IERC20Token _token,
        uint256 _value,
        address _from
    ) internal returns (bool) {
        ensureTransferFrom(_token, _from, address(this), _value);

        (
            uint256 downSideAmount,
            uint256 fundWalletamount,
            uint256 reserveAmount
        ) = calcuateAuctionFundDistrubution(
            _value,
            dayWiseDownSideProtectionRatio[auctionDay],
            fundWalletRatio
        );

        approveTransferFrom(_token, auctionProtectionAddress, downSideAmount);

        IAuctionProtection(auctionProtectionAddress).lockTokens(
            _token,
            address(this),
            _from,
            downSideAmount
        );

        approveTransferFrom(_token, liquadityAddress, reserveAmount);

        uint256 currentMarketPrice = IAuctionLiquadity(liquadityAddress)
            .contributeWithToken(_token, address(this), reserveAmount);

        ensureTransferFrom(
            _token,
            address(this),
            companyFundWalletAddress,
            fundWalletamount
        );

        fundAdded(address(_token), _value, 18, _from, currentMarketPrice);
    }

    function contributeWithEther() external payable returns (bool) {
        require(_checkContribution(msg.sender));
        return _contributeWithEther(msg.value, msg.sender);
    }

    function contributeWithToken(IERC20Token _token, uint256 _value)
        external
        returns (bool)
    {
        require(_checkContribution(msg.sender));
        return _contributeWithToken(_token, _value, msg.sender);
    }
}


contract Auction is AuctionFundCollector {
    uint256 public MIN_AUCTION_END_TIME = 0; //epoch

    uint256 public LAST_AUCTION_START = 0;

    uint256 public INTERVAL = 0;

    function changeTimings(uint256 _flag, uint256 _time)
        external
        onlyAuthorized()
        returns (bool)
    {
        if (_flag == 1) MIN_AUCTION_END_TIME = _time;
        else if (_flag == 2) LAST_AUCTION_START == _time;
        else if (_flag == 3) INTERVAL == _time;
        return true;
    }

    constructor(
        uint256 _startTime,
        uint256 _minAuctionTime,
        uint256 _interval,
        address _systemAddress,
        address _multisigAddress,
        address _registeryAddress
    )
        public
        AuctionFundCollector(
            _systemAddress,
            _multisigAddress,
            _registeryAddress
        )
    {
        LAST_AUCTION_START = _startTime;
        MIN_AUCTION_END_TIME = _minAuctionTime;
        INTERVAL = _interval;
    }

    event AuctionEnded(
        uint256 indexed _auctionDayId,
        uint256 _todaySupply,
        uint256 _yesterdaySupply,
        uint256 _todayContribution,
        uint256 _yesterdayContribution,
        uint256 _totalContribution,
        uint256 _maxContributionAllowed,
        uint256 _tokenPrice,
        uint256 _tokenMarketPrice
    );

    event FundDeposited(address _token, address indexed _from, uint256 _amount);

    event TokenDistrubuted(
        address indexed _whom,
        uint256 indexed dayId,
        uint256 _totalToken,
        uint256 lockedToken,
        uint256 _userToken
    );

    function getAuctionDetails()
        external
        view
        returns (
            uint256 _todaySupply,
            uint256 _yesterdaySupply,
            uint256 _todayContribution,
            uint256 _yesterdayContribution,
            uint256 _totalContribution,
            uint256 _maxContributionAllowed,
            uint256 _marketPrice
        )
    {
        uint256 _mainTokenPrice = ICurrencyPrices(currencyPricesAddress)
            .getCurrencyPrice(mainTokenAddress);

        return (
            todaySupply,
            yesterdaySupply,
            todayContribution,
            yesterdayContribution,
            safeAdd(totalContribution, todayContribution),
            allowedMaxContribution,
            _mainTokenPrice
        );
    }

    function auctionEnd() external onlySystem() returns (bool) {
        require(
            now >= safeAdd(LAST_AUCTION_START, MIN_AUCTION_END_TIME),
            "ERR_MIN_TIME_IS_NOT_OVER"
        );

        uint256 _mainTokenPrice = ICurrencyPrices(currencyPricesAddress)
            .getCurrencyPrice(mainTokenAddress);

        if (todayContribution == 0) {
            uint256 _ethPrice = ICurrencyPrices(currencyPricesAddress)
                .getCurrencyPrice(address(0));

            uint256 mainReserveAmount = IAuctionLiquadity(liquadityAddress)
                .contributeTowardMainReserve();

            uint256 mainReserveAmountUsd = safeDiv(
                safeMul(mainReserveAmount, _ethPrice),
                DECIMAL_NOMINATOR
            );

            dayWiseContribution[auctionDay] = mainReserveAmountUsd;

            todayContribution = mainReserveAmountUsd;

            walletDayWiseContribution[auctionDay][vaultAddress] = mainReserveAmountUsd;

            _mainTokenPrice = ICurrencyPrices(currencyPricesAddress)
                .getCurrencyPrice(mainTokenAddress);

            emit FundAdded(
                auctionDay,
                todayContribution,
                vaultAddress,
                address(0),
                mainReserveAmount,
                mainReserveAmountUsd,
                _mainTokenPrice
            );
        }

        uint256 bonusSupply = 0;

        allowedMaxContribution = safeDiv(
            safeMul(todayContribution, maxContributionAllowed),
            100
        );

        if (todayContribution > yesterdayContribution) {
            uint256 _groupBonusRatio = safeMul(
                safeDiv(
                    safeMul(todayContribution, DECIMAL_NOMINATOR),
                    yesterdayContribution
                ),
                groupBonusRatio
            );

            bonusSupply = safeSub(
                safeDiv(
                    safeMul(todaySupply, _groupBonusRatio),
                    DECIMAL_NOMINATOR
                ),
                todaySupply
            );
        }

        uint256 _avgDays = 10;
        uint256 _avgInvestment = 0;

        if (auctionDay < 11) {
            _avgDays = auctionDay;
        }

        for (uint32 tempX = 1; tempX <= _avgDays; tempX++) {
            _avgInvestment = safeAdd(
                _avgInvestment,
                dayWiseContribution[safeSub(auctionDay, tempX)]
            );
        }

        _avgInvestment = safeDiv(
            safeMul(safeDiv(_avgInvestment, _avgDays), maxContributionAllowed),
            100
        );

        if (_avgInvestment > allowedMaxContribution) {
            allowedMaxContribution = _avgInvestment;
        }

        dayWiseSupplyCore[auctionDay] = todaySupply;
        dayWiseSupplyBonus[auctionDay] = bonusSupply;
        dayWiseSupply[auctionDay] = safeAdd(todaySupply, bonusSupply);

        uint256 fee = calculateSupplyPercent(
            dayWiseSupply[auctionDay],
            mangmentFee
        );
        uint256 stackingAmount = calculateSupplyPercent(
            dayWiseSupply[auctionDay],
            stacking
        );

        IToken(mainTokenAddress).mintTokens(safeAdd(fee, stackingAmount));

        ensureTransferFrom(
            IERC20Token(mainTokenAddress),
            address(this),
            companyTokenWalletAddress,
            fee
        );

        approveTransferFrom(
            IERC20Token(mainTokenAddress),
            auctionProtectionAddress,
            stackingAmount
        );

        IAuctionProtection(auctionProtectionAddress).stackFund(stackingAmount);

        uint256 _tokenPrice = safeDiv(
            safeMul(todayContribution, DECIMAL_NOMINATOR),
            dayWiseSupply[auctionDay]
        );

        dayWiseMarketPrice[auctionDay] = _mainTokenPrice;

        todaySupply = safeDiv(
            safeMul(todayContribution, DECIMAL_NOMINATOR),
            _mainTokenPrice
        );

        totalContribution = safeAdd(totalContribution, todayContribution);

        yesterdaySupply = dayWiseSupply[auctionDay];

        yesterdayContribution = todayContribution;

        tokenAuctionEndPrice = _mainTokenPrice;

        auctionDay = safeAdd(auctionDay, 1);

        IAuctionLiquadity(liquadityAddress).auctionEnded();

        dayWiseDownSideProtectionRatio[auctionDay] = downSideProtectionRatio;

        LAST_AUCTION_START = safeSub(LAST_AUCTION_START, INTERVAL);

        auctionSoldOut = false;

        todayContribution = 0;

        emit AuctionEnded(
            auctionDay,
            todaySupply,
            yesterdaySupply,
            todayContribution,
            yesterdayContribution,
            totalContribution,
            allowedMaxContribution,
            _tokenPrice,
            _mainTokenPrice
        );

        return true;
    }

    function disturbuteTokenInternal(uint256 dayId, address _which)
        internal
        returns (bool)
    {
        require(
            returnToken[dayId][_which] == false,
            "ERR_ALREADY_TOKEN_DISTBUTED"
        );


            uint256 dayWiseContributionByWallet
         = walletDayWiseContribution[dayId][_which];

        uint256 dayWiseContribution = dayWiseContribution[dayId];

        (
            uint256 returnAmount,
            uint256 _userAmount
        ) = calcuateAuctionTokenDistrubution(
            dayWiseContributionByWallet,
            dayWiseSupplyCore[dayId],
            dayWiseSupplyBonus[dayId],
            dayWiseContribution,
            dayWiseDownSideProtectionRatio[dayId]
        );

        returnAmount = IIndividualBonus(individualBonusAddress).calucalteBonus(
            topContributiorIndex[dayId][_which],
            returnAmount
        );

        IToken(mainTokenAddress).mintTokens(returnAmount);

        // here we check with last auction bcz user can invest after auction start
        IToken(mainTokenAddress).lockToken(_which, 0, LAST_AUCTION_START);

        ensureTransferFrom(
            IERC20Token(mainTokenAddress),
            address(this),
            _which,
            _userAmount
        );

        approveTransferFrom(
            IERC20Token(mainTokenAddress),
            auctionProtectionAddress,
            safeSub(returnAmount, _userAmount)
        );

        IAuctionProtection(auctionProtectionAddress).depositToken(
            address(this),
            _which,
            safeSub(returnAmount, _userAmount)
        );

        returnToken[dayId][_which] = true;
        emit TokenDistrubuted(
            _which,
            dayId,
            returnAmount,
            safeSub(returnAmount, _userAmount),
            _userAmount
        );
        return true;
    }

    function disturbuteTokens(uint256 dayId, address[] calldata _which)
        external
        onlySystem()
        returns (bool)
    {
        require(dayId < auctionDay, "ERR_AUCTION_DAY");
        for (uint256 tempX = 0; tempX < _which.length; tempX++) {
            if (returnToken[dayId][_which[tempX]] == false)
                disturbuteTokenInternal(dayId, _which[tempX]);
        }
        return true;
    }

    function disturbuteTokens(uint256 dayId) external returns (bool) {
        require(dayId < auctionDay, "ERR_AUCTION_DAY");
        disturbuteTokenInternal(dayId, msg.sender);
    }

    //In case if there is other tokens into contract
    function returnFund(
        IERC20Token _token,
        uint256 _value,
        address payable _which
    ) external onlyOwner() returns (bool) {
        if (address(_token) == address(0)) {
            _which.transfer(_value);
        } else {
            ensureTransferFrom(_token, address(this), _which, _value);
        }
        return true;
    }

    function() external payable {
        emit FundDeposited(address(0), msg.sender, msg.value);
    }
}
