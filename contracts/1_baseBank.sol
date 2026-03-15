// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./7_IRankingOracle.sol";

contract EtherBank is ReentrancyGuard{
    // ============ 核心配置 ============
    address private immutable owner;
    uint256 public constant DAILY_INTEREST_RATE = 100; // 0.1% = 100/100000
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 private constant RANKING_LENGTH = 3;

    // ============ 数据结构：存储每笔存款明细 ============
    // 单笔存款记录
    struct DepositRecord {
        uint256 amount; 
        uint40 timestamp; 
    }

    // 用户总数据
    struct UserData {
        uint256 totalDeposit; // 总存款
        DepositRecord[] records; // 存款明细列表
        bool hasDeposit;
    }

    mapping (address => UserData) private userDeposit;
    address[RANKING_LENGTH] private userBalance_Top3;
    address RankingOracle;
    bool oracleEnabled = false; // 是否启用预言机

    event depositEvent(address indexed user, uint256 amount, uint256 timestamp);
    event RankingUpdated(address[3] top3Users);
    event withdrawEvent(address indexed user, uint256 amount);
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
        if( msg.value == 0 )revert ZeroDepositAmount();
        if(_user == address(0)) revert InvalidAddress();

        UserData storage user = userDeposit[_user]; 
        user.records.push(DepositRecord({
            amount:msg.value,
            timestamp:uint40(block.timestamp)
        }));
        user.totalDeposit += msg.value;
        user.hasDeposit = true;

        _updateBalanceRanking(_user); 
        emit depositEvent(_user, msg.value,block.timestamp);
    }

    // ============ 利息计算：按每笔存款单独计息 ============
    function calculateInterest(address _user) internal view returns (uint256 totalInterest) {
        if (_user == address(0)) revert InvalidAddress();

        UserData memory user = userDeposit[_user];
        if (!user.hasDeposit || user.totalDeposit == 0) return 0;

        unchecked {
            for (uint256 i = 0; i < user.records.length; i++) {
                DepositRecord memory record = user.records[i];
                uint256 times = (block.timestamp - record.timestamp) / SECONDS_PER_DAY;
                if (times == 0) continue;

                totalInterest += (record.amount * DAILY_INTEREST_RATE * times) / 100000;
            }
        }
    }

    // 用户全额提款
    function withdrawAll() external nonReentrant {
        address userAddr = msg.sender;
        UserData storage user = userDeposit[userAddr];

        if (!user.hasDeposit || user.totalDeposit == 0) revert NoDepositToWithdraw();

        uint256 principal = user.totalDeposit;
        uint256 interest = calculateInterest(userAddr);
        uint256 totalWithdraw = principal + interest;

        if (totalWithdraw > address(this).balance) revert InsufficientContractBalance();

        user.totalDeposit = 0;
        delete user.records; 
        user.hasDeposit = false;

        payable(userAddr).transfer(totalWithdraw);
        
        //(bool success, ) = payable(msg.sender).call{value: totalWithdraw}("");
        //if (!success) revert TransferFailed();

        _updateBalanceRanking(userAddr);

         emit withdrawEvent(userAddr, totalWithdraw);
    }

    // 管理员提币
    function ownerWithdraw(uint _value) external onlyOwner nonReentrant {
        if(_value > address(this).balance) revert InsufficientContractBalance();
        if(_value==0) revert ZeroWithdrawAmount();

        payable(msg.sender).transfer(_value);

        //(bool success, ) = payable(msg.sender).call{value: _value}("");
        //if (!success) revert TransferFailed();
        
        emit withdrawEvent(msg.sender, _value);
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
            if(userDeposit[_user].totalDeposit>userDeposit[userBalance_Top3[i-1]].totalDeposit){
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


    // ============ 通用查询函数 ============
    function getBalanceRanking() external view returns(address[3] memory){
        return userBalance_Top3;
    }

    function getUserBalance(address _user) external view returns(uint){
        return userDeposit[_user].totalDeposit;
    }

    function getAllBalance() external view returns (uint){
        return address(this).balance;
    }

    function getUserInterest(address _user) external view returns (uint256) {
        return calculateInterest(_user);
    }



} 