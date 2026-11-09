# Guía Maestra de Sustentación Oral y Defensa Técnica
## Reto de Arquitectura Cloud: Plataforma SaaS de Odoo sobre AWS (Zero-EC2)

---

## 1. Reparto Estratégico de Roles (Equipo de 2 Personas)

Para demostrar dominio coordinado ante el comité evaluador, se sugiere dividir la exposición en dos frentes complementarios:

| Rol | Integrante | Áreas de Enfoque y Responsabilidad |
|---|---|---|
| **Arquitecto de Soluciones & Seguridad (Persona 1)** | Integrante A | • Visión de negocio SaaS y modelo Multi-Tenant (Híbrido).<br>• Edge Security: Route 53, CloudFront, AWS WAF, ACM.<br>• SaaS Control Plane: API Gateway, Step Functions, DynamoDB.<br>• Seguridad, Cifrado KMS, Secrets Manager y cumplimiento. |
| **Arquitecto de Infraestructura & SRE (Persona 2)** | Integrante B | • Cómputo Serverless: Amazon ECS con AWS Fargate (Zero-EC2).<br>• Capa de Persistencia: Amazon RDS PostgreSQL Multi-AZ y Amazon EFS.<br>• Resiliencia ante desastres, Failover Multi-AZ, RTO/RPO.<br>• Escalabilidad horizontal/vertical, observabilidad y optimización de costos. |

---

## 2. Discurso de Apertura: Elevator Pitch (2 Minutos)

> *"Estimado comité evaluador: Nuestra propuesta no es simplemente instalar Odoo en la nube; es el diseño de una **fábrica digital SaaS automatizada, elástica y de nivel empresarial sobre AWS**, respetando en un 100% la directriz mandatoria: **cero instancias Amazon EC2**.*
>
> *Para resolver el reto de aislar clientes sin disparar los costos, elegimos un **Modelo Híbrido Silo-Pool**: cada cliente tiene tareas dedicadas de cómputo en **AWS Fargate** (eliminando de raíz el problema del vecino ruidoso y los bloqueos de workers de Python) y un punto de acceso exclusivo en **Amazon EFS** para su filestore; mientras que en la capa de datos, comparten un clúster de alta disponibilidad de **Amazon RDS PostgreSQL Multi-AZ**, pero con una base de datos lógica y usuario completamente independientes por cliente.*
>
> *Y lo más potente: gracias a nuestro **SaaS Control Plane serverless** orquestado con **AWS Step Functions**, cuando una empresa contrata el servicio, la plataforma aprovisiona su base de datos, credenciales, almacenamiento, contenedores, balanceo y certificados HTTPS en **menos de 3 minutos, de forma 100% automatizada y con capacidad de rollback automático (patrón Saga) si algo falla**.*
>
> *A continuación, demostraremos cómo nuestra arquitectura responde técnica y económicamente a cada uno de los escenarios de negocio."*

---

## 3. Respuestas Contundentes a los 6 Casos del Reto

---

### Caso 1: Nuevo cliente solicita una implementación de Odoo. ¿Qué sucede desde que realiza la solicitud hasta que puede ingresar a su plataforma?

**Respuesta Técnica (Persona 1):**
> 1. El cliente llena el formulario en el portal web (ej. solicita `acme.saasodoo.com`). Se envía un `POST /api/v1/tenants` a **Amazon API Gateway**.
> 2. API Gateway valida la autenticación e inicia una máquina de estados en **AWS Step Functions**.
> 3. Step Functions ejecuta en secuencia mediante funciones **AWS Lambda**:
>    - **Generación de Secretos:** Crea contraseñas criptográficas de 32 caracteres en **AWS Secrets Manager** (cifradas con AWS KMS).
>    - **Aprovisionamiento de Base de Datos:** En el clúster **Amazon RDS PostgreSQL Multi-AZ**, crea la base `db_tenant_acme` y el usuario `usr_tenant_acme` con permisos restringidos exclusivamente a su esquema.
>    - **Aprovisionamiento de Filestore:** En **Amazon EFS**, crea un **Access Point** específico para `/tenants/acme/filestore`, forzando POSIX UID 101 y GID 101.
>    - **Despliegue de Cómputo (Fargate):** Registra una Task Definition en **Amazon ECS** con la imagen productiva de Odoo 18 (que incluye los addons corporativos) y crea el servicio ECS con mínimo 2 réplicas (una en AZ-A y otra en AZ-B).
>    - **Enrutamiento y SSL:** Crea un Target Group en el **Application Load Balancer (ALB)** y agrega una regla basada en Host (`acme.saasodoo.com`). El certificado comodín `*.saasodoo.com` en **ACM** cubre el subdominio de inmediato sin esperas de emisión.
> 4. El ALB valida el health check en `/web/health` con código `200 OK`.
> 5. Step Functions marca el estado como `ACTIVE` en **Amazon DynamoDB** y despacha un email mediante **Amazon SES** con las credenciales temporales.
> **Tiempo total transcurrido:** Menos de 3 minutos. Cero intervención de operadores.

