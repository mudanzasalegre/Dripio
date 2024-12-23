// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CompanyRegistry
 * @dev Registra empresas, proyectos y empleados, y gestiona roles básicos.
 */
contract CompanyRegistry {
    // -- Custom Errors -- //
    error CompanyAlreadyExists(uint256 companyId);
    error CompanyDoesNotExist(uint256 companyId);
    error NotCompanyOwner(address caller, uint256 companyId);
    error ProjectAlreadyExists(uint256 projectId);
    error InvalidDates(uint256 startDate, uint256 endDate);
    error InvalidProject(uint256 projectId);
    error NotProjectOwner(address caller, uint256 projectId);
    error EmployeeAlreadyActive(address employeeWallet, uint256 projectId);
    error EmployeeNotActive(address employeeWallet, uint256 projectId);

    // -- Data Structures -- //
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

    // -- Storage -- //

    // companyId -> Company
    mapping(uint256 => Company) public companies;

    // projectId -> Project
    mapping(uint256 => Project) public projects;

    // projectId -> (employeeWallet -> Employee)
    mapping(uint256 => mapping(address => Employee)) public employees;

    // -- Events -- //
    event CompanyCreated(uint256 indexed companyId, address indexed owner);
    event ProjectCreated(
        uint256 indexed projectId,
        uint256 indexed companyId,
        uint256 startDate,
        uint256 endDate
    );
    event EmployeeAdded(
        uint256 indexed projectId,
        address indexed employeeWallet,
        bool hasBonus
    );
    event EmployeeRemoved(
        uint256 indexed projectId,
        address indexed employeeWallet
    );

    // -- Modifiers -- //

    /**
     * @dev Verifica que la compañía exista y que el msg.sender sea su propietario.
     */
    modifier onlyCompanyOwner(uint256 companyId) {
        if (!companies[companyId].exists) {
            revert CompanyDoesNotExist(companyId);
        }
        if (msg.sender != companies[companyId].owner) {
            revert NotCompanyOwner(msg.sender, companyId);
        }
        _;
    }

    /**
     * @dev Verifica que el proyecto sea válido y que el msg.sender sea el propietario de la compañía correspondiente.
     */
    modifier onlyProjectOwner(uint256 projectId) {
        Project memory p = projects[projectId];
        if (!p.isActive) {
            revert InvalidProject(projectId);
        }
        if (!companies[p.companyId].exists) {
            revert CompanyDoesNotExist(p.companyId);
        }
        if (msg.sender != companies[p.companyId].owner) {
            revert NotProjectOwner(msg.sender, projectId);
        }
        _;
    }

    // -- Funciones Principales -- //

    /**
     * @notice Crea una nueva compañía con un ID único.
     * @param companyId ID con el que se registrará la compañía.
     */
    function createCompany(uint256 companyId) external {
        if (companies[companyId].exists) {
            revert CompanyAlreadyExists(companyId);
        }
        companies[companyId] = Company({
            owner: msg.sender,
            exists: true
        });

        emit CompanyCreated(companyId, msg.sender);
    }

    /**
     * @notice Crea un nuevo proyecto asociado a una compañía existente.
     * @param projectId  ID único para el proyecto.
     * @param companyId  ID de la compañía a la que pertenece el proyecto.
     * @param startDate  Timestamp de inicio del proyecto.
     * @param endDate    Timestamp de finalización del proyecto.
     */
    function createProject(
        uint256 projectId,
        uint256 companyId,
        uint256 startDate,
        uint256 endDate
    )
        external
        onlyCompanyOwner(companyId)
    {
        if (projects[projectId].isActive) {
            revert ProjectAlreadyExists(projectId);
        }
        if (startDate >= endDate) {
            revert InvalidDates(startDate, endDate);
        }

        projects[projectId] = Project({
            companyId: companyId,
            startDate: startDate,
            endDate: endDate,
            isActive: true
        });

        emit ProjectCreated(projectId, companyId, startDate, endDate);
    }

    /**
     * @notice Añade un nuevo empleado a un proyecto.
     * @param projectId  ID del proyecto al que se añade el empleado.
     * @param wallet     Dirección del empleado (billetera).
     * @param hasBonus   Indica si el empleado tendrá bonus.
     */
    function addEmployee(
        uint256 projectId,
        address wallet,
        bool hasBonus
    )
        external
        onlyProjectOwner(projectId)
    {
        if (employees[projectId][wallet].isActive) {
            revert EmployeeAlreadyActive(wallet, projectId);
        }

        employees[projectId][wallet] = Employee({
            wallet: wallet,
            hasBonus: hasBonus,
            isActive: true
        });

        emit EmployeeAdded(projectId, wallet, hasBonus);
    }

    /**
     * @notice Desactiva (elimina) un empleado de un proyecto.
     * @param projectId   ID del proyecto.
     * @param wallet      Dirección del empleado a desactivar.
     */
    function removeEmployee(uint256 projectId, address wallet)
        external
        onlyProjectOwner(projectId)
    {
        if (!employees[projectId][wallet].isActive) {
            revert EmployeeNotActive(wallet, projectId);
        }
        employees[projectId][wallet].isActive = false;

        emit EmployeeRemoved(projectId, wallet);
    }

    // -- Helpers / Getters -- //

    /**
     * @notice Consulta si un empleado específico está activo en un proyecto.
     * @param projectId  ID del proyecto.
     * @param wallet     Dirección del empleado.
     * @return bool      Indica si el empleado está activo.
     */
    function isEmployeeActive(uint256 projectId, address wallet)
        external
        view
        returns (bool)
    {
        return employees[projectId][wallet].isActive;
    }

    /**
     * @notice Retorna la información de un proyecto.
     * @param projectId  ID del proyecto.
     * @return companyId ID de la compañía que creó el proyecto.
     * @return startDate Timestamp de inicio.
     * @return endDate   Timestamp de fin.
     * @return isActive  Indica si el proyecto está activo.
     */
    function getProjectInfo(uint256 projectId)
        external
        view
        returns (
            uint256 companyId,
            uint256 startDate,
            uint256 endDate,
            bool isActive
        )
    {
        Project memory p = projects[projectId];
        return (p.companyId, p.startDate, p.endDate, p.isActive);
    }

    /**
     * @notice Obtiene la dirección del propietario de una compañía.
     * @param companyId ID de la compañía.
     * @return Dirección que es propietaria de la compañía.
     */
    function getCompanyOwner(uint256 companyId)
        external
        view
        returns (address)
    {
        return companies[companyId].owner;
    }
}
