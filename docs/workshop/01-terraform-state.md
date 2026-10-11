# Lección 1 — Terraform state: qué problema resuelve y cómo puede fallar

**Meta:** dominar el estado de Terraform antes de tocar EKS. Base del taller: [plan de bootstrap](../superpowers/plans/2026-08-25-terraform-state-bootstrap.md), [PR #3](https://github.com/Wlanez/agentops-eks/pull/3) y [evidencia en la rama](https://github.com/Wlanez/agentops-eks/blob/feat/terraform-state-bootstrap/docs/evidence/v0.1/terraform-state-bootstrap.md).

## 1. El problema sin Terraform

Si creas una VPC manualmente, AWS conoce sus recursos, pero un archivo de configuración en tu laptop no sabe qué creó o qué debe reemplazar. Para automatizar cambios necesitamos relacionar lo **declarado en código** con lo **gestionado en AWS**.

Terraform usa:
- **Configuration:** descripción del estado deseado.
- **State:** vínculo entre direcciones lógicas y objetos remotos conocidos, más atributos/metadata de gestión.
- **Refresh/plan:** consulta de la infraestructura observada y cálculo de diferencias, bajo reglas del provider.
- **Apply:** mutaciones siguiendo un plan aprobado y actualización del state.

El state **no es un inventario completo de AWS** ni un archivo prescindible. Puede contener información sensible.

~~~mermaid
flowchart LR
  CONFIG[Configuración] --> PLAN[Terraform plan]
  STATE[State previo] --> PLAN
  AWS[AWS remoto] --> PLAN
  PLAN --> REVIEW[Revisión de riesgos]
  REVIEW --> APPLY[Apply aprobado]
  APPLY --> AWS
  APPLY --> STATE
~~~

## 2. ¿Por qué S3 remoto y locking?

State local sirve para ensayar, pero dificulta colaborar y recuperarse de un equipo perdido. El S3 backend permite mantener el state centralizado. El lock evita que dos ejecuciones compatibles modifiquen a la vez el mismo state; **no** es una transacción universal de todos los servicios AWS.

En este laboratorio se optó por:
- Bucket S3 del laboratorio, con versioning, cifrado, bloqueo de acceso público y transporte TLS.
- Estado separado para `bootstrap` y `dev`.
- Bloqueo nativo S3 `use_lockfile = true`; no DynamoDB.
- Protección adicional frente a eliminación accidental.
- Credenciales temporales IAM Identity Center, nunca claves AWS permanentes.

**Decisión de diseño:** separar el bucket/state bootstrap de los recursos de `dev` evita que un teardown normal destruya el backend que necesita para ejecutarse.

## 3. Ejercicio de razonamiento

**Caso A:** un compañero pierde su laptop. ¿Se pierde la definición del cluster? Respuesta: el código sigue en Git y el state remoto puede recuperarse bajo acceso autorizado; hay que validar que no existan archivos locales sin guardar o secretos fuera del flujo.

**Caso B:** dos pipelines ejecutan apply al mismo tiempo. ¿Qué protege el lock? Respuesta: serializa escrituras al mismo state cuando ambas ejecuciones respetan el backend/lock. No sustituye aprobación y control de cambios.

**Caso C:** alguien cambia una regla de seguridad desde la consola. ¿Qué ocurre? Respuesta: potencial *drift*. Un `plan` con acceso real y refresh puede mostrar el cambio y su reconciliación prevista. No aplicar ciegamente: entender si el cambio fue una emergencia válida.

## 4. Práctica segura sobre la rama del PR

Trabajar sobre `feat/terraform-state-bootstrap` solo si ya está revisada/localmente disponible. Antes de ejecutar comandos, comprobar la sesión SSO y el perfil AWS esperado según el preflight de la rama. Los siguientes comandos no necesitan ejecutar cambios reales:

~~~bash
terraform -chdir=terraform/bootstrap fmt -check
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/environments/dev fmt -check
terraform -chdir=terraform/environments/dev validate
~~~

`validate` puede requerir haber corrido `init` con un backend correctamente configurado y credenciales adecuadas; si falla por ese motivo, **no** improvisar ni publicar parámetros sensibles para arreglarlo. Seguir el README del workspace y el preflight.

### RED → GREEN (sin tocar AWS)

1. Lee una aserción de `terraform/bootstrap/tests/bootstrap.tftest.hcl`.
2. Predice cuál debería fallar si cambias una propiedad segura en una copia descartable.
3. Haz el cambio solo en el test/fixture local, observa el error y revierte.
4. Ejecuta las pruebas documentadas del backend; registra únicamente PASS/FAIL y la causa.
5. Explica por qué una validación con mock no prueba la configuración real del bucket.

## 5. Entrevista: explica en inglés sencillo

> We use remote Terraform state because infrastructure changes must be reproducible and controlled. S3 stores the state, versioning helps recovery, and locking reduces concurrent modification risk. Before applying changes, I review the plan, identity, and blast radius.

**Pregunta de nivel Senior:** ¿Por qué un plan exitoso no implica que apply será seguro? Porque permisos, estado remoto, reemplazos, costos y cambios concurrentes pueden introducir riesgos. El plan debe ser interpretado con su contexto operativo.

## 6. Conexión con agentes de IA

Un agente puede proponer HCL, pero **no** debe aprobar su propio plan ni asumir un rol administrador. La ejecución debe pasar por revisión humana y reglas deterministas que impidan recursos inesperados, exposición pública y costos no previstos. Terraform state es la analogía de una memoria operativa verificable, no memoria semántica del LLM.

## Terminado cuando

- Puedes explicar qué sucede si borras state, cambias un recurso fuera de Terraform o se superponen dos apply.
- Sabes distinguir validación local, plan, apply y readback.
- Puedes describir por qué el backend no se destruye con `dev`.
- Registraste al menos un test RED/GREEN **sin tocar AWS**.
