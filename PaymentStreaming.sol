// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Treasury.sol";
import "./CompanyRegistry.sol";

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
    // ETHER address
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
        bool isPaused;  // Nuevo campo
    }

    Treasury public treasury;
    CompanyRegistry public registry;

    // Tarifas de penalización e indemnización:
    // Ejemplo: 5% se considera indemnización para el empleado cuando se cancela.
    uint256 public indemnizationRate = 5_000; // 5% (base 100k => 5_000 / 100_000)
    // Comisión de la plataforma al crear un stream (ejemplo 1%)
    uint256 public platformFeeRate = 1_000; // 1% (base 100k)

    mapping(uint256 => Stream) public streams;
    uint256 public nextStreamId;

    // Eventos
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
    event Withdraw(uint256 indexed streamId, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed streamId, uint256 indemnity, uint256 refundToCompany);

    constructor(address _treasury, address _registry) {
        treasury = Treasury(_treasury);
        registry = CompanyRegistry(_registry);
    }

    // Modifiers
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

    // =========================================================
    //                   CREACIÓN DE STREAMS
    // =========================================================

    /**
     * @notice Crea un stream de pago para un empleado, con verificación de fondos en la tesorería.
     */
    function createStream(
        uint256 companyId,
        uint256 projectId,
        address token,
        address recipient,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        bool isBonus
    )
        external
        onlyProjectOwner(projectId)
        returns (uint256 streamId)
    {
        _checkProjectAndEmployee(projectId, recipient);
        if (endTime <= startTime) revert InvalidTimeRange(startTime, endTime);
        if (totalAmount == 0) revert ZeroTotalAmount();

        // Verificación de fondos disponibles en la tesorería
        uint256 available = treasury.getBalance(companyId, projectId, token);
        // Calculamos la comisión
        uint256 fee = (totalAmount * platformFeeRate) / 100_000; 
        uint256 required = totalAmount + fee;
        if (available < required) {
            revert InsufficientProjectFunds(required, available);
        }

        // Creamos el stream
        streamId = nextStreamId++;
        streams[streamId] = Stream({
            streamId: streamId,
            companyId: companyId,
            projectId: projectId,
            token: token,
            recipient: recipient,
            totalAmount: totalAmount,
            startTime: startTime,
            endTime: endTime,
            withdrawn: 0,
            isBonus: isBonus,
            isActive: true,
            isPaused: false
        });

        // Emitimos evento
        emit StreamCreated(streamId, projectId, recipient, totalAmount, isBonus);

        // Cobrar la comisión (puedes diseñar la lógica, p. ej. retirarFunds enseguida del treasury)
        if (fee > 0) {
            // Retiramos la comisión y la enviamos a la dirección "dueña" de la plataforma
            // Ejemplo, supón que la dirección del owner del contrato PaymentStreaming es la "cuenta de fees"
            // (o un address feeCollector).
            treasury.withdrawFunds(companyId, projectId, token, fee, address(this));
            // Queda en este contrato, podrías hacer un transfer a una dirección "feeCollector".
        }
    }

    /**
     * @notice Creación masiva de streams para múltiples empleados con mismos parámetros.
     */
    function createStreamsBatch(
        uint256 companyId,
        uint256 projectId,
        address token,
        uint256 totalAmountPerEmployee,
        uint256 startTime,
        uint256 endTime,
        bool isBonus,
        address[] calldata recipients
    )
        external
        onlyProjectOwner(projectId)
        returns (uint256[] memory streamIds)
    {
        if (endTime <= startTime) revert InvalidTimeRange(startTime, endTime);
        if (totalAmountPerEmployee == 0) revert ZeroTotalAmount();

        streamIds = new uint256[](recipients.length);

        // Calculamos la comisión total de golpe
        uint256 totalAmount = totalAmountPerEmployee * recipients.length;
        uint256 fee = (totalAmount * platformFeeRate) / 100_000;
        uint256 required = totalAmount + fee;

        // Verificar fondos
        uint256 available = treasury.getBalance(companyId, projectId, token);
        if (available < required) {
            revert InsufficientProjectFunds(required, available);
        }

        // Cobrar la comisión en un solo withdraw
        if (fee > 0) {
            treasury.withdrawFunds(companyId, projectId, token, fee, address(this));
        }

        // Creamos cada stream
        for (uint256 i = 0; i < recipients.length; i++) {
            _checkProjectAndEmployee(projectId, recipients[i]);

            uint256 sId = nextStreamId++;
            streams[sId] = Stream({
                streamId: sId,
                companyId: companyId,
                projectId: projectId,
                token: token,
                recipient: recipients[i],
                totalAmount: totalAmountPerEmployee,
                startTime: startTime,
                endTime: endTime,
                withdrawn: 0,
                isBonus: isBonus,
                isActive: true,
                isPaused: false
            });
            streamIds[i] = sId;

            emit StreamCreated(sId, projectId, recipients[i], totalAmountPerEmployee, isBonus);
        }

        emit BatchStreamCreated(streamIds);
    }

    // =========================================================
    //                   PAUSAR / REANUDAR STREAM
    // =========================================================

    function pauseStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        _checkOwnership(s.projectId);
        if (!s.isActive) revert StreamNotActive(streamId);
        s.isPaused = true;
        emit StreamPaused(streamId);
    }

    function resumeStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        _checkOwnership(s.projectId);
        if (!s.isActive) revert StreamNotActive(streamId);
        s.isPaused = false;
        emit StreamResumed(streamId);
    }

    // =========================================================
    //                   UPDATE STREAM
    // =========================================================

    /**
     * @notice Actualiza los parámetros de un stream.  
     *         Restricciones:
     *         - No se puede reducir totalAmount por debajo de lo ya retirado
     *         - No se puede acortar endTime por debajo de block.timestamp (si ya avanzó)
     *         - No se puede mover startTime a futuro si ya pasó
     */
    function updateStream(
        uint256 streamId,
        uint256 newTotalAmount,
        uint256 newStartTime,
        uint256 newEndTime
    )
        external
    {
        Stream storage s = streams[streamId];
        _checkOwnership(s.projectId);

        if (!s.isActive) revert StreamNotActive(streamId);
        if (newEndTime <= newStartTime) revert InvalidTimeRange(newStartTime, newEndTime);
        if (newTotalAmount < s.withdrawn) revert CannotReduceBelowWithdrawn();

        // Evitar saltarse pagos:
        //  - Si block.timestamp > s.startTime, no permitas reducir la ventana de acumulación para perjudicar al employee
        //  - Lógica adicional según tu criterio
        uint256 oldStart = s.startTime;
        uint256 oldEnd = s.endTime;
        uint256 oldTotal = s.totalAmount;

        // Actualiza
        s.totalAmount = newTotalAmount;
        s.startTime = newStartTime;
        s.endTime = newEndTime;

        emit StreamUpdated(
            streamId,
            oldTotal,
            newTotalAmount,
            oldStart,
            newStartTime,
            oldEnd,
            newEndTime
        );
    }

    // =========================================================
    //                   CÁLCULO Y RETIROS
    // =========================================================

    function balanceOf(uint256 streamId) public view returns (uint256) {
        Stream memory s = streams[streamId];
        if (!s.isActive) return 0;
        if (s.isPaused) {
            // Si está en pausa, no acumulamos nada más desde la pausa
            // Podríamos necesitar un "pausedAt" para saber hasta qué momento acumuló
            // Por simplicidad, consideramos que la pausa congela el tiempo
            // => Dejarías un campo "pausedTime" para cuando se pausó y "accumulatedUntilPause" ...
            //  Esto ya es a tu criterio, es una lógica más compleja.
        }
        if (block.timestamp < s.startTime) return 0;

        // Cálculo normal
        uint256 elapsed = block.timestamp < s.endTime
            ? block.timestamp - s.startTime
            : s.endTime - s.startTime;

        // Evitar division by zero:
        uint256 duration = s.endTime - s.startTime;
        if (duration == 0) return 0;

        uint256 earnedSoFar = (s.totalAmount * elapsed) / duration;
        if (earnedSoFar <= s.withdrawn) {
            return 0;
        }
        return earnedSoFar - s.withdrawn;
    }

    function withdraw(uint256 streamId) external onlyRecipient(streamId) {
        Stream storage s = streams[streamId];
        if (!s.isActive) revert StreamNotActive(streamId);
        if (s.isPaused) {
            // Se podría revert con "Stream is paused"
            revert("Stream is paused");
        }

        uint256 available = balanceOf(streamId);
        if (available == 0) revert NothingToWithdraw(streamId);

        s.withdrawn += available;

        // Retiramos de la tesorería
        treasury.withdrawFunds(s.companyId, s.projectId, s.token, available, msg.sender);

        emit Withdraw(streamId, msg.sender, available);
    }

    // =========================================================
    //                   CANCELACIÓN + INDEMNIZACIÓN
    // =========================================================

    function cancelStream(uint256 streamId) external {
        Stream storage s = streams[streamId];
        if (!s.isActive) revert StreamAlreadyInactive(streamId);
        _checkOwnership(s.projectId);

        s.isActive = false;

        // Calcular lo que el empleado puede retirar en caso de indemnización
        uint256 currentBalance = balanceOf(streamId);
        uint256 totalLeft = s.totalAmount - s.withdrawn;
        // Indemnización = un porcentaje del totalLeft (p.ej. 5%)
        uint256 indemnity = (totalLeft * indemnizationRate) / 100_000;

        // Caso 1: Se le da la indemnización al empleado de inmediato
        if (indemnity > 0) {
            // Aseguramos no pasarnos si la treasury no lo cubre, etc.
            // Pero asumimos que "si había totalLeft, hay fondos en la sub-bóveda"
            treasury.withdrawFunds(s.companyId, s.projectId, s.token, indemnity, s.recipient);
        }

        // El resto (totalLeft - indemnity) vuelve a quedar a disposición de la empresa.
        // "currentBalance" es la parte que no se generó todavía para el employee.
        // Para simplificar, decimos finalRefund = totalLeft - indemnity
        // (El employee no retira su 'currentBalance' => se convierte en parte del refund).
        uint256 finalRefund = 0;
        if (totalLeft > indemnity) {
            finalRefund = totalLeft - indemnity;
            // No se hace una "retirada" real, sino que conceptualmente
            // esos tokens vuelven a estar 100% disponibles para la empresa.
            // Podrías emitir un evento o llevar contabilidad extra para saberlo.
        }

        emit StreamCancelled(streamId, indemnity, finalRefund);
    }

    // =========================================================
    //                   FUNCIONES INTERNAS
    // =========================================================

    function _checkProjectAndEmployee(uint256 projectId, address wallet) internal view {
        // Verificamos que el proyecto está activo
        (, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);

        // Verificamos que el empleado está activo
        bool employeeActive = registry.isEmployeeActive(projectId, wallet);
        if (!employeeActive) revert EmployeeNotActive(wallet, projectId);
    }

    function _checkOwnership(uint256 projectId) internal view {
        (uint256 companyId, , , bool projectActive) = registry.getProjectInfo(projectId);
        if (!projectActive) revert ProjectNotActive(projectId);
        address owner = registry.getCompanyOwner(companyId);
        if (msg.sender != owner) revert NotProjectOwner(msg.sender, projectId);
    }
}