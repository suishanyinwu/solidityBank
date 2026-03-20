// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./7_IRankingOracle.sol";

contract EtherBank is ReentrancyGuard{
    // ============ 核心配置 ============
    address private immutable owner;
    uint256 public constant DAILY_INTEREST_RATE = 1e25; // 0.1% 
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 private constant RANKING_LENGTH = 3;
    uint256 public constant RAY = 1e27; // 核心精度常量

    // 用户总数据
    struct UserData {
        uint256 scaledBalance; // 缩放余额
    }

    mapping (address => UserData) private userDeposit;
    address[RANKING_LENGTH] private userBalance_Top3;
    address RankingOracle;
    bool oracleEnabled = false; // 是否启用预言机
    uint128 liquidityIndex=uint128(RAY); //全局流动性指数
    uint40 lastUpdateTimestamp;

    event depositEvent(address indexed user, uint256 amount, uint256 scaledBalance);
    event RankingUpdated(address[3] top3Users);
    event withdrawEvent(address indexed user, uint256 amount,uint256 scaledBalance);
    event OwnerWithdrawEvent(address indexed user, uint256 amount);
    event changeOracle(bool state, uint256 timestamp);

    error ZeroDepositAmount(); // 存款金额为0
    error NotContractOwner(); // 非管理员操作
    error InsufficientContractBalance(); // 合约余额不足
    error ZeroWithdrawAmount(); // 提款金额为0
    error NoDepositToWithdraw(); // 无存款可提
    error TransferFailed(); // 转账失败
    error InvalidAddress(); // 无效地址
    error OracleNotSet();
    error OracleCallFailed();
    error ZeroOracleAddress();

    constructor(){
        owner=msg.sender;
        lastUpdateTimestamp=uint40(block.timestamp);
    }

    //管理者权限检查
    modifier onlyOwner{
        if(msg.sender != owner) revert NotContractOwner();
        _;
    }

    receive() external payable nonReentrant {
        deposit(msg.sender);
    }

    
    //存款
    function deposit(address _user) public payable virtual nonReentrant {
        uint256 amount= msg.value;
        if( amount == 0 )revert ZeroDepositAmount();
        if(_user == address(0)) revert InvalidAddress();

        _updateReserveIndex();

        uint256 scaledBalanceToAdd = (amount * RAY) / uint256(liquidityIndex);

        UserData storage user = userDeposit[_user]; 
        user.scaledBalance += scaledBalanceToAdd;

        _updateBalanceRanking(_user); 
        emit depositEvent(_user, msg.value , scaledBalanceToAdd);

    }

    // 用户全额提款
    function withdrawAll() external nonReentrant {
        address userAddr = msg.sender;
        UserData storage user = userDeposit[userAddr];

        if (user.scaledBalance == 0) revert NoDepositToWithdraw();
        
        _updateReserveIndex();
        uint256 totalWithdraw = _rayMul(user.scaledBalance, liquidityIndex);

        if (totalWithdraw > address(this).balance) revert InsufficientContractBalance();
        uint256 scaledBalanceToSub =user.scaledBalance;
        user.scaledBalance=0;

        payable(userAddr).transfer(totalWithdraw);

        _updateBalanceRanking(userAddr);

         emit withdrawEvent(userAddr, totalWithdraw, scaledBalanceToSub);
    }

    //用户部分提款
    function withdraw(uint256 _amount) external nonReentrant {
        address userAddr = msg.sender;
        UserData storage user = userDeposit[userAddr];

        if (user.scaledBalance == 0) revert NoDepositToWithdraw();
        _updateReserveIndex();
        uint256 currentLiquidityIndex = liquidityIndex;
        if ( (user.scaledBalance * currentLiquidityIndex) < _amount) revert NoDepositToWithdraw();
        if (_amount > address(this).balance) revert InsufficientContractBalance();

        uint256 scaledBalanceToSub = (_amount * RAY) / currentLiquidityIndex;
        user.scaledBalance -= scaledBalanceToSub;

        payable(userAddr).transfer(_amount);

        _updateBalanceRanking(userAddr);

         emit withdrawEvent(userAddr, _amount, scaledBalanceToSub);
    }


    //更新全局流动性指数
    function _updateReserveIndex() internal {
        uint40 lastTimestamp = lastUpdateTimestamp;
        uint256 currentLiquidityIndex = liquidityIndex;

        // 如果时间未变化（同一区块多次操作），无需更新
        if (lastUpdateTimestamp == block.timestamp) return;

        uint256 timeDelta = block.timestamp - lastTimestamp;

        uint256 indexDelta = (DAILY_INTEREST_RATE * timeDelta) / SECONDS_PER_DAY;
        indexDelta = RAY + indexDelta;
        currentLiquidityIndex = _rayMul(currentLiquidityIndex, indexDelta);

        liquidityIndex = uint128(currentLiquidityIndex);
        lastUpdateTimestamp = uint40(block.timestamp);

    }

    function updateReserveIndex() external {
        _updateReserveIndex();
    }


    // 管理员提币
    function ownerWithdraw(uint _value) external onlyOwner nonReentrant {
        if(_value > address(this).balance) revert InsufficientContractBalance();
        if(_value==0) revert ZeroWithdrawAmount();

        payable(msg.sender).transfer(_value);
        
        emit OwnerWithdrawEvent(msg.sender, _value);
    }

    // ============ 排行榜更新逻辑 ============
    function _updateBalanceRanking(address _user) internal {
        if (!oracleEnabled) {
            _localUpdateRanking(_user);
            return;
        }

        if (RankingOracle == address(0)) revert OracleNotSet();
        try IRankingOracle(RankingOracle).updateRanking(
            _user,
            userBalance_Top3,
            address(this) 
        ) returns (address[RANKING_LENGTH] memory newTop3) {
            userBalance_Top3 = newTop3;
            emit RankingUpdated(newTop3);
        } catch {
            revert OracleCallFailed();
        }

    }

    // ============ 本地降级逻辑 ============
    // 原排行榜逻辑，兼容禁用预言机的情况
    // 无法完成用户提款的排序，需要预言机完成排序
    function _localUpdateRanking(address _user) internal {
         uint i=1;
        //判断是否为空，是否为一致，插入新的address
        for(;i<=3;i++){
            if(address(0) == userBalance_Top3[i-1] || _user == userBalance_Top3[i-1]) break;
        }
        if(i!=4) userBalance_Top3[i-1]=_user;

        //数组排序
        for(i--;i>=1;i--){
            if(userDeposit[_user].scaledBalance>userDeposit[userBalance_Top3[i-1]].scaledBalance){
                if(i==3){
                    userBalance_Top3[i-1]=_user;
                } else{
                    userBalance_Top3[i]=userBalance_Top3[i-1];
                    userBalance_Top3[i-1]=_user;
                }
            }
        }

        emit RankingUpdated(userBalance_Top3);

    }

    //设置预言机合约地址
    function setRankingOracle(address _oracle) external onlyOwner nonReentrant {
        if(_oracle == address(0)) revert ZeroOracleAddress();
        RankingOracle = _oracle;
    }

    function onOracle() external onlyOwner{
        oracleEnabled = true;
        emit changeOracle(oracleEnabled, block.timestamp);
    }
    
    function offOracle() external onlyOwner{
        oracleEnabled = false;
        emit changeOracle(oracleEnabled, block.timestamp);
    }
    
    //手动更新排行榜数据
    function manUpdateRanking() external{
        if(msg.sender != owner && ( msg.sender != RankingOracle || !oracleEnabled || RankingOracle == address(0))) revert OracleCallFailed();
        _updateBalanceRanking(msg.sender);
    }

    function _rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / RAY;
    }

    // ============ 通用查询函数 ============
    function getBalanceRanking() external view returns(address[3] memory){
        return userBalance_Top3;
    }

    function getUserBalance(address _user) external returns(uint){
        _updateReserveIndex();

        return _rayMul(userDeposit[_user].scaledBalance, liquidityIndex);
    }

    function getAllBalance() external view returns (uint){
        return address(this).balance;
    }



} 