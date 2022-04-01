//SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";

pragma solidity ^0.8.10;

contract NFTStaking is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint16;

    struct User {
        uint256 totalNFTDeposited;
        uint256 lastClaimTime;
        uint256 lastDepositTime;
        uint256 totalClaimed;
    }

    struct Pool {
        uint256 rewardPerNFT; //How much reward token per NFT
        uint16 stakeId; //Id of staking token
        uint16 rewardId; //Id of reward token
        uint256 rewardInterval; //How often reward is calculated
        uint16 lockPeriodInDays; //Lock period for unstaking
        uint256 totalDeposit;
        uint256 totalRewardDistributed;
        uint256 startDate;
        uint256 endDate;
    }

    IERC1155 public nft;

    mapping(uint8 => mapping(address => User)) public users;

    Pool[] public poolInfo;

    event Stake(address indexed addr, uint256 pool, uint256 amount);
    event Claim(address indexed addr, uint256 amount);

    constructor(address _nft) {
        nft = IERC1155(_nft);
    }

    function add(
      uint16 _stakeId,
      uint16 _rewardId,
        uint256 _rewardPerNFT,
        uint256 _rewardInterval,
        uint16 _lockPeriodInDays,
        uint256 _endDate
    ) external onlyOwner {
        poolInfo.push(
            Pool({
                rewardPerNFT: _rewardPerNFT,
                stakeId: _stakeId,
                rewardId: _rewardId,
                rewardInterval: _rewardInterval,
                lockPeriodInDays: _lockPeriodInDays,
                endDate: _endDate,
                startDate: block.timestamp,
                totalDeposit: 0,
                totalRewardDistributed: 0
            })
        );
    }

    function set(
        uint8 _pid,
        uint16 _rewardId,
        uint256 _rewardPerNFT,
        uint256 _rewardInterval,
        uint16 _lockPeriodInDays,
        uint256 _endDate
    ) public onlyOwner {
        Pool storage pool = poolInfo[_pid];

        pool.rewardPerNFT = _rewardPerNFT;
        pool.rewardId = _rewardId;
        pool.rewardInterval = _rewardInterval;
        pool.lockPeriodInDays = _lockPeriodInDays;
        pool.endDate = _endDate;
    }

    function stake(uint8 _pid, uint16 _amount)
        external
        returns (bool)
    {   
        uint16 _id = poolInfo[_pid].stakeId;

        nft.safeTransferFrom(msg.sender, address(this), _id, _amount,"");

        _claim(_pid, msg.sender);

        _stake(_pid, msg.sender,_amount);

        emit Stake(msg.sender, _pid, _amount);

        return true;
    }

    function _stake(uint8 _pid, address _sender, uint256 _amount) internal {
        User storage user = users[_pid][_sender];
        Pool storage pool = poolInfo[_pid];

        uint256 stopDepo = pool.endDate.sub(pool.lockPeriodInDays.mul(1 days));

        require(
            block.timestamp <= stopDepo,
            "Staking is disabled for this pool"
        );

        user.totalNFTDeposited += _amount;
        pool.totalDeposit += _amount;
        user.lastDepositTime = block.timestamp;
    }

    function claimAll(address _addr) public returns (bool) {
        uint256 len = poolInfo.length;
        
        for (uint8 i = 0; i < len; i++) {
            _claim(i, _addr);
        }

        return true;
    }

    function claim(uint8 _pid) public returns (bool) {
        _claim(_pid, msg.sender);

        return true;
    }

    function canUnstake(uint8 _pid, address _addr) public view returns (bool) {
        User memory user = users[_pid][_addr];
        Pool memory pool = poolInfo[_pid];

        return (block.timestamp >=
            user.lastDepositTime.add(pool.lockPeriodInDays.mul(1 days)));
    }

    function unStake(uint8 _pid, uint256 _amount) external returns (bool) {
        User storage user = users[_pid][msg.sender];
        Pool storage pool = poolInfo[_pid];

        require(user.totalNFTDeposited >= _amount, "You don't have enough funds");

        require(
            canUnstake(_pid, msg.sender),
            "Stake still in locked state"
        );

        _claim(_pid, msg.sender);

        pool.totalDeposit -= _amount;
        user.totalNFTDeposited -= _amount;

        nft.safeTransferFrom(address(this), msg.sender, pool.stakeId, _amount,"");

        return true;
    }

    function _claim(uint8 _pid, address _addr) internal {
        User storage user = users[_pid][_addr];

        uint256 amount = payout(_pid, _addr);

        if (amount > 0) {
            safeNFTTransfer(_addr,_pid, amount);

            user.lastClaimTime = block.timestamp;

            user.totalClaimed = user.totalClaimed.add(amount);
        }

        poolInfo[_pid].totalRewardDistributed += amount;

        emit Claim(_addr, amount);
    }

    function payout(uint8 _pid, address _addr)
        public
        view
        returns (uint256 value)
    {
        User storage user = users[_pid][_addr];
        Pool storage pool = poolInfo[_pid];

        uint256 from = user.lastClaimTime > user.lastDepositTime
            ? user.lastClaimTime
            : user.lastDepositTime;
        uint256 to = block.timestamp > pool.endDate
            ? pool.endDate
            : block.timestamp;

        if (from < to) {
            value = value.add(
                user
                    .totalNFTDeposited
                    .mul(to.sub(from))
                    .mul(pool.rewardPerNFT)
                    .div(pool.rewardInterval)
            );
        }

        return value;
    }

    function claimStuckTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    /**
     *
     * @dev safe transfer function, require to have enough token to transfer
     *
     */
    function safeNFTTransfer(address _to, uint16 _pid, uint256 _amount) internal {
        uint16 _id = poolInfo[_pid].rewardId; 
        
        nft.safeTransferFrom(address(this), _to, _id, _amount, "");
    }
}