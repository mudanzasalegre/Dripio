// SPDX-License-Identifier: Propietario Unico
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./RoleManager.sol";

contract CompanyRegistry is AccessControl, ReentrancyGuard {
    RoleManager public roleManager;
    uint256 public constant CREATE_COMPANY_FEE = 0.01 ether;
    address public feeCollector;

    error CompanyAlreadyExists(uint256 companyId);
    error CompanyDoesNotExist(uint256 companyId);
    error ProjectAlreadyExists(uint256 projectId);
    error InvalidDates(uint256 startDate, uint256 endDate);
    error InvalidProject(uint256 projectId);
    error EmployeeAlreadyActive(address employeeWallet, uint256 projectId);
    error EmployeeNotActive(address employeeWallet, uint256 projectId);
    error IncorrectFee(uint256 sent, uint256 required);
    error NotOwnerNorProjAdmin(address caller, uint256 companyId);

    struct Company {
        address owner;
        bool exists;
    }

    struct Project {
        uint256 companyId;
        uint256 startDate;
        uint256 endDate;
        bool isActive;
    }

    struct Employee {
        address wallet;
        bool hasBonus;
        bool isActive;
    }

    mapping(uint256 => Company) public companies;
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(address => Employee)) public employees;

    event CompanyCreated(uint256 indexed companyId, address indexed owner);
    event ProjectCreated(uint256 indexed projectId, uint256 indexed companyId, uint256 startDate, uint256 endDate);
    event EmployeeAdded(uint256 indexed projectId, address indexed employeeWallet, bool hasBonus);
    event EmployeeRemoved(uint256 indexed projectId, address indexed employeeWallet);

    constructor(address _feeCollector, address _roleManager) {
        feeCollector = _feeCollector;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        roleManager = RoleManager(_roleManager);
    }

    function createCompany(uint256 companyId) external payable nonReentrant {
        if (msg.value != CREATE_COMPANY_FEE) {
            revert IncorrectFee(msg.value, CREATE_COMPANY_FEE);
        }
        if (companies[companyId].exists) {
            revert CompanyAlreadyExists(companyId);
        }
        companies[companyId] = Company({owner: msg.sender, exists: true});
        roleManager.assignRole(msg.sender, roleManager.COMPANY_OWNER_ROLE());
        emit CompanyCreated(companyId, msg.sender);
        if (feeCollector != address(0)) {
            (bool success, ) = feeCollector.call{value: msg.value}("");
            require(success, "Fee transfer failed");
        }
    }

    function createProject(uint256 projectId, uint256 companyId, uint256 startDate, uint256 endDate) external {
        if (!companies[companyId].exists) {
            revert CompanyDoesNotExist(companyId);
        }
        if (projects[projectId].isActive) {
            revert ProjectAlreadyExists(projectId);
        }
        if (startDate >= endDate) {
            revert InvalidDates(startDate, endDate);
        }
        bool isOwner = (msg.sender == companies[companyId].owner);
        bool isLocalAdmin = roleManager.isProjectAdminForCompany(companyId, msg.sender);
        bool isGlobalAdmin = _hasGlobalProjectAdminRole(msg.sender);
        if (!isOwner && !isLocalAdmin && !isGlobalAdmin) {
            revert NotOwnerNorProjAdmin(msg.sender, companyId);
        }
        projects[projectId] = Project({companyId: companyId, startDate: startDate, endDate: endDate, isActive: true});
        emit ProjectCreated(projectId, companyId, startDate, endDate);
    }

    function addEmployee(uint256 projectId, address wallet, bool hasBonus) external {
        Project memory p = projects[projectId];
        if (!p.isActive) {
            revert InvalidProject(projectId);
        }
        if (!companies[p.companyId].exists) {
            revert CompanyDoesNotExist(p.companyId);
        }
        if (employees[projectId][wallet].isActive) {
            revert EmployeeAlreadyActive(wallet, projectId);
        }
        bool isOwner = (msg.sender == companies[p.companyId].owner);
        bool isLocalAdmin = roleManager.isProjectAdminForCompany(p.companyId, msg.sender);
        bool isGlobalAdmin = _hasGlobalProjectAdminRole(msg.sender);
        if (!isOwner && !isLocalAdmin && !isGlobalAdmin) {
            revert NotOwnerNorProjAdmin(msg.sender, p.companyId);
        }
        employees[projectId][wallet] = Employee({wallet: wallet, hasBonus: hasBonus, isActive: true});
        emit EmployeeAdded(projectId, wallet, hasBonus);
    }

    function removeEmployee(uint256 projectId, address wallet) external {
        Project memory p = projects[projectId];
        if (!p.isActive) {
            revert InvalidProject(projectId);
        }
        if (!companies[p.companyId].exists) {
            revert CompanyDoesNotExist(p.companyId);
        }
        if (!employees[projectId][wallet].isActive) {
            revert EmployeeNotActive(wallet, projectId);
        }
        bool isOwner = (msg.sender == companies[p.companyId].owner);
        bool isLocalAdmin = roleManager.isProjectAdminForCompany(p.companyId, msg.sender);
        bool isGlobalAdmin = _hasGlobalProjectAdminRole(msg.sender);
        if (!isOwner && !isLocalAdmin && !isGlobalAdmin) {
            revert NotOwnerNorProjAdmin(msg.sender, p.companyId);
        }
        employees[projectId][wallet].isActive = false;
        emit EmployeeRemoved(projectId, wallet);
    }

    function isEmployeeActive(uint256 projectId, address wallet) external view returns (bool) {
        return employees[projectId][wallet].isActive;
    }

    function getProjectInfo(uint256 projectId) external view returns (uint256 companyId, uint256 startDate, uint256 endDate, bool isActive) {
        Project memory p = projects[projectId];
        return (p.companyId, p.startDate, p.endDate, p.isActive);
    }

    function getCompanyOwner(uint256 companyId) external view returns (address) {
        return companies[companyId].owner;
    }

    function _hasGlobalProjectAdminRole(address user) internal view returns (bool) {
        return roleManager.hasRoleCustom(roleManager.PROJECT_ADMIN_ROLE(), user);
    }

    function setFeeCollector(address newCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeCollector = newCollector;
    }
}
