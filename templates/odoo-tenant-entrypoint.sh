#!/bin/bash
# ==============================================================================
# Script de Entrada Productivo para Contenedores Odoo 18 en AWS Fargate
# Lee variables de entorno inyectadas dinámicamente por AWS Secrets Manager
# ==============================================================================

set -eo pipefail

echo "=========================================================="
echo "Iniciando Contenedor SaaS Odoo 18 en AWS Fargate"
echo "Tenant ID: ${TENANT_ID:-default}"
echo "Database:  ${POSTGRES_DB}"
echo "DB Host:   ${POSTGRES_HOST}"
echo "=========================================================="

# 1. Validación de variables mandatorias
if [ -z "${POSTGRES_HOST}" ] || [ -z "${POSTGRES_DB}" ] || [ -z "${POSTGRES_USER}" ]; then
  echo "ERROR: Faltan variables obligatorias de conexión a PostgreSQL."
  exit 1
fi

# 2. Esperar a que la base de datos PostgreSQL Multi-AZ esté lista
echo "Verificando disponibilidad de Amazon RDS PostgreSQL..."
until pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; do
  echo "PostgreSQL no responde en ${POSTGRES_HOST}:${POSTGRES_PORT:-5432}. Reintentando en 3 segundos..."
  sleep 3
done
echo "Conexión a Amazon RDS PostgreSQL verificada con éxito."

# 3. Generación dinámica de odoo.conf en memoria (/tmp) para evitar persistir secretos en disco
ODOO_CONFIG_PATH="/tmp/odoo.conf"

cat <<EOF > "${ODOO_CONFIG_PATH}"
[options]
db_host = ${POSTGRES_HOST}
db_port = ${POSTGRES_PORT:-5432}
db_user = ${POSTGRES_USER}
db_password = ${POSTGRES_PASSWORD}
db_name = ${POSTGRES_DB}
dbfilter = ^${POSTGRES_DB}$
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
admin_passwd = ${ADMIN_PASSWORD:-saas_master_secret}
proxy_mode = True
workers = ${ODOO_WORKERS:-2}
limit_memory_hard = ${LIMIT_MEMORY_HARD:-2147483648}
limit_memory_soft = ${LIMIT_MEMORY_SOFT:-1610612736}
limit_request = 8192
limit_time_cpu = 120
limit_time_real = 240
max_cron_threads = 1
log_level = ${LOG_LEVEL:-info}
without_demo = True
data_dir = /var/lib/odoo
EOF

echo "Archivo de configuración generado dinámicamente en ${ODOO_CONFIG_PATH}."

# 4. Inicialización o migración de base de datos si es requerido
if [ "${INITIALIZE_DATABASE}" = "true" ]; then
  echo "Inicializando base de datos ${POSTGRES_DB} con módulos base y corporativos..."
  odoo -c "${ODOO_CONFIG_PATH}" -i base,auth_oauth_force_https,contacts_company_profile,contacts_person_profile,social_network_base --stop-after-init
  echo "Inicialización completada."
fi

# 5. Ejecutar Odoo ERP
echo "Lanzando proceso principal de Odoo 18..."
exec odoo -c "${ODOO_CONFIG_PATH}" "$@"
