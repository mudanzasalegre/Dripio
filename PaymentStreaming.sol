// SPDX-License-Identifier: Propietario Unico
pragma solidity ^0.8.28;

import "./Treasury.sol";
import "./CompanyRegistry.sol";
import "./RoleManager.sol";

error ProjectNotActive(uint256 projectId);
error NotProjectOwner(address caller, uint256 projectId);
error StreamNotActive(uint256 streamId);
error NotStreamRecipient(address caller, uint256 streamId);
error InvalidTimeRange(uint256 startTime, uint256 endTime);
error ZeroTotalAmount();
error EmployeeNotActive(address employee, uint256 projectId);
error NothingToWithdraw(uint256 streamId);
error StreamAlreadyInactive(uint256 streamId);
error InsufficientProjectFunds(uint256 required, uint256 available);
error CannotReduceBelowWithdrawn();

contract PaymentStreaming {
    address public constant ETHER = address(0);

    struct Stream {
        uint256 streamId;
        uint256 companyId;
        uint256 projectId;
        address token;
        address recipient;
        uint256 totalAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 withdrawn;
        bool isBonus;
        bool isActive;
        bool isPaused;
    }

    struct CreateStreamInput {
        uint256 companyId;
        uint256 projectId;
        address token;
        address recipient;
        uint256 totalAmount;
        uint256 startTime;
        uint256 endTime;
        bool isBonus;
    }

    struct BatchStreamInput {
        uint256 companyId;
        uint256 projectId;
        address token;
        uint256 totalAmountPerEmployee;
        uint256 startTime;
        uint256 endTime;
        bool isBonus;
        address[] recipients;
    }

    RoleManager public roleManager;
    Treasury public treasury;
    CompanyRegistry public registry;
    uint256 public indemnizationRate = 5000;
    uint256 public platformFeeRate = 1000;
    mapping(uint256 => Stream) public streams;
    uint256 public nextStreamId;

    event StreamCreated(
        uint256 indexed streamId,
        uint256 indexed projectId,
        address indexed recipient,
        uint256 totalAmount,
        bool isBonus
    );
    event BatchStreamCreated(uint256[] streamIds);
    event StreamPaused(uint256 indexed streamId);
    event StreamResumed(uint256 indexed streamId);
    event StreamUpdated(
        uint256 indexed streamId,
        uint256 oldTotalAmount,
        uint256 newTotalAmount,
        uint256 oldStartTime,
        uint256 newStartTime,
        uint256 oldEndTime,
        uint256 newEndTime
    );
    event Withdraw(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );
    event StreamCancelled(
        uint256 indexed streamId,
        uint256 indemnity,
        uint256 refundToCompany
    );

    constructor(address _roleManager, address _registry, address _treasury) {
        roleManager = RoleManager(_roleManager);
        registry = CompanyRegistry(_registry);
        treasury = Treasury(_treasury);
    }

    modifier onlyProjectOwner(uint256 projectId) {
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        address owner = registry.getCompanyOwner(companyId);
        if (msg.sender != owner) revert NotProjectOwner(msg.sender, projectId);
        _;
    }

    modifier onlyRecipient(uint256 streamId) {
        Stream memory s = streams[streamId];
        if (!s.isActive) revert StreamNotActive(streamId);
        if (msg.sender != s.recipient) revert NotStreamRecipient(msg.sender, streamId);
        _;
    }

    function createStream(CreateStreamInput memory inputData)
        external
        returns (uint256 streamId)
    {
        _checkRolesForCreation(inputData.projectId);
        _validateStreamCreation(inputData);
        streamId = _createStream(inputData);
        _chargePlatformFee(inputData.companyId, inputData.projectId, inputData.token, inputData.totalAmount);
    }

    function _checkRolesForCreation(uint256 projectId) internal view {
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        address owner = registry.getCompanyOwner(companyId);
        bool isOwner = (msg.sender == owner);
        bool isLocalAdmin = roleManager.isProjectAdminForCompany(companyId, msg.sender);
        bool isGlobalAdmin = roleManager.hasRoleCustom(roleManager.PROJECT_ADMIN_ROLE(), msg.sender)
            || roleManager.hasRoleCustom(roleManager.PAYMENT_ADMIN_ROLE(), msg.sender);
        if (!isOwner && !isLocalAdmin && !isGlobalAdmin) revert NotProjectOwner(msg.sender, projectId);
    }

    function _validateStreamCreation(CreateStreamInput memory inputData) internal view {
        _checkProjectAndEmployee(inputData.projectId, inputData.recipient);
        if (inputData.endTime <= inputData.startTime) revert InvalidTimeRange(inputData.startTime, inputData.endTime);
        if (inputData.totalAmount == 0) revert ZeroTotalAmount();
        uint256 available = treasury.getBalance(inputData.companyId, inputData.projectId, inputData.token);
        uint256 fee = (inputData.totalAmount * platformFeeRate) / 100000;
        uint256 required = inputData.totalAmount + fee;
        if (available < required) revert InsufficientProjectFunds(required, available);
    }

    function _createStream(CreateStreamInput memory inputData) internal returns (uint256) {
        uint256 streamId = nextStreamId++;
        streams[streamId] = Stream({
            streamId: streamId,
            companyId: inputData.companyId,
            projectId: inputData.projectId,
            token: inputData.token,
            recipient: inputData.recipient,
            totalAmount: inputData.totalAmount,
            startTime: inputData.startTime,
            endTime: inputData.endTime,
            withdrawn: 0,
            isBonus: inputData.isBonus,
            isActive: true,
            isPaused: false
        });
        emit StreamCreated(streamId, inputData.projectId, inputData.recipient, inputData.totalAmount, inputData.isBonus);
        return streamId;
    }

    function _chargePlatformFee(uint256 companyId, uint256 projectId, address token, uint256 totalAmount) internal {
        uint256 fee = (totalAmount * platformFeeRate) / 100000;
        if (fee > 0) {
            treasury.withdrawFunds(companyId, projectId, token, fee, address(this));
        }
    }

    function createStreamsBatch(BatchStreamInput memory b) external returns (uint256[] memory streamIds) {
        _checkRolesForCreation(b.projectId);
        if (b.endTime <= b.startTime) revert InvalidTimeRange(b.startTime, b.endTime);
        if (b.totalAmountPerEmployee == 0) revert ZeroTotalAmount();
        streamIds = _createStreamsBatchInternal(b);
    }

    function _createStreamsBatchInternal(BatchStreamInput memory b) internal returns (uint256[] memory streamIds) {
        uint256 totalAmount = b.totalAmountPerEmployee * b.recipients.length;
        uint256 fee = (totalAmount * platformFeeRate) / 100000;
        uint256 required = totalAmount + fee;
        uint256 available = treasury.getBalance(b.companyId, b.projectId, b.token);
        if (available < required) revert InsufficientProjectFunds(required, available);
        if (fee > 0) {
            treasury.withdrawFunds(b.companyId, b.projectId, b.token, fee, address(this));
        }
        streamIds = new uint256[](b.recipients.length);
        for (uint256 i = 0; i < b.recipients.length; i++) {
            _checkProjectAndEmployee(b.projectId, b.recipients[i]);
            uint256 sId = nextStreamId++;
            streams[sId] = Stream({
                streamId: sId,
                companyId: b.companyId,
                projectId: b.projectId,
                token: b.token,
                recipient: b.recipients[i],
                totalAmount: b.totalAmountPerEmployee,
                startTime: b.startTime,
                endTime: b.endTime,
                withdrawn: 0,
                isBonus: b.isBonus,
                isActive: true,
                isPaused: false
            });
            emit StreamCreated(sId, b.projectId, b.recipients[i], b.totalAmountPerEmployee, b.isBonus);
            streamIds[i] = sId;
        }
        emit BatchStreamCreated(streamIds);
    }

    function pauseStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        _checkRolesForUpdate(s.projectId);
        if (!s.isActive) revert StreamNotActive(streamId);
        s.isPaused = true;
        emit StreamPaused(streamId);
    }

    function resumeStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        _checkRolesForUpdate(s.projectId);
        if (!s.isActive) revert StreamNotActive(streamId);
        s.isPaused = false;
        emit StreamResumed(streamId);
    }

    function updateStream(uint256 streamId, uint256 newTotalAmount, uint256 newStartTime, uint256 newEndTime) external {
        Stream storage s = streams[streamId];
        _checkRolesForUpdate(s.projectId);
        if (!s.isActive) revert StreamNotActive(streamId);
        if (newEndTime <= newStartTime) revert InvalidTimeRange(newStartTime, newEndTime);
        if (newTotalAmount < s.withdrawn) revert CannotReduceBelowWithdrawn();
        uint256 oldStart = s.startTime;
        uint256 oldEnd = s.endTime;
        uint256 oldTotal = s.totalAmount;
        s.totalAmount = newTotalAmount;
        s.startTime = newStartTime;
        s.endTime = newEndTime;
        emit StreamUpdated(streamId, oldTotal, newTotalAmount, oldStart, newStartTime, oldEnd, newEndTime);
    }

    function balanceOf(uint256 streamId) public view returns (uint256) {
        Stream memory s = streams[streamId];
        if (!s.isActive) return 0;
        if (s.isPaused) {}
        if (block.timestamp < s.startTime) return 0;
        uint256 elapsed = block.timestamp < s.endTime
            ? (block.timestamp - s.startTime)
            : (s.endTime - s.startTime);
        uint256 duration = s.endTime - s.startTime;
        if (duration == 0) return 0;
        uint256 earnedSoFar = (s.totalAmount * elapsed) / duration;
        if (earnedSoFar <= s.withdrawn) return 0;
        return earnedSoFar - s.withdrawn;
    }

    function withdraw(uint256 streamId) external onlyRecipient(streamId) {
        Stream storage s = streams[streamId];
        if (!s.isActive) revert StreamNotActive(streamId);
        if (s.isPaused) revert("Stream is paused");
        uint256 available = balanceOf(streamId);
        if (available == 0) revert NothingToWithdraw(streamId);
        s.withdrawn += available;
        treasury.withdrawFunds(s.companyId, s.projectId, s.token, available, msg.sender);
        emit Withdraw(streamId, msg.sender, available);
    }

    function cancelStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        _checkRolesForUpdate(s.projectId);
        if (!s.isActive) revert StreamAlreadyInactive(streamId);
        s.isActive = false;
        uint256 totalLeft = s.totalAmount - s.withdrawn;
        uint256 indemnity = (totalLeft * indemnizationRate) / 100000;
        if (indemnity > 0) {
            treasury.withdrawFunds(s.companyId, s.projectId, s.token, indemnity, s.recipient);
        }
        uint256 finalRefund = 0;
        if (totalLeft > indemnity) {
            finalRefund = totalLeft - indemnity;
        }
        emit StreamCancelled(streamId, indemnity, finalRefund);
    }

    function _checkProjectAndEmployee(uint256 projectId, address wallet) internal view {
        (, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        bool employeeActive = registry.isEmployeeActive(projectId, wallet);
        if (!employeeActive) revert EmployeeNotActive(wallet, projectId);
    }

    function _checkOwnership(uint256 projectId) internal view {
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        address owner = registry.getCompanyOwner(companyId);
        if (msg.sender != owner) revert NotProjectOwner(msg.sender, projectId);
    }

    function _checkRolesForUpdate(uint256 projectId) internal view {
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        address owner = registry.getCompanyOwner(companyId);
        bool isOwner = (msg.sender == owner);
        bool isLocalAdmin = roleManager.isProjectAdminForCompany(companyId, msg.sender);
        bool isGlobalAdminProject = roleManager.hasRoleCustom(roleManager.PROJECT_ADMIN_ROLE(), msg.sender);
        bool isGlobalAdminPayment = roleManager.hasRoleCustom(roleManager.PAYMENT_ADMIN_ROLE(), msg.sender);
        bool hasAccess = (isOwner || isLocalAdmin || isGlobalAdminProject || isGlobalAdminPayment);
        if (!hasAccess) revert NotProjectOwner(msg.sender, projectId);
    }
}