---

### Caso 2: Un cliente pasa de 10 a 100 usuarios concurrentes. ¿Cómo se adapta la infraestructura?

**Respuesta Técnica (Persona 2):**
> 1. **Detección Automática:** El aumento de tráfico incrementa el consumo de CPU, memoria y el número de conexiones por tarea en el Application Load Balancer.
> 2. **Auto Scaling Horizontal en Fargate:** Las políticas de *Target Tracking* de **Application Auto Scaling** disparan el aprovisionamiento de nuevas tareas de Fargate en paralelo cuando la CPU promedio supera el 65% o las peticiones activas por target superan las 50. El servicio escala automáticamente de 2 a 4, 6 u 8 tareas en ambas zonas de disponibilidad en menos de 90 segundos.
> 3. **Aislamiento Noisy Neighbor:** Como las tareas de Fargate de este cliente son independientes de las tareas de los demás, **su crecimiento no consume un solo megabyte de RAM ni ciclo de reloj de otros clientes**.
> 4. **Escalabilidad en Base de Datos:**
>    - **RDS Storage Auto-scaling** expande el disco automáticamente sin downtime si las transacciones consumen almacenamiento.
>    - Si el cliente requiere más potencia, se escala verticalmente la instancia RDS mediante un failover controlado de 60 segundos, o se aprovisiona una **Read Replica** para separar consultas analíticas de reportes pesados.

---

### Caso 3: Se presenta una falla en una zona de disponibilidad. ¿Cómo responde la arquitectura?

**Respuesta Técnica (Persona 2):**
> 1. Supongamos que ocurre una catástrofe y la Zona de Disponibilidad A (AZ-A) se desconecta por completo.
> 2. **Capa Web (ALB + Route 53):** El balanceador y Route 53 detectan que los nodos en AZ-A no responden y dirigen el 100% del tráfico entrante a los nodos de AZ-B.
> 3. **Capa de Cómputo (ECS Fargate):** Las tareas que corrían en AZ-A se pierden, pero el servicio de ECS Fargate detecta que el número de tareas activas es inferior al deseado y **crea de inmediato tareas de reemplazo en AZ-B** (y AZ-C).
> 4. **Capa de Filestore (Amazon EFS):** Como EFS es un servicio regional Multi-AZ nativo, los archivos están replicados sincrónicamente en AZ-B. El montaje NFS continúa sin interrupción.
> 5. **Capa de Base de Datos (RDS PostgreSQL Multi-AZ):**
>    - Si la instancia Primary estaba en AZ-A, el monitor de RDS detecta la pérdida de latido (*heartbeat*).
>    - Ejecuta un **failover automático síncrono**: la instancia Standby en AZ-B asume como Primary en **menos de 60 a 120 segundos**.
>    - El endpoint CNAME de RDS se actualiza a la nueva IP y los pools de conexión de Odoo se restablecen automáticamente.
> 6. **Métricas de Resiliencia:** **RTO < 2 minutos. RPO = 0 (cero pérdida de datos de transacciones confirmadas).**

---

### Caso 4: Un cliente presenta un incremento considerable en el almacenamiento de documentos. ¿Cómo se gestiona?

