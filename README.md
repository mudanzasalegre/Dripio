# Dripio: Payment Streaming Ecosystem

Este repositorio contiene **cuatro contratos** principales escritos en Solidity (versión 0.8.x) que conforman un sistema de **Payment Streaming** para empresas, proyectos y empleados. Cada contrato desempeña una función específica, asegurando un flujo de pagos continuo y seguro para los empleados, con la posibilidad de cancelar y pausar streams, manejar indemnizaciones y más.

---

## **Contratos**

1. **RoleManager.sol**  
   - Define roles globales: `COMPANY_OWNER_ROLE`, `PROJECT_ADMIN_ROLE`, `TREASURY_ADMIN_ROLE`, `PAYMENT_ADMIN_ROLE`.  
   - Maneja asignaciones locales por compañía mediante `companyProjectAdmins[companyId][user]`.  
   - Permite que el dueño de compañía o un admin global asigne o revoque estos roles.

2. **CompanyRegistry.sol**  
   - Registra **empresas** con un “dueño nominal” (owner) y una tarifa fija al crearlas.  
   - Administra **proyectos** y **empleados**, verificando que solo el dueño, o roles específicos (admins globales/locales), tengan permiso para dichas operaciones.  
   - Emite eventos para la creación de compañías, proyectos y la gestión de empleados.

3. **Treasury.sol**  
   - Custodia los fondos en sub-bóvedas (companyId, projectId, token).  
   - Soporta Ether (address(0)) y cualquier token ERC20 (mediante `transferFrom` y `transfer`).  
   - Limita el retiro de fondos a usuarios con `TREASURY_ADMIN_ROLE` o a contratos autorizados (por ejemplo, `PaymentStreaming`).  
   - Emite eventos de depósito y retiro.

4. **PaymentStreaming.sol**  
   - Gestiona la **creación, pausa, reanudación, actualización y cancelación** de los streams.  
   - Valida que haya fondos suficientes en la `Treasury` para crear nuevos streams, aplicando una comisión si procede.  
   - Calcula cuánto puede retirar cada empleado (`balanceOf`), permite retiros e indemnizaciones al cancelar.  
   - Emite eventos como `StreamCreated`, `Withdraw` y `StreamCancelled`.

---

## **Resumen de Funcionamiento**

1. **Creación de Compañía**  
   - `CompanyRegistry.createCompany(companyId, ...)` cobra una **tarifa fija** al creador y lo asigna como dueño nominal.  
   - Emite `CompanyCreated`.

2. **Gestión de Proyectos y Empleados**  
   - El dueño nominal o roles autorizados (`PROJECT_ADMIN_ROLE`, admins locales) crean proyectos con `createProject`.  
   - Añaden o retiran empleados mediante `addEmployee` / `removeEmployee`.

3. **Depósito de Fondos**  
   - Se llama a `Treasury.depositFunds(companyId, projectId, token, amount)` o se envía Ether directamente si `token == address(0)`.  
   - Los fondos se guardan en una sub-bóveda única para `(companyId, projectId, token)`.

4. **Creación de Streams**  
   - Con `PaymentStreaming.createStream(...)` o `createStreamsBatch(...)`, el sistema comprueba que haya fondos suficientes en la `Treasury`, descuenta la comisión y crea los registros internos para cada stream.  
   - Emite eventos como `StreamCreated` y `BatchStreamCreated`.

5. **Retiros e Indemnizaciones**  
   - El empleado (recipient) llama a `withdraw(streamId)` para retirar lo que haya acumulado.  
   - Si se cancela el stream (`cancelStream`), se calcula la indemnización y se transfiere al empleado. El resto queda “disponible” para la empresa.

6. **Pausa y Reanudación**  
   - `pauseStream` / `resumeStream` permiten suspender o reactivar la acumulación de fondos, útil para ajustes temporales en la nómina.

---

## **Pasos de Despliegue**

1. **Desplegar RoleManager**  
2. **Desplegar CompanyRegistry** con la dirección del `RoleManager` y el `feeCollector` para recibir las tarifas.  
3. **Desplegar Treasury** con la dirección del `RoleManager`.  
4. **Desplegar PaymentStreaming** con la dirección de `RoleManager`, `CompanyRegistry` y `Treasury`.  
5. **Autorizar** en `Treasury` al contrato `PaymentStreaming` para que pueda retirar fondos:  
   ```solidity
   treasury.setAuthorizedContract(paymentStreamingAddress, true);


---

## Consideraciones de Seguridad

- **Roles y Access Control**:  
  Cada contrato verifica mediante roles o dueño nominal. En un entorno complejo, revisa o personaliza la lógica de acceso para cada compañía/proyecto.

- **Pruebas y Auditoría**:  
  Siempre es recomendable realizar pruebas extensivas (unitarias e integradas) y, de ser posible, una auditoría externa antes de emplear estos contratos en entornos con activos reales.

- **CLógica de Streams**:  
  Para evitar inconsistencias, revisa los rangos de tiempo (startTime, endTime) y el manejo de indemnizaciones.

- **Limitaciones**:  
 Contratos no son “upgradeables” por defecto. Para cambios futuros, se requeriría un redeployment.

---

## Licencia

Este proyecto está disponible bajo la licencia Propietario Único. If you know, you know.

---

¡Gracias por usar **Dripio**! Si tienes dudas o deseas contribuir, no dudes en abrir un _issue_ o un _pull request_ en este repositorio.  