**Respuesta Técnica (Persona 2):**
> 1. **Elasticidad Automática en Filestore:** **Amazon EFS** es un sistema de archivos serverless elástico. No requiere preaprovisionar gigabytes; crece en caliente a medida que el cliente sube facturas electrónicas, imágenes o adjuntos, soportando petabytes de forma transparente.
> 2. **Optimización Financiera Automática:** Para que el costo no se vuelva insostenible, aplicamos **EFS Lifecycle Management**: cualquier archivo que no haya sido consultado durante 30 días se transfiere automáticamente al nivel de almacenamiento **EFS Infrequent Access (IA)**.
> 3. **Ahorro:** Esto reduce el costo de almacenamiento en un **92%** ($0.016 por GB-mes frente a $0.30 por GB-mes en estándar), sin que el usuario de Odoo note ningún cambio al abrir un documento antiguo.
> 4. **En Base de Datos:** **RDS Storage Auto-scaling** añade almacenamiento en bloques SSD GP3 de manera dinámica sin interrupción del motor PostgreSQL.

---

### Caso 5: La empresa pasa de administrar 5 a 100 clientes. ¿Qué cambios requiere la operación?

**Respuesta Técnica (Persona 1):**
> 1. **Cero Rediseño:** La arquitectura es intrínsecamente modular. Pasar de 5 a 100 clientes consiste simplemente en ejecutar 95 veces la máquina de estados de Step Functions.
> 2. **Cero Mantenimiento de Servidores (No Ops Overload):** Al no haber instancias EC2, el equipo de operaciones no tiene que parchar 100 sistemas operativos Linux ni gestionar actualizaciones de kernel. AWS se encarga de la infraestructura física subyacente.
> 3. **Evolución de Base de Datos por Agrupación (Pool Sharding):**
>    - Para 5 clientes, un clúster compartido `db.m6g.large` es suficiente.
>    - Para 100 clientes, se segmenta en clústeres RDS por grupos (ej. 1 instancia RDS Multi-AZ por cada 25-30 clientes pequeños), o se migran los 5 clientes más grandes a instancias RDS dedicadas.
> 4. **Enrutamiento Escalable:** Se pueden agrupar reglas en múltiples Application Load Balancers divididos por Tier (ej. ALB-Starter y ALB-Enterprise) o gestionar el enrutamiento con CloudFront y Lambda@Edge.
> 5. **Gobierno y Costos:** Cada recurso cuenta con la etiqueta `TenantId`, lo que permite visualizar en **AWS Cost Explorer** el costo unitario exacto y la rentabilidad por cliente.

---

### Caso 6: Se presenta una falla en la base de datos de uno de los clientes. ¿Qué sucede con los demás clientes y cómo se recupera el servicio?

**Respuesta Técnica (Persona 1 & 2):**
> 1. **Aislamiento Total del Fallo:**
>    - Si el fallo es **lógico** (ej. un administrador del cliente ejecutó un script erróneo o se corrompió una tabla en `db_tenant_acme`), **los demás clientes no sufren ninguna afectación**. Sus bases de datos lógicas (`db_tenant_globex`, etc.) son completamente ajenas.
>    - Si el cliente ejecutó una consulta pesada sin límite, el parámetro de PostgreSQL `statement_timeout = 60s` cancela la consulta antes de que agote la CPU compartida.
> 2. **Recuperación Rápida mediante PITR:**
>    - Se utiliza la funcionalidad **Point-In-Time-Recovery (PITR)** de Amazon RDS, la cual mantiene los logs WAL continuamente en Amazon S3.
>    - Se restaura una instancia temporal al minuto exacto previo al fallo (ej. 10:14:00 AM).
>    - Se extrae únicamente la base de datos afectada (`db_tenant_acme`) mediante `pg_dump` y se restaura en el clúster productivo con `pg_restore`.
>    - Se reinician las tareas de ECS Fargate de ese tenant para refrescar conexiones.
> 3. **Alternativa con AWS Backup:** Si el daño requiere restauración completa, se recupera el último snapshot consistente tomado por AWS Backup.

---

## 4. Preguntas "Trampa" de los Evaluadores y Cómo Responderlas

### Pregunta Trampa 1: *"¿Por qué no utilizaron Amazon EKS con Fargate en lugar de Amazon ECS con Fargate?"*
**Respuesta Ganadora:**
> *"Evaluamos EKS con Fargate, pero para una plataforma SaaS de Odoo, **Amazon ECS es superior en simplicidad, costo y velocidad de aprovisionamiento**:
> 1. **Costo Base:** EKS tiene un costo fijo de control plane de $73 USD/mes por clúster antes de ejecutar un solo pod; ECS tiene costo fijo de control plane de **$0 USD**.
> 2. **Velocidad de Arranque:** Las tareas de Fargate en ECS se aprovisionan significativamente más rápido que pods de Kubernetes sobre Fargate, vital para cumplir con el SLA de onboarding en < 3 minutos.
> 3. **Integración Nativa:** ECS se integra directamente en la Task Definition con AWS Secrets Manager y EFS Access Points sin requerir controladores adicionales como CSI drivers, operadores externos o CRDs que añaden puntos de fallo innecesarios."*

### Pregunta Trampa 2: *"¿Por qué usar Amazon EFS para el filestore en lugar de guardar los archivos en Amazon S3, que es más barato?"*
**Respuesta Ganadora:**
> *"Odoo fue diseñado desde sus raíces para operar sobre un sistema de archivos local POSIX (`/var/lib/odoo/filestore/<dbname>`). Aunque existen módulos comunitarios para S3, introducen latencia de red en cada generación de reportes masivos y son vulnerables a desincronizaciones en migraciones de versión.
> **Amazon EFS se monta nativamente en Fargate como un directorio POSIX**, garantizando compatibilidad 100% transparente y sin tocar el core de Odoo.
> Y para neutralizar el costo de EFS frente a S3, implementamos **EFS Lifecycle Management**: los archivos con más de 30 días se mueven a **EFS Infrequent Access (IA)**, donde el costo cae a **$0.016/GB-mes**, prácticamente igual al precio de S3 ($0.023/GB-mes)."*

### Pregunta Trampa 3: *"¿Qué sucede con las sesiones web de los usuarios si una tarea de Fargate muere?"*
**Respuesta Ganadora:**
> *"Implementamos dos mecanismos:
> 1. En el **Application Load Balancer**, habilitamos **Sticky Sessions (afinidad de sesión por cookie)** de 24 horas, garantizando que el usuario se mantenga en la misma tarea sana.
> 2. El directorio de sesiones de Odoo se monta sobre el **Amazon EFS Access Point** del cliente. Si una tarea Fargate es terminada, la nueva tarea de reemplazo lee la sesión activa persistida en EFS, por lo que el usuario no es expulsado ni pierde su trabajo en curso."*

### Pregunta Trampa 4: *"Si el clúster de RDS PostgreSQL es compartido en el Tier Estándar, ¿cómo evitan que un atacante en un tenant lea datos de otro?"*
**Respuesta Ganadora:**
> *"El aislamiento no se hace a nivel de tablas compartidas, sino a nivel de **bases de datos lógicas independientes y usuarios PostgreSQL exclusivos**.
> El usuario `usr_acme` solo tiene privilegios sobre `db_tenant_acme`. En PostgreSQL, un usuario no puede conectarse ni ejecutar consultas sobre otra base de datos del mismo motor a menos que se le otorguen privilegios explícitos (`REVOKE ALL ON DATABASE db_tenant_globex FROM usr_acme;`).
> Además, los contenedores Fargate de cada cliente se configuran con credenciales independientes inyectadas desde Secrets Manager en memoria."*

### Pregunta Trampa 5: *"¿Cómo aseguran que un contenedor de un cliente no acceda al filestore de otro cliente en el mismo EFS?"*
**Respuesta Ganadora:**
> *"Mediante **EFS Access Points**. Un Access Point actúa como una vista de seguridad delegada:
> 1. Fuerza el directorio raíz a `/tenants/{tenant_id}/filestore`. El contenedor no tiene visibilidad de la raíz del sistema de archivos NFS.
> 2. Impone una identidad POSIX obligatoria (UID 101, GID 101).
> Incluso si un proceso dentro del contenedor intentara hacer un directory traversal con `cd ../..`, el protocolo NFS y las políticas de IAM del Access Point en AWS rechazan la solicitud a nivel de red."*
